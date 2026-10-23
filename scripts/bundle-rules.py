"""Bundle the native app domain modules for in-process JavaScriptCore execution."""
from pathlib import Path
import argparse, re, hashlib, json
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Fail when generated rules are out of date.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source_root = root / 'SharedRules'
entry = root / 'SharedRules/native-entry.js'
modules = {}
def collect_modules(path):
    path = path.resolve()
    key = str(path.relative_to(source_root))
    if key in modules: return key
    source = path.read_text()
    modules[key] = ''
    def imported(m):
        names, target = m.groups()
        module = target if target.startswith('node:') else collect_modules(path.parent / target)
        return 'const {' + names + '} = require(' + json.dumps(module) + ');'
    source = re.sub(r"import\s*\{([^}]+)\}\s*from\s*['\"]([^'\"]+)['\"];?", imported, source)
    exports = re.findall(r'export\s+(?:async\s+)?function\s+(\w+)|export\s+(?:const|let|var)\s+(\w+)', source)
    names = [a or b for a,b in exports]
    source = re.sub(r'\bexport\s+', '', source)
    modules[key] = source + '\nreturn {' + ','.join(names) + '};'
    return key
collect_modules(entry)
shim = '''
if(typeof structuredClone === 'undefined') globalThis.structuredClone = x => JSON.parse(JSON.stringify(x));
const modules = Object.create(null), cache = Object.create(null);
modules['node:crypto'] = () => ({randomUUID:()=>nativeUUID(),createHash:()=>{let value='';return {update(x){value+=String(x);return this;},digest(){return nativeHash(value);}};}});
function require(id){ if(!cache[id]) cache[id]=modules[id](); return cache[id]; }
'''
output = shim + '\n'.join('modules['+json.dumps(k)+'] = function(){\n'+v+'\n};' for k,v in modules.items()) + "\nglobalThis.gearhouseCall = require('native-entry.js').call;\n"
manifest = {k:hashlib.sha256((source_root/k).read_bytes()).hexdigest() for k in modules}
files = {'Sources/GearhouseCore/Resources/gearhouse-rules.js': output, 'SharedRules/source-manifest.json': json.dumps(manifest,indent=2)+'\n'}
outdated = []
for relative, content in files.items():
    path = root / relative
    if args.check:
        if not path.exists() or path.read_text() != content: outdated.append(relative)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
if outdated: raise SystemExit('Regenerate the rules: python3 scripts/bundle-rules.py\n'+'\n'.join(outdated))
print('Bundled rules are current.' if args.check else f'Bundled {len(modules)} modules')
