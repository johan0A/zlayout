const std = @import("std");
const rl = @import("raylib");
const layout_mod = @import("layout.zig");
const configs = @import("configs.zig");
const renderer_mod = @import("renderer.zig");

pub const Layout = layout_mod.Layout(union(enum) {
    flex: configs.Flex,
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    rl.setConfigFlags(.{ .window_resizable = true });

    rl.initWindow(1200, 800, "Layout Demo");
    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        var ui = Layout.init(gpa.allocator());
        defer ui.deinit();
        try demoLayout(&ui, @floatFromInt(rl.getRenderWidth()), @floatFromInt(rl.getRenderHeight()));
        try ui.calculateLayout();

        rl.beginDrawing();
        rl.clearBackground(rl.Color.init(20, 20, 20, 255));

        const mouse_x = rl.getMouseX();
        const mouse_y = rl.getMouseY();

        renderer_mod.render(&ui, mouse_x, mouse_y);

        rl.endDrawing();
    }
}

fn testLayout(ui: *Layout) !void {
    _ = try ui.open(.{ .flex = .{
        .sizing = .{ .width = .fixed(1000), .height = .fit },
        .axis = .x,
        .padding = .all(10),
        .child_gap = 10,
        .child_alignment = .{ .y = .center },
    } });
    defer ui.close();

    {
        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .fixed(300), .height = .fixed(300) },
            .axis = .y,
            .padding = .all(10),
            .child_gap = 10,
        } });
        defer ui.close();

        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .fixed(300), .height = .fixed(300) },
            .axis = .y,
            .padding = .all(10),
            .child_gap = 10,
        } });
        ui.close();
    }

    _ = try ui.open(.{ .flex = .{
        .sizing = .{ .width = .grow, .height = .grow },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    } });
    ui.close();

    _ = try ui.open(.{ .flex = .{
        .sizing = .{ .width = .fixed(350), .height = .fixed(200) },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    } });
    ui.close();

    _ = try ui.open(.{ .flex = .{
        .sizing = .{ .width = .grow, .height = .grow },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    } });
    ui.close();
}

fn demoLayout(ui: *Layout, width: f32, height: f32) !void {
    _ = try ui.open(.{ .flex = .{
        .sizing = .{ .width = .fixed(width), .height = .fixed(height) },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    } });
    defer ui.close();

    {
        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .grow, .height = .fixed(60) },
            .axis = .x,
            .padding = .symmetric(20, 10),
            .child_gap = 20,
            .child_alignment = .{ .x = .left, .y = .center },
        } });
        defer ui.close();

        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .fixed(40), .height = .fixed(40) },
        } });
        ui.close();

        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .grow, .height = .growMinMax(0, 40) },
        } });
        ui.close();

        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .fixed(40), .height = .fixed(40) },
        } });
        ui.close();
    }

    {
        _ = try ui.open(.{ .flex = .{
            .sizing = .{ .width = .grow, .height = .grow },
            .axis = .x,
            .child_gap = 10,
        } });
        defer ui.close();

        {
            _ = try ui.open(.{ .flex = .{
                .sizing = .{ .width = .fixed(200), .height = .grow },
                .axis = .y,
                .padding = .all(10),
                .child_gap = 8,
            } });
            defer ui.close();

            for ([_][]const u8{ "Dashboard", "Analytics", "Reports", "Settings", "Users", "Billing", "Help", "Logout" }) |label| {
                _ = label; // autofix
                _ = try ui.open(.{ .flex = .{
                    .sizing = .{ .width = .grow, .height = .fixed(36) },
                    .padding = .symmetric(12, 8),
                    .child_alignment = .{ .y = .center },
                } });
                defer ui.close();
            }
        }

        {
            _ = try ui.open(.{ .flex = .{
                .sizing = .{ .width = .grow, .height = .grow },
                .axis = .y,
                .padding = .all(20),
                .child_gap = 20,
            } });
            defer ui.close();

            {
                // _ = try ui.open(.{ .flex = .{
                //     .sizing = .{ .width = .grow, .height = .fit },
                //     .axis = .x,
                //     .child_gap = 20,
                // } });
                // defer ui.close();

                {
                    // _ = try ui.open(.{ .flex = .{
                    //     .sizing = .{ .width = .grow, .height = .grow },
                    //     .axis = .y,
                    //     .padding = .all(16),
                    //     .child_gap = 12,
                    // } });
                    // defer ui.close();

                    // _ = try ui.open(.{ .grid = .{
                    //     .child_gap = 8,
                    // } });
                    // defer ui.close();

                    // for (0..15) |_| {
                    //     // _ = try ui.open(.{ .flex = .{
                    //     //     .sizing = .{ .width = .grow, .height = .fixed(48) },
                    //     //     .axis = .x,
                    //     //     .padding = .symmetric(12, 8),
                    //     //     .child_gap = 12,
                    //     //     .child_alignment = .{ .y = .center },
                    //     // } });
                    //     // defer ui.close();

                    //     // _ = try ui.open(.{ .flex = .{
                    //     //     .sizing = .{ .width = .fixed(32), .height = .fixed(32) },
                    //     //     .padding = .all(16),
                    //     // } });
                    //     // ui.close();

                    //     _ = try ui.open(.{ .flex = .{
                    //         .sizing = .{ .width = .fixed(32), .height = .fixed(32) },
                    //         .padding = .all(16),
                    //     } });
                    //     ui.close();

                    //     // _ = try ui.open(.{ .flex = .{
                    //     //     .sizing = .{ .width = .grow },
                    //     //     .axis = .y,
                    //     //     .child_gap = 4,
                    //     // } });
                    //     // ui.close();
                    // }
                }

                // _ = try ui.open(.{ .flex = .{
                //     .sizing = .{ .width = .fixed(250), .height = .grow },
                //     .axis = .y,
                //     .padding = .all(16),
                //     .child_gap = 16,
                // } });
                // ui.close();
            }
        }
    }

    _ = try ui.open(.{ .flex = .{
        .sizing = .{ .width = .grow, .height = .fixed(40) },
        .axis = .x,
        .child_alignment = .{ .x = .center, .y = .center },
        .child_gap = 20,
    } });
    ui.close();
}
