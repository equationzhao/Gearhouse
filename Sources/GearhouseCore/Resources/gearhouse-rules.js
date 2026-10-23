
if(typeof structuredClone === 'undefined') globalThis.structuredClone = x => JSON.parse(JSON.stringify(x));
const modules = Object.create(null), cache = Object.create(null);
modules['node:crypto'] = () => ({randomUUID:()=>nativeUUID(),createHash:()=>{let value='';return {update(x){value+=String(x);return this;},digest(){return nativeHash(value);}};}});
function require(id){ if(!cache[id]) cache[id]=modules[id](); return cache[id]; }
modules["native-entry.js"] = function(){
const {readGearStatuses,readInventoryConflict} = require("lib/gear-state.mjs");
const {validateInventory,saveInventoryGear,readOperationOptions,previewGearOperation,applyGearOperation,previewOperationDeletion,deleteGearOperation,previewInventoryBatch,storeInventoryBatch} = require("lib/inventory.mjs");
const {ensureCategories,saveCategory,deleteCategory} = require("lib/categories.mjs");
const {empty,clone,ensure,nowLocal,installationDate,migrateInstallationDates,saveGear,deleteGear,restoreGear,batchMove,saveAssignment,importGear,mergeActivities,stats,treeValid} = require("lib/domain.mjs");
const {saveInstallation,deleteInstallation} = require("lib/history.mjs");
const {previewOrganization,applyOrganization} = require("lib/organize.mjs");
const {previewRecompute,applyRecompute} = require("lib/recompute.mjs");
const {previewPurge,purgeGear} = require("lib/purge.mjs");
const {mutateGearEvent,eventMetrics} = require("lib/gear-events.mjs");
const {addPhoto,editPhotos,attachEventPhotos,prunePhotos} = require("lib/photos.mjs");
const {createComponent} = require("lib/components.mjs");
const {addAttachment,deleteAttachment} = require("lib/attachments.mjs");
const {buildSnapshot} = require("public/snapshot.js");
const {gearActivityRows,filterUsageRange,summarizeUsage} = require("public/gear-activities.js");
const {syncPlan,retryDelay} = require("lib/auto-sync.mjs");
const {applyConfirmedDeletions} = require("lib/activity-deletions.mjs");

function stable(v){if(Array.isArray(v))return v.map(stable);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])]));return v;}
function sameSerialized(row,text){try{return JSON.stringify(stable(row))===JSON.stringify(stable(JSON.parse(text)));}catch{return false;}}
function normalized(raw){
 if(!raw)return empty();
 if(!Array.isArray(raw.events)) { // Migrate the initial Swift prototype once.
  const s=empty();
  s.gears=(raw.gears||[]).map(g=>({...g,sourceGearId:g.remoteID,remoteId:['Bike','Shoes'].includes(g.type)?g.remoteID:null}));
  s.events=s.gears.filter(g=>g.parentID).map(g=>({id: nativeUUID(),gearId:g.id,parentId:g.parentID,at:'2000-01-01T00:00:00'}));
  s.activities=(raw.activities||[]).map(a=>({...a,at:(a.at||'').replace(/Z$/,'').slice(0,19),main:a.mainGearID||null,remoteId:a.remoteGearID||null,extras:[],excluded:[],snapshot:a.mainGearID?[{id:a.mainGearID,parentId:null,...(a.equipmentDistanceIncluded===false?{distanceIncluded:false}:{})}]:[],equipmentDistance:a.equipmentDistanceIncluded,manual:false}));
  // Prototype dates were absolute ISO instants; restore the canonical Shanghai wall clock.
  s.activities.forEach((a,i)=>{const d=Date.parse(raw.activities[i].at);if(Number.isFinite(d))a.at=new Date(d+8*3600000).toISOString().slice(0,19);});
  s.nativePrototypeMigration=true;return s;
 }
 ensure(Array.isArray(raw.gears)&&Array.isArray(raw.activities),'备份数据无效');
 delete raw.configs;raw.gearEvents??=[];raw.photos??=[];raw.syncLog??=[];raw.remoteGears??=[];
 ensure(treeValid(raw,raw.events),'装配历史存在环路');return raw;
}
function view(s,date){
 if(date){const snapshot=buildSnapshot(s,date,nowLocal());return {...snapshot,gearStatuses:readGearStatuses(snapshot,snapshot.snapshotView.cutoff)};}
 return {...s,gearStatuses:readGearStatuses(s,nowLocal()),inventoryConflicts:s.activities.filter(a=>!a.deleted&&a.at&&readInventoryConflict(s,a)).map(a=>a.id),statistics:Object.fromEntries(s.gears.map(g=>[g.id,stats(s,g.id)])),eventStatistics:Object.fromEntries((s.gearEvents||[]).map(e=>[e.id,eventMetrics(s,e)]))};
}
function call(serialized){
 try{
  const {state,action,input={}}=JSON.parse(serialized),s=validateInventory(ensureCategories(normalized(state)));let result=null,mutate=true;
  if(input.revision!==undefined)ensure(s.revision===input.revision,'数据已更新，请重新预览');
  switch(action){
   case 'initialize':migrateInstallationDates(s);break;
   case 'view':return JSON.stringify({result:view(s,input.date)});
   case 'usage':{const rows=filterUsageRange(gearActivityRows(input.date?buildSnapshot(s,input.date,nowLocal()):s,input.id),input);return JSON.stringify({result:{rows,summary:summarizeUsage(rows)}});}
   case 'category-save':result=saveCategory(s,input);break;
   case 'category-delete':result=deleteCategory(s,input);break;
   case 'gear':result=saveInventoryGear(s,input);break;
   case 'inventory-options':result=readOperationOptions(s,input);mutate=false;break;
   case 'inventory-preview':result=previewGearOperation(s,input);mutate=false;break;
   case 'inventory-batch-preview':result=previewInventoryBatch(s,input);mutate=false;break;
   case 'inventory-batch':result=storeInventoryBatch(s,input);break;
   case 'inventory-save':result=applyGearOperation(s,input);break;
   case 'inventory-delete-preview':result=previewOperationDeletion(s,input);mutate=false;break;
   case 'inventory-delete':result=deleteGearOperation(s,input);break;
   case 'gear-copy':{
    const source=s.gears.find(g=>g.id===input.sourceId&&!g.deletedAt);ensure(source,'装备不存在或已删除');
    const fields=input.gear||{};
    result=saveInventoryGear(s,{name:fields.name??source.name,type:source.type,categoryId:source.categoryId,notes:fields.notes??source.notes,purchased:fields.purchased??null,condition:fields.condition??'',retired:false,remoteId:null,placement:'stock'});break;
   }
   case 'component':result=createComponent(s,input);break;
   case 'delete':result=deleteGear(s,input.id);break;
   case 'restore':result=restoreGear(s,input.id);break;
   case 'hidden':{const g=s.gears.find(g=>g.id===input.id&&!g.deletedAt);ensure(g,'装备不存在');g.hidden=!!input.hidden;break;}
   case 'moves':batchMove(s,input.changes,input.at);result={ok:true};break;
   case 'history-save':result=saveInstallation(s,input);break;
   case 'history-delete':result=deleteInstallation(s,input);break;
   case 'organize-preview':result=previewOrganization(s,input.changes);mutate=false;break;
   case 'organize':result=applyOrganization(s,input.changes);break;
   case 'recompute-preview':result=previewRecompute(s,input);mutate=false;break;
   case 'recompute':{const p=previewRecompute(s,input);ensure(!p.totals.some(t=>t.baselineDisabled)||input.baselineConfirmed,'请确认停用 ICU 历史基数');result=applyRecompute(s,input);break;}
   case 'purge-preview':result=previewPurge(s,input.id);mutate=false;break;
   case 'purge':result=purgeGear(s,input);break;
   case 'event-save':result=mutateGearEvent(s,'save',input);attachEventPhotos(s,result.id,input.event);break;
   case 'event-delete':result=mutateGearEvent(s,'delete',input);break;
   case 'photo-add':result=addPhoto(s,input,input.metadata);break;
   case 'photo-edit':result=editPhotos(s,input);break;
   case 'attachment-add':result=addAttachment(s,input);break;
   case 'attachment-delete':result=deleteAttachment(s,input);break;
   case 'assignment-preview':result=saveAssignment(s,input.id,input.assignment);mutate=false;break;
   case 'assignment':result=saveAssignment(s,input.id,input.assignment);break;
   case 'account':ensure(input.id,'账户无效');ensure(!s.account||s.account.id===input.id,'此数据库属于其他 ICU 账户');s.account=input;break;
   case 'gear-import':{
    result=importGear(s,input.rows);
    if(s.nativePrototypeMigration||s.gears.some(g=>g.remoteID!==undefined&&g.sourceComponent===undefined)){
     for(const r of input.rows){
      const g=s.gears.find(g=>g.sourceGearId===String(r.id));
      if(g&&g.remoteID!==undefined&&g.sourceComponent===undefined){
       g.sourceComponent=!!r.component;g.retired=!!r.retired;g.retiredAt=typeof r.retired==='string'?r.retired:null;
       if(!g.purchased)g.purchased=r.purchased||null;
       g.remoteId=!r.component&&['Bike','Shoes'].includes(r.type)?String(r.id):null;
      }
     }
     const parents=new Map(),lookup=id=>s.gears.find(g=>g.sourceGearId===String(id)||g.remoteId===String(id));
     for(const r of input.rows){const p=lookup(r.id);if(!p)continue;for(const id of r.component_ids||[]){const child=lookup(id);if(!child||s.events.some(e=>e.gearId===child.id))continue;const choices=parents.get(child.id)||new Set();choices.add(p.id);parents.set(child.id,choices);}}
     for(const [id,choices] of parents)if(choices.size===1){const event={id:nativeUUID(),gearId:id,parentId:[...choices][0],at:installationDate(nowLocal()),allDay:true};if(treeValid(s,[...s.events,event]))s.events.push(event);}
     delete s.nativePrototypeMigration;
    }
    ensureCategories(s);
    break;
   }
   case 'sync-plan':return JSON.stringify({result:syncPlan(s.autoSync||{})});
   case 'sync-settings':s.autoSync={...(s.autoSync||{}),...input};break;
   case 'sync-rows':{
    const before=new Map(s.activities.map(a=>[a.id,JSON.stringify(a)]));
    const rows=input.rows.filter(r=>{const a=s.activities.find(a=>a.id===String(r.id));return (a?.lastWriteAt||null)===(input.writes?.[String(r.id)]||null);});
    const recovered=(input.recovered||[]).filter(r=>sameSerialized(s.activities.find(a=>a.id===String(r.row.id)),r.before)).map(r=>r.row);
    result=mergeActivities(s,[...rows,...recovered],{historical:input.historical});result.updated=s.activities.filter(a=>before.has(a.id)&&before.get(a.id)!==JSON.stringify(a)).length;
    result.removed=applyConfirmedDeletions(s,(input.deleted||[]).filter(r=>sameSerialized(s.activities.find(a=>a.id===r.id),r.before)).map(r=>({...r,before:JSON.stringify(s.activities.find(a=>a.id===r.id))})),new Date().toISOString());
    s.lastSync={at:new Date().toISOString(),oldest:input.from,newest:input.to};
    s.syncLog.unshift({...s.lastSync,...result});s.syncLog=s.syncLog.slice(0,1000);
    if(input.saveResume!==false)s.autoSync={...(s.autoSync||{}),resume:{next:input.next}};break;
   }
   case 'write-result':{const a=s.activities.find(a=>a.id===input.id);ensure(a,'活动不存在');if(input.error)a.error=input.error;else {ensure((a.main||null)===(input.main||null),'活动已有后续修改');a.remoteId=input.target;a.pending=false;a.error=null;a.lastWriteAt=new Date().toISOString();}break;}
   default:throw Error('未知操作');
  }
  if(mutate){prunePhotos(s);s.revision=(s.revision||0)+1;}
  return JSON.stringify(mutate?{state:s,result}:{result});
 }catch(e){return JSON.stringify({error:e.message});}
}

return {call};
};
modules["lib/gear-state.mjs"] = function(){
// Read dated equipment status without changing saved activity membership.
function readOwnGearStatus(s,id,at,includeUndatedRetirement=true){
 const gear=s.gears.find(g=>g.id===id);
 const row=(s.gearStates||[]).filter(e=>e.gearId===id&&e.at<=at).sort((a,b)=>a.at.localeCompare(b.at)).at(-1);
 if(row)return row.status;
 return gear?.retired&&(gear.retiredAt?gear.retiredAt<=at:includeUndatedRetirement)?'retired':'active';
}
function readGearStatus(s,id,at,includeUndatedRetirement=true){
 const seen=new Set();let current=id,status='active';
 while(current&&!seen.has(current)){
  seen.add(current);status=readOwnGearStatus(s,current,at,includeUndatedRetirement);
  if(status==='retired')return status;
  const parent=s.events.filter(e=>e.gearId===current&&e.at<=at).sort((a,b)=>a.at.localeCompare(b.at)).at(-1)?.parentId;
  if(!parent)return status;
  current=parent;
 }
 return status;
}
function readGearStatuses(s,at){return Object.fromEntries(s.gears.map(g=>[g.id,readGearStatus(s,g.id,at)]));}
function readInventoryConflict(s,activity){
 return [activity.main,...(activity.extras||[])].filter(Boolean).some(id=>readGearStatus(s,id,activity.at,false)!=='active');
}

return {readOwnGearStatus,readGearStatus,readGearStatuses,readInventoryConflict};
};
modules["lib/inventory.mjs"] = function(){
const {clone,ensure,uid,nowLocal,installationDate,parentAt,saveGear,batchMove,treeValid,expand} = require("lib/domain.mjs");
const {readGearStatus,readOwnGearStatus,readGearStatuses} = require("lib/gear-state.mjs");

const conflictMessage='该日期已有更换或库存记录，请编辑原记录。';
const laterMessage='已有后续装配或库存记录，请先处理后续记录。';
function findGear(s,id){const gear=s.gears.find(g=>g.id===id&&!g.deletedAt);ensure(gear,'装备不存在或已删除');return gear;}
function readCategory(gear){return gear.categoryId||gear.type;}
function readChildren(s,id,at){return s.gears.filter(g=>!g.deletedAt&&parentAt(s,g.id,at)===id);}
function readDescendants(s,ids,at){
 const result=new Set(ids);let count;
 do{count=result.size;for(const gear of s.gears)if(result.has(parentAt(s,gear.id,at)))result.add(gear.id);}while(count!==result.size);
 return result;
}
function ensureUnchangedFuture(s,ids,at){
 ensure(!s.events.some(e=>e.at>at&&(ids.has(e.gearId)||ids.has(e.parentId)))&&!(s.gearStates||[]).some(e=>e.at>at&&ids.has(e.gearId)),laterMessage);
}
function writeStatus(s,id,status,at,operationId){
 s.gearStates??=[];
 const previous=s.gearStates.find(e=>e.gearId===id&&e.at===at);
 ensure(!previous?.operationId||previous.operationId===operationId,conflictMessage);
 s.gearStates=s.gearStates.filter(e=>!(e.gearId===id&&e.at===at));
 s.gearStates.push({id:previous?.id||uid(),gearId:id,status,at,...(operationId?{operationId}:{})});
}
function serializeRows(rows){return JSON.stringify(rows.slice().sort((a,b)=>a.id.localeCompare(b.id)).map(row=>Object.fromEntries(Object.entries(row).sort(([a],[b])=>a.localeCompare(b)))));}
function readAffectedActivities(s,next,from){
 return s.activities.filter(a=>{
  if(a.deleted||a.summary||a.unavailable||!a.at||a.at<from)return false;
  const before=expand(s,[a.main,...(a.extras||[])],a.at,a.excluded||[]),after=expand(next,[a.main,...(a.extras||[])],a.at,a.excluded||[]);
  const changed=new Set([...before.filter(row=>!after.some(other=>other.id===row.id&&other.parentId===row.parentId)),...after.filter(row=>!before.some(other=>other.id===row.id&&other.parentId===row.parentId))].map(row=>row.id));
  if(!changed.size)return false;
  const saved=(a.snapshot||[]).filter(row=>changed.has(row.id)).map(({id,parentId})=>({id,parentId:parentId||null}));
  return serializeRows(saved)!==serializeRows(after.filter(row=>changed.has(row.id)));
 });
}
function removeOperation(s,id){
 const operation=(s.gearOperations||[]).find(op=>op.id===id);ensure(operation,'更换或库存记录已不存在，请重新打开。');
 for(const gearID of operation.gearIds)findGear(s,gearID);
 const ids=readDescendants(s,operation.gearIds,operation.at);
 ensureUnchangedFuture(s,ids,operation.at);
 for(const [field,before,after] of [['events','beforeEvents','afterEvents'],['gearStates','beforeStates','afterStates']]){
  const actual=(s[field]||[]).filter(e=>e.operationId===id);
  ensure(serializeRows(actual)===serializeRows(operation[after]),'相关记录已修改，请重新打开后检查。');
  s[field]=(s[field]||[]).filter(e=>e.operationId!==id).concat(clone(operation[before]));
 }
 s.gearOperations=s.gearOperations.filter(op=>op.id!==id);
 ensure(treeValid(s,s.events),'装配历史存在环路');
 return operation;
}
function prepareState(s,input){const next=clone(s);if(input.operationId)removeOperation(next,input.operationId);return next;}
function validateInventory(s){
 for(const field of ['gearStates','gearOperations'])ensure(s[field]===undefined||Array.isArray(s[field]),'库存记录不完整，请选择完整备份。');
 const ids=new Set(),days=new Set(),known=new Set(s.gears.map(g=>g.id));
 for(const row of s.gearStates||[]){
  ensure(row.id&&known.has(row.gearId)&&!ids.has(row.id)&&['active','stock','retired'].includes(row.status),'库存记录不完整，请选择完整备份。');
  ensure(installationDate(row.at)===row.at&&!days.has(row.gearId+row.at),'库存记录不完整，请选择完整备份。');
  ids.add(row.id);days.add(row.gearId+row.at);
 }
 const operations=new Set();
 for(const op of s.gearOperations||[]){
  ensure(op.id&&!operations.has(op.id)&&['replace','store','activate','install'].includes(op.kind)&&known.has(op.gearId)&&Array.isArray(op.gearIds)&&op.gearIds.every(id=>known.has(id)),'库存记录不完整，请选择完整备份。');
  ensure(['beforeEvents','afterEvents','beforeStates','afterStates'].every(field=>Array.isArray(op[field])),'库存记录不完整，请选择完整备份。');
  ensure(installationDate(op.at)===op.at,'库存记录不完整，请选择完整备份。');
  ensure(serializeRows(s.events.filter(e=>e.operationId===op.id))===serializeRows(op.afterEvents)&&serializeRows((s.gearStates||[]).filter(e=>e.operationId===op.id))===serializeRows(op.afterStates),'库存记录不完整，请选择完整备份。');
  ensure([...op.beforeEvents,...op.afterEvents].every(e=>known.has(e.gearId)&&(!e.parentId||known.has(e.parentId)))&&[...op.beforeStates,...op.afterStates].every(e=>known.has(e.gearId)&&['active','stock','retired'].includes(e.status)),'库存记录不完整，请选择完整备份。');
  operations.add(op.id);
 }
 for(const row of [...s.events,...(s.gearStates||[])])ensure(!row.operationId||operations.has(row.operationId),'库存记录不完整，请选择完整备份。');
 return s;
}
function saveInventoryGear(s,input){
 const next=clone(s),existing=next.gears.find(g=>g.id===input.id),at=installationDate(nowLocal());
 const oldStatus=existing?readOwnGearStatus(next,existing.id,nowLocal()):'active';
 const gear=saveGear(next,{...input,...(existing?{retired:!!existing.retired}:{})});
 if(input.condition!==undefined){ensure(['','unused','used'].includes(input.condition),'请选择装备状况。');gear.condition=input.condition;}
 if(existing&&input.retired!==undefined&&input.retired!==(oldStatus==='retired')){
  writeStatus(next,gear.id,input.retired?'retired':'active',at);
 }
 if(!existing&&input.placement==='stock'){const entered=installationDate(input.purchased||nowLocal());ensure(entered<=nowLocal(),'购买日期不能晚于今天。');writeStatus(next,gear.id,'stock',entered);}
 Object.assign(s,next);return gear;
}
function readOperationOptions(s,input){
 const next=prepareState(s,input),at=installationDate(input.at||nowLocal()),gear=findGear(next,input.gearId);
 const descendants=readDescendants(next,[gear.id],at);
 const candidates=next.gears.filter(g=>g.id!==gear.id&&!g.deletedAt&&!descendants.has(g.id)&&readCategory(g)===readCategory(gear)&&readGearStatus(next,g.id,at)==='stock');
 const ancestors=new Set();let current=parentAt(next,gear.id,at);while(current&&!ancestors.has(current)){ancestors.add(current);current=parentAt(next,current,at);}
 const parents=next.gears.filter(g=>!g.deletedAt&&!descendants.has(g.id)&&readGearStatus(next,g.id,at)!=='retired');
 return {revision:s.revision,gear,parentId:parentAt(next,gear.id,at),status:readGearStatus(next,gear.id,at),candidates:candidates.filter(g=>!ancestors.has(g.id)),parents,children:readChildren(next,gear.id,at),statuses:readGearStatuses(next,at)};
}
function planOperation(s,input){
 const next=prepareState(s,input),at=installationDate(input.at||nowLocal());ensure(at<=nowLocal(),'不能设置未来的装配时间');
 const previous=(s.gearOperations||[]).find(op=>op.id===input.operationId);
 const recomputeFrom=previous&&previous.at<at?previous.at:at;
 const gear=findGear(next,input.gearId),kind=input.kind;ensure(['replace','store','activate','install'].includes(kind),'请选择装备操作。');
 const operationId=input.operationId||uid(),changes=[],statuses=[],gearIds=new Set([gear.id]);
 let replacement=null,parentId=parentAt(next,gear.id,at),created=false;
 if(kind==='replace'){
  ensure(parentId,'该装备在所选日期未装配，请选择其他日期。');
  ensure(readGearStatus(next,gear.id,at)!=='retired','请先恢复使用，再更换装备。');
  if(input.newGear){
   ensure(!input.newGear.id,'请创建新装备');
   ensure(!input.newGear.categoryId||input.newGear.categoryId===readCategory(gear),'只能更换同一类别的装备。');
   replacement=saveGear(next,{...input.newGear,categoryId:readCategory(gear),type:gear.type,retired:false,remoteId:null});
   replacement.condition=input.newGear.condition??'unused';
   ensure(['unused','used',''].includes(replacement.condition),'请选择装备状况。');
   writeStatus(next,replacement.id,'stock',installationDate(replacement.purchased||at));created=true;
  }else replacement=findGear(next,input.replacementId);
  ensure(replacement.id!==gear.id&&readCategory(replacement)===readCategory(gear),'只能更换同一类别的装备。');
  ensure(readGearStatus(next,replacement.id,at)==='stock','所选装备不在库存，请重新选择。');
  ensure(!replacement.purchased||replacement.purchased.slice(0,10)<=at.slice(0,10),'装配日期不能早于新件的购买日期。');
  let ancestor=gear.id;const seen=new Set();while(ancestor&&!seen.has(ancestor)){ensure(ancestor!==replacement.id,'不能使用自身或上级装备进行更换。');seen.add(ancestor);ancestor=parentAt(next,ancestor,at);}
  ensure(!readDescendants(next,[gear.id],at).has(replacement.id),'不能使用自身或组件进行更换。');
  const destination=input.destination||'stock';ensure(['stock','retired'].includes(destination),'请选择旧件去向。');
  changes.push({gearId:gear.id,parentId:null},{gearId:replacement.id,parentId});
  statuses.push([gear.id,destination],[replacement.id,'active']);gearIds.add(replacement.id);
  const children=readChildren(next,gear.id,at),selected=[...new Set(input.childIds||[])];
  ensure(selected.every(id=>children.some(g=>g.id===id)),'所选组件已改变，请重新选择。');
  for(const id of selected){changes.push({gearId:id,parentId:replacement.id});gearIds.add(id);}
 }else if(kind==='store'){
  ensure(readGearStatus(next,gear.id,at)!=='retired','请先恢复使用，再放入库存。');
  ensure(readGearStatus(next,gear.id,at)!=='stock'||parentId,'该装备已在库存。');
  if(parentId)changes.push({gearId:gear.id,parentId:null});statuses.push([gear.id,'stock']);
 }else if(kind==='activate'){
  if(parentId)changes.push({gearId:gear.id,parentId:null});statuses.push([gear.id,'active']);
 }else{
  ensure(readGearStatus(next,gear.id,at)==='stock','所选装备不在库存，请重新选择。');
  const target=findGear(next,input.parentId);ensure(readGearStatus(next,target.id,at)!=='retired','请先恢复所属装备。');
  parentId=target.id;changes.push({gearId:gear.id,parentId});statuses.push([gear.id,'active']);
 }
 const affected=readDescendants(next,[...gearIds],at);
 ensureUnchangedFuture(next,affected,at);
 for(const id of gearIds){
  ensure(!next.events.some(e=>e.gearId===id&&e.at===at&&e.operationId)&&!(next.gearStates||[]).some(e=>e.gearId===id&&e.at===at&&e.operationId),conflictMessage);
 }
 const moved=new Set(changes.map(c=>c.gearId)),stateIds=new Set(statuses.map(([id])=>id));
 const beforeEvents=clone(next.events.filter(e=>moved.has(e.gearId)&&e.at===at));
 const beforeStates=clone((next.gearStates||[]).filter(e=>stateIds.has(e.gearId)&&e.at===at));
 if(changes.length){batchMove(next,changes,at);for(const event of next.events)if(moved.has(event.gearId)&&event.at===at)event.operationId=operationId;}
 for(const [id,status] of statuses)writeStatus(next,id,status,at,operationId);
 const operation={id:operationId,kind,gearId:gear.id,gearIds:[...gearIds],at,parentId,replacementId:replacement?.id||null,destination:input.destination||'stock',childIds:input.childIds||[],created,
  beforeEvents,beforeStates,afterEvents:clone(next.events.filter(e=>e.operationId===operationId)),afterStates:clone((next.gearStates||[]).filter(e=>e.operationId===operationId))};
 (next.gearOperations??=[]).push(operation);
 const affectedActivities=readAffectedActivities(s,next,recomputeFrom);
 const preview={...operation,revision:s.revision,affectedActivities:affectedActivities.length,sameDayActivities:s.activities.filter(a=>!a.deleted&&a.at?.slice(0,10)===at.slice(0,10)&&a.snapshot?.some(row=>affected.has(row.id)||row.id===parentId)).length,newName:replacement?.name||null,oldName:gear.name,parentName:next.gears.find(g=>g.id===parentId)?.name||null,transferred:changes.filter(c=>c.gearId!==gear.id&&c.gearId!==replacement?.id).map(c=>({id:c.gearId,name:findGear(next,c.gearId).name})),recomputeGearId:parentId||gear.id,recomputeFrom,recomputeGearIds:[...new Set([parentId||gear.id,...(previous?[previous.parentId||previous.gearId]:[])])]};
 return {next,preview};
}
function previewGearOperation(s,input){return planOperation(s,input).preview;}
function applyGearOperation(s,input){const {next,preview}=planOperation(s,input);Object.assign(s,next);return preview;}
function previewOperationDeletion(s,input){const next=clone(s),operation=removeOperation(next,input.id);return {...operation,revision:s.revision};}
function deleteGearOperation(s,input){ensure(input.confirmed,'请确认删除记录');const next=clone(s),operation=removeOperation(next,input.id);Object.assign(s,next);return operation;}

function planInventoryBatch(s,input){
 ensure(Array.isArray(input.gearIds)&&input.gearIds.length>0&&input.gearIds.length<500,'请选择要移动的装备。');
 const at=installationDate(input.at||nowLocal()),chosen=new Set(input.gearIds);
 const roots=[...chosen].filter(id=>{let parent=parentAt(s,id,at),seen=new Set();while(parent&&!seen.has(parent)){if(chosen.has(parent))return false;seen.add(parent);parent=parentAt(s,parent,at);}return true;});
 let next=clone(s);const rows=[];
 for(const id of roots){const result=planOperation(next,{kind:'store',gearId:id,at});next=result.next;rows.push(result.preview);}
 const affected=readAffectedActivities(s,next,at).length;
 return {next,preview:{revision:s.revision,rows,affectedActivities:affected}};
}
function previewInventoryBatch(s,input){return planInventoryBatch(s,input).preview;}
function storeInventoryBatch(s,input){const {next,preview}=planInventoryBatch(s,input);Object.assign(s,next);return preview;}

return {validateInventory,saveInventoryGear,readOperationOptions,previewGearOperation,applyGearOperation,previewOperationDeletion,deleteGearOperation,previewInventoryBatch,storeInventoryBatch};
};
modules["lib/domain.mjs"] = function(){
const {randomUUID} = require("node:crypto");
const {ensureCategories} = require("lib/categories.mjs");
const {readGearStatus,readOwnGearStatus} = require("lib/gear-state.mjs");
const uid=()=>randomUUID();
const clone=x=>structuredClone(x);
const empty=()=>ensureCategories({version:1,revision:0,account:null,gears:[],events:[],gearEvents:[],activities:[],remoteGears:[],gearImported:false,lastSync:null,syncLog:[]});
function ensure(ok,message){if(!ok){const e=new Error(message);e.status=400;throw e;}}
function dateTime(value){ensure(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(value)&&Number.isFinite(Date.parse(value+'Z')),'时间格式无效');const full=value.length===16?value+':00':value;ensure(new Date(full+'Z').toISOString().slice(0,19)===full,'时间格式无效');return full;}
function installationDate(value){
 ensure(typeof value==='string','日期无效');
 return dateTime(value.length===10?value+'T00:00:00':value).slice(0,10)+'T00:00:00';
}
function migrateInstallationDates(s){
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
function today(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai'}).format(new Date());}
function nowLocal(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date()).replace(' ','T');}
function parentAt(s,id,at){return s.events.filter(e=>e.gearId===id&&e.at<=at).sort((a,b)=>a.at.localeCompare(b.at)).at(-1)?.parentId||null;}
// Cache only an exact structural signature; imported data cannot assert trust.
let treeValidation;
function treeValid(s,events){
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
function batchMove(s,changes,at){at=installationDate(at);ensure(at<=nowLocal(),'不能设置未来的装配时间');ensure(Array.isArray(changes)&&changes.length>0&&changes.length<500,'没有可保存的修改');const ids=new Set();for(const c of changes){ensure(s.gears.some(g=>g.id===c.gearId&&!g.deletedAt),'装备不存在或已删除');ensure(!ids.has(c.gearId),'装备重复');ids.add(c.gearId);ensure(c.parentId===null||s.gears.some(g=>g.id===c.parentId&&!g.deletedAt),'所属装备不存在或已删除');}
ensure(!(s.gearOperations||[]).some(op=>op.at>=at&&op.gearIds.some(id=>ids.has(id))),'请通过更换或库存记录修改这次装配。');
ensure(!s.events.some(e=>ids.has(e.gearId)&&e.at.slice(0,10)===at.slice(0,10)&&e.operationId),'该日期已有更换或库存记录，请编辑原记录。');
const rootStatuses=new Map(changes.map(c=>[c.gearId,c.parentId===null&&readGearStatus(s,c.gearId,at)==='stock'?'stock':'active']));
const events=s.events.filter(e=>!(ids.has(e.gearId)&&e.at.slice(0,10)===at.slice(0,10))).concat(changes.map(c=>{const old=s.events.find(e=>e.gearId===c.gearId&&e.at.slice(0,10)===at.slice(0,10));return {id:old?.id||uid(),gearId:c.gearId,parentId:c.parentId,at,allDay:true};}));ensure(treeValid(s,events),'所属装备不能是自身或子装备（含后续历史关系）');s.events=events;for(const c of changes)activateMovedGear(s,c.gearId,at,events.find(e=>e.gearId===c.gearId&&e.at===at)?.id,rootStatuses.get(c.gearId));return s;}
function activateMovedGear(s,id,at,installationId,status='active'){
 const before=readOwnGearStatus(s,id,at);if(before===status||before==='retired')return;
 const existing=(s.gearStates||[]).find(e=>e.gearId===id&&e.at===at);
 ensure(!existing?.operationId,'该日期已有更换或库存记录，请编辑原记录。');
 s.gearStates=(s.gearStates||[]).filter(e=>!(e.gearId===id&&e.at===at));
 s.gearStates.push({id:existing?.id||uid(),gearId:id,status,at,installationId});
}
function expand(s,roots,at,excluded=[],{allowInactiveRoots=false}={}){const result=[],seen=new Set(),ex=new Set(excluded);function visit(id,via){if(!id||seen.has(id)||ex.has(id))return;const g=s.gears.find(x=>x.id===id);if(!g||(g.deletedAt&&at>=g.deletedAt)||readGearStatus(s,id,at,false)!=='active'&&!(allowInactiveRoots&&via===null))return;seen.add(id);result.push({id,parentId:via});s.gears.filter(x=>parentAt(s,x.id,at)===id).forEach(x=>visit(x.id,id));}roots.forEach(id=>visit(id,null));return result;}
function equipmentDistanceIncluded(s,a,rows=[]){
 const used=new Set([a.main,...(a.extras||[]),...rows.map(x=>x.id)]);
 return a.type!=='VirtualRide'&&a.trainer!==true&&!s.gears.some(g=>g.type==='Trainer'&&used.has(g.id));
}
function distanceSnapshot(rows,included,s){
 // Persist the decision per gear: category edits never reinterpret saved history.
 return rows.map(({distanceIncluded,...row})=>{
  const gear=s?.gears.find(g=>g.id===row.id);
  const category=s?.gearCategories?.find(c=>c.id===(gear?.categoryId||gear?.type));
  return included||category?.indoorDistance===true?row:{...row,distanceIncluded:false};
 });
}
function preserveDistanceSnapshot(rows,a){
 // Missing flags belong to legacy history and continue to count distance.
 return rows.map(row=>{const old=a.snapshot?.find(x=>x.id===row.id);return (old?old.distanceIncluded:a.equipmentDistance)===false?{...row,distanceIncluded:false}:row;});
}
function deleteGear(s,id){
const g=s.gears.find(x=>x.id===id);ensure(g,'装备不存在');ensure(!g.deletedAt,'装备已删除');
const at=nowLocal();
ensure(!s.gears.some(x=>!x.deletedAt&&parentAt(s,x.id,at)===id),'请先移出该装备下的组件');
g.deletedAt=at;return g;
}
function restoreGear(s,id){
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
function saveGear(s,input){const existing=s.gears.find(g=>g.id===input.id);ensure(!existing?.deletedAt,'请先恢复装备');const name=String(input.name||'').trim();ensure(name.length>0&&name.length<=160,'请输入装备名称');const requestedType=String(input.type||existing?.type||'Equipment');
const categoryId=input.categoryId||(input.type&&input.type!==existing?.type?requestedType:existing?.categoryId||requestedType);
const category=s.gearCategories.find(c=>c.id===categoryId);ensure(category,'请选择装备类别。');
const type=category.baseType;let remoteId=input.remoteId||null;
if(remoteId){const r=s.remoteGears.find(x=>x.id===remoteId&&!x.component);ensure(r&&['Bike','Shoes'].includes(r.type),'请选择可关联的 Bike / Shoes');ensure(type===r.type,'装备类型与远端类型不一致');ensure(!s.gears.some(g=>g.id!==input.id&&g.remoteId===remoteId),'该 ICU 装备已关联其他本地装备');}
const purchased=purchaseDate(input.purchased===undefined?(existing?.purchased||null):input.purchased);
const g={id:existing?.id||uid(),name,type,categoryId,remoteId,purchased,notes:String(input.notes||'').slice(0,3000),createdAt:existing?.createdAt||nowLocal(),retired:!!input.retired};if(input.condition!==undefined){ensure(['','unused','used'].includes(input.condition),'请选择装备状况。');g.condition=input.condition;}if(existing)Object.assign(existing,g);else s.gears.push(g);return g;}
function saveAssignment(s,id,input){const a=s.activities.find(x=>x.id===id);ensure(a&&!a.summary&&!a.unavailable&&!a.deleted,'活动不可编辑，请先读取完整数据');const main=input.main||null;ensure(main===null||s.gears.some(g=>g.id===main&&(!g.deletedAt||a.main===main)&&['Bike','Shoes'].includes(g.type)),'主装备必须是 Bike / Shoes');const extras=[...new Set(input.extras||[])];ensure(extras.every(x=>s.gears.some(g=>g.id===x&&(!g.deletedAt||(a.extras||[]).includes(x)))),'附加装备无效');const excluded=[...new Set(input.excluded||[])];ensure(excluded.every(x=>s.gears.some(g=>g.id===x))&&!excluded.includes(main),'排除装备无效');
for(const selected of [main,...extras].filter(Boolean))ensure(readGearStatus(s,selected,a.at)==='active'||a.snapshot?.some(row=>row.id===selected),'该装备在活动当天未使用，请先调整使用日期。');
const same=sameUsage(a,{main,extras,excluded});let snapshot=same&&!input.rebuild&&!input.refreshAssembly?a.snapshot:expand(s,[main,...extras],a.at,excluded);
if(input.rebuild){a.equipmentDistance=equipmentDistanceIncluded(s,{...a,main,extras},snapshot);snapshot=distanceSnapshot(snapshot,a.equipmentDistance,s);}
else if(!same||input.refreshAssembly)snapshot=preserveDistanceSnapshot(snapshot,a);
Object.assign(a,{main,extras,excluded,snapshot,manual:true,unknown:false,error:null});a.pending=(s.gears.find(g=>g.id===main)?.remoteId||null)!==(a.remoteId||null);if(main&&!s.gears.find(g=>g.id===main)?.remoteId)a.pending=true;return a;}
function sameUsage(a,b){return a.main===b.main&&JSON.stringify(a.extras||[])===JSON.stringify(b.extras)&&JSON.stringify(a.excluded||[])===JSON.stringify(b.excluded);}
function importGear(s,gears,{at=nowLocal()}={}){
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
function mergeActivities(s,rows,{historical=false}={}){ensure(Array.isArray(rows),'ICU 活动返回格式无效');let added=0,updated=0,unavailable=0;for(const r of rows){if(!r||!r.id)continue;let a=s.activities.find(x=>x.id===String(r.id));const stub=!r.start_date_local||!r.type;if(stub){unavailable++;if(a){a.unavailable=true;continue;}s.activities.push({id:String(r.id),name:r.name||'受限活动',at:r.start_date_local||'',type:r.type||'',distance:null,seconds:null,main:null,remoteId:null,snapshot:[],extras:[],excluded:[],unavailable:true});continue;}
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
function stats(s,id){
const gear=s.gears.find(g=>g.id===id);
const baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
const activities=s.activities.filter(a=>!a.deleted&&!a.summary&&!a.unavailable&&(!baseline||a.at>baseline.through)&&a.snapshot?.some(x=>x.id===id));
return {count:(baseline?.count||0)+activities.length,distance:activities.reduce((v,a)=>v+(a.snapshot.find(x=>x.id===id).distanceIncluded===false?0:(a.distance||0)),baseline?.distance||0),seconds:activities.reduce((v,a)=>v+(a.seconds||0),baseline?.seconds||0)};
}

return {uid,clone,empty,ensure,dateTime,installationDate,migrateInstallationDates,today,nowLocal,parentAt,treeValid,batchMove,activateMovedGear,expand,equipmentDistanceIncluded,distanceSnapshot,preserveDistanceSnapshot,deleteGear,restoreGear,saveGear,saveAssignment,importGear,mergeActivities,stats};
};
modules["lib/categories.mjs"] = function(){
const {randomUUID} = require("node:crypto");

const builtinCategories = [
 ['Bike','自行车'],['Shoes','跑鞋'],['CyclingShoes','锁鞋'],['Cleats','锁片'],
 ['Pedals','锁踏'],['PowerMeter','功率计'],['Handlebar','车把'],['Saddle','坐垫'],['Seatpost','坐杆'],
 ['Chainrings','牙盘'],['Crankset','曲柄'],['Spider','盘爪'],
 ['Wheelset','轮组'],['Tyre','轮胎'],['Tube','内胎'],['BrakePads','来令片'],['BrakeRotor','碟片'],
 ['Cassette','飞轮'],['Chain','链条'],['FrontDerailleur','前变速器'],['RearDerailleur','后变速器'],['Trainer','骑行台'],['Equipment','其他装备']
].map(([id,name])=>({id,name,baseType:id,builtin:true,indoorDistance:['Trainer','Chain','Cassette','Chainrings','Crankset','Spider','FrontDerailleur','RearDerailleur'].includes(id)}));
const addedCategoryIDs=new Set(['BrakePads','BrakeRotor','Saddle','Seatpost','FrontDerailleur','RearDerailleur','Crankset','Spider']);
function check(ok,message){if(!ok)throw Error(message);}
function nameKey(name){return name.trim().toLowerCase();}

function migrateCategoryTypes(s){
 const wheel=s.gearCategories.find(c=>c?.id==='Wheel');
 if(wheel&&!s.gearCategories.some(c=>c?.id==='Wheelset'))s.gearCategories.push({...wheel,id:'Wheelset',name:'轮组',baseType:'Wheelset',builtin:true});
 for(const gear of s.gears){
  if(gear.categoryId==='Wheel')gear.categoryId='Wheelset';
  if(gear.type==='Wheel'){gear.type='Wheelset';gear.categoryId??='Wheelset';}
  if(gear.type==='Drivetrain'){
   gear.categoryId??='Drivetrain';gear.type='Equipment';
   if(gear.categoryId==='Drivetrain'&&!s.gearCategories.some(c=>c?.id==='Drivetrain'))s.gearCategories.push({id:'Drivetrain',name:'传动系统',baseType:'Equipment',builtin:false,indoorDistance:true});
  }
 }
 s.gearCategories=s.gearCategories.filter(c=>c?.id!=='Wheel'&&(c?.id!=='Drivetrain'||s.gears.some(g=>g.categoryId===c.id)||c.name!=='传动系统'));
 for(const category of s.gearCategories){
  if(category?.baseType==='Wheel')category.baseType='Wheelset';
  if(category?.baseType==='Drivetrain')category.baseType='Equipment';
 }
}

function ensureCategories(s){
 if(s.gearCategories===undefined)s.gearCategories=builtinCategories.map(c=>({...c}));
 check(Array.isArray(s.gearCategories),'无法读取装备类别，请选择完整备份。');
 migrateCategoryTypes(s);
 const ids=new Set(),names=new Set();
 for(const c of s.gearCategories){
  check(c&&typeof c.id==='string'&&c.id.length>0&&!ids.has(c.id),'备份中的装备类别重复或损坏，请重新导出备份。');
  check(typeof c.name==='string'&&c.name.trim().length>0&&c.name.length<=80&&!names.has(nameKey(c.name)),'备份中的装备类别名称重复或损坏，请重新导出备份。');
  check(builtinCategories.some(b=>b.id===c.baseType)&&typeof c.indoorDistance==='boolean','无法读取装备类别，请选择完整备份。');
  const builtin=builtinCategories.find(b=>b.id===c.id);
  check(!builtin||c.baseType===builtin.baseType,'内置类别的基础类型不能修改。');
  c.builtin=!!builtin;ids.add(c.id);names.add(nameKey(c.name));
 }
 for(const builtin of builtinCategories)if(!ids.has(builtin.id)){
  // Keep an existing user category when a newly added default has the same name.
  if(addedCategoryIDs.has(builtin.id)&&names.has(nameKey(builtin.name)))continue;
  check(!names.has(nameKey(builtin.name)),'备份中的装备类别名称重复或损坏，请重新导出备份。');
  s.gearCategories.push({...builtin});ids.add(builtin.id);names.add(nameKey(builtin.name));
 }
 for(const gear of s.gears){
  if(gear.categoryId){
   const category=s.gearCategories.find(c=>c.id===gear.categoryId);
   check(category,'装备的类别已不存在，请检查备份。');
   check(gear.type===category.baseType||category.legacyType&&gear.type===category.legacyType,'备份中的装备类别不一致，请重新导出备份。');
   continue;
  }
  const type=gear.type||'Equipment';
  let category=s.gearCategories.find(c=>c.id===type||c.legacyType===type);
  const builtin=builtinCategories.find(c=>c.id===type);
  if(!category&&builtin){category=s.gearCategories.find(c=>nameKey(c.name)===nameKey(builtin.name));if(category)gear.type=category.baseType;}
  if(!category){
   let name=type,suffix=1;while(names.has(nameKey(name)))name=type+' '+(++suffix);
   category={id:randomUUID(),name,baseType:'Equipment',builtin:false,indoorDistance:false,legacyType:type};
   s.gearCategories.push(category);ids.add(category.id);names.add(nameKey(name));
  }
  gear.categoryId=category.id;
 }
 return s;
}
function saveCategory(s,input){
 const existing=input.id?s.gearCategories.find(c=>c.id===input.id):null;
 check(!input.id||existing,'类别已不存在，请重新打开。');
 const name=String(input.name||'').trim();
 check(name.length>0&&name.length<=80,'请填写类别名称，最多 80 字。');
 check(!s.gearCategories.some(c=>c.id!==existing?.id&&nameKey(c.name)===nameKey(name)),'已有同名类别，请使用其他名称。');
 const baseType=input.baseType||existing?.baseType||'Equipment';
 check(builtinCategories.some(c=>c.id===baseType),'请选择基础类型。');
 check(!existing?.builtin||baseType===existing.baseType,'内置类别的基础类型不能修改。');
 check(!existing||baseType===existing.baseType||!s.gears.some(g=>g.categoryId===existing.id),'该类别已有装备，不能修改基础类型。');
 check(typeof input.indoorDistance==='boolean','请选择是否计入室内骑行距离。');
 const category={...existing,id:existing?.id||randomUUID(),name,baseType,builtin:!!existing?.builtin,indoorDistance:input.indoorDistance};
 if(existing)Object.assign(existing,category);else s.gearCategories.push(category);
 return category;
}
function deleteCategory(s,input){
 const category=s.gearCategories.find(c=>c.id===input.id);
 check(category,'类别已不存在，请重新打开。');
 check(!category.builtin,'内置类别不能删除。');
 check(input.confirmed===true,'请确认删除类别。');
 const gears=s.gears.filter(g=>g.categoryId===category.id);
 if(gears.length){
  const replacement=s.gearCategories.find(c=>c.id===input.replacementId&&c.id!==category.id);
  check(replacement,'请为关联装备选择替代类别。');
  check(replacement.baseType===category.baseType,'请选择相同基础类型的替代类别。');
  for(const gear of gears){gear.categoryId=replacement.id;gear.type=replacement.baseType;}
 }
 s.gearCategories=s.gearCategories.filter(c=>c.id!==category.id);
 return {moved:gears.length};
}

return {builtinCategories,ensureCategories,saveCategory,deleteCategory};
};
modules["lib/history.mjs"] = function(){
const {readGearStatus} = require("lib/gear-state.mjs");
const {uid,clone,ensure,installationDate,nowLocal,treeValid,activateMovedGear} = require("lib/domain.mjs");
const records=(s,id)=>s.events.filter(e=>e.gearId===id).sort((a,b)=>a.at.localeCompare(b.at));
function install(s,gearId,events){
 const next=s.events.filter(e=>e.gearId!==gearId).concat(events);
 ensure(treeValid(s,next),'所属装备不能是自身或子装备（含后续历史关系）');
 s.events=next;
}
function record(s,gearId,before,action){
 const edit={id:uid(),gearId,at:nowLocal(),action,before,after:clone(records(s,gearId))};
 (s.historyEdits??=[]).push(edit);return edit;
}
function saveInstallation(s,input){
 ensure(s.gears.some(g=>g.id===input.gearId&&!g.deletedAt),'装备不存在或已删除');
 const at=installationDate(input.at);ensure(at<=nowLocal(),'不能设置未来的装配时间');
 ensure(input.parentId===null||s.gears.some(g=>g.id===input.parentId&&!g.deletedAt),'所属装备不存在或已删除');
 const before=clone(records(s,input.gearId));
 const boundary=before.find(e=>e.id===input.id)?.at||at;
 ensure(!(s.gearOperations||[]).some(op=>op.gearIds.includes(input.gearId)&&op.at>=(boundary<at?boundary:at)),'请通过更换或库存记录修改这次装配。');
 if(input.id)ensure(before.some(e=>e.id===input.id),'装配记录不存在');
 ensure(!before.some(e=>e.id===input.id&&e.operationId),'请通过更换或库存记录修改这次装配。');
 ensure(!before.some(e=>e.id!==input.id&&e.at.slice(0,10)===at.slice(0,10)),'当天已有装配记录，请编辑原记录。');
 const event={id:input.id||uid(),gearId:input.gearId,parentId:input.parentId,at,allDay:true};
 const status=input.parentId===null&&readGearStatus(s,input.gearId,at)==='stock'?'stock':'active';
 install(s,input.gearId,before.filter(e=>e.id!==input.id).concat(event));
 s.gearStates=(s.gearStates||[]).filter(e=>e.installationId!==event.id);
 activateMovedGear(s,input.gearId,at,event.id,status);
 record(s,input.gearId,before,input.id?'编辑':'新增');return event;
}
function deleteInstallation(s,{gearId,id}){
 ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'装备不存在或已删除');
 const before=clone(records(s,gearId));ensure(before.some(e=>e.id===id),'装配记录不存在');
 ensure(!(s.gearOperations||[]).some(op=>op.gearIds.includes(gearId)&&op.at>=before.find(e=>e.id===id).at),'请通过更换或库存记录修改这次装配。');
 ensure(!before.some(e=>e.id===id&&e.operationId),'请通过更换或库存记录修改这次装配。');
 s.gearStates=(s.gearStates||[]).filter(e=>e.installationId!==id);
 install(s,gearId,before.filter(e=>e.id!==id));record(s,gearId,before,'删除');return {ok:true};
}
function undoInstallation(s,gearId){
 ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'装备不存在或已删除');
 const edit=(s.historyEdits||[]).filter(e=>e.gearId===gearId&&!e.undoneAt).at(-1);ensure(edit,'没有可撤销的历史修改');
 ensure(JSON.stringify(records(s,gearId))===JSON.stringify(edit.after),'装配历史已有后续修改，无法撤销');
 install(s,gearId,clone(edit.before));edit.undoneAt=nowLocal();return {ok:true};
}

return {saveInstallation,deleteInstallation,undoInstallation};
};
modules["lib/organize.mjs"] = function(){
const {clone,ensure,uid,nowLocal,treeValid} = require("lib/domain.mjs");

function rootOf(parents,id){
 const seen=new Set();
 while(id){ensure(!seen.has(id),'装配历史存在环路');seen.add(id);const p=parents.get(id);if(!p)return id;id=p;}
 return null;
}

// Evaluate the original timeline, so batch order never changes eligibility.
function plan(s,changes){
 ensure(Array.isArray(changes)&&changes.length>0&&changes.length<500,'没有可保存的修改');
 const ids=new Set(),gears=new Map(s.gears.map(g=>[g.id,g]));
 for(const c of changes){
  ensure(gears.has(c.gearId)&&!gears.get(c.gearId).deletedAt,'装备不存在或已删除');
  ensure(!ids.has(c.gearId),'装备重复');ids.add(c.gearId);
  ensure(c.fromParentId&&c.parentId&&c.fromParentId!==c.parentId,'整理层级需要选择不同的所属装备');
  ensure(gears.has(c.fromParentId)&&gears.has(c.parentId)&&!gears.get(c.parentId).deletedAt,'所属装备不存在或已删除');
  ensure(c.gearId!==c.parentId,'所属装备不能是自身');
 }
 const boundaries=[...new Set([...s.events.map(e=>e.at),...s.gears.map(g=>g.deletedAt).filter(Boolean)])].sort();
 const byTime=new Map(boundaries.map(t=>[t,s.events.filter(e=>e.at===t)]));
 const parents=new Map(),rows=changes.map(c=>({...c,ranges:[],unchangedRanges:[]}));
 const histories=new Map(changes.map(c=>[c.gearId,[]]));
 const previous=new Map(),previousOriginal=new Map();
 function range(list,from,to){const last=list.at(-1);if(last&&last.to===from)last.to=to;else list.push({from,to});}
 for(let i=0;i<boundaries.length;i++){
  const at=boundaries[i],to=boundaries[i+1]||null,events=byTime.get(at);
  for(const e of events)parents.set(e.gearId,e.parentId);
  for(const row of rows){
   const {gearId,fromParentId,parentId}=row,original=parents.get(gearId)||null;
   const present=id=>!gears.get(id)?.deletedAt||at<gears.get(id).deletedAt;
   const eligible=original===fromParentId&&present(gearId)&&present(parentId)&&rootOf(parents,gearId)===rootOf(parents,parentId);
   const desired=eligible?parentId:original,existing=events.find(e=>e.gearId===gearId);
   if(eligible)range(row.ranges,at,to);
   else if(original===fromParentId)range(row.unchangedRanges,at,to);
   // Preserve original timestamps/IDs. Remove only boundaries made redundant by this correction.
   if(desired!==(previous.get(gearId)||null)||existing&&original===(previousOriginal.get(gearId)||null)){
    histories.get(gearId).push(existing?{...existing,parentId:desired}:{id:uid(),gearId,parentId:desired,at});
   }
   previous.set(gearId,desired);previousOriginal.set(gearId,original);
  }
 }
 ensure(!s.events.some(e=>ids.has(e.gearId)&&e.operationId),'请通过更换或库存记录修改这次装配。');
 const next=s.events.filter(e=>!ids.has(e.gearId)).concat([...histories.values()].flat());
 ensure(treeValid(s,next),'所属装备不能是自身或子装备（含历史关系）');
 // Guard against coordinated moves that would change a root despite individual eligibility.
 const nextParents=new Map(),oldParents=new Map();
 for(const at of boundaries){
  for(const e of byTime.get(at))oldParents.set(e.gearId,e.parentId);
  for(const e of next.filter(e=>e.at===at))nextParents.set(e.gearId,e.parentId);
  ensure(s.gears.every(g=>rootOf(oldParents,g.id)===rootOf(nextParents,g.id)),'整理层级不能改变装备归属，请使用变更装配');
 }
 return {events:next,preview:{revision:s.revision,changes:clone(changes),rows,changed:rows.filter(r=>r.ranges.length).length}};
}

function previewOrganization(s,changes){return plan(s,changes).preview;}
function applyOrganization(s,changes){
 const result=plan(s,changes);ensure(result.preview.changed>0,'没有可整理的共同装配时段');
 const ids=new Set(changes.map(c=>c.gearId));
 const operation={id:uid(),at:nowLocal(),changes:clone(changes),before:clone(s.events.filter(e=>ids.has(e.gearId))),after:clone(result.events.filter(e=>ids.has(e.gearId)))};
 s.events=result.events;(s.organizations??=[]).push(operation);
 return result.preview;
}

return {previewOrganization,applyOrganization};
};
modules["lib/recompute.mjs"] = function(){
const {uid,clone,ensure,dateTime,nowLocal,today,expand,stats,equipmentDistanceIncluded,distanceSnapshot} = require("lib/domain.mjs");
function date(value){ensure(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value),'请选择日期范围');dateTime(value+'T00:00:00');return value;}
function descendants(rows,id){const ids=new Set([id]);let size;do{size=ids.size;for(const row of rows)if(ids.has(row.parentId))ids.add(row.id);}while(ids.size!==size);return ids;}
function activityUsage(a){return {main:a.main,extras:a.extras||[],excluded:a.excluded||[],manual:!!a.manual,snapshot:a.snapshot||[],recomputedGearIds:a.recomputedGearIds||[]};}
function missingRanges(s,from,to){
 const days=x=>Math.floor(Date.parse(x+'T00:00:00Z')/86400000),format=x=>new Date(x*86400000).toISOString().slice(0,10);
 const intervals=(s.syncLog||[]).map(x=>[Math.max(days(from),days(x.oldest)),Math.min(days(to),days(x.newest))]).filter(([a,b])=>a<=b).sort((a,b)=>a[0]-b[0]);
 let cursor=days(from);const end=days(to),gaps=[];for(const [a,b] of intervals){if(a>cursor)gaps.push({from:format(cursor),to:format(a-1)});cursor=Math.max(cursor,b+1);}if(cursor<=end)gaps.push({from:format(cursor),to});return gaps;
}
function planRecompute(s,input){
 const category=input.categoryId?s.gearCategories.find(c=>c.id===input.categoryId):null;
 if(input.categoryId)ensure(category,'类别已不存在，请重新打开。');
 const targets=category?s.gears.filter(g=>g.categoryId===category.id&&!g.deletedAt):s.gears.filter(g=>g.id===input.gearId&&!g.deletedAt);
 ensure(targets.length,category?'该类别下没有可重算的装备。':'装备不存在或已删除');
 const gear=targets[0];
 const from=date(input.from),to=date(input.to);ensure(from<=to&&to<=today(),'日期范围无效');
 const scope=input.scope||'self',manual=input.manual||'preserve';ensure(['self','subtree'].includes(scope)&&['preserve','recalculate'].includes(manual),'重算选项无效');
 const start=from+'T00:00:00',end=to+'T23:59:59',gearIds=new Set(targets.map(g=>g.id)),rows=[],patches=[];
 if(!category&&scope==='subtree')for(const at of [start,...s.events.filter(e=>e.at>=start&&e.at<=end).map(e=>e.at)])for(const row of expand(s,[gear.id],at))gearIds.add(row.id);
 const skipped={manual:0,unavailable:0,undatedUnavailable:0,missingMain:0,incompleteMetrics:0};
 for(const a of s.activities){
  if(a.deleted)continue;
  if(!a.at){if(a.summary||a.unavailable)skipped.undatedUnavailable++;continue;}
  if(a.at<start||a.at>end)continue;
  if(a.summary||a.unavailable){skipped.unavailable++;continue;}
  if(!a.main)skipped.missingMain++;
  const current=a.snapshot||[];
  const physical=category?new Set(targets.map(g=>g.id)):scope==='subtree'?new Set(expand(s,[gear.id],a.at).map(x=>x.id)):new Set([gear.id]);
  if(!category&&scope==='subtree')for(const id of descendants(current,gear.id))physical.add(id);
  for(const id of physical)gearIds.add(id);
  const expanded=expand(s,[a.main,...(a.extras||[])],a.at,a.excluded||[]);
  const expected=distanceSnapshot(expanded,equipmentDistanceIncluded(s,a,expanded),s);
  const oldRows=current.filter(x=>physical.has(x.id)),newRows=expected.filter(x=>physical.has(x.id));
  if(!oldRows.length&&!newRows.length)continue;
  if(a.manual&&manual==='preserve'){skipped.manual++;rows.push({id:a.id,name:a.name,at:a.at,status:'manual',added:[],removed:[]});continue;}
  const retained=current.filter(x=>!physical.has(x.id)),present=new Set([...retained,...newRows].map(x=>x.id));
  const normalized=newRows.map(x=>({...x,parentId:present.has(x.parentId)?x.parentId:null}));
  const afterSnapshot=[...retained,...normalized];
  // Removing a target must not leave unrelated snapshot nodes pointing to a missing parent.
  for(let i=0;i<afterSnapshot.length;i++)if(afterSnapshot[i].parentId&&!present.has(afterSnapshot[i].parentId))afterSnapshot[i]={...afterSnapshot[i],parentId:null};
  const oldIds=new Set(oldRows.map(x=>x.id)),newIds=new Set(newRows.map(x=>x.id));
  const added=[...newIds].filter(id=>!oldIds.has(id)),removed=[...oldIds].filter(id=>!newIds.has(id));
  const canonical=x=>JSON.stringify([...x].sort((a,b)=>a.id.localeCompare(b.id)));
  const changed=canonical(current)!==canonical(afterSnapshot);
  const membership=x=>x.map(({distanceIncluded,...row})=>row);
  const distanceOnly=changed&&canonical(membership(current))===canonical(membership(afterSnapshot));
  if(a.distance===null||a.seconds===null)skipped.incompleteMetrics++;
  rows.push({id:a.id,name:a.name,at:a.at,status:added.length||removed.length?'changed':distanceOnly?'distance':changed?'assembly':'unchanged',added,removed,distance:a.distance,seconds:a.seconds,distanceExcluded:newRows.some(x=>x.distanceIncluded===false)});
  if(changed){const before=clone(activityUsage(a));patches.push({id:a.id,before,after:{...before,snapshot:afterSnapshot,recomputedGearIds:[...new Set([...before.recomputedGearIds,...physical])]}});}
 }
 const next=clone(s);for(const patch of patches){const a=next.activities.find(x=>x.id===patch.id);a.snapshot=clone(patch.after.snapshot);a.recomputedGearIds=clone(patch.after.recomputedGearIds);}
 for(const g of next.gears)if(gearIds.has(g.id))g.totalsMode='local';
 const totals=[...gearIds].map(id=>({id,name:s.gears.find(g=>g.id===id)?.name||id,before:stats(s,id),after:stats(next,id),baselineDisabled:!!s.gears.find(g=>g.id===id)?.importedTotals&&s.gears.find(g=>g.id===id)?.totalsMode!=='local'}));
 return {options:{...(category?{categoryId:category.id}:{gearId:gear.id}),from,to,scope:category?'self':scope,manual},revision:s.revision,gearIds:[...gearIds],rows:rows.sort((a,b)=>b.at.localeCompare(a.at)),totals,skipped,gaps:missingRanges(s,from,to),added:rows.filter(x=>x.added.length).length,removed:rows.filter(x=>x.removed.length).length,changed:patches.length,patches};
}
function previewRecompute(s,input){const {patches,...preview}=planRecompute(s,input);return preview;}
function applyRecompute(s,input){
 const plan=planRecompute(s,input),modes=plan.gearIds.map(id=>{const g=s.gears.find(x=>x.id===id);return {id,before:g.totalsMode??null,after:'local'};});
 for(const patch of plan.patches){const a=s.activities.find(x=>x.id===patch.id);a.snapshot=clone(patch.after.snapshot);a.recomputedGearIds=clone(patch.after.recomputedGearIds);}
 for(const mode of modes)s.gears.find(g=>g.id===mode.id).totalsMode='local';
 const {patches,...summary}=plan;const operation={id:uid(),at:nowLocal(),...summary,patches,modes};(s.recalculations??=[]).push(operation);
 return {id:operation.id,...summary};
}
function undoRecompute(s,id){
 const op=(s.recalculations||[]).find(x=>x.id===id&&!x.undoneAt);ensure(op,'重算记录不存在或已撤销');
 // Prevent a later overlapping run (including a no-op) from being silently undone.
 const index=s.recalculations.indexOf(op);ensure(!s.recalculations.slice(index+1).some(x=>!x.undoneAt&&x.gearIds.some(id=>op.gearIds.includes(id))),'请先撤销后续重算');
 for(const patch of op.patches){const a=s.activities.find(x=>x.id===patch.id);ensure(a&&JSON.stringify(activityUsage(a))===JSON.stringify(patch.after),'活动装备已有后续修改，无法撤销');}
 for(const mode of op.modes)ensure(s.gears.find(g=>g.id===mode.id)?.totalsMode===mode.after,'统计方式已有后续修改，无法撤销');
 for(const patch of op.patches){const a=s.activities.find(x=>x.id===patch.id);a.snapshot=clone(patch.before.snapshot);a.recomputedGearIds=clone(patch.before.recomputedGearIds);}
 for(const mode of op.modes){const g=s.gears.find(x=>x.id===mode.id);if(mode.before===null)delete g.totalsMode;else g.totalsMode=mode.before;}
 op.undoneAt=nowLocal();return {ok:true};
}

return {planRecompute,previewRecompute,applyRecompute,undoRecompute};
};
modules["lib/purge.mjs"] = function(){
const {ensure} = require("lib/domain.mjs");

const references=(value,id)=>value===id||Array.isArray(value)&&value.some(v=>references(v,id))||value&&typeof value==='object'&&Object.values(value).some(v=>references(v,id));
function previewPurge(s,id){
 const gear=s.gears.find(g=>g.id===id);ensure(gear?.deletedAt,'请先将装备移入回收站');
 return {id,name:gear.name,attachments:(s.attachments||[]).filter(a=>a.gearId===id).length,photos:(s.photos||[]).filter(p=>p.ownerType==='gear'&&p.ownerId===id||p.ownerType==='event'&&s.gearEvents?.some(e=>e.id===p.ownerId&&e.gearId===id)).length,activities:s.activities.filter(a=>a.main===id||a.extras?.includes(id)||a.excluded?.includes(id)||a.snapshot?.some(x=>x.id===id||x.parentId===id)).length,gearEvents:(s.gearEvents||[]).filter(e=>e.gearId===id).length,installations:s.events.filter(e=>e.gearId===id||e.parentId===id).length};
}
function purgeGear(s,{id,confirmed}){
 const preview=previewPurge(s,id);ensure(confirmed===true,'请确认永久删除');
 s.gearEvents=(s.gearEvents||[]).filter(e=>e.gearId!==id);s.gearEventRequests=(s.gearEventRequests||[]).filter(e=>e.gearId!==id);
 const removedOperations=new Set((s.gearOperations||[]).filter(op=>references(op,id)).map(op=>op.id));
 s.gearOperations=(s.gearOperations||[]).filter(op=>!removedOperations.has(op.id));
 s.gearStates=(s.gearStates||[]).filter(e=>e.gearId!==id);
 for(const row of [...s.events,...s.gearStates])if(removedOperations.has(row.operationId))delete row.operationId;
 s.gears=s.gears.filter(g=>g.id!==id);
 s.attachments=(s.attachments||[]).filter(a=>a.gearId!==id);
 s.events=s.events.filter(e=>e.gearId!==id).map(e=>e.parentId===id?{...e,parentId:null}:e);
 for(const a of s.activities){
  if(a.main===id){a.main=null;a.pending=false;a.error=null;}
  for(const field of ['extras','excluded','recomputedGearIds'])if(a[field])a[field]=a[field].filter(x=>x!==id);
  if(a.snapshot){
   const parent=a.snapshot.find(x=>x.id===id)?.parentId;
   const remaining=a.snapshot.filter(x=>x.id!==id),known=new Set(remaining.map(x=>x.id));
   a.snapshot=remaining.map(x=>x.parentId===id?{...x,parentId:known.has(parent)?parent:null}:x);
  }
 }
 // Undo payloads must never resurrect a purged entity or its references.
 for(const field of ['historyEdits','recalculations','organizations'])if(s[field])s[field]=s[field].filter(op=>!references(op,id));
 return preview;
}

return {previewPurge,purgeGear};
};
modules["lib/gear-events.mjs"] = function(){
const {calculateEventMetrics} = require("public/snapshot.js");
const {createHash} = require("node:crypto");
const {ensure,uid,dateTime,nowLocal} = require("lib/domain.mjs");
const eventKinds={maintenance:'保养',crash:'摔车',dripWax:'滴蜡',hotWax:'煮蜡',cleaning:'清洁',inspection:'检查',custom:'其他'};
function eventMetrics(s,event,now=nowLocal()){return calculateEventMetrics(s,event,now);}

const fingerprint=(op,input)=>createHash('sha256').update(JSON.stringify({op,event:input.event,id:input.id,confirmed:input.confirmed})).digest('hex');
function replayEventRequest(s,op,input){
 ensure(typeof input.requestId==='string'&&/^[a-zA-Z0-9-]{8,100}$/.test(input.requestId),'请求标识无效');
 const receipt=(s.gearEventRequests||[]).find(r=>r.id===input.requestId);
 if(!receipt)return null;
 ensure(receipt.fingerprint===fingerprint(op,input),'请求标识已用于其他修改');return receipt.result;
}
function mutateGearEvent(s,op,input,now=nowLocal()){
 const replay=replayEventRequest(s,op,input);if(replay)return replay;
 let result,gearId;
 if(op==='save'){
  const e=input.event;ensure(e&&typeof e==='object','记录无效');gearId=e.gearId;
  ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'请先恢复装备，或选择有效装备');
  const old=(s.gearEvents||[]).find(x=>x.id===e.id);if(e.id)ensure(old,'记录不存在');ensure(!old||old.gearId===gearId,'不能修改记录所属装备');
  ensure(Object.hasOwn(eventKinds,e.kind),'事件类型无效');
  ensure(typeof e.occurredDate==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(e.occurredDate),'日期无效');
  const time=e.occurredTime||null;ensure(time===null||typeof time==='string'&&/^\d{2}:\d{2}$/.test(time),'时刻无效');
  const at=dateTime(e.occurredDate+'T'+(time||'00:00'));ensure(at<=now,'不能记录未来的事件');
  const customName=e.kind==='custom'?String(e.customName||'').trim():null;ensure(e.kind!=='custom'||customName.length>0&&customName.length<=80,'请输入 1–80 字的名称');
  ensure(e.notes===undefined||typeof e.notes==='string','备注无效');const notes=e.notes||'';ensure(notes.length<=2000,'备注不能超过 2000 字');
  const stamp=new Date().toISOString();const row={id:old?.id||uid(),gearId,kind:e.kind,customName,occurredDate:e.occurredDate,occurredTime:time,timezone:'Asia/Shanghai',notes,createdAt:old?.createdAt||stamp,updatedAt:stamp};
  s.gearEvents??=[];if(old)Object.assign(old,row);else s.gearEvents.push(row);result={id:row.id};
 }else{
  ensure(op==='delete'&&input.confirmed===true,'请确认删除记录');const row=(s.gearEvents||[]).find(e=>e.id===input.id);ensure(row,'记录不存在');gearId=row.gearId;ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'请先恢复装备');
  s.gearEvents=s.gearEvents.filter(e=>e.id!==input.id);result={ok:true};
 }
 (s.gearEventRequests??=[]).push({id:input.requestId,gearId,fingerprint:fingerprint(op,input),result});return result;
}

return {eventKinds,eventMetrics,replayEventRequest,mutateGearEvent};
};
modules["public/snapshot.js"] = function(){
// A historical view reconstructed from the records available now, not a
// database-version restore. Never mutate the live state or saved usage rows.
function snapshotCutoff(date, now) {
 if (!/^\d{4}-\d{2}-\d{2}$/.test(date) ||
     !Number.isFinite(Date.parse(date+'T00:00:00Z')) ||
     new Date(date+'T00:00:00Z').toISOString().slice(0,10)!==date ||
     date>now.slice(0,10)) throw new Error('请选择有效的历史日期');
 return date===now.slice(0,10)?now:date+'T23:59:59';
}

function snapshotStats(state, gear, cutoff) {
 const baseline=gear.totalsMode==='local'?null:gear.importedTotals;
 const blocked=!!baseline&&baseline.through>cutoff;
 const rows=state.activities.filter(a=>a.at&&a.at<=cutoff&&!a.deleted&&!a.summary&&!a.unavailable&&
  a.snapshot?.some(x=>x.id===gear.id)&&(!baseline||blocked||a.at>baseline.through));
 const recorded={distance:0,seconds:0,count:rows.length};
 let missing=false;
 for(const activity of rows){
  const countsDistance=activity.snapshot.find(x=>x.id===gear.id).distanceIncluded!==false;
  if(countsDistance&&Number.isFinite(activity.distance))recorded.distance+=activity.distance;
  if(Number.isFinite(activity.seconds))recorded.seconds+=activity.seconds;
  if(countsDistance&&!Number.isFinite(activity.distance)||!Number.isFinite(activity.seconds))missing=true;
 }
 if(blocked)return {distance:null,seconds:null,count:null,partial:true,reason:'baseline',recorded};
 return {
  distance:(baseline?.distance||0)+recorded.distance,
  seconds:(baseline?.seconds||0)+recorded.seconds,
  count:(baseline?.count||0)+recorded.count,
  partial:missing,reason:missing?'missing':null,recorded
 };
}

function buildSnapshot(state, date, now) {
 const cutoff=snapshotCutoff(date,now);
 const gears=state.gears.filter(g=>{
  if(g.deletedAt&&g.deletedAt<=cutoff)return false;
  // Purchase is the explicit effective date. Creation of an imported record
  // only tells us when it entered Gearhouse, not when the gear existed.
  if(g.purchased)return g.purchased.slice(0,10)<=date;
  if(g.sourceGearId||g.remoteId||g.importedTotals)return true;
  const evidence=[g.createdAt,
   ...state.events.filter(e=>e.gearId===g.id||e.parentId===g.id).map(e=>e.at),
   ...(state.gearStates||[]).filter(e=>e.gearId===g.id).map(e=>e.at),
   ...state.activities.filter(a=>a.snapshot?.some(x=>x.id===g.id)).map(a=>a.at),
   ...(state.gearEvents||[]).filter(e=>e.gearId===g.id).map(e=>e.occurredDate)
  ].filter(Boolean);
  return !evidence.length||evidence.some(at=>at<=cutoff);
 }).map(g=>({
  ...g,deletedAt:undefined,hidden:false,
  retired:!!g.retiredAt&&g.retiredAt<=cutoff,
  snapshotStatusUnknown:!!g.retired&&!g.retiredAt,
  snapshotAgeUnknown:!g.purchased&&(!!g.sourceGearId||!!g.remoteId||!!g.importedTotals)
 }));
 const ids=new Set(gears.map(g=>g.id));
 const events=state.events.filter(e=>e.at<=cutoff&&ids.has(e.gearId))
  .map(e=>({...e,parentId:ids.has(e.parentId)?e.parentId:null}));
 const gearEvents=(state.gearEvents||[]).filter(e=>ids.has(e.gearId)&&
  e.occurredDate+'T'+(e.occurredTime||'00:00')+':00'<=cutoff);
 const view={...state,gears,events,gearEvents,
  gearStates:(state.gearStates||[]).filter(e=>e.at<=cutoff&&ids.has(e.gearId)),
  gearOperations:(state.gearOperations||[]).filter(e=>e.at<=cutoff&&ids.has(e.gearId)),
  activities:state.activities.filter(a=>a.at&&a.at<=cutoff),
  snapshotView:{date,cutoff},
  statistics:Object.fromEntries(gears.map(g=>[g.id,snapshotStats(state,g,cutoff)]))
 };
 view.eventStatistics=Object.fromEntries(gearEvents.map(e=>[e.id,calculateEventMetrics(view,e,cutoff)]));
 return view;
}

function calculateEventMetrics(s,event,now){
 const boundary=event.occurredDate+'T'+(event.occurredTime||'00:00')+':00';
 const after=event.occurredTime?boundary:new Date(Date.parse(event.occurredDate+'T00:00:00Z')+86400000).toISOString().slice(0,10)+'T00:00:00';
 const gear=s.gears.find(g=>g.id===event.gearId),baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
 const rows=s.activities.filter(a=>!a.deleted&&!a.summary&&!a.unavailable&&a.at<=now&&Number.isFinite(a.distance)&&a.distance>=0&&a.snapshot?.some(x=>x.id===event.gearId)&&a.snapshot.find(x=>x.id===event.gearId).distanceIncluded!==false);
 const sum=predicate=>rows.filter(predicate).reduce((v,a)=>v+a.distance,0);
 return {distance:sum(a=>a.at>=after),days:Math.round((Date.parse(now.slice(0,10))-Date.parse(event.occurredDate))/86400000),total:baseline&&baseline.through>boundary?null:(baseline?.distance||0)+sum(a=>a.at<boundary&&(!baseline||a.at>baseline.through)),limited:s.activities.some(a=>!a.deleted&&(a.unavailable||a.summary||!Number.isFinite(a.distance)))};
}

return {snapshotCutoff,snapshotStats,buildSnapshot,calculateEventMetrics};
};
modules["lib/photos.mjs"] = function(){
const {createHash} = require("node:crypto");
const {ensure} = require("lib/domain.mjs");

const PHOTO_LIMIT=40,MAX_PHOTO_BYTES=10*1024*1024;
const photoIdValid=id=>typeof id==='string'&&/^[a-f0-9-]{36}$/.test(id);
function photoOwner(s,type,id,gearId,{readOnly=false}={}){
 let owner;
 if(type==='gear')owner=s.gears.find(g=>g.id===id&&(readOnly||!g.deletedAt));
 if(type==='activity')owner=s.activities.find(a=>a.id===id&&(readOnly||!a.deleted&&!a.unavailable&&!a.summary));
 if(type==='event'){
  owner=s.gearEvents?.find(e=>e.id===id);
  if(owner&&!s.gears.some(g=>g.id===owner.gearId&&(readOnly||!g.deletedAt)))owner=null;
 }
 if(type==='draft'&&photoIdValid(id))owner=s.gears.find(g=>g.id===gearId&&!g.deletedAt);
 ensure(owner,'图片所属内容不存在或不可编辑');return owner;
}
// Browser exports a bounded JPEG. Validate markers/dimensions independently
// and refuse metadata segments so location/camera metadata cannot be retained.
function inspectPhoto(bytes){
 ensure(bytes.length<=MAX_PHOTO_BYTES&&bytes.length>20,'图片大小无效');
 ensure(bytes[0]===255&&bytes[1]===216&&bytes.at(-2)===255&&bytes.at(-1)===217,'请选择有效的图片');
 let offset=2,size;
 while(offset<bytes.length-2){
  ensure(bytes[offset++]===255,'图片格式无效');
  while(bytes[offset]===255)offset++;
  const marker=bytes[offset++];
  if(marker===218)break;
  ensure(offset+2<=bytes.length,'图片格式无效');
  const length=bytes.readUInt16BE(offset);
  ensure(length>=2&&offset+length<=bytes.length,'图片格式无效');
  ensure(![225,237,254].includes(marker),'请重新选择图片以移除附带信息');
  if([192,193,194].includes(marker)){
   ensure(length>=8,'图片格式无效');
   const height=bytes.readUInt16BE(offset+3),width=bytes.readUInt16BE(offset+5);
   ensure(width>0&&height>0&&width<=2560&&height<=2560,'图片尺寸过大');
   size={width,height};
  }
  offset+=length;
 }
 ensure(size&&bytes[offset-1]===218,'图片格式无效');
 return {...size,bytes:bytes.length,hash:createHash('sha256').update(bytes).digest('hex')};
}
const ownerPhotos=(s,type,id)=>(s.photos||[]).filter(p=>p.ownerType===type&&p.ownerId===id);
function addPhoto(s,input,metadata){
 const {id,ownerType,ownerId,gearId}=input;
 ensure(photoIdValid(id),'图片标识无效');photoOwner(s,ownerType,ownerId,gearId);
 const old=s.photos?.find(p=>p.id===id);
 if(old){ensure(old.ownerType===ownerType&&old.ownerId===ownerId&&old.hash===metadata.hash,'上传标识已用于其他图片');return old;}
 ensure(ownerType!=='event','请通过编辑记录添加图片');
 ensure(ownerPhotos(s,ownerType,ownerId).length<PHOTO_LIMIT,'最多添加 40 张图片');
 const row={id,ownerType,ownerId,...(ownerType==='draft'?{gearId}:{}),...metadata,createdAt:new Date().toISOString()};
 (s.photos??=[]).push(row);return row;
}
function editPhotos(s,input){
 const {ownerType,ownerId,ids,action,id}=input;
 ensure(['gear','activity'].includes(ownerType),'请通过编辑记录管理图片');
 photoOwner(s,ownerType,ownerId);
 const photos=ownerPhotos(s,ownerType,ownerId),photo=photos.find(p=>p.id===id);
 if(action==='delete'){
  ensure(input.confirmed===true&&photo,'请确认删除图片');s.photos=s.photos.filter(p=>p.id!==id);
  const gear=s.gears.find(g=>ownerType==='gear'&&g.id===ownerId);
  if(gear?.coverPhotoId===id)delete gear.coverPhotoId;
 }else if(action==='cover'){
  ensure(ownerType==='gear'&&photo,'请选择装备照片');s.gears.find(g=>g.id===ownerId).coverPhotoId=id;
 }else{
  ensure(action==='reorder'&&Array.isArray(ids)&&ids.length===photos.length&&new Set(ids).size===ids.length&&ids.every(id=>photos.some(p=>p.id===id)),'图片列表已更新，请重新打开');
  s.photos=s.photos.filter(p=>p.ownerType!==ownerType||p.ownerId!==ownerId).concat(ids.map(id=>photos.find(p=>p.id===id)));
 }
 return {ok:true};
}
function attachEventPhotos(s,eventId,event){
 if(event.photoIds===undefined)return;
 const ids=event.photoIds;
 ensure(Array.isArray(ids)&&ids.length<=PHOTO_LIMIT&&new Set(ids).size===ids.length,'图片列表无效');
 const chosen=ids.map(id=>{
  const p=s.photos?.find(p=>p.id===id);
  ensure(p&&(p.ownerType==='event'&&p.ownerId===eventId||p.ownerType==='draft'&&p.ownerId===event.photoDraftId&&p.gearId===event.gearId),'图片不属于这条记录');
  return {...p,ownerType:'event',ownerId:eventId,gearId:event.gearId};
 });
 s.photos=(s.photos||[]).filter(p=>!(p.ownerType==='event'&&p.ownerId===eventId)&&!(p.ownerType==='draft'&&p.ownerId===event.photoDraftId)).concat(chosen);
}
function prunePhotos(s,now=Date.now()){
 if(!s.photos)return;
 s.photos=s.photos.filter(p=>{
  if(p.ownerType==='draft')return now-Date.parse(p.createdAt)<86400000&&s.gears.some(g=>g.id===p.gearId&&!g.deletedAt);
  try{photoOwner(s,p.ownerType,p.ownerId,null,{readOnly:true});return true;}catch{return false;}
 });
 for(const g of s.gears)if(g.coverPhotoId&&!ownerPhotos(s,'gear',g.id).some(p=>p.id===g.coverPhotoId))delete g.coverPhotoId;
}

return {PHOTO_LIMIT,photoIdValid,photoOwner,inspectPhoto,ownerPhotos,addPhoto,editPhotos,attachEventPhotos,prunePhotos};
};
modules["lib/components.mjs"] = function(){
const {clone,ensure,saveGear,batchMove} = require("lib/domain.mjs");

function createComponent(s,{parentId,gear,at}){
 ensure(s.gears.some(g=>g.id===parentId&&!g.deletedAt),'所属装备不存在或已删除');
 ensure(gear&&typeof gear==='object'&&!gear.id,'请创建新装备');
 const next=clone(s);
 const created=saveGear(next,{...gear,remoteId:null});
 batchMove(next,[{gearId:created.id,parentId}],at);
 // Publish both changes together; invalid installation must not leave an orphan gear.
 s.gears=next.gears;s.events=next.events;
 return created;
}

return {createComponent};
};
modules["lib/attachments.mjs"] = function(){
const {ensure} = require("lib/domain.mjs");

function addAttachment(s,input){
 const {id,gearId,name,contentType,bytes,hash}=input;
 ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'装备不存在或已删除');
 ensure(typeof id==='string'&&/^[a-f0-9-]{36}$/.test(id),'无法添加附件，请重新选择文件。');
 ensure(typeof name==='string'&&name.trim().length>0&&name.length<=240,'文件名过长，请重命名后重试。');
 ensure(['application/pdf','image/jpeg'].includes(contentType),'请选择 PDF 或图片。');
 ensure(Number.isInteger(bytes)&&bytes>0&&bytes<=20*1024*1024,'附件不能超过 20 MB。');
 ensure(typeof hash==='string'&&/^[a-f0-9]{64}$/.test(hash),'无法添加附件，请重新选择文件。');
 ensure(!(s.attachments||[]).some(a=>a.id===id),'附件已存在，请重新选择文件。');
 const attachment={id,gearId,name:name.trim(),contentType,bytes,hash,createdAt:new Date().toISOString()};
 (s.attachments??=[]).push(attachment);return attachment;
}
function deleteAttachment(s,{id,confirmed}){
 const row=(s.attachments||[]).find(a=>a.id===id);ensure(row,'附件已删除，请重新打开装备。');
 ensure(s.gears.some(g=>g.id===row.gearId&&!g.deletedAt),'装备不存在或已删除');
 ensure(confirmed===true,'请确认删除附件。');
 s.attachments=s.attachments.filter(a=>a.id!==id);return {ok:true};
}

return {addAttachment,deleteAttachment};
};
modules["public/gear-activities.js"] = function(){
// Usage comes from the saved activity snapshot, never today's assembly tree.
function gearActivityRows(state, gearId, cutoff=state.snapshotView?.cutoff) {
 const gear=state.gears.find(g=>g.id===gearId);
 const baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
 const seen=new Set();
 return state.activities.filter(a=>{
  if(seen.has(a.id)||a.deleted||a.summary||a.unavailable||!a.at||
     cutoff&&a.at>cutoff||!a.snapshot?.some(row=>row.id===gearId))return false;
  seen.add(a.id);return true;
 }).sort((a,b)=>b.at.localeCompare(a.at)||String(a.id).localeCompare(String(b.id)))
 .map(activity=>{
  const membership=activity.snapshot.find(row=>row.id===gearId);
  const excluded=membership.distanceIncluded===false;
  const measured=value=>Number.isFinite(value)&&value>=0?value:null;
  return {activity,excluded,distance:excluded?0:measured(activity.distance),
   sourceDistance:measured(activity.distance),seconds:measured(activity.seconds),
   baselineCovered:!!baseline&&activity.at<=baseline.through,
   path:savedGearPath(activity,gearId)};
 });
}

function savedGearPath(activity,gearId) {
 const path=[],seen=new Set();let id=gearId;
 while(id&&!seen.has(id)){
  seen.add(id);path.unshift(id);
  const row=activity.snapshot?.find(item=>item.id===id);
  if(!row)break;
  id=row.parentId;
 }
 return path;
}

function usageDuration(seconds) {
 if(seconds===null)return '—';
 const minutes=Math.floor(seconds/60);
 return `${Math.floor(minutes/60)}h ${String(minutes%60).padStart(2,'0')}m`;
}

function validateUsageRange(range) {
 for(const value of [range.from,range.to]){
  if(!value)continue;
  if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||
     !Number.isFinite(Date.parse(value+'T00:00:00Z'))||
     new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)
   throw new Error('请选择有效日期');
 }
 if(range.from&&range.to&&range.from>range.to)throw new Error('开始日期不能晚于结束日期');
}

function filterUsageRange(rows,range={}) {
 validateUsageRange(range);
 return rows.filter(row=>{
  const day=row.activity.at.slice(0,10);
  return (!range.from||day>=range.from)&&(!range.to||day<=range.to);
 });
}

function summarizeUsage(rows) {
 return rows.reduce((sum,row)=>{
  if(row.distance===null)sum.missingDistance++;else sum.distance+=row.distance;
  if(row.seconds===null)sum.missingTime++;else sum.seconds+=row.seconds;
  sum.count++;
  return sum;
 },{distance:0,seconds:0,count:0,missingDistance:0,missingTime:0});
}

return {gearActivityRows,savedGearPath,usageDuration,validateUsageRange,filterUsageRange,summarizeUsage};
};
modules["lib/auto-sync.mjs"] = function(){
const INTERVAL = 5 * 60_000;
const shanghaiDay = time => new Intl.DateTimeFormat('sv-SE', {timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(time));
const shift = (day,n) => new Date(Date.parse(day+'T00:00:00Z')+n*86400_000).toISOString().slice(0,10);
function syncPlan(status,now=Date.now()) {
 const newest=shanghaiDay(now),daily=status.dailyThrough!==newest;
 let oldest=shift(newest,daily?-30:-7);
 if(status.lastSuccess){const overlap=shift(shanghaiDay(status.lastSuccess),-7);if(overlap<oldest)oldest=overlap;}
 if(status.resume){oldest=status.resume.next>newest?newest:status.resume.next;}
 return {oldest,newest,daily};
}
function retryDelay(status,failures) {
 if(status===401||status===403)return null;
 return Math.max(status===429?15*60_000:0,Math.min(60*60_000,INTERVAL*2**Math.min(failures-1,4)));
}
// One shared job for automatic, immediate and historical requests.
function singleFlight() {
 let active=null;
 return run=>{if(active)return active;active=Promise.resolve().then(run).finally(()=>{active=null;});return active;};
}
function changedMerge(state,rows,merge,options) {
 const before=new Map(state.activities.map(a=>[a.id,JSON.stringify(a)]));
 const result=merge(state,rows,options);
 result.updated=state.activities.filter(a=>before.has(a.id)&&before.get(a.id)!==JSON.stringify(a)).length;
 result.changed=state.activities.length!==before.size||result.updated>0;
 return result;
}

return {INTERVAL,shanghaiDay,syncPlan,retryDelay,singleFlight,changedMerge};
};
modules["lib/activity-deletions.mjs"] = function(){
// A missing list entry alone is not proof of deletion: dates can change and
// restricted providers may return partial data. Confirm each absent ID first.
async function inspectMissingActivities(activities, rows, from, to, request) {
 if (!Array.isArray(rows) || rows.some(row => !row || !row.id)) {
  throw new Error('ICU 活动返回格式无效');
 }
 const present = new Set(rows.map(row => String(row.id)));
 const missing = activities.filter(a => !a.deleted && a.at?.slice(0,10) >= from &&
  a.at.slice(0,10) <= to && !present.has(a.id));
 const deleted = [], recovered = [];
 for (const activity of missing) {
  const before = JSON.stringify(activity);
  try {
   const row = await request('/activity/' + encodeURIComponent(activity.id) + '?intervals=false');
   if (!row?.id || String(row.id) !== activity.id) throw new Error('ICU 活动详情返回格式无效');
   recovered.push({before, row});
  } catch (error) {
   if (error.remoteStatus !== 404) throw error;
   deleted.push({id:activity.id, before});
  }
 }
 return {deleted, recovered};
}

function applyConfirmedDeletions(state, confirmations, at) {
 let removed = 0;
 for (const entry of confirmations) {
  const activity = state.activities.find(a => a.id === entry.id);
  // A concurrent local edit requires checking again next time.
  if (!activity || activity.deleted || JSON.stringify(activity) !== entry.before) continue;
  activity.deleted = true;
  activity.remoteDeletedAt = at;
  activity.pending = false;
  activity.error = null;
  removed++;
 }
 return removed;
}

return {inspectMissingActivities,applyConfirmedDeletions};
};
globalThis.gearhouseCall = require('native-entry.js').call;
