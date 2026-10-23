import {ensure} from './domain.mjs';

const references=(value,id)=>value===id||Array.isArray(value)&&value.some(v=>references(v,id))||value&&typeof value==='object'&&Object.values(value).some(v=>references(v,id));
export function previewPurge(s,id){
 const gear=s.gears.find(g=>g.id===id);ensure(gear?.deletedAt,'请先将装备移入回收站');
 return {id,name:gear.name,attachments:(s.attachments||[]).filter(a=>a.gearId===id).length,photos:(s.photos||[]).filter(p=>p.ownerType==='gear'&&p.ownerId===id||p.ownerType==='event'&&s.gearEvents?.some(e=>e.id===p.ownerId&&e.gearId===id)).length,activities:s.activities.filter(a=>a.main===id||a.extras?.includes(id)||a.excluded?.includes(id)||a.snapshot?.some(x=>x.id===id||x.parentId===id)).length,gearEvents:(s.gearEvents||[]).filter(e=>e.gearId===id).length,installations:s.events.filter(e=>e.gearId===id||e.parentId===id).length};
}
export function purgeGear(s,{id,confirmed}){
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
