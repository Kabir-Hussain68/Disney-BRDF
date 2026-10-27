Shader "Custom/Disney-PBR"
{
    Properties
    {
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("MainTex", 2D) = "" {}
        _NormalMap ("NormalMap", 2D) = "" {}
        _TangentMap ("TangentMap", 2D) = "" {}
        _NormalStrength ("NormalStrength", Range(0, 1)) = 0.5
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Subsurface ("Subsurface", Range(0, 1)) = 0
        _Specular ("Specular", Range(0, 2)) = 0.5
        _Roughness ("Roughness", Range(0 , 1)) = 0.5
        _SpecularTint ("Specular Tint", Range(0, 1)) = 0
        _Anisotropic ("Anisotropic", Range(0, 1)) = 0
        _Sheen ("Sheen", Range(0, 1)) = 0
        _SheenTint ("Sheen Tint", Range(0, 1)) = 0.5
        _Clearcoat ("Clearcoat", Range(0, 1)) = 0
        _ClearcoatGloss ("ClearcoatGloss", Range(0, 1)) = 1
    }

    SubShader
    {

        CGINCLUDE

        #include "UnityCG.cginc"
        #include "UnityPBSLighting.cginc"
        #include "AutoLight.cginc"
        
        float4 _Tint;
        sampler2D _MainTex;
        sampler2D _NormalMap;
        sampler2D _TangentMap;
        float _NormalStrength;
        float _Metallic;
        float _Subsurface;
        float _Specular;
        float _Roughness;
        float _SpecularTint;
        float _Anisotropic;
        float _Sheen;
        float _SheenTint;
        float _Clearcoat;
        float _ClearcoatGloss;

        #define PI 3.1415926f
        
        struct vertexData
        {
            float4 vertex : POSITION;
            float3 normal : NORMAL;
            float4 tangent : TANGENT;
            float2 uv : TEXCOORD0;
        };

        struct vert2frag
        {
            float4 pos : SV_POSITION;
            float3 normal : TEXCOORD0;
            float4 tangent : TEXCOORD1;
            float2 uv : TEXCOORD2;
            float3 worldPos : TEXCOORD3;
            SHADOW_COORDS(4)
        };

        struct BRDFResults
        {
            float3 diffuse;
            float3 specular;
            float3 clearcoat;
        };

        float sqr(float x)
        {
            return x * x;
        }

        //Equal to F(u) = (1 -u)^5, used in the Fresnel equation
        float SchlickFresnel(float u)
        {
            float x = saturate(1 - u);
            float x2 = x * x;
            return x2 * x2 * x; //Equalus to m^5, doing this because calculations more simple
        }

        //Generalized Trowbridge Reitz Gamma = 1, not the common GGX Distribution
        //Equal to D(h) = a2 - 1 / PI * ln(a2) * [1 + (a2 - 1) * (n.h)^2]
        float GTR1(float NdotH, float a)
        {
            float a2 = a * a;
            float t = 1 + (a2 - 1) * NdotH * NdotH; 
            return (a2 - 1) / (PI * log(a2) * t);
        }

        //Generalized Trowbridge Reitz Gamma = 2, the common GGX distribution
        //Equal to GGX = 1 / PI * ax * ay * [(hx / ax)^2 + (hy / ay)^2 + (n.h)^2]^2
        //hx = h.x     hy = h.y
       float anisotropicGTR2(float NdotH, float HdotX, float HdotY, float ax, float ay)
       {
            return rcp(PI * ax * ay * sqr(sqr(HdotX / ax) + sqr(HdotY / ay) +  sqr(NdotH)));
       }

       //Isotropic Geometrix Attenuation for GGX
       //Equal to smithGGX = 1 / (n.v) * sqrt(a^2 + (1 - a^2) * (n.v)*2)
       float smithGGX(float alphaSquared, float NdotL, float NdotV)
       {
            float a = NdotV * sqrt(alphaSquared + NdotL * (NdotL - alphaSquared * NdotL));
            float b = NdotL * sqrt(alphaSquared + NdotV * (NdotV - alphaSquared * NdotV));
            return 0.5 / (a + b);
       }

       //Anisotropic Geometric Attenuation for GGX
       //Equal to aniGGX = 1 / (n.v) + sqrt(sqr(ax * vx)^2 + (ay * vy)^2 + (n.v)^2)
       float anisotropicSmithGGX(float NdotV, float VdotX, float VdotY, float ax, float ay)
       {
            return rcp(NdotV + sqrt(sqr(VdotX * ax) + sqr(VdotY * ay) + sqr(NdotV)));
       }

       float luminance(float3 color)
       {
        return dot(color, float3(0.299, 0.587, 0.114));
       }

        BRDFResults BRDFFunction(float3 baseColor, float3 L, float3 V, float3 N, float3 X, float3 Y)
        {
            BRDFResults output;
            output.diffuse = float3(0, 0, 0);
            output.specular = float3(0, 0, 0);
            output.clearcoat = float3(0, 0, 0);

            float3 H = normalize(V + L);    

            float NdotL = DotClamped(N, L);
            float NdotV = DotClamped(N, V);
            float NdotH = DotClamped(N, H);
            float LdotH = DotClamped(L, H);

            float3 Cdlin = baseColor;
            float Cdlum = luminance(Cdlin);

            float3 Ctint = Cdlum > 0 ? Cdlin / Cdlum : 1;
            float3 Cspec0 = lerp(_Specular * 0.08 * lerp(1, Ctint, _SpecularTint), Cdlin, _Metallic);
            float3 Csheen = lerp(1, Ctint, _SheenTint);

            //Diffuse Fresnel
            float FL = SchlickFresnel(NdotL);
            float FV = SchlickFresnel(NdotV);

            float Fss90 = LdotH * LdotH * _Roughness;

            float Fd90 = 0.5 + 2 * Fss90;
            float Fd = lerp(1, Fd90, FL) * lerp(1, Fd90, FV);

            //Hanrahan-Krueger BRDF Approximation
            float Fss = lerp(1, Fss90, FL) * lerp(1, Fss90, FV);
            float ss = 1.25 * (Fss * (rcp(NdotL + NdotV) - 0.5) + 0.5);

            float roughnessSqr = _Roughness * _Roughness;
            
            //Anisotropic Microfacent
            float aspect = sqrt(1 - _Anisotropic * 0.9);    
            float ax = max(0.001, roughnessSqr/aspect);
            float ay = max(0.001, roughnessSqr * aspect);
            float Ds = anisotropicGTR2(NdotH, dot(H, X), dot(H, Y), ax, ay);

            //Geometric Attenuation
            float GeoroughnessSqr = sqr(0.5f + _Roughness * 0.5f);
            float Geoax = max(0.001, GeoroughnessSqr/aspect);
            float Geoay = max(0.001, GeoroughnessSqr * aspect);
            float Gs = anisotropicSmithGGX(NdotV, dot(V, X), dot(V, Y), Geoax, Geoay);
            Gs *= anisotropicSmithGGX(NdotL, dot(L,X), dot(L, Y), Geoax, Geoay);

            //Fresnel
            float FH = SchlickFresnel(LdotH);
            float3 Fs = lerp(Cspec0, 1.0, FH);

            //sheen
            float3 Fsheen = FH * _Sheen * Csheen;
            
            //Clearcoat
            float Dr = GTR1(NdotH, lerp(0.1, 0.001, _ClearcoatGloss));
            float Fr = lerp(0.04, 1.0, FH);
            float Gr = smithGGX(NdotL, NdotV, 0.25);

            float3 diffuse = (1.0 / PI) * (lerp(Fd, ss, _Subsurface) * Cdlin + Fsheen) * (1 - _Metallic);
            output.diffuse = diffuse;

            float3 specular = Ds * Fs * Gs;
            output.specular = specular;

            float3 clearcoat = 0.25 * _Clearcoat * Gr * Fr * Dr;
            output.clearcoat = clearcoat;

            return output;
        }

        ENDCG
        
        Pass
        {
            Tags
            {
                "LightMode" = "ForwardBase"
            }
    
            CGPROGRAM
            
            #pragma target 3.0
    
            #pragma vertex VertexProgram
            #pragma fragment FragmentProgram

            #pragma multi_compile _ SHADOWS_SCREEN
    
            vert2frag VertexProgram(vertexData v)
            {
                vert2frag i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                i.normal = UnityObjectToWorldNormal(v.normal);
                i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
                i.uv = v.uv;
                TRANSFER_SHADOW(i);
                return i;
            }
    
            float4 FragmentProgram(vert2frag v) : SV_Target
            {
                // Build worldToTangent matrix
                float3 unnormalizedNormal = v.normal;
                float renormFactor = 1.0 / length(unnormalizedNormal);
                float3 bitangent = cross(unnormalizedNormal, v.tangent.xyz) * v.tangent.w;
                
                float3x3 worldToTangent;
                worldToTangent[0] = v.tangent.xyz * renormFactor;
                worldToTangent[1] = bitangent * renormFactor;
                worldToTangent[2] = unnormalizedNormal * renormFactor;

                // Unpack normal from DXT5nm
                float4 packedNormal = tex2D(_NormalMap, v.uv);
                packedNormal.w *= packedNormal.x;

                float3 N;
                N.xy = packedNormal.wy * 2.0 - 1.0;
                N.xy *= _NormalStrength;
                N.z = sqrt(1.0 - saturate(dot(N.xy, N.xy)));
                N = mul(N, worldToTangent);

                // Unpack tangent from DXT5nm
                float3 T;
                T.xy = tex2D(_TangentMap, v.uv).wy * 2.0 - 1.0;
                T.z = sqrt(1.0 - saturate(dot(T.xy, T.xy)));
                
                T = mul(lerp(float3(1.0, 0.0, 0.0), T, saturate(_NormalStrength)), worldToTangent);

                float3 albedo = tex2D(_MainTex, v.uv).rgb * _Tint.rgb;
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - v.worldPos.xyz);
                float3 X = normalize(T);
                float3 Y = normalize(cross(N, T) * v.tangent.w);

                BRDFResults reflection = BRDFFunction(albedo, L, V, N, X, Y);

                float3 results = _LightColor0 * (reflection.diffuse + reflection.specular + reflection.clearcoat);  
                results *= DotClamped(N, L);     
                results *= SHADOW_ATTENUATION(v);  

                return float4(results, 1);
            }
            
            ENDCG
        }

        Pass
        {
            Tags
            { 
                "LightMode" = "ForwardAdd" 
            }

            Blend One One
            ZWrite Off

            CGPROGRAM

            #pragma target 3.0

            #pragma vertex VertexProgram
            #pragma fragment FragmentProgram

            #pragma multi_compile _ SHADOWS_SCREEN

            vert2frag VertexProgram(vertexData v)
            {
                vert2frag i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                i.normal = UnityObjectToWorldNormal(v.normal);
                i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
                i.uv = v.uv;
                TRANSFER_SHADOW(i);
                return i;
            }

            float4 FragmentProgram(vert2frag v) : SV_Target
            {
                // Build worldToTangent matrix
                float3 unnormalizedNormal = v.normal;
                float renormFactor = 1.0 / length(unnormalizedNormal);
                float3 bitangent = cross(unnormalizedNormal, v.tangent.xyz) * v.tangent.w;
                
                float3x3 worldToTangent;
                worldToTangent[0] = v.tangent.xyz * renormFactor;
                worldToTangent[1] = bitangent * renormFactor;
                worldToTangent[2] = unnormalizedNormal * renormFactor;

                // Unpack normal from DXT5nm
                float4 packedNormal = tex2D(_NormalMap, v.uv);
                packedNormal.w *= packedNormal.x;
                float3 N;
                N.xy = packedNormal.wy * 2.0 - 1.0;
                N.xy *= _NormalStrength;
                N.z = sqrt(1.0 - saturate(dot(N.xy, N.xy)));
                N = mul(N, worldToTangent);

                // Unpack tangent from DXT5nm
                float4 packedTangent = tex2D(_TangentMap, v.uv);
                float3 T;
                T.xy = packedTangent.wy * 2.0 - 1.0;
                T.z = sqrt(1.0 - saturate(dot(T.xy, T.xy)));
                T = mul(lerp(float3(1.0, 0.0, 0.0), T, saturate(_NormalStrength)), worldToTangent);

                float3 albedo = tex2D(_MainTex, v.uv).rgb * _Tint.rgb;
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - v.worldPos.xyz);
                float3 X = normalize(T);
                float3 Y = normalize(cross(N, T) * v.tangent.w);

                BRDFResults reflection = BRDFFunction(albedo, L, V, N, X, Y);

                float3 results = _LightColor0 * (reflection.diffuse + reflection.specular + reflection.clearcoat);  
                results *= DotClamped(N, L); 
                results *= SHADOW_ATTENUATION(v);
                return float4(max(0, results), 1);
            }

            ENDCG
        }

        Pass
        {
            Tags
            { 
                "LightMode" = "ShadowCaster" 
            }

            CGPROGRAM

            #pragma vertex vp
            #pragma fragment fp
            
            #include "UnityCG.cginc"

            struct v 
            { 
                float4 vertex : POSITION; 
                float3 normal : NORMAL; 
            };

            struct f 
            {
                float4 pos : SV_POSITION; 
            };

            f vp(v i) 
            {
                f o;
                o.pos = UnityClipSpaceShadowCasterPos(i.vertex.xyz, i.normal);
                o.pos = UnityApplyLinearShadowBias(o.pos);
                return o;
            }

            float4 fp(f i) : SV_Target 
            { 
                return 0; 
            }
            ENDCG
        }
    }
}
