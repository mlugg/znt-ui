const std = @import("std");
const znt = @import("znt");
const gl = @import("zgl");

pub fn ui(comptime Scene: type) type {
    return struct {
        const box_component = Scene.componentByType(Box);
        const rect_component = Scene.componentByType(Rect);

        /// The Box component specifies a tree of nested boxes that can be laid out by the LayoutSystem
        pub const Box = struct {
            parent: ?znt.EntityId, // Parent of this box
            sibling: ?znt.EntityId, // Previous sibling
            settings: Settings, // Box layout settings
            shape: RectShape = undefined, // Shape of the box, set by layout

            // Internal
            _visited: bool = false, // Has this box been processed yet?
            // Total growth of all children, or size of one growth unit, depending on what stage of layout we're at
            _grow_total_or_unit: f32 = undefined,
            _offset: f32 = undefined, // Current offset into the box

            pub const Relation = enum {
                parent,
                sibling,
            };
            pub const Settings = struct {
                direction: Direction = .row,
                grow: f32 = 1,
                fill_cross: bool = true,
                margins: Margins = .{},
                min_size: [2]usize = .{ 0, 0 },
                // TODO: minimum size function
            };
            pub const Direction = enum { row, col };
            pub const Margins = struct {
                l: usize = 0,
                b: usize = 0,
                r: usize = 0,
                t: usize = 0,
            };

            pub fn init(parent: ?znt.EntityId, sibling: ?znt.EntityId, settings: Settings) Box {
                return .{ .parent = parent, .sibling = sibling, .settings = settings };
            }
        };

        /// The Rect component displays a colored rectangle at a size and location specified by a callback
        pub const Rect = struct {
            color: [4]f32,
            shapeFn: fn (*Scene, znt.EntityId) RectShape,

            pub fn init(color: [4]f32, shapeFn: fn (*Scene, znt.EntityId) RectShape) Rect {
                return .{ .color = color, .shapeFn = shapeFn };
            }
        };
        pub const RectShape = struct {
            x: f32,
            y: f32,
            w: f32,
            h: f32,

            inline fn coord(self: *RectShape, axis: u1) *f32 {
                return switch (axis) {
                    0 => &self.x,
                    1 => &self.y,
                };
            }
            inline fn dim(self: *RectShape, axis: u1) *f32 {
                return switch (axis) {
                    0 => &self.w,
                    1 => &self.h,
                };
            }
        };

        const Renderer = struct {
            vao: gl.VertexArray,
            prog: gl.Program,
            u_color: ?u32,
            buf: gl.Buffer,
            origin: RenderSystem.Origin,

            pub fn init(origin: RenderSystem.Origin) Renderer {
                const vao = gl.VertexArray.create();
                vao.enableVertexAttribute(0);
                vao.attribFormat(0, 2, .float, false, 0);
                vao.attribBinding(0, 0);

                const buf = gl.Buffer.create();
                buf.storage([2]f32, 4, null, .{ .map_write = true });
                vao.vertexBuffer(0, buf, 0, @sizeOf([2]f32));

                const prog = createProgram();
                const u_color = prog.uniformLocation("u_color");

                return .{
                    .vao = vao,
                    .prog = prog,
                    .u_color = u_color,
                    .buf = buf,
                    .origin = origin,
                };
            }

            pub fn deinit(self: Renderer) void {
                self.vao.delete();
                self.prog.delete();
                self.buf.delete();
            }

            fn createProgram() gl.Program {
                const vert = gl.Shader.create(.vertex);
                defer vert.delete();
                vert.source(1, &.{
                    \\  #version 330
                    \\  layout(location = 0) in vec2 pos;
                    \\  void main() {
                    \\      gl_Position = vec4(pos, 0, 1);
                    \\  }
                });
                vert.compile();
                if (vert.get(.compile_status) == 0) {
                    std.debug.panic("Vertex shader compilation failed:\n{s}\n", .{vert.getCompileLog(std.heap.page_allocator)});
                }

                const frag = gl.Shader.create(.fragment);
                defer frag.delete();
                frag.source(1, &.{
                    \\  #version 330
                    \\  uniform vec4 u_color;
                    \\  out vec4 f_color;
                    \\  void main() {
                    \\      f_color = u_color;
                    \\  }
                });
                frag.compile();
                if (frag.get(.compile_status) == 0) {
                    std.debug.panic("Fragment shader compilation failed:\n{s}\n", .{frag.getCompileLog(std.heap.page_allocator)});
                }

                const prog = gl.Program.create();
                prog.attach(vert);
                defer prog.detach(vert);
                prog.attach(frag);
                defer prog.detach(frag);
                prog.link();
                if (prog.get(.link_status) == 0) {
                    std.debug.panic("Shader linking failed:\n{s}\n", .{frag.getCompileLog(std.heap.page_allocator)});
                }
                return prog;
            }

            // TODO: use multidraw
            // TODO: use persistent mappings

            pub fn drawRect(self: *Renderer, rect: RectShape, color: [4]f32) void {
                self.prog.uniform4f(self.u_color, color[0], color[1], color[2], color[3]);

                while (true) {
                    const buf = self.buf.mapRange([2]gl.Float, 0, 4, .{ .write = true });
                    buf[0] = self.coord(.{ rect.x, rect.y });
                    buf[1] = self.coord(.{ rect.x, rect.y + rect.h });
                    buf[2] = self.coord(.{ rect.x + rect.w, rect.y });
                    buf[3] = self.coord(.{ rect.x + rect.w, rect.y + rect.h });
                    if (self.buf.unmap()) break;
                }

                self.vao.bind();
                self.prog.use();
                gl.drawArrays(.triangle_strip, 0, 4);
            }

            /// Origin-adjust a coordinate
            fn coord(self: Renderer, input_coord: [2]gl.Float) [2]gl.Float {
                var c = input_coord;
                switch (self.origin) {
                    .bottom_left => {}, // Nothing to do
                    .bottom_right => c[0] = -c[0], // Flip X
                    .top_left => c[1] = -c[1], // Flip Y
                    .top_right => { // Flip X and Y
                        c[0] = -c[0];
                        c[1] = -c[1];
                    },
                }
                return c;
            }
        };

        /// boxRect is a Rect callback that takes the size and location from a Box component
        pub fn boxRect(scene: *Scene, eid: znt.EntityId) RectShape {
            const box = scene.getOne(box_component, eid).?;
            return box.shape;
        }

        /// The LayoutSystem arranges a tree of nested boxes according to their constraints
        pub const LayoutSystem = struct {
            s: *Scene,
            boxes: std.ArrayList(*Box),
            view_scale: [2]f32, // Viewport scale

            // Viewport width and height should be in screen units, not pixels
            pub fn init(allocator: *std.mem.Allocator, scene: *Scene, viewport_size: [2]u31) LayoutSystem {
                var self = LayoutSystem{
                    .s = scene,
                    .boxes = std.ArrayList(*Box).init(allocator),
                    .view_scale = undefined,
                };
                self.setViewport(viewport_size);
                return self;
            }
            pub fn deinit(self: LayoutSystem) void {
                self.boxes.deinit();
            }

            pub fn setViewport(self: *LayoutSystem, size: [2]u31) void {
                self.view_scale = .{
                    2.0 / @intToFloat(f32, size[0]),
                    2.0 / @intToFloat(f32, size[1]),
                };
            }

            pub fn layout(self: *LayoutSystem) std.mem.Allocator.Error!void {
                // Collect all boxes, parents before children
                // We also reset every box to a zero shape during this process
                try self.resetAndCollectBoxes();

                // Compute minimum sizes
                // Iterate backwards so we compute child sizes before fitting parents around them
                var i = self.boxes.items.len;
                while (i > 0) {
                    i -= 1;
                    const box = self.boxes.items[i];
                    self.layoutMin(box);
                }

                // Compute layout
                // Iterate forwards so we compute parent capacities before fitting children to them
                for (self.boxes.items) |box| {
                    self.layoutFull(box);
                    box._visited = false; // Reset the visited flag while we're here
                }
            }

            /// Collect the scene's boxes into the box list, with parents before children, and siblings in order
            /// Also resets boxes in preparation for layout
            fn resetAndCollectBoxes(self: *LayoutSystem) !void {
                self.boxes.clearRetainingCapacity();
                try self.boxes.ensureTotalCapacity(self.s.count(box_component));

                var have_root = false;

                var iter = self.s.iter(&.{box_component});
                var entity = iter.next() orelse return;
                while (true) {
                    var box = @field(entity, @tagName(box_component));

                    // Reset and append the box, followed by all siblings and parents
                    const start = self.boxes.items.len;
                    while (!box._visited) {
                        box._visited = true; // Tag as visited

                        // Reset box
                        box.shape = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
                        box._grow_total_or_unit = 0;
                        box._offset = 0;

                        self.boxes.appendAssumeCapacity(box);

                        if (box.sibling) |id| {
                            const sibling = self.s.getOne(box_component, id).?;
                            // TODO: cycle detection
                            std.debug.assert(sibling.parent.? == box.parent.?);
                            box = sibling;
                        } else if (box.parent) |id| {
                            // TODO: detect more than one first child
                            box = self.s.getOne(box_component, id).?;
                        } else {
                            std.debug.assert(!have_root); // There can only be one root box
                            have_root = true;
                            break;
                        }
                    }

                    // Then reverse the appended data to put the parents first
                    std.mem.reverse(*Box, self.boxes.items[start..]);

                    entity = iter.next() orelse break;
                }

                std.debug.assert(have_root); // There must be one root box if there are any boxes
                std.debug.assert(self.boxes.items[0].parent == null); // All boxes must be descendants of the root box
            }

            /// Layout a box at its minimum size, in preparation for full layout.
            /// All children must have been laid out by this function beforehand.
            fn layoutMin(self: LayoutSystem, box: *Box) void {
                // Compute minimum size
                const minw = self.view_scale[0] * @intToFloat(f32, box.settings.min_size[0]);
                const minh = self.view_scale[1] * @intToFloat(f32, box.settings.min_size[1]);
                box.shape.w = std.math.max(box.shape.w, minw);
                box.shape.h = std.math.max(box.shape.h, minh);

                if (box.parent) |parent_id| {
                    const parent = self.s.getOne(box_component, parent_id).?;

                    // Add to parent minsize
                    const outer_size = self.pad(.out, box.shape, box.settings.margins);
                    switch (parent.settings.direction) {
                        .row => {
                            parent.shape.w += outer_size.w;
                            parent.shape.h = std.math.max(parent.shape.h, outer_size.h);
                        },
                        .col => {
                            parent.shape.w = std.math.max(parent.shape.w, outer_size.w);
                            parent.shape.h += outer_size.h;
                        },
                    }

                    // Compute grow total (for second pass)
                    parent._grow_total_or_unit += box.settings.grow;
                }
            }

            /// Layout a box at its full size.
            /// All parents and prior siblings must have been laid out by this function beforehand.
            fn layoutFull(self: LayoutSystem, box: *Box) void {
                // Default shape is OpenGL full screen plane, padded inwards by margin
                var shape = self.pad(.in, .{ .x = -1, .y = -1, .w = 2, .h = 2 }, box.settings.margins);
                if (box.parent) |parent_id| {
                    const parent = self.s.getOne(box_component, parent_id).?;

                    const main_axis = @enumToInt(parent.settings.direction);
                    const cross_axis = 1 - main_axis;

                    const main_growth = box.settings.grow * parent._grow_total_or_unit;
                    const main_size = box.shape.dim(main_axis).* + main_growth;

                    shape = self.pad(.in, parent.shape, box.settings.margins); // Compute initial shape
                    shape.dim(main_axis).* = std.math.max(0, main_size); // Replace main axis size
                    shape.coord(main_axis).* += parent._offset; // Adjust main axis position
                    if (!box.settings.fill_cross) { // If we're not filling cross axis, replace with min cross size
                        shape.dim(cross_axis).* = box.shape.dim(cross_axis).*;
                    }

                    // Advance parent offset
                    parent._offset += self.pad(.out, shape, box.settings.margins).dim(main_axis).*;
                }

                const child_main_axis = @enumToInt(box.settings.direction);
                const extra_space = shape.dim(child_main_axis).* - box.shape.dim(child_main_axis).*;
                if (box._grow_total_or_unit != 0) {
                    box._grow_total_or_unit = std.math.max(0, extra_space) / box._grow_total_or_unit;
                }
                box.shape = shape;
            }

            const PaddingSide = enum { in, out };
            fn pad(self: LayoutSystem, comptime side: PaddingSide, rect: RectShape, margins: Box.Margins) RectShape {
                const mx = self.view_scale[0] * @intToFloat(f32, margins.l);
                const my = self.view_scale[1] * @intToFloat(f32, margins.b);
                const mw = self.view_scale[0] * @intToFloat(f32, margins.l + margins.r);
                const mh = self.view_scale[1] * @intToFloat(f32, margins.b + margins.t);

                return switch (side) {
                    .in => .{
                        .x = rect.x + mx,
                        .y = rect.y + my,
                        .w = std.math.max(0, rect.w - mw),
                        .h = std.math.max(0, rect.h - mh),
                    },
                    .out => .{
                        .x = rect.x - mx,
                        .y = rect.y - my,
                        .w = rect.w + mw,
                        .h = rect.h + mh,
                    },
                };
            }
        };

        /// The RenderSystem draws Rects to an OpenGL context
        pub const RenderSystem = struct {
            s: *Scene,
            renderer: Renderer,

            pub const Origin = enum {
                top_left,
                top_right,
                bottom_left,
                bottom_right,
            };

            pub fn init(scene: *Scene, origin: Origin) RenderSystem {
                return .{ .s = scene, .renderer = Renderer.init(origin) };
            }
            pub fn deinit(self: RenderSystem) void {
                self.renderer.deinit();
            }

            pub fn render(self: *RenderSystem) void {
                var iter = self.s.iter(&.{rect_component});
                while (iter.next()) |entity| {
                    const rect = @field(entity, @tagName(rect_component));
                    var shape = rect.shapeFn(self.s, entity.id);
                    self.renderer.drawRect(shape, rect.color);
                }
            }
        };
    };
}
