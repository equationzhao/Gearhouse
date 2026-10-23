export const INTERVAL = 5 * 60_000;
export const shanghaiDay = time => new Intl.DateTimeFormat('sv-SE', {timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(time));
const shift = (day,n) => new Date(Date.parse(day+'T00:00:00Z')+n*86400_000).toISOString().slice(0,10);
export function syncPlan(status,now=Date.now()) {
 const newest=shanghaiDay(now),daily=status.dailyThrough!==newest;
 let oldest=shift(newest,daily?-30:-7);
 if(status.lastSuccess){const overlap=shift(shanghaiDay(status.lastSuccess),-7);if(overlap<oldest)oldest=overlap;}
 if(status.resume){oldest=status.resume.next>newest?newest:status.resume.next;}
 return {oldest,newest,daily};
}
export function retryDelay(status,failures) {
 if(status===401||status===403)return null;
 return Math.max(status===429?15*60_000:0,Math.min(60*60_000,INTERVAL*2**Math.min(failures-1,4)));
}
// One shared job for automatic, immediate and historical requests.
export function singleFlight() {
 let active=null;
 return run=>{if(active)return active;active=Promise.resolve().then(run).finally(()=>{active=null;});return active;};
}
export function changedMerge(state,rows,merge,options) {
 const before=new Map(state.activities.map(a=>[a.id,JSON.stringify(a)]));
 const result=merge(state,rows,options);
 result.updated=state.activities.filter(a=>before.has(a.id)&&before.get(a.id)!==JSON.stringify(a)).length;
 result.changed=state.activities.length!==before.size||result.updated>0;
 return result;
}
