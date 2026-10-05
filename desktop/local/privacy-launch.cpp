#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <string>
#include <vector>
#include <iostream>
static bool debugging=false;
static void continueEvent(DEBUG_EVENT& event){
    if(event.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT&&event.u.CreateProcessInfo.hFile)CloseHandle(event.u.CreateProcessInfo.hFile);
    if(event.dwDebugEventCode==LOAD_DLL_DEBUG_EVENT&&event.u.LoadDll.hFile)CloseHandle(event.u.LoadDll.hFile);
    DWORD handled=DBG_CONTINUE;
    if(event.dwDebugEventCode==EXCEPTION_DEBUG_EVENT&&event.u.Exception.ExceptionRecord.ExceptionCode!=EXCEPTION_BREAKPOINT)handled=DBG_EXCEPTION_NOT_HANDLED;
    ContinueDebugEvent(event.dwProcessId,event.dwThreadId,handled);
}

static std::wstring quote(const std::wstring& value) {
    std::wstring result = L"\""; size_t slashes = 0;
    for (auto ch : value) {
        if (ch == L'\\') { ++slashes; continue; }
        if (ch == L'\"') result.append(slashes * 2 + 1, L'\\'); else result.append(slashes, L'\\');
        slashes = 0; result += ch;
    }
    result.append(slashes * 2, L'\\'); return result + L"\"";
}
static bool remoteCall(HANDLE process, LPTHREAD_START_ROUTINE function, LPVOID parameter, DWORD& result) {
    auto thread = CreateRemoteThread(process, nullptr, 0, function, parameter, 0, nullptr);
    if (!thread) return false;
    DWORD started=GetTickCount();
    while(WaitForSingleObject(thread,0)==WAIT_TIMEOUT&&GetTickCount()-started<15000){
        if(debugging){DEBUG_EVENT event{};if(WaitForDebugEvent(&event,100))continueEvent(event);}
        else Sleep(10);
    }
    bool ok = WaitForSingleObject(thread,0)==WAIT_OBJECT_0&&GetExitCodeThread(thread,&result);
    CloseHandle(thread); return ok;
}
static bool inject(PROCESS_INFORMATION& process, const std::wstring& path) {
    size_t size = (path.size() + 1) * sizeof(wchar_t);
    auto memory = VirtualAllocEx(process.hProcess, nullptr, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!memory) return false;
    DWORD result = 0;
    bool loaded = WriteProcessMemory(process.hProcess, memory, path.c_str(), size, nullptr) &&
        remoteCall(process.hProcess, reinterpret_cast<LPTHREAD_START_ROUTINE>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW")), memory, result);
    VirtualFreeEx(process.hProcess, memory, 0, MEM_RELEASE);
    if (!loaded) return false;
    auto modules = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, process.dwProcessId);
    if (modules == INVALID_HANDLE_VALUE) return false;
    MODULEENTRY32W item{}; item.dwSize = sizeof(item); uintptr_t remoteBase = 0;
    if (Module32FirstW(modules, &item)) do {
        if (!_wcsicmp(item.szExePath, path.c_str())) { remoteBase = reinterpret_cast<uintptr_t>(item.modBaseAddr); break; }
    } while (Module32NextW(modules, &item));
    CloseHandle(modules);
    if (!remoteBase) return false;
    auto localModule = LoadLibraryExW(path.c_str(), nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!localModule) return false;
    auto init = reinterpret_cast<uintptr_t>(GetProcAddress(localModule, "PrivacyInit"));
    auto remoteInit = reinterpret_cast<LPTHREAD_START_ROUTINE>(remoteBase + init - reinterpret_cast<uintptr_t>(localModule));
    bool initialized = init && remoteCall(process.hProcess, remoteInit, nullptr, result) && result == 0;
    FreeLibrary(localModule);
    if (!initialized) std::cerr << "Locale initialization failed: " << result << "\n";
    return initialized;
}
static bool networkReady(const std::wstring& folder, const wchar_t* target) {
    std::wstring helper=folder+L"\\network-guard.exe";
    std::wstring command=quote(helper)+L" check "+quote(target);
    std::vector<wchar_t> mutableCommand(command.begin(),command.end());mutableCommand.push_back(0);
    SECURITY_ATTRIBUTES attributes{sizeof(attributes),nullptr,TRUE};
    HANDLE nullOutput=CreateFileW(L"NUL",GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&attributes,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    STARTUPINFOW startup{};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESTDHANDLES;
    startup.hStdInput=GetStdHandle(STD_INPUT_HANDLE);startup.hStdOutput=nullOutput;startup.hStdError=nullOutput;
    PROCESS_INFORMATION child{};
    bool started=CreateProcessW(helper.c_str(),mutableCommand.data(),nullptr,nullptr,TRUE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&child);
    DWORD result=1;
    if(started){if(WaitForSingleObject(child.hProcess,10000)==WAIT_OBJECT_0)GetExitCodeProcess(child.hProcess,&result);else TerminateProcess(child.hProcess,9);CloseHandle(child.hThread);CloseHandle(child.hProcess);}
    CloseHandle(nullOutput);return started&&result==0;
}
int wmain(int argc, wchar_t** argv) {
    if (argc < 2) { std::cerr << "usage: privacy-launch.exe PROGRAM [arguments...]\n"; return 2; }
    wchar_t self[MAX_PATH]; GetModuleFileNameW(nullptr, self, MAX_PATH);
    std::wstring folder(self); folder=folder.substr(0,folder.find_last_of(L"\\/"));std::wstring path=folder+L"\\locale-shim.dll";
    int first=1;bool intercepted=true;
    if(argc>2&&!wcscmp(argv[1],L"--ifeo")){intercepted=true;first=2;}
    if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) { std::cerr << "Locale module missing; program not started.\n"; return 3; }
    if(!networkReady(folder,argv[first])){std::cerr<<"Target has no verified IPv4/IPv6 guard; program not started. Run setup.ps1 as administrator.\n";return 6;}
    SetEnvironmentVariableW(L"TZ", L"America/Los_Angeles");
    SetEnvironmentVariableW(L"LANG", L"en_US.UTF-8"); SetEnvironmentVariableW(L"LC_ALL", L"en_US.UTF-8");
    SetEnvironmentVariableW(L"HTTP_PROXY", L"http://127.0.0.1:17992"); SetEnvironmentVariableW(L"HTTPS_PROXY", L"http://127.0.0.1:17992");
    SetEnvironmentVariableW(L"ALL_PROXY", L"http://127.0.0.1:17992"); SetEnvironmentVariableW(L"NO_PROXY", L"localhost,127.0.0.1,::1");
    SetEnvironmentVariableW(L"NODE_USE_ENV_PROXY", L"1");
    std::wstring command;
    for (int index = first; index < argc; ++index) { if (index != first) command += L" "; command += quote(argv[index]); }
    if(std::wstring(argv[first]).find(L"WindowsApps")!=std::wstring::npos)command+=L" --lang=en-US --proxy-server=http://127.0.0.1:17992";
    STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
    std::vector<wchar_t> mutableCommand(command.begin(), command.end()); mutableCommand.push_back(0);
    if (!CreateProcessW(argv[first], mutableCommand.data(), nullptr, nullptr, TRUE, CREATE_SUSPENDED|(intercepted?DEBUG_ONLY_THIS_PROCESS:0), nullptr, nullptr, &startup, &process)) {
        std::cerr << "Cannot start target: " << GetLastError() << "\n"; return 4;
    }
    if(intercepted){
        DebugSetProcessKillOnExit(FALSE);DEBUG_EVENT event{};
        bool ready=false;ResumeThread(process.hThread);
        if(WaitForDebugEvent(&event,10000)){
            SuspendThread(process.hThread);continueEvent(event);ready=true;debugging=true;
        }
        if(!ready){TerminateProcess(process.hProcess,7);CloseHandle(process.hThread);CloseHandle(process.hProcess);std::cerr<<"Cannot safely establish startup debugger; target stopped.\n";return 7;}
    }
    if (!inject(process, path)) {
        TerminateProcess(process.hProcess, 5); CloseHandle(process.hThread); CloseHandle(process.hProcess);
        std::cerr << "Locale injection failed; suspended target was terminated.\n"; return 5;
    }
    if(debugging){if(!DebugActiveProcessStop(process.dwProcessId)){TerminateProcess(process.hProcess,7);CloseHandle(process.hThread);CloseHandle(process.hProcess);return 7;}debugging=false;}
    ResumeThread(process.hThread); CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE); DWORD exit = 0; GetExitCodeProcess(process.hProcess, &exit); CloseHandle(process.hProcess);
    return static_cast<int>(exit);
}
