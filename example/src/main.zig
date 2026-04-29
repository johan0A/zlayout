const std = @import("std");
const rl = @import("raylib");
const zlayout = @import("zlayout");
const configs = zlayout.configs;
const Layout = zlayout.Layout;

const renderer = @import("renderer.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();

    rl.setConfigFlags(.{ .window_resizable = true });

    rl.initWindow(1200, 800, "Layout Demo");
    defer rl.closeWindow();

    var ui: Layout = .init(gpa);

    while (!rl.windowShouldClose()) {
        try demoLayout(&ui, @floatFromInt(rl.getRenderWidth()), @floatFromInt(rl.getRenderHeight()));
        try ui.calculateLayout();
        defer ui.clear();

        rl.beginDrawing();
        rl.clearBackground(rl.Color.init(20, 20, 20, 255));

        const mouse_x = rl.getMouseX();
        const mouse_y = rl.getMouseY();

        renderer.render(&ui, mouse_x, mouse_y);

        rl.endDrawing();
    }
}

fn testLayout(ui: *Layout) !void {
    _ = try ui.open(0, configs.Flex{
        .sizing = .{ .width = .fixed(1000), .height = .fit },
        .axis = .x,
        .padding = .all(10),
        .child_gap = 10,
        .child_alignment = .{ .y = .center },
    });
    defer ui.close();

    {
        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .fixed(300), .height = .fixed(300) },
            .axis = .y,
            .padding = .all(10),
            .child_gap = 10,
        });
        defer ui.close();

        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .fixed(300), .height = .fixed(300) },
            .axis = .y,
            .padding = .all(10),
            .child_gap = 10,
        });
        ui.close();
    }

    _ = try ui.open(0, configs.Flex{
        .sizing = .{ .width = .grow, .height = .grow },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    });
    ui.close();

    _ = try ui.open(0, configs.Flex{
        .sizing = .{ .width = .fixed(350), .height = .fixed(200) },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    });
    ui.close();

    _ = try ui.open(0, configs.Flex{
        .sizing = .{ .width = .grow, .height = .grow },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    });
    ui.close();
}

fn demoLayout(ui: *Layout, width: f32, height: f32) !void {
    _ = try ui.open(0, configs.Flex{
        .sizing = .{ .width = .fixed(width), .height = .fixed(height) },
        .axis = .y,
        .padding = .all(10),
        .child_gap = 10,
    });
    defer ui.close();

    {
        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .grow, .height = .fixed(60) },
            .axis = .x,
            .padding = .symmetric(20, 10),
            .child_gap = 20,
            .child_alignment = .{ .x = .left, .y = .center },
        });
        defer ui.close();

        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .fixed(40), .height = .fixed(40) },
        });
        ui.close();

        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .grow, .height = .growMinMax(0, 40) },
        });
        ui.close();

        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .fixed(40), .height = .fixed(40) },
        });
        ui.close();
    }

    {
        _ = try ui.open(0, configs.Flex{
            .sizing = .{ .width = .grow, .height = .grow },
            .axis = .x,
            .child_gap = 10,
        });
        defer ui.close();

        {
            _ = try ui.open(0, configs.Flex{
                .sizing = .{ .width = .fixed(200), .height = .grow },
                .axis = .y,
                .padding = .all(10),
                .child_gap = 8,
            });
            defer ui.close();

            // for ([_][]const u8{ "Dashboard", "Analytics", "Reports", "Settings", "Users", "Billing", "Help", "Logout" }) |label| {
            for (0..3) |_| {
                _ = try ui.open(0, configs.Flex{
                    .sizing = .{ .width = .grow, .height = .fixed(36) },
                    .padding = .symmetric(12, 8),
                    .child_alignment = .{ .y = .center },
                });
                defer ui.close();
            }
        }

        {
            _ = try ui.open(0, configs.Flex{
                .sizing = .{ .width = .grow, .height = .grow },
                .axis = .y,
                .padding = .all(20),
                .child_gap = 20,
            });
            defer ui.close();

            {
                _ = try ui.open(0, configs.Grid{});
                defer ui.close();

                for (0..10) |_| {
                    _ = try ui.open(0, configs.Flex{
                        .sizing = .{ .width = .fixed(36), .height = .fixed(62) },
                        .child_alignment = .{ .y = .center },
                    });
                    defer ui.close();
                }
            }

            {
                // _ = try ui.open(0, configs.Flex{
                //     .sizing = .{ .width = .grow, .height = .fit },
                //     .axis = .x,
                //     .child_gap = 20,
                // });
                // defer ui.close();

                {
                    // _ = try ui.open(0, configs.Flex{
                    //     .sizing = .{ .width = .grow, .height = .grow },
                    //     .axis = .y,
                    //     .padding = .all(16),
                    //     .child_gap = 12,
                    // });
                    // defer ui.close();

                    // _ = try ui.open(0, .{ .grid = .{
                    //     .child_gap = 8,
                    // });
                    // defer ui.close();

                    // for (0..15) |_| {
                    //     // _ = try ui.open(0, configs.Flex{
                    //     //     .sizing = .{ .width = .grow, .height = .fixed(48) },
                    //     //     .axis = .x,
                    //     //     .padding = .symmetric(12, 8),
                    //     //     .child_gap = 12,
                    //     //     .child_alignment = .{ .y = .center },
                    //     // });
                    //     // defer ui.close();

                    //     // _ = try ui.open(0, configs.Flex{
                    //     //     .sizing = .{ .width = .fixed(32), .height = .fixed(32) },
                    //     //     .padding = .all(16),
                    //     // });
                    //     // ui.close();

                    //     _ = try ui.open(0, configs.Flex{
                    //         .sizing = .{ .width = .fixed(32), .height = .fixed(32) },
                    //         .padding = .all(16),
                    //     });
                    //     ui.close();

                    //     // _ = try ui.open(0, configs.Flex{
                    //     //     .sizing = .{ .width = .grow },
                    //     //     .axis = .y,
                    //     //     .child_gap = 4,
                    //     // });
                    //     // ui.close();
                    // }
                }

                // _ = try ui.open(0, configs.Flex{
                //     .sizing = .{ .width = .fixed(250), .height = .grow },
                //     .axis = .y,
                //     .padding = .all(16),
                //     .child_gap = 16,
                // });
                // ui.close();
            }
        }
    }

    _ = try ui.open(0, configs.Flex{
        .sizing = .{ .width = .grow, .height = .fixed(40) },
        .axis = .x,
        .child_alignment = .{ .x = .center, .y = .center },
        .child_gap = 20,
    });
    ui.close();
}
