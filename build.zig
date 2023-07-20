const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // MiniSketch library
    const minisketch = b.addStaticLibrary(.{
        .name = "minisketch",
        .target = target,
        .optimize = optimize,
    });
    minisketch.linkLibCpp();
    minisketch.addCSourceFile("vendor/minisketch/src/minisketch.cpp", &.{});

    minisketch.addCSourceFile("vendor/minisketch/src/fields/generic_1byte.cpp", &.{});
    var i: usize = 2;
    while (i <= 8) : (i += 1) {
        var fname: [255]u8 = undefined;
        var stream = std.io.fixedBufferStream(&fname);
        try std.fmt.format(stream.writer(), "vendor/minisketch/src/fields/generic_{}bytes.cpp", .{i});
        minisketch.addCSourceFile(stream.getWritten(), &.{});
    }

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.addIncludePath("vendor/minisketch/include");
    main_tests.linkLibrary(minisketch);

    const tests_run_step = b.addRunArtifact(main_tests);
    tests_run_step.has_side_effects = true;

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests_run_step.step);

    const test_tow = b.addExecutable(.{
        .name = "ish-test-tow",
        .root_source_file = .{ .path = "src/test/ish-test-tow.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_tow.setMainPkgPath(".");
    b.default_step.dependOn(&test_tow.step);

    // const test_tow = b.addExecutable("ish-test-tow", "src/test/ish-test-tow.zig");
    // test_tow.setTarget(target);
    // test_tow.setBuildMode(mode);
    // test_tow.setMainPkgPath(".");
    // test_tow.install();

    const run_tow = b.addRunArtifact(test_tow);
    run_tow.has_side_effects = true;
    const run_tow_step = b.step("test-tow", "Run ish-test-tow");
    run_tow_step.dependOn(&run_tow.step);
}
