#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fstream>
#include <string>
#include <iostream>
std::wstring value(const std::wstring& url,const std::wstring& key){auto n=url.find(key+L"=");if(n==std::wstring::npos)return L"";n+=key.size()+1;return url.substr(n,url.find(L'&',n)-n);}
int wmain(int argc,wchar_t**argv){
 if(argc!=3)return 2;std::wstring u=argv[1],root=argv[2];if(u.size()>2048||(u.rfind(L"appprivacy-fixture://callback?",0)!=0&&u.rfind(L"appprivacy-fixture://callback/?",0)!=0))return 2;
 std::ifstream input(root+L"\\expected-state.txt");std::string expected;std::getline(input,expected);std::wstring wide(expected.begin(),expected.end());
 bool bound=expected.size()==36&&value(u,L"state")==wide&&value(u,L"code")==L"mock-only";
 wchar_t locale[100]{};GetUserDefaultLocaleName(locale,100);DYNAMIC_TIME_ZONE_INFORMATION tz{};GetDynamicTimeZoneInformation(&tz);
 bool us=std::wstring(locale)==L"en-US",pacific=std::wstring(tz.TimeZoneKeyName)==L"Pacific Standard Time";
 std::ofstream output(root+L"\\callback-result.json");output<<"{\"os_protocol_callback\":true,\"state_bound\":"<<(bound?"true":"false")<<",\"native_locale_us\":"<<(us?"true":"false")<<",\"native_timezone_pacific\":"<<(pacific?"true":"false")<<",\"real_account_used\":false}";return bound?0:3;
}
