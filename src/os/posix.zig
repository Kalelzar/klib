const std = @import("std");

// `gethostname`/`getpwuid`/`getuid` come from libc (the module links libc);
// declared by hand since `@cImport` is gone in Zig 0.17.
extern "c" fn gethostname(name: [*]u8, len: usize) c_int;
extern "c" fn getuid() std.c.uid_t;
extern "c" fn getpwuid(uid: std.c.uid_t) ?*std.c.passwd;

pub fn hostname(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [256]u8 = undefined;
    if (gethostname(&buf, buf.len) != 0) {
        return error.HostnameError;
    }
    const len = std.mem.len(@as([*:0]u8, @ptrCast(&buf)));
    return allocator.dupe(u8, buf[0..len]);
}

pub fn username(allocator: std.mem.Allocator) ![]const u8 {
    const pw = getpwuid(getuid()) orelse return error.UsernameError;
    const name = std.mem.span(pw.name orelse return error.UsernameError);
    return allocator.dupe(u8, name);
}
