# ish - Sketches for Zig

**ish** is a library written in [Zig](https://ziglang.org/) for _sketches_.
A sketch is a data structure which stores a summary of a data set using much less memory than the full data set.
This summary is only an approximation, but sometimes they can be surprisingly effective.

## Features

* **Tug of War**: Implementation of ["The Space Complexity of Approximating the Frequency Moments"](https://www.sciencedirect.com/science/article/pii/S0022000097915452) used for frequency moments (F^2), multiplicity queries, self-join size, and set difference.
* **MiniSketch**: Zig wrapper around [MiniSketch](https://github.com/sipa/minisketch) used for compact set reconciliation.
* **PBS**: Implementation of ["Space- and Computationally-Efficient Set Reconciliation via Parity Bitmap Sketch"](https://arxiv.org/pdf/2007.14569.pdf) used for compact set reconciliation.
  Scales better than MiniSketch for large number of differences (according to the paper).

## Examples

### Tug of War: Set difference

Here's a program which uses 256 bytes to summarize two sets (which actually have thousands of items).
Then these two sketches are used to estimate how many items are distinct between those two sets.
The estimated answer ends up with an error of ~2% which isn't too bad for merely 256 bytes!

```zig
// Run this with:
// zig run examples/est-set-diff.zig --main-pkg-path .

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
```

Output:

```
First set would take 48000 bytes
Second set would take 56000 bytes
Using 256 bytes per sketch
Estimated number of different items: 7316
Exact number of different items: 6000
```
