pub const AlignX = enum { left, center, right };
pub const AlignY = enum { top, center, bottom };

pub const SizingType = union(enum) {
    fit: void,
    grow: void,
    percent: f32,
    fixed: f32,
};

pub const SizingAxis = struct {
    type: SizingType = .fit,
    min: f32 = 0,
    max: f32 = std.math.floatMax(f32),

    pub const fit: SizingAxis = .{ .type = .fit };
    pub const grow: SizingAxis = .{ .type = .grow };

    pub fn fixed(size: f32) SizingAxis {
        return .{ .type = .{ .fixed = size }, .min = size, .max = size };
    }
    pub fn growMinMax(min_val: f32, max_val: f32) SizingAxis {
        return .{ .type = .grow, .min = min_val, .max = if (max_val == 0) std.math.floatMax(f32) else max_val };
    }
    pub fn fitMinMax(min_val: f32, max_val: f32) SizingAxis {
        return .{ .type = .fit, .min = min_val, .max = if (max_val == 0) std.math.floatMax(f32) else max_val };
    }
    pub fn percent(pct: f32) SizingAxis {
        return .{ .type = .{ .percent = pct } };
    }
};

pub const Sizing = struct {
    width: SizingAxis = .{},
    height: SizingAxis = .{},
};

pub const Padding = struct {
    left: f32 = 0,
    right: f32 = 0,
    top: f32 = 0,
    bottom: f32 = 0,

    pub fn all(v: f32) Padding {
        return .{ .left = v, .right = v, .top = v, .bottom = v };
    }
    pub fn symmetric(h: f32, v: f32) Padding {
        return .{ .left = h, .right = h, .top = v, .bottom = v };
    }

    fn axis(self: Padding, axis_: zlayout.Axis) f32 {
        return switch (axis_) {
            .x => self.left + self.right,
            .y => self.top + self.bottom,
        };
    }
};

pub const ChildAlignment = struct { x: AlignX = .left, y: AlignY = .top };

pub const Flex = struct {
    sizing: Sizing = .{},
    padding: Padding = .{},
    child_gap: f32 = 0,
    child_alignment: ChildAlignment = .{},
    /// x => left to right
    /// y => top to bottom
    axis: zlayout.Axis = .x,

    pub fn fitAxis(layout: *const Layout, handle: zlayout.Handle, config: *const Flex, axis: zlayout.Axis) void {
        const box = &layout.getNode(handle).box;

        const sizing = switch (axis) {
            .x => config.sizing.width,
            .y => config.sizing.height,
        };

        const min_size = box.min_size.axis(axis);
        const preferred_size = box.preferred_size.axis(axis);
        const max_size = box.max_size.axis(axis);

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child_min = layout.getNodeMinSize(child_handle, axis);
            if (config.axis == axis) {
                min_size.* += child_min;
            } else {
                min_size.* = @max(min_size.*, child_min);
            }
        }

        const padding = config.padding.axis(axis);
        const gap_sum = if (config.axis == axis) @as(f32, @floatFromInt(layout.childCount(handle) -| 1)) * config.child_gap else 0;

        min_size.* += padding + gap_sum;
        min_size.* = std.math.clamp(min_size.*, sizing.min, sizing.max);

        preferred_size.* = switch (sizing.type) {
            .fit => min_size.*,
            .grow => sizing.max,
            .fixed => |s| s,
            .percent => @panic("TODO"),
        };

        max_size.* = switch (sizing.type) {
            .fit => min_size.*,
            .grow => sizing.max,
            .fixed => |s| s,
            .percent => @panic("TODO"),
        };
    }

    pub fn sizeAxis(layout: *const Layout, handle: zlayout.Handle, config: *const Flex, axis: zlayout.Axis) void {
        const parent = &layout.getNode(handle).box;

        const parent_size = parent.size.axis(axis).*;
        const padding = config.padding.axis(axis);
        const available = parent_size - padding;

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child = &layout.getNode(child_handle).box;
            const child_size = child.size.axis(axis);
            const child_min = layout.getNodeMinSize(child_handle, axis);
            const child_preferred = layout.getNodePreferedSize(child_handle, axis);

            if (config.axis == axis) {
                child_size.* = child_min;
            } else if (child_size.* < child_preferred) {
                child_size.* = @max(child_min, @min(available, child_preferred));
            }
        }

        if (config.axis != axis) return;

        var remaining = available;

        var child_count: usize = 0;
        var it1 = layout.children(handle);
        while (it1.next(layout)) |child_handle| {
            const child = &layout.getNode(child_handle).box;
            child_count += 1;
            remaining -= child.size.axis(axis).*;
        }
        remaining -= @as(f32, @floatFromInt(child_count -| 1)) * config.child_gap;

        while (remaining > 0) {
            var size_to_add = remaining;
            var growable_count: usize = 0;

            var smallest = std.math.floatMax(f32);
            var second_smallest = std.math.floatMax(f32);
            var it2 = layout.children(handle);
            while (it2.next(layout)) |child_handle| {
                const child = &layout.getNode(child_handle).box;
                const child_size = child.size.axis(axis).*;

                const child_preferred = layout.getNodePreferedSize(child_handle, axis);

                if (child_size >= child_preferred) continue;
                growable_count += 1;

                if (child_size < smallest) {
                    second_smallest = smallest;
                    smallest = child_size;
                }
                if (child_size > smallest) {
                    second_smallest = @min(second_smallest, child_size);
                    size_to_add = second_smallest - smallest;
                }
            }

            if (growable_count == 0) break;

            size_to_add = @min(size_to_add, remaining / @as(f32, @floatFromInt(growable_count)));

            var it3 = layout.children(handle);
            while (it3.next(layout)) |child_handle| {
                const child = &layout.getNode(child_handle).box;
                const child_size = child.size.axis(axis);
                if (child_size.* == smallest) {
                    child_size.* += size_to_add;
                    remaining -= size_to_add;
                }
            }
        }
    }

    pub fn position(layout: *const Layout, handle: zlayout.Handle, config: *const Flex) void {
        const parent = &layout.getNode(handle).box;
        const direction = config.axis;

        var main_offset = switch (direction) {
            .x => parent.pos.x + config.padding.left,
            .y => parent.pos.y + config.padding.top,
        };

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child = &layout.getNode(child_handle).box;

            switch (direction) {
                .x => {
                    child.pos.x = main_offset;
                    main_offset += child.size.width + config.child_gap;

                    const available_height = parent.size.height - config.padding.axis(.y);
                    const cross_offset = switch (config.child_alignment.y) {
                        .top => 0,
                        .center => (available_height - child.size.height) / 2,
                        .bottom => available_height - child.size.height,
                    };
                    child.pos.y = parent.pos.y + config.padding.top + cross_offset;
                },
                .y => {
                    child.pos.y = main_offset;
                    main_offset += child.size.height + config.child_gap;

                    const available_width = parent.size.width - config.padding.axis(.x);
                    const cross_offset = switch (config.child_alignment.x) {
                        .left => 0,
                        .center => (available_width - child.size.width) / 2,
                        .right => available_width - child.size.width,
                    };
                    child.pos.x = parent.pos.x + config.padding.left + cross_offset;
                },
            }
        }
    }
};

pub const Grid = struct {
    fn cellSize(layout: *const Layout, handle: zlayout.Handle, axis: zlayout.Axis) f32 {
        var max_size: f32 = 0;
        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child_min = layout.getNodeMinSize(child_handle, axis);
            max_size = @max(max_size, child_min);
        }
        return max_size;
    }

    pub fn fitAxis(layout: *const Layout, handle: zlayout.Handle, config: *const Grid, axis: zlayout.Axis) void {
        _ = config;
        const box = &layout.getNode(handle).box;
        const min_size = box.min_size.axis(axis);
        const preferred_size = box.preferred_size.axis(axis);
        const max_size = box.max_size.axis(axis);

        const cell = cellSize(layout, handle, axis);
        const count: f32 = @floatFromInt(layout.childCount(handle));

        switch (axis) {
            .x => {
                min_size.* = cell;
                preferred_size.* = cell * count;
                max_size.* = cell * count;
            },
            .y => {
                const cell_x = cellSize(layout, handle, .x);
                const width = box.size.axis(.x).*;
                const cols: f32 = if (cell_x > 0 and width >= cell_x) @floor(width / cell_x) else 1;
                const rows = @ceil(count / cols);
                min_size.* = cell * rows;
                preferred_size.* = cell * rows;
                max_size.* = cell * rows;
            },
        }
    }

    pub fn sizeAxis(layout: *const Layout, handle: zlayout.Handle, config: *const Grid, axis: zlayout.Axis) void {
        _ = config;
        const cell = cellSize(layout, handle, axis);

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child = &layout.getNode(child_handle).box;
            child.size.axis(axis).* = cell;
        }
    }

    pub fn position(layout: *const Layout, handle: zlayout.Handle, config: *const Grid) void {
        _ = config;
        const parent = &layout.getNode(handle).box;

        const cell_x = cellSize(layout, handle, .x);
        const cell_y = cellSize(layout, handle, .y);

        if (cell_x <= 0 or cell_y <= 0) return;

        const cols_per_row: u32 = @max(1, @as(u32, @intFromFloat(@floor(parent.size.width / cell_x))));

        var i: u32 = 0;
        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| : (i += 1) {
            const child = &layout.getNode(child_handle).box;
            const row = i / cols_per_row;
            const col = i % cols_per_row;
            child.pos.x = parent.pos.x + @as(f32, @floatFromInt(col)) * cell_x;
            child.pos.y = parent.pos.y + @as(f32, @floatFromInt(row)) * cell_y;
        }
    }
};

const std = @import("std");

const zlayout = @import("root.zig");
const Layout = zlayout.Layout;
