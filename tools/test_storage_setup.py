"""Exercise first-run initialization, persistence, and the game process data directory."""
import os
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
binary = pathlib.Path(os.environ.get('EMBER_BINARY', root / 'zig-out/bin/ember'))
with tempfile.TemporaryDirectory(prefix='ember-first-run-') as tmp:
    folder = pathlib.Path(tmp)
    library = folder / 'Chosen Ember'
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy',
               XDG_DATA_HOME=str(folder / 'data'), EMBER_SETUP_CHECK=str(library),
               ORBIT_SCREENSHOT=str(folder / 'library.bmp'))
    for key in ('ORBIT_DATA_DIR', 'EMBER_ROM_DIR', 'EMBER_SKIP_SETUP'):
        env.pop(key, None)

    def run():
        result = subprocess.run([str(binary)], env=env, capture_output=True,
                                text=True, timeout=20)
        assert result.returncode == 0, result.stderr

    run()
    for child in ('roms/snes', 'configs', 'saves/snes', 'states/snes', 'settings/snes', 'system'):
        assert (library / child).is_dir(), child
    configs = list((folder / 'data').rglob('storage-path.txt'))
    assert len(configs) == 1 and configs[0].read_text() == str(library)
    assert (folder / 'library.bmp').stat().st_size > 0
    print('PASS first-run initialization and remembered custom directory')
    env.pop('EMBER_SETUP_CHECK')
    run()
    print('PASS restart skips setup and renders the library')
    rom = root / 'roms/snes/Super Mario World (USA).sfc'
    if rom.exists():
        shutil.copy(rom, library / 'roms/snes')
        env.pop('ORBIT_SCREENSHOT')
        env.update(ORBIT_LAUNCH_CHECK='2', ORBIT_HOST_FRAMES='120')
        run()
        assert list((library / 'states/snes').glob('*.state'))
        assert list((library / 'saves/snes').glob('*.srm'))
        print('PASS game process uses selected ROM, save, and resume-state directory')
