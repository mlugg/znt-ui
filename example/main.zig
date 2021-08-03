const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfz");
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
            .render = ui.RenderSystem.init(scene, .top_left),
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
        .context_version_major = 4,
        .context_version_minor = 5,
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

    try initUi(&scene);

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

fn initUi(scene: *Scene) !void {
    const margins = ui.Box.Margins{ .l = 10, .b = 10, .r = 10, .t = 10 };
    const root = try scene.add(.{
        .box = ui.Box.init(null, null, .{}),
        .rect = ui.Rect.init(.{ 1, 1, 0, 0.4 }, ui.boxRect),
    });

    const level1 = try scene.add(.{
        .box = ui.Box.init(root, null, .{
            .margins = margins,
            .direction = .col,
        }),
        .rect = ui.Rect.init(.{ 1, 0, 1, 0.4 }, ui.boxRect),
    });
    _ = try scene.add(.{
        .box = ui.Box.init(root, level1, .{
            .margins = margins,
            .grow = 0,
            .fill_cross = false,
            .min_size = .{ 400, 400 },
        }),
        .rect = ui.Rect.init(.{ 0, 1, 0, 0.4 }, ui.boxRect),
    });

    var box = try scene.add(.{
        .box = ui.Box.init(level1, null, .{
            .margins = margins,
            .grow = 0,
            .min_size = .{ 50, 50 },
        }),
        .rect = ui.Rect.init(.{ 0, 1, 1, 0.4 }, ui.boxRect),
    });
    box = try scene.add(.{
        .box = ui.Box.init(level1, box, .{
            .margins = margins,
            .fill_cross = false,
            .min_size = .{ 300, 50 },
        }),
        .rect = ui.Rect.init(.{ 0.5, 0.5, 1, 0.4 }, ui.boxRect),
    });
    box = try scene.add(.{
        .box = ui.Box.init(level1, box, .{
            .margins = margins,
            .grow = 0,
            .fill_cross = false,
            .min_size = .{ 100, 200 },
        }),
        .rect = ui.Rect.init(.{ 0.5, 0.5, 1, 0.4 }, ui.boxRect),
    });
}
