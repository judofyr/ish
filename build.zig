const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // MiniSketch library
    const minisketch = b.addStaticLibrary("minisketch", null);
    minisketch.setBuildMode(mode);
    minisketch.setTarget(target);
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

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.setTarget(target);

    main_tests.addIncludeDir("vendor/minisketch/include");
    main_tests.linkLibrary(minisketch);

    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    if (coverage) {
        main_tests.setExecCmd(&[_]?[]const u8{
            "kcov",
            "kcov-output", // output dir for kcov
            null, // to get zig to use the --test-cmd-bin flag
        });
    }

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const test_tow = b.addExecutable("ish-test-tow", "src/test/ish-test-tow.zig");
    test_tow.setTarget(target);
    test_tow.setBuildMode(mode);
    test_tow.setMainPkgPath(".");
    test_tow.install();

    const run_tow = test_tow.run();
    const run_tow_step = b.step("test-tow", "Run ish-test-tow");
    run_tow_step.dependOn(&run_tow.step);
}
