#ifndef ATMOSPHERIC_SCATTERING_HLSL
#define ATMOSPHERIC_SCATTERING_HLSL

#define ITERATION_COUNT 256

struct Ray
{
    float3 origin;
    float3 direction;
};

struct Sphere
{
    float3 position;
    float radius;
};

struct Trace
{
    bool isHit;
    float2 slice;
};

struct Inscattering
{
    float3 rayleigh;
    float3 mie;

    float2 density;
};

struct AtmosphericScattering
{
    float3 inscattering;
    float3 extinction;
};

Texture2D<float2> _ParticleDensity;
Texture2D<float3> _RandomVectors;

SamplerState LinearClampSampler;

float4 _Planet;
float4 _Sunlight;
float4 _IncomingLightColor;

float3 _Frustum[4];

float3 _SunlightDirection;
float3 _RayleighExtinction;
float3 _MieExtinction;
float3 _RayleighScattering;
float3 _MieScattering;

float2 _Scale;

float _KarmanLine;
float _G;
float _Sunshine;

Trace TraceSphere(in Ray ray, in Sphere sphere)
{
    Trace result;
    result.isHit = false;
    result.slice = -1.;

    float3 delta = ray.origin - sphere.position;

    float a = dot(delta, ray.direction);
    float b = dot(delta, delta) - sphere.radius * sphere.radius;

    float c = a * a - b;

    if (c < 0.)
        return result;

    c = sqrt(c);

    result.isHit = true;
    result.slice = float2(-a - c, -a + c);

    return result;
}

float3 GetSun(in float3 mie, in float mu)
{
    float sun = .0004 * rcp(12.566371 * pow(1.9604 - 1.96 * mu, 1.5));
    return mie * sun * .0003;
}

float2 GetParticleDensity(in Ray ray)
{
    Sphere surface;
    surface.position = _Planet.xyz;
    surface.radius = _Planet.w;

    Sphere turbopause;
    turbopause.position = _Planet.xyz;
    turbopause.radius = _Planet.w + _KarmanLine;

    Trace trace = TraceSphere(ray, surface);

    if (trace.slice.x >= 0.)
        return 1e+38;

    trace = TraceSphere(ray, turbopause);
    float3 end = ray.origin + ray.direction * trace.slice.y;

    float3 slice = (end - ray.origin) / (float) ITERATION_COUNT;
    float2 density = 0;

    for (int i = 0; i < ITERATION_COUNT; ++i)
    {
        float3 position = ray.origin + slice * (.5 + (float) i);

        float2 height =
            abs(distance(position, _Planet.xyz) - _Planet.w);

        density += exp(-height * _Scale) * length(slice);
    }

    return density;
}

float4 GetAtmosphereDensity(in float3 position, in float3 light)
{
	float2 height = distance(position, _Planet.xyz) - _Planet.w;
	float4 density = float4(exp(-height * _Scale), 0., 0.);

	float diffuse = dot(normalize(position - _Planet.xyz), -light);

	density.zw = _ParticleDensity.SampleLevel(LinearClampSampler,
        float2(.5 * diffuse + .5, height.x / _KarmanLine), 0.).xy;

    return density;
}

float3 GetExtinction(in float2 density)
{
    return exp(-density.x * _RayleighExtinction - density.y * _MieExtinction);
}

float3 GetOpticalDepth(in float2 density)
{
	return GetExtinction(density) * _IncomingLightColor.rgb;
}

float2 GetAngularDistribution(in float mu)
{
    float numerator = (1. - _G * _G) * (1. + mu * mu);

    float denominator = rcp((2. + _G * _G) *
        pow(max(0., 1. + _G * _G - 2. * _G * mu), 1.5));

    /* bruneton: .059683 * (1. + mu * mu)
     * elek = .063662 * (1.4 + .5 * mu) */
    return float2(.063662 * (1.4 + .5 * mu), .119366 * numerator * denominator);
}

Inscattering GetLocalInscattering(in float2 local, in float2 edge,
    in float2 forward)
{
	float3 extinction = GetExtinction(edge + forward);

    Inscattering inscattering;
    inscattering.rayleigh = local.x * extinction;
    inscattering.mie = local.y * extinction;

    return inscattering;
}

Inscattering GetInscattering(in Ray ray, in float range, in float3 light,
    in int iterationCount)
{
    float3 slice = ray.direction * range / (float) iterationCount;
    float delta = length(slice);

    float4 atmosphereDensity = GetAtmosphereDensity(ray.origin, light);

    float2 forward = 0.;
    float2 local = 0.;

    Inscattering result;
    result.rayleigh = 0.;
    result.mie = 0.;

    Inscattering previous = GetLocalInscattering(atmosphereDensity.xy,
        atmosphereDensity.zw, forward);

    for (int i = 0; i < iterationCount; ++i)
    {
        float3 position = ray.origin + slice * (float) (i + 1);

        atmosphereDensity = GetAtmosphereDensity(position, light);

        forward += (atmosphereDensity.xy + local) * delta * .5;
        local = atmosphereDensity.xy;

        Inscattering current = GetLocalInscattering(atmosphereDensity.xy,
            atmosphereDensity.zw, forward);

        result.rayleigh += (current.rayleigh + previous.rayleigh) * delta * .5;
        result.mie += (current.mie + previous.mie) * delta * .5;

        previous.rayleigh = current.rayleigh;
        previous.mie = current.mie;
    }

    result.density = forward;
    return result;
}

AtmosphericScattering GetAtmosphericScattering(in Ray ray, in float range,
    in float3 light, in int iterationCount)
{
    Inscattering inscattering =
        GetInscattering(ray, range, light, iterationCount);

    float2 phase = GetAngularDistribution(dot(ray.direction, -light));

    inscattering.rayleigh *= phase.x;
    inscattering.mie *= phase.y;

    AtmosphericScattering atmosphericScattering;
    atmosphericScattering.inscattering = _IncomingLightColor.rgb *
        (inscattering.rayleigh * _RayleighScattering + inscattering.mie *
            _MieScattering);

    atmosphericScattering.inscattering += GetSun(inscattering.mie,
        dot(ray.direction, -light)) * _Sunshine;

    atmosphericScattering.extinction = GetExtinction(inscattering.density);
    return atmosphericScattering;
}

float4 GetAmbientLight(in float3 light)
{
    Ray ray;
    ray.origin = 0.;
    ray.direction = 0.;

    Sphere surface;
    surface.position = _Planet.xyz;
    surface.radius = _Planet.w;

    Sphere turbopause;
    turbopause.position = _Planet.xyz;
    turbopause.radius = _Planet.w + _KarmanLine;

    float4 color = 0.;

    for (int i = 0; i < ITERATION_COUNT; ++i)
    {
        float2 uv = float2((float) i + .5 * rcp((float) ITERATION_COUNT), .5);

        ray.direction = _RandomVectors.Sample(LinearClampSampler, uv).xyz;
        ray.direction.y = abs(ray.direction.y);

        Trace trace = TraceSphere(ray, turbopause);
        float range = trace.slice.y;

        trace = TraceSphere(ray, surface);

        if (trace.slice.x > 0.)
            range = min(range, trace.slice.x);

        AtmosphericScattering atmosphericScattering =
            GetAtmosphericScattering(ray, range, light, ITERATION_COUNT);

        color += float4(atmosphericScattering.inscattering *
            dot(ray.direction, float3(0., 1., 0.)), 1.);
    }

    return color * 6.283185 / (float) ITERATION_COUNT;
}

float4 GetDirectionalLight(in float3 direction)
{
    // TODO: expose that 500. maybe?
	float4 atmosphereDensity =
		GetAtmosphereDensity(float3(0., 500., 0.), -direction);

	return float4(GetOpticalDepth(atmosphereDensity.zw), 1.);
}

#endif
