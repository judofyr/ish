// Run this with:
// zig run examples/est-set-diff.zig --main-pkg-path .

const std = @import("std");

const AutoTugOfWar = @import("../src/main.zig").tow.AutoTugOfWar;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var tow1 = try AutoTugOfWar(i32, i64).init(allocator, 64);
    defer tow1.deinit(allocator);

    var tow2 = try AutoTugOfWar(i32, i64).init(allocator, 64);
    defer tow2.deinit(allocator);

    // Store [1000, 7000] in the first
    var size1: usize = 0;
    var i: i64 = 1000;
    while (i < 7000) : (i += 1) {
        tow1.addOne(i);
        size1 += @sizeOf(@TypeOf(i));
    }

    // Store [3000, 10000] in the second
    var size2: usize = 0;
    i = 3000;
    while (i < 10000) : (i += 1) {
        tow2.addOne(i);
        size2 += @sizeOf(@TypeOf(i));
    }

    // This means that:
    // - 1000-2999 are only in the first.
    // - 3000-6999 are in both.
    // - 7000-9999 are only in the second.
    // Thus there are unique 6000 items.

    std.debug.print("First set would take {} bytes\n", .{size1});
    std.debug.print("Second set would take {} bytes\n", .{size2});

    const bytes_used = @sizeOf(i32) * tow2.counters.len;
    std.debug.print("Using {} bytes per sketch\n", .{bytes_used});

    // Calculate the number of different items.
    tow1.removeSketch(&tow2);
    const diff = tow1.meanOfSquares();
    std.debug.print("Estimated number of different items: {}\n", .{diff});
    std.debug.print("Exact number of different items: 6000\n", .{});
}
