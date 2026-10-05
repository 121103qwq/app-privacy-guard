#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <iostream>
#include <string>

static std::string utf8(const wchar_t* value) {
    int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    std::string text(count, 0); WideCharToMultiByte(CP_UTF8, 0, value, -1, text.data(), count, nullptr, nullptr); text.resize(count - 1); return text;
}
static std::string registry(HKEY hive, const wchar_t* subkey, const wchar_t* name) {
    wchar_t value[300]{}; DWORD size = sizeof(value), type = 0; HKEY key{};
    if (RegOpenKeyExW(hive, subkey, 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) return "missing";
    auto status = RegQueryValueExW(key, name, nullptr, &type, reinterpret_cast<BYTE*>(value), &size); RegCloseKey(key);
    return status == ERROR_SUCCESS ? utf8(value) : "error";
}
int main() {
    wchar_t locale[100]{}, systemLocale[100]{}, geo[100]{}, proxy[200]{};
    GetEnvironmentVariableW(L"HTTP_PROXY", proxy, 200);
    GetUserDefaultLocaleName(locale, 100); GetSystemDefaultLocaleName(systemLocale, 100);
    using GeoNameFn = int(WINAPI*)(LPWSTR,int);
    auto geoName = reinterpret_cast<GeoNameFn>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"GetUserDefaultGeoName"));
    if(geoName) geoName(geo,100);
    DYNAMIC_TIME_ZONE_INFORMATION zone{}; auto state = GetDynamicTimeZoneInformation(&zone);
    SYSTEMTIME local{}, winter{2026,1,0,15,12,0,0,0}, summer{2026,7,0,15,12,0,0,0}, win{}, sum{};
    GetLocalTime(&local); SystemTimeToTzSpecificLocalTimeEx(nullptr, &winter, &win); SystemTimeToTzSpecificLocalTimeEx(nullptr, &summer, &sum);
    std::cout << "{\"proxy\":\"" << utf8(proxy) << "\",\"userLocale\":\"" << utf8(locale) << "\",\"systemLocale\":\"" << utf8(systemLocale)
        << "\",\"geo\":\"" << utf8(geo) << "\",\"lcid\":" << GetUserDefaultLCID()
        << ",\"timezone\":\"" << utf8(zone.TimeZoneKeyName) << "\",\"zoneState\":" << state
        << ",\"baseBias\":" << zone.Bias << ",\"localHour\":" << local.wHour
        << ",\"winterHour\":" << win.wHour << ",\"summerHour\":" << sum.wHour
        << ",\"registryLocale\":\"" << registry(HKEY_CURRENT_USER,L"Control Panel\\International",L"LocaleName")
        << "\",\"registryGeo\":\"" << registry(HKEY_CURRENT_USER,L"Control Panel\\International\\Geo",L"Name")
        << "\",\"registryTimezone\":\"" << registry(HKEY_LOCAL_MACHINE,L"SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation",L"TimeZoneKeyName") << "\"}\n";
}
