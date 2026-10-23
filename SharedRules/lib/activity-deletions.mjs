// A missing list entry alone is not proof of deletion: dates can change and
// restricted providers may return partial data. Confirm each absent ID first.
export async function inspectMissingActivities(activities, rows, from, to, request) {
 if (!Array.isArray(rows) || rows.some(row => !row || !row.id)) {
  throw new Error('ICU 活动返回格式无效');
 }
 const present = new Set(rows.map(row => String(row.id)));
 const missing = activities.filter(a => !a.deleted && a.at?.slice(0,10) >= from &&
  a.at.slice(0,10) <= to && !present.has(a.id));
 const deleted = [], recovered = [];
 for (const activity of missing) {
  const before = JSON.stringify(activity);
  try {
   const row = await request('/activity/' + encodeURIComponent(activity.id) + '?intervals=false');
   if (!row?.id || String(row.id) !== activity.id) throw new Error('ICU 活动详情返回格式无效');
   recovered.push({before, row});
  } catch (error) {
   if (error.remoteStatus !== 404) throw error;
   deleted.push({id:activity.id, before});
  }
 }
 return {deleted, recovered};
}

export function applyConfirmedDeletions(state, confirmations, at) {
 let removed = 0;
 for (const entry of confirmations) {
  const activity = state.activities.find(a => a.id === entry.id);
  // A concurrent local edit requires checking again next time.
  if (!activity || activity.deleted || JSON.stringify(activity) !== entry.before) continue;
  activity.deleted = true;
  activity.remoteDeletedAt = at;
  activity.pending = false;
  activity.error = null;
  removed++;
 }
 return removed;
}
