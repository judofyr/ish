const std = @import("std");

const tow = @import("./tug_of_war.zig");

pub const AutoTugOfWar = tow.AutoTugOfWar;
pub const TugOfWar = tow.TugOfWar;

pub const MiniSketch = @import("./minisketch.zig");

comptime {
    std.testing.refAllDecls(@This());
}
