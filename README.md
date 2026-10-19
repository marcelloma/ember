# Ember

A native Zig + SDL3 game launcher prototype for Linux and Windows.

## Automated builds

GitHub Actions builds every push to `main` and updates the rolling
[latest release](https://github.com/marcelloma/ember/releases/tag/latest) after
both Linux and Windows packages pass. Pull requests run the same build checks
without publishing. The workflow also supports manual runs on `main`.

Release downloads include a Linux tar.gz, Windows zip, and archive SHA-256
checksums. ROMs are excluded. Linux CI builds on Ubuntu 24.04 (glibc 2.39),
bundles the three SDL shared libraries, and uses system FreeType, HarfBuzz,
PNG, audio and desktop libraries. Windows bundles its SDL DLLs and core.
The Linux job runs unit tests and a headless library render; Windows binaries
receive PE/resource/DLL checks and still need runtime testing on Windows.
ROM-dependent integration tests remain local.

## Build and run

Requires **Zig 0.16.0**, **SDL3**, **SDL3_ttf**, and **SDL3_image** development
libraries. Linux builds discover these through pkg-config (`sdl3`, `sdl3-ttf`,
`sdl3-image`).

```sh
zig build run
```

If the default global cache is unavailable:

```sh
zig build run --global-cache-dir /tmp/orbit-zig-cache
```

Fonts and artwork are installed beside the executable in `zig-out/bin/assets`.
The executable resolves assets relative to itself, independent of the working
directory. Distribute that directory alongside the executable.

## Linux and Windows release builds

The supported release targets are **x86_64 Linux (glibc)** and **x86_64 Windows
(GNU ABI)**. Zig performs Windows cross-compilation directly; MinGW GCC and
Visual Studio are not needed on this Linux machine.

Fetch the pinned Windows SDK archives and emulator core once:

```sh
python3 tools/fetch_windows_deps.py
```

Downloads come from official SDL GitHub releases and the libretro build server.
SHA-256 checksums and URLs are locked in `packaging/windows/dependencies.json`.
The SDK is extracted into Git-ignored `.deps/windows-x86_64`, with cached archives
under `.deps/downloads`. No system packages or global toolchains are installed.
The build itself performs no downloads. Override the SDK path with
`-Dwindows-sdk=/absolute/path/to/sdk` if needed.

```sh
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe --prefix dist/windows-x86_64
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe --prefix dist/linux-x86_64
```

Both produce their executable and runtime assets in their prefix's `bin/` folder.
Windows output includes `ember.exe`, a GUI subsystem (no console window), the
embedded flame icon and version resource, SDL/runtime DLLs, fonts, artwork,
license notices, and `cores/snes9x_libretro.dll`. Linux output includes the ELF
executable and Linux Snes9x core; SDL3 runtime packages are system dependencies.
Linux uses this machine's installed SDL headers/libraries and detected glibc
version (currently 2.43); this package is not a universal old-distro/AppImage
build. Building against an older Linux runtime requires a matching SDK/sysroot.

Package outputs:

```sh
python3 tools/check_windows_package.py
python3 tools/package_release.py windows-x86_64
python3 tools/package_release.py windows-x86_64 --include-roms
python3 tools/package_release.py linux-x86_64 --include-roms
```

Archives are written to `dist/packages/`. `--include-roms` adds only the ten local
imported ROMs, verified against the library's checksums, for a private playable
build. Without it, copy those ROMs into `roms/snes/` beside the extracted
executable. The launcher currently has a fixed ten-game SNES library.
Extract the entire archive before running; keep DLLs, assets, and cores together.

Windows PE architecture, GUI subsystem, resource presence, and DLL dependency
closure are checked by the validation script. Windows execution has not been
tested: neither Windows nor Wine is installed here. Linux session tests can
exercise an extracted package with `EMBER_BINARY=/absolute/path/to/Ember/ember`.

## Controls

- Arrows or WASD: navigate the responsive cover grid. Left/right wraps.
- Mouse wheel: scroll the cover grid. Keyboard selection scrolls into view.
- Tab / Shift+Tab: next / previous game.
- Home / End: first / last game.
- Click a cover: select it; double-click to play.
- Enter / Space or the Play button: start the selected game directly.
- Escape in a game: pause and open the controller/keybind overlay. Escape in the library: exit.

The layout fills the window without letterboxing, adapts its column count to the
available width, and scrolls when the covers exceed the available height. Covers
stay at 208 x 312 logical pixels with 24-pixel horizontal gaps; resizing changes
the viewport and column count, never the cover size. The
selection bar stays anchored to the bottom. Minimum window size is 800 x 600.
High-density display output and mouse coordinates use SDL logical presentation.
Hover highlights and persistent selection indicate navigation state.

## SNES library and artwork

The launcher now displays the ten imported SNES games. `library/snes.json` records
full titles, local ROM paths, SHA-256 checksums, and corresponding cover paths.
ROM content stays in the Git-ignored `roms/snes/` folder. Play starts a separate
libretro host process, hides the library during play, and restores it on exit.
The host loads the Snes9x shared library directly; RetroArch is not required.

All ten covers are existing community portrait adaptations downloaded at their
original 600 x 900 resolution from SteamGridDB. No AI-generated art or enlarged
low-resolution images are used. The art retains its original aspect ratio and
fills fixed 208 x 312 cards. `assets/covers/snes/sources.json` records each
creator, source page, full-size download URL, and dimensions. Artwork belongs to
its respective rights holders and is not covered by the project's code license.

`python3 tools/fetch_covers.py` verifies the cached cover files. Add `--download`
to download a missing file from its recorded URL (requires network; if the site
refuses direct requests, download through the recorded source page instead).
Bundled Open Sans fonts include their license in `assets/fonts/LICENSE.txt`.

## Playing SNES games

Click Play, press Enter, or double-click a cover. The selected ROM opens in a
fullscreen game surface owned by Ember, with audio and no emulator menus.
Escape opens a pause overlay showing a SNES controller and arrows labeling every
keyboard binding. Escape again resumes; choose Resume or Save & return to library
with the mouse, or use Left/Right (or Tab) and Enter. Game execution and audio
remain paused while the overlay is open. F11 toggles fullscreen.

The Escape menu also exposes two display toggles: **CRT scanlines** overlays
subtle horizontal dark bands on the game image; **Full screen (stretch)** fills
the entire game window instead of preserving its original aspect ratio. Both
default to off. Click a toggle or select it with Tab/arrows and press Enter or
Space. Changes preview immediately behind the menu and save immediately.

Display settings persist independently of resume states in
`settings/snes/<ROM SHA-256>.json` under the per-user data folder. Each game keeps
its own settings across sessions and reboots. Files use versioned JSON and
atomic replacement. A failed write leaves the previous values active and shows
an error in the menu. The stretch setting controls the image shape; F11 still
controls whether the game window itself is fullscreen. Switching away
pauses emulation and audio until the game regains focus.

Keyboard controls (SNES layout):

| Key | SNES button |
| --- | --- |
| Arrow keys | D-pad |
| Z / X | B / A |
| A / S | Y / X |
| Q / W | L / R |
| Enter / Right Shift | Start / Select |

Up to two SDL gamepads are supported with hotplugging. Face buttons follow their
physical positions (south = B, east = A, west = Y, north = X); the D-pad and left
stick both control movement. Keyboard controls player one.

Battery SRAM and RTC are restored on launch, saved every two seconds during
play, and saved again on normal exit. Saves use temporary-file replacement under
SDL's existing per-user data folder (`SDL_GetPrefPath("Orbit", "Orbit")`,
retained for compatibility with saves created before the Ember rename), in `saves/snes`.
`ORBIT_DATA_DIR` overrides the data folder. Mega Man X uses passwords and has no
battery SRAM. Each normal game exit also serializes an automatic resume state into
`states/snes/<ROM filename>.resume.state`. Launching that game restores the state
automatically before its first frame, continuing the exact session rather than
cold-booting. This works when exiting through the pause menu or closing the game
window, and persists across launcher and computer restarts. Force-killing a
process or losing power cannot create a new exit state.

Resume states use an Ember envelope with a format marker, ROM SHA-256, core-binary
SHA-256, state length, and payload SHA-256. Incompatible or damaged states are
reported instead of silently discarded. Writes use a temporary file and atomic
replacement, preserving the previous resume point on write failure. Battery
SRAM/RTC remains separate; restoring a full session also restores the SRAM
contained in that session. A core update may make an existing resume point
incompatible; the library reports that case.

The bundled core is the official Linux x86_64 Snes9x libretro build. Its source
URL and SHA-256 checksum are recorded in `cores/source.json`; its non-commercial
license is included in `cores/SNES9X-LICENSE.txt`. The host checks the libretro API
version and required symbols. It supports software-framebuffer cores using
XRGB8888, RGB565, or 0RGB1555 video and stereo 16-bit audio.

The executable expects `cores/snes9x_libretro.so` beside it on Linux, or
`cores/snes9x_libretro.dll` on Windows. `ORBIT_CORE_PATH` overrides this location.
ROMs are resolved from `roms/snes` beside the installed executable, falling back
to the project-root ROM folder for development. ROMs are not bundled by the build.

## Verification

```sh
zig build test
python3 tools/test_sessions.py
python3 tools/test_resume.py
python3 tools/test_game_settings.py
```

Unit tests use an actual SDL virtual controller to verify button/axis mappings,
port isolation, focus handling, and duplicate hotplug events; core option/video
negotiation is tested too. The integration script boots all ten imported ROMs
for 900 frames with dummy SDL video/audio, checks real video/audio callbacks and
battery-save sizes, verifies SRAM reload in a fresh process, and exercises the
library's Play-button event, process handoff, and rendered return to the library
from a different working directory. It also checks missing-core failure, Escape
pause/resume without advancing game/audio callbacks, the rendered controller
overlay, and its Save & return button. The resume test compares a restarted session
against an uninterrupted run, checks ROM/core/payload validation, and confirms
that failed writes preserve the previous resume point.

Library screenshot without a display server:

```sh
SDL_VIDEODRIVER=dummy ORBIT_SCREENSHOT=/tmp/orbit.bmp ./zig-out/bin/ember
```

`ORBIT_WINDOW_SIZE=1920x1080` selects a viewport for render checks.
`ORBIT_HOST_FRAMES` enables accelerated, finite headless host checks, with
`ORBIT_HOST_SCREENSHOT` saving the final game frame. These options are for testing.

Linux and Windows x86_64 release builds are supported. Windows has been
cross-compiled and statically checked, but still requires runtime validation on
Windows (see release-build instructions above).
