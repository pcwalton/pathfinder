#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












#extension GL_GOOGLE_include_directive : enable

precision highp float;
















vec4 computeCoverage(vec2 from, vec2 to, sampler2D areaLUT){

    vec2 left = from . x < to . x ? from : to, right = from . x < to . x ? to : from;


    vec2 window = clamp(vec2(from . x, to . x), - 0.5, 0.5);
    float offset = mix(window . x, window . y, 0.5)- left . x;
    float t = offset /(right . x - left . x);


    float y = mix(left . y, right . y, t);
    float d =(right . y - left . y)/(right . x - left . x);


    float dX = window . x - window . y;
    return texture(areaLUT, vec2(y + 8.0, abs(d * dX))/ 16.0)* dX;
}


layout(local_size_x = 16, local_size_y = 4)in;

uniform writeonly image2D uDest;
uniform sampler2D uAreaLUT;
uniform int uFirstTileIndex;

layout(std430, binding = 0)buffer bFills {
    restrict readonly uint iFills[];
};

layout(std430, binding = 1)buffer bFillTileMap {
    restrict readonly int iFillTileMap[];
};

void main(){
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID . xy)* ivec2(1, 4);
    uint tileIndexOffset = gl_WorkGroupID . z;

    uint tileIndex = tileIndexOffset + uint(uFirstTileIndex);

    int fillIndex = iFillTileMap[tileIndex];
    if(fillIndex < 0)
        return;

    vec4 coverages = vec4(0.0);
    do {
        uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
        vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                fillTo & 0xffff, fillTo >> 16)/ 256.0;

        coverages += computeCoverage(lineSegment . xy -(vec2(tileSubCoord)+ vec2(0.5)),
                                     lineSegment . zw -(vec2(tileSubCoord)+ vec2(0.5)),
                                     uAreaLUT);

        fillIndex = int(iFills[fillIndex * 3 + 2]);
    } while(fillIndex >= 0);

    ivec2 tileOrigin =
        ivec2(tileIndex & 0xff,(tileIndex >> 8u)& 0xff +(((tileIndex >> 16u)& 0xff)<< 8u))*
        ivec2(16, 4);
    ivec2 destCoord = tileOrigin + ivec2(gl_LocalInvocationID . xy);
    imageStore(uDest, destCoord, coverages);
}
