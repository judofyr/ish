/// Implementation of Parity Bitmap Sketch: https://arxiv.org/pdf/2007.14569.pdf
const std = @import("std");

const hash = @import("./hash.zig");

const MiniSketch = @import("./MiniSketch.zig");

const small_seed = 5;
const big_seed = 6;

const Bucket = struct {
    xor_hash: u64,
    parity: u1,
};

pub const Settings = struct {
    const Self = @This();

    /// The estimated total number of changes.
    d: usize,

    /// The number of changes we want per partition in PBS.
    delta: usize = 5,

    /// n is the number of buckets we use in Small-PBS.
    logn: u6 = 8,

    /// Capacity of the codeword.
    t: usize = 7,

    pub fn partitionCount(self: Self) usize {
        return @maximum(self.d / self.delta, 1);
    }

    pub fn smallCodewordSize(self: Self) usize {
        return (self.logn * self.t + 7) / 8;
    }

    pub fn combinedCodewordsSize(self: Self) usize {
        return self.partitionCount() * self.smallCodewordSize();
    }
};

pub const SmallPBS = struct {
    const Self = @This();

    xor: []u64,
    parity: std.DynamicBitSetUnmanaged,

    pub fn init(allocator: std.mem.Allocator, settings: Settings) !Self {
        const n = (@as(usize, 1) << settings.logn) - 1;
        const xor = try allocator.alloc(u64, n);
        std.mem.set(u64, xor, 0);
        const parity = try std.DynamicBitSetUnmanaged.initEmpty(allocator, n);
        return Self{ .xor = xor, .parity = parity };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.xor);
        self.parity.deinit(allocator);
        self.* = undefined;
    }

    pub fn addOne(self: *Self, val: u64) void {
        const idx = hash.hashValue(val, small_seed) % self.xor.len;
        self.xor[idx] ^= val;
        self.parity.toggle(idx);
    }

    pub fn buildCodeword(self: *const Self, settings: Settings) MiniSketch {
        var m = MiniSketch.init(settings.logn, settings.t);

        var i: usize = 0;

        while (i < self.xor.len) : (i += 1) {
            if (self.parity.isSet(i)) {
                m.addOne(i + 1);
            }
        }

        return m;
    }

    pub fn xorForIdx(self: *const Self, idx: usize) u64 {
        return self.xor[idx - 1];
    }

    pub fn recoverXor(self: *const Self, idx: usize, xor: u64) ?u64 {
        const val = self.xor[idx - 1] ^ xor;
        const exp_idx = hash.hashValue(val, small_seed) % self.xor.len;
        if (exp_idx == idx - 1) {
            return val;
        }
        return null;
    }
};

pub const PBS = struct {
    const Self = @This();

    n: usize,
    xor: []u64,
    parity: std.DynamicBitSetUnmanaged,

    pub fn init(allocator: std.mem.Allocator, settings: Settings) !Self {
        const n = (@as(usize, 1) << settings.logn) - 1;
        const xor = try allocator.alloc(u64, n * settings.partitionCount());
        std.mem.set(u64, xor, 0);

        // n is always 2^m - 1 and 2^m is always a multiple of usize.
        // We add 1 here so that all the masks start at a sensible boundary.
        const parity = try std.DynamicBitSetUnmanaged.initEmpty(allocator, (n + 1) * settings.partitionCount());

        return Self{ .xor = xor, .parity = parity, .n = n };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.xor);
        self.parity.deinit(allocator);
        self.* = undefined;
    }

    fn partition(self: *const Self, idx: usize) SmallPBS {
        const xor_start = idx * self.n;
        const masks_start = (idx * (self.n + 1)) / @bitSizeOf(std.DynamicBitSetUnmanaged.MaskInt);
        const parity = std.DynamicBitSetUnmanaged{
            .bit_length = self.n,
            .masks = self.parity.masks + masks_start,
        };
        return SmallPBS{
            .xor = self.xor[xor_start..(xor_start + self.n)],
            .parity = parity,
        };
    }

    fn partitionCount(self: *const Self) usize {
        return self.xor.len / self.n;
    }

    pub fn addOne(self: *Self, val: u64) void {
        const idx = hash.hashValue(val, big_seed) % self.partitionCount();
        self.partition(idx).addOne(val);
    }

    pub fn buildCodewords(self: *const Self, settings: Settings, allocator: std.mem.Allocator) ![]MiniSketch {
        const count = self.partitionCount();
        var codewords = try allocator.alloc(MiniSketch, count);

        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            codewords[idx] = self.partition(idx).buildCodeword(settings);
        }
        return codewords;
    }

    pub fn freeCodewords(allocator: std.mem.Allocator, codewords: []MiniSketch) void {
        for (codewords) |*cw| {
            cw.deinit();
        }
        allocator.free(codewords);
    }

    /// Serializes the codewords. The target should have enough capacity for Settings.combinedCodewordsSize.
    pub fn serializeCodewords(codewords: []MiniSketch, target: *std.ArrayListUnmanaged(u8)) !void {
        for (codewords) |*cw| {
            try cw.serialize(target);
        }
    }

    pub fn deserializeCodewords(settings: Settings, allocator: std.mem.Allocator, target: *std.ArrayListUnmanaged(u8)) ![]MiniSketch {
        var codewords = try allocator.alloc(MiniSketch, settings.partitionCount());
        var idx: usize = 0;
        for (codewords) |*cw| {
            cw.* = MiniSketch.init(settings.logn, settings.t);
            try cw.deserialize(target.items[idx..]);
            idx += settings.smallCodewordSize();
        }
        return codewords;
    }

    /// Serializes the difference based on the codewords. Note that this will modify `codewords`.
    pub fn serializeDiff(self: *const Self, settings: Settings, allocator: std.mem.Allocator, codewords: []MiniSketch, other: []const MiniSketch, writer: anytype) !usize {
        var buf = try std.ArrayListUnmanaged(u64).initCapacity(allocator, settings.t);
        defer buf.deinit(allocator);

        var count: usize = 0;

        for (codewords) |*cw, idx| {
            buf.clearRetainingCapacity();
            try cw.merge(&other[idx]);

            cw.decode(&buf) catch {
                continue;
            };

            for (buf.items) |bucket_idx| {
                const xor_hash = self.partition(idx).xorForIdx(bucket_idx);
                try writer.writeIntLittle(u64, xor_hash);
                count += 1;
            }
        }

        return count;
    }

    /// Applies a serialized diff.
    /// Note that this will modify `codewords`.
    pub fn applyDiff(
        self: *Self,
        settings: Settings,
        allocator: std.mem.Allocator,
        codewords: []MiniSketch,
        other: []const MiniSketch,
        reader: anytype,
        cb: anytype,
    ) !usize {
        var buf = try std.ArrayListUnmanaged(u64).initCapacity(allocator, settings.t);
        defer buf.deinit(allocator);

        var count: usize = 0;

        for (codewords) |*cw, idx| {
            buf.clearRetainingCapacity();
            try cw.merge(&other[idx]);

            cw.decode(&buf) catch {
                continue;
            };

            for (buf.items) |bucket_idx| {
                const xor_hash = try reader.readIntLittle(u64);
                count += 1;

                const part = self.partition(idx);
                const val = part.recoverXor(bucket_idx, xor_hash) orelse continue;
                const exp_idx = hash.hashValue(val, big_seed) % self.partitionCount();
                if (exp_idx == idx) {
                    cb.call(val);
                }
            }
        }

        return count;
    }
};

const testing = std.testing;

test "small" {
    const s = Settings{ .d = 5 };

    var pbs1 = try SmallPBS.init(testing.allocator, s);
    defer pbs1.deinit(testing.allocator);

    var pbs2 = try SmallPBS.init(testing.allocator, s);
    defer pbs2.deinit(testing.allocator);

    var a: u64 = 100;
    var b: u64 = 1000;

    // Add all numbers from [a, b]
    while (a < b) : (a += 1) {
        pbs1.addOne(a);
        pbs2.addOne(a);
    }

    // Now add `d` more items to pbs2.
    while (a < b + s.d) : (a += 1) {
        pbs2.addOne(a);
    }

    var cw1 = pbs1.buildCodeword(s);
    defer cw1.deinit();

    var cw2 = pbs2.buildCodeword(s);
    defer cw2.deinit();

    var diff = try std.ArrayListUnmanaged(u64).initCapacity(testing.allocator, s.t);
    defer diff.deinit(testing.allocator);

    try cw1.merge(&cw2);
    try cw1.decode(&diff);
}

test "big" {
    const s = Settings{ .d = 1000, .t = 7 };

    var pbs1 = try PBS.init(testing.allocator, s);
    defer pbs1.deinit(testing.allocator);

    var pbs2 = try PBS.init(testing.allocator, s);
    defer pbs2.deinit(testing.allocator);

    var a: u64 = 100;
    var b: u64 = 10000;

    // Add all numbers from [a, b]
    while (a < b) : (a += 1) {
        pbs1.addOne(a);
        pbs2.addOne(a);
    }

    // Now add `d` more items to pbs2.
    while (a < b + s.d) : (a += 1) {
        pbs2.addOne(a);
    }

    // At 1: Build our codewords
    var cw1 = try pbs1.buildCodewords(s, testing.allocator);
    defer PBS.freeCodewords(testing.allocator, cw1);

    // 1: Build bytes.
    var cw1_bytes = try std.ArrayListUnmanaged(u8).initCapacity(testing.allocator, s.combinedCodewordsSize());
    defer cw1_bytes.deinit(testing.allocator);
    try PBS.serializeCodewords(cw1, &cw1_bytes);

    // 2: Build codewords
    var cw2 = try pbs2.buildCodewords(s, testing.allocator);
    defer PBS.freeCodewords(testing.allocator, cw2);

    // 2: Parse 1's codewords.
    var cw1_copy = try PBS.deserializeCodewords(s, testing.allocator, &cw1_bytes);
    defer PBS.freeCodewords(testing.allocator, cw1_copy);

    // 2: Build bytes.
    var cw2_bytes = try std.ArrayListUnmanaged(u8).initCapacity(testing.allocator, s.combinedCodewordsSize());
    defer cw2_bytes.deinit(testing.allocator);
    try PBS.serializeCodewords(cw2, &cw2_bytes);

    // 1: Parse 2's codewords.
    var cw2_copy = try PBS.deserializeCodewords(s, testing.allocator, &cw2_bytes);
    defer PBS.freeCodewords(testing.allocator, cw2_copy);

    // 1: Build diff.
    var diff_bytes = std.ArrayList(u8).init(testing.allocator);
    defer diff_bytes.deinit();
    const count1 = try pbs1.serializeDiff(s, testing.allocator, cw1, cw2_copy, diff_bytes.writer());

    // 2: Apply the diff.
    const cb = struct {
        pub fn call(self: @This(), val: u64) void {
            _ = self;
            _ = val;
            // std.debug.print("val={}\n", .{val});
        }
    };

    const reader = std.io.fixedBufferStream(diff_bytes.items).reader();
    const count2 = try pbs2.applyDiff(s, testing.allocator, cw2, cw1_copy, reader, cb{});

    // Now check that the count is equal on both sides.
    try testing.expectEqual(count1, count2);
}
