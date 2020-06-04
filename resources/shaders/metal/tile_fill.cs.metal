// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    
    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }
    
    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }
    
    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }
    
    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

struct bInitialTileMap
{
    uint iInitialTileMap[1];
};

struct bTiles
{
    int iTiles[1];
};

struct bTileLinkMap
{
    int2 iTileLinkMap[1];
};

struct bFills
{
    uint iFills[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 4u, 1u);

constant spvUnsafeArray<float4, 4> _141 = spvUnsafeArray<float4, 4>({ float4(0.0), float4(0.0), float4(0.0), float4(0.0) });

static inline __attribute__((always_inline))
float4 computeCoverage(thread const float2& from, thread const float2& to, thread const texture2d<float> areaLUT, thread const sampler areaLUTSmplr)
{
    float2 left = select(to, from, bool2(from.x < to.x));
    float2 right = select(from, to, bool2(from.x < to.x));
    float2 window = fast::clamp(float2(from.x, to.x), float2(-0.5), float2(0.5));
    float offset = mix(window.x, window.y, 0.5) - left.x;
    float t = offset / (right.x - left.x);
    float y = mix(left.y, right.y, t);
    float d = (right.y - left.y) / (right.x - left.x);
    float dX = window.x - window.y;
    return areaLUT.sample(areaLUTSmplr, (float2(y + 8.0, abs(d * dX)) / float2(16.0)), level(0.0)) * dX;
}

kernel void main0(constant int2& uFramebufferTileSize [[buffer(0)]], constant int2& uTextureMetadataSize [[buffer(5)]], const device bInitialTileMap& _161 [[buffer(1)]], const device bTiles& _180 [[buffer(2)]], const device bTileLinkMap& _216 [[buffer(3)]], const device bFills& _231 [[buffer(4)]], texture2d<float> uAreaLUT [[texture(0)]], texture2d<float> uTextureMetadata [[texture(1)]], texture2d<float, access::write> uDest [[texture(2)]], sampler uAreaLUTSmplr [[sampler(0)]], sampler uTextureMetadataSmplr [[sampler(1)]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    int2 tileSubCoord = int2(gl_LocalInvocationID.xy) * int2(1, 4);
    int2 tileCoord = int2(gl_WorkGroupID.xy);
    spvUnsafeArray<float4, 4> colors = spvUnsafeArray<float4, 4>({ float4(0.0), float4(0.0), float4(0.0), float4(0.0) });
    uint tileIndexOffset = uint(tileCoord.x + (tileCoord.y * uFramebufferTileSize.x));
    int tileIndex = int(_161.iInitialTileMap[tileIndexOffset]);
    uint iteration = 0u;
    while (tileIndex >= 0)
    {
        uint pathIndex = uint(_180.iTiles[(tileIndex * 4) + 2]);
        uint colorIndex = uint(_180.iTiles[(tileIndex * 4) + 3]) & 65535u;
        int backdrop = _180.iTiles[(tileIndex * 4) + 3] >> 24;
        float4 coverages = float4(float(backdrop));
        int fillIndex = _216.iTileLinkMap[tileIndex].x;
        while (fillIndex >= 0)
        {
            uint fillFrom = _231.iFills[(fillIndex * 3) + 0];
            uint fillTo = _231.iFills[(fillIndex * 3) + 1];
            float4 lineSegment = float4(float(fillFrom & 65535u), float(fillFrom >> uint(16)), float(fillTo & 65535u), float(fillTo >> uint(16))) / float4(256.0);
            float2 param = lineSegment.xy - (float2(tileSubCoord) + float2(0.5));
            float2 param_1 = lineSegment.zw - (float2(tileSubCoord) + float2(0.5));
            coverages += computeCoverage(param, param_1, uAreaLUT, uAreaLUTSmplr);
            fillIndex = int(_231.iFills[(fillIndex * 3) + 2]);
            iteration++;
            if (iteration >= 16384u)
            {
                return;
            }
        }
        float2 textureMetadataScale = float2(1.0) / float2(uTextureMetadataSize);
        float2 metadataEntryCoord = float2(float((colorIndex % 128u) * 4u), float(colorIndex / 128u));
        float2 colorTexMatrix0Coord = (metadataEntryCoord + float2(0.5)) * textureMetadataScale;
        float2 colorTexOffsetsCoord = (metadataEntryCoord + float2(1.5, 0.5)) * textureMetadataScale;
        float2 baseColorCoord = (metadataEntryCoord + float2(2.5, 0.5)) * textureMetadataScale;
        float4 colorTexMatrix0 = uTextureMetadata.sample(uTextureMetadataSmplr, colorTexMatrix0Coord, level(0.0));
        float4 colorTexOffsets = uTextureMetadata.sample(uTextureMetadataSmplr, colorTexOffsetsCoord, level(0.0));
        float4 baseColor = uTextureMetadata.sample(uTextureMetadataSmplr, baseColorCoord, level(0.0));
        for (uint y = 0u; y < 4u; y++)
        {
            float4 thisColor = float4(baseColor.xyz, baseColor.w * fast::clamp(abs(coverages[y]), 0.0, 1.0));
            colors[y] = mix(colors[y], thisColor, float4(thisColor.w));
        }
        tileIndex = _216.iTileLinkMap[tileIndex].y;
    }
    int2 destCoord = (tileCoord * int2(16)) + tileSubCoord;
    for (uint y_1 = 0u; y_1 < 4u; y_1++)
    {
        uDest.write(colors[y_1], uint2((destCoord + int2(0, int(y_1)))));
    }
}

