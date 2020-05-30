#version 430

// pathfinder/shaders/dice.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#extension GL_GOOGLE_include_directive : enable

#define BIN_WORKGROUP_SIZE  64

#define MAX_CURVE_STACK_SIZE    32

#define FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC   0x80000000u
#define FLAGS_PATH_INDEX_CURVE_IS_CUBIC       0x40000000u

#define TOLERANCE   0.25

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

layout(local_size_x = 64) in;

uniform mat2 uTransform;
uniform vec2 uTranslation;
uniform int uPathCount;
uniform int uLastBatchSegmentIndex;

struct Segment {
    vec4 line;
    uvec4 pathIndex;
};

layout(std430, binding = 0) buffer bComputeIndirectParams {
    // [0]: number of x workgroups
    // [1]: number of y workgroups (always 1)
    // [2]: number of z workgroups (always 1)
    // [3]: unused
    // [4]: unused
    // [5]: number of output segments
    restrict uint iComputeIndirectParams[];
};

// Indexed by batch path index.
layout(std430, binding = 1) buffer bDiceMetadata {
    // x: global path ID
    // y: first global segment index
    // z: first batch segment index
    // w: unused
    restrict readonly uvec4 iDiceMetadata[];
};

layout(std430, binding = 2) buffer bPoints {
    restrict readonly vec2 iPoints[];
};

layout(std430, binding = 3) buffer bInputIndices {
    restrict readonly uvec2 iInputIndices[];
};

layout(std430, binding = 4) buffer bOutputSegments {
    restrict Segment iOutputSegments[];
};

void emitLineSegment(vec4 lineSegment, uint pathIndex) {
    uint outputSegmentIndex = atomicAdd(iComputeIndirectParams[5], 1);
    if (outputSegmentIndex % BIN_WORKGROUP_SIZE == 0)
        atomicAdd(iComputeIndirectParams[0], 1);

    iOutputSegments[outputSegmentIndex].line = lineSegment;
    iOutputSegments[outputSegmentIndex].pathIndex.x = pathIndex;
}

// See Kaspar Fischer, "Piecewise Linear Approximation of Bézier Curves", 2000.
bool curveIsFlat(vec4 baseline, vec4 ctrl) {
    vec4 uv = vec4(3.0) * ctrl - vec4(2.0) * baseline - baseline.zwxy;
    uv *= uv;
    uv = max(uv, uv.zwxy);
    return uv.x + uv.y <= 16.0 * TOLERANCE * TOLERANCE;
}

void subdivideCurve(vec4 baseline,
                    vec4 ctrl,
                    float t,
                    out vec4 prevBaseline,
                    out vec4 prevCtrl,
                    out vec4 nextBaseline,
                    out vec4 nextCtrl) {
    vec2 p0 = baseline.xy, p1 = ctrl.xy, p2 = ctrl.zw, p3 = baseline.zw;
    vec2 p0p1 = mix(p0, p1, t), p1p2 = mix(p1, p2, t), p2p3 = mix(p2, p3, t);
    vec2 p0p1p2 = mix(p0p1, p1p2, t), p1p2p3 = mix(p1p2, p2p3, t);
    vec2 p0p1p2p3 = mix(p0p1p2, p1p2p3, t);
    prevBaseline = vec4(p0, p0p1p2p3);
    prevCtrl = vec4(p0p1, p0p1p2);
    nextBaseline = vec4(p0p1p2p3, p3);
    nextCtrl = vec4(p1p2p3, p2p3);
}

vec2 getPoint(uint pointIndex) {
    return uTransform * iPoints[pointIndex] + uTranslation;
}

void main() {
    uint batchSegmentIndex = gl_GlobalInvocationID.x;
    if (batchSegmentIndex >= uLastBatchSegmentIndex)
        return;

    // Find the path index.
    uint lowPathIndex = 0, highPathIndex = uint(uPathCount);
    int iteration = 0;
    while (iteration < 1024 && lowPathIndex + 1 < highPathIndex) {
        uint midPathIndex = lowPathIndex + (highPathIndex - lowPathIndex) / 2;
        uint midBatchSegmentIndex = iDiceMetadata[midPathIndex].z;
        if (batchSegmentIndex < midBatchSegmentIndex) {
            highPathIndex = midPathIndex;
        } else {
            lowPathIndex = midPathIndex;
            if (batchSegmentIndex == midBatchSegmentIndex)
                break;
        }
        iteration++;
    }

    uint batchPathIndex = lowPathIndex;
    uvec4 diceMetadata = iDiceMetadata[batchPathIndex];
    uint firstGlobalSegmentIndexInPath = diceMetadata.y;
    uint firstBatchSegmentIndexInPath = diceMetadata.z;
    uint globalSegmentIndex = batchSegmentIndex - firstBatchSegmentIndexInPath +
        firstGlobalSegmentIndexInPath;

    uvec2 inputIndices = iInputIndices[globalSegmentIndex];
    uint fromPointIndex = inputIndices.x, flagsPathIndex = inputIndices.y;

    uint toPointIndex = fromPointIndex;
    if ((flagsPathIndex & FLAGS_PATH_INDEX_CURVE_IS_CUBIC) != 0u)
        toPointIndex += 3;
    else if ((flagsPathIndex & FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC) != 0u)
        toPointIndex += 2;
    else
        toPointIndex += 1;

    vec4 baseline = vec4(getPoint(fromPointIndex), getPoint(toPointIndex));
    if ((flagsPathIndex & (FLAGS_PATH_INDEX_CURVE_IS_CUBIC |
                           FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC)) == 0) {
        emitLineSegment(baseline, batchPathIndex);
        return;
    }

    // Get control points. Degree elevate if quadratic.
    vec2 ctrl0 = getPoint(fromPointIndex + 1);
    vec4 ctrl;
    if ((flagsPathIndex & FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC) != 0) {
        vec2 ctrl0_2 = ctrl0 * vec2(2.0);
        ctrl = (baseline + (ctrl0 * vec2(2.0)).xyxy) * vec4(1.0 / 3.0);
    } else {
        ctrl = vec4(ctrl0, getPoint(fromPointIndex + 2));
    }

    vec4 baselines[MAX_CURVE_STACK_SIZE];
    vec4 ctrls[MAX_CURVE_STACK_SIZE];
    int curveStackSize = 1;
    baselines[0] = baseline;
    ctrls[0] = ctrl;

    while (curveStackSize > 0) {
        curveStackSize--;
        baseline = baselines[curveStackSize];
        ctrl = ctrls[curveStackSize];
        if (curveIsFlat(baseline, ctrl) || curveStackSize + 2 >= MAX_CURVE_STACK_SIZE) {
            emitLineSegment(baseline, batchPathIndex);
        } else {
            subdivideCurve(baseline,
                           ctrl,
                           0.5,
                           baselines[curveStackSize + 1],
                           ctrls[curveStackSize + 1],
                           baselines[curveStackSize + 0],
                           ctrls[curveStackSize + 0]);
            curveStackSize += 2;
        }
    }
}