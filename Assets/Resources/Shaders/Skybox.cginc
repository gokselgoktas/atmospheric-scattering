#ifndef SKYBOX_CGINC
#define SKYBOX_CGINC

#include "UnityCG.cginc"
#include "AtmosphericScattering.hlsl"

struct Input
{
    float4 vertex : POSITION;
};

struct Varyings
{
    float4 vertex : SV_POSITION;
    float3 direction : TEXCOORD0;
};

sampler3D _Skybox;

Varyings vertex(in Input input)
{
    Varyings output;

    output.vertex = UnityObjectToClipPos(input.vertex);
    output.direction = mul(unity_ObjectToWorld, input.vertex).xyz;

    return output;
}

float4 fragment(in Varyings input) : SV_Target
{
    Ray ray;
    ray.origin = _WorldSpaceCameraPos;
    ray.direction = normalize(input.direction);

    float3 light = -_WorldSpaceLightPos0.xyz;

    float height = distance(ray.origin, _Planet.xyz) - _Planet.w;
    float mesosphere = _Planet.w + height;

    float3 normal = normalize(ray.origin - _Planet.xyz);
    float2 zenith = float2(dot(normal, ray.direction), dot(normal, -light));

    float3 uvw = float3(sqrt(height / _KarmanLine), .5 * zenith.xy + .5);

    float horizon = -sqrt(height * (2. * _Planet.w + height)) * rcp(mesosphere);

    if (zenith.x > horizon)
        uvw.y = .5 * pow((zenith.x - horizon) / (1. - horizon), .2) + .5;
    else
        uvw.y = .5 * pow((horizon - zenith.x) / (horizon + 1.), .2);

    uvw.z = .5 * ((atan(zenith.y * 5.749812) * .90091) + .74);

    float4 rayleigh = tex3D(_Skybox, uvw);
    float3 mie = rayleigh.xyz * rayleigh.w * rcp(rayleigh.x);

    float2 phase = GetAngularDistribution(dot(ray.direction, -light.xyz));

    rayleigh.xyz *= phase.x;
    mie *= phase.y;

    float3 atmosphericScattering = (rayleigh.xyz * _RayleighScattering + mie *
        _MieScattering) * _IncomingLightColor.rgb;

    atmosphericScattering += GetSun(mie, dot(ray.direction, -light.xyz)) *
        _Sunshine;

    return float4(max(0., atmosphericScattering), 1.);
}

#endif
