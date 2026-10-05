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
    env_map: *const std.process.Environ.Map,

    pub fn getXdgConfigHome(self: *const ConfigLocations) ?[]const u8 {
        return self.fromEnv("XDG_CONFIG_HOME");
    }

    pub fn getHome(self: *const ConfigLocations) ?[]const u8 {
        return self.fromEnv("HOME");
    }

    fn fromEnv(self: *const ConfigLocations, envKey: []const u8) ?[]const u8 {
        const env = self.env_map.get(envKey) orelse return null;
        return env;
    }
};

fn openConfigFile(
    comptime ConfigType: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !ConfigType {
    const file = try std.Io.Dir.openFileAbsolute(
        io,
        path,
        .{ .mode = .read_only },
    );
    defer file.close(io);

    // The JSON reader peeks through the file reader's buffer, so it must not be empty.
    var read_buf: [4096]u8 = undefined;
    var file_reader = file.readerStreaming(io, &read_buf);
    var json_reader = json.Reader.init(allocator, &file_reader.interface);

    const parsed = try json.parseFromTokenSourceLeaky(ConfigType, allocator, &json_reader, .{
        .allocate = .alloc_always,
    });

    return parsed;
}

fn updateConfigFile(io: std.Io, path: []const u8, config: anytype) !void {
    const file = try std.Io.Dir.createFileAbsolute(io, path, .{ .truncate = true });

    defer file.close(io);

    try file.seekTo(0);
    var buf: [4096]u8 = undefined;
    var file_writer = file.writer(&buf);
    const wi = &file_writer.interface;
    const fmt = std.json.fmt(
        config,
        .{ .whitespace = .indent_2 },
    );
    try fmt.format(wi);
    try wi.flush();
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

    pub fn deinit(self: *LoadPaths) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }

        self.paths.deinit(self.allocator);
    }
};

fn buildConfigPaths(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    comptime dirname: []const u8,
    comptime basename: []const u8,
) !LoadPaths {
    var paths = std.ArrayList([]u8).empty;
    errdefer {
        var load_paths = LoadPaths.init(allocator, paths);
        load_paths.deinit();
    }

    const ext = ".json";
    const config_path = basename ++ ext;

    // 1. Check current directory
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd: []const u8 = buf[0..try std.process.currentPath(io, &buf)];
    try paths.append(allocator, try std.fs.path.join(allocator, &.{ cwd, config_path }));

    const locs = ConfigLocations{ .env_map = env_map };

    // 2. Check XDG config directory
    if (locs.getXdgConfigHome()) |xdg_config| {
        const xdg_path = try std.fs.path.join(
            allocator,
            &.{ xdg_config, dirname, config_path },
        );
        try paths.append(allocator, xdg_path);
    }

    // 3. Check HOME config directory
    if (locs.getHome()) |home_config| {
        const home_path = try std.fs.path.join(
            allocator,
            &.{ home_config, ".config", dirname, config_path },
        );
        try paths.append(allocator, home_path);
    }

    // 4. Check /etc for system-wide config
    try paths.append(allocator, try std.fs.path.join(
        allocator,
        &.{ "/", "etc", dirname, config_path },
    ));
    return LoadPaths.init(allocator, paths);
}

pub fn findConfigFile(
    comptime ConfigType: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    comptime dir_name: []const u8,
    comptime config_name: []const u8,
) !?ConfigType {
    var loadPath = try buildConfigPaths(
        allocator,
        io,
        env_map,
        dir_name,
        config_name,
    );
    defer loadPath.deinit();
    var result: ?ConfigType = null;

    for (loadPath.paths.items) |path| {
        result = openConfigFile(ConfigType, allocator, io, path) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |other_error| return other_error,
        };
        errdefer result.?.deinit();
        break;
    }

    return result;
}

pub fn findConfigFileToUpdate(
    config: anytype,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    allocator: std.mem.Allocator,
    comptime dir_name: []const u8,
    comptime config_name: []const u8,
) !void {
    var loadPath = try buildConfigPaths(
        allocator,
        io,
        env_map,
        dir_name,
        config_name,
    );
    defer loadPath.deinit();

    for (loadPath.paths.items) |path| {
        updateConfigFile(io, path, config) catch |err| switch (err) {
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
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    comptime dir_name: []const u8,
    comptime config_name: []const u8,
) !ConfigType {
    return (try findConfigFile(ConfigType, allocator, io, env_map, dir_name, config_name)) orelse std.mem.zeroInit(ConfigType, .{});
}

pub fn findConfigFileWithDefaults(
    comptime Base: type,
    comptime OptBase: type,
    comptime ConfigType: type,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    comptime dir_name: []const u8,
    comptime base_config_name: []const u8,
    comptime config_name: []const u8,
    arena: *std.heap.ArenaAllocator,
) !Config(Base, ConfigType) {
    const allocator = arena.allocator();

    const Extension = meta.MergeStructs(OptBase, ConfigType);
    const ext = try findConfigFileOrDefault(Extension, allocator, io, env_map, dir_name, config_name);

    const base = try findConfigFileOrDefault(Base, allocator, io, env_map, dir_name, base_config_name);
    const Final = meta.MergeStructs(Base, ConfigType);

    const final = meta.merge(Base, Extension, Final, base, ext);

    try meta.assertNotEmpty(Final, final);

    return Config(Base, ConfigType).init(final);
}
