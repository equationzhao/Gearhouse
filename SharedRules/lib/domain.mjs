import {randomUUID} from 'node:crypto';
import {ensureCategories} from './categories.mjs';
import {readGearStatus,readOwnGearStatus} from './gear-state.mjs';
export const uid=()=>randomUUID();
export const clone=x=>structuredClone(x);
export const empty=()=>ensureCategories({version:1,revision:0,account:null,gears:[],events:[],gearEvents:[],activities:[],remoteGears:[],gearImported:false,lastSync:null,syncLog:[]});
export function ensure(ok,message){if(!ok){const e=new Error(message);e.status=400;throw e;}}
export function dateTime(value){ensure(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(value)&&Number.isFinite(Date.parse(value+'Z')),'时间格式无效');const full=value.length===16?value+':00':value;ensure(new Date(full+'Z').toISOString().slice(0,19)===full,'时间格式无效');return full;}
export function installationDate(value){
 ensure(typeof value==='string','日期无效');
 return dateTime(value.length===10?value+'T00:00:00':value).slice(0,10)+'T00:00:00';
}
export function migrateInstallationDates(s){
 if(s.installationDatesVersion===1)return;
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
export function parentAt(s,id,at){return s.events.filter(e=>e.gearId===id&&e.at<=at).sort((a,b)=>a.at.localeCompare(b.at)).at(-1)?.parentId||null;}
// Cache only an exact structural signature; imported data cannot assert trust.
let treeValidation;
export function treeValid(s,events){
 const signature=JSON.stringify([s.gears.map(g=>g.id),events.map(e=>[e.gearId,e.parentId,e.at])]);
 if(treeValidation?.signature===signature)return treeValidation.valid;
 const ordered=events.slice().sort((a,b)=>a.at.localeCompare(b.at)),parents=new Map();
 let valid=true;
 for(let i=0;i<ordered.length&&valid;){
  const at=ordered[i].at;
  do{const e=ordered[i++];parents.set(e.gearId,e.parentId||null);}while(i<ordered.length&&ordered[i].at===at);
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
export function batchMove(s,changes,at){at=installationDate(at);ensure(at<=nowLocal(),'不能设置未来的装配时间');ensure(Array.isArray(changes)&&changes.length>0&&changes.length<500,'没有可保存的修改');const ids=new Set();for(const c of changes){ensure(s.gears.some(g=>g.id===c.gearId&&!g.deletedAt),'装备不存在或已删除');ensure(!ids.has(c.gearId),'装备重复');ids.add(c.gearId);ensure(c.parentId===null||s.gears.some(g=>g.id===c.parentId&&!g.deletedAt),'所属装备不存在或已删除');}
ensure(!(s.gearOperations||[]).some(op=>op.at>=at&&op.gearIds.some(id=>ids.has(id))),'请通过更换或库存记录修改这次装配。');
ensure(!s.events.some(e=>ids.has(e.gearId)&&e.at.slice(0,10)===at.slice(0,10)&&e.operationId),'该日期已有更换或库存记录，请编辑原记录。');
const rootStatuses=new Map(changes.map(c=>[c.gearId,c.parentId===null&&readGearStatus(s,c.gearId,at)==='stock'?'stock':'active']));
const events=s.events.filter(e=>!(ids.has(e.gearId)&&e.at.slice(0,10)===at.slice(0,10))).concat(changes.map(c=>{const old=s.events.find(e=>e.gearId===c.gearId&&e.at.slice(0,10)===at.slice(0,10));return {id:old?.id||uid(),gearId:c.gearId,parentId:c.parentId,at,allDay:true};}));ensure(treeValid(s,events),'所属装备不能是自身或子装备（含后续历史关系）');s.events=events;for(const c of changes)activateMovedGear(s,c.gearId,at,events.find(e=>e.gearId===c.gearId&&e.at===at)?.id,rootStatuses.get(c.gearId));return s;}
export function activateMovedGear(s,id,at,installationId,status='active'){
 const before=readOwnGearStatus(s,id,at);if(before===status||before==='retired')return;
 const existing=(s.gearStates||[]).find(e=>e.gearId===id&&e.at===at);
 ensure(!existing?.operationId,'该日期已有更换或库存记录，请编辑原记录。');
 s.gearStates=(s.gearStates||[]).filter(e=>!(e.gearId===id&&e.at===at));
 s.gearStates.push({id:existing?.id||uid(),gearId:id,status,at,installationId});
}
export function expand(s,roots,at,excluded=[],{allowInactiveRoots=false}={}){const result=[],seen=new Set(),ex=new Set(excluded);function visit(id,via){if(!id||seen.has(id)||ex.has(id))return;const g=s.gears.find(x=>x.id===id);if(!g||(g.deletedAt&&at>=g.deletedAt)||readGearStatus(s,id,at,false)!=='active'&&!(allowInactiveRoots&&via===null))return;seen.add(id);result.push({id,parentId:via});s.gears.filter(x=>parentAt(s,x.id,at)===id).forEach(x=>visit(x.id,id));}roots.forEach(id=>visit(id,null));return result;}
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
if(remoteId){const r=s.remoteGears.find(x=>x.id===remoteId&&!x.component);ensure(r&&['Bike','Shoes'].includes(r.type),'请选择可关联的 Bike / Shoes');ensure(type===r.type,'装备类型与远端类型不一致');ensure(!s.gears.some(g=>g.id!==input.id&&g.remoteId===remoteId),'该 ICU 装备已关联其他本地装备');}
const purchased=purchaseDate(input.purchased===undefined?(existing?.purchased||null):input.purchased);
const g={id:existing?.id||uid(),name,type,categoryId,remoteId,purchased,notes:String(input.notes||'').slice(0,3000),createdAt:existing?.createdAt||nowLocal(),retired:!!input.retired};if(input.condition!==undefined){ensure(['','unused','used'].includes(input.condition),'请选择装备状况。');g.condition=input.condition;}if(existing)Object.assign(existing,g);else s.gears.push(g);return g;}
export function saveAssignment(s,id,input){const a=s.activities.find(x=>x.id===id);ensure(a&&!a.summary&&!a.unavailable&&!a.deleted,'活动不可编辑，请先读取完整数据');const main=input.main||null;ensure(main===null||s.gears.some(g=>g.id===main&&(!g.deletedAt||a.main===main)&&['Bike','Shoes'].includes(g.type)),'主装备必须是 Bike / Shoes');const extras=[...new Set(input.extras||[])];ensure(extras.every(x=>s.gears.some(g=>g.id===x&&(!g.deletedAt||(a.extras||[]).includes(x)))),'附加装备无效');const excluded=[...new Set(input.excluded||[])];ensure(excluded.every(x=>s.gears.some(g=>g.id===x))&&!excluded.includes(main),'排除装备无效');
for(const selected of [main,...extras].filter(Boolean))ensure(readGearStatus(s,selected,a.at)==='active'||a.snapshot?.some(row=>row.id===selected),'该装备在活动当天未使用，请先调整使用日期。');
const same=sameUsage(a,{main,extras,excluded});let snapshot=same&&!input.rebuild&&!input.refreshAssembly?a.snapshot:expand(s,[main,...extras],a.at,excluded);
if(input.rebuild){a.equipmentDistance=equipmentDistanceIncluded(s,{...a,main,extras},snapshot);snapshot=distanceSnapshot(snapshot,a.equipmentDistance,s);}
else if(!same||input.refreshAssembly)snapshot=preserveDistanceSnapshot(snapshot,a);
Object.assign(a,{main,extras,excluded,snapshot,manual:true,unknown:false,error:null});a.pending=(s.gears.find(g=>g.id===main)?.remoteId||null)!==(a.remoteId||null);if(main&&!s.gears.find(g=>g.id===main)?.remoteId)a.pending=true;return a;}
function sameUsage(a,b){return a.main===b.main&&JSON.stringify(a.extras||[])===JSON.stringify(b.extras)&&JSON.stringify(a.excluded||[])===JSON.stringify(b.excluded);}
export function importGear(s,gears,{at=nowLocal()}={}){
ensure(Array.isArray(gears),'ICU Gear 返回格式无效');
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
// Keep the one-time source catalog separate from primary Gear writeback mappings.
s.remoteGears=filtered.map(g=>({id:String(g.id),name:g.name||String(g.id),type:g.type||'Equipment',component:!!g.component,component_ids:g.component_ids||[]}));
for(const g of filtered){
 const local=lookup(g.id);
 if(!g.component||!local||local.importedTotals)continue;
 if(![g.distance,g.time,g.activities].every(x=>Number.isFinite(x)&&x>=0))continue;
 local.importedTotals={distance:g.distance,seconds:g.time,count:g.activities,through:at};
}
s.gearImported=true;s.gearImportVersion=3;
return {added:imported.size,relations};
}
export function mergeActivities(s,rows,{historical=false}={}){ensure(Array.isArray(rows),'ICU 活动返回格式无效');let added=0,updated=0,unavailable=0;for(const r of rows){if(!r||!r.id)continue;let a=s.activities.find(x=>x.id===String(r.id));const stub=!r.start_date_local||!r.type;if(stub){unavailable++;if(a){a.unavailable=true;continue;}s.activities.push({id:String(r.id),name:r.name||'受限活动',at:r.start_date_local||'',type:r.type||'',distance:null,seconds:null,main:null,remoteId:null,snapshot:[],extras:[],excluded:[],unavailable:true});continue;}
const hasGear=Object.hasOwn(r,'gear');const remoteId=hasGear?(r.gear?.id?String(r.gear.id):null):(a?.remoteId||null);const complete={id:String(r.id),name:r.name||r.type,at:r.start_date_local,type:r.type,distance:Number.isFinite(r.distance)?r.distance:null,seconds:Number.isFinite(r.moving_time)?r.moving_time:(r.elapsed_time??null),source:r.source||'',...(typeof r.trainer==='boolean'?{trainer:r.trainer}:{}),remoteId,summary:false,unavailable:false,deleted:false};
if(a&&!a.summary){
 Object.assign(a,complete);delete a.remoteDeletedAt;
 if(!a.manual&&hasGear){
  const mapped=remoteId?s.gears.find(g=>g.remoteId===remoteId&&['Bike','Shoes'].includes(g.type)&&(!g.deletedAt||a.at<g.deletedAt))?.id||null:null;
  // Compare local ownership too: older syncs already refreshed remoteId without
  // following the Gear change, and a missing mapping may be added later.
  if((a.main||null)!==mapped){
   const snapshot=expand(s,[mapped,...(a.extras||[])],a.at,a.excluded||[],{allowInactiveRoots:true});
   a.snapshot=preserveDistanceSnapshot(snapshot,a);a.main=mapped;
   a.unknown=!!remoteId&&!mapped;a.error=null;
  }
 }
 a.pending=a.manual&&((a.main&&!s.gears.find(g=>g.id===a.main)?.remoteId)||((s.gears.find(g=>g.id===a.main)?.remoteId||null)!==remoteId));updated++;continue;}
const main=remoteId?s.gears.find(g=>g.remoteId===remoteId)?.id||null:null;
const assignment={main,extras:[],excluded:[],manual:false,pending:false,error:null,unknown:historical,snapshot:historical?(main?[{id:main,parentId:null}]:[]):expand(s,[main],complete.at,[],{allowInactiveRoots:true})};
const next={...complete,...assignment};next.equipmentDistance=equipmentDistanceIncluded(s,next,next.snapshot);next.snapshot=distanceSnapshot(next.snapshot,next.equipmentDistance,s);if(a)Object.assign(a,next);else{s.activities.push(next);added++;}}
return {added,updated,unavailable};}
export function stats(s,id){
const gear=s.gears.find(g=>g.id===id);
const baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
const activities=s.activities.filter(a=>!a.deleted&&!a.summary&&!a.unavailable&&(!baseline||a.at>baseline.through)&&a.snapshot?.some(x=>x.id===id));
return {count:(baseline?.count||0)+activities.length,distance:activities.reduce((v,a)=>v+(a.snapshot.find(x=>x.id===id).distanceIncluded===false?0:(a.distance||0)),baseline?.distance||0),seconds:activities.reduce((v,a)=>v+(a.seconds||0),baseline?.seconds||0)};
}
