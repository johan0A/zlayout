const std = @import("std");
const rl = @import("raylib");
const layout_mod = @import("layout.zig");
const Layout = @import("main.zig").Layout;
const Node = layout_mod.Node;
const configs = @import("configs.zig");

const SizingAxis = layout_mod.SizingAxis;
const Padding = layout_mod.Padding;

const depth_colors = [_]rl.Color{
    rl.Color.init(66, 135, 245, 255), // Blue
    rl.Color.init(102, 187, 106, 255), // Green
    rl.Color.init(255, 167, 38, 255), // Orange
    rl.Color.init(171, 71, 188, 255), // Purple
    rl.Color.init(239, 83, 80, 255), // Red
    rl.Color.init(38, 198, 218, 255), // Cyan
    rl.Color.init(255, 238, 88, 255), // Yellow
    rl.Color.init(141, 110, 99, 255), // Brown
};

const type_colors = struct {
    const flex = rl.Color.init(66, 135, 245, 255); // Blue
    const text = rl.Color.init(102, 187, 106, 255); // Green
    const scroll = rl.Color.init(255, 167, 38, 255); // Orange
    const grid = rl.Color.init(171, 71, 188, 255); // Purple
};

pub fn render(layout: *const Layout, mouse_x: i32, mouse_y: i32) void {
    var stack: [256]layout_mod.Handle = undefined;
    var stack_len: usize = 1;
    stack[0] = layout.root;

    while (stack_len > 0) {
        stack_len -= 1;
        const handle = stack[stack_len];
        const bb = layout.getBox(handle);

        const fill_color = getDepthColor(layout, handle);

        const x: i32 = @intFromFloat(bb.pos.x);
        const y: i32 = @intFromFloat(bb.pos.y);
        const w: i32 = @intFromFloat(@max(4, bb.size.width));
        const h: i32 = @intFromFloat(@max(4, bb.size.height));

        rl.drawRectangle(x, y, w, h, fill_color);

        rl.drawRectangleLinesEx(.{
            .x = bb.pos.x,
            .y = bb.pos.y,
            .width = bb.size.width,
            .height = bb.size.height,
        }, 1, rl.Color.black);

        // Draw element index
        if (bb.size.width > 10 and bb.size.height > 10) {
            var buf: [32]u8 = undefined;
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{@intFromEnum(handle)}) catch "?";
            rl.drawText(label, x + 3, y + 2, 13, rl.Color.black);
        }

        // Push children in reverse order so they render left-to-right
        var children: [256]layout_mod.Handle = undefined;
        var child_count: usize = 0;
        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            children[child_count] = child_handle;
            child_count += 1;
        }
        while (child_count > 0) {
            child_count -= 1;
            stack[stack_len] = children[child_count];
            stack_len += 1;
        }
    }

    // Hover highlight and tooltip
    if (findNodeAt(layout, mouse_x, mouse_y)) |hovered_handle| {
        const bb = layout.getBox(hovered_handle);

        rl.drawRectangleLinesEx(
            .{ .x = bb.pos.x, .y = bb.pos.y, .width = bb.size.width, .height = bb.size.height },
            3,
            rl.Color.yellow,
        );

        const node = layout.getNode(hovered_handle);
        drawNodeTooltip(layout, node, hovered_handle, mouse_x, mouse_y);
    }
}

fn getDepthColor(layout: *const Layout, handle: layout_mod.Handle) rl.Color {
    const depth = calculateDepth(layout, handle);
    return depth_colors[depth % depth_colors.len];
}

fn calculateDepth(layout: *const Layout, handle: layout_mod.Handle) u32 {
    var depth: u32 = 0;
    var parent = layout.getNode(handle).parent;
    while (parent != .none) {
        depth += 1;
        parent = layout.getNode(parent).parent;
    }
    return depth;
}

pub fn findNodeAt(layout: *const Layout, x: i32, y: i32) ?layout_mod.Handle {
    const fx: f32 = @floatFromInt(x);
    const fy: f32 = @floatFromInt(y);

    var result: ?layout_mod.Handle = null;

    var stack: [256]layout_mod.Handle = undefined;
    var stack_len: usize = 1;
    stack[0] = layout.root;

    while (stack_len > 0) {
        stack_len -= 1;
        const handle = stack[stack_len];
        const bb = layout.getBox(handle);

        if (fx >= bb.pos.x and fx < bb.pos.x + bb.size.width and
            fy >= bb.pos.y and fy < bb.pos.y + bb.size.height)
        {
            result = handle;

            // Check children (deeper nodes)
            var it = layout.children(handle);
            while (it.next(layout)) |child_handle| {
                stack[stack_len] = child_handle;
                stack_len += 1;
            }
        }
    }

    return result;
}

fn drawNodeTooltip(layout: *const Layout, node: *const Node, handle: layout_mod.Handle, x: i32, y: i32) void {
    var buff: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buff);
    const gpa = fba.allocator();

    const bb = node.box;
    const depth = calculateDepth(layout, handle);
    const idx = @intFromEnum(handle);

    var lines: std.ArrayList([:0]const u8) = .empty;

    // Basic info
    lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Node #{d}", .{idx}, 0) catch "?") catch {};
    lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Depth: {d}", .{depth}, 0) catch "?") catch {};
    lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Pos  : ({d:.0}, {d:.0})", .{ bb.pos.x, bb.pos.y }, 0) catch "?") catch {};
    lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Size : {d:.0} x {d:.0}", .{ bb.size.width, bb.size.height }, 0) catch "?") catch {};
    lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "min  : {d:.0} x {d:.0}", .{ @min(9999, bb.min_size.width), @min(9999, bb.min_size.height) }, 0) catch "?") catch {};

    // Config-specific info
    // lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Direction: {s}", .{@tagName(node.config.direction)}, 0) catch "?") catch {};
    // lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Childgap: {d}", .{node.config.child_gap}, 0) catch "?") catch {};
    // if (node.config.sizing.width.type != .fit or node.config.sizing.height.type != .fit) {
    //     lines.append(gpa, std.fmt.allocPrintSentinel(gpa, "Sizing: {s}/{s}", .{
    //         @tagName(node.config.sizing.width.type),
    //         @tagName(node.config.sizing.height.type),
    //     }, 0) catch "?") catch {};
    // }

    // Draw tooltip
    const line_height: i32 = 18;
    const tooltip_width: i32 = 150;
    const tooltip_height: i32 = @as(i32, @intCast(lines.items.len)) * line_height + 10;
    const tooltip_x = @min(x + 15, @as(i32, @intCast(rl.getScreenWidth())) - tooltip_width - 5);
    const tooltip_y = @min(y + 15, @as(i32, @intCast(rl.getScreenHeight())) - tooltip_height - 5);

    // Background
    rl.drawRectangle(tooltip_x, tooltip_y, tooltip_width, tooltip_height, rl.Color.init(30, 30, 30, 240));

    // Lines
    for (lines.items, 0..) |line, i| {
        const ly = tooltip_y + 5 + @as(i32, @intCast(i)) * line_height;
        rl.drawText(line, tooltip_x + 5, ly, 14, .white);
    }
}
