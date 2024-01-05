const std = @import("std");

const ToW = @import("main.zig").tow.AutoTugOfWar;

const allocator = std.heap.page_allocator;

const Exp = struct {
    // Number of counters
    n: usize,

    // Total number of elements
    m: i64,

    // Number of extra elements per sketch
    d: i64,

    // The key where we start
    k: i64,

    pub fn run(self: Exp) !Result {
        var a = try ToW(i64, i64).init(allocator, self.n);
        defer a.deinit(allocator);

        var b = try ToW(i64, i64).init(allocator, self.n);
        defer b.deinit(allocator);

        var i: i64 = 0;
        while (i < self.m) : (i += 1) {
            const val_a = self.k + i;
            a.addOne(val_a);
            const val_b = self.k + i - self.d;
            b.addOne(val_b);
        }

        // Remove the sketch
        a.removeSketch(&b);

        // Calculate diff
        const estimated = a.meanOfSquares();

        return Result{
            .expected = self.d * 2,
            .estimated = estimated,
        };
    }
};

const Result = struct {
    expected: i64,
    estimated: i64,

    pub fn err(self: Result) i64 {
        return self.estimated - self.expected;
    }

    pub fn relativeError(self: Result) f64 {
        const diff = @abs(@as(f64, @floatFromInt(self.estimated - self.expected)));
        return diff / @as(f64, @floatFromInt(self.expected));
    }
};

pub fn main() !void {
    // Run a simple experiment to estimate the difference between two sets.
    const exp: Exp = .{
        .n = 64,
        .d = 100000,
        .k = 10001,
        .m = 1000000,
    };
    const result = try exp.run();
    std.debug.print("RelErr={} exp={} est={}\n", .{ result.relativeError(), result.expected, result.estimated });
}
