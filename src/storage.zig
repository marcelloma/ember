const std = @import("std");
const c = @import("api.zig").c;

fn configPath(allocator: std.mem.Allocator) ![:0]u8 {
    const base = c.SDL_GetPrefPath("Ember", "Ember") orelse return error.StorageConfig;
    defer c.SDL_free(base);
    return std.fmt.allocPrintSentinel(allocator, "{s}storage-path.txt", .{base}, 0);
}

pub fn load(allocator: std.mem.Allocator) !?[:0]u8 {
    const path = try configPath(allocator);
    defer allocator.free(path);
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path, &info)) return null;
    if (info.size > 32768) return error.StorageConfig;
    var size: usize = 0;
    const data = c.SDL_LoadFile(path, &size) orelse return error.StorageConfig;
    defer c.SDL_free(data);
    const value = std.mem.trim(u8, @as([*]const u8, @ptrCast(data))[0..size], "\r\n");
    if (value.len == 0 or std.mem.indexOfScalar(u8, value, 0) != null) return error.StorageConfig;
    return try allocator.dupeZ(u8, value);
}

pub fn initialize(allocator: std.mem.Allocator, root: [:0]const u8) !void {
    for ([_][]const u8{ "", "/roms/snes", "/configs", "/saves/snes", "/states/snes", "/settings/snes", "/system" }) |suffix| {
        const path = try std.fmt.allocPrintSentinel(allocator, "{s}{s}", .{ root, suffix }, 0);
        defer allocator.free(path);
        if (!c.SDL_CreateDirectory(path)) return error.StorageNotWritable;
    }
    // Check actual write access before remembering a folder selected through a portal.
    const probe = try std.fmt.allocPrintSentinel(allocator, "{s}/.ember-write-test", .{root}, 0);
    defer allocator.free(probe);
    var info: c.SDL_PathInfo = undefined;
    if (c.SDL_GetPathInfo(probe, &info)) return error.StorageProbeExists;
    if (!c.SDL_SaveFile(probe, "ok", 2)) return error.StorageNotWritable;
    if (!c.SDL_RemovePath(probe)) return error.StorageNotWritable;
}

pub fn remember(allocator: std.mem.Allocator, root: [:0]const u8) !void {
    const path = try configPath(allocator);
    defer allocator.free(path);
    const temp = try std.fmt.allocPrintSentinel(allocator, "{s}.tmp", .{path}, 0);
    defer allocator.free(temp);
    if (!c.SDL_SaveFile(temp, root.ptr, root.len) or !c.SDL_RenamePath(temp, path)) return error.StorageConfig;
}

pub fn activate(allocator: std.mem.Allocator, root: [:0]const u8) !void {
    const roms = try std.fmt.allocPrintSentinel(allocator, "{s}/roms", .{root}, 0);
    defer allocator.free(roms);
    // Update both SDL's environment snapshot and the OS environment inherited by game processes.
    for ([_]struct { name: [:0]const u8, value: [:0]const u8 }{
        .{ .name = "EMBER_ROM_DIR", .value = roms },
        .{ .name = "ORBIT_DATA_DIR", .value = root },
    }) |entry| {
        if (c.SDL_setenv_unsafe(entry.name, entry.value, 1) != 0 or
            !c.SDL_SetEnvironmentVariable(c.SDL_GetEnvironment(), entry.name, entry.value, true)) return error.StorageEnvironment;
    }
}

pub const Selection = struct {
    ready: std.atomic.Value(bool) = .init(false),
    path: ?[*:0]u8 = null,
    failed: bool = false,

    pub fn callback(userdata: ?*anyopaque, files: [*c]const [*c]const u8, _: c_int) callconv(.c) void {
        const self: *Selection = @ptrCast(@alignCast(userdata.?));
        self.failed = files == null;
        if (files != null and files[0] != null) {
            self.path = c.SDL_strdup(files[0]);
            self.failed = self.path == null;
        }
        self.ready.store(true, .release);
    }
};
