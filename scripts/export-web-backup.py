"""Export the Web application's SQLite state and JPEGs without reading credentials."""
import argparse, sqlite3, json, base64
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--data-dir',required=True,type=Path)
parser.add_argument('--output',required=True,type=Path)
args=parser.parse_args()
with sqlite3.connect((args.data_dir/'gearhouse.sqlite').resolve().as_uri()+'?mode=ro',uri=True) as db:
    row=db.execute('SELECT value FROM state WHERE id=1').fetchone()
if not row: raise SystemExit('No Gearhouse state found')
state=json.loads(row[0]);media={}
status=args.data_dir/'auto-sync.json'
if status.exists():
    state['autoSync']=json.loads(status.read_text())
    state['autoSync']['running']=False
    state['autoSync']['nextAt']=None
for photo in state.get('photos',[]):
    import uuid
    uuid.UUID(photo['id'])
    media[photo['id']]=base64.b64encode((args.data_dir/'media'/(photo['id']+'.jpg')).read_bytes()).decode()
args.output.parent.mkdir(parents=True,exist_ok=True)
with args.output.open('x') as f:
    args.output.chmod(0o600)
    json.dump({'state':state,'media':media},f,ensure_ascii=False)
print(f'Exported {len(state["gears"])} equipment items, {len(state["activities"])} activities and {len(media)} photos')
