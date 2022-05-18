# zig-mqtt

A build package for the awesome [mqtt-c](https://github.com/LiamBindle/MQTT-C) project by [Liam Bindle](https://github.com/LiamBindle).

Right now only provides a build script API in `Sdk.zig`, but might contain a Zig frontend in the future.

## Usage

```zig
const std = @import("std");
const Sdk = @import("Sdk.zig");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = Sdk.createLibrary(b);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();

    const exe = b.addExecutable(…);
    exe.linkLibary(lib);
    exe.addIncludePath(Sdk.include_path);
    …
}
```
