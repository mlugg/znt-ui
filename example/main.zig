const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw.zig");
const ui = @import("znt-ui").ui(Scene);
const znt = @import("znt");

const Scene = znt.Scene(struct {
    box: ui.Box,
    rect: ui.Rect,
}, .{});
const Systems = struct {
    layout: ui.LayoutSystem,
    render: ui.RenderSystem,

    pub fn init(allocator: *std.mem.Allocator, scene: *Scene, viewport_size: [2]u31) Systems {
        return .{
            .layout = ui.LayoutSystem.init(allocator, scene, viewport_size),
            .render = ui.RenderSystem.init(scene),
        };
    }
    pub fn deinit(self: Systems) void {
        self.layout.deinit();
        self.render.deinit();
    }

    pub fn update(self: *Systems) !void {
        try self.layout.layout();
        self.render.render();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try glfw.init();
    const win = try glfw.Window.init(800, 600, "Hello, world!", .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = .core,
        .opengl_forward_compat = true,
    });
    defer win.deinit();
    win.makeContextCurrent();
    glfw.swapInterval(0); // Disable vsync

    var scene = Scene.init(&gpa.allocator);
    defer scene.deinit();
    var systems = Systems.init(
        std.heap.page_allocator,
        &scene,
        win.windowSize(),
    );
    defer systems.deinit();
    win.setUserPointer(&systems);

    const root = try scene.add(.{
        .box = ui.Box.init(null, null, .{}),
        .rect = ui.Rect.init(.{ 1, 1, 0, 0.4 }, ui.boxRect),
    });
    var box = try scene.add(.{
        .box = ui.Box.init(root, null, .{ .margins = .{
            .l = 100,
            .b = 50,
            .r = 200,
            .t = 100,
        }, .min_size = .{
            70, 50,
        } }),
        .rect = ui.Rect.init(.{ 1, 0, 1, 0.4 }, ui.boxRect),
    });
    box = try scene.add(.{
        .box = ui.Box.init(root, box, .{
            .grow = 0,
            .fill_cross = false,
            .min_size = .{ 100, 800 },
        }),
        .rect = ui.Rect.init(.{ 0, 1, 0, 0.4 }, ui.boxRect),
    });
    box = try scene.add(.{
        .box = ui.Box.init(root, box, .{ .margins = .{
            .l = 200,
            .b = 100,
            .r = 100,
            .t = 50,
        } }),
        .rect = ui.Rect.init(.{ 0, 1, 1, 0.4 }, ui.boxRect),
    });

    _ = win.setWindowSizeCallback(sizeCallback);
    _ = win.setFramebufferSizeCallback(fbSizeCallback);

    while (!win.shouldClose()) {
        gl.clearColor(0, 0, 0, 0);
        gl.clear(.{ .color = true });
        gl.enable(.blend);
        gl.blendFunc(.src_alpha, .one_minus_src_alpha);

        try systems.update();

        win.swapBuffers();
        glfw.waitEvents();
    }
}

fn sizeCallback(win: *glfw.Window, w: c_int, h: c_int) callconv(.C) void {
    const systems = win.getUserPointer(*Systems);
    systems.layout.setViewport(.{ @intCast(u31, w), @intCast(u31, h) });
}
fn fbSizeCallback(_: *glfw.Window, w: c_int, h: c_int) callconv(.C) void {
    gl.viewport(0, 0, @intCast(usize, w), @intCast(usize, h));
}
