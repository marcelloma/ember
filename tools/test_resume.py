"""Verify actual serialized resume across processes, isolation, and safe failures."""
from pathlib import Path
from PIL import Image, ImageChops
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
binary=Path(os.environ.get('EMBER_BINARY',str(root/'zig-out/bin/ember')))
rom=root/'roms/snes/Super Mario World (USA).sfc'
core=root/'cores/snes9x_libretro.so'
with tempfile.TemporaryDirectory(prefix='orbit-resume-') as temp:
    temp=Path(temp)
    def run(folder,frames,screenshot):
        env=dict(os.environ,SDL_VIDEODRIVER='dummy',SDL_AUDIODRIVER='dummy',ORBIT_DATA_DIR=str(folder),ORBIT_HOST_FRAMES=str(frames),ORBIT_HOST_SCREENSHOT=str(screenshot))
        return subprocess.run([str(binary),'--host',str(core),str(rom),'Super Mario World'],env=env,capture_output=True,text=True,timeout=20)
    first=run(temp/'resume',360,temp/'first.bmp')
    assert first.returncode==0,first.stderr
    state=temp/'resume/states/snes/Super Mario World (USA).resume.state'
    assert state.exists()
    second=run(temp/'resume',360,temp/'resumed.bmp')
    assert second.returncode==0,second.stderr
    assert 'Resume state restored:' in second.stderr
    uninterrupted=run(temp/'baseline',720,temp/'baseline.bmp')
    assert uninterrupted.returncode==0,uninterrupted.stderr
    a=Image.open(temp/'resumed.bmp').convert('RGB')
    b=Image.open(temp/'baseline.bmp').convert('RGB')
    assert ImageChops.difference(a,b).getbbox() is None,'Resume did not continue from the saved frame'
    print('PASS restart after 360 frames matches uninterrupted frame 720',flush=True)
    valid=state.read_bytes()
    for offset in [0,8,40,112]:
        broken=bytearray(valid);broken[offset]^=0xFF;state.write_bytes(broken)
        result=run(temp/'resume',1,temp/'bad.bmp')
        assert result.returncode==7,result.stderr
        assert state.read_bytes()==broken,'Rejected state was overwritten'
    state.write_bytes(valid)
    print('PASS damaged, wrong-ROM, and wrong-core states are rejected without overwrite',flush=True)
    # A failed temporary-file write must preserve the previous resume point.
    Path(str(state)+'.tmp').mkdir()
    result=run(temp/'resume',1,temp/'failed-save.bmp')
    assert result.returncode==4,result.stderr
    assert state.read_bytes()==valid,'Failed save replaced the previous resume point'
    print('PASS failed state write preserves the previous resume point',flush=True)
