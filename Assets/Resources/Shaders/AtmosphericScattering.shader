Shader "Hidden/Atmospheric Scattering"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
        }

        Pass
        {
            Cull Off ZTest Off ZWrite Off Blend Off

            CGPROGRAM
            #pragma vertex vertex
            #pragma fragment fragment

            #include "UnityCG.cginc"
            #include "AtmosphericScattering.hlsl"

            struct Input
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vertex(in Input input)
            {
                Varyings output;

                output.vertex = UnityObjectToClipPos(input.vertex);
                output.uv = input.uv;

                return output;
            }

            float4 fragment(in Varyings input) : SV_Target
            {
                float x = 2. * input.uv.x - 1.;

                Ray ray;
                ray.origin = float3(0., lerp(0., _KarmanLine, input.uv.y), 0.);
                ray.direction = float3(sqrt(saturate(1. - x * x)), x, 0.);

                return float4(GetParticleDensity(ray), 0., 0.);
            }
            ENDCG
        }

        Pass
        {
            Cull Off ZTest Off ZWrite Off Blend Off

            CGPROGRAM
            #pragma vertex vertex
            #pragma fragment fragment

            #include "UnityCG.cginc"
            #include "AtmosphericScattering.hlsl"

            struct Input
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vertex(in Input input)
            {
                Varyings output;

                output.vertex = UnityObjectToClipPos(input.vertex);
                output.uv = input.uv;

                return output;
            }

            float4 fragment(in Varyings input) : SV_Target
            {
                float x = 2. * input.uv.x - .5;
                float3 direction = float3(sqrt(saturate(1. - x * x)), x, 0.);

                return GetAmbientLight(-normalize(direction));
            }
            ENDCG
        }

        Pass
        {
            Cull Off ZTest Off ZWrite Off Blend Off

            CGPROGRAM
            #pragma vertex vertex
            #pragma fragment fragment

            #include "UnityCG.cginc"
            #include "AtmosphericScattering.hlsl"

            struct Input
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vertex(in Input input)
            {
                Varyings output;

                output.vertex = UnityObjectToClipPos(input.vertex);
                output.uv = input.uv;

                return output;
            }

            float4 fragment(in Varyings input) : SV_Target
            {
                float x = 2. * input.uv.x - .5;
                float3 direction = float3(sqrt(saturate(1. - x * x)), x, 0.);

                return GetDirectionalLight(normalize(direction));
            }
            ENDCG
        }

        Pass
        {
            Cull Off ZWrite Off ZTest Always Blend One Zero

            CGPROGRAM
            #pragma vertex vertex
            #pragma fragment fragment

            #include "UnityCG.cginc"
            #include "UnityDeferredLibrary.cginc"

            #include "AtmosphericScattering.hlsl"

            sampler2D _MainTex;

            sampler3D _Inscattering;
            sampler3D _Extinction;

            struct Input
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;

                uint id : SV_VertexID;
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;

                float3 frustum : TEXCOORD1;
            };

            Varyings vertex(in Input input)
            {
                Varyings output;

                output.vertex = UnityObjectToClipPos(input.vertex);
                output.uv = input.uv;

                output.frustum = _Frustum[input.id];
                return output;
            }

            float4 fragment(in Varyings input) : SV_Target
            {
                float depth = tex2D(_CameraDepthTexture, input.uv).r;
                depth = Linear01Depth(depth);

                Ray ray;
                ray.origin = _WorldSpaceCameraPos;
                ray.direction = (input.frustum - _WorldSpaceCameraPos) * depth;

                float range = length(ray.direction);
                ray.direction /= range;

                if (depth >= .999999)
                    return tex2D(_MainTex, input.uv);

                Sphere surface;
                surface.position = _Planet.xyz;
                surface.radius = _Planet.w;

                Sphere turbopause;
                turbopause.position = _Planet.xyz;
                turbopause.radius = _Planet.w + _KarmanLine;

                Trace trace = TraceSphere(ray, turbopause);
                range = min(range, trace.slice.y);

                trace = TraceSphere(ray, surface);

                if (trace.slice.x > 0.)
                    range = min(range, trace.slice.x);

                float3 uvw = float3(input.uv, depth);

                float3 inscattering = tex3D(_Inscattering, uvw).rgb;
                float3 extinction = tex3D(_Extinction, uvw).rgb;

                float4 color = tex2D(_MainTex, input.uv);
                color.rgb = color.rgb * extinction + inscattering;

                return color;
            }
            ENDCG
        }
    }
}
