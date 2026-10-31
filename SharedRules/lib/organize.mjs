import {clone,ensure,uid,nowLocal,treeValid} from './domain.mjs';
import {compareTimeline} from './timeline-time.mjs';

function rootOf(parents,id){
 const seen=new Set();
 while(id){ensure(!seen.has(id),'装配历史存在环路');seen.add(id);const p=parents.get(id);if(!p)return id;id=p;}
 return null;
}

// Evaluate the original timeline, so batch order never changes eligibility.
function plan(s,changes){
 ensure(Array.isArray(changes)&&changes.length>0,'没有可保存的修改');
 ensure(changes.length<500,'每次最多调整 499 件装备，请减少选择后重试。');
 const ids=new Set(),gears=new Map(s.gears.map(g=>[g.id,g]));
 ensure(!s.gears.some(g=>g.deletedAt&&s.events.some(e=>e.instant&&e.at.slice(0,10)===g.deletedAt.slice(0,10))),'删除记录缺少可靠时刻，无法安全整理同日装配。');
 for(const c of changes){
  ensure(gears.has(c.gearId)&&!gears.get(c.gearId).deletedAt,'装备不存在或已删除');
  ensure(!ids.has(c.gearId),'装备重复');ids.add(c.gearId);
  ensure(c.fromParentId&&c.parentId&&c.fromParentId!==c.parentId,'整理层级需要选择不同的所属装备');
  ensure(gears.has(c.fromParentId)&&gears.has(c.parentId)&&!gears.get(c.parentId).deletedAt,'所属装备不存在或已删除');
  ensure(c.gearId!==c.parentId,'所属装备不能是自身');
 }
 const points=[...s.events.map(e=>({at:e.at,...(e.instant?{instant:e.instant,allDay:false}:{})})),...s.gears.map(g=>g.deletedAt).filter(Boolean).map(at=>({at}))].sort(compareTimeline);
 const boundaries=[];for(const point of points)if(!boundaries.length||compareTimeline(boundaries.at(-1),point)!==0)boundaries.push(point);
 const byTime=boundaries.map(t=>s.events.filter(e=>compareTimeline(e,t)===0));
 const parents=new Map(),rows=changes.map(c=>({...c,ranges:[],unchangedRanges:[]}));
 const histories=new Map(changes.map(c=>[c.gearId,[]]));
 const previous=new Map(),previousOriginal=new Map();
 function range(list,from,to){const last=list.at(-1),end=to?.at||null,endInstant=to?.instant||null;if(last&&last.to===from.at&&(last.toInstant||null)===(from.instant||null)){last.to=end;last.toInstant=endInstant;}else list.push({from:from.at,to:end,...(from.instant?{fromInstant:from.instant}:{}),...(endInstant?{toInstant:endInstant}:{})});}
 for(let i=0;i<boundaries.length;i++){
  const point=boundaries[i],at=point.at,to=boundaries[i+1]||null,events=byTime[i];
  for(const e of events)parents.set(e.gearId,e.parentId);
  for(const row of rows){
   const {gearId,fromParentId,parentId}=row,original=parents.get(gearId)||null;
   const present=id=>!gears.get(id)?.deletedAt||at<gears.get(id).deletedAt;
   const eligible=original===fromParentId&&present(gearId)&&present(parentId)&&rootOf(parents,gearId)===rootOf(parents,parentId);
   const desired=eligible?parentId:original,existing=events.find(e=>e.gearId===gearId);
   if(eligible)range(row.ranges,point,to);
   else if(original===fromParentId)range(row.unchangedRanges,point,to);
   // Preserve original timestamps/IDs. Remove only boundaries made redundant by this correction.
   if(desired!==(previous.get(gearId)||null)||existing&&original===(previousOriginal.get(gearId)||null)){
    histories.get(gearId).push(existing?{...existing,parentId:desired}:{id:uid(),gearId,parentId:desired,at,...(point.instant?{instant:point.instant,allDay:false}:{})});
   }
   previous.set(gearId,desired);previousOriginal.set(gearId,original);
  }
 }
 ensure(!s.events.some(e=>ids.has(e.gearId)&&e.operationId),'请通过更换或库存记录修改这次装配。');
 const next=s.events.filter(e=>!ids.has(e.gearId)).concat([...histories.values()].flat());
 ensure(treeValid(s,next),'所属装备不能是自身或子装备（含历史关系）');
 // Guard against coordinated moves that would change a root despite individual eligibility.
 const nextParents=new Map(),oldParents=new Map();
 for(let i=0;i<boundaries.length;i++){
  const point=boundaries[i];
  for(const e of byTime[i])oldParents.set(e.gearId,e.parentId);
  for(const e of next.filter(e=>compareTimeline(e,point)===0))nextParents.set(e.gearId,e.parentId);
  ensure(s.gears.every(g=>rootOf(oldParents,g.id)===rootOf(nextParents,g.id)),'整理层级不能改变装备归属，请使用变更装配');
 }
 return {events:next,preview:{revision:s.revision,changes:clone(changes),rows,changed:rows.filter(r=>r.ranges.length).length}};
}

export function previewOrganization(s,changes){return plan(s,changes).preview;}
export function applyOrganization(s,changes){
 const result=plan(s,changes);ensure(result.preview.changed>0,'没有可整理的共同装配时段');
 const ids=new Set(changes.map(c=>c.gearId));
 const operation={id:uid(),at:nowLocal(),changes:clone(changes),before:clone(s.events.filter(e=>ids.has(e.gearId))),after:clone(result.events.filter(e=>ids.has(e.gearId)))};
 s.events=result.events;(s.organizations??=[]).push(operation);
 return result.preview;
}
