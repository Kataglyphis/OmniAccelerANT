#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"
#include "kataglyphis_native_inference_plugin_private.h"

#include "kataglyphis_texture_abi.h"
#include <cstddef>
#include <cstdint>
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

}// namespace test
}// namespace kataglyphis_native_inference
