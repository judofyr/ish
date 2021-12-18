const std = @import("std");
const hash = @import("./hash.zig");

pub fn AutoTugOfWar(
    comptime CountType: type,
    comptime ValueType: type,
) type {
    return TugOfWar(CountType, ValueType, hash.AutoContext(ValueType));
}

/// Implementation of Alon, Matias, and Szegedy's classic "tug-of-war" sketch
/// as presented in "The space complexity of approximating the frequency moments".
pub fn TugOfWar(
    /// The type used per counter. Must be a signed integer.
    comptime CountType: type,
    /// The type of the values we're counting.
    comptime ValueType: type,
    /// Type of the context which provides the hashing function.
    comptime Context: type,
) type {
    return struct {
        const Self = @This();

        // List of counters.
        counters: []CountType,

        /// Context used for hashing.
        ctx: Context,

        pub fn init(allocator: std.mem.Allocator, count: usize) !Self {
            return initWithContext(allocator, count, .{});
        }

        pub fn initWithContext(allocator: std.mem.Allocator, count: usize, ctx: Context) !Self {
            const counters = try allocator.alloc(CountType, count);
            std.mem.set(CountType, counters, 0);
            return Self{ .counters = counters, .ctx = ctx };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.counters);
            self.* = undefined;
        }

        /// Adds a value to the sketch with a given count.
        pub fn addCount(self: *Self, val: ValueType, count: CountType) void {
            // The counter to update
            var i: usize = 0;
            // The seed to use for hashing
            var j: usize = 0;

            var h: u64 = undefined;

            while (i < self.counters.len) : (i += 1) {
                if (i % 64 == 0) {
                    h = self.ctx.hash(val, j);
                    j += 1;
                }

                if (h & 1 == 1) {
                    self.counters[i] += count;
                } else {
                    self.counters[i] -= count;
                }

                h >>= 1;
            }
        }

        pub fn addOne(self: *Self, val: ValueType) void {
            self.addCount(val, 1);
        }

        pub fn addSketch(self: *Self, other: *const Self) void {
            var i: usize = 0;
            while (i < self.counters.len) : (i += 1) {
                self.counters[i] += other.counters[i];
            }
        }

        pub fn removeOne(self: *Self, val: ValueType) void {
            self.addCount(val, -1);
        }

        pub fn removeCount(self: *Self, val: ValueType, count: CountType) void {
            self.addCount(val, -count);
        }

        pub fn removeSketch(self: *Self, other: *const Self) void {
            var i: usize = 0;
            while (i < self.counters.len) : (i += 1) {
                self.counters[i] -= other.counters[i];
            }
        }

        pub fn meanOfSquares(self: *const Self) CountType {
            var sum: CountType = 0;
            for (self.counters) |val| {
                sum += val * val;
            }
            return @divFloor(sum, @intCast(CountType, self.counters.len));
        }
    };
}

const testing = std.testing;

test "basic" {
    var t = try AutoTugOfWar(i64, i64).init(testing.allocator, 32);
    defer t.deinit(testing.allocator);

    t.addOne(@as(i64, 1));
    t.addOne(@as(i64, 10));
    t.addCount(@as(i64, 15), 5);
    _ = t.meanOfSquares();
}

test "custom hashing" {
    const V = struct {
        a: i64,
        b: i64,

        pub fn autoHash(self: @This(), hasher: anytype) void {
            std.hash.autoHash(hasher, self.a);
        }
    };

    var t = try AutoTugOfWar(i64, V).init(testing.allocator, 32);
    defer t.deinit(testing.allocator);

    // Since our hash function ignores `b` this should lead to an empty sketch.
    t.addOne(.{ .a = 0, .b = 1 });
    t.removeOne(.{ .a = 0, .b = 2 });

    try testing.expectEqual(@as(i64, 0), t.meanOfSquares());
}
