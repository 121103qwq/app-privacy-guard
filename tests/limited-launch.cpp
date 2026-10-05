#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <iostream>
#include <string>
#include <vector>

static std::wstring quote(const std::wstring& value) {
    std::wstring result=L"\"";size_t slashes=0;
    for(auto ch:value) {
        if(ch==L'\\'){++slashes;continue;}
        result.append(ch==L'"'?slashes*2+1:slashes,L'\\');slashes=0;result+=ch;
    }
    result.append(slashes*2,L'\\');return result+L"\"";
}
int wmain(int argc,wchar_t** argv) {
    if(argc<2)return 2;
    HANDLE original=nullptr,limited=nullptr;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ALL_ACCESS,&original))return 3;
    BYTE buffer[SECURITY_MAX_SID_SIZE];DWORD size=sizeof(buffer);
    if(!CreateWellKnownSid(WinBuiltinAdministratorsSid,nullptr,buffer,&size)){CloseHandle(original);return 3;}
    SID_AND_ATTRIBUTES admin{buffer,0};
    if(!CreateRestrictedToken(original,DISABLE_MAX_PRIVILEGE,1,&admin,0,nullptr,0,nullptr,&limited)){std::cerr<<"CreateRestrictedToken failed: "<<GetLastError()<<"\n";CloseHandle(original);return 4;}
    PSID medium=nullptr;
    if(!ConvertStringSidToSidW(L"S-1-16-8192",&medium)){CloseHandle(limited);CloseHandle(original);return 4;}
    TOKEN_MANDATORY_LABEL label{{medium,SE_GROUP_INTEGRITY}};
    BOOL lowered=SetTokenInformation(limited,TokenIntegrityLevel,&label,sizeof(label)+GetLengthSid(medium));
    LocalFree(medium);
    if(!lowered){std::cerr<<"Lowering token integrity failed: "<<GetLastError()<<"\n";CloseHandle(limited);CloseHandle(original);return 4;}
    // Hosts with UAC disabled can have a high-integrity desktop. Use a new hidden
    // desktop for this test rather than changing the user's desktop security.
    PSECURITY_DESCRIPTOR security=nullptr;
    if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:(A;;GA;;;AU)(A;;GA;;;SY)S:(ML;;NW;;;ME)",SDDL_REVISION_1,&security,nullptr)){CloseHandle(limited);CloseHandle(original);return 4;}
    SECURITY_ATTRIBUTES attributes{sizeof(attributes),security,FALSE};
    std::wstring stationName=L"AppPrivacyTokenTest"+std::to_wstring(GetCurrentProcessId());
    HWINSTA prior=GetProcessWindowStation();
    HWINSTA station=CreateWindowStationW(stationName.c_str(),0,WINSTA_ALL_ACCESS,&attributes);
    if(!station||!SetProcessWindowStation(station)){if(station)CloseWindowStation(station);LocalFree(security);CloseHandle(limited);CloseHandle(original);return 4;}
    HDESK desktop=CreateDesktopW(L"Default",nullptr,nullptr,0,GENERIC_ALL,&attributes);
    SetProcessWindowStation(prior);LocalFree(security);
    if(!desktop){CloseWindowStation(station);CloseHandle(limited);CloseHandle(original);return 4;}
    std::wstring command;
    for(int index=1;index<argc;++index){if(index>1)command+=L" ";command+=quote(argv[index]);}
    std::vector<wchar_t> mutableCommand(command.begin(),command.end());mutableCommand.push_back(0);
    STARTUPINFOW startup{};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESTDHANDLES;
    std::wstring desktopName=stationName+L"\\Default";startup.lpDesktop=const_cast<wchar_t*>(desktopName.c_str());
    startup.hStdInput=GetStdHandle(STD_INPUT_HANDLE);startup.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);startup.hStdError=GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION process{};
    BOOL started=CreateProcessAsUserW(limited,argv[1],mutableCommand.data(),nullptr,nullptr,TRUE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process);
    DWORD error=GetLastError();CloseHandle(limited);CloseHandle(original);
    if(!started){CloseDesktop(desktop);CloseWindowStation(station);std::cerr<<"Restricted-token process creation failed: "<<error<<"\n";return 5;}
    DWORD result=9;
    if(WaitForSingleObject(process.hProcess,30000)==WAIT_OBJECT_0)GetExitCodeProcess(process.hProcess,&result);
    else TerminateProcess(process.hProcess,9);
    CloseHandle(process.hThread);CloseHandle(process.hProcess);CloseDesktop(desktop);CloseWindowStation(station);return static_cast<int>(result);
}
