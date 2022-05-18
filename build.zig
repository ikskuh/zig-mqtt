const std = @import("std");
const Sdk = @import("Sdk.zig");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = Sdk.createLibrary(b);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();
}
