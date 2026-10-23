// Usage comes from the saved activity snapshot, never today's assembly tree.
export function gearActivityRows(state, gearId, cutoff=state.snapshotView?.cutoff) {
 const gear=state.gears.find(g=>g.id===gearId);
 const baseline=gear?.totalsMode==='local'?null:gear?.importedTotals;
 const seen=new Set();
 return state.activities.filter(a=>{
  if(seen.has(a.id)||a.deleted||a.summary||a.unavailable||!a.at||
     cutoff&&a.at>cutoff||!a.snapshot?.some(row=>row.id===gearId))return false;
  seen.add(a.id);return true;
 }).sort((a,b)=>b.at.localeCompare(a.at)||String(a.id).localeCompare(String(b.id)))
 .map(activity=>{
  const membership=activity.snapshot.find(row=>row.id===gearId);
  const excluded=membership.distanceIncluded===false;
  const measured=value=>Number.isFinite(value)&&value>=0?value:null;
  return {activity,excluded,distance:excluded?0:measured(activity.distance),
   sourceDistance:measured(activity.distance),seconds:measured(activity.seconds),
   baselineCovered:!!baseline&&activity.at<=baseline.through,
   path:savedGearPath(activity,gearId)};
 });
}

export function savedGearPath(activity,gearId) {
 const path=[],seen=new Set();let id=gearId;
 while(id&&!seen.has(id)){
  seen.add(id);path.unshift(id);
  const row=activity.snapshot?.find(item=>item.id===id);
  if(!row)break;
  id=row.parentId;
 }
 return path;
}

export function usageDuration(seconds) {
 if(seconds===null)return '—';
 const minutes=Math.floor(seconds/60);
 return `${Math.floor(minutes/60)}h ${String(minutes%60).padStart(2,'0')}m`;
}

export function validateUsageRange(range) {
 for(const value of [range.from,range.to]){
  if(!value)continue;
  if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||
     !Number.isFinite(Date.parse(value+'T00:00:00Z'))||
     new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)
   throw new Error('请选择有效日期');
 }
 if(range.from&&range.to&&range.from>range.to)throw new Error('开始日期不能晚于结束日期');
}

export function filterUsageRange(rows,range={}) {
 validateUsageRange(range);
 return rows.filter(row=>{
  const day=row.activity.at.slice(0,10);
  return (!range.from||day>=range.from)&&(!range.to||day<=range.to);
 });
}

export function summarizeUsage(rows) {
 return rows.reduce((sum,row)=>{
  if(row.distance===null)sum.missingDistance++;else sum.distance+=row.distance;
  if(row.seconds===null)sum.missingTime++;else sum.seconds+=row.seconds;
  sum.count++;
  return sum;
 },{distance:0,seconds:0,count:0,missingDistance:0,missingTime:0});
}
