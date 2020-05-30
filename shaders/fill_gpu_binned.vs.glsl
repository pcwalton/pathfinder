#version 430

// pathfinder/shaders/fill_gpu_binned.vs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#extension GL_GOOGLE_include_directive : enable

// TODO(pcwalton): See if we can use preprocessor magic to conditionally remove the SSBO, so that
// we can merge this shader with `fill_cpu_binned.vs.glsl`.

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

#include "fill_vertex.inc.glsl"

uniform vec2 uFramebufferSize;
uniform vec2 uTileSize;

layout(std430, binding = 0) buffer bTiles {
    restrict uint iTiles[];
};

in uvec2 aTessCoord;
in uvec4 aLineSegment;
in int aTileIndex;

out vec2 vFrom;
out vec2 vTo;

void main() {
    // If we binned on GPU, then `aTileIndex` refers to a *global* tile index, and we have to
    // convert that to an alpha tile index.
    //
    // This is unfortunately very confusing, but I don't know of any other way to make the D3D10
    // rasterization pipeline work simultaneously with compute.
    gl_Position = computeVertexPosition(iTiles[aTileIndex * 4 + 1],
                                        aTessCoord,
                                        aLineSegment,
                                        uTileSize,
                                        uFramebufferSize,
                                        vFrom,
                                        vTo);
}