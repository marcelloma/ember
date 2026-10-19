"""Exercise settings menu clicks, per-ROM persistence, and real rendered effects."""
from pathlib import Path
from PIL import Image, ImageChops
import json,os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
binary=Path(os.environ.get('EMBER_BINARY',str(root/'zig-out/bin/ember')))
games=json.loads((root/'library/snes.json').read_text())
mario=games[2]
with tempfile.TemporaryDirectory(prefix='orbit-settings-') as tmp:
    tmp=Path(tmp)
    def run(folder,game,frames,extra=None):
        env=dict(os.environ,SDL_VIDEODRIVER='dummy',SDL_AUDIODRIVER='dummy',ORBIT_DATA_DIR=str(folder),ORBIT_HOST_FRAMES=str(frames),ORBIT_WINDOW_SIZE='1600x900')
        env.update(extra or {})
        r=subprocess.run([str(binary),'--host',str(root/'cores/snes9x_libretro.so'),str(root/game['rom_path']),game['title']],env=env,capture_output=True,text=True,timeout=20)
        assert r.returncode==0,r.stdout+r.stderr
        return r
    folder=tmp/'selected'
    run(folder,mario,120,{'ORBIT_PAUSE_SCREENSHOT':'/tmp/orbit-settings-menu.bmp','ORBIT_SETTINGS_CHECK':'1'})
    path=folder/'settings/snes'/(mario['sha256']+'.json')
    assert json.loads(path.read_text())=={'version':1,'crt_scanlines':True,'fullscreen_stretch':True}
    run(folder,mario,600,{'ORBIT_HOST_SCREENSHOT':str(tmp/'effects.bmp')})
    assert json.loads(path.read_text())['crt_scanlines'] is True
    run(folder,games[0],1)
    assert not (folder/'settings/snes'/(games[0]['sha256']+'.json')).exists(),'Settings leaked to another game'
    print('PASS menu clicks persist both toggles across processes, isolated by ROM',flush=True)
    baseline=tmp/'baseline'
    profile=baseline/'settings/snes'/(mario['sha256']+'.json')
    profile.parent.mkdir(parents=True)
    profile.write_text(json.dumps({'version':1,'crt_scanlines':False,'fullscreen_stretch':True}))
    run(baseline,mario,720,{'ORBIT_HOST_SCREENSHOT':str(tmp/'stretch.bmp')})
    a=Image.open(tmp/'effects.bmp').convert('RGB')
    b=Image.open(tmp/'stretch.bmp').convert('RGB')
    assert a.size==(1600,900)
    assert ImageChops.difference(a,b).getbbox() is not None,'Scanlines not rendered'
    changed_rows=sum(ImageChops.difference(a.crop((0,y,1600,y+1)),b.crop((0,y,1600,y+1))).getbbox() is not None for y in range(900))
    assert 100<changed_rows<450,changed_rows
    run(tmp/'native',mario,720,{'ORBIT_HOST_SCREENSHOT':str(tmp/'native.bmp')})
    native=Image.open(tmp/'native.bmp').convert('RGB')
    assert native.crop((0,0,190,900)).getbbox() is None,'Original aspect ratio was not preserved'
    assert b.crop((0,0,190,900)).getbbox() is not None,'Stretch did not fill the window'
    print('PASS scanlines change only horizontal bands; stretch fills original pillarboxes',flush=True)
    Image.open('/tmp/orbit-settings-menu.bmp').save('/tmp/orbit-settings-menu.png')

    blocked=tmp/'blocked'
    blocked_profile=blocked/'settings/snes'/(mario['sha256']+'.json')
    blocked_profile.parent.mkdir(parents=True)
    original={'version':1,'crt_scanlines':False,'fullscreen_stretch':False}
    blocked_profile.write_text(json.dumps(original))
    Path(str(blocked_profile)+'.tmp').mkdir()
    run(blocked,mario,120,{'ORBIT_PAUSE_SCREENSHOT':str(tmp/'blocked-menu.bmp'),'ORBIT_SETTINGS_CHECK':'1'})
    assert json.loads(blocked_profile.read_text())==original,'Failed write changed saved settings'
    print('PASS failed settings write preserves prior values and keeps the game session usable',flush=True)
