const std = @import("std");
const assert = std.debug.assert;

const lib = @cImport({
    @cInclude("minisketch.h");
});

const Self = @This();

data: *lib.minisketch,

pub fn init(bits: u32, cap: usize) Self {
    return .{
        .data = lib.minisketch_create(bits, 0, cap) orelse unreachable,
    };
}

pub fn deinit(self: *Self) void {
    lib.minisketch_destroy(self.data);
    self.* = undefined;
}

pub fn addOne(self: *Self, value: u64) void {
    lib.minisketch_add_uint64(self.data, value);
}

pub fn merge(self: *Self, other: *const Self) !void {
    const res = lib.minisketch_merge(self.data, other.data);
    if (res == 0) {
        // The other sketch has different capacity than our
        return error.InvalidArgument;
    }
}

pub fn decode(self: *Self, target: *std.ArrayListUnmanaged(u64)) !void {
    var ptr: [*]u64 = @ptrCast(target.items);
    const res = lib.minisketch_decode(self.data, target.capacity, &ptr[target.items.len]);
    if (res == -1) {
        return error.DecodeError;
    }
    target.items.len += @intCast(res);
}

pub fn serializedSize(self: *Self) usize {
    return lib.minisketch_serialized_size(self.data);
}

/// Appends the sketch into the given target. This assumes that the target has
/// enough capacity to store the sketch.
pub fn serialize(self: *Self, target: *std.ArrayListUnmanaged(u8)) !void {
    const size = self.serializedSize();

    // We must have capacity for it.
    assert(target.capacity >= target.items.len + size);

    var start = target.items.len;
    var ptr: [*]u8 = @ptrCast(target.items);
    lib.minisketch_serialize(self.data, &ptr[start]);
    target.items.len += size;
}

pub fn deserialize(self: *Self, source: []const u8) !void {
    assert(source.len >= self.serializedSize());
    lib.minisketch_deserialize(self.data, @ptrCast(source));
}

const testing = std.testing;

test "basic" {
    const bits = 32;
    const t = 10;

    var a = Self.init(bits, t);
    defer a.deinit();

    var b = Self.init(bits, t);
    defer b.deinit();

    a.addOne(1);
    a.addOne(2);
    b.addOne(2);
    b.addOne(3);

    // Serialize
    var bytes = try std.ArrayListUnmanaged(u8).initCapacity(testing.allocator, b.serializedSize());
    defer bytes.deinit(testing.allocator);

    try a.serialize(&bytes);
    try testing.expect(bytes.items.len > 0);

    // Deserialize
    var a2 = Self.init(bits, t);
    defer a2.deinit();

    try a2.deserialize(bytes.items);

    // Decoding
    try a2.merge(&b);

    var diff = try std.ArrayListUnmanaged(u64).initCapacity(testing.allocator, 10);
    defer diff.deinit(testing.allocator);

    // Add one here to verify that decode actually _appends_.
    try diff.append(testing.allocator, 100);

    try a2.decode(&diff);

    try testing.expectEqual(@as(usize, 3), diff.items.len);

    try testing.expectEqual(@as(u64, 100), diff.items[0]);
    try testing.expectEqual(@as(u64, 1), diff.items[1]);
    try testing.expectEqual(@as(u64, 3), diff.items[2]);
}
