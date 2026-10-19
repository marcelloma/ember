const std = @import("std");
const c = @import("api.zig").c;
pub fn configure() void {
    _ = c.SDL_SetAppMetadata("Ember", "0.1.0", "org.ember.Launcher");
    _ = c.SDL_SetHint(c.SDL_HINT_APP_ID, "org.ember.Launcher");
}
pub fn setWindowIcon(window: *c.SDL_Window) !void {
    var buffer: [4096]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buffer, "{s}assets/brand/icon.svg", .{std.mem.span(c.SDL_GetBasePath())});
    const icon = c.IMG_Load(path) orelse return error.BrandImageMissing;
    defer c.SDL_DestroySurface(icon);
    // Desktop-entry matching supplies the taskbar icon on Wayland compositors
    // that do not support setting an icon directly on the window.
    _ = c.SDL_SetWindowIcon(window, icon);
}
