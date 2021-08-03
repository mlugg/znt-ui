const std = @import("std");
const Deps = @import("Deps.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    var deps = Deps.init(b);
    deps.add("https://github.com/vktec/glfz", "main");
    deps.add("https://github.com/vktec/zgl", "master");
    deps.add("https://github.com/vktec/znt", "main");
    deps.add("https://github.com/vktec/znt-ui", "main");

    const exe = b.addExecutable("example", "main.zig");
    deps.addTo(exe);

    exe.linkLibC();
    exe.linkSystemLibrary("epoxy");
    exe.linkSystemLibrary("glfw3");

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
