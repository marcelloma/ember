const std = @import("std");
const c = @import("api.zig").c;
const RGB = [3]u8;
const light: RGB = .{ 240, 238, 235 };
const muted: RGB = .{ 164, 160, 155 };
const accent: RGB = .{ 255, 138, 56 };
const Label = struct { value: [:0]const u8, font: usize, texture: *c.SDL_Texture, w: f32, h: f32, rgb: RGB };
pub const Action = enum { none, resume_game, return_to_library, toggle_scanlines, toggle_stretch };
pub const Menu = struct {
    renderer: *c.SDL_Renderer,
    fonts: [3]*c.TTF_Font,
    labels: [48]Label = undefined,
    count: usize = 0,
    scale: f32 = 1,
    ox: f32 = 0,
    oy: f32 = 0,
    selected: usize = 0,
    settings: @import("game_settings.zig").Settings = .{},
    settings_error: bool = false,
    pub fn init(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer) !Menu {
        var fonts: [3]*c.TTF_Font = undefined;
        const path = try std.fmt.allocPrintSentinel(allocator, "{s}assets/fonts/OpenSans-Semibold.ttf", .{std.mem.span(c.SDL_GetBasePath())}, 0);
        defer allocator.free(path);
        var loaded: usize = 0;
        errdefer for (fonts[0..loaded]) |font| c.TTF_CloseFont(font);
        for ([_]f32{ 14, 20, 32 }, 0..) |size, i| {
            fonts[i] = c.TTF_OpenFont(path, size) orelse return error.PauseMenuFont;
            loaded += 1;
        }
        return .{ .renderer = renderer, .fonts = fonts };
    }
    pub fn deinit(self: *Menu) void {
        for (self.labels[0..self.count]) |label| c.SDL_DestroyTexture(label.texture);
        for (self.fonts) |font| c.TTF_CloseFont(font);
    }
    fn color(self: *Menu, rgb: RGB) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, rgb[0], rgb[1], rgb[2], 255);
    }
    fn rect(self: *Menu, x: f32, y: f32, w: f32, h: f32, rgb: RGB) void {
        self.color(rgb);
        const r = c.SDL_FRect{ .x = x + self.ox, .y = y + self.oy, .w = w, .h = h };
        _ = c.SDL_RenderFillRect(self.renderer, &r);
    }
    fn circle(self: *Menu, x: f32, y: f32, r: f32, rgb: RGB) void {
        var vertices: [66]c.SDL_Vertex = undefined;
        var indices: [192]c_int = undefined;
        const col = c.SDL_FColor{ .r = @as(f32, @floatFromInt(rgb[0])) / 255, .g = @as(f32, @floatFromInt(rgb[1])) / 255, .b = @as(f32, @floatFromInt(rgb[2])) / 255, .a = 1 };
        vertices[0] = .{ .position = .{ .x = x + self.ox, .y = y + self.oy }, .color = col, .tex_coord = .{ .x = 0, .y = 0 } };
        for (0..65) |i| {
            const angle = @as(f32, @floatFromInt(i)) * std.math.pi * 2 / 64;
            vertices[i + 1] = .{ .position = .{ .x = x + self.ox + @cos(angle) * r, .y = y + self.oy + @sin(angle) * r }, .color = col, .tex_coord = .{ .x = 0, .y = 0 } };
        }
        for (0..64) |i| {
            indices[i * 3] = 0;
            indices[i * 3 + 1] = @intCast(i + 1);
            indices[i * 3 + 2] = @intCast(i + 2);
        }
        _ = c.SDL_RenderGeometry(self.renderer, null, &vertices, vertices.len, &indices, indices.len);
    }
    fn pill(self: *Menu, x: f32, y: f32, w: f32, h: f32, rgb: RGB) void {
        self.rect(x + h / 2, y, w - h, h, rgb);
        self.circle(x + h / 2, y + h / 2, h / 2, rgb);
        self.circle(x + w - h / 2, y + h / 2, h / 2, rgb);
    }
    fn text(self: *Menu, x: f32, y: f32, font: usize, value: [:0]const u8, rgb: RGB) void {
        var entry: ?Label = null;
        for (self.labels[0..self.count]) |label| if (label.font == font and std.mem.eql(u8, label.value, value) and std.mem.eql(u8, &label.rgb, &rgb)) {
            entry = label;
            break;
        };
        if (entry == null) {
            if (self.count == self.labels.len) return;
            const surface = c.TTF_RenderText_Blended(self.fonts[font], value, value.len, .{ .r = rgb[0], .g = rgb[1], .b = rgb[2], .a = 255 }) orelse return;
            defer c.SDL_DestroySurface(surface);
            const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return;
            entry = .{ .texture = texture, .value = value, .font = font, .w = @floatFromInt(surface.*.w), .h = @floatFromInt(surface.*.h), .rgb = rgb };
            self.labels[self.count] = entry.?;
            self.count += 1;
        }
        const label = entry.?;
        const dst = c.SDL_FRect{ .x = x + self.ox, .y = y + self.oy, .w = label.w, .h = label.h };
        _ = c.SDL_RenderTexture(self.renderer, label.texture, null, &dst);
    }
    fn line(self: *Menu, x: f32, y: f32, tx: f32, ty: f32) void {
        self.color(accent);
        _ = c.SDL_RenderLine(self.renderer, x + self.ox, y + self.oy, tx + self.ox, ty + self.oy);
    }
    fn arrow(self: *Menu, x: f32, y: f32, tx: f32, ty: f32) void {
        self.line(x, y, tx, ty);
        const angle = std.math.atan2(ty - y, tx - x);
        self.line(tx, ty, tx - 10 * @cos(angle - 0.5), ty - 10 * @sin(angle - 0.5));
        self.line(tx, ty, tx - 10 * @cos(angle + 0.5), ty - 10 * @sin(angle + 0.5));
    }
    fn bind(self: *Menu, x: f32, y: f32, label: [:0]const u8, key: [:0]const u8) void {
        self.text(x, y, 0, label, muted);
        self.pill(x, y + 24, 150, 38, .{ 47, 47, 47 });
        self.text(x + 16, y + 29, 1, key, light);
    }
    pub fn hit(self: *const Menu, px: f32, py: f32) Action {
        const x = px / self.scale - self.ox;
        const y = py / self.scale - self.oy;
        if (y >= 64 and y <= 146) {
            if (x >= 625 and x <= 855) return .toggle_scanlines;
            if (x >= 880 and x <= 1110) return .toggle_stretch;
        }
        if (y >= 700 and y <= 748) {
            if (x >= 690 and x <= 870) return .resume_game;
            if (x >= 890 and x <= 1110) return .return_to_library;
        }
        return .none;
    }
    fn toggle(self: *Menu, x: f32, label: [:0]const u8, enabled: bool, selected: bool) void {
        self.rect(x, 64, 230, 82, if (selected) .{ 65, 43, 28 } else .{ 37, 37, 37 });
        self.text(x + 14, 74, 0, label, if (selected) accent else light);
        self.pill(x + 14, 107, 64, 26, if (enabled) accent else .{ 65, 65, 65 });
        self.text(x + 29, 109, 0, if (enabled) "ON" else "OFF", if (enabled) .{ 28, 19, 12 } else light);
    }
    pub fn draw(self: *Menu) void {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetRenderOutputSize(self.renderer, &w, &h);
        _ = c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_BLEND);
        _ = c.SDL_SetRenderDrawColor(self.renderer, 10, 10, 10, 220);
        const shade = c.SDL_FRect{ .x = 0, .y = 0, .w = @floatFromInt(w), .h = @floatFromInt(h) };
        _ = c.SDL_RenderFillRect(self.renderer, &shade);
        _ = c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_NONE);
        self.scale = @min(@as(f32, @floatFromInt(w)) / 1200, @as(f32, @floatFromInt(h)) / 820);
        self.ox = (@as(f32, @floatFromInt(w)) / self.scale - 1200) / 2;
        self.oy = (@as(f32, @floatFromInt(h)) / self.scale - 820) / 2;
        _ = c.SDL_SetRenderScale(self.renderer, self.scale, self.scale);
        self.rect(40, 40, 1120, 740, .{ 26, 26, 26 });
        self.text(85, 70, 2, "Game paused", light);
        self.text(85, 117, 0, "KEYBOARD CONTROLS  /  SUPER NINTENDO", muted);
        self.toggle(625, "CRT scanlines", self.settings.crt_scanlines, self.selected == 2);
        self.toggle(880, "Full screen (stretch)", self.settings.fullscreen_stretch, self.selected == 3);
        if (self.settings_error) self.text(85, 151, 0, "Settings could not be saved. Please try again.", .{ 255, 155, 155 });
        // The controller is native geometry; the labels stay crisp at every viewport size.
        self.pill(351, 274, 147, 28, .{ 130, 130, 130 });
        self.pill(702, 274, 147, 28, .{ 130, 130, 130 });
        self.rect(430, 298, 340, 230, .{ 192, 192, 192 });
        self.circle(430, 414, 124, .{ 192, 192, 192 });
        self.circle(770, 414, 124, .{ 192, 192, 192 });
        self.circle(430, 414, 89, .{ 165, 165, 165 });
        self.circle(770, 414, 95, .{ 145, 145, 145 });
        self.rect(414, 368, 32, 92, .{ 46, 46, 46 });
        self.rect(384, 398, 92, 32, .{ 46, 46, 46 });
        self.circle(430, 414, 12, .{ 65, 65, 65 });
        self.text(506, 333, 0, "SUPER NINTENDO", .{ 85, 85, 85 });
        self.pill(524, 424, 52, 18, .{ 60, 60, 60 });
        self.pill(608, 424, 52, 18, .{ 60, 60, 60 });
        self.text(524, 454, 0, "SELECT", .{ 78, 78, 78 });
        self.text(608, 454, 0, "START", .{ 78, 78, 78 });
        self.circle(770, 356, 25, .{ 206, 117, 53 });
        self.circle(716, 410, 25, .{ 206, 117, 53 });
        self.circle(824, 410, 25, .{ 145, 67, 26 });
        self.circle(770, 464, 25, .{ 145, 67, 26 });
        self.text(762, 341, 1, "X", light);
        self.text(708, 395, 1, "Y", light);
        self.text(816, 395, 1, "A", light);
        self.text(762, 449, 1, "B", light);
        self.bind(220, 185, "L SHOULDER", "Q");
        self.arrow(370, 228, 410, 285);
        self.bind(830, 185, "R SHOULDER", "W");
        self.arrow(830, 228, 790, 285);
        self.bind(100, 380, "D-PAD", "Arrow keys");
        self.arrow(260, 424, 383, 414);
        self.bind(945, 300, "X BUTTON", "S");
        self.arrow(935, 342, 797, 356);
        self.bind(945, 395, "A BUTTON", "X");
        self.arrow(935, 435, 851, 414);
        self.bind(945, 490, "B BUTTON", "Z");
        self.arrow(935, 530, 796, 477);
        self.bind(760, 582, "Y BUTTON", "A");
        self.arrow(780, 574, 716, 440);
        self.bind(430, 582, "SELECT", "Right Shift");
        self.arrow(505, 574, 547, 445);
        self.bind(595, 582, "START", "Enter");
        self.arrow(655, 574, 637, 445);
        self.text(85, 711, 0, "Esc to resume  /  Tab or arrows to choose", muted);
        self.pill(690, 700, 180, 48, if (self.selected == 0) accent else .{ 49, 49, 49 });
        self.pill(890, 700, 220, 48, if (self.selected == 1) accent else .{ 49, 49, 49 });
        self.text(739, 709, 1, "Resume", if (self.selected == 0) .{ 28, 19, 12 } else light);
        self.text(914, 712, 0, "Save & return to library", if (self.selected == 1) .{ 28, 19, 12 } else light);
        _ = c.SDL_SetRenderScale(self.renderer, 1, 1);
    }
};
