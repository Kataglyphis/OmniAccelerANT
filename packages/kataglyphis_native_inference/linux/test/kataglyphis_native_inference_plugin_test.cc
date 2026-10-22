#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"
#include "kataglyphis_native_inference_plugin_private.h"

#include <array>
#include <cstdint>
#include "kataglyphis_texture_abi.h"

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

    class MyTextureTest : public ::testing::Test
    {
      protected:
        void SetUp() override { texture = my_texture_new(64, 48, 0, 0, 255); }
        void TearDown() override { g_object_unref(texture); }
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
        // Rust's frames may arrive transparent: Flutter would show what lies under the texture.
        for (uint32_t index = 0; index < pixels.width * pixels.height; ++index) {
            ASSERT_EQ(pixels.data[index * 4U + 3U], 255) << "pixel " << index << " is not opaque";
        }

        my_texture_unregister_push_target(id);
        EXPECT_EQ(knt_push_frame(id, green.data(), 2, 2), -2);
        EXPECT_FALSE(my_texture_has_pushed_frame(id));
    }

}// namespace test
}// namespace kataglyphis_native_inference
