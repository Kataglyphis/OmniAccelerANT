#ifndef OMNI_ACCELERANT_ORT_DEVICE_H_
#define OMNI_ACCELERANT_ORT_DEVICE_H_

#include <windows.h>

#include <algorithm>
#include <string>

// The selected package may be deliberately run on the CPU for testing.
inline bool IsAllowedOrtDevice(std::wstring device, const std::wstring &provider) {
  std::transform(device.begin(), device.end(), device.begin(), [](wchar_t ch) {
    return ch >= L'A' && ch <= L'Z' ? ch + (L'a' - L'A') : ch;
  });
  return device == L"cpu" || device == L"auto" || device == provider;
}

inline bool ConfigureOrtDevice(const wchar_t *provider) {
  const wchar_t *name = L"KATAGLYPHIS_ORT_DEVICE";
  ::SetLastError(ERROR_SUCCESS);
  const DWORD size = ::GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0 && ::GetLastError() == ERROR_ENVVAR_NOT_FOUND) {
    return ::SetEnvironmentVariableW(name, provider) != 0;
  }
  if (size == 0) { return false; }
  std::wstring value(size, L'\0');
  const DWORD written = ::GetEnvironmentVariableW(name, &value[0], size);
  if (written == 0 || written >= size) { return false; }
  value.resize(written);
  return IsAllowedOrtDevice(value, provider);
}

#endif  // OMNI_ACCELERANT_ORT_DEVICE_H_
