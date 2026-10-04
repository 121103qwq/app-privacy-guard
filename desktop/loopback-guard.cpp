#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <iostream>
#include <string>
#include <cwctype>
#include <cstring>
#include <vector>
static const GUID provider={0x9e2a378c,0x073b,0x45e1,{0x94,0x67,0x32,0xb7,0xa6,0x13,0xe4,0x02}};
static const GUID sublayer={0x9e2a378c,0x073b,0x45e1,{0x94,0x67,0x32,0xb7,0xa6,0x13,0xe4,0x03}};
GUID key(const std::wstring& p,int kind){unsigned long long a=1469598103934665603ULL,b=1099511628211ULL;for(auto c:p){a=(a^towlower(c))*1099511628211ULL;b=(b^(towlower(c)+17))*1469598103934665603ULL;}a^=kind;GUID k;memcpy(&k,&a,8);memcpy(((BYTE*)&k)+8,&b,8);return k;}
int wmain(int argc,wchar_t**argv){
 if(argc!=4){std::cerr<<"loopback-guard install|check|remove|observe PROGRAM PROXY_PORT\n";return 2;}
 std::wstring mode=argv[1];if(mode!=L"install"&&mode!=L"check"&&mode!=L"remove"&&mode!=L"observe")return 2;
 int port=_wtoi(argv[3]);if(port<1||port>65535)return 2;wchar_t p[32768];if(!GetFullPathNameW(argv[2],32768,p,nullptr))return 2;
 HANDLE e=nullptr;DWORD s=FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,nullptr,&e);if(s)return 3;
 if(mode==L"observe"){
  FWP_VALUE0* old=nullptr;s=FwpmEngineGetOption0(e,FWPM_ENGINE_COLLECT_NET_EVENTS,&old);if(s){FwpmEngineClose0(e);return 6;}
  FWP_VALUE0 enabled{};enabled.type=FWP_UINT32;enabled.uint32=1;s=FwpmEngineSetOption0(e,FWPM_ENGINE_COLLECT_NET_EVENTS,&enabled);if(s){FwpmFreeMemory0((void**)&old);FwpmEngineClose0(e);return 6;}
  UINT64 ids[4]{};for(int kind=0;kind<4;++kind){auto id=key(p,kind);FWPM_FILTER0* f=nullptr;if(!FwpmFilterGetByKey0(e,&id,&f)){ids[kind]=f->filterId;FwpmFreeMemory0((void**)&f);}}
  FILETIME started;GetSystemTimeAsFileTime(&started);std::wstring command=L"\""+std::wstring(p)+L"\" "+argv[3];std::vector<wchar_t> mutableCommand(command.begin(),command.end());mutableCommand.push_back(0);
  STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION process{};bool ran=CreateProcessW(p,mutableCommand.data(),nullptr,nullptr,TRUE,0,nullptr,nullptr,&startup,&process);if(ran){WaitForSingleObject(process.hProcess,10000);CloseHandle(process.hThread);CloseHandle(process.hProcess);Sleep(400);}
  FWPM_NET_EVENT_ENUM_TEMPLATE0 query{};query.startTime=started;GetSystemTimeAsFileTime(&query.endTime);HANDLE enumeration=nullptr;int drops=0,udp=0,v6=0;
  if(!FwpmNetEventCreateEnumHandle0(e,&query,&enumeration)){FWPM_NET_EVENT0** events=nullptr;UINT32 count=0;if(!FwpmNetEventEnum0(e,enumeration,2048,&events,&count)){
   for(UINT32 i=0;i<count;++i){auto n=events[i];if(n->type!=FWPM_NET_EVENT_TYPE_CLASSIFY_DROP||!n->classifyDrop)continue;for(int k=0;k<4;++k)if(ids[k]&&n->classifyDrop->filterId==ids[k]){++drops;if(n->header.ipProtocol==17)++udp;if(k==3)++v6;break;}}
   FwpmFreeMemory0((void**)&events);}FwpmNetEventDestroyEnumHandle0(e,enumeration);}
  DWORD restored=FwpmEngineSetOption0(e,FWPM_ENGINE_COLLECT_NET_EVENTS,old);FwpmFreeMemory0((void**)&old);FwpmEngineClose0(e);
  std::cout<<"{\"wfp_observed_drops\":"<<drops<<",\"udp_observed_drops\":"<<udp<<",\"ipv6_observed_drops\":"<<v6<<",\"event_option_restored\":"<<(restored?"false":"true")<<"}\n";return ran&&!restored&&udp>0&&v6>0?0:7;
 }
 if(mode==L"install"){
  FWPM_PROVIDER0 item{};item.providerKey=provider;item.flags=FWPM_PROVIDER_FLAG_PERSISTENT;item.displayData.name=const_cast<wchar_t*>(L"App Privacy strict loopback guard");s=FwpmProviderAdd0(e,&item,nullptr);if(s&&s!=FWP_E_ALREADY_EXISTS){FwpmEngineClose0(e);return 4;}
  FWPM_SUBLAYER0 sub{};sub.subLayerKey=sublayer;sub.providerKey=const_cast<GUID*>(&provider);sub.flags=FWPM_SUBLAYER_FLAG_PERSISTENT;sub.weight=0xffff;sub.displayData.name=item.displayData.name;s=FwpmSubLayerAdd0(e,&sub,nullptr);if(s&&s!=FWP_E_ALREADY_EXISTS){FwpmEngineClose0(e);return 4;}
 }
 FWP_BYTE_BLOB* app=nullptr;s=FwpmGetAppIdFromFileName0(p,&app);if(s){FwpmEngineClose0(e);return 4;}
 s=FwpmTransactionBegin0(e,0);if(s){FwpmFreeMemory0((void**)&app);FwpmEngineClose0(e);return 5;}
 for(int kind=0;kind<4&&!s;++kind){GUID id=key(p,kind);FWPM_FILTER0* existing=nullptr;DWORD got=FwpmFilterGetByKey0(e,&id,&existing);
  if(mode==L"check"){s=got;if(existing){if(kind==1&&(existing->numFilterConditions!=2||existing->filterCondition[1].conditionValue.type!=FWP_UINT16||existing->filterCondition[1].conditionValue.uint16!=port))s=ERROR_INVALID_DATA;FwpmFreeMemory0((void**)&existing);}continue;}
  if(existing){FwpmFreeMemory0((void**)&existing);s=FwpmFilterDeleteByKey0(e,&id);if(s)break;}if(mode==L"remove")continue;
  FWPM_FILTER_CONDITION0 c[2]{};c[0].fieldKey=FWPM_CONDITION_ALE_APP_ID;c[0].matchType=FWP_MATCH_EQUAL;c[0].conditionValue.type=FWP_BYTE_BLOB_TYPE;c[0].conditionValue.byteBlob=app;
  if(kind==0){c[1].fieldKey=FWPM_CONDITION_IP_REMOTE_ADDRESS;c[1].conditionValue.type=FWP_UINT32;c[1].conditionValue.uint32=0x7f000001;}
  if(kind==1){c[1].fieldKey=FWPM_CONDITION_IP_REMOTE_PORT;c[1].conditionValue.type=FWP_UINT16;c[1].conditionValue.uint16=(UINT16)port;}
  if(kind==2){c[1].fieldKey=FWPM_CONDITION_IP_PROTOCOL;c[1].conditionValue.type=FWP_UINT8;c[1].conditionValue.uint8=6;}
  c[1].matchType=FWP_MATCH_NOT_EQUAL;
  FWPM_FILTER0 f{};f.filterKey=id;f.providerKey=const_cast<GUID*>(&provider);f.subLayerKey=sublayer;f.layerKey=kind==3?FWPM_LAYER_ALE_AUTH_CONNECT_V6:FWPM_LAYER_ALE_AUTH_CONNECT_V4;
  f.flags=FWPM_FILTER_FLAG_PERSISTENT|FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT;f.displayData.name=const_cast<wchar_t*>(L"Deny every route except selected loopback TCP port");UINT64 weight=~0ULL;f.weight.type=FWP_UINT64;f.weight.uint64=&weight;f.action.type=FWP_ACTION_BLOCK;f.numFilterConditions=kind==3?1:2;f.filterCondition=c;UINT64 added;s=FwpmFilterAdd0(e,&f,nullptr,&added);
 }
 if(s)FwpmTransactionAbort0(e);else s=FwpmTransactionCommit0(e);FwpmFreeMemory0((void**)&app);FwpmEngineClose0(e);if(s){std::cerr<<"WFP operation failed: "<<s<<"\n";return 5;}
 std::cout<<"{\"success\":true,\"onlyLoopbackTcpPort\":"<<port<<",\"ipv6Denied\":true}\n";return 0;
}
