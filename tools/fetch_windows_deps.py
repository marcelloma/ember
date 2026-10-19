"""Fetch checksum-pinned official x86_64 Windows dependencies (no system installation)."""
import json,urllib.request,hashlib,zipfile,io,pathlib,concurrent.futures
root=pathlib.Path(__file__).resolve().parents[1]
dest=root/'.deps/windows-x86_64'
dest.mkdir(parents=True,exist_ok=True)
(root/'.deps/downloads').mkdir(parents=True,exist_ok=True)
assets=json.loads((root/'packaging/windows/dependencies.json').read_text())
def fetch(a):
 p=root/'.deps/downloads'/a['name']
 data=(root/a['local_path']).read_bytes() if 'local_path' in a else (p.read_bytes() if p.exists() else urllib.request.urlopen(a['url'],timeout=120).read())
 digest=hashlib.sha256(data).hexdigest()
 if a['sha256'] and digest!=a['sha256']:raise RuntimeError('Checksum mismatch '+a['name'])
 a['sha256']=digest;p.write_bytes(data);print(a['name'],len(data),flush=True)
 return a,data
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(fetch,assets))
# Development libraries first; runtime packages fill in missing dependencies.
results.sort(key=lambda v: 0 if 'mingw' in v[0]['name'] else 1)
for a,data in results:
 with zipfile.ZipFile(io.BytesIO(data)) as z:
  for name in z.namelist():
   p=pathlib.PurePosixPath(name)
   if name.endswith('/'):continue
   target=None
   if 'x86_64-w64-mingw32' in p.parts:
    parts=p.parts[p.parts.index('x86_64-w64-mingw32')+1:]
    if parts and parts[0] in ('include','lib','bin') and not any(x in ('..','.') for x in parts):target=dest.joinpath(*parts)
   elif 'mingw' not in a['name'] and p.suffix.lower()=='.dll':
    target=dest/('cores' if a['component']=='snes9x' else 'bin')/p.name
   if target:
    target.parent.mkdir(parents=True,exist_ok=True)
    if not target.exists():target.write_bytes(z.read(name))
   if p.suffix.lower() in ('.txt','.md') and any(k in p.name.lower() for k in ('license','copying','readme')):
    target=dest/'licenses'/a['component']/p.name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(name))
print('Windows dependencies ready at',dest)
