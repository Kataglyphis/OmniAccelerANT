#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"
#include "kataglyphis_native_inference_plugin_private.h"

// Not in the app build: run_plugin_gtest (scripts/linux/lib/container-steps.sh) builds and runs it in the native lanes.

namespace kataglyphis_native_inference {
namespace test {

TEST(KataglyphisNativeInferencePlugin, GetPlatformVersion) {
  g_autoptr(FlMethodResponse) response = get_platform_version();
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  FlValue* result = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_STRING);
  // The full string varies, so just validate that it has the right format.
  EXPECT_THAT(fl_value_get_string(result), testing::StartsWith("Linux "));
}

}  // namespace test
}  // namespace kataglyphis_native_inference
