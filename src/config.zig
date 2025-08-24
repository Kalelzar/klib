const std = @import("std");
const log = std.log.scoped(.config);
const json = std.json;

const meta = @import("meta.zig");

pub fn validate(comptime Base: type, comptime Extension: type) type {
    meta.ensureStructure(Base, Extension);
    return Extension;
}

//TODO: These locations should be configurable.
const ConfigLocations = struct {
    // Add XDG Base Directory support
    pub fn getXdgConfigHome(allocator: std.mem.Allocator) !?[]const u8 {
        return fromEnv(allocator, "XDG_CONFIG_HOME");
    }

    pub fn getHome(allocator: std.mem.Allocator) !?[]const u8 {
        return fromEnv(allocator, "HOME");
    }

    fn fromEnv(allocator: std.mem.Allocator, envKey: []const u8) !?[]const u8 {
        const env = std.process.getEnvVarOwned(allocator, envKey);
        if (env) |path| {
            return path;
        } else |err| {
            switch (err) {
                error.EnvironmentVariableNotFound => {
                    return null;
                },
                else => |other_error| return other_error,
            }
        }
    }
};

fn openConfigFile(comptime ConfigType: type, allocator: std.mem.Allocator, path: []const u8) !ConfigType {
    const file = try std.fs.openFileAbsolute(
        path,
        std.fs.File.OpenFlags{ .mode = .read_only },
    );
    defer file.close();

    const stat = try file.stat();
    const max_size = stat.size;
    const contents = try file.readToEndAlloc(allocator, max_size);
    defer allocator.free(contents);

    const parsed = try json.parseFromSliceLeaky(
        ConfigType,
        allocator,
        contents,
        .{
            .allocate = .alloc_always,
        },
    );

    return parsed;
}

fn updateConfigFile(path: []const u8, config: anytype) !void {
    const file = try std.fs.openFileAbsolute(
        path,
        std.fs.File.OpenFlags{ .mode = .write_only },
    );
    defer file.close();

    try file.seekTo(0);
    const file_writer = file.writer();
    try std.json.stringify(
        config,
        .{ .whitespace = .indent_2 },
        file_writer,
    );
}

const LoadPaths = struct {
    paths: std.ArrayList([]u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, paths: std.ArrayList([]u8)) LoadPaths {
        return .{
            .allocator = allocator,
            .paths = paths,
        };
    }

    pub fn deinit(self: *const LoadPaths) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }

        self.paths.deinit(self.allocator);
    }
};

fn buildConfigPaths(allocator: std.mem.Allocator, comptime dirname: []const u8, comptime basename: []const u8) !LoadPaths {
    var paths = std.ArrayList([]u8){};
    errdefer {
        const load_paths = LoadPaths.init(allocator, paths);
        load_paths.deinit();
    }

    const ext = ".json";
    const config_path = basename ++ ext;

    // 1. Check current directory
    const buf: [256]u8 = undefined;
    const cwd = try std.process.getCwd(&buf);
    try paths.append(try std.fs.path.join(allocator, &.{ cwd, config_path }));

    // 2. Check XDG config directory
    if (try ConfigLocations.getXdgConfigHome(allocator)) |xdg_config| {
        defer allocator.free(xdg_config);
        const xdg_path = try std.fs.path.join(allocator, &.{ xdg_config, dirname, config_path });
        try paths.append(xdg_path);
    }

    // 3. Check HOME config directory
    if (try ConfigLocations.getHome(allocator)) |home_config| {
        defer allocator.free(home_config);
        const home_path = try std.fs.path.join(allocator, &.{ home_config, ".config", dirname, config_path });
        try paths.append(home_path);
    }

    // 4. Check /etc for system-wide config
    try paths.append(try std.fs.path.join(allocator, &.{ "/", "etc", dirname, config_path }));
    return LoadPaths.init(allocator, paths);
}

pub fn findConfigFile(
    comptime ConfigType: type,
    allocator: std.mem.Allocator,
    comptime dir_name: []const u8,
    comptime config_name: []const u8,
) !?ConfigType {
    const loadPath = try buildConfigPaths(allocator, dir_name, config_name);
    defer loadPath.deinit();
    var result: ?ConfigType = null;

    for (loadPath.paths.items) |path| {
        result = openConfigFile(ConfigType, allocator, path) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |other_error| return other_error,
        };
        errdefer result.?.deinit();
        break;
    }

    return result;
}

pub fn findConfigFileToUpdate(config: anytype, allocator: std.mem.Allocator, comptime dir_name: []const u8, comptime config_name: []const u8) !void {
    const loadPath = try buildConfigPaths(allocator, dir_name, config_name);
    defer loadPath.deinit();

    for (loadPath.paths.items) |path| {
        updateConfigFile(path, config) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |other_error| return other_error,
        };
        return;
    }

    return error.FileNotFound;
}

pub fn Config(comptime Base: type, comptime Extension: type) type {
    const Result = meta.MergeStructs(Base, Extension);

    return struct {
        value: Result,

        pub fn init(result: Result) Config(Base, Extension) {
            return .{
                .value = result,
            };
        }
    };
}

fn findConfigFileOrDefault(
    comptime ConfigType: type,
    allocator: std.mem.Allocator,
    comptime dir_name: []const u8,
    comptime config_name: []const u8,
) !ConfigType {
    return (try findConfigFile(ConfigType, allocator, dir_name, config_name)) orelse std.mem.zeroInit(ConfigType, .{});
}

pub fn findConfigFileWithDefaults(
    comptime Base: type,
    comptime OptBase: type,
    comptime ConfigType: type,
    comptime dir_name: []const u8,
    comptime base_config_name: []const u8,
    comptime config_name: []const u8,
    arena: *std.heap.ArenaAllocator,
) !Config(Base, ConfigType) {
    const allocator = arena.allocator();

    const Extension = meta.MergeStructs(OptBase, ConfigType);
    const ext = try findConfigFileOrDefault(Extension, allocator, dir_name, config_name);

    const base = try findConfigFileOrDefault(Base, allocator, dir_name, base_config_name);
    const Final = meta.MergeStructs(Base, ConfigType);

    const final = meta.merge(Base, Extension, Final, base, ext);

    try meta.assertNotEmpty(Final, final);

    return Config(Base, ConfigType).init(final);
}
