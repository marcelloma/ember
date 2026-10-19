const std = @import("std");
const c = @import("api.zig").c;
pub const Settings = struct {
    version: u32 = 1,
    crt_scanlines: bool = false,
    fullscreen_stretch: bool = false,
};
pub fn read(allocator: std.mem.Allocator, path: [:0]const u8) !Settings {
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path, &info)) return .{};
    if (info.size > 4096) return error.GameSettingsRead;
    var size: usize = 0;
    const data = c.SDL_LoadFile(path, &size) orelse return error.GameSettingsRead;
    defer c.SDL_free(data);
    const parsed = std.json.parseFromSlice(Settings, allocator, @as([*]const u8, @ptrCast(data))[0..size], .{ .ignore_unknown_fields = true }) catch return error.GameSettingsRead;
    defer parsed.deinit();
    if (parsed.value.version != 1) return error.GameSettingsRead;
    return parsed.value;
}
pub fn write(path: [:0]const u8, value: Settings) !void {
    var buffer: [256]u8 = undefined;
    const json = try std.fmt.bufPrint(&buffer, "{{\"version\":1,\"crt_scanlines\":{s},\"fullscreen_stretch\":{s}}}\n", .{ if (value.crt_scanlines) "true" else "false", if (value.fullscreen_stretch) "true" else "false" });
    var temp_buffer: [4096]u8 = undefined;
    const temp = try std.fmt.bufPrintZ(&temp_buffer, "{s}.tmp", .{path});
    if (!c.SDL_SaveFile(temp, json.ptr, json.len) or !c.SDL_RenamePath(temp, path)) return error.GameSettingsWrite;
}
