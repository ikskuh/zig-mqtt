const std = @import("std");

fn sdkRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const sdk_root = sdkRoot();

pub const include_path = sdk_root ++ "/vendor/mqtt-c/include";

pub fn createLibrary(b: *std.build.Builder) *std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("mqtt", null);
    lib.addCSourceFiles(&mqtt_c_sources, &.{});
    lib.addIncludePath(include_path);
    lib.linkLibC();
    return lib;
}

const mqtt_c_sources = [_][]const u8{
    sdk_root ++ "/vendor/mqtt-c/src/mqtt.c",
    sdk_root ++ "/vendor/mqtt-c/src/mqtt_pal.c",
};
