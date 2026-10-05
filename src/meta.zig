const std = @import("std");

// Check if a given type is a struct.
pub fn isStruct(comptime Type: type) bool {
    return switch (@typeInfo(Type)) {
        .@"struct" => true,
        else => false,
    };
}

pub fn ensureStruct(comptime Type: type) void {
    if (!isStruct(Type)) {
        @compileError("Only structs are supported");
    }
}

// Merge two structs into a single type.
// NOTE: This discards any declarations they have (fn, var, etc...)
pub fn MergeStructs(comptime Base: type, comptime Child: type) type {
    const base_info = @typeInfo(Base);
    const child_info = @typeInfo(Child);

    ensureStruct(Base);
    ensureStruct(Child);

    const b = base_info.@"struct";
    const c = child_info.@"struct";

    const names = b.field_names ++ c.field_names;
    const types = b.field_types ++ c.field_types;
    const attributes = b.field_attrs ++ c.field_attrs;

    return @Struct(.auto, null, names, types, attributes);
}

// Validates that a struct has the same fields as another.
pub fn overlaps(comptime Left: type, comptime Right: type) bool {
    ensureStruct(Left);
    ensureStruct(Right);
    const left_info = @typeInfo(Left);
    const right_info = @typeInfo(Right);
    const left_s = left_info.@"struct";
    const right_s = right_info.@"struct";

    inline for (left_s.field_names, left_s.field_types) |left_name, LeftFieldType| {
        var found = false;
        const left_type = @typeInfo(LeftFieldType);
        inline for (right_s.field_names, right_s.field_types) |right_name, RightFieldType| {
            if (!std.mem.eql(u8, left_name, right_name)) continue;
            found = true;
            const right_type = @typeInfo(RightFieldType);
            switch (left_type) {
                .@"struct" => {
                    // We need to verify that the inner structs also overlap.
                    // We do not compare types since we only care about structure.
                    if (!overlaps(LeftFieldType, RightFieldType)) {
                        return false;
                    }
                },
                .optional => {
                    const InnerLeftType = left_type.optional.child;
                    switch (right_type) {
                        .optional => {
                            const InnerRightType = right_type.optional.child;
                            if (isStruct(InnerLeftType) and isStruct(InnerRightType)) {
                                if (!overlaps(InnerLeftType, InnerRightType)) {
                                    @compileError("Non-overlapping child for struct? and struct?");
                                    //return false;
                                }
                            } else {
                                if (InnerLeftType != InnerRightType) {
                                    @compileError("Differing types for type? and type?");
                                    //return false;
                                }
                            }
                        },
                        else => {
                            if (isStruct(InnerLeftType) and isStruct(RightFieldType)) {
                                if (!overlaps(InnerLeftType, RightFieldType)) {
                                    @compileError("Non-overlapping child for struct? and struct");
                                    //return false;
                                }
                            } else {
                                if (InnerLeftType != RightFieldType) {
                                    @compileError("Differing types for type? and type");
                                }
                            }
                        },
                    }
                },
                else => {
                    switch (right_type) {
                        .optional => {
                            if (LeftFieldType != right_type.optional.child) {
                                @compileLog(LeftFieldType, right_type.optional.child);
                                @compileError("Differing types for type and type?");
                                //return false;
                            }
                        },
                        else => {
                            if (LeftFieldType != RightFieldType) {
                                @compileLog(LeftFieldType, RightFieldType);
                                @compileError("Differing types for type and type");
                                //return false;
                            }
                        },
                    }
                },
            }
        }
        if (!found) {
            return false;
        }
    }

    return true;
}

pub fn ensureStructure(comptime Left: type, comptime Right: type) void {
    if (!overlaps(Left, Right) or !overlaps(Right, Left)) {
        @compileError("Structs differ in structure");
    }
}

pub const ValidationError = error{
    Null,
    EmptyArray,
    EmptyPointer,
};

fn assertNotEmptyInternal(comptime field_name: []const u8, comptime Type: type, field_value: Type) ValidationError!void {
    switch (@typeInfo(Type)) {
        .optional => {
            if (field_value) |value| {
                const ValueType = @TypeOf(value);
                try assertNotEmptyInternal(field_name, ValueType, value);
            } else {
                return ValidationError.Null;
            }
        },
        .@"struct" => {
            try assertNotEmpty(Type, field_value);
        },
        .array => {
            if (field_value.len == 0) {
                return ValidationError.EmptyArray;
            }
            for (field_value) |value| {
                const ValueType = @TypeOf(value);
                try assertNotEmptyInternal(field_name, ValueType, value);
            }
        },
        .pointer => {
            if (field_value.len == 0) {
                return ValidationError.EmptyPointer;
            }
            for (field_value) |value| {
                const ValueType = @TypeOf(value);
                try assertNotEmptyInternal(field_name, ValueType, value);
            }
        },
        else => {},
    }
}

pub fn assertNotEmpty(comptime StructType: type, struct_value: StructType) ValidationError!void {
    const info = @typeInfo(StructType).@"struct";
    inline for (info.field_names, info.field_types) |field_name, FieldType| {
        const value = @field(struct_value, field_name);
        try assertNotEmptyInternal(field_name, FieldType, value);
    }
}

fn assign(
    comptime Target: type,
    comptime ValueType: type,
    comptime field_name: []const u8,
    comptime FieldType: type,
    value_maybe_optional: ValueType,
    target: *Target,
) void {
    const value_info = @typeInfo(ValueType);
    switch (value_info) {
        .optional => {
            if (value_maybe_optional) |value| {
                assign(Target, value_info.optional.child, field_name, FieldType, value, target);
            }
        },
        .@"struct" => {
            var child_target = @field(target, field_name);
            const ChildTarget = @TypeOf(child_target);
            @field(target, field_name) = copyTo(FieldType, ChildTarget, value_maybe_optional, &child_target).*;
        },
        else => {
            @field(target, field_name) = value_maybe_optional;
        },
    }
}

pub fn copyTo(comptime Source: type, comptime Target: type, source: Source, target: *Target) *Target {
    const info = @typeInfo(Source).@"struct";

    inline for (info.field_names, info.field_types) |field_name, FieldType| {
        if (comptime @hasField(Target, field_name)) {
            const value_maybe_optional = @field(source, field_name);
            assign(
                Target,
                FieldType,
                field_name,
                FieldType,
                value_maybe_optional,
                target,
            );
        }
    }

    return target;
}

pub fn copy(comptime Source: type, comptime Target: type, source: Source) Target {
    var target = std.mem.zeroInit(Target, .{});

    return copyTo(Source, Target, source, &target).*;
}

pub fn merge(comptime Base: type, comptime Child: type, comptime ResultT: type, base: Base, child: Child) ResultT {
    var result = std.mem.zeroInit(ResultT, .{});
    const result1 = copyTo(Base, ResultT, base, &result);
    const result2 = copyTo(Child, ResultT, child, result1);
    return result2.*;
}

// As per: https://github.com/ziglang/zig/issues/19858#issuecomment-2369861301
pub const TypeId = *const struct {
    _: u8 = undefined,
};

pub inline fn typeId(comptime T: type) TypeId {
    const TCache = &struct {
        comptime {
            _ = T;
        }
        var id: std.meta.Child(TypeId) = .{};
    };
    return &TCache.id;
}

pub fn isValuePointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .one,
        else => false,
    };
}

pub fn Return(comptime fun: anytype) type {
    return ReturnT(@TypeOf(fun));
}

pub fn ReturnT(comptime fun: type) type {
    return switch (@typeInfo(fun)) {
        .@"fn" => |f| f.return_type.?,
        .pointer => |p| ReturnT(p.child),
        else => @compileError("Expected a function, got " ++ @typeName(fun)),
    };
}

pub fn Fn(comptime fun: anytype) type {
    return switch (@typeInfo(fun)) {
        .@"fn" => fun,
        .pointer => |p| Fn(p.child),
        else => @compileError("Expected a function, got " ++ @typeName(fun)),
    };
}

pub fn Result(comptime fun: anytype) type {
    const R = Return(fun);

    return switch (@typeInfo(R)) {
        .error_union => |r| r.payload,
        else => R,
    };
}

pub fn canBeError(comptime fun: anytype) bool {
    return switch (@typeInfo(Return(fun))) {
        .error_union, .error_set => true,
        else => false,
    };
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

test "expect `isStruct` to succeed for structs." {
    try expect(isStruct(struct {}));
}

test "expect `isStruct` to fail for pointers." {
    const v: struct {} = .{};
    try expect(!isStruct(@TypeOf(&v)));
}

test "expect `isStruct` to fail for optional struct." {
    const v: ?struct {} = null;
    try expect(!isStruct(@TypeOf(&v)));
}

test "expect `isStruct` to fail for error union." {
    const v: anyerror!struct {} = error.Valid;
    try expect(!isStruct(@TypeOf(&v)));
    const v2: anyerror!struct {} = .{};
    try expect(!isStruct(@TypeOf(&v2)));
}

test "expect `MergeStruct` to merge two structs together" {
    const A = struct { a: i32 };
    const B = struct { b: i32 };

    const C = MergeStructs(A, B);
    try expect(@hasField(C, "a"));
    try expect(@hasField(C, "b"));
}

test "expect `overlaps` to correctly validate a flat struct" {
    const A = struct {
        a: i32,
        b: []const u8,
        c: ?u8 = null,
        d: *i32,
    };

    const B = struct {
        a: i32,
        b: []const u8,
        c: ?u8 = null,
        d: *i32,
    };

    try expect(comptime overlaps(A, B));
    try expect(comptime overlaps(B, A));
}

test "expect `overlaps` to be uni-directional (A subset B, but not B subset A)" {
    const A = struct {
        a: i32,
        b: []const u8,
    };

    const B = struct {
        a: i32,
        b: []const u8,
        c: ?u8 = null,
        d: *i32,
    };

    try expect(comptime overlaps(A, B));
    try expect(!comptime overlaps(B, A));
}

test "expect `overlaps` to succeed even if fields differ in optional." {
    const A = struct {
        a: ?i32,
        b: ?[]const u8,
        c: ?u8 = null,
        d: ?*i32,
    };

    const B = struct {
        a: i32,
        b: []const u8,
        c: u8,
        d: *i32,
    };

    try expect(comptime overlaps(A, B));
    try expect(comptime overlaps(B, A));
}

test "expect `overlaps` to follow structs and arrays." {
    const A = struct {
        a: i32,
        b: []const u8,
        c: u8,
        d: *i32,
    };

    const B = struct {
        a: A,
        b: *A,
        c: []A,
        d: ?A,
    };

    try expect(comptime overlaps(B, B));
}

test "expect `overlaps` to succeed for deeply nested structs." {
    const B = struct {
        a: struct {
            b: []struct {
                c: *struct {
                    d: ?struct {
                        u: u1,
                        i: i1,
                        a: []const u8,
                    },
                },
            },
        },
    };

    try expect(comptime overlaps(B, B));
}

test "expect `assertNotEmpty` to fail if an object is null" {
    const S = struct {
        s: ?i32 = null,
    };
    const s = S{};
    try expectError(
        error.Null,
        assertNotEmpty(S, s),
    );
}

test "expect `assertNotEmpty` to fail if a pointer is null" {
    const S = struct {
        s: []i32 = &.{},
    };
    const s = S{};
    try expectError(
        error.EmptyPointer,
        assertNotEmpty(S, s),
    );
}

test "expect `copyTo` to selectively copy only matching fields from one struct to another" {
    const A = struct {
        replace: i32 = 1,
        skip: i32 = 2,
    };

    const B = struct {
        replace: i32 = 2,
        remain: i32 = 3,
    };

    const a = A{};
    var b = B{};

    _ = copyTo(A, B, a, &b);
    try expectEqual(3, b.remain);
    try expectEqual(1, b.replace);
}

test "expect `copyTo` to recursively copy only matching fields from one struct to another" {
    const A = struct {
        inner: struct {
            replace: i32 = 1,
            skip: i32 = 2,
        } = .{},
    };

    const B = struct {
        inner: struct {
            replace: i32 = 2,
            remain: i32 = 3,
        } = .{},
    };

    const a = A{};
    var b = B{};

    _ = copyTo(A, B, a, &b);
    try expectEqual(3, b.inner.remain);
    try expectEqual(1, b.inner.replace);
}

test "expect `copyTo` to copy only matching fields while disregarding their optionality" {
    const A = struct {
        inner: struct {
            replace: ?i32 = 1,
            skip: i32 = 2,
        } = .{},
    };

    const B = struct {
        inner: struct {
            replace: i32 = 2,
            remain: i32 = 3,
        } = .{},
    };

    const a = A{};
    var b = B{};

    _ = copyTo(A, B, a, &b);
    try expectEqual(3, b.inner.remain);
    try expectEqual(1, b.inner.replace);
}

test "expect `copyTo` to copy only fields that aren't null" {
    const A = struct {
        inner: struct {
            replace: ?i32 = null,
            skip: i32 = 2,
        } = .{},
    };

    const B = struct {
        inner: struct {
            replace: i32 = 2,
            remain: i32 = 3,
        } = .{},
    };

    const a = A{};
    var b = B{};

    _ = copyTo(A, B, a, &b);
    try expectEqual(3, b.inner.remain);
    try expectEqual(2, b.inner.replace);
}

test "expect `copy` to instantiate a new struct that is a subset of another" {
    const A = struct {
        inner: struct {
            replace: ?i32 = 1,
            skip: i32 = 2,
        } = .{},
    };

    const B = struct {
        inner: struct {
            replace: i32 = 2,
            remain: i32 = 3,
        } = .{},
    };

    const a = A{};

    const b = copy(A, B, a);
    try expectEqual(3, b.inner.remain);
    try expectEqual(1, b.inner.replace);
}

test "expect `merge` to produce a struct instance that is a field-wise merge of two other structs" {
    const A = struct {
        inner: struct {
            left: ?i32 = 1,
            right: i32 = 2,
        } = .{},
    };

    const B = struct {
        a: i32 = 3,
        b: i32 = 4,
    };

    const C = MergeStructs(A, B);

    const a = A{};
    const b = B{};

    const c = merge(A, B, C, a, b);
    try expectEqual(1, c.inner.left);
    try expectEqual(2, c.inner.right);
    try expectEqual(3, c.a);
    try expectEqual(4, c.b);
}

test "expect `typeId` to produce a fingerprint for a type that is comparable at compile-time" {
    const T = struct {};
    const a = typeId(T);
    const b = typeId(T);
    try expectEqual(a, b);

    const U = struct {};
    const c = typeId(U);
    try expect(a != c);
}

test "expect `Return` to correctly identify the return type of a function" {
    const F = struct {
        pub fn t() i32 {
            return 1;
        }

        pub fn u() anyerror!i32 {
            return 1;
        }
    };

    try expectEqual(i32, Return(F.t));
    try expectEqual(anyerror!i32, Return(F.u));
}

test "expect `Result` to correctly identify the result type of a function" {
    const F = struct {
        pub fn t() i32 {
            return 1;
        }

        pub fn u() !i32 {
            return 1;
        }
    };

    try expectEqual(i32, Result(F.t));
    try expectEqual(i32, Result(F.u));
}

test "expect `canBeError` to correctly identify if a function can return an error" {
    const F = struct {
        pub fn t() i32 {
            return 1;
        }

        pub fn u() !i32 {
            return 1;
        }

        pub fn e() anyerror {
            return error.Test;
        }
    };

    try expect(!canBeError(F.t));
    try expect(canBeError(F.u));
    try expect(canBeError(F.e));
}
