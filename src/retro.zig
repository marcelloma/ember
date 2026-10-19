const std = @import("std");
const c = @import("api.zig").c;
const settings_io = @import("game_settings.zig");
const pause_ui = @import("pause_menu.zig");
fn load(comptime T: type, lib: *c.SDL_SharedObject, comptime name: [:0]const u8) !T {
    return @ptrCast(c.SDL_LoadFunction(lib, name) orelse return error.MissingCoreSymbol);
}
const Core = struct {
    init: *const fn () callconv(.c) void,
    deinit: *const fn () callconv(.c) void,
    api_version: *const fn () callconv(.c) c_uint,
    get_system_info: *const fn (*c.struct_retro_system_info) callconv(.c) void,
    get_system_av_info: *const fn (*c.struct_retro_system_av_info) callconv(.c) void,
    set_environment: *const fn (c.retro_environment_t) callconv(.c) void,
    set_video_refresh: *const fn (c.retro_video_refresh_t) callconv(.c) void,
    set_audio_sample: *const fn (c.retro_audio_sample_t) callconv(.c) void,
    set_audio_sample_batch: *const fn (c.retro_audio_sample_batch_t) callconv(.c) void,
    set_input_poll: *const fn (c.retro_input_poll_t) callconv(.c) void,
    set_input_state: *const fn (c.retro_input_state_t) callconv(.c) void,
    set_controller_port_device: *const fn (c_uint, c_uint) callconv(.c) void,
    load_game: *const fn (*const c.struct_retro_game_info) callconv(.c) bool,
    unload_game: *const fn () callconv(.c) void,
    run: *const fn () callconv(.c) void,
    serialize_size: *const fn () callconv(.c) usize,
    serialize: *const fn (?*anyopaque, usize) callconv(.c) bool,
    unserialize: *const fn (?*const anyopaque, usize) callconv(.c) bool,
    get_memory_data: *const fn (c_uint) callconv(.c) ?*anyopaque,
    get_memory_size: *const fn (c_uint) callconv(.c) usize,
    fn open(lib: *c.SDL_SharedObject) !Core {
        var core: Core = undefined;
        inline for (@typeInfo(Core).@"struct".fields) |field| {
            @field(core, field.name) = try load(field.type, lib, "retro_" ++ field.name);
        }
        if (core.api_version() != c.RETRO_API_VERSION) return error.UnsupportedCoreAPI;
        return core;
    }
};
const Option = struct { key: [*:0]const u8, value: [256:0]u8 };
const Context = struct {
    renderer: *c.SDL_Renderer,
    texture: ?*c.SDL_Texture = null,
    tw: c_uint = 0,
    th: c_uint = 0,
    pixel_format: c_uint = c.RETRO_PIXEL_FORMAT_0RGB1555,
    stream: ?*c.SDL_AudioStream = null,
    sample_rate: f64 = 32040,
    aspect: f32 = 4.0 / 3.0,
    system_dir: [:0]const u8,
    save_dir: [:0]const u8,
    options: [128]Option = undefined,
    option_count: usize = 0,
    pads: [2]?*c.SDL_Gamepad = .{ null, null },
    focused: bool = true,
    paused: bool = false,
    start_blocked: bool = false,
    shutdown: bool = false,
    failed: bool = false,
    video_frames: usize = 0,
    audio_frames: usize = 0,
};
var active: *Context = undefined;
fn typed(comptime T: type, data: ?*anyopaque) *T {
    return @ptrCast(@alignCast(data.?));
}
fn environment(cmd: c_uint, data: ?*anyopaque) callconv(.c) bool {
    if (data == null and cmd != c.RETRO_ENVIRONMENT_SHUTDOWN) return false;
    switch (cmd) {
        c.RETRO_ENVIRONMENT_GET_CAN_DUPE => {
            typed(bool, data).* = true;
            return true;
        },
        c.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT => {
            const format = typed(c_uint, data).*;
            if (format > c.RETRO_PIXEL_FORMAT_RGB565) return false;
            active.pixel_format = format;
            return true;
        },
        c.RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY => {
            typed([*:0]const u8, data).* = active.system_dir.ptr;
            return true;
        },
        c.RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY => {
            typed([*:0]const u8, data).* = active.save_dir.ptr;
            return true;
        },
        c.RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION => {
            typed(c_uint, data).* = 0;
            return true;
        },
        c.RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE => {
            typed(bool, data).* = false;
            return true;
        },
        c.RETRO_ENVIRONMENT_SET_VARIABLES => {
            const vars: [*]const c.struct_retro_variable = @ptrCast(@alignCast(data.?));
            active.option_count = 0;
            for (0..128) |i| {
                if (vars[i].key == null) break;
                const desc = std.mem.span(vars[i].value);
                const semicolon = std.mem.indexOfScalar(u8, desc, ';') orelse continue;
                const choices = std.mem.trimStart(u8, desc[semicolon + 1 ..], " ");
                const first = choices[0..(std.mem.indexOfScalar(u8, choices, '|') orelse choices.len)];
                if (first.len >= 256) continue;
                const opt = &active.options[active.option_count];
                opt.key = @ptrCast(vars[i].key);
                @memcpy(opt.value[0..first.len], first);
                opt.value[first.len] = 0;
                active.option_count += 1;
            }
            return true;
        },
        c.RETRO_ENVIRONMENT_GET_VARIABLE => {
            const variable = typed(c.struct_retro_variable, data);
            if (variable.key == null) return false;
            for (active.options[0..active.option_count]) |*opt| {
                if (std.mem.eql(u8, std.mem.span(variable.key), std.mem.span(opt.key))) {
                    variable.value = &opt.value;
                    return true;
                }
            }
            variable.value = null;
            return false;
        },
        c.RETRO_ENVIRONMENT_SET_GEOMETRY => {
            const geometry = typed(c.struct_retro_game_geometry, data);
            if (geometry.aspect_ratio > 0) active.aspect = geometry.aspect_ratio;
            return true;
        },
        c.RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS, c.RETRO_ENVIRONMENT_SET_CONTROLLER_INFO => return true,
        c.RETRO_ENVIRONMENT_GET_INPUT_BITMASKS => return false,
        c.RETRO_ENVIRONMENT_SHUTDOWN => {
            active.shutdown = true;
            return true;
        },
        else => return false,
    }
}
fn video(data: ?*const anyopaque, width: c_uint, height: c_uint, pitch: usize) callconv(.c) void {
    if (data == null) return; // libretro duplicate frame
    if (width == 0 or height == 0 or width > 2048 or height > 2048 or pitch > 16384) {
        active.failed = true;
        return;
    }
    if (active.texture == null or active.tw != width or active.th != height) {
        if (active.texture) |t| c.SDL_DestroyTexture(t);
        const format: c.SDL_PixelFormat = switch (active.pixel_format) {
            c.RETRO_PIXEL_FORMAT_XRGB8888 => c.SDL_PIXELFORMAT_XRGB8888,
            c.RETRO_PIXEL_FORMAT_RGB565 => c.SDL_PIXELFORMAT_RGB565,
            else => c.SDL_PIXELFORMAT_XRGB1555,
        };
        active.texture = c.SDL_CreateTexture(active.renderer, format, c.SDL_TEXTUREACCESS_STREAMING, @intCast(width), @intCast(height));
        active.tw = width;
        active.th = height;
        if (active.texture) |t| {
            _ = c.SDL_SetTextureScaleMode(t, c.SDL_SCALEMODE_NEAREST);
        }
    }
    if (active.texture) |t| {
        if (!c.SDL_UpdateTexture(t, null, data, @intCast(pitch))) active.failed = true;
        active.video_frames += 1;
    } else active.failed = true;
}
fn audioBatch(samples: [*c]const i16, frames: usize) callconv(.c) usize {
    if (samples == null or frames > 65536) return 0;
    active.audio_frames += frames;
    if (active.stream) |stream| {
        if (c.SDL_GetAudioStreamQueued(stream) > @as(c_int, @intFromFloat(active.sample_rate))) _ = c.SDL_ClearAudioStream(stream);
        if (!c.SDL_PutAudioStreamData(stream, samples, @intCast(frames * 4))) active.failed = true;
    }
    return frames;
}
fn audioSample(left: i16, right: i16) callconv(.c) void {
    const pair = [2]i16{ left, right };
    _ = audioBatch(&pair, 1);
}
fn inputPoll() callconv(.c) void {
    if (!c.SDL_GetKeyboardState(null)[c.SDL_SCANCODE_RETURN]) active.start_blocked = false;
}
fn inputState(port: c_uint, device: c_uint, index: c_uint, id: c_uint) callconv(.c) i16 {
    if (active.paused or !active.focused or port >= 2 or device != c.RETRO_DEVICE_JOYPAD or index != 0 or id >= 12) return 0;
    const keys = [_]c.SDL_Scancode{ c.SDL_SCANCODE_Z, c.SDL_SCANCODE_A, c.SDL_SCANCODE_RSHIFT, c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_UP, c.SDL_SCANCODE_DOWN, c.SDL_SCANCODE_LEFT, c.SDL_SCANCODE_RIGHT, c.SDL_SCANCODE_X, c.SDL_SCANCODE_S, c.SDL_SCANCODE_Q, c.SDL_SCANCODE_W };
    const buttons = [_]c.SDL_GamepadButton{ c.SDL_GAMEPAD_BUTTON_SOUTH, c.SDL_GAMEPAD_BUTTON_WEST, c.SDL_GAMEPAD_BUTTON_BACK, c.SDL_GAMEPAD_BUTTON_START, c.SDL_GAMEPAD_BUTTON_DPAD_UP, c.SDL_GAMEPAD_BUTTON_DPAD_DOWN, c.SDL_GAMEPAD_BUTTON_DPAD_LEFT, c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT, c.SDL_GAMEPAD_BUTTON_EAST, c.SDL_GAMEPAD_BUTTON_NORTH, c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER };
    if (port == 0 and !(id == c.RETRO_DEVICE_ID_JOYPAD_START and active.start_blocked) and c.SDL_GetKeyboardState(null)[@intCast(keys[id])]) return 1;
    if (active.pads[port]) |pad| {
        if (c.SDL_GetGamepadButton(pad, buttons[id])) return 1;
        const ax = c.SDL_GetGamepadAxis(pad, c.SDL_GAMEPAD_AXIS_LEFTX);
        const ay = c.SDL_GetGamepadAxis(pad, c.SDL_GAMEPAD_AXIS_LEFTY);
        if ((id == 4 and ay < -16000) or (id == 5 and ay > 16000) or (id == 6 and ax < -16000) or (id == 7 and ax > 16000)) return 1;
    }
    return 0;
}
fn addPad(id: c.SDL_JoystickID) void {
    for (active.pads) |slot| if (slot) |pad| {
        if (c.SDL_GetGamepadID(pad) == id) return;
    };
    for (&active.pads) |*slot| if (slot.* == null) {
        slot.* = c.SDL_OpenGamepad(id);
        return;
    };
}
fn persist(core: Core, path: [:0]const u8, kind: c_uint) !void {
    const size = core.get_memory_size(kind);
    const data = core.get_memory_data(kind);
    if (size == 0 or data == null) return;
    var buf: [4096]u8 = undefined;
    const temp = try std.fmt.bufPrintZ(&buf, "{s}.tmp", .{path});
    if (!c.SDL_SaveFile(temp, data, size) or !c.SDL_RenamePath(temp, path)) return error.SaveFailed;
}
fn restore(core: Core, path: [:0]const u8, kind: c_uint) void {
    const size = core.get_memory_size(kind);
    const target = core.get_memory_data(kind);
    if (size == 0 or target == null) return;
    var actual: usize = 0;
    const data = c.SDL_LoadFile(path, &actual) orelse return;
    defer c.SDL_free(data);
    if (actual == size) @memcpy(@as([*]u8, @ptrCast(target))[0..size], @as([*]const u8, @ptrCast(data))[0..size]);
}
const StateIdentity = struct { rom: [32]u8, core: [32]u8 };
const state_header_size = 112;
const state_magic = "ORBITST1";
fn saveState(allocator: std.mem.Allocator, core: Core, path: [:0]const u8, identity: StateIdentity) !void {
    const size = core.serialize_size();
    if (size == 0 or size > 64 * 1024 * 1024) return error.ResumeStateUnsupported;
    const bytes = try allocator.alloc(u8, state_header_size + size);
    defer allocator.free(bytes);
    @memcpy(bytes[0..8], state_magic);
    @memcpy(bytes[8..40], &identity.rom);
    @memcpy(bytes[40..72], &identity.core);
    std.mem.writeInt(u64, bytes[72..80], @intCast(size), .little);
    if (!core.serialize(bytes[state_header_size..].ptr, size)) return error.ResumeStateSave;
    var checksum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[state_header_size..], &checksum, .{});
    @memcpy(bytes[80..112], &checksum);
    var buffer: [4096]u8 = undefined;
    const temp = try std.fmt.bufPrintZ(&buffer, "{s}.tmp", .{path});
    // Replace the previous resume point only after serialization and writing succeed.
    if (!c.SDL_SaveFile(temp, bytes.ptr, bytes.len) or !c.SDL_RenamePath(temp, path)) return error.SaveFailed;
    c.SDL_Log("Resume state saved: %zu bytes", size);
}
fn restoreState(core: Core, path: [:0]const u8, identity: StateIdentity) !bool {
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path, &info)) return false;
    if (info.size < state_header_size or info.size > state_header_size + 64 * 1024 * 1024) return error.ResumeStateInvalid;
    var size: usize = 0;
    const data = c.SDL_LoadFile(path, &size) orelse return error.ResumeStateRead;
    defer c.SDL_free(data);
    const bytes = @as([*]const u8, @ptrCast(data))[0..size];
    if (size < state_header_size or !std.mem.eql(u8, bytes[0..8], state_magic)) return error.ResumeStateInvalid;
    if (!std.mem.eql(u8, bytes[8..40], &identity.rom) or !std.mem.eql(u8, bytes[40..72], &identity.core)) return error.ResumeStateMismatch;
    const expected = std.mem.readInt(u64, bytes[72..80], .little);
    if (expected != size - state_header_size or expected != core.serialize_size()) return error.ResumeStateInvalid;
    var checksum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[state_header_size..], &checksum, .{});
    if (!std.mem.eql(u8, bytes[80..112], &checksum)) return error.ResumeStateInvalid;
    if (!core.unserialize(bytes[state_header_size..].ptr, @intCast(expected))) return error.ResumeStateRejected;
    c.SDL_Log("Resume state restored: %zu bytes", size - state_header_size);
    return true;
}
fn pause(ctx: *Context, menu: *pause_ui.Menu, enabled: bool) void {
    ctx.paused = enabled;
    if (enabled) {
        menu.selected = 0;
        ctx.start_blocked = true;
        _ = c.SDL_ShowCursor();
        _ = c.SDL_PauseAudioStreamDevice(ctx.stream);
        _ = c.SDL_ClearAudioStream(ctx.stream);
    } else {
        _ = c.SDL_HideCursor();
        if (ctx.focused) _ = c.SDL_ResumeAudioStreamDevice(ctx.stream);
    }
}
fn toggleSetting(menu: *pause_ui.Menu, action: pause_ui.Action, path: [:0]const u8) void {
    var candidate = menu.settings;
    switch (action) {
        .toggle_scanlines => candidate.crt_scanlines = !candidate.crt_scanlines,
        .toggle_stretch => candidate.fullscreen_stretch = !candidate.fullscreen_stretch,
        else => return,
    }
    settings_io.write(path, candidate) catch {
        menu.settings_error = true;
        return;
    };
    menu.settings = candidate;
    menu.settings_error = false;
}
pub fn run(allocator: std.mem.Allocator, core_path: [:0]const u8, rom: [:0]const u8, title: [:0]const u8) !void {
    @import("brand.zig").configure();
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMEPAD)) return error.SDLInitialization;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.FontInitialization;
    defer c.TTF_Quit();
    const smoke = c.SDL_getenv("ORBIT_HOST_FRAMES");
    const frame_limit = if (smoke != null) try std.fmt.parseInt(usize, std.mem.span(smoke), 10) else 0;
    const window = c.SDL_CreateWindow(title, 1280, 960, if (frame_limit > 0) c.SDL_WINDOW_HIDDEN else c.SDL_WINDOW_FULLSCREEN | c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse return error.GameWindow;
    defer c.SDL_DestroyWindow(window);
    try @import("brand.zig").setWindowIcon(window);
    if (frame_limit > 0) {
        if (c.SDL_getenv("ORBIT_WINDOW_SIZE")) |size| {
            var parts = std.mem.splitScalar(u8, std.mem.span(size), 'x');
            const w = try std.fmt.parseInt(c_int, parts.next() orelse return error.InvalidSize, 10);
            const h = try std.fmt.parseInt(c_int, parts.next() orelse return error.InvalidSize, 10);
            if (w < 1 or h < 1) return error.InvalidSize;
            if (!c.SDL_SetWindowSize(window, w, h)) return error.InvalidSize;
        }
    }
    if (frame_limit == 0) _ = c.SDL_HideCursor();
    const renderer = c.SDL_CreateRenderer(window, null) orelse return error.GameRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    var menu = try pause_ui.Menu.init(allocator, renderer);
    defer menu.deinit();
    _ = c.SDL_SetRenderVSync(renderer, 0);
    const pref = if (c.SDL_getenv("ORBIT_DATA_DIR")) |p| try allocator.dupeZ(u8, std.mem.span(p)) else blk: {
        const p = c.SDL_GetPrefPath("Orbit", "Orbit") orelse return error.SaveDirectory;
        defer c.SDL_free(p);
        break :blk try allocator.dupeZ(u8, std.mem.span(p));
    };
    defer allocator.free(pref);
    const system_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/system", .{pref}, 0);
    defer allocator.free(system_dir);
    const save_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/saves/snes", .{pref}, 0);
    defer allocator.free(save_dir);
    if (!c.SDL_CreateDirectory(system_dir) or !c.SDL_CreateDirectory(save_dir)) return error.SaveDirectory;
    var ctx = Context{ .renderer = renderer, .system_dir = system_dir, .save_dir = save_dir };
    active = &ctx;
    defer if (ctx.texture) |texture| c.SDL_DestroyTexture(texture);
    defer for (ctx.pads) |pad| {
        if (pad) |p| c.SDL_CloseGamepad(p);
    };
    const lib = c.SDL_LoadObject(core_path) orelse return error.CoreNotFound;
    defer c.SDL_UnloadObject(lib);
    const core = try Core.open(lib);
    core.set_environment(environment);
    core.set_video_refresh(video);
    core.set_audio_sample(audioSample);
    core.set_audio_sample_batch(audioBatch);
    core.set_input_poll(inputPoll);
    core.set_input_state(inputState);
    core.init();
    defer core.deinit();
    var info: c.struct_retro_system_info = std.mem.zeroes(c.struct_retro_system_info);
    core.get_system_info(&info);
    var rom_size: usize = 0;
    const rom_data = c.SDL_LoadFile(rom, &rom_size) orelse return error.ROMNotFound;
    defer c.SDL_free(rom_data);
    const game = c.struct_retro_game_info{ .path = rom.ptr, .data = if (info.need_fullpath) null else rom_data, .size = if (info.need_fullpath) 0 else rom_size, .meta = null };
    if (!core.load_game(&game)) return error.CoreRejectedROM;
    defer core.unload_game();
    core.set_controller_port_device(0, c.RETRO_DEVICE_JOYPAD);
    core.set_controller_port_device(1, c.RETRO_DEVICE_JOYPAD);
    const stem = std.fs.path.stem(rom);
    const save_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}.srm", .{ save_dir, stem }, 0);
    defer allocator.free(save_path);
    const rtc_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}.rtc", .{ save_dir, stem }, 0);
    defer allocator.free(rtc_path);
    restore(core, save_path, c.RETRO_MEMORY_SAVE_RAM);
    restore(core, rtc_path, c.RETRO_MEMORY_RTC);
    const state_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/states/snes", .{pref}, 0);
    defer allocator.free(state_dir);
    if (!c.SDL_CreateDirectory(state_dir)) return error.SaveDirectory;
    const state_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}.resume.state", .{ state_dir, stem }, 0);
    defer allocator.free(state_path);
    var identity: StateIdentity = undefined;
    std.crypto.hash.sha2.Sha256.hash(@as([*]const u8, @ptrCast(rom_data))[0..rom_size], &identity.rom, .{});
    var core_size: usize = 0;
    const core_bytes = c.SDL_LoadFile(core_path, &core_size) orelse return error.CoreNotFound;
    defer c.SDL_free(core_bytes);
    std.crypto.hash.sha2.Sha256.hash(@as([*]const u8, @ptrCast(core_bytes))[0..core_size], &identity.core, .{});
    _ = try restoreState(core, state_path, identity);
    const settings_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/settings/snes", .{pref}, 0);
    defer allocator.free(settings_dir);
    if (!c.SDL_CreateDirectory(settings_dir)) return error.SaveDirectory;
    const rom_id = std.fmt.bytesToHex(identity.rom, .lower);
    const settings_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}.json", .{ settings_dir, rom_id }, 0);
    defer allocator.free(settings_path);
    menu.settings = try settings_io.read(allocator, settings_path);
    var av: c.struct_retro_system_av_info = undefined;
    core.get_system_av_info(&av);
    if (av.timing.fps < 1 or av.timing.fps > 240 or av.timing.sample_rate < 8000 or av.timing.sample_rate > 192000) return error.InvalidCoreTiming;
    ctx.sample_rate = av.timing.sample_rate;
    if (av.geometry.aspect_ratio > 0) ctx.aspect = av.geometry.aspect_ratio;
    const spec = c.SDL_AudioSpec{ .format = c.SDL_AUDIO_S16, .channels = 2, .freq = @intFromFloat(av.timing.sample_rate) };
    ctx.stream = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, null, null) orelse return error.AudioDevice;
    defer c.SDL_DestroyAudioStream(ctx.stream);
    if (!c.SDL_ResumeAudioStreamDevice(ctx.stream)) return error.AudioDevice;
    var count: c_int = 0;
    const ids = c.SDL_GetGamepads(&count);
    if (ids != null) {
        defer c.SDL_free(ids);
        for (0..@intCast(count)) |i| addPad(ids[i]);
    }
    const duration: u64 = @intFromFloat(1_000_000_000.0 / av.timing.fps);
    var deadline = c.SDL_GetTicksNS();
    var last_save = c.SDL_GetTicks();
    var frames: usize = 0;
    var fullscreen = frame_limit == 0;
    var running = true;
    var failed_save = false;
    const pause_check = c.SDL_getenv("ORBIT_PAUSE_SCREENSHOT");
    var pause_check_queued = false;
    var pause_check_ticks: usize = 0;
    var pause_audio: usize = 0;
    while (running and !ctx.shutdown) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) switch (event.type) {
            c.SDL_EVENT_QUIT => running = false,
            c.SDL_EVENT_KEY_DOWN => {
                if (event.key.repeat) continue;
                if (event.key.key == c.SDLK_ESCAPE) {
                    pause(&ctx, &menu, !ctx.paused);
                    deadline = c.SDL_GetTicksNS();
                } else if (ctx.paused) {
                    switch (event.key.key) {
                        c.SDLK_LEFT, c.SDLK_UP => menu.selected = (menu.selected + 3) % 4,
                        c.SDLK_RIGHT, c.SDLK_DOWN, c.SDLK_TAB => menu.selected = (menu.selected + 1) % 4,
                        c.SDLK_RETURN, c.SDLK_SPACE => {
                            switch (menu.selected) {
                                0 => pause(&ctx, &menu, false),
                                1 => running = false,
                                2 => toggleSetting(&menu, .toggle_scanlines, settings_path),
                                3 => toggleSetting(&menu, .toggle_stretch, settings_path),
                                else => {},
                            }
                            deadline = c.SDL_GetTicksNS();
                        },
                        else => {},
                    }
                }
                if (event.key.key == c.SDLK_F11 and !event.key.repeat) {
                    fullscreen = !fullscreen;
                    _ = c.SDL_SetWindowFullscreen(window, fullscreen);
                }
            },
            c.SDL_EVENT_WINDOW_FOCUS_LOST => {
                if (frame_limit == 0) {
                    ctx.focused = false;
                    _ = c.SDL_PauseAudioStreamDevice(ctx.stream);
                    _ = c.SDL_ClearAudioStream(ctx.stream);
                }
            },
            c.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                ctx.focused = true;
                deadline = c.SDL_GetTicksNS();
                if (!ctx.paused) _ = c.SDL_ResumeAudioStreamDevice(ctx.stream);
            },
            c.SDL_EVENT_MOUSE_MOTION, c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (ctx.paused) {
                    var x: f32 = 0;
                    var y: f32 = 0;
                    const mx = if (event.type == c.SDL_EVENT_MOUSE_MOTION) event.motion.x else event.button.x;
                    const my = if (event.type == c.SDL_EVENT_MOUSE_MOTION) event.motion.y else event.button.y;
                    _ = c.SDL_RenderCoordinatesFromWindow(renderer, mx, my, &x, &y);
                    const action = menu.hit(x, y);
                    if (action != .none) menu.selected = @intFromEnum(action) - 1;
                    if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_LEFT) {
                        toggleSetting(&menu, action, settings_path);
                        if (action == .return_to_library) running = false;
                        if (action == .resume_game) {
                            pause(&ctx, &menu, false);
                            deadline = c.SDL_GetTicksNS();
                        }
                    }
                }
            },
            c.SDL_EVENT_GAMEPAD_ADDED => addPad(event.gdevice.which),
            c.SDL_EVENT_GAMEPAD_REMOVED => {
                for (&ctx.pads) |*pad| {
                    if (pad.*) |p| if (c.SDL_GetGamepadID(p) == event.gdevice.which) {
                        c.SDL_CloseGamepad(p);
                        pad.* = null;
                    };
                }
            },
            else => {},
        };
        if (!running) break;
        if (!ctx.focused) {
            c.SDL_Delay(20);
            continue;
        }
        if (!ctx.paused) {
            core.run();
            frames += 1;
        }
        if (ctx.failed) return error.EmulationOutput;
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);
        if (ctx.texture) |texture| {
            var w: c_int = 0;
            var h: c_int = 0;
            _ = c.SDL_GetRenderOutputSize(renderer, &w, &h);
            const dw = if (menu.settings.fullscreen_stretch) @as(f32, @floatFromInt(w)) else @min(@as(f32, @floatFromInt(w)), @as(f32, @floatFromInt(h)) * ctx.aspect);
            const dh = if (menu.settings.fullscreen_stretch) @as(f32, @floatFromInt(h)) else dw / ctx.aspect;
            const dst = c.SDL_FRect{ .x = (@as(f32, @floatFromInt(w)) - dw) / 2, .y = (@as(f32, @floatFromInt(h)) - dh) / 2, .w = dw, .h = dh };
            _ = c.SDL_RenderTexture(renderer, texture, null, &dst);
            if (menu.settings.crt_scanlines) {
                _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
                _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 85);
                const spacing = @max(2, @round(dh / @as(f32, @floatFromInt(ctx.th))));
                const thickness = @max(1, @floor(spacing * 0.25));
                var y = dst.y + spacing - thickness;
                while (y < dst.y + dh) : (y += spacing) {
                    const band = c.SDL_FRect{ .x = dst.x, .y = y, .w = dw, .h = @min(thickness, dst.y + dh - y) };
                    _ = c.SDL_RenderFillRect(renderer, &band);
                }
                _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_NONE);
            }
        }
        if (ctx.paused) menu.draw();
        if (pause_check != null and frames == 60 and !pause_check_queued) {
            pause_check_queued = true;
            pause_audio = ctx.audio_frames;
            var key: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
            key.type = c.SDL_EVENT_KEY_DOWN;
            key.key.key = c.SDLK_ESCAPE;
            if (!c.SDL_PushEvent(&key)) return error.PauseCheck;
        }
        if (pause_check != null and ctx.paused) {
            pause_check_ticks += 1;
            if (c.SDL_getenv("ORBIT_SETTINGS_CHECK") != null and (pause_check_ticks == 1 or pause_check_ticks == 2)) {
                var click: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
                click.type = c.SDL_EVENT_MOUSE_BUTTON_DOWN;
                click.button.button = c.SDL_BUTTON_LEFT;
                const x: f32 = if (pause_check_ticks == 1) 740 else 995;
                _ = c.SDL_RenderCoordinatesToWindow(renderer, (menu.ox + x) * menu.scale, (menu.oy + 115) * menu.scale, &click.button.x, &click.button.y);
                if (!c.SDL_PushEvent(&click)) return error.PauseCheck;
            }
            if (frames != 60 or ctx.audio_frames != pause_audio) return error.PauseCheck;
            if (pause_check_ticks == 4) {
                const surface = c.SDL_RenderReadPixels(renderer, null) orelse return error.ScreenshotRead;
                defer c.SDL_DestroySurface(surface);
                if (!c.SDL_SaveBMP(surface, pause_check)) return error.ScreenshotSave;
                var action: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
                if (c.SDL_getenv("ORBIT_PAUSE_RETURN") != null) {
                    action.type = c.SDL_EVENT_MOUSE_BUTTON_DOWN;
                    action.button.button = c.SDL_BUTTON_LEFT;
                    _ = c.SDL_RenderCoordinatesToWindow(renderer, (menu.ox + 1000) * menu.scale, (menu.oy + 724) * menu.scale, &action.button.x, &action.button.y);
                } else {
                    action.type = c.SDL_EVENT_KEY_DOWN;
                    action.key.key = c.SDLK_ESCAPE;
                }
                if (!c.SDL_PushEvent(&action)) return error.PauseCheck;
                c.SDL_Log("Pause overlay froze core and audio; action queued");
            }
        }
        if (frame_limit > 0 and frames >= frame_limit) {
            if (c.SDL_getenv("ORBIT_HOST_SCREENSHOT")) |output| {
                const surface = c.SDL_RenderReadPixels(renderer, null) orelse return error.ScreenshotRead;
                defer c.SDL_DestroySurface(surface);
                if (!c.SDL_SaveBMP(surface, output)) return error.ScreenshotSave;
            }
            running = false;
        }
        _ = c.SDL_RenderPresent(renderer);
        if (c.SDL_GetTicks() - last_save >= 2000) {
            persist(core, save_path, c.RETRO_MEMORY_SAVE_RAM) catch {
                failed_save = true;
            };
            persist(core, rtc_path, c.RETRO_MEMORY_RTC) catch {
                failed_save = true;
            };
            last_save = c.SDL_GetTicks();
        }
        if (ctx.paused) {
            deadline = c.SDL_GetTicksNS();
            c.SDL_Delay(16);
        } else if (frame_limit == 0) {
            deadline += duration;
            const now = c.SDL_GetTicksNS();
            if (deadline > now) c.SDL_DelayNS(deadline - now) else if (now - deadline > duration * 3) deadline = now;
        } else _ = c.SDL_ClearAudioStream(ctx.stream);
    }
    const state_result = saveState(allocator, core, state_path, identity);
    const battery_result = persist(core, save_path, c.RETRO_MEMORY_SAVE_RAM);
    const rtc_result = persist(core, rtc_path, c.RETRO_MEMORY_RTC);
    try state_result;
    try battery_result;
    try rtc_result;
    if (failed_save) return error.AutosaveFailed;
    if (ctx.video_frames == 0) return error.NoVideoFrames;
    c.SDL_Log("SRAM bytes: %zu", core.get_memory_size(c.RETRO_MEMORY_SAVE_RAM));
    c.SDL_Log("Session finished: %zu frames, %zu video frames, %zu audio frames", frames, ctx.video_frames, ctx.audio_frames);
}

test "virtual controller maps SNES buttons and keeps ports independent" {
    try std.testing.expect(c.SDL_Init(c.SDL_INIT_GAMEPAD));
    defer c.SDL_Quit();
    var ctx = Context{ .renderer = undefined, .system_dir = "", .save_dir = "" };
    active = &ctx;
    var desc = std.mem.zeroes(c.SDL_VirtualJoystickDesc);
    desc.version = @sizeOf(c.SDL_VirtualJoystickDesc);
    desc.type = c.SDL_JOYSTICK_TYPE_GAMEPAD;
    desc.nbuttons = c.SDL_GAMEPAD_BUTTON_COUNT;
    desc.button_mask = (1 << c.SDL_GAMEPAD_BUTTON_COUNT) - 1;
    desc.naxes = c.SDL_GAMEPAD_AXIS_COUNT;
    desc.axis_mask = (1 << c.SDL_GAMEPAD_AXIS_COUNT) - 1;
    desc.name = "Ember test controller";
    const id = c.SDL_AttachVirtualJoystick(&desc);
    try std.testing.expect(id != 0);
    defer _ = c.SDL_DetachVirtualJoystick(id);
    addPad(id);
    defer for (ctx.pads) |pad| {
        if (pad) |p| c.SDL_CloseGamepad(p);
    };
    try std.testing.expect(ctx.pads[0] != null);
    addPad(id);
    try std.testing.expect(ctx.pads[1] == null);
    const joystick = c.SDL_GetGamepadJoystick(ctx.pads[0]);
    try std.testing.expect(c.SDL_SetJoystickVirtualButton(joystick, c.SDL_GAMEPAD_BUTTON_SOUTH, true));
    c.SDL_UpdateGamepads();
    try std.testing.expectEqual(@as(i16, 1), inputState(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_B));
    try std.testing.expectEqual(@as(i16, 0), inputState(1, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_B));
    try std.testing.expect(c.SDL_SetJoystickVirtualButton(joystick, c.SDL_GAMEPAD_BUTTON_SOUTH, false));
    c.SDL_UpdateGamepads();
    try std.testing.expectEqual(@as(i16, 0), inputState(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_B));
    try std.testing.expect(c.SDL_SetJoystickVirtualAxis(joystick, c.SDL_GAMEPAD_AXIS_LEFTX, -20000));
    c.SDL_UpdateGamepads();
    try std.testing.expectEqual(@as(i16, 1), inputState(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_LEFT));
    ctx.focused = false;
    try std.testing.expectEqual(@as(i16, 0), inputState(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_LEFT));
}

test "core environment negotiates video formats and option defaults" {
    var ctx = Context{ .renderer = undefined, .system_dir = "system", .save_dir = "saves" };
    active = &ctx;
    var format: c_uint = c.RETRO_PIXEL_FORMAT_RGB565;
    try std.testing.expect(environment(c.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &format));
    try std.testing.expectEqual(format, ctx.pixel_format);
    format = 999;
    try std.testing.expect(!environment(c.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &format));
    const options = [_]c.struct_retro_variable{ .{ .key = "region", .value = "Region; auto|ntsc|pal" }, .{ .key = null, .value = null } };
    try std.testing.expect(environment(c.RETRO_ENVIRONMENT_SET_VARIABLES, @ptrCast(@constCast(&options))));
    var variable = c.struct_retro_variable{ .key = "region", .value = null };
    try std.testing.expect(environment(c.RETRO_ENVIRONMENT_GET_VARIABLE, &variable));
    try std.testing.expectEqualStrings("auto", std.mem.span(variable.value));
    variable.key = "missing";
    try std.testing.expect(!environment(c.RETRO_ENVIRONMENT_GET_VARIABLE, &variable));
    try std.testing.expect(variable.value == null);
}
