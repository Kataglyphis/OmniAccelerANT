#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"
#include "kataglyphis_native_inference_plugin_private.h"

#include "kataglyphis_texture_abi.h"
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <random>
#include <string>
#include <utility>
#include <vector>

import kataglyphis.my_texture;

// Not in the app build: run_plugin_gtest (scripts/linux/lib/container-steps.sh) builds and runs it in the native lanes.

namespace kataglyphis_native_inference {
namespace test {

    TEST(KataglyphisNativeInferencePlugin, GetPlatformVersion)
    {
        g_autoptr(FlMethodResponse) response = get_platform_version();
        ASSERT_NE(response, nullptr);
        ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));
        FlValue *result = fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response));
        ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_STRING);
        // The full string varies, so just validate that it has the right format.
        EXPECT_THAT(fl_value_get_string(result), testing::StartsWith("Linux "));
    }

    // What copy_pixels hands Flutter for one frame, for the shared ABI cases.
    struct AbiFrame
    {
        uint32_t width = 0;
        uint32_t height = 0;
        std::vector<uint8_t> bytes;
    };

    // The Linux side of the shared cases: an FlTexture read the way Flutter's raster thread reads it.
    class AbiTexture
    {
      public:
        AbiTexture(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b)
          : texture_(my_texture_new(width, height, r, g, b))
        {}
        ~AbiTexture() { g_object_unref(texture_); }
        AbiTexture(const AbiTexture &) = delete;
        AbiTexture &operator=(const AbiTexture &) = delete;

        void register_as(int64_t id) { my_texture_register_push_target(id, texture_); }
        static void unregister(int64_t id) { my_texture_unregister_push_target(id); }

        AbiFrame frame()
        {
            const uint8_t *data = nullptr;
            AbiFrame frame;
            GError *error = nullptr;
            const gboolean ok = FL_PIXEL_BUFFER_TEXTURE_GET_CLASS(texture_)->copy_pixels(
              FL_PIXEL_BUFFER_TEXTURE(texture_), &data, &frame.width, &frame.height, &error);
            g_clear_error(&error);
            EXPECT_EQ(ok, TRUE);
            if (ok == TRUE) { frame.bytes.assign(data, data + (static_cast<size_t>(frame.width) * frame.height * 4U)); }
            return frame;
        }

      private:
        FlTexture *texture_;
    };

#include "../../shared/texture_abi_cases.inc"

    TEST(MyTexture, HasPushedFrameFollowsTheRegistry)
    {
        AbiTexture texture(2, 2, 0, 0, 255);
        const std::vector<uint8_t> green(16, 255);
        constexpr int64_t id = 4242;
        EXPECT_FALSE(my_texture_has_pushed_frame(id));
        texture.register_as(id);
        EXPECT_FALSE(my_texture_has_pushed_frame(id));
        EXPECT_EQ(knt_push_frame(id, green.data(), 2, 2), KNT_OK);
        EXPECT_TRUE(my_texture_has_pushed_frame(id));
        AbiTexture::unregister(id);
        EXPECT_FALSE(my_texture_has_pushed_frame(id));
    }

    TEST(MyTexture, ATakenFrameStaysUntilTheNextAndTheNextMayChangeSize)
    {
        AbiTexture texture(2, 2, 0, 0, 255);
        constexpr int64_t id = 4243;
        texture.register_as(id);
        const std::vector<uint8_t> red{ 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255 };
        EXPECT_EQ(knt_push_frame(id, red.data(), 2, 2), KNT_OK);
        EXPECT_EQ(texture.frame().bytes, red);
        // No new frame: Flutter asks again and must see the same one, not the buffer it handed back.
        EXPECT_EQ(texture.frame().bytes, red);
        std::vector<uint8_t> wide(3U * 4U, 0);
        for (size_t pixel = 0; pixel < 3U; ++pixel) {
            wide[pixel * 4U + 1U] = 255;
            wide[pixel * 4U + 3U] = 255;
        }
        EXPECT_EQ(knt_push_frame(id, wide.data(), 3, 1), KNT_OK);
        const AbiFrame frame = texture.frame();
        EXPECT_EQ(frame.width, 3U);
        EXPECT_EQ(frame.height, 1U);
        EXPECT_EQ(frame.bytes, wide);
        EXPECT_EQ(knt_push_frame(id, red.data(), 2, 2), KNT_OK);
        EXPECT_EQ(texture.frame().bytes, red);
        AbiTexture::unregister(id);
    }

    // Milliseconds per frame of knt_push_frame's copy and copy_pixels, which takes the pushed buffer.
    struct FramePathTiming
    {
        std::string size;
        double push_ms = 0.0;
        double copy_ms = 0.0;
    };

    constexpr int kTimedFrames = 300;

    FramePathTiming time_frame_path(uint32_t width, uint32_t height, int64_t id)
    {
        using Clock = std::chrono::steady_clock;
        FlTexture *texture = my_texture_new(width, height, 0, 0, 0);
        my_texture_register_push_target(id, texture);
        std::vector<uint8_t> rgba(static_cast<size_t>(width) * height * 4U, 128);
        auto *texture_class = FL_PIXEL_BUFFER_TEXTURE_GET_CLASS(texture);
        const uint8_t *out = nullptr;
        uint32_t out_width = 0;
        uint32_t out_height = 0;
        Clock::duration push{};
        Clock::duration copy{};
        for (int frame = 0; frame < kTimedFrames; ++frame) {
            rgba.front() = static_cast<uint8_t>(frame);
            const auto started = Clock::now();
            EXPECT_EQ(knt_push_frame(id, rgba.data(), width, height), KNT_OK);
            const auto pushed = Clock::now();
            EXPECT_EQ(
              texture_class->copy_pixels(FL_PIXEL_BUFFER_TEXTURE(texture), &out, &out_width, &out_height, nullptr),
              TRUE);
            copy += Clock::now() - pushed;
            push += pushed - started;
        }
        // The last frame reached Flutter's buffer, so the loop timed real copies.
        EXPECT_EQ(out_width, width);
        EXPECT_EQ(out_height, height);
        if (out != nullptr) { EXPECT_EQ(out[0], static_cast<uint8_t>(kTimedFrames - 1)); }
        my_texture_unregister_push_target(id);
        g_object_unref(texture);
        const auto per_frame = [](Clock::duration total) {
            return std::chrono::duration<double, std::milli>(total).count() / kTimedFrames;
        };
        return { std::to_string(width) + "x" + std::to_string(height), per_frame(push), per_frame(copy) };
    }

    // google-benchmark's JSON shape, so the hub's bench-history reads it without a parser of its own.
    void write_timings(const char *path, const std::vector<FramePathTiming> &timings)
    {
        std::ofstream json(path);
        json << R"({"context": {"executable": "kataglyphis_native_inference_test"}, "benchmarks": [)";
        const char *separator = "";
        for (const auto &timing : timings) {
            for (const auto &[step, ms] :
              { std::pair{ "push", timing.push_ms }, std::pair{ "copy", timing.copy_ms } }) {
                json << separator << R"({"name": "frame_path_)" << step << "/" << timing.size
                     << R"(", "run_type": "iteration", "iterations": )" << kTimedFrames << R"(, "real_time": )" << ms
                     << R"(, "cpu_time": )" << ms << R"(, "time_unit": "ms"})";
                separator = ", ";
            }
        }
        json << "]}\n";
    }

    TEST(FramePath, PushAndCopyAreTimedPerFrame)
    {
        const std::vector<FramePathTiming> timings{ time_frame_path(640, 480, 5150), time_frame_path(1280, 720, 5151) };
        for (const auto &timing : timings) {
            std::printf("frame path %s: push %.3f ms, copy %.3f ms per frame\n",
              timing.size.c_str(),
              timing.push_ms,
              timing.copy_ms);
        }
        // Set by run_plugin_gtest in the native Linux lane; bench-history compares the file with earlier runs.
        if (const char *path = std::getenv("KNT_FRAME_TIMING_JSON"); path != nullptr && *path != '\0') {
            write_timings(path, timings);
        }
    }

}// namespace test
}// namespace kataglyphis_native_inference
