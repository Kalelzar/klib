const std = @import("std");

pub const InstrumentedArena = struct {
    alloc: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    instrumented: *InstrumentedAllocator,

    pub fn init(alloc: std.mem.Allocator, shim: MemMetricsShim) !InstrumentedArena {
        const result = InstrumentedArena{
            .alloc = alloc,
            .arena = try alloc.create(std.heap.ArenaAllocator),
            .instrumented = try alloc.create(InstrumentedAllocator),
        };
        result.instrumented.* = InstrumentedAllocator.init(std.heap.page_allocator, shim);
        result.arena.* = std.heap.ArenaAllocator.init(result.instrumented.allocator());
        return result;
    }

    pub fn allocator(self: *InstrumentedArena) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *InstrumentedArena) void {
        if (!self.arena.reset(.retain_capacity)) {
            std.log.warn("Did not retain capacity!", .{});
        }
    }

    pub fn deinit(self: *InstrumentedArena) void {
        self.arena.deinit();
        self.alloc.destroy(self.arena);
        self.alloc.destroy(self.instrumented);
    }
};

pub const InstrumentedAllocator = @import("allocator.zig").InstrumentedAllocator;
pub const MemMetricsShim = @import("allocator.zig").MemMetricsShim;
