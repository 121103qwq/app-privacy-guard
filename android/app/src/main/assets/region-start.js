(()=>{function installRegion(root, config = { locale: 'en-US', timezone: 'America/Los_Angeles' }) {
  if (root.__appPrivacyRegion?.version === 1) return root.__appPrivacyRegion;
  const NativeDate = root.Date;
  const D = NativeDate.prototype;
  const NativeFormatter = root.Intl.DateTimeFormat;
  const nativeOffset = D.getTimezoneOffset;
  const getTime = D.getTime, setTime = D.setTime;
  const utcMethods = {};
  for (const name of ['getUTCFullYear','getUTCMonth','getUTCDate','getUTCDay','getUTCHours','getUTCMinutes','getUTCSeconds','getUTCMilliseconds','setUTCFullYear']) utcMethods[name] = D[name];
  const formatter = new NativeFormatter('en-US', { timeZone: config.timezone, calendar: 'gregory', numberingSystem: 'latn', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  const wallEpoch = (y,m,d,h=0,n=0,s=0,ms=0) => {
    const date = new NativeDate(0);
    utcMethods.setUTCFullYear.call(date,y,m,d); D.setUTCHours.call(date,h,n,s,ms); return getTime.call(date);
  };
  const parts = timestamp => {
    if (!Number.isFinite(timestamp)) return null;
    const p = Object.fromEntries(formatter.formatToParts(new NativeDate(timestamp)).map(item => [item.type,item.value]));
    return { y:+p.year,m:+p.month-1,d:+p.day,h:+p.hour,n:+p.minute,s:+p.second,ms:((timestamp%1000)+1000)%1000 };
  };
  const asWall = p => wallEpoch(p.y,p.m,p.d,p.h,p.n,p.s,p.ms);
  const offset = timestamp => {
    const p = parts(timestamp); return p ? Math.round((timestamp-asWall(p))/60000) : NaN;
  };
  const fromWall = epoch => {
    if (!Number.isFinite(epoch)) return NaN;
    const offsets = new Set([-183,-1,0,1,183].map(days => offset(epoch+days*86400000)));
    const choices = [...offsets].map(minutes => { const timestamp=epoch+minutes*60000; return { timestamp, delta:asWall(parts(timestamp))-epoch }; });
    const exact = choices.filter(item => item.delta===0).sort((a,b)=>a.timestamp-b.timestamp);
    if (exact.length) return exact[0].timestamp;
    // Native Date's compatible DST behavior: advance across gaps, earlier in overlaps.
    const after = choices.filter(item=>item.delta>0).sort((a,b)=>a.delta-b.delta||a.timestamp-b.timestamp);
    return after[0]?.timestamp ?? choices[0]?.timestamp ?? NaN;
  };
  const normalizeYear = value => value>=0&&value<=99?value+1900:value;
  const parse = value => {
    const text=String(value);
    const local=text.match(/^([+-]?\d{4,6})-(\d\d)-(\d\d)[T ](\d\d):(\d\d)(?::(\d\d)(?:\.(\d{1,3}))?)?$/);
    if(local)return fromWall(wallEpoch(+local[1],+local[2]-1,+local[3],+local[4],+local[5],+(local[6]||0),+(local[7]||'0').padEnd(3,'0')));
    const parsed=NativeDate.parse(text);
    const explicitZone=/\b(?:GMT|UTC|UT|[ECMP][DS]T)\b|(?:Z|[+-]\d{2}:?\d{2})$/i.test(text);
    const isoDateOnly=/^[+-]?\d{4,6}-\d\d(?:-\d\d)?$/.test(text);
    return Number.isFinite(parsed)&&!explicitZone&&!isoDateOnly?fromWall(parsed-nativeOffset.call(new NativeDate(parsed))*60000):parsed;
  };
  let DateFacade;
  DateFacade = new Proxy(NativeDate, {
    apply() { return D.toString.call(new DateFacade()); },
    construct(target,args,newTarget) {
      let values=args;
      if(args.length>=2) values=[fromWall(wallEpoch(normalizeYear(Number(args[0])),Number(args[1]),args.length>2?Number(args[2]):1,args.length>3?Number(args[3]):0,args.length>4?Number(args[4]):0,args.length>5?Number(args[5]):0,args.length>6?Number(args[6]):0))];
      else if(args.length===1&&typeof args[0]==='string') values=[parse(args[0])];
      return Reflect.construct(target,values,newTarget);
    },
    get(target,key,receiver) { if(key==='parse')return parse;return Reflect.get(target,key,receiver); }
  });
  const define = (object,name,value) => Object.defineProperty(object,name,{configurable:true,writable:true,value});
  const getters={getFullYear:'y',getMonth:'m',getDate:'d',getHours:'h',getMinutes:'n',getSeconds:'s',getMilliseconds:'ms'};
  for(const [method,key] of Object.entries(getters))define(D,method,function(){return parts(getTime.call(this))?.[key]??NaN;});
  define(D,'getTimezoneOffset',function(){return offset(getTime.call(this));});
  define(D,'getDay',function(){const p=parts(getTime.call(this));return p?utcMethods.getUTCDay.call(new NativeDate(wallEpoch(p.y,p.m,p.d))):NaN;});
  define(D,'getYear',function(){return this.getFullYear()-1900;});
  const setters={setFullYear:['y','m','d'],setMonth:['m','d'],setDate:['d'],setHours:['h','n','s','ms'],setMinutes:['n','s','ms'],setSeconds:['s','ms'],setMilliseconds:['ms']};
  for(const [method,keys] of Object.entries(setters))define(D,method,function(...values){
    let p=parts(getTime.call(this));
    if(!p&&method==='setFullYear')p=parts(0);
    if(!p)return setTime.call(this,NaN);
    if(!values.length)return setTime.call(this,NaN);
    for(let index=0;index<Math.min(values.length,keys.length);++index)p[keys[index]]=Number(values[index]);
    return setTime.call(this,fromWall(asWall(p)));
  });
  define(D,'setYear',function(year){return this.setFullYear(normalizeYear(Number(year)));});
  const dayNames=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const monthNames=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const pad=value=>String(value).padStart(2,'0');
  const dateText=date=>`${dayNames[date.getDay()]} ${monthNames[date.getMonth()]} ${pad(date.getDate())} ${date.getFullYear()}`;
  const timeText=date=>{
    const minutes=date.getTimezoneOffset(),absolute=Math.abs(minutes);
    const label=new NativeFormatter('en-US',{timeZone:config.timezone,timeZoneName:'long'}).formatToParts(date).find(item=>item.type==='timeZoneName').value;
    return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())} GMT${minutes<=0?'+':'-'}${pad(Math.floor(absolute/60))}${pad(absolute%60)} (${label})`;
  };
  define(D,'toDateString',function(){return Number.isFinite(getTime.call(this))?dateText(this):'Invalid Date';});
  define(D,'toTimeString',function(){return Number.isFinite(getTime.call(this))?timeText(this):'Invalid Date';});
  define(D,'toString',function(){return Number.isFinite(getTime.call(this))?`${dateText(this)} ${timeText(this)}`:'Invalid Date';});
  for(const [method,defaults] of Object.entries({toLocaleString:{year:'numeric',month:'numeric',day:'numeric',hour:'numeric',minute:'numeric',second:'numeric'},toLocaleDateString:{year:'numeric',month:'numeric',day:'numeric'},toLocaleTimeString:{hour:'numeric',minute:'numeric',second:'numeric'}})){
    define(D,method,function(locales,options){if(!Number.isFinite(getTime.call(this)))return'Invalid Date';return new NativeFormatter(locales??config.locale,{...(options??defaults),timeZone:options?.timeZone??config.timezone}).format(this);});
  }
  define(D,'constructor',DateFacade);
  define(root,'Date',DateFacade);
  for(const name of ['DateTimeFormat','NumberFormat','Collator','PluralRules','RelativeTimeFormat','ListFormat','Segmenter','DisplayNames','DurationFormat']){
    const Constructor=root.Intl[name];if(!Constructor)continue;
    const argumentsFor=args=>[args[0]??config.locale,name==='DateTimeFormat'?{...args[1],timeZone:args[1]?.timeZone??config.timezone}:args[1]];
    const facade=new Proxy(Constructor,{apply(target,receiver,args){return Reflect.apply(target,receiver,argumentsFor(args));},construct(target,args,newTarget){return Reflect.construct(target,argumentsFor(args),newTarget);}});
    define(root.Intl,name,facade);define(Constructor.prototype,'constructor',facade);
  }
  const languages=Object.freeze([config.locale,config.locale.split('-')[0]]);
  if(root.navigator){
    const prototype=Object.getPrototypeOf(root.navigator);
    for(const [name,value] of [['language',config.locale],['languages',languages]]){
      try{Object.defineProperty(prototype,name,{configurable:true,enumerable:true,get:()=>value});}
      catch{Object.defineProperty(root.navigator,name,{configurable:true,get:()=>value});}
    }
  }
  const status=Object.freeze({version:1,locale:config.locale,timezone:config.timezone,scriptLayer:true});
  Object.defineProperty(root,'__appPrivacyRegion',{configurable:true,value:status});
  return status;
}

installRegion(globalThis);
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

})();
