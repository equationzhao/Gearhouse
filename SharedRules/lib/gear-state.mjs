// Read dated equipment status without changing saved activity membership.
export function readOwnGearStatus(s,id,at,includeUndatedRetirement=true){
 const gear=s.gears.find(g=>g.id===id);
 const row=(s.gearStates||[]).filter(e=>e.gearId===id&&e.at<=at).sort((a,b)=>a.at.localeCompare(b.at)).at(-1);
 if(row)return row.status;
 return gear?.retired&&(gear.retiredAt?gear.retiredAt<=at:includeUndatedRetirement)?'retired':'active';
}
export function readGearStatus(s,id,at,includeUndatedRetirement=true){
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
export function readGearStatuses(s,at){return Object.fromEntries(s.gears.map(g=>[g.id,readGearStatus(s,g.id,at)]));}
export function readInventoryConflict(s,activity){
 return [activity.main,...(activity.extras||[])].filter(Boolean).some(id=>readGearStatus(s,id,activity.at,false)!=='active');
}
