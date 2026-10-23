import {uid,clone,ensure,dateTime,nowLocal,today,expand,stats,equipmentDistanceIncluded,distanceSnapshot} from './domain.mjs';
function date(value){ensure(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value),'请选择日期范围');dateTime(value+'T00:00:00');return value;}
function descendants(rows,id){const ids=new Set([id]);let size;do{size=ids.size;for(const row of rows)if(ids.has(row.parentId))ids.add(row.id);}while(ids.size!==size);return ids;}
function activityUsage(a){return {main:a.main,extras:a.extras||[],excluded:a.excluded||[],manual:!!a.manual,snapshot:a.snapshot||[],recomputedGearIds:a.recomputedGearIds||[]};}
function missingRanges(s,from,to){
 const days=x=>Math.floor(Date.parse(x+'T00:00:00Z')/86400000),format=x=>new Date(x*86400000).toISOString().slice(0,10);
 const intervals=(s.syncLog||[]).map(x=>[Math.max(days(from),days(x.oldest)),Math.min(days(to),days(x.newest))]).filter(([a,b])=>a<=b).sort((a,b)=>a[0]-b[0]);
 let cursor=days(from);const end=days(to),gaps=[];for(const [a,b] of intervals){if(a>cursor)gaps.push({from:format(cursor),to:format(a-1)});cursor=Math.max(cursor,b+1);}if(cursor<=end)gaps.push({from:format(cursor),to});return gaps;
}
export function planRecompute(s,input){
 const category=input.categoryId?s.gearCategories.find(c=>c.id===input.categoryId):null;
 if(input.categoryId)ensure(category,'类别已不存在，请重新打开。');
 const targets=category?s.gears.filter(g=>g.categoryId===category.id&&!g.deletedAt):s.gears.filter(g=>g.id===input.gearId&&!g.deletedAt);
 ensure(targets.length,category?'该类别下没有可重算的装备。':'装备不存在或已删除');
 const gear=targets[0];
 const from=date(input.from),to=date(input.to);ensure(from<=to&&to<=today(),'日期范围无效');
 const scope=input.scope||'self',manual=input.manual||'preserve';ensure(['self','subtree'].includes(scope)&&['preserve','recalculate'].includes(manual),'重算选项无效');
 const start=from+'T00:00:00',end=to+'T23:59:59',gearIds=new Set(targets.map(g=>g.id)),rows=[],patches=[];
 if(!category&&scope==='subtree')for(const at of [start,...s.events.filter(e=>e.at>=start&&e.at<=end).map(e=>e.at)])for(const row of expand(s,[gear.id],at))gearIds.add(row.id);
 const skipped={manual:0,unavailable:0,undatedUnavailable:0,missingMain:0,incompleteMetrics:0};
 for(const a of s.activities){
  if(a.deleted)continue;
  if(!a.at){if(a.summary||a.unavailable)skipped.undatedUnavailable++;continue;}
  if(a.at<start||a.at>end)continue;
  if(a.summary||a.unavailable){skipped.unavailable++;continue;}
  if(!a.main)skipped.missingMain++;
  const current=a.snapshot||[];
  const physical=category?new Set(targets.map(g=>g.id)):scope==='subtree'?new Set(expand(s,[gear.id],a.at).map(x=>x.id)):new Set([gear.id]);
  if(!category&&scope==='subtree')for(const id of descendants(current,gear.id))physical.add(id);
  for(const id of physical)gearIds.add(id);
  const expanded=expand(s,[a.main,...(a.extras||[])],a.at,a.excluded||[]);
  const expected=distanceSnapshot(expanded,equipmentDistanceIncluded(s,a,expanded),s);
  const oldRows=current.filter(x=>physical.has(x.id)),newRows=expected.filter(x=>physical.has(x.id));
  if(!oldRows.length&&!newRows.length)continue;
  if(a.manual&&manual==='preserve'){skipped.manual++;rows.push({id:a.id,name:a.name,at:a.at,status:'manual',added:[],removed:[]});continue;}
  const retained=current.filter(x=>!physical.has(x.id)),present=new Set([...retained,...newRows].map(x=>x.id));
  const normalized=newRows.map(x=>({...x,parentId:present.has(x.parentId)?x.parentId:null}));
  const afterSnapshot=[...retained,...normalized];
  // Removing a target must not leave unrelated snapshot nodes pointing to a missing parent.
  for(let i=0;i<afterSnapshot.length;i++)if(afterSnapshot[i].parentId&&!present.has(afterSnapshot[i].parentId))afterSnapshot[i]={...afterSnapshot[i],parentId:null};
  const oldIds=new Set(oldRows.map(x=>x.id)),newIds=new Set(newRows.map(x=>x.id));
  const added=[...newIds].filter(id=>!oldIds.has(id)),removed=[...oldIds].filter(id=>!newIds.has(id));
  const canonical=x=>JSON.stringify([...x].sort((a,b)=>a.id.localeCompare(b.id)));
  const changed=canonical(current)!==canonical(afterSnapshot);
  const membership=x=>x.map(({distanceIncluded,...row})=>row);
  const distanceOnly=changed&&canonical(membership(current))===canonical(membership(afterSnapshot));
  if(a.distance===null||a.seconds===null)skipped.incompleteMetrics++;
  rows.push({id:a.id,name:a.name,at:a.at,status:added.length||removed.length?'changed':distanceOnly?'distance':changed?'assembly':'unchanged',added,removed,distance:a.distance,seconds:a.seconds,distanceExcluded:newRows.some(x=>x.distanceIncluded===false)});
  if(changed){const before=clone(activityUsage(a));patches.push({id:a.id,before,after:{...before,snapshot:afterSnapshot,recomputedGearIds:[...new Set([...before.recomputedGearIds,...physical])]}});}
 }
 const next=clone(s);for(const patch of patches){const a=next.activities.find(x=>x.id===patch.id);a.snapshot=clone(patch.after.snapshot);a.recomputedGearIds=clone(patch.after.recomputedGearIds);}
 for(const g of next.gears)if(gearIds.has(g.id))g.totalsMode='local';
 const totals=[...gearIds].map(id=>({id,name:s.gears.find(g=>g.id===id)?.name||id,before:stats(s,id),after:stats(next,id),baselineDisabled:!!s.gears.find(g=>g.id===id)?.importedTotals&&s.gears.find(g=>g.id===id)?.totalsMode!=='local'}));
 return {options:{...(category?{categoryId:category.id}:{gearId:gear.id}),from,to,scope:category?'self':scope,manual},revision:s.revision,gearIds:[...gearIds],rows:rows.sort((a,b)=>b.at.localeCompare(a.at)),totals,skipped,gaps:missingRanges(s,from,to),added:rows.filter(x=>x.added.length).length,removed:rows.filter(x=>x.removed.length).length,changed:patches.length,patches};
}
export function previewRecompute(s,input){const {patches,...preview}=planRecompute(s,input);return preview;}
export function applyRecompute(s,input){
 const plan=planRecompute(s,input),modes=plan.gearIds.map(id=>{const g=s.gears.find(x=>x.id===id);return {id,before:g.totalsMode??null,after:'local'};});
 for(const patch of plan.patches){const a=s.activities.find(x=>x.id===patch.id);a.snapshot=clone(patch.after.snapshot);a.recomputedGearIds=clone(patch.after.recomputedGearIds);}
 for(const mode of modes)s.gears.find(g=>g.id===mode.id).totalsMode='local';
 const {patches,...summary}=plan;const operation={id:uid(),at:nowLocal(),...summary,patches,modes};(s.recalculations??=[]).push(operation);
 return {id:operation.id,...summary};
}
export function undoRecompute(s,id){
 const op=(s.recalculations||[]).find(x=>x.id===id&&!x.undoneAt);ensure(op,'重算记录不存在或已撤销');
 // Prevent a later overlapping run (including a no-op) from being silently undone.
 const index=s.recalculations.indexOf(op);ensure(!s.recalculations.slice(index+1).some(x=>!x.undoneAt&&x.gearIds.some(id=>op.gearIds.includes(id))),'请先撤销后续重算');
 for(const patch of op.patches){const a=s.activities.find(x=>x.id===patch.id);ensure(a&&JSON.stringify(activityUsage(a))===JSON.stringify(patch.after),'活动装备已有后续修改，无法撤销');}
 for(const mode of op.modes)ensure(s.gears.find(g=>g.id===mode.id)?.totalsMode===mode.after,'统计方式已有后续修改，无法撤销');
 for(const patch of op.patches){const a=s.activities.find(x=>x.id===patch.id);a.snapshot=clone(patch.before.snapshot);a.recomputedGearIds=clone(patch.before.recomputedGearIds);}
 for(const mode of op.modes){const g=s.gears.find(x=>x.id===mode.id);if(mode.before===null)delete g.totalsMode;else g.totalsMode=mode.before;}
 op.undoneAt=nowLocal();return {ok:true};
}
