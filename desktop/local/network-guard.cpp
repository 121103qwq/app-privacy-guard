#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <iostream>
#include <string>
#include <cwctype>
#include <cstring>
#include <vector>

// Independent WFP filters: Windows Defender Firewall profiles remain untouched.
static const GUID providerKey = {0x6dda9049,0x2ac6,0x4382,{0xb7,0x35,0x83,0x65,0x47,0xc8,0x88,0xf1}};
static const GUID layerKey = {0x6dda9049,0x2ac6,0x4382,{0xb7,0x35,0x83,0x65,0x47,0xc8,0x88,0xf2}};
static GUID filterKey(std::wstring path, int family) {
    unsigned long long a=1469598103934665603ULL, b=1099511628211ULL;
    for (auto ch:path) { auto c=static_cast<unsigned>(towlower(ch)); a=(a^c)*1099511628211ULL; b=(b^(c+71))*1469598103934665603ULL; }
    a ^= family; b ^= static_cast<unsigned long long>(family) << 32;
    GUID result; memcpy(&result,&a,8); memcpy(reinterpret_cast<BYTE*>(&result)+8,&b,8); return result;
}
static DWORD ensureProvider(HANDLE engine) {
    FWPM_PROVIDER0 provider{}; provider.providerKey=providerKey; provider.flags=FWPM_PROVIDER_FLAG_PERSISTENT;
    provider.displayData.name=const_cast<wchar_t*>(L"App Privacy Guard");
    DWORD status=FwpmProviderAdd0(engine,&provider,nullptr);
    if(status!=ERROR_SUCCESS && status!=FWP_E_ALREADY_EXISTS) return status;
    FWPM_SUBLAYER0 layer{}; layer.subLayerKey=layerKey; layer.providerKey=const_cast<GUID*>(&providerKey);
    layer.flags=FWPM_SUBLAYER_FLAG_PERSISTENT; layer.weight=0xffff;
    layer.displayData.name=const_cast<wchar_t*>(L"App Privacy Guard: selected executables only");
    status=FwpmSubLayerAdd0(engine,&layer,nullptr);
    return status==FWP_E_ALREADY_EXISTS?ERROR_SUCCESS:status;
}
static DWORD apply(HANDLE engine,const std::wstring& path,int family,const std::wstring& mode) {
    auto id=filterKey(path,family);
    FWPM_FILTER0* existing=nullptr;
    DWORD status=FwpmFilterGetByKey0(engine,&id,&existing);
    if(mode==L"check") { if(existing)FwpmFreeMemory0(reinterpret_cast<void**>(&existing)); return status; }
    if(mode==L"remove") { if(existing)FwpmFreeMemory0(reinterpret_cast<void**>(&existing)); return status==FWP_E_FILTER_NOT_FOUND?0:FwpmFilterDeleteByKey0(engine,&id); }
    if(existing){ FwpmFreeMemory0(reinterpret_cast<void**>(&existing)); return 0; }
    FWP_BYTE_BLOB* app=nullptr;
    status=FwpmGetAppIdFromFileName0(path.c_str(),&app); if(status)return status;
    FWPM_FILTER_CONDITION0 conditions[2]{};
    conditions[0].fieldKey=FWPM_CONDITION_ALE_APP_ID; conditions[0].matchType=FWP_MATCH_EQUAL;
    conditions[0].conditionValue.type=FWP_BYTE_BLOB_TYPE; conditions[0].conditionValue.byteBlob=app;
    conditions[1].fieldKey=FWPM_CONDITION_FLAGS; conditions[1].matchType=FWP_MATCH_FLAGS_NONE_SET;
    conditions[1].conditionValue.type=FWP_UINT32; conditions[1].conditionValue.uint32=FWP_CONDITION_FLAG_IS_LOOPBACK;
    FWPM_FILTER0 filter{}; filter.filterKey=id; filter.providerKey=const_cast<GUID*>(&providerKey);
    filter.displayData.name=const_cast<wchar_t*>(L"App Privacy Guard: deny non-loopback outbound");
    filter.subLayerKey=layerKey; filter.layerKey=family==4?FWPM_LAYER_ALE_AUTH_CONNECT_V4:FWPM_LAYER_ALE_AUTH_CONNECT_V6;
    filter.flags=FWPM_FILTER_FLAG_PERSISTENT|FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT;
    UINT64 weight=0xffffffffffffffffULL; filter.weight.type=FWP_UINT64; filter.weight.uint64=&weight;
    filter.action.type=FWP_ACTION_BLOCK; filter.numFilterConditions=2; filter.filterCondition=conditions;
    UINT64 added=0; status=FwpmFilterAdd0(engine,&filter,nullptr,&added); FwpmFreeMemory0(reinterpret_cast<void**>(&app)); return status;
}
int wmain(int argc,wchar_t** argv) {
    if(argc<3){std::cerr<<"usage: network-guard.exe install|check|inspect|remove PROGRAM [PROGRAM...]\n";return 2;}
    std::wstring mode=argv[1]; if(mode!=L"install"&&mode!=L"check"&&mode!=L"remove"&&mode!=L"observe"&&mode!=L"inspect")return 2;
    FWPM_SESSION0 session{}; session.displayData.name=const_cast<wchar_t*>(L"App Privacy Guard management");
    HANDLE engine=nullptr; DWORD status=FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,&session,&engine);
    if(status){std::cerr<<"WFP open failed: "<<status<<"\n";return 3;}
    if(mode==L"inspect") {
        if(argc!=3){FwpmEngineClose0(engine);return 2;}
        wchar_t absolute[32768]{};if(!GetFullPathNameW(argv[2],32768,absolute,nullptr)){FwpmEngineClose0(engine);return 2;}
        bool found[2]{};
        for(int family:{4,6}) {auto id=filterKey(absolute,family);FWPM_FILTER0* item=nullptr;DWORD got=FwpmFilterGetByKey0(engine,&id,&item);if(got&&got!=FWP_E_FILTER_NOT_FOUND){FwpmEngineClose0(engine);return 5;}found[family==4?0:1]=got==0;if(item)FwpmFreeMemory0(reinterpret_cast<void**>(&item));}
        FwpmEngineClose0(engine);std::cout<<"{\"ipv4\":"<<(found[0]?"true":"false")<<",\"ipv6\":"<<(found[1]?"true":"false")<<"}\n";return 0;
    }
    if(mode==L"observe"){
        FWP_VALUE0* oldOption=nullptr;status=FwpmEngineGetOption0(engine,FWPM_ENGINE_COLLECT_NET_EVENTS,&oldOption);
        if(status){FwpmEngineClose0(engine);return 6;}
        FWP_VALUE0 enabled{};enabled.type=FWP_UINT32;enabled.uint32=1;
        status=FwpmEngineSetOption0(engine,FWPM_ENGINE_COLLECT_NET_EVENTS,&enabled);
        if(status){FwpmFreeMemory0(reinterpret_cast<void**>(&oldOption));FwpmEngineClose0(engine);return 6;}
        wchar_t absolute[32768]{};GetFullPathNameW(argv[2],32768,absolute,nullptr);
        UINT64 ids[2]{};
        for(int family:{4,6}){auto id=filterKey(absolute,family);FWPM_FILTER0* item=nullptr;if(!FwpmFilterGetByKey0(engine,&id,&item)){ids[family==4?0:1]=item->filterId;FwpmFreeMemory0(reinterpret_cast<void**>(&item));}}
        FILETIME started{};GetSystemTimeAsFileTime(&started);
        std::wstring command=L"\""+std::wstring(absolute)+L"\" "+(argc>3?argv[3]:L"udp");
        std::vector<wchar_t> mutableCommand(command.begin(),command.end());mutableCommand.push_back(0);
        STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION child{};
        bool ran=CreateProcessW(absolute,mutableCommand.data(),nullptr,nullptr,TRUE,0,nullptr,nullptr,&startup,&child);
        if(ran){WaitForSingleObject(child.hProcess,12000);CloseHandle(child.hThread);CloseHandle(child.hProcess);Sleep(250);}
        FWPM_NET_EVENT_ENUM_TEMPLATE0 query{};query.startTime=started;GetSystemTimeAsFileTime(&query.endTime);
        HANDLE enumeration=nullptr;UINT32 count=0;FWPM_NET_EVENT0** events=nullptr;int drops=0,udpDrops=0,v6Drops=0;
        if(!FwpmNetEventCreateEnumHandle0(engine,&query,&enumeration)){
            if(!FwpmNetEventEnum0(engine,enumeration,1000,&events,&count)){
                for(UINT32 index=0;index<count;++index){auto item=events[index];if(item->type==FWPM_NET_EVENT_TYPE_CLASSIFY_DROP&&item->classifyDrop&&(item->classifyDrop->filterId==ids[0]||item->classifyDrop->filterId==ids[1])){++drops;if(item->header.ipProtocol==17)++udpDrops;if(item->classifyDrop->filterId==ids[1])++v6Drops;}}
                FwpmFreeMemory0(reinterpret_cast<void**>(&events));
            }
            FwpmNetEventDestroyEnumHandle0(engine,enumeration);
        }
        DWORD restored=FwpmEngineSetOption0(engine,FWPM_ENGINE_COLLECT_NET_EVENTS,oldOption);FwpmFreeMemory0(reinterpret_cast<void**>(&oldOption));FwpmEngineClose0(engine);
        std::cout<<"{\"targetFilterDrops\":"<<drops<<",\"udpDrops\":"<<udpDrops<<",\"ipv6Drops\":"<<v6Drops<<",\"eventOptionRestored\":"<<(restored==0?"true":"false")<<"}\n";
        return ran&&restored==0?0:7;
    }
    if(mode==L"install") { status=ensureProvider(engine); if(status){FwpmEngineClose0(engine);std::cerr<<"Provider creation failed: "<<status<<"\n";return 4;} }
    for(int index=2;index<argc;++index) {
        wchar_t absolute[32768]{}; if(!GetFullPathNameW(argv[index],32768,absolute,nullptr)){status=GetLastError();break;}
        if(mode==L"install" && GetFileAttributesW(absolute)==INVALID_FILE_ATTRIBUTES){status=ERROR_FILE_NOT_FOUND;break;}
        if(mode==L"check"){status=apply(engine,absolute,4,mode);if(!status)status=apply(engine,absolute,6,mode);if(status)break;continue;}
        status=FwpmTransactionBegin0(engine,0); if(status)break;
        status=apply(engine,absolute,4,mode); if(!status)status=apply(engine,absolute,6,mode);
        if(status)FwpmTransactionAbort0(engine); else status=FwpmTransactionCommit0(engine);
        if(status)break;
    }
    FwpmEngineClose0(engine);
    if(status){std::cerr<<"App-scoped WFP operation failed: "<<status<<"\n";return 5;}
    std::cout<<"{\"success\":true,\"families\":[4,6],\"loopbackAllowed\":true,\"windowsFirewallProfilesChanged\":false,\"programs\":"<<(argc-2)<<"}\n";
}
