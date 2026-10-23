import {clone,ensure,saveGear,batchMove} from './domain.mjs';

export function createComponent(s,{parentId,gear,at}){
 ensure(s.gears.some(g=>g.id===parentId&&!g.deletedAt),'所属装备不存在或已删除');
 ensure(gear&&typeof gear==='object'&&!gear.id,'请创建新装备');
 const next=clone(s);
 const created=saveGear(next,{...gear,remoteId:null});
 batchMove(next,[{gearId:created.id,parentId}],at);
 // Publish both changes together; invalid installation must not leave an orphan gear.
 s.gears=next.gears;s.events=next.events;
 return created;
}
