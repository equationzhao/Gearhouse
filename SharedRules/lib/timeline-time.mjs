// Date-only records remain effective from their recorded civil day. Precise
// records carry UTC so repeated wall-clock hours can be ordered correctly.
export function compareTimeline(a,b){
 if(a.instant&&b.instant)return a.instant.localeCompare(b.instant);
 const day=a.at.slice(0,10).localeCompare(b.at.slice(0,10));
 if(day)return day;
 if(a.at===b.at&&a.at.endsWith('T00:00:00'))return 0;
 if(!a.instant&&b.instant)return a.allDay||a.at.endsWith('T00:00:00')?-1:(a.at.localeCompare(b.at)||-1);
 if(a.instant&&!b.instant)return b.allDay||b.at.endsWith('T00:00:00')?1:(a.at.localeCompare(b.at)||1);
 return a.at.localeCompare(b.at);
}
export function appliesAt(row,at,instant){
 if(row.instant&&instant)return row.instant<=instant;
 return row.at<=at;
}
