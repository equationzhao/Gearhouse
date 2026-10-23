import {ensure} from './domain.mjs';

export function addAttachment(s,input){
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
export function deleteAttachment(s,{id,confirmed}){
 const row=(s.attachments||[]).find(a=>a.id===id);ensure(row,'附件已删除，请重新打开装备。');
 ensure(s.gears.some(g=>g.id===row.gearId&&!g.deletedAt),'装备不存在或已删除');
 ensure(confirmed===true,'请确认删除附件。');
 s.attachments=s.attachments.filter(a=>a.id!==id);return {ok:true};
}
