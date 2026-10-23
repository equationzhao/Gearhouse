import {calculateEventMetrics} from '../public/snapshot.js';
import {createHash} from 'node:crypto';
import {ensure,uid,dateTime,nowLocal} from './domain.mjs';
export const eventKinds={maintenance:'保养',crash:'摔车',dripWax:'滴蜡',hotWax:'煮蜡',cleaning:'清洁',inspection:'检查',custom:'其他'};
export function eventMetrics(s,event,now=nowLocal()){return calculateEventMetrics(s,event,now);}

const fingerprint=(op,input)=>createHash('sha256').update(JSON.stringify({op,event:input.event,id:input.id,confirmed:input.confirmed})).digest('hex');
export function replayEventRequest(s,op,input){
 ensure(typeof input.requestId==='string'&&/^[a-zA-Z0-9-]{8,100}$/.test(input.requestId),'请求标识无效');
 const receipt=(s.gearEventRequests||[]).find(r=>r.id===input.requestId);
 if(!receipt)return null;
 ensure(receipt.fingerprint===fingerprint(op,input),'请求标识已用于其他修改');return receipt.result;
}
export function mutateGearEvent(s,op,input,now=nowLocal()){
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
