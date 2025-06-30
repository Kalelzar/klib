const std = @import("std");
const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .windows => @import("os/windows.zig"),
    .linux, .macos, .freebsd, .openbsd, .netbsd, .dragonfly, .solaris => @import("os/posix.zig"),
    else => |tag| @compileError(std.fmt.comptimePrint("Compilation is not supported on: {}", .{tag})),
};

pub inline fn hostname(allocator: std.mem.Allocator) ![]const u8 {
    return platform.hostname(allocator);
}

pub inline fn username(allocator: std.mem.Allocator) ![]const u8 {
    return platform.username(allocator);
}
