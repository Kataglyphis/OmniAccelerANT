#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"
#include "kataglyphis_native_inference_plugin_private.h"

#include <gst/gst.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <string>
#include <thread>

import kataglyphis.my_texture;

extern "C" int32_t knt_push_frame(int64_t texture_id, const uint8_t *rgba, uint32_t width, uint32_t height);

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

    // What copy_pixels hands Flutter for one frame.
    struct Pixels
    {
        const uint8_t *data = nullptr;
        uint32_t width = 0;
        uint32_t height = 0;
        std::array<uint8_t, 4> first() const { return { data[0], data[1], data[2], data[3] }; }
    };

    bool copy(FlTexture *texture, Pixels *out)
    {
        GError *error = nullptr;
        const gboolean ok = FL_PIXEL_BUFFER_TEXTURE_GET_CLASS(texture)->copy_pixels(
          FL_PIXEL_BUFFER_TEXTURE(texture), &out->data, &out->width, &out->height, &error);
        g_clear_error(&error);
        return ok == TRUE;
    }

    // The error a call left, as text; empty when it left none.
    std::string message(GError *error) { return error != nullptr ? error->message : ""; }

    class MyTextureTest : public ::testing::Test
    {
      protected:
        void SetUp() override { texture = my_texture_new(64, 48, 0, 0, 255); }
        void TearDown() override
        {
            my_texture_stop(texture);
            g_object_unref(texture);
        }
        FlTexture *texture = nullptr;
    };

    TEST_F(MyTextureTest, ANewTextureShowsItsColourUntilAFrameArrives)
    {
        Pixels pixels;
        ASSERT_TRUE(copy(texture, &pixels));
        EXPECT_EQ(pixels.width, 64U);
        EXPECT_EQ(pixels.height, 48U);
        EXPECT_EQ(pixels.first(), (std::array<uint8_t, 4>{ 0, 0, 255, 255 }));
    }

    TEST_F(MyTextureTest, APipelineMustParseAndEndInTheNamedAppsink)
    {
        GError *error = nullptr;
        EXPECT_FALSE(my_texture_set_pipeline(texture, "videotestsrc ! ! appsink", &error));
        EXPECT_FALSE(message(error).empty()) << "gst_parse_launch's reason was lost";
        g_clear_error(&error);

        EXPECT_FALSE(my_texture_set_pipeline(texture, "videotestsrc ! fakesink", &error));
        EXPECT_THAT(message(error), testing::HasSubstr("name='sink'"));
        g_clear_error(&error);

        EXPECT_FALSE(my_texture_set_pipeline(texture, "fakesrc", &error));
        EXPECT_THAT(message(error), testing::HasSubstr("Bin/Pipeline"));
        g_clear_error(&error);

        EXPECT_TRUE(my_texture_set_pipeline(texture, "videotestsrc ! videoconvert ! appsink name=sink", &error));
        EXPECT_EQ(error, nullptr);
    }

    TEST_F(MyTextureTest, PlayWithoutAPipelineSaysWhatToCallFirst)
    {
        GError *error = nullptr;
        EXPECT_FALSE(my_texture_play(texture, &error));
        EXPECT_THAT(message(error), testing::HasSubstr("setPipeline"));
        g_clear_error(&error);
    }

    TEST_F(MyTextureTest, ASourceThatFailsNamesWhatFailedForDart)
    {
        GError *error = nullptr;
        ASSERT_TRUE(my_texture_set_pipeline(
          texture, "filesrc location=/nonexistent/clip.raw ! videoparse ! videoconvert ! appsink name=sink", &error));
        EXPECT_FALSE(my_texture_play(texture, &error));
        // The debug part names the element and its file, which is what the Stream page shows.
        EXPECT_THAT(message(error), testing::HasSubstr("/nonexistent/clip.raw"));
        g_clear_error(&error);
    }

    // Its frames arrive fully transparent: Flutter would show what lies under the texture.
    TEST_F(MyTextureTest, ATestPatternReachesThePixelsOpaque)
    {
        GError *error = nullptr;
        ASSERT_TRUE(my_texture_set_pipeline(texture,
          "videotestsrc pattern=red ! videoconvert ! videoscale ! video/x-raw,width=64,height=48 ! alpha alpha=0 ! "
          "videoconvert ! appsink name=sink",
          &error))
          << message(error);
        ASSERT_TRUE(my_texture_play(texture, &error)) << message(error);

        Pixels pixels;
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
        do {
            ASSERT_TRUE(copy(texture, &pixels));
            if (pixels.first()[0] > 250 && pixels.first()[2] < 5) { break; }
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        } while (std::chrono::steady_clock::now() < deadline);
        EXPECT_GT(pixels.first()[0], 250) << "no red frame in 10 s";
        EXPECT_LT(pixels.first()[2], 5);
        for (uint32_t index = 0; index < pixels.width * pixels.height; ++index) {
            ASSERT_EQ(pixels.data[index * 4U + 3U], 255) << "pixel " << index << " is not opaque";
        }
    }

    TEST_F(MyTextureTest, OnlyARegisteredTextureTakesAPushedFrameAndItWins)
    {
        // Transparent green: the texture must still show it opaque.
        const std::array<uint8_t, 16> green = { 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0 };
        constexpr int64_t id = 4242;
        EXPECT_EQ(knt_push_frame(id, green.data(), 2, 2), -2) << "an unknown id took a frame";
        EXPECT_FALSE(my_texture_has_pushed_frame(id));

        my_texture_register_push_target(id, texture);
        EXPECT_EQ(knt_push_frame(id, nullptr, 2, 2), -1);
        EXPECT_EQ(knt_push_frame(id, green.data(), 0, 2), -1);
        EXPECT_FALSE(my_texture_has_pushed_frame(id));
        EXPECT_EQ(knt_push_frame(id, green.data(), 2, 2), 0);
        EXPECT_TRUE(my_texture_has_pushed_frame(id));

        Pixels pixels;
        ASSERT_TRUE(copy(texture, &pixels));
        EXPECT_EQ(pixels.width, 64U) << "a pushed frame keeps the texture's size";
        EXPECT_EQ(pixels.first(), (std::array<uint8_t, 4>{ 0, 255, 0, 255 }));

        my_texture_unregister_push_target(id);
        EXPECT_EQ(knt_push_frame(id, green.data(), 2, 2), -2);
        EXPECT_FALSE(my_texture_has_pushed_frame(id));
    }

}// namespace test
}// namespace kataglyphis_native_inference
