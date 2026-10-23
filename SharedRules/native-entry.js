import {readGearStatuses,readInventoryConflict} from './lib/gear-state.mjs';
import {validateInventory,saveInventoryGear,readOperationOptions,previewGearOperation,applyGearOperation,previewOperationDeletion,deleteGearOperation,previewInventoryBatch,storeInventoryBatch} from './lib/inventory.mjs';
import {ensureCategories,saveCategory,deleteCategory} from './lib/categories.mjs';
import {empty,clone,ensure,nowLocal,installationDate,migrateInstallationDates,saveGear,deleteGear,restoreGear,batchMove,saveAssignment,importGear,mergeActivities,stats,treeValid} from './lib/domain.mjs';
import {saveInstallation,deleteInstallation} from './lib/history.mjs';
import {previewOrganization,applyOrganization} from './lib/organize.mjs';
import {previewRecompute,applyRecompute} from './lib/recompute.mjs';
import {previewPurge,purgeGear} from './lib/purge.mjs';
import {mutateGearEvent,eventMetrics} from './lib/gear-events.mjs';
import {addPhoto,editPhotos,attachEventPhotos,prunePhotos} from './lib/photos.mjs';
import {createComponent} from './lib/components.mjs';
import {addAttachment,deleteAttachment} from './lib/attachments.mjs';
import {buildSnapshot} from './public/snapshot.js';
import {gearActivityRows,filterUsageRange,summarizeUsage} from './public/gear-activities.js';
import {syncPlan,retryDelay} from './lib/auto-sync.mjs';
import {applyConfirmedDeletions} from './lib/activity-deletions.mjs';

function stable(v){if(Array.isArray(v))return v.map(stable);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])]));return v;}
function sameSerialized(row,text){try{return JSON.stringify(stable(row))===JSON.stringify(stable(JSON.parse(text)));}catch{return false;}}
function normalized(raw){
 if(!raw)return empty();
 if(!Array.isArray(raw.events)) { // Migrate the initial Swift prototype once.
  const s=empty();
  s.gears=(raw.gears||[]).map(g=>({...g,sourceGearId:g.remoteID,remoteId:['Bike','Shoes'].includes(g.type)?g.remoteID:null}));
  s.events=s.gears.filter(g=>g.parentID).map(g=>({id: nativeUUID(),gearId:g.id,parentId:g.parentID,at:'2000-01-01T00:00:00'}));
  s.activities=(raw.activities||[]).map(a=>({...a,at:(a.at||'').replace(/Z$/,'').slice(0,19),main:a.mainGearID||null,remoteId:a.remoteGearID||null,extras:[],excluded:[],snapshot:a.mainGearID?[{id:a.mainGearID,parentId:null,...(a.equipmentDistanceIncluded===false?{distanceIncluded:false}:{})}]:[],equipmentDistance:a.equipmentDistanceIncluded,manual:false}));
  // Prototype dates were absolute ISO instants; restore the canonical Shanghai wall clock.
  s.activities.forEach((a,i)=>{const d=Date.parse(raw.activities[i].at);if(Number.isFinite(d))a.at=new Date(d+8*3600000).toISOString().slice(0,19);});
  s.nativePrototypeMigration=true;return s;
 }
 ensure(Array.isArray(raw.gears)&&Array.isArray(raw.activities),'备份数据无效');
 delete raw.configs;raw.gearEvents??=[];raw.photos??=[];raw.syncLog??=[];raw.remoteGears??=[];
 ensure(treeValid(raw,raw.events),'装配历史存在环路');return raw;
}
function view(s,date){
 if(date){const snapshot=buildSnapshot(s,date,nowLocal());return {...snapshot,gearStatuses:readGearStatuses(snapshot,snapshot.snapshotView.cutoff)};}
 return {...s,gearStatuses:readGearStatuses(s,nowLocal()),inventoryConflicts:s.activities.filter(a=>!a.deleted&&a.at&&readInventoryConflict(s,a)).map(a=>a.id),statistics:Object.fromEntries(s.gears.map(g=>[g.id,stats(s,g.id)])),eventStatistics:Object.fromEntries((s.gearEvents||[]).map(e=>[e.id,eventMetrics(s,e)]))};
}
export function call(serialized){
 try{
  const {state,action,input={}}=JSON.parse(serialized),s=validateInventory(ensureCategories(normalized(state)));let result=null,mutate=true;
  if(input.revision!==undefined)ensure(s.revision===input.revision,'数据已更新，请重新预览');
  switch(action){
   case 'initialize':migrateInstallationDates(s);break;
   case 'view':return JSON.stringify({result:view(s,input.date)});
   case 'usage':{const rows=filterUsageRange(gearActivityRows(input.date?buildSnapshot(s,input.date,nowLocal()):s,input.id),input);return JSON.stringify({result:{rows,summary:summarizeUsage(rows)}});}
   case 'category-save':result=saveCategory(s,input);break;
   case 'category-delete':result=deleteCategory(s,input);break;
   case 'gear':result=saveInventoryGear(s,input);break;
   case 'inventory-options':result=readOperationOptions(s,input);mutate=false;break;
   case 'inventory-preview':result=previewGearOperation(s,input);mutate=false;break;
   case 'inventory-batch-preview':result=previewInventoryBatch(s,input);mutate=false;break;
   case 'inventory-batch':result=storeInventoryBatch(s,input);break;
   case 'inventory-save':result=applyGearOperation(s,input);break;
   case 'inventory-delete-preview':result=previewOperationDeletion(s,input);mutate=false;break;
   case 'inventory-delete':result=deleteGearOperation(s,input);break;
   case 'gear-copy':{
    const source=s.gears.find(g=>g.id===input.sourceId&&!g.deletedAt);ensure(source,'装备不存在或已删除');
    const fields=input.gear||{};
    result=saveInventoryGear(s,{name:fields.name??source.name,type:source.type,categoryId:source.categoryId,notes:fields.notes??source.notes,purchased:fields.purchased??null,condition:fields.condition??'',retired:false,remoteId:null,placement:'stock'});break;
   }
   case 'component':result=createComponent(s,input);break;
   case 'delete':result=deleteGear(s,input.id);break;
   case 'restore':result=restoreGear(s,input.id);break;
   case 'hidden':{const g=s.gears.find(g=>g.id===input.id&&!g.deletedAt);ensure(g,'装备不存在');g.hidden=!!input.hidden;break;}
   case 'moves':batchMove(s,input.changes,input.at);result={ok:true};break;
   case 'history-save':result=saveInstallation(s,input);break;
   case 'history-delete':result=deleteInstallation(s,input);break;
   case 'organize-preview':result=previewOrganization(s,input.changes);mutate=false;break;
   case 'organize':result=applyOrganization(s,input.changes);break;
   case 'recompute-preview':result=previewRecompute(s,input);mutate=false;break;
   case 'recompute':{const p=previewRecompute(s,input);ensure(!p.totals.some(t=>t.baselineDisabled)||input.baselineConfirmed,'请确认停用 ICU 历史基数');result=applyRecompute(s,input);break;}
   case 'purge-preview':result=previewPurge(s,input.id);mutate=false;break;
   case 'purge':result=purgeGear(s,input);break;
   case 'event-save':result=mutateGearEvent(s,'save',input);attachEventPhotos(s,result.id,input.event);break;
   case 'event-delete':result=mutateGearEvent(s,'delete',input);break;
   case 'photo-add':result=addPhoto(s,input,input.metadata);break;
   case 'photo-edit':result=editPhotos(s,input);break;
   case 'attachment-add':result=addAttachment(s,input);break;
   case 'attachment-delete':result=deleteAttachment(s,input);break;
   case 'assignment-preview':result=saveAssignment(s,input.id,input.assignment);mutate=false;break;
   case 'assignment':result=saveAssignment(s,input.id,input.assignment);break;
   case 'account':ensure(input.id,'账户无效');ensure(!s.account||s.account.id===input.id,'此数据库属于其他 ICU 账户');s.account=input;break;
   case 'gear-import':{
    result=importGear(s,input.rows);
    if(s.nativePrototypeMigration||s.gears.some(g=>g.remoteID!==undefined&&g.sourceComponent===undefined)){
     for(const r of input.rows){
      const g=s.gears.find(g=>g.sourceGearId===String(r.id));
      if(g&&g.remoteID!==undefined&&g.sourceComponent===undefined){
       g.sourceComponent=!!r.component;g.retired=!!r.retired;g.retiredAt=typeof r.retired==='string'?r.retired:null;
       if(!g.purchased)g.purchased=r.purchased||null;
       g.remoteId=!r.component&&['Bike','Shoes'].includes(r.type)?String(r.id):null;
      }
     }
     const parents=new Map(),lookup=id=>s.gears.find(g=>g.sourceGearId===String(id)||g.remoteId===String(id));
     for(const r of input.rows){const p=lookup(r.id);if(!p)continue;for(const id of r.component_ids||[]){const child=lookup(id);if(!child||s.events.some(e=>e.gearId===child.id))continue;const choices=parents.get(child.id)||new Set();choices.add(p.id);parents.set(child.id,choices);}}
     for(const [id,choices] of parents)if(choices.size===1){const event={id:nativeUUID(),gearId:id,parentId:[...choices][0],at:installationDate(nowLocal()),allDay:true};if(treeValid(s,[...s.events,event]))s.events.push(event);}
     delete s.nativePrototypeMigration;
    }
    ensureCategories(s);
    break;
   }
   case 'sync-plan':return JSON.stringify({result:syncPlan(s.autoSync||{})});
   case 'sync-settings':s.autoSync={...(s.autoSync||{}),...input};break;
   case 'sync-rows':{
    const before=new Map(s.activities.map(a=>[a.id,JSON.stringify(a)]));
    const rows=input.rows.filter(r=>{const a=s.activities.find(a=>a.id===String(r.id));return (a?.lastWriteAt||null)===(input.writes?.[String(r.id)]||null);});
    const recovered=(input.recovered||[]).filter(r=>sameSerialized(s.activities.find(a=>a.id===String(r.row.id)),r.before)).map(r=>r.row);
    result=mergeActivities(s,[...rows,...recovered],{historical:input.historical});result.updated=s.activities.filter(a=>before.has(a.id)&&before.get(a.id)!==JSON.stringify(a)).length;
    result.removed=applyConfirmedDeletions(s,(input.deleted||[]).filter(r=>sameSerialized(s.activities.find(a=>a.id===r.id),r.before)).map(r=>({...r,before:JSON.stringify(s.activities.find(a=>a.id===r.id))})),new Date().toISOString());
    s.lastSync={at:new Date().toISOString(),oldest:input.from,newest:input.to};
    s.syncLog.unshift({...s.lastSync,...result});s.syncLog=s.syncLog.slice(0,1000);
    if(input.saveResume!==false)s.autoSync={...(s.autoSync||{}),resume:{next:input.next}};break;
   }
   case 'write-result':{const a=s.activities.find(a=>a.id===input.id);ensure(a,'活动不存在');if(input.error)a.error=input.error;else {ensure((a.main||null)===(input.main||null),'活动已有后续修改');a.remoteId=input.target;a.pending=false;a.error=null;a.lastWriteAt=new Date().toISOString();}break;}
   default:throw Error('未知操作');
  }
  if(mutate){prunePhotos(s);s.revision=(s.revision||0)+1;}
  return JSON.stringify(mutate?{state:s,result}:{result});
 }catch(e){return JSON.stringify({error:e.message});}
}
