Shader "Skybox/Atmospheric Scattering"
{
    SubShader
    {
        Tags
        {
            "Queue" = "Background"
            "RenderType" = "Background"

            "PreviewType" = "Skybox"
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vertex
            #pragma fragment fragment

            #include "Skybox.cginc"
            ENDCG
        }
    }
}
