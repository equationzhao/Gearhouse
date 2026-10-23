import {readGearStatus} from './gear-state.mjs';
import {uid,clone,ensure,installationDate,nowLocal,treeValid,activateMovedGear} from './domain.mjs';
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
export function saveInstallation(s,input){
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
export function deleteInstallation(s,{gearId,id}){
 ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'装备不存在或已删除');
 const before=clone(records(s,gearId));ensure(before.some(e=>e.id===id),'装配记录不存在');
 ensure(!(s.gearOperations||[]).some(op=>op.gearIds.includes(gearId)&&op.at>=before.find(e=>e.id===id).at),'请通过更换或库存记录修改这次装配。');
 ensure(!before.some(e=>e.id===id&&e.operationId),'请通过更换或库存记录修改这次装配。');
 s.gearStates=(s.gearStates||[]).filter(e=>e.installationId!==id);
 install(s,gearId,before.filter(e=>e.id!==id));record(s,gearId,before,'删除');return {ok:true};
}
export function undoInstallation(s,gearId){
 ensure(s.gears.some(g=>g.id===gearId&&!g.deletedAt),'装备不存在或已删除');
 const edit=(s.historyEdits||[]).filter(e=>e.gearId===gearId&&!e.undoneAt).at(-1);ensure(edit,'没有可撤销的历史修改');
 ensure(JSON.stringify(records(s,gearId))===JSON.stringify(edit.after),'装配历史已有后续修改，无法撤销');
 install(s,gearId,clone(edit.before));edit.undoneAt=nowLocal();return {ok:true};
}
