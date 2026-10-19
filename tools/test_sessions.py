"""Boot all imported ROMs through the real host, checking video/audio and saves."""
import json, os, pathlib, re, subprocess, tempfile
from PIL import Image
root=pathlib.Path(__file__).resolve().parents[1]
binary=pathlib.Path(os.environ.get('EMBER_BINARY',str(root/'zig-out/bin/ember')))
with tempfile.TemporaryDirectory(prefix='orbit-sessions-') as tmp:
    for game in json.loads((root/'library/snes.json').read_text()):
        screenshot=pathlib.Path(tmp)/'frame.bmp'
        env=dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', ORBIT_DATA_DIR=tmp, ORBIT_HOST_FRAMES='900', ORBIT_HOST_SCREENSHOT=str(screenshot))
        result=subprocess.run([str(binary),'--host',str(root/'cores/snes9x_libretro.so'),str(root/game['rom_path']),game['title']],env=env,capture_output=True,text=True,timeout=30)
        output=result.stdout+result.stderr
        assert result.returncode==0,output
        match=re.search(r'(\d+) video frames, (\d+) audio frames',output)
        assert match and int(match[1])>0 and int(match[2])>0,output
        image=Image.open(screenshot).convert('RGB')
        assert any(high>low for low,high in image.getextrema()),'Empty game frame'
        save=pathlib.Path(tmp)/'saves/snes'/(pathlib.Path(game['rom_path']).stem+'.srm')
        resume=pathlib.Path(tmp)/'states/snes'/(pathlib.Path(game['rom_path']).stem+'.resume.state')
        assert resume.read_bytes()[:8]==b'ORBITST1','Missing resume state'
        assert resume.read_bytes()[8:40].hex()==game['sha256'],'Resume state belongs to wrong ROM'
        expected=int(re.search(r'SRAM bytes: (\d+)',output)[1])
        if expected:
            assert save.exists() and save.stat().st_size==expected,'Missing or incomplete battery save'
        print(f"PASS {game['title']}: video + audio, {expected} bytes SRAM",flush=True)
        if game['title']=='Chrono Trigger':
            seeded=bytes(i%256 for i in range(expected))
            save.write_bytes(seeded)
            # Test battery loading independently of automatic session resume.
            (pathlib.Path(tmp)/'states/snes'/(pathlib.Path(game['rom_path']).stem+'.resume.state')).unlink()
            env['ORBIT_HOST_FRAMES']='1'
            result=subprocess.run([str(binary),'--host',str(root/'cores/snes9x_libretro.so'),str(root/game['rom_path']),game['title']],env=env,capture_output=True,text=True,timeout=30)
            assert result.returncode==0,result.stdout+result.stderr
            assert save.read_bytes()==seeded,'Battery save did not survive a fresh process'
            print('PASS battery-save reload in a fresh process',flush=True)

    env.pop('ORBIT_HOST_SCREENSHOT',None)
    env['ORBIT_HOST_FRAMES']='60'
    env['ORBIT_LAUNCH_CHECK']='2'
    env['ORBIT_LAUNCH_SCREENSHOT']=str(pathlib.Path(tmp)/'library.bmp')
    result=subprocess.run([str(binary)],cwd=tmp,env=env,capture_output=True,text=True,timeout=30)
    assert result.returncode==0,result.stdout+result.stderr
    assert 'Library Play handoff and return passed' in result.stderr,result.stderr
    assert Image.open(pathlib.Path(tmp)/'library.bmp').getpixel((0,0))[:3] == (24,24,24),'Library was not restored'
    print('PASS library Play click -> game process -> library return (independent working directory)',flush=True)

    env['ORBIT_CORE_PATH']=str(pathlib.Path(tmp)/'missing-core.so')
    result=subprocess.run([str(binary)],cwd=tmp,env=env,capture_output=True,text=True,timeout=10)
    assert result.returncode!=0,'Missing core should fail gracefully'
    print('PASS missing core is reported instead of starting a session',flush=True)

    env.pop('ORBIT_CORE_PATH',None)
    env['ORBIT_HOST_FRAMES']='120'
    env['ORBIT_PAUSE_SCREENSHOT']=str(pathlib.Path(tmp)/'pause.bmp')
    env.pop('ORBIT_LAUNCH_CHECK',None)
    mario=root/'roms/snes/Super Mario World (USA).sfc'
    result=subprocess.run([str(binary),'--host',str(root/'cores/snes9x_libretro.so'),str(mario),'Super Mario World'],env=env,capture_output=True,text=True,timeout=20)
    assert result.returncode==0,result.stdout+result.stderr
    assert 'Pause overlay froze core and audio' in result.stderr,result.stderr
    assert 'Session finished: 120 frames' in result.stderr,'Game did not resume'
    assert Image.open(pathlib.Path(tmp)/'pause.bmp').getpixel((60,100))[:3] == (26,26,26),'Pause menu not rendered'
    print('PASS Escape pauses game/audio, renders controller overlay, and resumes',flush=True)
    env['ORBIT_PAUSE_RETURN']='1'
    env['ORBIT_LAUNCH_CHECK']='2'
    result=subprocess.run([str(binary)],cwd=tmp,env=env,capture_output=True,text=True,timeout=20)
    assert result.returncode==0,result.stdout+result.stderr
    assert 'Session finished: 60 frames' in result.stderr,'Paused game kept running'
    assert 'Library Play handoff and return passed' in result.stderr,'Return button failed'
    print('PASS pause overlay Save & return button restores library',flush=True)
