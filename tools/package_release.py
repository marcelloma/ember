"""Package an already-built target; optionally include the user's local ROMs."""
import argparse,hashlib,json,pathlib,tarfile,zipfile
root=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('target',choices=['windows-x86_64','linux-x86_64'])
p.add_argument('--include-roms',action='store_true',help='Include the ten local imported ROMs for a private build')
a=p.parse_args()
folder=root/'dist'/a.target/'bin'
executable=folder/('ember.exe' if a.target.startswith('windows') else 'ember')
if not executable.exists():raise SystemExit(f'Build {a.target} first')
files={path.relative_to(folder).as_posix():path for path in folder.rglob('*') if path.is_file() and path.suffix.lower() not in ('.pdb',)}
if a.include_roms:
    for game in json.loads((root/'library/snes.json').read_text()):
        rom=root/game['rom_path']
        if hashlib.sha256(rom.read_bytes()).hexdigest()!=game['sha256']:raise SystemExit('ROM checksum mismatch: '+str(rom))
        files[game['rom_path']]=rom
readme='''Ember 0.1.0

Extract the entire folder before launching. Open ember.exe on Windows, or
./ember on Linux. Keep assets/, cores/, and the Windows DLLs beside the program.
Linux requires SDL3, SDL3_ttf, and SDL3_image runtime libraries.

Click Play or double-click a cover to launch a game. Escape opens the pause menu.
Choose Save & return to library to exit; launching again restores your session.
The Escape menu includes per-game CRT scanlines and image stretch toggles.

Keyboard: arrows = D-pad; Z/X = B/A; A/S = Y/X; Q/W = L/R;
Enter = Start; Right Shift = Select. F11 toggles fullscreen.

Game content is resolved from roms/snes/ next to the executable. Saves, resume
states, and settings are stored in the current user's application data folder,
not in this extracted folder. Existing Orbit data-folder naming is retained.

Windows builds were cross-compiled on Linux and have not been runtime-tested on
Windows. See licenses/ and cores/SNES9X-LICENSE.txt for bundled software licenses.
'''
package_dir=root/'dist/packages';package_dir.mkdir(parents=True,exist_ok=True)
variant='-with-local-roms' if a.include_roms else ''
name=f'Ember-0.1.0-{a.target}{variant}'
manifest={key:hashlib.sha256(path.read_bytes()).hexdigest() for key,path in sorted(files.items())}
manifest_json=json.dumps(manifest,indent=2)+'\n'
if a.target.startswith('windows'):
    output=package_dir/(name+'.zip')
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for key,path in sorted(files.items()):z.write(path,'Ember/'+key)
        z.writestr('Ember/README.txt',readme)
        z.writestr('Ember/SHA256SUMS.json',manifest_json)
else:
    import io
    output=package_dir/(name+'.tar.gz')
    with tarfile.open(output,'w:gz') as tar:
        for key,path in sorted(files.items()):tar.add(path,arcname='Ember/'+key)
        for key,data in [('README.txt',readme),('SHA256SUMS.json',manifest_json)]:
            encoded=data.encode();info=tarfile.TarInfo('Ember/'+key);info.size=len(encoded);info.mode=0o644;tar.addfile(info,io.BytesIO(encoded))
print(output)
print(f'{len(files)} files, {output.stat().st_size/1024/1024:.1f} MiB; ROMs included: {a.include_roms}')
