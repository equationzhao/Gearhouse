// A historical view reconstructed from the records available now, not a
// database-version restore. Never mutate the live state or saved usage rows.
export function snapshotCutoff(date, now) {
 if (!/^\d{4}-\d{2}-\d{2}$/.test(date) ||
     !Number.isFinite(Date.parse(date+'T00:00:00Z')) ||
     new Date(date+'T00:00:00Z').toISOString().slice(0,10)!==date ||
     date>now.slice(0,10)) throw new Error('请选择有效的历史日期');
 return date===now.slice(0,10)?now:date+'T23:59:59';
}

export function snapshotStats(state, gear, cutoff) {
 const baseline=gear.totalsMode==='local'?null:gear.importedTotals;
 const blocked=!!baseline&&baseline.through>cutoff;
 const rows=state.activities.filter(a=>a.at&&a.at<=cutoff&&!a.deleted&&!a.summary&&!a.unavailable&&
  a.snapshot?.some(x=>x.id===gear.id)&&(!baseline||blocked||a.at>baseline.through));
 const recorded={distance:0,seconds:0,count:rows.length};
 let missing=false;
 for(const activity of rows){
  const countsDistance=activity.snapshot.find(x=>x.id===gear.id).distanceIncluded!==false;
  if(countsDistance&&Number.isFinite(activity.distance))recorded.distance+=activity.distance;
  if(Number.isFinite(activity.seconds))recorded.seconds+=activity.seconds;
  if(countsDistance&&!Number.isFinite(activity.distance)||!Number.isFinite(activity.seconds))missing=true;
 }
 if(blocked)return {distance:null,seconds:null,count:null,partial:true,reason:'baseline',recorded};
 return {
  distance:(baseline?.distance||0)+recorded.distance,
  seconds:(baseline?.seconds||0)+recorded.seconds,
  count:(baseline?.count||0)+recorded.count,
  partial:missing,reason:missing?'missing':null,recorded
 };
}

export function buildSnapshot(state, date, now) {
 const cutoff=snapshotCutoff(date,now);
 const gears=state.gears.filter(g=>{
  if(g.deletedAt&&g.deletedAt<=cutoff)return false;
  // Purchase is the explicit effective date. Creation of an imported record
  // only tells us when it entered Gearhouse, not when the gear existed.
  if(g.purchased)return g.purchased.slice(0,10)<=date;
  if(g.sourceGearId||g.remoteId||g.importedTotals)return true;
  const evidence=[g.createdAt,
   ...state.events.filter(e=>e.gearId===g.id||e.parentId===g.id).map(e=>e.at),
   ...(state.gearStates||[]).filter(e=>e.gearId===g.id).map(e=>e.at),
   ...state.activities.filter(a=>a.snapshot?.some(x=>x.id===g.id)).map(a=>a.at),
   ...(state.gearEvents||[]).filter(e=>e.gearId===g.id).map(e=>e.occurredDate)
  ].filter(Boolean);
  return !evidence.length||evidence.some(at=>at<=cutoff);
 }).map(g=>({
  ...g,deletedAt:undefined,hidden:false,
  retired:!!g.retiredAt&&g.retiredAt<=cutoff,
  snapshotStatusUnknown:!!g.retired&&!g.retiredAt,
  snapshotAgeUnknown:!g.purchased&&(!!g.sourceGearId||!!g.remoteId||!!g.importedTotals)
 }));
 const ids=new Set(gears.map(g=>g.id));
 const events=state.events.filter(e=>e.at<=cutoff&&ids.has(e.gearId))
  .map(e=>({...e,parentId:ids.has(e.parentId)?e.parentId:null}));
 const gearEvents=(state.gearEvents||[]).filter(e=>ids.has(e.gearId)&&
  e.occurredDate+'T'+(e.occurredTime||'00:00')+':00'<=cutoff);
 const view={...state,gears,events,gearEvents,
  gearStates:(state.gearStates||[]).filter(e=>e.at<=cutoff&&ids.has(e.gearId)),
  gearOperations:(state.gearOperations||[]).filter(e=>e.at<=cutoff&&ids.has(e.gearId)),
  activities:state.activities.filter(a=>a.at&&a.at<=cutoff),
  snapshotView:{date,cutoff},
  statistics:Object.fromEntries(gears.map(g=>[g.id,snapshotStats(state,g,cutoff)]))
 };
 view.eventStatistics=Object.fromEntries(gearEvents.map(e=>[e.id,calculateEventMetrics(view,e,cutoff)]));
 return view;
}

export function calculateEventMetrics(s,event,now){
 const boundary=event.occurredDate+'T'+(event.occurredTime||'00:00')+':00';
 const after=event.occurredTime?boundary:new Date(Date.parse(event.occurredDate+'T00:00:00Z')+86400000).toISOString().slice(0,10)+'T00:00:00';
 const gear=s.gears.find(g=>g.id===event.gearId),baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
 const rows=s.activities.filter(a=>!a.deleted&&!a.summary&&!a.unavailable&&a.at<=now&&Number.isFinite(a.distance)&&a.distance>=0&&a.snapshot?.some(x=>x.id===event.gearId)&&a.snapshot.find(x=>x.id===event.gearId).distanceIncluded!==false);
 const sum=predicate=>rows.filter(predicate).reduce((v,a)=>v+a.distance,0);
 return {distance:sum(a=>a.at>=after),days:Math.round((Date.parse(now.slice(0,10))-Date.parse(event.occurredDate))/86400000),total:baseline&&baseline.through>boundary?null:(baseline?.distance||0)+sum(a=>a.at<boundary&&(!baseline||a.at>baseline.through)),limited:s.activities.some(a=>!a.deleted&&(a.unavailable||a.summary||!Number.isFinite(a.distance)))};
}
