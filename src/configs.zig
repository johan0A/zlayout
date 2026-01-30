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

    fn axis(self: Padding, axis_: layout_mod.Axis) f32 {
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
    axis: layout_mod.Axis = .x,

    pub fn fitAxis(_: void, layout: anytype, handle: layout_mod.Handle, config: Flex, axis: layout_mod.Axis) void {
        const node = layout.get(handle);

        const sizing = switch (axis) {
            .x => config.sizing.width,
            .y => config.sizing.height,
        };

        const min_size = node.box.min_size.axis(axis);
        const max_size = node.box.max_size.axis(axis);
        const preferred_size = node.box.preferred_size.axis(axis);

        max_size.* = sizing.max;

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child = layout.get(child_handle);
            const child_min = child.box.min_size.axis(axis).*;
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
            .grow => max_size.*,
            .fixed => |s| s,
            .percent => @panic("TODO"),
        };
    }

    pub fn sizeAxis(_: void, layout: anytype, handle: layout_mod.Handle, config: Flex, axis: layout_mod.Axis) void {
        const parent = layout.get(handle);

        const parent_size = parent.box.size.axis(axis).*;
        const padding = config.padding.axis(axis);
        const available = parent_size - padding;

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child = layout.get(child_handle);
            const child_size = child.box.size.axis(axis);
            const child_preferred = child.box.preferred_size.axis(axis).*;

            if (config.axis != axis and child_size.* < child_preferred) {
                const child_min = child.box.min_size.axis(axis).*;
                child_size.* = @max(child_min, @min(available, child_preferred));
            }
        }

        if (config.axis != axis) return;

        var remaining = available;

        var child_count: usize = 0;
        var it1 = layout.children(handle);
        while (it1.next(layout)) |child_handle| {
            const child = layout.get(child_handle);
            child_count += 1;
            remaining -= child.box.size.axis(axis).*;
        }
        remaining -= @as(f32, @floatFromInt(child_count -| 1)) * config.child_gap;

        while (remaining > 0) {
            var size_to_add = remaining;
            var growable_count: usize = 0;

            var smallest = std.math.floatMax(f32);
            var second_smallest = std.math.floatMax(f32);
            var it2 = layout.children(handle);
            while (it2.next(layout)) |child_handle| {
                const child = layout.get(child_handle);

                const child_size = child.box.size.axis(axis).*;
                const child_preferred = child.box.preferred_size.axis(axis).*;

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
                const child = layout.get(child_handle);
                const child_size = child.box.size.axis(axis);
                if (child_size.* == smallest) {
                    child_size.* += size_to_add;
                    remaining -= size_to_add;
                }
            }
        }
    }

    pub fn position(_: void, layout: anytype, handle: layout_mod.Handle, config: Flex) void {
        const parent = layout.get(handle);
        const direction = config.axis;

        var main_offset = switch (direction) {
            .x => parent.box.pos.x + config.padding.left,
            .y => parent.box.pos.y + config.padding.top,
        };

        var it = layout.children(handle);
        while (it.next(layout)) |child_handle| {
            const child = layout.get(child_handle);

            switch (direction) {
                .x => {
                    child.box.pos.x = main_offset;
                    main_offset += child.box.size.width + config.child_gap;

                    const available_height = parent.box.size.height - config.padding.axis(.y);
                    const cross_offset = switch (config.child_alignment.y) {
                        .top => 0,
                        .center => (available_height - child.box.size.height) / 2,
                        .bottom => available_height - child.box.size.height,
                    };
                    child.box.pos.y = parent.box.pos.y + config.padding.top + cross_offset;
                },
                .y => {
                    child.box.pos.y = main_offset;
                    main_offset += child.box.size.height + config.child_gap;

                    const available_width = parent.box.size.width - config.padding.axis(.x);
                    const cross_offset = switch (config.child_alignment.x) {
                        .left => 0,
                        .center => (available_width - child.box.size.width) / 2,
                        .right => available_width - child.box.size.width,
                    };
                    child.box.pos.x = parent.box.pos.x + config.padding.left + cross_offset;
                },
            }
        }
    }
};

const layout_mod = @import("layout.zig");
const std = @import("std");
