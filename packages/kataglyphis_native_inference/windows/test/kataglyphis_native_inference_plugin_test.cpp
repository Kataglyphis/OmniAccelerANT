#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <variant>

#include "kataglyphis_native_inference_plugin.h"
#include "kataglyphis_texture.h"

namespace kataglyphis_native_inference {
namespace test {

    namespace {

        using flutter::EncodableMap;
        using flutter::EncodableValue;
        using flutter::MethodCall;
        using flutter::MethodResultFunctions;

        // The copy Flutter's raster thread takes, as GetTextureVariant hands it out.
        const FlutterDesktopPixelBuffer *CopyFrame(KataglyphisTexture &texture)
        {
            flutter::TextureVariant variant = texture.GetTextureVariant();
            return std::get<flutter::PixelBufferTexture>(variant).CopyPixelBuffer(0, 0);
        }

    }// namespace

    TEST(KataglyphisTexture, ANewTextureShowsItsColourUntilAFrameArrives)
    {
        KataglyphisTexture texture(2, 1, 10, 20, 30);
        const FlutterDesktopPixelBuffer *frame = CopyFrame(texture);
        ASSERT_NE(frame, nullptr);
        EXPECT_EQ(frame->width, 2u);
        EXPECT_EQ(frame->height, 1u);
        const uint8_t expected[] = { 10, 20, 30, 255, 10, 20, 30, 255 };
        EXPECT_EQ(std::memcmp(frame->buffer, expected, sizeof expected), 0);
    }

    TEST(KataglyphisTexture, SetColorRepaintsEveryPixelOpaque)
    {
        KataglyphisTexture texture(1, 2, 0, 0, 0);
        texture.SetColor(7, 8, 9);
        const FlutterDesktopPixelBuffer *frame = CopyFrame(texture);
        const uint8_t expected[] = { 7, 8, 9, 255, 7, 8, 9, 255 };
        EXPECT_EQ(std::memcmp(frame->buffer, expected, sizeof expected), 0);
    }

    // Mirrors linux/test's case: the id only reaches a texture while it is registered, and the pushed frame replaces the colour.
    TEST(KataglyphisTexture, OnlyARegisteredTextureTakesAPushedFrameAndItWins)
    {
        KataglyphisTexture texture(1, 1, 0, 0, 0);
        const int64_t id = 4711;
        const uint8_t pushed[] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
        EXPECT_EQ(knt_push_frame(id, pushed, 3, 1), -2);

        RegisterPushTarget(id, &texture);
        EXPECT_EQ(knt_push_frame(id, pushed, 3, 1), 0);
        const FlutterDesktopPixelBuffer *frame = CopyFrame(texture);
        EXPECT_EQ(frame->width, 3u);
        EXPECT_EQ(frame->height, 1u);
        EXPECT_EQ(std::memcmp(frame->buffer, pushed, sizeof pushed), 0);

        UnregisterPushTarget(id);
        EXPECT_EQ(knt_push_frame(id, pushed, 3, 1), -2);
    }

    TEST(KataglyphisTexture, AFrameOfAnotherSizeResizesTheTextureAndBadArgumentsChangeNothing)
    {
        KataglyphisTexture texture(4, 4, 0, 0, 0);
        const uint8_t pushed[] = { 50, 60, 70, 80, 90, 100, 110, 120 };
        EXPECT_TRUE(texture.PushFrame(pushed, 1, 2));
        EXPECT_FALSE(texture.PushFrame(nullptr, 1, 2));
        EXPECT_FALSE(texture.PushFrame(pushed, 0, 2));
        const FlutterDesktopPixelBuffer *frame = CopyFrame(texture);
        EXPECT_EQ(frame->width, 1u);
        EXPECT_EQ(frame->height, 2u);
        EXPECT_EQ(std::memcmp(frame->buffer, pushed, sizeof pushed), 0);
    }

    namespace {

        // What one call answered: a value, an error code, or that the method is unknown.
        struct Reply
        {
            bool success = false;
            bool not_implemented = false;
            std::string error;
        };

        std::unique_ptr<MethodResultFunctions<>> Recorder(Reply &reply)
        {
            return std::make_unique<MethodResultFunctions<>>([&reply](const EncodableValue *) { reply.success = true; },
              [&reply](const std::string &code, const std::string &, const EncodableValue *) { reply.error = code; },
              [&reply]() { reply.not_implemented = true; });
        }

    }// namespace

    TEST(KataglyphisNativeInferencePlugin, AnUnknownMethodIsNotImplemented)
    {
        // It used to reach NotImplemented through a result already moved into the texture handler.
        KataglyphisNativeInferencePlugin plugin;
        Reply reply;
        plugin.HandleMethodCall(MethodCall("noSuchMethod", std::make_unique<EncodableValue>()), Recorder(reply));
        EXPECT_TRUE(reply.not_implemented);
        EXPECT_FALSE(reply.success);
        EXPECT_TRUE(reply.error.empty());
    }

    TEST(KataglyphisNativeInferencePlugin, AddWithANonIntegerIsBadArgsNotAThrow)
    {
        KataglyphisNativeInferencePlugin plugin;
        Reply reply;
        EncodableMap args{ { EncodableValue("a"), EncodableValue("one") }, { EncodableValue("b"), EncodableValue(2) } };
        plugin.HandleMethodCall(MethodCall("add", std::make_unique<EncodableValue>(args)), Recorder(reply));
        EXPECT_EQ(reply.error, "bad_args");
    }

    TEST(KataglyphisNativeInferencePlugin, ANegativeSizeIsBadArgs)
    {
        // Cast first, -1 became 4294967295 and passed the size check.
        KataglyphisNativeInferencePlugin plugin;
        Reply reply;
        flutter::EncodableList size{ EncodableValue(-1), EncodableValue(5) };
        plugin.HandleMethodCall(MethodCall("create", std::make_unique<EncodableValue>(size)), Recorder(reply));
        EXPECT_EQ(reply.error, "bad_args");
        EXPECT_FALSE(reply.success);
    }

    TEST(KataglyphisNativeInferencePlugin, GetPlatformVersion)
    {
        KataglyphisNativeInferencePlugin plugin;
        // Save the reply value from the success callback.
        std::string result_string;
        plugin.HandleMethodCall(MethodCall("getPlatformVersion", std::make_unique<EncodableValue>()),
          std::make_unique<MethodResultFunctions<>>(
            [&result_string](const EncodableValue *result) { result_string = std::get<std::string>(*result); },
            nullptr,
            nullptr));

        // The exact string varies by host.
        EXPECT_TRUE(result_string.rfind("Windows ", 0) == 0);
    }

}// namespace test
}// namespace kataglyphis_native_inference
