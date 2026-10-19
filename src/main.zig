const std = @import("std");
const s = @import("api.zig").c;
const retro = @import("retro.zig");
const RGB = [3]u8;
const white: RGB = .{ 240, 238, 235 };
const muted: RGB = .{ 154, 151, 147 };
const accent: RGB = .{ 255, 138, 56 };
const Game = struct { title: [:0]const u8, platform: [:0]const u8, file: [:0]const u8, rom_path: [:0]const u8 };
const games = [_]Game{
    .{ .title = "Chrono Trigger", .platform = "Super Nintendo  /  1995", .file = "snes/chrono-trigger.png", .rom_path = "roms/snes/Chrono Trigger (USA).sfc" },
    .{ .title = "Super Metroid", .platform = "Super Nintendo  /  1994", .file = "snes/super-metroid.png", .rom_path = "roms/snes/Super Metroid (Japan, USA) (En,Ja).sfc" },
    .{ .title = "Super Mario World", .platform = "Super Nintendo  /  1990", .file = "snes/super-mario-world.png", .rom_path = "roms/snes/Super Mario World (USA).sfc" },
    .{ .title = "A Link to the Past", .platform = "Super Nintendo  /  1991", .file = "snes/a-link-to-the-past.png", .rom_path = "roms/snes/Legend of Zelda, The - A Link to the Past (USA).sfc" },
    .{ .title = "Final Fantasy VI", .platform = "Super Nintendo  /  1994", .file = "snes/final-fantasy-vi.png", .rom_path = "roms/snes/Final Fantasy III (USA).sfc" },
    .{ .title = "EarthBound", .platform = "Super Nintendo  /  1994", .file = "snes/earthbound.png", .rom_path = "roms/snes/EarthBound (USA).sfc" },
    .{ .title = "Donkey Kong Country 2", .platform = "Super Nintendo  /  1995", .file = "snes/donkey-kong-country-2.png", .rom_path = "roms/snes/Donkey Kong Country 2 - Diddy's Kong Quest (USA) (En,Fr).sfc" },
    .{ .title = "Mega Man X", .platform = "Super Nintendo  /  1993", .file = "snes/mega-man-x.png", .rom_path = "roms/snes/Mega Man X (USA).sfc" },
    .{ .title = "Yoshi's Island", .platform = "Super Nintendo  /  1995", .file = "snes/yoshis-island.png", .rom_path = "roms/snes/Super Mario World 2 - Yoshi's Island (USA).sfc" },
    .{ .title = "Super Mario RPG", .platform = "Super Nintendo  /  1996", .file = "snes/super-mario-rpg.png", .rom_path = "roms/snes/Super Mario RPG - Legend of the Seven Stars (USA).sfc" },
};
var renderer: *s.SDL_Renderer = undefined;
var fonts: [5]*s.TTF_Font = undefined;
const sizes = [_]f32{ 13, 15, 18, 24, 36 };
const Label = struct { value: [:0]const u8, size: usize, rgb: RGB, texture: *s.SDL_Texture, w: f32, h: f32 };
var labels: [160]Label = undefined;
var label_count: usize = 0;
fn rect(x: f32, y: f32, w: f32, h: f32, rgb: RGB) void {
    _ = s.SDL_SetRenderDrawColor(renderer, rgb[0], rgb[1], rgb[2], 255);
    const r = s.SDL_FRect{ .x = x, .y = y, .w = w, .h = h };
    _ = s.SDL_RenderFillRect(renderer, &r);
}
fn rounded(x: f32, y: f32, w: f32, h: f32, radius: f32, rgb: RGB) void {
    rect(x + radius, y, w - radius * 2, h, rgb);
    rect(x, y + radius, w, h - radius * 2, rgb);
    var yy: f32 = 0;
    while (yy < radius) : (yy += 1) {
        const inset = radius - @sqrt(@max(0, radius * radius - (radius - yy - 0.5) * (radius - yy - 0.5)));
        rect(x + inset, y + yy, w - inset * 2, 1, rgb);
        rect(x + inset, y + h - yy - 1, w - inset * 2, 1, rgb);
    }
}
fn text(x: f32, y: f32, size: usize, value: [:0]const u8, rgb: RGB) void {
    if (value.len == 0) return;
    var label: ?Label = null;
    for (labels[0..label_count]) |entry| {
        if (entry.size == size and std.mem.eql(u8, entry.value, value) and std.mem.eql(u8, &entry.rgb, &rgb)) {
            label = entry;
            break;
        }
    }
    if (label == null) {
        if (label_count == labels.len) return;
        const surface = s.TTF_RenderText_Blended(fonts[size], value, value.len, .{ .r = rgb[0], .g = rgb[1], .b = rgb[2], .a = 255 }) orelse return;
        defer s.SDL_DestroySurface(surface);
        const texture = s.SDL_CreateTextureFromSurface(renderer, surface) orelse return;
        label = .{ .value = value, .size = size, .rgb = rgb, .texture = texture, .w = @floatFromInt(surface.*.w), .h = @floatFromInt(surface.*.h) };
        labels[label_count] = label.?;
        label_count += 1;
    }
    const l = label.?;
    const dest = s.SDL_FRect{ .x = x, .y = y, .w = l.w, .h = l.h };
    _ = s.SDL_RenderTexture(renderer, l.texture, null, &dest);
}
fn art(texture: *s.SDL_Texture, x: f32, y: f32, w: f32, h: f32) void {
    var tw: f32 = 0;
    var th: f32 = 0;
    _ = s.SDL_GetTextureSize(texture, &tw, &th);
    // Preserve the portrait artwork aspect ratio at every window size.
    const scale = @min(w / tw, h / th);
    const dst = s.SDL_FRect{ .x = x + (w - tw * scale) / 2, .y = y + (h - th * scale) / 2, .w = tw * scale, .h = th * scale };
    _ = s.SDL_RenderTexture(renderer, texture, null, &dst);
}
fn hit(x: f32, y: f32, rx: f32, ry: f32, w: f32, h: f32) bool {
    return x >= rx and x <= rx + w and y >= ry and y <= ry + h;
}
const Layout = struct {
    width: f32,
    height: f32,
    columns: usize,
    card_width: f32,
    card_height: f32,
    scroll: f32 = 0,
    fn init(width: f32, height: f32) Layout {
        const available = width - 272;
        const columns: usize = @max(1, @min(games.len, @as(usize, @intFromFloat(@max(1, @floor((available + 24) / 232))))));
        return .{ .width = width, .height = height, .columns = columns, .card_width = 208, .card_height = 312 };
    }
    fn x(self: Layout, i: usize) f32 {
        return 232 + @as(f32, @floatFromInt(i % self.columns)) * (self.card_width + 24);
    }
    fn y(self: Layout, i: usize) f32 {
        return 206 + @as(f32, @floatFromInt(i / self.columns)) * (self.card_height + 60) - self.scroll;
    }
    fn maxScroll(self: Layout) f32 {
        const rows = (games.len + self.columns - 1) / self.columns;
        return @max(0, @as(f32, @floatFromInt(rows)) * (self.card_height + 60) - 10 - (self.height - 330));
    }
    fn reveal(self: *Layout, i: usize) void {
        const top = self.y(i);
        const bottom = top + self.card_height + 50;
        if (top < 206) self.scroll -= 206 - top;
        if (bottom > self.height - 124) self.scroll += bottom - (self.height - 124);
        self.scroll = std.math.clamp(self.scroll, 0, self.maxScroll());
    }
    fn cardAt(self: Layout, px: f32, py: f32) ?usize {
        if (py < 202 or py >= self.height - 124) return null;
        for (0..games.len) |i| {
            if (hit(px, py, self.x(i), self.y(i), self.card_width, self.card_height + 50)) return i;
        }
        return null;
    }
};
fn initializeStorage(allocator: std.mem.Allocator, window: *s.SDL_Window) !bool {
    // Explicit overrides keep headless tools and developer workflows non-interactive.
    if (s.SDL_getenv("EMBER_SKIP_SETUP") != null or s.SDL_getenv("ORBIT_DATA_DIR") != null) return true;
    const storage = @import("storage.zig");
    const remembered = storage.load(allocator) catch null;
    var selected_path = remembered orelse blk: {
        const home = s.SDL_GetUserFolder(s.SDL_FOLDER_HOME) orelse return error.StorageHome;
        break :blk try std.fmt.allocPrintSentinel(allocator, "{s}{s}Ember", .{ std.mem.span(home), if (std.mem.endsWith(u8, std.mem.span(home), "/") or std.mem.endsWith(u8, std.mem.span(home), "\\")) "" else "/" }, 0);
    };
    if (remembered != null) {
        if (storage.initialize(allocator, selected_path)) |_| {
            try storage.activate(allocator, selected_path);
            return true;
        } else |_| {}
    }
    var focus: usize = 1;
    var pending = false;
    var quit = false;
    var picker = storage.Selection{};
    const setup_check = s.SDL_getenv("EMBER_SETUP_CHECK");
    if (setup_check) |directory| selected_path = try allocator.dupeZ(u8, std.mem.span(directory));
    var check_queued = false;
    var message: [:0]const u8 = "ROMs, saves, settings and system files will live here.";
    defer {
        for (labels[0..label_count]) |label| s.SDL_DestroyTexture(label.texture);
        label_count = 0;
    }
    while (true) {
        if (pending and picker.ready.load(.acquire)) {
            pending = false;
            if (picker.path) |chosen| {
                selected_path = try allocator.dupeZ(u8, std.mem.span(chosen));
                s.SDL_free(chosen);
                picker.path = null;
            }
            if (picker.failed) message = "The folder picker could not open. Try again or use the default.";
        }
        if (quit and !pending) return false;
        _ = s.SDL_SetRenderLogicalPresentation(renderer, 1000, 650, s.SDL_LOGICAL_PRESENTATION_LETTERBOX);
        var action: ?usize = null;
        var event: s.SDL_Event = undefined;
        while (s.SDL_PollEvent(&event)) {
            _ = s.SDL_ConvertEventToRenderCoordinates(renderer, &event);
            if (event.type == s.SDL_EVENT_QUIT) quit = true;
            if (pending) continue;
            if (event.type == s.SDL_EVENT_KEY_DOWN) {
                switch (event.key.key) {
                    s.SDLK_ESCAPE => quit = true,
                    s.SDLK_TAB, s.SDLK_LEFT, s.SDLK_RIGHT => focus = 1 - focus,
                    s.SDLK_RETURN, s.SDLK_SPACE => action = focus,
                    else => {},
                }
            }
            if (event.type == s.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == s.SDL_BUTTON_LEFT) {
                if (hit(event.button.x, event.button.y, 100, 410, 270, 60)) action = 0;
                if (hit(event.button.x, event.button.y, 390, 410, 300, 60)) action = 1;
            }
        }
        if (action) |choice| {
            focus = choice;
            if (choice == 0) {
                picker = .{};
                pending = true;
                s.SDL_ShowOpenFolderDialog(storage.Selection.callback, &picker, window, selected_path, false);
            } else {
                if (storage.initialize(allocator, selected_path)) |_| {
                    if (storage.remember(allocator, selected_path)) |_| {
                        try storage.activate(allocator, selected_path);
                        return true;
                    } else |_| {
                        message = "Could not remember this location. Check your app configuration access.";
                    }
                } else |_| {
                    message = "Cannot write to this folder. Choose an accessible location.";
                }
            }
        }
        _ = s.SDL_SetRenderDrawColor(renderer, 20, 21, 23, 255);
        _ = s.SDL_RenderClear(renderer);
        text(100, 100, 0, "WELCOME TO EMBER", accent);
        text(100, 145, 4, "A home for your games", white);
        text(100, 220, 1, "Choose where to initialize your Ember directory.", muted);
        rect(100, 280, 800, 72, .{ 39, 40, 43 });
        const clip = s.SDL_Rect{ .x = 115, .y = 280, .w = 770, .h = 72 };
        _ = s.SDL_SetRenderClipRect(renderer, &clip);
        text(120, 302, 1, selected_path, white);
        _ = s.SDL_SetRenderClipRect(renderer, null);
        text(100, 370, 0, message, muted);
        rect(100, 410, 270, 60, if (focus == 0) accent else .{ 50, 51, 54 });
        text(125, 427, 1, if (pending) "Choosing folder..." else "Choose another folder", if (focus == 0) .{ 20, 20, 20 } else white);
        rect(390, 410, 300, 60, if (focus == 1) accent else .{ 50, 51, 54 });
        text(420, 427, 1, "Initialize Ember", if (focus == 1) .{ 20, 20, 20 } else white);
        text(100, 520, 0, "Existing files are kept. Game files are supplied separately.", muted);
        if (setup_check != null and !check_queued) {
            if (s.SDL_getenv("EMBER_SETUP_SCREENSHOT")) |output| {
                const surface = s.SDL_RenderReadPixels(renderer, null) orelse return error.ScreenshotRead;
                defer s.SDL_DestroySurface(surface);
                if (!s.SDL_SaveBMP(surface, output)) return error.ScreenshotSave;
            }
            var enter: s.SDL_Event = std.mem.zeroes(s.SDL_Event);
            enter.type = s.SDL_EVENT_KEY_DOWN;
            enter.key.key = s.SDLK_RETURN;
            if (!s.SDL_PushEvent(&enter)) return error.SetupCheckEvent;
            check_queued = true;
        }
        _ = s.SDL_RenderPresent(renderer);
        s.SDL_Delay(16);
    }
}
fn launchGame(allocator: std.mem.Allocator, base: [*:0]const u8, game: Game) !*s.SDL_Process {
    const windows = @import("builtin").os.tag == .windows;
    const executable = try std.fmt.allocPrintSentinel(allocator, "{s}ember{s}", .{ std.mem.span(base), if (windows) ".exe" else "" }, 0);
    defer allocator.free(executable);
    const core = if (s.SDL_getenv("ORBIT_CORE_PATH")) |override| try allocator.dupeZ(u8, std.mem.span(override)) else try std.fmt.allocPrintSentinel(allocator, "{s}cores/snes9x_libretro.{s}", .{ std.mem.span(base), if (windows) "dll" else "so" }, 0);
    defer allocator.free(core);
    var info: s.SDL_PathInfo = undefined;
    if (!s.SDL_GetPathInfo(core, &info)) return error.CoreMissing;
    const rom_dir = s.SDL_getenv("EMBER_ROM_DIR");
    var rom = if (rom_dir) |directory|
        try std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ std.mem.span(directory), game.rom_path["roms/".len..] }, 0)
    else
        try std.fmt.allocPrintSentinel(allocator, "{s}{s}", .{ std.mem.span(base), game.rom_path }, 0);
    if (rom_dir == null and !s.SDL_GetPathInfo(rom, &info)) {
        allocator.free(rom);
        rom = try std.fmt.allocPrintSentinel(allocator, "{s}../../{s}", .{ std.mem.span(base), game.rom_path }, 0);
    }
    defer allocator.free(rom);
    if (!s.SDL_GetPathInfo(rom, &info)) return error.ROMMissing;
    const args = [_:null]?[*:0]const u8{ executable.ptr, "--host", core.ptr, rom.ptr, game.title.ptr };
    return s.SDL_CreateProcess(@ptrCast(&args), false) orelse error.ProcessCreation;
}
fn sessionError(code: c_int) [:0]const u8 {
    return switch (code) {
        2 => "The SNES core could not be loaded.",
        3 => "The ROM could not be opened by the core.",
        4 => "Game saves could not be written. Check folder access.",
        5 => "The audio device could not be opened.",
        7 => "The resume state is incompatible or damaged.",
        9 => "The game display settings could not be loaded.",
        8 => "The core could not create an automatic resume state.",
        else => "The game session ended unexpectedly.",
    };
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 1 and std.mem.eql(u8, args[1], "--host")) {
        if (args.len != 5) return error.InvalidHostArguments;
        retro.run(init.gpa, args[2], args[3], args[4]) catch |err| {
            s.SDL_Log("Game session failed: %s (%s)", @errorName(err).ptr, s.SDL_GetError());
            std.process.exit(switch (err) {
                error.CoreNotFound, error.MissingCoreSymbol, error.UnsupportedCoreAPI => 2,
                error.ROMNotFound, error.CoreRejectedROM => 3,
                error.SaveFailed, error.AutosaveFailed, error.SaveDirectory => 4,
                error.AudioDevice => 5,
                error.GameSettingsRead => 9,
                error.ResumeStateInvalid, error.ResumeStateRead, error.ResumeStateMismatch, error.ResumeStateRejected => 7,
                error.ResumeStateUnsupported, error.ResumeStateSave => 8,
                else => 6,
            });
        };
        return;
    }
    @import("brand.zig").configure();
    if (!s.SDL_Init(s.SDL_INIT_VIDEO)) return error.SDLInitialization;
    defer s.SDL_Quit();
    if (!s.TTF_Init()) return error.FontInitialization;
    defer s.TTF_Quit();
    const window = s.SDL_CreateWindow("Ember - Your games, together", 1440, 1000, s.SDL_WINDOW_RESIZABLE | s.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse return error.WindowCreation;
    defer s.SDL_DestroyWindow(window);
    try @import("brand.zig").setWindowIcon(window);
    if (s.SDL_getenv("ORBIT_WINDOW_SIZE")) |value| {
        var parts = std.mem.splitScalar(u8, std.mem.span(value), 'x');
        const w = try std.fmt.parseInt(c_int, parts.next() orelse return error.InvalidSize, 10);
        const h = try std.fmt.parseInt(c_int, parts.next() orelse return error.InvalidSize, 10);
        _ = s.SDL_SetWindowSize(window, @max(800, w), @max(600, h));
    }
    renderer = s.SDL_CreateRenderer(window, null) orelse return error.RendererCreation;
    defer s.SDL_DestroyRenderer(renderer);
    _ = s.SDL_SetWindowMinimumSize(window, 800, 600);
    _ = s.SDL_SetRenderVSync(renderer, 1);
    // SDL base path makes packaged assets independent of the working directory.
    const base = s.SDL_GetBasePath();
    var path: [4096]u8 = undefined;
    const flame_path = try std.fmt.bufPrintZ(&path, "{s}assets/brand/flame.svg", .{std.mem.span(base)});
    const flame = s.IMG_LoadTexture(renderer, flame_path) orelse return error.BrandImageMissing;
    defer s.SDL_DestroyTexture(flame);
    _ = s.SDL_SetTextureScaleMode(flame, s.SDL_SCALEMODE_LINEAR);
    for (sizes, 0..) |size, i| {
        const font_path = try std.fmt.bufPrintZ(&path, "{s}assets/fonts/OpenSans-{s}.ttf", .{ std.mem.span(base), if (i >= 2) "Semibold" else "Regular" });
        fonts[i] = s.TTF_OpenFont(font_path, size) orelse return error.FontMissing;
    }
    defer for (fonts) |font| s.TTF_CloseFont(font);
    defer for (labels[0..label_count]) |label| s.SDL_DestroyTexture(label.texture);
    if (!try initializeStorage(init.arena.allocator(), window)) return;
    var covers: [games.len]*s.SDL_Texture = undefined;
    var loaded: usize = 0;
    defer for (covers[0..loaded]) |texture| s.SDL_DestroyTexture(texture);
    for (games, 0..) |game, i| {
        const cover_path = try std.fmt.bufPrintZ(&path, "{s}assets/covers/{s}", .{ std.mem.span(base), game.file });
        covers[i] = s.IMG_LoadTexture(renderer, cover_path) orelse {
            s.SDL_Log("Missing artwork: %s (%s)", cover_path.ptr, s.SDL_GetError());
            return error.ArtworkMissing;
        };
        loaded += 1;
    }
    const launch_check = s.SDL_getenv("ORBIT_LAUNCH_CHECK");
    var selected: usize = if (launch_check != null) try std.fmt.parseInt(usize, std.mem.span(launch_check), 10) else 0;
    if (selected >= games.len) return error.InvalidGameIndex;
    var check_queued = false;
    var check_finished = false;
    var hovered: ?usize = null;
    var running = true;
    var notice = false;
    var notice_message: [:0]const u8 = "";
    var launch_requested = false;
    var session: ?*s.SDL_Process = null;
    defer if (session) |process| s.SDL_DestroyProcess(process);
    const screenshot = s.SDL_getenv("ORBIT_SCREENSHOT");
    var initial_w: c_int = 0;
    var initial_h: c_int = 0;
    _ = s.SDL_GetWindowSize(window, &initial_w, &initial_h);
    _ = s.SDL_SetRenderLogicalPresentation(renderer, initial_w, initial_h, s.SDL_LOGICAL_PRESENTATION_STRETCH);
    var layout = Layout.init(@floatFromInt(initial_w), @floatFromInt(initial_h));
    while (running) {
        if (session) |process| {
            s.SDL_PumpEvents();
            var exitcode: c_int = 0;
            if (!s.SDL_WaitProcess(process, false, &exitcode)) {
                s.SDL_Delay(20);
                continue;
            }
            s.SDL_DestroyProcess(process);
            session = null;
            if (launch_check != null) {
                if (exitcode != 0) return error.LaunchCheckFailed;
                check_finished = true;
            }
            _ = s.SDL_ShowWindow(window);
            _ = s.SDL_RaiseWindow(window);
            if (exitcode != 0) {
                notice_message = sessionError(exitcode);
                notice = true;
            }
            // Discard keys and clicks left over from the game handoff.
            s.SDL_PumpEvents();
            s.SDL_FlushEvents(s.SDL_EVENT_KEY_DOWN, s.SDL_EVENT_KEY_UP);
            s.SDL_FlushEvents(s.SDL_EVENT_MOUSE_BUTTON_DOWN, s.SDL_EVENT_MOUSE_BUTTON_UP);
        }
        var event: s.SDL_Event = undefined;
        while (s.SDL_PollEvent(&event)) {
            var ww: c_int = 0;
            var wh: c_int = 0;
            _ = s.SDL_GetWindowSize(window, &ww, &wh);
            if (ww > 0 and wh > 0) {
                _ = s.SDL_SetRenderLogicalPresentation(renderer, ww, wh, s.SDL_LOGICAL_PRESENTATION_STRETCH);
                if (layout.width != @as(f32, @floatFromInt(ww)) or layout.height != @as(f32, @floatFromInt(wh))) {
                    layout = Layout.init(@floatFromInt(ww), @floatFromInt(wh));
                    layout.reveal(selected);
                    hovered = null;
                }
            }
            _ = s.SDL_ConvertEventToRenderCoordinates(renderer, &event);
            switch (event.type) {
                s.SDL_EVENT_QUIT => running = false,
                s.SDL_EVENT_KEY_DOWN => {
                    if (notice) {
                        if (event.key.key == s.SDLK_ESCAPE or event.key.key == s.SDLK_RETURN) notice = false;
                        continue;
                    }
                    switch (event.key.key) {
                        s.SDLK_ESCAPE => running = false,
                        s.SDLK_RIGHT, s.SDLK_D => selected = (selected + 1) % games.len,
                        s.SDLK_TAB => selected = if (event.key.mod & s.SDL_KMOD_SHIFT != 0) (selected + games.len - 1) % games.len else (selected + 1) % games.len,
                        s.SDLK_LEFT, s.SDLK_A => selected = (selected + games.len - 1) % games.len,
                        s.SDLK_UP, s.SDLK_W => selected = if (selected >= layout.columns) selected - layout.columns else selected,
                        s.SDLK_DOWN, s.SDLK_S => selected = @min(selected + layout.columns, games.len - 1),
                        s.SDLK_HOME => selected = 0,
                        s.SDLK_END => selected = games.len - 1,
                        s.SDLK_RETURN, s.SDLK_SPACE => {
                            if (!event.key.repeat) launch_requested = true;
                        },
                        else => {},
                    }
                    layout.reveal(selected);
                },
                s.SDL_EVENT_MOUSE_WHEEL => {
                    if (!notice) {
                        layout.scroll = std.math.clamp(layout.scroll - event.wheel.y * 80, 0, layout.maxScroll());
                        hovered = null;
                    }
                },
                s.SDL_EVENT_MOUSE_MOTION => {
                    hovered = if (notice) null else layout.cardAt(event.motion.x, event.motion.y);
                },
                s.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.button != s.SDL_BUTTON_LEFT) continue;
                    const x = event.button.x;
                    const y = event.button.y;
                    if (notice) {
                        if (hit(x, y, (layout.width - 320) / 2, (layout.height - 270) / 2 + 191, 320, 44)) notice = false;
                        continue;
                    }
                    if (layout.cardAt(x, y)) |i| {
                        selected = i;
                        launch_requested = event.button.clicks >= 2;
                    }
                    if (hit(x, y, layout.width - 248, layout.height - 90, 168, 48)) launch_requested = true;
                },
                else => {},
            }
        }
        if (launch_requested) {
            launch_requested = false;
            session = launchGame(init.gpa, @ptrCast(base), games[selected]) catch |err| blk: {
                notice_message = switch (err) {
                    error.CoreMissing => "The bundled SNES core is missing.",
                    error.ROMMissing => "This game's ROM file could not be found.",
                    else => "The game process could not be started.",
                };
                notice = true;
                break :blk null;
            };
            if (launch_check != null and session == null) return error.LaunchCheckFailed;
            if (session != null) {
                _ = s.SDL_HideWindow(window);
                continue;
            }
        }
        rect(0, 0, layout.width, layout.height, .{ 18, 18, 18 });
        rect(0, 0, 192, layout.height, .{ 24, 24, 24 });
        const flame_rect = s.SDL_FRect{ .x = 26, .y = 26, .w = 32, .h = 40 };
        _ = s.SDL_RenderTexture(renderer, flame, null, &flame_rect);
        text(68, 29, 3, "ember", white);
        text(28, 104, 0, "YOUR SPACE", muted);
        rounded(16, 138, 160, 44, 10, .{ 55, 37, 25 });
        text(32, 149, 1, "Library", .{ 255, 183, 128 });
        text(28, 218, 0, "ONE COLLECTION", muted);
        text(28, 250, 1, "Native", muted);
        text(28, 283, 1, "Proton", muted);
        text(28, 316, 1, "Emulated", muted);
        rect(28, layout.height - 105, 136, 1, .{ 48, 48, 48 });
        text(28, layout.height - 84, 0, "LOCAL LIBRARY", white);
        text(28, layout.height - 59, 0, "SNES collection", muted);
        text(232, 32, 0, "LIBRARY  /  COLLECTIONS", muted);
        rounded(layout.width - 232, 30, 168, 30, 15, .{ 35, 35, 35 });
        text(layout.width - 212, 36, 0, "10 games", muted);
        text(232, 77, 4, "Super Nintendo", white);
        text(233, 130, 1, "A collection of classics. Yours to rediscover.", muted);
        text(233, 176, 0, "ALL GAMES", accent);
        text(layout.width - 267, 176, 0, "SNES  /  10 GAMES", muted);
        const clip = s.SDL_Rect{ .x = 224, .y = 202, .w = @intFromFloat(layout.width - 256), .h = @intFromFloat(layout.height - 326) };
        _ = s.SDL_SetRenderClipRect(renderer, &clip);
        for (games, 0..) |game, i| {
            const x = layout.x(i);
            const y = layout.y(i);
            const cw = layout.card_width;
            const ch = layout.card_height;
            if (y + ch + 50 < 202 or y > layout.height - 124) continue;
            if (i == selected) rounded(x - 4, y - 4, cw + 8, ch + 8, 9, accent) else if (hovered == i) rounded(x - 4, y - 4, cw + 8, ch + 8, 9, .{ 103, 99, 94 });
            rounded(x, y, cw, ch, 6, .{ 30, 30, 30 });
            art(covers[i], x, y, cw, ch);
            text(x, y + ch + 11, 1, game.title, if (i == selected) .{ 255, 183, 128 } else white);
            text(x, y + ch + 35, 0, game.platform, muted);
        }
        _ = s.SDL_SetRenderClipRect(renderer, null);
        if (layout.maxScroll() > 0) {
            const track = layout.height - 326;
            const thumb = @max(28, track * track / (track + layout.maxScroll()));
            rounded(layout.width - 20, 202, 4, track, 2, .{ 35, 35, 35 });
            rounded(layout.width - 20, 202 + layout.scroll / layout.maxScroll() * (track - thumb), 4, thumb, 2, .{ 151, 100, 64 });
        }
        rounded(224, layout.height - 105, layout.width - 280, 78, 14, .{ 32, 32, 32 });
        text(248, layout.height - 92, 2, games[selected].title, white);
        text(248, layout.height - 61, 0, games[selected].platform, muted);
        if (layout.width >= 1280) text(layout.width - 655, layout.height - 73, 0, "Arrow keys to browse  /  Enter to play", muted);
        rounded(layout.width - 248, layout.height - 90, 168, 48, 10, accent);
        text(layout.width - 192, layout.height - 78, 2, "Play", .{ 28, 19, 12 });
        if (notice) {
            _ = s.SDL_SetRenderDrawBlendMode(renderer, s.SDL_BLENDMODE_BLEND);
            _ = s.SDL_SetRenderDrawColor(renderer, 10, 10, 10, 205);
            const overlay = s.SDL_FRect{ .x = 0, .y = 0, .w = layout.width, .h = layout.height };
            _ = s.SDL_RenderFillRect(renderer, &overlay);
            _ = s.SDL_SetRenderDrawBlendMode(renderer, s.SDL_BLENDMODE_NONE);
            const mx = (layout.width - 520) / 2;
            const my = (layout.height - 270) / 2;
            rounded(mx, my, 520, 270, 20, .{ 35, 35, 35 });
            text(mx + 40, my + 35, 0, "UNABLE TO PLAY", accent);
            text(mx + 40, my + 73, 3, games[selected].title, white);
            text(mx + 40, my + 122, 1, notice_message, muted);
            text(mx + 40, my + 147, 1, "Close this message to return to your library.", muted);
            rounded(mx + 100, my + 191, 320, 44, 10, accent);
            text(mx + 211, my + 201, 1, "Got it", .{ 28, 19, 12 });
        }
        if (check_finished) {
            if (s.SDL_getenv("ORBIT_LAUNCH_SCREENSHOT")) |output| {
                const surface = s.SDL_RenderReadPixels(renderer, null) orelse return error.ScreenshotRead;
                defer s.SDL_DestroySurface(surface);
                if (!s.SDL_SaveBMP(surface, output)) return error.ScreenshotSave;
            }
            s.SDL_Log("Library Play handoff and return passed");
            return;
        }
        if (screenshot != null) {
            const surface = s.SDL_RenderReadPixels(renderer, null) orelse return error.ScreenshotRead;
            defer s.SDL_DestroySurface(surface);
            if (!s.SDL_SaveBMP(surface, screenshot)) return error.ScreenshotSave;
            running = false;
        }
        if (launch_check != null and !check_queued) {
            // Exercise the exact mouse event used by the visible Play button.
            var click: s.SDL_Event = std.mem.zeroes(s.SDL_Event);
            click.type = s.SDL_EVENT_MOUSE_BUTTON_DOWN;
            click.button.button = s.SDL_BUTTON_LEFT;
            click.button.clicks = 1;
            click.button.x = layout.width - 164;
            click.button.y = layout.height - 66;
            if (!s.SDL_PushEvent(&click)) return error.LaunchCheckEvent;
            check_queued = true;
        }
        _ = s.SDL_RenderPresent(renderer);
        s.SDL_Delay(8);
    }
}
