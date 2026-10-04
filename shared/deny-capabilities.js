// Strict profile: block workers completely to avoid an unpatched first execution.
const deny = message => {throw new DOMException(message,'NotAllowedError');};
const blockedConstructors=new WeakMap();
for(const name of ['Worker','SharedWorker','RTCPeerConnection','webkitRTCPeerConnection','WebTransport']){
 const original=globalThis[name];if(!original)continue;
 let blocked=blockedConstructors.get(original);
 if(!blocked){blocked=new Proxy(original,{construct(){return deny(name+' is disabled in this profile');},apply(){return deny(name+' is disabled in this profile');}});blockedConstructors.set(original,blocked);Object.defineProperty(original.prototype,'constructor',{value:blocked,writable:false,configurable:false});}
 Object.defineProperty(globalThis,name,{value:blocked,writable:false,configurable:false});
}
if(globalThis.ServiceWorkerContainer){
 Object.defineProperty(ServiceWorkerContainer.prototype,'register',{value(){return Promise.reject(new DOMException('Service workers are disabled','NotAllowedError'));},writable:false,configurable:false});
}
if(globalThis.Geolocation){
 for(const method of ['getCurrentPosition','watchPosition'])Object.defineProperty(Geolocation.prototype,method,{value(_success,error){if(error)queueMicrotask(()=>error({code:1,message:'Location disabled'}));return 0;},writable:false,configurable:false});
}
if(globalThis.MediaDevices){
 for(const method of ['getUserMedia','getDisplayMedia'])Object.defineProperty(MediaDevices.prototype,method,{value(){return Promise.reject(new DOMException('Media disabled','NotAllowedError'));},writable:false,configurable:false});
}
