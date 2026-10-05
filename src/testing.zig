const std = @import("std");
const builtin = @import("builtin");

/// Reference every public declaration of `T`, recursing into nested container
/// types, so that `zig build test` analyses them. Zig 0.17 dropped
/// `std.testing.refAllDeclsRecursive`; this is the same contract rebuilt on
/// `decl_names` (which, like `@hasDecl` since 0.17, only sees `pub` decls).
pub fn refAllDeclsRecursive(comptime T: type) void {
    if (!builtin.is_test) return;
    inline for (comptime std.meta.declarations(T)) |name| {
        const decl = @field(T, name);
        if (@TypeOf(decl) == type) {
            switch (@typeInfo(decl)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(decl),
                else => {},
            }
        }
        _ = &decl;
    }
}
