import {createHash} from 'node:crypto';
import {ensure} from './domain.mjs';

export const PHOTO_LIMIT=40,MAX_PHOTO_BYTES=10*1024*1024;
export const photoIdValid=id=>typeof id==='string'&&/^[a-f0-9-]{36}$/.test(id);
export function photoOwner(s,type,id,gearId,{readOnly=false}={}){
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
export function inspectPhoto(bytes){
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
export const ownerPhotos=(s,type,id)=>(s.photos||[]).filter(p=>p.ownerType===type&&p.ownerId===id);
export function addPhoto(s,input,metadata){
 const {id,ownerType,ownerId,gearId}=input;
 ensure(photoIdValid(id),'图片标识无效');photoOwner(s,ownerType,ownerId,gearId);
 const old=s.photos?.find(p=>p.id===id);
 if(old){ensure(old.ownerType===ownerType&&old.ownerId===ownerId&&old.hash===metadata.hash,'上传标识已用于其他图片');return old;}
 ensure(ownerType!=='event','请通过编辑记录添加图片');
 ensure(ownerPhotos(s,ownerType,ownerId).length<PHOTO_LIMIT,'最多添加 40 张图片');
 const row={id,ownerType,ownerId,...(ownerType==='draft'?{gearId}:{}),...metadata,createdAt:new Date().toISOString()};
 (s.photos??=[]).push(row);return row;
}
export function editPhotos(s,input){
 const {ownerType,ownerId,ids,action,id,gearId}=input;
 if(ownerType==='draft'){
  ensure(action==='delete','草稿图片仅可移除。');
  photoOwner(s,ownerType,ownerId,gearId);
  const photo=ownerPhotos(s,ownerType,ownerId).find(p=>p.id===id);
  ensure(input.confirmed===true&&photo&&photo.gearId===gearId,'无法移除图片，请重新打开记录后重试。');
  s.photos=s.photos.filter(p=>p.id!==id);return {ok:true};
 }
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
export function attachEventPhotos(s,eventId,event){
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
export function prunePhotos(s,now=Date.now()){
 if(!s.photos)return;
 s.photos=s.photos.filter(p=>{
  if(p.ownerType==='draft')return now-Date.parse(p.createdAt)<86400000&&s.gears.some(g=>g.id===p.gearId&&!g.deletedAt);
  try{photoOwner(s,p.ownerType,p.ownerId,null,{readOnly:true});return true;}catch{return false;}
 });
 for(const g of s.gears)if(g.coverPhotoId&&!ownerPhotos(s,'gear',g.id).some(p=>p.id===g.coverPhotoId))delete g.coverPhotoId;
}
