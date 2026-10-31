import {compareTimeline,appliesAt} from './timeline-time.mjs';
// This index belongs to one unchanged view input; never reuse after mutation.
export function buildGearStateIndex(s){
 const gears=new Map(),events=new Map(),states=new Map();
 for(const gear of s.gears)if(!gears.has(gear.id))gears.set(gear.id,gear);
 for(const row of s.events){if(!events.has(row.gearId))events.set(row.gearId,[]);events.get(row.gearId).push(row);}
 for(const row of s.gearStates||[]){if(!states.has(row.gearId))states.set(row.gearId,[]);states.get(row.gearId).push(row);}
 return {gears,events,states};
}
// Read dated equipment status without changing saved activity membership.
export function readOwnGearStatus(s,id,at,includeUndatedRetirement=true,index,instant){
 const gear=index?index.gears.get(id):s.gears.find(g=>g.id===id);
 const row=(index?index.states.get(id)||[]:s.gearStates||[]).filter(e=>e.gearId===id&&appliesAt(e,at,instant)).sort(compareTimeline).at(-1);
 if(row)return row.status;
 return gear?.retired&&(gear.retiredAt?gear.retiredAt<=at:includeUndatedRetirement)?'retired':'active';
}
export function readGearStatus(s,id,at,includeUndatedRetirement=true,index,instant){
 const seen=new Set();let current=id,status='active';
 while(current&&!seen.has(current)){
  seen.add(current);status=readOwnGearStatus(s,current,at,includeUndatedRetirement,index,instant);
  if(status==='retired')return status;
  const parent=(index?index.events.get(current)||[]:s.events).filter(e=>e.gearId===current&&appliesAt(e,at,instant)).sort(compareTimeline).at(-1)?.parentId;
  if(!parent)return status;
  current=parent;
 }
 return status;
}
export function readGearStatuses(s,at,index,instant){return Object.fromEntries(s.gears.map(g=>[g.id,readGearStatus(s,g.id,at,true,index,instant)]));}
export function readInventoryConflict(s,activity,index){
 if(activity.assemblyTimeUnknown)return false;
 return [activity.main,...(activity.extras||[])].filter(Boolean).some(id=>readGearStatus(s,id,activity.at,false,index,activity.startInstant)!=='active');
}
