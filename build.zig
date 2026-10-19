const std = @import("std");

fn dependencies(b: *std.Build, module: *std.Build.Module, windows: bool, sdk: []const u8) void {
    module.link_libc = true;
    module.addIncludePath(b.path("vendor/libretro"));
    if (windows) {
        module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "include" }) });
        module.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "lib" }) });
        for ([_][]const u8{ "SDL3", "SDL3_ttf", "SDL3_image" }) |name| {
            module.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ sdk, "lib", b.fmt("lib{s}.dll.a", .{name}) }) });
        }
    } else {
        // Explicit Linux target triples do not inherit Zig's native library
        // search paths. Resolve the SDL library directory through pkg-config.
        const libdir = std.mem.trim(u8, b.run(&.{ "pkg-config", "--variable=libdir", "sdl3" }), " \r\n\t");
        module.addLibraryPath(.{ .cwd_relative = libdir });
        const includedir = std.mem.trim(u8, b.run(&.{ "pkg-config", "--variable=includedir", "sdl3" }), " \r\n\t");
        module.addSystemIncludePath(.{ .cwd_relative = includedir });
        module.linkSystemLibrary("SDL3", .{});
        module.linkSystemLibrary("sdl3-ttf", .{});
        module.linkSystemLibrary("sdl3-image", .{});
    }
}
pub fn build(b: *std.Build) void {
    var target = b.standardTargetOptions(.{});
    // Linux links the host's SDL packages, so use their detected glibc ABI
    // unless the caller explicitly supplies a glibc version/sysroot.
    if (target.result.os.tag == .linux and b.graph.host.result.os.tag == .linux and target.query.glibc_version == null and target.query.os_tag != null) {
        var query = target.query;
        query.glibc_version = b.graph.host.result.os.version_range.linux.glibc;
        target = b.resolveTargetQuery(query);
    }
    const optimize = b.standardOptimizeOption(.{});
    const windows = target.result.os.tag == .windows;
    if (target.result.os.tag != .linux and !windows) @panic("Ember supports Linux and Windows targets");
    if (target.result.cpu.arch != .x86_64) @panic("Bundled cores currently support x86_64 only");
    const sdk = b.option([]const u8, "windows-sdk", "Windows SDL dependency directory") orelse ".deps/windows-x86_64";
    const exe = b.addExecutable(.{ .name = "ember", .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize }) });
    dependencies(b, exe.root_module, windows, sdk);
    if (windows) {
        exe.subsystem = .windows;
        exe.root_module.addWin32ResourceFile(.{ .file = b.path("packaging/windows/ember.rc"), .include_paths = &.{b.path("assets/brand")} });
    }
    b.installArtifact(exe);
    b.installDirectory(.{ .source_dir = b.path("assets"), .install_dir = .bin, .install_subdir = "assets" });
    if (windows) {
        b.installDirectory(.{ .source_dir = .{ .cwd_relative = b.pathJoin(&.{ sdk, "bin" }) }, .install_dir = .bin, .install_subdir = "", .include_extensions = &.{".dll"} });
        b.installDirectory(.{ .source_dir = .{ .cwd_relative = b.pathJoin(&.{ sdk, "cores" }) }, .install_dir = .bin, .install_subdir = "cores", .include_extensions = &.{".dll"} });
        b.installDirectory(.{ .source_dir = .{ .cwd_relative = b.pathJoin(&.{ sdk, "licenses" }) }, .install_dir = .bin, .install_subdir = "licenses" });
        b.installDirectory(.{ .source_dir = b.path("packaging/windows/licenses"), .install_dir = .bin, .install_subdir = "licenses/font-rendering" });
        b.installFile("cores/SNES9X-LICENSE.txt", "bin/cores/SNES9X-LICENSE.txt");
        b.installFile("packaging/windows/dependencies.json", "bin/licenses/dependencies.json");
    } else {
        b.installDirectory(.{ .source_dir = b.path("cores"), .install_dir = .bin, .install_subdir = "cores", .include_extensions = &.{ ".so", ".txt", ".json" } });
    }
    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/retro.zig"), .target = target, .optimize = optimize }) });
    dependencies(b, tests.root_module, windows, sdk);
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Test libretro options and controller input (native target)").dependOn(&run_tests.step);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the launcher (native target)").dependOn(&run.step);
}
