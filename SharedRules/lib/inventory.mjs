import {clone,ensure,uid,nowLocal,installationDate,parentAt,saveGear,batchMove,treeValid,expand} from './domain.mjs';
import {readGearStatus,readOwnGearStatus,readGearStatuses} from './gear-state.mjs';

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
export function validateInventory(s){
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
export function saveInventoryGear(s,input){
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
export function readOperationOptions(s,input){
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
export function previewGearOperation(s,input){return planOperation(s,input).preview;}
export function applyGearOperation(s,input){const {next,preview}=planOperation(s,input);Object.assign(s,next);return preview;}
export function previewOperationDeletion(s,input){const next=clone(s),operation=removeOperation(next,input.id);return {...operation,revision:s.revision};}
export function deleteGearOperation(s,input){ensure(input.confirmed,'请确认删除记录');const next=clone(s),operation=removeOperation(next,input.id);Object.assign(s,next);return operation;}

function planInventoryBatch(s,input){
 ensure(Array.isArray(input.gearIds)&&input.gearIds.length>0&&input.gearIds.length<500,'请选择要移动的装备。');
 const at=installationDate(input.at||nowLocal()),chosen=new Set(input.gearIds);
 const roots=[...chosen].filter(id=>{let parent=parentAt(s,id,at),seen=new Set();while(parent&&!seen.has(parent)){if(chosen.has(parent))return false;seen.add(parent);parent=parentAt(s,parent,at);}return true;});
 let next=clone(s);const rows=[];
 for(const id of roots){const result=planOperation(next,{kind:'store',gearId:id,at});next=result.next;rows.push(result.preview);}
 const affected=readAffectedActivities(s,next,at).length;
 return {next,preview:{revision:s.revision,rows,affectedActivities:affected}};
}
export function previewInventoryBatch(s,input){return planInventoryBatch(s,input).preview;}
export function storeInventoryBatch(s,input){const {next,preview}=planInventoryBatch(s,input);Object.assign(s,next);return preview;}
