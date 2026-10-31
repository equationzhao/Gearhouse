import {randomUUID} from 'node:crypto';
import {ensureCategories} from './categories.mjs';
import {readGearStatus,readOwnGearStatus} from './gear-state.mjs';
import {compareTimeline,appliesAt} from './timeline-time.mjs';
export const uid=()=>randomUUID();
export const clone=x=>structuredClone(x);
export const empty=()=>ensureCategories({version:1,revision:0,account:null,gears:[],events:[],gearEvents:[],activities:[],remoteGears:[],gearImported:false,lastSync:null,syncLog:[]});
export function ensure(ok,message){if(!ok){const e=new Error(message);e.status=400;throw e;}}
export function dateTime(value){ensure(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(value)&&Number.isFinite(Date.parse(value+'Z')),'时间格式无效');const full=value.length===16?value+':00':value;ensure(new Date(full+'Z').toISOString().slice(0,19)===full,'时间格式无效');return full;}
// An ICU local clock alone cannot distinguish time zones or repeated DST hours.
export function activityInstant(value){
 if(typeof value!=='string')return null;
 const match=/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d{1,3})?(Z|[+-]\d{2}:\d{2})$/.exec(value);
 if(!match)return null;
 try{dateTime(match[1]);}catch{return null;}
 if(match[2]!=='Z'){const h=Number(match[2].slice(1,3)),m=Number(match[2].slice(4,6));if(h>14||m>59||(h===14&&m!==0))return null;}
 const parsed=Date.parse(value);return Number.isFinite(parsed)?new Date(parsed).toISOString():null;
}
export function installationDate(value){
 ensure(typeof value==='string','日期无效');
 return dateTime(value.length===10?value+'T00:00:00':value).slice(0,10)+'T00:00:00';
}
export function shanghaiTime(instant){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date(instant)).replace(' ','T');}
export function installationTime(value,instant,{allowFuture=false}={}){
 if(instant===undefined||instant===null)return {at:installationDate(value),allDay:true};
 const utc=activityInstant(instant);ensure(utc,'请选择有效的生效时间');
 const at=shanghaiTime(utc);
 ensure(typeof value==='string'&&value.slice(0,10)===at.slice(0,10),'生效日期与时间不一致');
 ensure(allowFuture||Date.parse(utc)<=Date.now(),'不能设置未来的装配时间');
 return {at,instant:utc,allDay:false};
}
export function buildTimedAssemblyIndex(s){
 const parents=new Map();function find(id){if(!parents.has(id))parents.set(id,id);let p=id;while(parents.get(p)!==p)p=parents.get(p);while(id!==p){const next=parents.get(id);parents.set(id,p);id=next;}return p;}
 for(const row of s.events)if(row.gearId&&row.parentId){const a=find(row.gearId),b=find(row.parentId);if(a!==b)parents.set(a,b);}
 const days=new Map();for(const row of [...s.events,...(s.gearStates||[])])if(row.instant&&row.gearId){const root=find(row.gearId),list=days.get(root)||[];list.push(Date.parse(row.at.slice(0,10)+'T00:00:00Z'));days.set(root,list);}
 return {find,days};
}
export function hasTimedAssembly(s,a,index=buildTimedAssemblyIndex(s)){
 return [a.main,...(a.extras||[])].filter(Boolean).some(id=>index.days.has(index.find(id)));
}
export function activityTimeUncertain(s,a,index=buildTimedAssemblyIndex(s)){
 if(a.startInstant||!a.at)return false;
 const day=Date.parse(a.at.slice(0,10)+'T00:00:00Z');
 if(!Number.isFinite(day))return true;
 return [a.main,...(a.extras||[])].filter(Boolean).some(id=>(index.days.get(index.find(id))||[]).some(value=>Math.abs(value-day)<=2*86400000));
}
export function migrateInstallationDates(s){
 if(s.installationDatesVersion===1)return;
 ensure(!s.events.some(e=>e.instant),'装配记录缺少时间版本，请选择完整备份。');
 const byDay=new Map(),aliases=new Map();let changed=0;
 for(const e of s.events.slice().sort((a,b)=>a.at.localeCompare(b.at))){
  const at=installationDate(e.at),key=e.gearId+':'+at,previous=byDay.get(key);
  if(previous)aliases.set(previous.id,e.id);
  byDay.set(key,{...e,at,allDay:true});
  if(e.at!==at)changed++;
 }
 const next=[...byDay.values()];
 ensure(treeValid(s,next),'装配历史存在环路');
 for(const r of s.reminders||[])if(r.anchor==='installation'){
  const seen=new Set();while(aliases.has(r.anchorID)&&!seen.has(r.anchorID)){seen.add(r.anchorID);r.anchorID=aliases.get(r.anchorID);}
 }
 s.installationDatesMigration={changed,merged:s.events.length-next.length};
 s.events=next;s.installationDatesVersion=1;
}
export function today(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai'}).format(new Date());}
export function nowLocal(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date()).replace(' ','T');}
export function parentAt(s,id,at,instant){return s.events.filter(e=>e.gearId===id&&appliesAt(e,at,instant)).sort(compareTimeline).at(-1)?.parentId||null;}
// Cache only an exact structural signature; imported data cannot assert trust.
let treeValidation;
export function treeValid(s,events){
 const signature=JSON.stringify([s.gears.map(g=>g.id),events.map(e=>[e.gearId,e.parentId,e.at,e.instant])]);
 if(treeValidation?.signature===signature)return treeValidation.valid;
 const ordered=events.slice().sort(compareTimeline),parents=new Map();
 let valid=true;
 for(let i=0;i<ordered.length&&valid;){
  const point=ordered[i];
  do{const e=ordered[i++];parents.set(e.gearId,e.parentId||null);}while(i<ordered.length&&compareTimeline(ordered[i],point)===0);
  // Apply all events at the same instant before checking the resulting graph.
  const complete=new Set();
  for(const g of s.gears){
   const path=new Set();let id=g.id;
   while(id&&!complete.has(id)){
    if(path.has(id)){valid=false;break;}
    path.add(id);id=parents.get(id);
   }
   if(!valid)break;
   for(const id of path)complete.add(id);
  }
 }
 treeValidation={signature,valid};return valid;
}
export function batchMove(s,changes,value,instant){const time=installationTime(value,instant),at=time.at;ensure(time.instant||at<=nowLocal(),'不能设置未来的装配时间');ensure(Array.isArray(changes)&&changes.length>0,'没有可保存的修改');ensure(changes.length<500,'每次最多调整 499 件装备，请减少选择后重试。');const ids=new Set();for(const c of changes){ensure(s.gears.some(g=>g.id===c.gearId&&!g.deletedAt),'装备不存在或已删除');ensure(!ids.has(c.gearId),'装备重复');ids.add(c.gearId);ensure(c.parentId===null||s.gears.some(g=>g.id===c.parentId&&!g.deletedAt),'所属装备不存在或已删除');}
const sameDay=e=>e.at.slice(0,10)===at.slice(0,10),samePoint=e=>time.instant?e.instant===time.instant:!e.instant&&sameDay(e);
ensure(!(s.gearOperations||[]).some(op=>compareTimeline(op,time)>=0&&op.gearIds.some(id=>ids.has(id))),'请通过更换或库存记录修改这次装配。');
ensure(!time.instant||!s.events.some(e=>ids.has(e.gearId)&&samePoint(e)),'该时刻已有装配记录，请编辑原记录。');
ensure(!s.events.some(e=>ids.has(e.gearId)&&sameDay(e)&&(e.operationId&&(time.allDay||samePoint(e))||time.allDay&&e.instant||time.instant&&!e.instant&&e.at===at)),'该日期已有更换或库存记录，请编辑原记录。');
const rootStatuses=new Map(changes.map(c=>[c.gearId,c.parentId===null&&readGearStatus(s,c.gearId,at,true,undefined,time.instant)==='stock'?'stock':'active']));
const events=s.events.filter(e=>!(ids.has(e.gearId)&&samePoint(e))).concat(changes.map(c=>{const old=s.events.find(e=>e.gearId===c.gearId&&samePoint(e));return {id:old?.id||uid(),gearId:c.gearId,parentId:c.parentId,...time};}));ensure(treeValid(s,events),'所属装备不能是自身或子装备（含后续历史关系）');s.events=events;for(const c of changes)activateMovedGear(s,c.gearId,at,events.find(e=>e.gearId===c.gearId&&samePoint(e))?.id,rootStatuses.get(c.gearId),time.instant);return s;}
export function activateMovedGear(s,id,at,installationId,status='active',instant){
 const before=readOwnGearStatus(s,id,at,true,undefined,instant);if(before===status||before==='retired')return;
 const existing=(s.gearStates||[]).find(e=>e.gearId===id&&(instant?e.instant===instant:e.at===at&&!e.instant));
 ensure(!existing?.operationId,'该日期已有更换或库存记录，请编辑原记录。');
 s.gearStates=(s.gearStates||[]).filter(e=>!(e.gearId===id&&(instant?e.instant===instant:e.at===at&&!e.instant)));
 s.gearStates.push({id:existing?.id||uid(),gearId:id,status,at,installationId,...(instant?{instant,allDay:false}:{})});
}
export function expand(s,roots,at,excluded=[],{allowInactiveRoots=false,instant=null}={}){const result=[],seen=new Set(),ex=new Set(excluded);function visit(id,via){if(!id||seen.has(id)||ex.has(id))return;const g=s.gears.find(x=>x.id===id);if(!g||(g.deletedAt&&at>=g.deletedAt)||readGearStatus(s,id,at,false,undefined,instant)!=='active'&&!(allowInactiveRoots&&via===null))return;seen.add(id);result.push({id,parentId:via});s.gears.filter(x=>parentAt(s,x.id,at,instant)===id).forEach(x=>visit(x.id,id));}roots.forEach(id=>visit(id,null));return result;}
export function equipmentDistanceIncluded(s,a,rows=[]){
 const used=new Set([a.main,...(a.extras||[]),...rows.map(x=>x.id)]);
 return a.type!=='VirtualRide'&&a.trainer!==true&&!s.gears.some(g=>g.type==='Trainer'&&used.has(g.id));
}
export function distanceSnapshot(rows,included,s){
 // Persist the decision per gear: category edits never reinterpret saved history.
 return rows.map(({distanceIncluded,...row})=>{
  const gear=s?.gears.find(g=>g.id===row.id);
  const category=s?.gearCategories?.find(c=>c.id===(gear?.categoryId||gear?.type));
  return included||category?.indoorDistance===true?row:{...row,distanceIncluded:false};
 });
}
export function preserveDistanceSnapshot(rows,a){
 // Missing flags belong to legacy history and continue to count distance.
 return rows.map(row=>{const old=a.snapshot?.find(x=>x.id===row.id);return (old?old.distanceIncluded:a.equipmentDistance)===false?{...row,distanceIncluded:false}:row;});
}
export function deleteGear(s,id){
const g=s.gears.find(x=>x.id===id);ensure(g,'装备不存在');ensure(!g.deletedAt,'装备已删除');
const at=nowLocal();
ensure(!s.gears.some(x=>!x.deletedAt&&parentAt(s,x.id,at)===id),'请先移出该装备下的组件');
g.deletedAt=at;return g;
}
export function restoreGear(s,id){
const g=s.gears.find(x=>x.id===id);ensure(g?.deletedAt,'装备不在回收站');
const p=parentAt(s,id,nowLocal());ensure(!s.gears.find(x=>x.id===p)?.deletedAt,'请先恢复所属装备');
delete g.deletedAt;return g;
}
function purchaseDate(value){
if(value===null||value==='')return null;
ensure(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?$/.test(value),'购买时间格式无效');
const full=value.length===10?value+'T00:00:00':value.length===16?value+':00':value;
const parsed=new Date(full+'Z');ensure(Number.isFinite(parsed.getTime())&&parsed.toISOString().slice(0,19)===full,'购买时间无效');
return value;
}
export function saveGear(s,input){const existing=s.gears.find(g=>g.id===input.id);ensure(!existing?.deletedAt,'请先恢复装备');const name=String(input.name||'').trim();ensure(name.length>0&&name.length<=160,'请输入装备名称');const requestedType=String(input.type||existing?.type||'Equipment');
const categoryId=input.categoryId||(input.type&&input.type!==existing?.type?requestedType:existing?.categoryId||requestedType);
const category=s.gearCategories.find(c=>c.id===categoryId);ensure(category,'请选择装备类别。');
const type=category.baseType;let remoteId=input.remoteId||null;
if(remoteId){const r=s.remoteGears.find(x=>x.id===remoteId&&!x.component);const retained=existing?.remoteId===remoteId&&existing.type===type;ensure(retained||r&&['Bike','Shoes'].includes(r.type),'请选择可关联的 Bike / Shoes');ensure(retained||type===r.type,'装备类型与远端类型不一致');ensure(!s.gears.some(g=>g.id!==input.id&&g.remoteId===remoteId),'该 ICU 装备已关联其他本地装备');}
const purchased=purchaseDate(input.purchased===undefined?(existing?.purchased||null):input.purchased);
const g={id:existing?.id||uid(),name,type,categoryId,remoteId,purchased,notes:String(input.notes||'').slice(0,3000),createdAt:existing?.createdAt||nowLocal(),retired:!!input.retired};if(input.condition!==undefined){ensure(['','unused','used'].includes(input.condition),'请选择装备状况。');g.condition=input.condition;}if(existing)Object.assign(existing,g);else s.gears.push(g);return g;}
export function readAssignmentOverrides(a){
 // Old saves cannot tell us which field was edited. Keep their ownership and
 // frozen assembly until the rider explicitly resumes following ICU.
 return a.assignmentOverrides?{...a.assignmentOverrides}:a.manual?{main:'legacy',assembly:true}:{};
}
function mapRemoteMain(s,a){return a.remoteId?s.gears.find(g=>g.remoteId===a.remoteId&&['Bike','Shoes'].includes(g.type)&&(!g.deletedAt||a.at<g.deletedAt))?.id||null:null;}
function replaceAssignmentRoots(s,a,main,extras){
 const roots=[main,...extras].filter(Boolean),oldRoots=[a.main,...(a.extras||[])].filter(Boolean);
 const timeUnknown=activityTimeUncertain(s,{...a,main,extras});
 const removed=new Set(oldRoots.filter(id=>!roots.includes(id)));let count;
 do{count=removed.size;for(const row of a.snapshot||[])if(removed.has(row.parentId)&&!roots.includes(row.id))removed.add(row.id);}while(count!==removed.size);
 const rows=(a.snapshot||[]).filter(row=>!removed.has(row.id));
 for(const id of roots.filter(id=>!oldRoots.includes(id))){
  const expanded=timeUnknown?[{id,parentId:null}]:expand(s,[id],a.at,a.excluded||[],{allowInactiveRoots:true,instant:a.startInstant});
  for(const row of preserveDistanceSnapshot(expanded,a))if(!rows.some(x=>x.id===row.id))rows.push(row);
 }
 const present=new Set(rows.map(row=>row.id));
 return rows.map(row=>row.parentId&&!present.has(row.parentId)?{...row,parentId:null}:row);
}
export function updateAssignmentSync(s,a){
 const overrides=readAssignmentOverrides(a),target=s.gears.find(g=>g.id===a.main)?.remoteId||null;
 a.pending=!!overrides.main&&(!!a.main&&!target||target!==(a.remoteId||null));
 if(overrides.main&&overrides.main!=='legacy'&&!a.pending){a.mainSyncBase=a.remoteId||null;delete a.mainResolutionRequired;}
 // Legacy edits have no recorded base. They require an explicit choice before
 // a retry can overwrite a different remote value.
 const base=Object.hasOwn(a,'mainSyncBase')?a.mainSyncBase:a.remoteId||null;
 a.mainConflict=!!a.pending&&(a.mainResolutionRequired||overrides.main==='legacy'||base!==(a.remoteId||null)&&target!==(a.remoteId||null));
}
export function reconcileActivityMappings(s){
 for(const a of s.activities){
  if(a.summary||a.unavailable||a.deleted)continue;
  if(!readAssignmentOverrides(a).main){
   const mapped=mapRemoteMain(s,a);
   if((a.main||null)!==mapped){a.snapshot=replaceAssignmentRoots(s,a,mapped,a.extras||[]);a.main=mapped;if(activityTimeUncertain(s,a))a.assemblyTimeUnknown=true;}
   a.unknown=!!a.remoteId&&!mapped;
  }
  updateAssignmentSync(s,a);
 }
}
export function saveAssignment(s,id,input){
 const a=s.activities.find(x=>x.id===id);ensure(a&&!a.summary&&!a.unavailable&&!a.deleted,'活动不可编辑，请先读取完整数据');
 const overrides=readAssignmentOverrides(a),changesMain=Object.hasOwn(input,'main')||input.followRemote===true;
 let main=changesMain?(input.followRemote?mapRemoteMain(s,a):input.main||null):a.main||null;
 ensure(main===null||s.gears.some(g=>g.id===main&&(!g.deletedAt||a.main===main)&&['Bike','Shoes'].includes(g.type)),'主装备必须是 Bike / Shoes');
 let extras=[...new Set(Object.hasOwn(input,'extras')?input.extras||[]:a.extras||[])];
 if(Object.hasOwn(input,'extras')){overrides.shoe=true;overrides.trainer=true;}
 for(const [field,type] of [['shoe','CyclingShoes'],['trainer','Trainer']])if(Object.hasOwn(input,field)){
  const selected=input[field]||null;
  ensure(!selected||s.gears.some(g=>g.id===selected&&g.type===type&&(!g.deletedAt||(a.extras||[]).includes(g.id))),'附加装备无效');
  extras=extras.filter(id=>s.gears.find(g=>g.id===id)?.type!==type);if(selected)extras.push(selected);
  overrides[field]=true;
 }
 ensure(extras.every(id=>s.gears.some(g=>g.id===id&&(!g.deletedAt||(a.extras||[]).includes(id)))),'附加装备无效');
 const excluded=Object.hasOwn(input,'excluded')?[...new Set(input.excluded||[])]:a.excluded||[];
 ensure(excluded.every(id=>s.gears.some(g=>g.id===id))&&!excluded.includes(main),'排除装备无效');
 const oldRoots=[a.main,...(a.extras||[])];
 const timeUnknown=activityTimeUncertain(s,{...a,main,extras});
 for(const selected of [main,...extras].filter(Boolean))if(!oldRoots.includes(selected)&&!input.followRemote){ensure(!timeUnknown,'活动缺少可靠的开始时刻，请先同步完整活动。');ensure(readGearStatus(s,selected,a.at,true,undefined,a.startInstant)==='active','该装备在活动当天未使用，请先调整使用日期。');}
 ensure(!timeUnknown||(!input.rebuild&&!input.refreshAssembly),'活动缺少可靠的开始时刻，请先同步完整活动。');
 let snapshot=input.rebuild||input.refreshAssembly?expand(s,[main,...extras],a.at,excluded,{instant:a.startInstant}):replaceAssignmentRoots(s,{...a,excluded},main,extras);
 if(input.rebuild){a.equipmentDistance=equipmentDistanceIncluded(s,{...a,main,extras},snapshot);snapshot=distanceSnapshot(snapshot,a.equipmentDistance,s);overrides.assembly=true;}
 else if(input.refreshAssembly)snapshot=preserveDistanceSnapshot(snapshot,a);
 if(changesMain){
  if(input.followRemote){delete overrides.main;delete overrides.assembly;delete a.mainSyncBase;delete a.mainEditId;delete a.mainResolutionRequired;}
  else {
   // Preserve the original comparison base through retries and ordinary reads.
   if(!overrides.main||!a.pending)a.mainSyncBase=a.remoteId||null;
   overrides.main=true;a.mainEditId=uid();
  }
  a.error=null;
 }
 const unresolved=timeUnknown||!!a.assemblyTimeUnknown&&!input.rebuild&&!input.refreshAssembly;
 Object.assign(a,{main,extras,excluded,snapshot,assignmentOverrides:overrides,manual:Object.keys(overrides).length>0,assemblyTimeUnknown:unresolved});
 a.unknown=!overrides.main&&!!a.remoteId&&!main;updateAssignmentSync(s,a);return a;
}
export function observeActivityGear(s,input){
 const a=s.activities.find(x=>x.id===input.id);ensure(a,'活动不存在');
 ensure(!input.editId||a.mainEditId===input.editId,'活动已有后续修改');
 a.remoteId=input.remoteId||null;a.remoteGearName=input.name||null;
 if(typeof input.source==='string')a.source=input.source;
 if(input.requireResolution)a.mainResolutionRequired=true;
 updateAssignmentSync(s,a);return a;
}
export function refreshRemoteGears(s,gears){
 ensure(Array.isArray(gears)&&gears.every(g=>g&&g.id&&typeof g.name==='string'&&typeof g.type==='string'),'ICU Gear 返回格式无效');
 ensure(new Set(gears.map(g=>String(g.id))).size===gears.length,'ICU Gear 返回格式无效');
 s.remoteGears=gears.map(g=>({id:String(g.id),name:g.name||String(g.id),type:g.type,component:!!g.component,component_ids:g.component_ids||[]}));
 return {count:s.remoteGears.length};
}
export function importGear(s,gears,{at=nowLocal()}={}){
ensure(Array.isArray(gears),'ICU Gear 返回格式无效');
refreshRemoteGears(s,gears);
if(s.gearImportVersion>=3)return {added:0,relations:0};
at=dateTime(at);
const first=!s.gearImported,filtered=gears.filter(g=>g&&g.id);
const imported=new Set();
for(const g of filtered){
 const sourceGearId=String(g.id);
 if(s.gears.some(x=>x.sourceGearId===sourceGearId||x.remoteId===sourceGearId))continue;
 if(s.gearImportVersion>=2||(!first&&!g.component))continue;
 const main=!g.component&&['Bike','Shoes'].includes(g.type);
 const local={id:uid(),name:g.name||sourceGearId,type:g.type||'Equipment',remoteId:main?sourceGearId:null,sourceGearId,sourceComponent:!!g.component,notes:g.notes||'',createdAt:at,purchased:g.purchased||null,retired:!!g.retired,retiredAt:typeof g.retired==='string'?g.retired:null};
 s.gears.push(local);imported.add(local.id);
}
const lookup=id=>s.gears.find(g=>g.sourceGearId===String(id)||g.remoteId===String(id));
const parents=new Map();
for(const g of filtered){const parent=lookup(g.id);if(!parent)continue;for(const id of g.component_ids||[]){const child=lookup(id);if(!child||!imported.has(child.id)||s.events.some(e=>e.gearId===child.id))continue;const choices=parents.get(child.id)||new Set();choices.add(parent.id);parents.set(child.id,choices);}}
let relations=0;
for(const [gearId,choices] of parents){if(choices.size!==1)continue;const event={id:uid(),gearId,parentId:[...choices][0],at:installationDate(at),allDay:true};if(treeValid(s,[...s.events,event])){s.events.push(event);relations++;}}
for(const g of filtered){
 const local=lookup(g.id);
 if(!g.component||!local||local.importedTotals)continue;
 if(![g.distance,g.time,g.activities].every(x=>Number.isFinite(x)&&x>=0))continue;
 local.importedTotals={distance:g.distance,seconds:g.time,count:g.activities,through:at};
}
s.gearImported=true;s.gearImportVersion=3;
return {added:imported.size,relations};
}
export function mergeActivities(s,rows,{historical=false}={}){ensure(Array.isArray(rows),'ICU 活动返回格式无效');const timeIndex=buildTimedAssemblyIndex(s);let added=0,updated=0,unavailable=0;for(const r of rows){if(!r||!r.id)continue;let a=s.activities.find(x=>x.id===String(r.id));const stub=!r.start_date_local||!r.type;if(stub){unavailable++;if(a){a.unavailable=true;continue;}s.activities.push({id:String(r.id),name:r.name||'受限活动',at:r.start_date_local||'',type:r.type||'',distance:null,seconds:null,main:null,remoteId:null,snapshot:[],extras:[],excluded:[],unavailable:true});continue;}
const hasGear=Object.hasOwn(r,'gear');const remoteId=hasGear?(r.gear?.id?String(r.gear.id):null):(a?.remoteId||null);
const startInstant=Object.hasOwn(r,'start_date')?activityInstant(r.start_date):(a?.at===r.start_date_local?a?.startInstant||null:null);
const complete={id:String(r.id),name:r.name||r.type,at:r.start_date_local,startInstant,type:r.type,distance:Number.isFinite(r.distance)?r.distance:null,seconds:Number.isFinite(r.moving_time)?r.moving_time:(r.elapsed_time??null),source:r.source||'',...(typeof r.trainer==='boolean'?{trainer:r.trainer}:{}),remoteId,summary:false,unavailable:false,deleted:false};
if(a&&!a.summary){
 const previousInstant=a.startInstant||null,previousAt=a.at;
 Object.assign(a,complete);delete a.remoteDeletedAt;
 if((previousInstant!==startInstant||previousAt!==complete.at)&&hasTimedAssembly(s,a,timeIndex))a.assemblyTimeUnknown=true;
 if(!readAssignmentOverrides(a).main&&hasGear){
  const mapped=remoteId?s.gears.find(g=>g.remoteId===remoteId&&['Bike','Shoes'].includes(g.type)&&(!g.deletedAt||a.at<g.deletedAt))?.id||null:null;
  // Compare local ownership too: older syncs already refreshed remoteId without
  // following the Gear change, and a missing mapping may be added later.
  if((a.main||null)!==mapped){
   a.snapshot=replaceAssignmentRoots(s,a,mapped,a.extras||[]);a.main=mapped;if(activityTimeUncertain(s,a))a.assemblyTimeUnknown=true;
   a.unknown=!!remoteId&&!mapped;a.error=null;
  }
 }
 if(hasGear){a.remoteGearName=r.gear?.name||null;if(!readAssignmentOverrides(a).main)a.unknown=!!remoteId&&!a.main;}
 updateAssignmentSync(s,a);updated++;continue;}
const main=mapRemoteMain(s,complete);
const timeUnknown=activityTimeUncertain(s,{...complete,main},timeIndex);
const assignment={main,extras:[],excluded:[],manual:false,assignmentOverrides:{},pending:false,mainConflict:false,error:null,unknown:!!remoteId&&!main,assemblyTimeUnknown:timeUnknown,remoteGearName:r.gear?.name||null,snapshot:historical&&!hasTimedAssembly(s,{...complete,main},timeIndex)||timeUnknown?(main?[{id:main,parentId:null}]:[]):expand(s,[main],complete.at,[],{allowInactiveRoots:true,instant:complete.startInstant})};
const next={...complete,...assignment};next.equipmentDistance=equipmentDistanceIncluded(s,next,next.snapshot);next.snapshot=distanceSnapshot(next.snapshot,next.equipmentDistance,s);if(a)Object.assign(a,next);else{s.activities.push(next);added++;}}
return {added,updated,unavailable};}
export function stats(s,id,activityIndex){
const gear=s.gears.find(g=>g.id===id);
const baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
const source=activityIndex?activityIndex.byGear.get(id)||[]:s.activities;
const activities=source.filter(a=>!a.deleted&&!a.summary&&!a.unavailable&&(!baseline||a.at>baseline.through)&&a.snapshot?.some(x=>x.id===id));
return {count:(baseline?.count||0)+activities.length,distance:activities.reduce((v,a)=>v+(a.snapshot.find(x=>x.id===id).distanceIncluded===false?0:(a.distance||0)),baseline?.distance||0),seconds:activities.reduce((v,a)=>v+(a.seconds||0),baseline?.seconds||0)};
}
