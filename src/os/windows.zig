const std = @import("std");
const windows = std.os.windows;

const ComputerName = enum(u32) {
    ComputerNameNetBIOS, // NetBIOS name
    ComputerNameDnsHostname, // DNS hostname
    ComputerNameDnsDomain, // DNS domain name
    ComputerNameDnsFullyQualified, // Fully qualified DNS name
    ComputerNamePhysicalNetBIOS, // Physical NetBIOS name
    ComputerNamePhysicalDnsHostname, // Physical DNS hostname
    ComputerNamePhysicalDnsDomain, // Physical DNS domain
    ComputerNamePhysicalDnsFullyQualified, // Physical fully qualified DNS
    ComputerNameMax,
};

extern "kernel32" fn GetComputerNameExA(
    computerName: ComputerName,
    outBuffer: ?windows.LPSTR,
    outSize: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

pub fn hostname(allocator: std.mem.Allocator) ![]const u8 {
    var size: u32 = 0;
    _ = GetComputerNameExA(.ComputerNameDnsHostname, null, &size);
    const bufZ = try allocator.allocSentinel(u8, size, 0);
    if (GetComputerNameExA(.ComputerNameDnsHostname, bufZ.ptr, &size) == 0) {
        const err = windows.GetLastError();
        std.log.err("Failed to retrieve hostname with: {}", .{err});
        return error.HostnameError; //TODO: Maybe return а more detailed error.
    }
    return std.mem.span(bufZ.ptr);
}

extern "advapi32" fn GetUserNameA(
    lpBuffer: ?windows.LPSTR,
    pcbBuffer: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

pub fn username(allocator: std.mem.Allocator) ![]const u8 {
    var size: u32 = 0;
    _ = GetUserNameA(null, &size);

    const bufZ = try allocator.allocSentinel(u8, size - 1, 0);
    errdefer allocator.free(bufZ);

    if (GetUserNameA(bufZ.ptr, &size) == 0) {
        const err = windows.GetLastError();
        std.log.err("Failed to retrieve username: {}", .{err});
        return error.UsernameError;
    }

    return std.mem.span(bufZ.ptr);
}
