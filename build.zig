const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path("vendor/minisketch/include"));

    const minisketch = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    minisketch.addImport("c", translate_c.createModule());

    minisketch.linkSystemLibrary("c++", .{});
    minisketch.addCSourceFile(.{ .file = b.path("vendor/minisketch/src/minisketch.cpp"), .flags = &.{} });

    minisketch.addCSourceFile(.{ .file = b.path("vendor/minisketch/src/fields/generic_1byte.cpp"), .flags = &.{} });
    var i: usize = 2;
    while (i <= 8) : (i += 1) {
        var fname: [255]u8 = undefined;
        var w = std.Io.Writer.fixed(&fname);
        try w.print("vendor/minisketch/src/fields/generic_{}bytes.cpp", .{i});
        minisketch.addCSourceFile(.{ .file = b.path(w.buffered()), .flags = &.{} });
    }

    const main_tests = b.addTest(.{
        .root_module = minisketch,
    });

    const tests_run_step = b.addRunArtifact(main_tests);
    tests_run_step.has_side_effects = true;

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests_run_step.step);

    const test_tow = b.addExecutable(.{
        .name = "ish-test-tow",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ish-test-tow.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.default_step.dependOn(&test_tow.step);

    const run_tow = b.addRunArtifact(test_tow);
    run_tow.has_side_effects = true;
    const run_tow_step = b.step("test-tow", "Run ish-test-tow");
    run_tow_step.dependOn(&run_tow.step);
}
