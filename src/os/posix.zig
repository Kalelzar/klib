const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("pwd.h");
});

pub fn hostname(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [256]u8 = undefined;
    if (c.gethostname(&buf, buf.len) != 0) {
        return error.HostnameError;
    }
    const len = std.mem.len(@as([*:0]u8, @ptrCast(&buf)));
    return allocator.dupe(u8, buf[0..len]);
}

pub fn username(allocator: std.mem.Allocator) ![]const u8 {
    const pw = c.getpwuid(c.getuid());
    if (pw == null) return error.UsernameError;

    const name = std.mem.span(pw.*.pw_name);
    return allocator.dupe(u8, name);
}
