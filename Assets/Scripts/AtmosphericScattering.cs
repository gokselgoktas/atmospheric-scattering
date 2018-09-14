using System;

using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode]
[RequireComponent(typeof (Camera))]
public sealed class AtmosphericScattering : MonoBehaviour
{
    [Header("Atmosphere")]

    public Vector2 scale = new Vector2(7994f, 1200f);

    [Range(0f, 10f)]
    public float rayleighScatteringCoefficient = 1f;

    [Range(0f, 10f)]
    public float rayleighExtinctionCoefficient = 1f;

    [Range(0f, 10f)]
    public float mieScatteringCoefficient = 1f;

    [Range(0, 10f)]
    public float mieExtinctionCoefficient = 1f;

    [Range(-1f, 1f)]
    public float g = .76f;

    public bool generateReflectionProbe = false;

    [Header("Environment")]

    public Light sun;

    [ColorUsage(true, true)]
    public Color incomingLightColor = new Color(4f, 4f, 4f, 4f);

    [Range(0f, 16f)]
    public float sunshine = 1f;

    [Range(0f, 10000000f)]
    public float planetRadius = 6378100f;

    [Range(0f, 160000f)]
    public const float karmanLine = 80000f;

    private ComputeShader m_ComputeShader;
    private ComputeShader computeShader
    {
        get
        {
            if (m_ComputeShader == null)
            {
                m_ComputeShader = (ComputeShader)
                    Resources.Load("Shaders/AtmosphericScattering");
            }

            return m_ComputeShader;
        }
    }
    private Shader m_Shader;
    public Shader shader
    {
        get
        {
            if (m_Shader == null)
                m_Shader = Shader.Find("Hidden/Atmospheric Scattering");

            return m_Shader;
        }
    }

    private Material m_Material;
    private Material material
    {
        get
        {
            if (m_Material == null)
            {
                if (shader == null || shader.isSupported == false)
                    return null;

                m_Material = new Material(shader);
            }

            return m_Material;
        }
    }

    private Camera m_Camera;
    private new Camera camera
    {
        get
        {
            if (m_Camera == null)
                m_Camera = GetComponent<Camera>();

            return m_Camera;
        }
    }

    private Texture2D m_RandomVectors = null;
    private Texture2D randomVectors
    {
        get
        {
            if (m_RandomVectors == null)
            {
                m_RandomVectors = (Texture2D)
                    Resources.Load("Textures/RandomVectors");
            }

            return m_RandomVectors;
        }
    }

    private RenderTexture m_ParticleDensity;
    private RenderTexture particleDensity
    {
        get
        {
            if (m_ParticleDensity == null)
            {
                m_ParticleDensity = new RenderTexture(1024, 1024, 0,
                    RenderTextureFormat.RGFloat, RenderTextureReadWrite.Linear);

                m_ParticleDensity.filterMode = FilterMode.Bilinear;
                m_ParticleDensity.hideFlags = HideFlags.HideAndDontSave;

                m_ParticleDensity.Create();
            }

            return m_ParticleDensity;
        }
    }

    private RenderTexture m_Skybox;
    private RenderTexture skybox
    {
        get
        {
            if (m_Skybox == null)
            {
                m_Skybox = new RenderTexture(32, 128, 0,
                    RenderTextureFormat.ARGBHalf,
                    RenderTextureReadWrite.Linear);

                m_Skybox.dimension = TextureDimension.Tex3D;
                m_Skybox.volumeDepth = 32;

                m_Skybox.enableRandomWrite = true;

                m_Skybox.hideFlags = HideFlags.HideAndDontSave;
                m_Skybox.Create();
            }

            return m_Skybox;
        }
    }

    private RenderTexture m_Inscattering;
    private RenderTexture inscattering
    {
        get
        {
            if (m_Inscattering == null)
            {
                m_Inscattering = new RenderTexture(8, 8, 0,
                    RenderTextureFormat.ARGBHalf,
                    RenderTextureReadWrite.Linear);

                m_Inscattering.dimension = TextureDimension.Tex3D;
                m_Inscattering.volumeDepth = 64;

                m_Inscattering.enableRandomWrite = true;

                m_Inscattering.hideFlags = HideFlags.HideAndDontSave;
                m_Inscattering.Create();
            }

            return m_Inscattering;
        }
    }

    private RenderTexture m_Extinction;
    private RenderTexture extinction
    {
        get
        {
            if (m_Extinction == null)
            {
                m_Extinction = new RenderTexture(8, 8, 0,
                    RenderTextureFormat.ARGBHalf,
                    RenderTextureReadWrite.Linear);

                m_Extinction.dimension = TextureDimension.Tex3D;
                m_Extinction.volumeDepth = 64;

                m_Extinction.enableRandomWrite = true;

                m_Extinction.hideFlags = HideFlags.HideAndDontSave;
                m_Extinction.Create();
            }

            return m_Extinction;
        }
    }

    private Texture2D m_Readback;
    private Texture2D readback
    {
        get
        {
            if (m_Readback == null)
            {
                m_Readback = new Texture2D(128, 1, TextureFormat.RGBAHalf,
                    false, true);

                m_Readback.Apply();
            }

            return m_Readback;
        }
    }

    private ReflectionProbe m_ReflectionProbe;
    private ReflectionProbe reflectionProbe
    {
        get
        {
            if (m_ReflectionProbe == null)
            {
                GameObject atmosphere = new GameObject("Atmosphere");
                atmosphere.transform.parent = camera.transform;
                atmosphere.transform.position = Vector3.zero;

                m_ReflectionProbe = atmosphere.AddComponent<ReflectionProbe>();

                m_ReflectionProbe.clearFlags =
                    ReflectionProbeClearFlags.Skybox;

                m_ReflectionProbe.cullingMask = 0;

                m_ReflectionProbe.hdr = true;

                m_ReflectionProbe.mode = ReflectionProbeMode.Realtime;
                m_ReflectionProbe.refreshMode =
                    ReflectionProbeRefreshMode.EveryFrame;

                m_ReflectionProbe.timeSlicingMode =
                    ReflectionProbeTimeSlicingMode.IndividualFaces;

                m_ReflectionProbe.resolution = 128;
                m_ReflectionProbe.size = new Vector3(50000, 50000, 50000);
            }

            return m_ReflectionProbe;
        }
    }

    private Color m_Sunlight = Color.white;

    private Color[] m_DirectionalLight;
    private Color[] m_AmbientLight;

    private Vector4[] m_Frustum = new Vector4[4];

    private readonly Vector3 m_Rayleigh =
        new Vector4(5.8f, 13.5f, 33.1f) * .000001f;

    private readonly Vector3 m_Mie = new Vector4(2f, 2f, 2f) * .00001f;

    public void GenerateLightLUTs()
    {
        var temporary = RenderTexture.GetTemporary(128, 1, 0,
            RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);

        material.SetTexture("_RandomVectors", randomVectors);

        Graphics.Blit(null, temporary, material, 1);

        readback.ReadPixels(new Rect(0, 0, 128, 1), 0, 0);
        m_AmbientLight = readback.GetPixels(0, 0, 128, 1);

        Graphics.Blit(null, temporary, material, 2);

        readback.ReadPixels(new Rect(0, 0, 128, 1), 0, 0);
        m_DirectionalLight = readback.GetPixels(0, 0, 128, 1);

        RenderTexture.active = null;

        RenderTexture.ReleaseTemporary(temporary);
    }

    private void GenerateSkybox()
    {
        int kernel = computeShader.FindKernel("GenerateSkybox");

        SetComputeShaderParameters(kernel);

        computeShader.SetTexture(kernel, "_Skybox", skybox);
        computeShader.Dispatch(kernel, skybox.width >> 3, skybox.height >> 3,
            skybox.volumeDepth >> 3);
    }

    public void OnEnable()
    {
        material.SetTexture("_ParticleDensity", particleDensity);
        SetMaterialParameters(material);

        Graphics.Blit(null, particleDensity, material, 0);

        GenerateLightLUTs();
        GenerateSkybox();

        if (generateReflectionProbe == true)
            reflectionProbe.gameObject.SetActive(true);
    }

    public void OnDisable()
    {
        if (m_ParticleDensity != null)
        {
           m_ParticleDensity.Release();
           m_ParticleDensity = null;
        }

        if (m_Skybox != null)
        {
           m_Skybox.Release();
           m_Skybox = null;
        }

        if (m_Inscattering != null)
        {
            m_Inscattering.Release();
            m_Inscattering = null;
        }

        if (m_Extinction != null)
        {
            m_Extinction.Release();
            m_Extinction = null;
        }
    }

    private void SetComputeShaderParameters(int kernel)
    {
        computeShader.SetTexture(kernel, "_ParticleDensity", particleDensity);

        computeShader.SetVector("_Planet",
            new Vector4(0f, -planetRadius, 0f, planetRadius));

        computeShader.SetVector("_Sunlight", sun.color * sun.intensity);
        computeShader.SetVector("_IncomingLightColor", incomingLightColor);

        computeShader.SetVectorArray("_Frustum", m_Frustum);

        computeShader.SetVector("_SunlightDirection", sun.transform.forward);
        computeShader.SetVector("_RayleighScattering",
            m_Rayleigh * rayleighScatteringCoefficient);

        computeShader.SetVector("_MieScattering",
            m_Mie * mieScatteringCoefficient);

        computeShader.SetVector("_RayleighExtinction",
            m_Rayleigh * rayleighExtinctionCoefficient);

        computeShader.SetVector("_MieExtinction",
            m_Mie * mieExtinctionCoefficient);

        computeShader.SetVector("_Scale",
            new Vector2(1f / scale.x, 1f / scale.y));

        computeShader.SetFloat("_KarmanLine", karmanLine);
        computeShader.SetFloat("_G", g);
        computeShader.SetFloat("_Sunshine", sunshine);
    }

    private void SetMaterialParameters(Material material)
    {
        material.SetTexture("_Inscattering", inscattering);
        material.SetTexture("_Extinction", extinction);
        material.SetTexture("_Skybox", skybox);

        material.SetVector("_Planet",
            new Vector4(0f, -planetRadius, 0f, planetRadius));

        material.SetColor("_Sunlight", sun.color * sun.intensity);
        material.SetColor("_IncomingLightColor", incomingLightColor);

        m_Frustum[0] = camera.ViewportToWorldPoint(
            new Vector3(0f, 0f, camera.farClipPlane));

        m_Frustum[1] = camera.ViewportToWorldPoint(
            new Vector3(0f, 1f, camera.farClipPlane));

        m_Frustum[2] = camera.ViewportToWorldPoint(
            new Vector3(1f, 1f, camera.farClipPlane));

        m_Frustum[3] = camera.ViewportToWorldPoint(
            new Vector3(1f, 0f, camera.farClipPlane));

        material.SetVectorArray("_Frustum", m_Frustum);

        material.SetVector("_SunlightDirection", sun.transform.forward);
        material.SetVector("_RayleighScattering",
            m_Rayleigh * rayleighScatteringCoefficient);

        material.SetVector("_MieScattering", m_Mie * mieScatteringCoefficient);

        material.SetVector("_RayleighExtinction",
            m_Rayleigh * rayleighExtinctionCoefficient);

        material.SetVector("_MieExtinction", m_Mie * mieExtinctionCoefficient);

        material.SetVector("_Scale", new Vector2(1f / scale.x, 1f / scale.y));

        material.SetFloat("_KarmanLine", karmanLine);
        material.SetFloat("_G", g);
        material.SetFloat("_Sunshine", sunshine);
    }

    private Color CalculateSunlight()
    {
        float mu = Vector3.Dot(Vector3.up, -sun.transform.forward);
        float selector = 128f * ((mu + .5f) * .5f);

        int i = (int) Mathf.Clamp(Mathf.Floor(selector), 0f, 127f);
        int k = (int) Mathf.Clamp(i + 1, 0f, 127f);

        float r = selector - i;
        float t = 1f - r;

        return (m_DirectionalLight[i] * t + m_DirectionalLight[k] * r).gamma;
    }

    private void SetSunlight(Color color)
    {
        Vector3 rgb = new Vector3(color.r, color.g, color.b);

        float length = rgb.magnitude;
        rgb = rgb.normalized;

        sun.color = new Color(Mathf.Max(rgb.x, .01f), Mathf.Max(rgb.y, .01f),
            Mathf.Max(rgb.z, .01f), 1f);

        sun.intensity = Mathf.Max(length, .01f);
    }

    private Color CalculateAmbientLight()
    {
        float mu = Vector3.Dot(Vector3.up, -sun.transform.forward);
        float selector = 128f * ((mu + .5f) * .5f);

        int i = (int) Mathf.Clamp(Mathf.Floor(selector), 0f, 127f);
        int k = (int) Mathf.Clamp(i + 1, 0f, 127f);

        float r = selector - i;
        float t = 1f - r;

        return (m_AmbientLight[i] * t + m_AmbientLight[k] * r).gamma;
    }

    private void GenerateInscattering()
    {
        int kernel = computeShader.FindKernel("GenerateInscattering");

        SetComputeShaderParameters(kernel);

        computeShader.SetTexture(kernel, "_Inscattering", inscattering);
        computeShader.SetTexture(kernel, "_Extinction", extinction);

        computeShader.Dispatch(kernel, 1, 1, 8);
    }

    public void Update()
    {
        m_Sunlight = CalculateSunlight();

        SetSunlight(m_Sunlight);
        RenderSettings.ambientLight = CalculateAmbientLight();
    }

    public void OnPreRender()
    {
        if (RenderSettings.skybox != null)
            SetMaterialParameters(RenderSettings.skybox);

        SetMaterialParameters(material);
        GenerateInscattering();
    }

    [ImageEffectOpaque]
    public void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        Graphics.Blit(source, destination, material, 3);
    }
}
