// Core Image kernels for render version 1: tape artefacts (05 V04, 08 I01: chroma bleed, VHS
// softness, scanlines, line jitter and a rolling tracking band) and the Beat glitch. Compiled with -fcikernel and
// linked with -cikernel (Config/RENN.shared.xcconfig) into the app's default.metallib.
//
// Deterministic: every random value is a hash of (row, media tick, seed); nothing reads the clock.
// Sizes are relative to the frame's short edge (1080 px reference), like the grain.

#include <CoreImage/CoreImage.h>
using namespace metal;

namespace renn {
    inline float hash(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    inline float3 toYIQ(float3 c) {
        return float3(dot(c, float3(0.299, 0.587, 0.114)),
                      dot(c, float3(0.596, -0.274, -0.322)),
                      dot(c, float3(0.211, -0.523, 0.312)));
    }

    inline float3 toRGB(float3 y) {
        return float3(y.x + 0.956 * y.y + 0.621 * y.z,
                      y.x - 0.272 * y.y - 0.647 * y.z,
                      y.x - 1.106 * y.y + 1.703 * y.z);
    }
}

extern "C" { namespace coreimage {
    /// frame: (origin x, origin y, width, height) of the output.
    /// strengths: (chroma bleed, softness, scanlines, line jitter), each 0...1.
    /// motion: (media tick, tracking strength 0...1, seed 0...1, unused).
    float4 rennVHS(sampler src, float4 frame, float4 strengths, float4 motion, destination dest) {
        float2 p = dest.coord();
        float2 local = p - frame.xy;
        float scale = max(0.25, min(frame.z, frame.w) / 1080.0);
        float tick = motion.x;
        float tracking = motion.y;
        float seed = motion.z;

        // Tape lines: about 480 across a 1080 px short edge.
        float lineHeight = max(1.0, 2.25 * scale);
        float row = floor(local.y / lineHeight);

        // Line jitter: each tape line wobbles sideways by up to 1.5 px (at 1080), per tick.
        float shift = (renn::hash(float2(row + seed * 977.0, tick)) - 0.5) * 3.0 * strengths.w * scale;

        // Tracking band: a 5% high band rolls up the frame every 8 seconds, displacing lines and
        // adding tape noise.
        float bandCentre = (1.2 - fract(tick / 480.0 + seed)) * frame.w - 0.1 * frame.w;
        float bandHalf = 0.025 * frame.w;
        float band = tracking * (1.0 - smoothstep(0.0, bandHalf, abs(local.y - bandCentre)));
        float bandNoise = renn::hash(float2(row * 1.7 + 13.0, tick + seed * 311.0));
        shift += band * (bandNoise - 0.3) * 14.0 * scale;

        float2 q = float2(p.x + shift, p.y);
        float4 centre = src.sample(src.transform(q));

        // Softness: horizontal 5-tap luma blur, radius up to 2.5 px (at 1080).
        float r = strengths.y * 2.5 * scale;
        float lumaBlur = 0.0;
        float weights[5] = { 1.0, 2.0, 3.0, 2.0, 1.0 };
        for (int k = -2; k <= 2; k++) {
            float3 c = src.sample(src.transform(q + float2(float(k) * r, 0.0))).rgb;
            lumaBlur += renn::toYIQ(c).x * weights[k + 2];
        }
        lumaBlur /= 9.0;

        // Chroma bleed: colour is averaged from pixels to the left, so it trails to the right,
        // up to 8 px (at 1080).
        float b = strengths.x * 2.0 * scale;
        float2 chroma = float2(0.0);
        for (int k = 0; k < 5; k++) {
            float3 c = src.sample(src.transform(q - float2(float(k) * b, 0.0))).rgb;
            chroma += renn::toYIQ(c).yz;
        }
        chroma /= 5.0;

        float3 yiq = float3(lumaBlur, chroma);
        // Tape noise inside the tracking band.
        yiq.x = mix(yiq.x, bandNoise, band * 0.35);

        float3 rgb = renn::toRGB(yiq);
        // Scanlines: a soft dark line between tape lines, at most 35% darker.
        float phase = 0.5 - 0.5 * cos(6.2831853 * local.y / lineHeight);
        rgb *= 1.0 - strengths.z * 0.35 * phase;
        return float4(rgb, centre.a);
    }

    /// Beat glitch after an onset (BeatModulation): about 15% of 24 horizontal blocks shift
    /// sideways (up to 24 px at 1080) and red/blue split apart (up to 6 px). Brightness is
    /// untouched, so a hit never flashes.
    /// glitch: (rgb split 0...1, block shift 0...1, hit seed, unused).
    float4 rennBeatGlitch(sampler src, float4 frame, float4 glitch, destination dest) {
        float2 p = dest.coord();
        float2 local = p - frame.xy;
        float scale = max(0.25, min(frame.z, frame.w) / 1080.0);
        float seed = glitch.z;

        float block = floor(local.y / max(1.0, frame.w / 24.0));
        float pick = renn::hash(float2(block + 17.0, seed));
        float direction = renn::hash(float2(block + 91.0, seed + 5.0)) - 0.5;
        float shift = pick > 0.85 ? direction * 2.0 * glitch.y * 24.0 * scale : 0.0;

        float split = glitch.x * 6.0 * scale;
        float2 q = float2(p.x + shift, p.y);
        float4 g = src.sample(src.transform(q));
        float r = src.sample(src.transform(q + float2(split, 0.0))).r;
        float b = src.sample(src.transform(q - float2(split, 0.0))).b;
        return float4(r, g.g, b, g.a);
    }
}}
