#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <winternl.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cwctype>
#include <cstring>
#include <winhttp.h>
#include "MinHook.h"

// Only the explicitly injected process is changed. No machine settings are written.
static DYNAMIC_TIME_ZONE_INFORMATION pacific{};
static volatile LONG initialized = 0;
static int mandatoryFailed = 0;
using WinHttpOpenFn = HINTERNET(WINAPI*)(LPCWSTR,DWORD,LPCWSTR,LPCWSTR,DWORD);
static WinHttpOpenFn originalHttpOpen;
static std::wstring localProxy=L"127.0.0.1:17992";
static HINTERNET WINAPI ProxyHttpOpen(LPCWSTR agent,DWORD,LPCWSTR,LPCWSTR,DWORD flags){
    return originalHttpOpen(agent,WINHTTP_ACCESS_TYPE_NAMED_PROXY,localProxy.c_str(),L"localhost;127.*;[::1]",flags);
}
using NtQueryKeyFn = NTSTATUS(NTAPI*)(HANDLE, int, PVOID, ULONG, PULONG);
static NtQueryKeyFn ntQueryKey = nullptr;

static int WINAPI UserLocaleName(LPWSTR out, int count) {
    if (!out || count < 6) { SetLastError(ERROR_INSUFFICIENT_BUFFER); return 0; }
    memcpy(out, L"en-US", 6 * sizeof(wchar_t)); return 6;
}
static LCID WINAPI DefaultLCID() { return 0x0409; }
static LANGID WINAPI DefaultLangID() { return 0x0409; }
static GEOID WINAPI UserGeoID(GEOCLASS) { return 244; }
static int WINAPI UserGeoName(LPWSTR out, int count) {
    if (!out && count == 0) return 3;
    if (!out || count < 3) { SetLastError(ERROR_INSUFFICIENT_BUFFER); return 0; }
    memcpy(out, L"US", 3 * sizeof(wchar_t)); return 3;
}
static BOOL WINAPI PreferredLanguages(DWORD flags, PULONG count, PZZWSTR out, PULONG size) {
    if (!count || !size) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
    const wchar_t* text = flags & MUI_LANGUAGE_ID ? L"0409\0" : L"en-US\0";
    ULONG needed = flags & MUI_LANGUAGE_ID ? 6 : 7;
    *count = 1;
    if (!out) { *size = needed; return TRUE; }
    if (*size < needed) { *size = needed; SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE; }
    memcpy(out, text, needed * sizeof(wchar_t)); *size = needed; return TRUE;
}
using LocaleExFn = int(WINAPI*)(LPCWSTR, LCTYPE, LPWSTR, int);
using LocaleWFn = int(WINAPI*)(LCID, LCTYPE, LPWSTR, int);
using LocaleAFn = int(WINAPI*)(LCID, LCTYPE, LPSTR, int);
static LocaleExFn originalLocaleEx;
static LocaleWFn originalLocaleW;
static LocaleAFn originalLocaleA;
static bool defaultLocale(LCID value) {
    return value == LOCALE_USER_DEFAULT || value == LOCALE_SYSTEM_DEFAULT || value == LOCALE_NEUTRAL;
}
static int WINAPI LocaleEx(LPCWSTR name, LCTYPE type, LPWSTR data, int count) {
    bool isDefault = !name || !*name || name == LOCALE_NAME_SYSTEM_DEFAULT;
    if (name && !isDefault) isDefault = !wcscmp(name, LOCALE_NAME_SYSTEM_DEFAULT);
    return originalLocaleEx(isDefault ? L"en-US" : name, type | (isDefault ? LOCALE_NOUSEROVERRIDE : 0), data, count);
}
static int WINAPI LocaleW(LCID locale, LCTYPE type, LPWSTR data, int count) {
    bool isDefault = defaultLocale(locale);
    return originalLocaleW(isDefault ? 0x0409 : locale, type | (isDefault ? LOCALE_NOUSEROVERRIDE : 0), data, count);
}
static int WINAPI LocaleA(LCID locale, LCTYPE type, LPSTR data, int count) {
    bool isDefault = defaultLocale(locale);
    return originalLocaleA(isDefault ? 0x0409 : locale, type | (isDefault ? LOCALE_NOUSEROVERRIDE : 0), data, count);
}

static LONG currentBias() {
    SYSTEMTIME utc{}, local{};
    GetSystemTime(&utc);
    if (!SystemTimeToTzSpecificLocalTimeEx(&pacific, &utc, &local)) return pacific.Bias;
    FILETIME utcFile{}, localFile{};
    SystemTimeToFileTime(&utc, &utcFile); SystemTimeToFileTime(&local, &localFile);
    ULARGE_INTEGER u{}, l{};
    u.LowPart = utcFile.dwLowDateTime; u.HighPart = utcFile.dwHighDateTime;
    l.LowPart = localFile.dwLowDateTime; l.HighPart = localFile.dwHighDateTime;
    return static_cast<LONG>((static_cast<LONGLONG>(u.QuadPart) - static_cast<LONGLONG>(l.QuadPart)) / 600000000LL);
}
static DWORD zoneState() { return currentBias() == pacific.Bias + pacific.DaylightBias ? TIME_ZONE_ID_DAYLIGHT : TIME_ZONE_ID_STANDARD; }
static DWORD WINAPI DynamicZone(PDYNAMIC_TIME_ZONE_INFORMATION out) {
    if (!out) { SetLastError(ERROR_INVALID_PARAMETER); return TIME_ZONE_ID_INVALID; }
    *out = pacific; return zoneState();
}
static DWORD WINAPI Zone(LPTIME_ZONE_INFORMATION out) {
    if (!out) { SetLastError(ERROR_INVALID_PARAMETER); return TIME_ZONE_ID_INVALID; }
    memcpy(out, &pacific, sizeof(TIME_ZONE_INFORMATION)); return zoneState();
}
static void WINAPI LocalTime(LPSYSTEMTIME out) {
    SYSTEMTIME utc{}; GetSystemTime(&utc); SystemTimeToTzSpecificLocalTimeEx(&pacific, &utc, out);
}
using ConvertFn = BOOL(WINAPI*)(const TIME_ZONE_INFORMATION*, const SYSTEMTIME*, LPSYSTEMTIME);
using ConvertExFn = BOOL(WINAPI*)(const DYNAMIC_TIME_ZONE_INFORMATION*, const SYSTEMTIME*, LPSYSTEMTIME);
using ZoneYearFn = BOOL(WINAPI*)(USHORT, PDYNAMIC_TIME_ZONE_INFORMATION, LPTIME_ZONE_INFORMATION);
static ConvertFn originalToLocal, originalToUTC;
static ConvertExFn originalToLocalEx, originalToUTCEx;
static ZoneYearFn originalZoneYear;
static BOOL WINAPI ToLocal(const TIME_ZONE_INFORMATION* zone, const SYSTEMTIME* value, LPSYSTEMTIME out) {
    return originalToLocal(zone ? zone : reinterpret_cast<TIME_ZONE_INFORMATION*>(&pacific), value, out);
}
static BOOL WINAPI ToUTC(const TIME_ZONE_INFORMATION* zone, const SYSTEMTIME* value, LPSYSTEMTIME out) {
    return originalToUTC(zone ? zone : reinterpret_cast<TIME_ZONE_INFORMATION*>(&pacific), value, out);
}
static BOOL WINAPI ToLocalEx(const DYNAMIC_TIME_ZONE_INFORMATION* zone, const SYSTEMTIME* value, LPSYSTEMTIME out) {
    return originalToLocalEx(zone ? zone : &pacific, value, out);
}
static BOOL WINAPI ToUTCEx(const DYNAMIC_TIME_ZONE_INFORMATION* zone, const SYSTEMTIME* value, LPSYSTEMTIME out) {
    return originalToUTCEx(zone ? zone : &pacific, value, out);
}
static BOOL WINAPI ZoneYear(USHORT year, PDYNAMIC_TIME_ZONE_INFORMATION zone, LPTIME_ZONE_INFORMATION out) {
    return originalZoneYear(year, zone ? zone : &pacific, out);
}

struct Value { DWORD type = 0; std::vector<BYTE> bytes; };
static Value textValue(const wchar_t* text, bool ansi) {
    Value v; v.type = REG_SZ;
    if (ansi) {
        int count = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
        v.bytes.resize(count); WideCharToMultiByte(CP_UTF8, 0, text, -1, reinterpret_cast<char*>(v.bytes.data()), count, nullptr, nullptr);
    } else {
        auto size = (wcslen(text) + 1) * sizeof(wchar_t); v.bytes.resize(size); memcpy(v.bytes.data(), text, size);
    }
    return v;
}
static Value numberValue(DWORD number) {
    Value v; v.type = REG_DWORD; v.bytes.resize(4); memcpy(v.bytes.data(), &number, 4); return v;
}
static std::wstring keyName(HKEY key) {
    if (!ntQueryKey) return {};
    ULONG needed = 0; ntQueryKey(key, 3, nullptr, 0, &needed);
    if (needed < 4 || needed > 16384) return {};
    std::vector<BYTE> data(needed + 2);
    if (ntQueryKey(key, 3, data.data(), needed, &needed) < 0) return {};
    auto chars = *reinterpret_cast<ULONG*>(data.data()) / sizeof(wchar_t);
    std::wstring result(reinterpret_cast<wchar_t*>(data.data() + 4), chars);
    std::transform(result.begin(), result.end(), result.begin(), towlower); return result;
}
static Value virtualValue(HKEY key, const wchar_t* value, bool ansi) {
    if (!value) return {};
    auto name = keyName(key); std::wstring requested(value);
    std::transform(requested.begin(), requested.end(), requested.begin(), towlower);
    auto ends = [&](const wchar_t* suffix) { auto len = wcslen(suffix); return name.size() >= len && name.compare(name.size() - len, len, suffix) == 0; };
    if (ends(L"\\control panel\\international")) {
        const std::pair<const wchar_t*, const wchar_t*> values[] = {
            {L"localename",L"en-US"},{L"locale",L"00000409"},{L"scountry",L"United States"},
            {L"slanguage",L"ENU"},{L"icountry",L"1"},{L"sshortdate",L"M/d/yyyy"},
            {L"slongdate",L"dddd, MMMM d, yyyy"},{L"stimeformat",L"h:mm:ss tt"},
            {L"s1159",L"AM"},{L"s2359",L"PM"},{L"sdate",L"/"},{L"stime",L":"},
            {L"imeasure",L"1"},{L"ifirstdayofweek",L"6"}
        };
        for (auto& item : values) if (requested == item.first) return textValue(item.second, ansi);
    }
    if (ends(L"\\control panel\\international\\geo")) {
        if (requested == L"name") return textValue(L"US", ansi);
        if (requested == L"nation") return textValue(L"244", ansi);
    }
    if (ends(L"\\control\\timezoneinformation")) {
        if (requested == L"timezonekeyname" || requested == L"standardname") return textValue(L"Pacific Standard Time", ansi);
        if (requested == L"daylightname") return textValue(L"Pacific Daylight Time", ansi);
        if (requested == L"bias") return numberValue(480);
        if (requested == L"activetimebias") return numberValue(currentBias());
        if (requested == L"standardbias" || requested == L"dynamicdaylighttimedisabled") return numberValue(0);
        if (requested == L"daylightbias") return numberValue(static_cast<DWORD>(-60));
    }
    return {};
}
static LSTATUS copyValue(const Value& value, LPDWORD type, LPBYTE data, LPDWORD size) {
    if (!size) return ERROR_INVALID_PARAMETER;
    if (type) *type = value.type;
    DWORD available = *size; *size = static_cast<DWORD>(value.bytes.size());
    if (!data) return ERROR_SUCCESS;
    if (available < value.bytes.size()) return ERROR_MORE_DATA;
    memcpy(data, value.bytes.data(), value.bytes.size()); return ERROR_SUCCESS;
}
using QueryWFn = LSTATUS(WINAPI*)(HKEY, LPCWSTR, LPDWORD, LPDWORD, LPBYTE, LPDWORD);
using QueryAFn = LSTATUS(WINAPI*)(HKEY, LPCSTR, LPDWORD, LPDWORD, LPBYTE, LPDWORD);
static QueryWFn originalQueryW;
static QueryAFn originalQueryA;
static LSTATUS WINAPI QueryW(HKEY key, LPCWSTR name, LPDWORD reserved, LPDWORD type, LPBYTE data, LPDWORD size) {
    auto value = virtualValue(key, name, false);
    return value.type ? copyValue(value, type, data, size) : originalQueryW(key, name, reserved, type, data, size);
}
static LSTATUS WINAPI QueryA(HKEY key, LPCSTR name, LPDWORD reserved, LPDWORD type, LPBYTE data, LPDWORD size) {
    std::wstring wide;
    if (name) { for (auto p = name; *p; ++p) wide += static_cast<unsigned char>(*p); }
    auto value = virtualValue(key, wide.c_str(), true);
    return value.type ? copyValue(value, type, data, size) : originalQueryA(key, name, reserved, type, data, size);
}
using GetValueWFn = LSTATUS(WINAPI*)(HKEY, LPCWSTR, LPCWSTR, DWORD, LPDWORD, PVOID, LPDWORD);
using GetValueAFn = LSTATUS(WINAPI*)(HKEY, LPCSTR, LPCSTR, DWORD, LPDWORD, PVOID, LPDWORD);
static GetValueWFn originalGetValueW;
static GetValueAFn originalGetValueA;
static LSTATUS WINAPI GetValueW(HKEY key, LPCWSTR subkey, LPCWSTR name, DWORD flags, LPDWORD type, PVOID data, LPDWORD size) {
    HKEY opened = key;
    if (subkey && *subkey && RegOpenKeyExW(key, subkey, 0, KEY_QUERY_VALUE, &opened) != ERROR_SUCCESS) return originalGetValueW(key, subkey, name, flags, type, data, size);
    auto value = virtualValue(opened, name, false); if (opened != key) RegCloseKey(opened);
    return value.type ? copyValue(value, type, static_cast<BYTE*>(data), size) : originalGetValueW(key, subkey, name, flags, type, data, size);
}
static LSTATUS WINAPI GetValueA(HKEY key, LPCSTR subkey, LPCSTR name, DWORD flags, LPDWORD type, PVOID data, LPDWORD size) {
    HKEY opened = key;
    if (subkey && *subkey && RegOpenKeyExA(key, subkey, 0, KEY_QUERY_VALUE, &opened) != ERROR_SUCCESS) return originalGetValueA(key, subkey, name, flags, type, data, size);
    std::wstring wide; if (name) for (auto p = name; *p; ++p) wide += static_cast<unsigned char>(*p);
    auto value = virtualValue(opened, wide.c_str(), true); if (opened != key) RegCloseKey(opened);
    return value.type ? copyValue(value, type, static_cast<BYTE*>(data), size) : originalGetValueA(key, subkey, name, flags, type, data, size);
}

static void hook(const wchar_t* module, const char* api, LPVOID replacement, LPVOID* original = nullptr, bool mandatory = true) {
    auto result = MH_CreateHookApi(module, api, replacement, original);
    if (result != MH_OK && mandatory) ++mandatoryFailed;
}
extern "C" __declspec(dllexport) DWORD WINAPI PrivacyInit(LPVOID) {
    if (InterlockedCompareExchange(&initialized, 1, 0)) return 0;
    wchar_t proxy[100]{};
    if(GetEnvironmentVariableW(L"HTTP_PROXY",proxy,100)){
        const std::wstring value(proxy),prefix=L"http://127.0.0.1:";
        if(value.rfind(prefix,0)!=0)return 104;
        const auto number=value.substr(prefix.size());
        if(number.empty()||number.size()>5||number.find_first_not_of(L"0123456789")!=std::wstring::npos)return 104;
        const int port=_wtoi(number.c_str());if(port<1||port>65535)return 104;
        localProxy=L"127.0.0.1:"+std::to_wstring(port);
    }
    bool found = false;
    for (DWORD index = 0; index < 1000; ++index) {
        DYNAMIC_TIME_ZONE_INFORMATION item{};
        if (EnumDynamicTimeZoneInformation(index, &item) != ERROR_SUCCESS) break;
        if (!wcscmp(item.TimeZoneKeyName, L"Pacific Standard Time")) { pacific = item; found = true; break; }
    }
    if (!found) return 101;
    wcscpy_s(pacific.StandardName, L"Pacific Standard Time"); wcscpy_s(pacific.DaylightName, L"Pacific Daylight Time");
    pacific.DynamicDaylightTimeDisabled = FALSE;
    ntQueryKey = reinterpret_cast<NtQueryKeyFn>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryKey"));
    if (!ntQueryKey || MH_Initialize() != MH_OK) return 102;
    hook(L"kernel32.dll", "GetUserDefaultLocaleName", reinterpret_cast<LPVOID>(UserLocaleName));
    hook(L"kernel32.dll", "GetSystemDefaultLocaleName", reinterpret_cast<LPVOID>(UserLocaleName));
    for (auto api : {"GetUserDefaultLCID", "GetSystemDefaultLCID", "GetThreadLocale"}) hook(L"kernel32.dll", api, reinterpret_cast<LPVOID>(DefaultLCID));
    for (auto api : {"GetUserDefaultLangID", "GetSystemDefaultLangID", "GetUserDefaultUILanguage", "GetSystemDefaultUILanguage", "GetThreadUILanguage"}) hook(L"kernel32.dll", api, reinterpret_cast<LPVOID>(DefaultLangID));
    hook(L"kernel32.dll", "GetUserGeoID", reinterpret_cast<LPVOID>(UserGeoID));
    hook(L"kernel32.dll", "GetUserDefaultGeoName", reinterpret_cast<LPVOID>(UserGeoName), nullptr, false);
    for (auto api : {"GetUserPreferredUILanguages", "GetSystemPreferredUILanguages", "GetThreadPreferredUILanguages"}) hook(L"kernel32.dll", api, reinterpret_cast<LPVOID>(PreferredLanguages), nullptr, false);
    hook(L"kernel32.dll", "GetLocaleInfoEx", reinterpret_cast<LPVOID>(LocaleEx), reinterpret_cast<LPVOID*>(&originalLocaleEx));
    hook(L"kernel32.dll", "GetLocaleInfoW", reinterpret_cast<LPVOID>(LocaleW), reinterpret_cast<LPVOID*>(&originalLocaleW));
    hook(L"kernel32.dll", "GetLocaleInfoA", reinterpret_cast<LPVOID>(LocaleA), reinterpret_cast<LPVOID*>(&originalLocaleA));
    hook(L"kernel32.dll", "GetDynamicTimeZoneInformation", reinterpret_cast<LPVOID>(DynamicZone));
    hook(L"kernel32.dll", "GetTimeZoneInformation", reinterpret_cast<LPVOID>(Zone));
    hook(L"kernel32.dll", "GetLocalTime", reinterpret_cast<LPVOID>(LocalTime));
    hook(L"kernel32.dll", "SystemTimeToTzSpecificLocalTime", reinterpret_cast<LPVOID>(ToLocal), reinterpret_cast<LPVOID*>(&originalToLocal));
    hook(L"kernel32.dll", "TzSpecificLocalTimeToSystemTime", reinterpret_cast<LPVOID>(ToUTC), reinterpret_cast<LPVOID*>(&originalToUTC));
    hook(L"kernel32.dll", "SystemTimeToTzSpecificLocalTimeEx", reinterpret_cast<LPVOID>(ToLocalEx), reinterpret_cast<LPVOID*>(&originalToLocalEx));
    hook(L"kernel32.dll", "TzSpecificLocalTimeToSystemTimeEx", reinterpret_cast<LPVOID>(ToUTCEx), reinterpret_cast<LPVOID*>(&originalToUTCEx));
    hook(L"kernel32.dll", "GetTimeZoneInformationForYear", reinterpret_cast<LPVOID>(ZoneYear), reinterpret_cast<LPVOID*>(&originalZoneYear));
    LoadLibraryW(L"advapi32.dll");
    hook(L"advapi32.dll", "RegQueryValueExW", reinterpret_cast<LPVOID>(QueryW), reinterpret_cast<LPVOID*>(&originalQueryW));
    hook(L"advapi32.dll", "RegQueryValueExA", reinterpret_cast<LPVOID>(QueryA), reinterpret_cast<LPVOID*>(&originalQueryA));
    hook(L"advapi32.dll", "RegGetValueW", reinterpret_cast<LPVOID>(GetValueW), reinterpret_cast<LPVOID*>(&originalGetValueW));
    hook(L"advapi32.dll", "RegGetValueA", reinterpret_cast<LPVOID>(GetValueA), reinterpret_cast<LPVOID*>(&originalGetValueA));
    LoadLibraryW(L"winhttp.dll");
    hook(L"winhttp.dll","WinHttpOpen",reinterpret_cast<LPVOID>(ProxyHttpOpen),reinterpret_cast<LPVOID*>(&originalHttpOpen));
    if (mandatoryFailed) { MH_Uninitialize(); return 200 + mandatoryFailed; }
    if (MH_EnableHook(MH_ALL_HOOKS) != MH_OK) return 103;
    return 0;
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(module);
    return TRUE;
}
