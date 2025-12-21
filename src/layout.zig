const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_float = std.math.floatMax(f32);

pub const Position = struct {
    x: f32,
    y: f32,
};

pub const Size = struct {
    width: f32,
    height: f32,

    pub fn axis(self: *Size, a: Axis) *f32 {
        return switch (a) {
            .y => &self.height,
            .x => &self.width,
        };
    }
};

pub const Box = struct {
    pos: Position,
    size: Size,
    preferred_size: Size,
    min_size: Size,
    max_size: Size,

    pub const zero: Box = .{
        .pos = .{ .x = 0, .y = 0 },
        .size = .{ .width = 0, .height = 0 },
        .preferred_size = .{ .width = 0, .height = 0 },
        .min_size = .{ .width = 0, .height = 0 },
        .max_size = .{ .width = 0, .height = 0 },
    };
};

pub const Axis = enum { x, y };
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
    max: f32 = max_float,

    pub const fit: SizingAxis = .{ .type = .fit };
    pub const grow: SizingAxis = .{ .type = .grow };

    pub fn fixed(size: f32) SizingAxis {
        return .{ .type = .{ .fixed = size }, .min = size, .max = size };
    }
    pub fn growMinMax(min_val: f32, max_val: f32) SizingAxis {
        return .{ .type = .grow, .min = min_val, .max = if (max_val == 0) max_float else max_val };
    }
    pub fn fitMinMax(min_val: f32, max_val: f32) SizingAxis {
        return .{ .type = .fit, .min = min_val, .max = if (max_val == 0) max_float else max_val };
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

    fn axis(self: Padding, axis_: Axis) f32 {
        return switch (axis_) {
            .x => self.left + self.right,
            .y => self.top + self.bottom,
        };
    }
};

pub const ChildAlignment = struct { x: AlignX = .left, y: AlignY = .top };

pub const LayoutConfig = struct {
    sizing: Sizing = .{},
    padding: Padding = .{},
    child_gap: f32 = 0,
    child_alignment: ChildAlignment = .{},
    direction: Axis = .x,
};

pub const Node = struct {
    parent: Handle,
    first_child: Handle,
    last_child: Handle,
    next_sibling: Handle,
    config: LayoutConfig,
    box: Box,

    pub const Handle = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn from(idx: u32) Handle {
            return @enumFromInt(idx);
        }
    };
};

pub const ChildIterator = struct {
    current: Node.Handle,

    pub fn next(self: *ChildIterator, layout: *const Layout) ?Node.Handle {
        if (self.current == .none) return null;
        const handle = self.current;
        self.current = layout.get(handle).next_sibling;
        return handle;
    }
};

pub const Layout = struct {
    gpa: Allocator,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    free: std.ArrayListUnmanaged(Node.Handle) = .empty,
    open_stack: std.ArrayListUnmanaged(Node.Handle) = .empty,
    root: Node.Handle = .none,

    pub fn init(gpa: Allocator) Layout {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Layout) void {
        self.nodes.deinit(self.gpa);
        self.free.deinit(self.gpa);
        self.open_stack.deinit(self.gpa);
    }

    pub fn clear(self: *Layout) void {
        self.nodes.clearRetainingCapacity();
        self.free.clearRetainingCapacity();
        self.open_stack.clearRetainingCapacity();
        self.root = .none;
    }

    fn insert(self: *Layout, node: Node) !Node.Handle {
        if (self.free.pop()) |handle| {
            self.nodes.items[@intFromEnum(handle)] = node;
            return handle;
        }
        try self.nodes.append(self.gpa, node);
        return Node.Handle.from(@intCast(self.nodes.items.len - 1));
    }

    pub fn remove(self: *Layout, handle: Node.Handle) !void {
        self.get(handle).* = undefined;
        try self.free.append(self.gpa, handle);
    }

    pub fn open(self: *Layout, config: LayoutConfig) !Node.Handle {
        const parent_handle = self.open_stack.getLastOrNull() orelse .none;

        const handle = try self.insert(.{
            .parent = parent_handle,
            .first_child = .none,
            .last_child = .none,
            .next_sibling = .none,
            .config = config,
            .box = .zero,
        });

        if (parent_handle != .none) {
            const parent = self.get(parent_handle);
            if (parent.first_child == .none) {
                parent.first_child = handle;
                parent.last_child = handle;
            } else {
                self.get(parent.last_child).next_sibling = handle;
                parent.last_child = handle;
            }
        } else {
            self.root = handle;
        }

        try self.open_stack.append(self.gpa, handle);
        return handle;
    }

    pub fn close(self: *Layout) void {
        _ = self.open_stack.pop();
    }

    pub fn get(self: *const Layout, handle: Node.Handle) *Node {
        return &self.nodes.items[@intFromEnum(handle)];
    }

    pub fn children(self: *const Layout, handle: Node.Handle) ChildIterator {
        return .{ .current = self.get(handle).first_child };
    }

    fn childCount(self: *const Layout, handle: Node.Handle) u32 {
        var count: u32 = 0;
        var iter = self.children(handle);
        while (iter.next(self)) |_| count += 1;
        return count;
    }

    fn calculateAxisSizing(self: *Layout, axis: Axis) !void {
        if (self.root == .none) return;

        {
            var stack: std.ArrayList(struct { Node.Handle, bool }) = .empty;
            defer stack.deinit(self.gpa);
            try stack.append(self.gpa, .{ self.root, false });

            while (stack.pop()) |frame| {
                const node_handle, const visited = frame;

                if (visited) {
                    const node = self.get(node_handle);

                    const sizing = switch (axis) {
                        .x => node.config.sizing.width,
                        .y => node.config.sizing.height,
                    };

                    const min_size = node.box.min_size.axis(axis);
                    const max_size = node.box.max_size.axis(axis);
                    const preferred_size = node.box.preferred_size.axis(axis);
                    const size = node.box.size.axis(axis);

                    min_size.* = sizing.min;
                    max_size.* = sizing.max;

                    const padding = node.config.padding.axis(axis);

                    const gap_sum = if (node.config.direction == axis) @as(f32, @floatFromInt(self.childCount(node_handle) -| 1)) * node.config.child_gap else 0;

                    size.* += padding + gap_sum;
                    size.* = std.math.clamp(size.*, sizing.min, sizing.max);

                    preferred_size.* = switch (sizing.type) {
                        .fit => size.*,
                        .grow => max_size.*,
                        .fixed => |s| s,
                        .percent => @panic("TODO"),
                    };

                    if (node.parent == .none) continue;
                    const parent = self.get(node.parent);

                    const parent_size = parent.box.size.axis(axis);
                    if (parent.config.direction == axis) {
                        parent_size.* += size.*;
                    } else {
                        parent_size.* = @max(parent_size.*, size.*);
                    }
                } else {
                    try stack.append(self.gpa, .{ node_handle, true });
                    var it = self.children(node_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, .{ child_handle, false });
                    }
                }
            }
        }

        {
            var stack: std.ArrayList(Node.Handle) = .empty;
            defer stack.deinit(self.gpa);
            try stack.append(self.gpa, self.root);

            while (stack.pop()) |parent_handle| {
                const parent = self.get(parent_handle);

                const parent_size = parent.box.size.axis(axis).*;
                const padding = parent.config.padding.axis(axis);
                const available = parent_size - padding;

                var it = self.children(parent_handle);
                while (it.next(self)) |child_handle| {
                    const child = self.get(child_handle);

                    if (parent.config.direction != axis) {
                        const child_size = child.box.size.axis(axis);
                        const child_preferred = child.box.preferred_size.axis(axis).*;

                        if (child_size.* < child_preferred) {
                            child_size.* = @min(available, child_preferred);
                        }
                    }

                    try stack.append(self.gpa, child_handle);
                }

                if (parent.config.direction != axis) continue;

                var remaining = available;

                var child_count: usize = 0;
                var it1 = self.children(parent_handle);
                while (it1.next(self)) |child_handle| {
                    const child = self.get(child_handle);
                    child_count += 1;
                    remaining -= child.box.size.axis(axis).*;
                }
                remaining -= @as(f32, @floatFromInt(child_count -| 1)) * parent.config.child_gap;

                while (remaining > 0) {
                    var size_to_add = remaining;
                    var growable_count: usize = 0;

                    var smallest = std.math.floatMax(f32);
                    var second_smallest = std.math.floatMax(f32);
                    var it2 = self.children(parent_handle);
                    while (it2.next(self)) |child_handle| {
                        const child = self.get(child_handle);

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

                    var it3 = self.children(parent_handle);
                    while (it3.next(self)) |child_handle| {
                        const child = self.get(child_handle);
                        const child_size = child.box.size.axis(axis);
                        if (child_size.* == smallest) {
                            child_size.* += size_to_add;
                            remaining -= size_to_add;
                        }
                    }
                }
            }
        }
    }

    pub fn calculateLayout(self: *Layout) !void {
        if (self.root == .none) return;

        try self.calculateAxisSizing(.x);
        try self.calculateAxisSizing(.y);

        {
            var stack: std.ArrayList(Node.Handle) = .empty;
            defer stack.deinit(self.gpa);
            try stack.append(self.gpa, self.root);

            while (stack.pop()) |parent_handle| {
                const parent = self.get(parent_handle);
                const direction = parent.config.direction;

                var main_offset = switch (direction) {
                    .x => parent.box.pos.x + parent.config.padding.left,
                    .y => parent.box.pos.y + parent.config.padding.top,
                };

                var it = self.children(parent_handle);
                while (it.next(self)) |child_handle| {
                    const child = self.get(child_handle);

                    switch (direction) {
                        .x => {
                            child.box.pos.x = main_offset;
                            main_offset += child.box.size.width + parent.config.child_gap;

                            const available_height = parent.box.size.height - parent.config.padding.axis(.y);
                            const cross_offset = switch (parent.config.child_alignment.y) {
                                .top => 0,
                                .center => (available_height - child.box.size.height) / 2,
                                .bottom => available_height - child.box.size.height,
                            };
                            child.box.pos.y = parent.box.pos.y + parent.config.padding.top + cross_offset;
                        },
                        .y => {
                            child.box.pos.y = main_offset;
                            main_offset += child.box.size.height + parent.config.child_gap;

                            const available_width = parent.box.size.width - parent.config.padding.axis(.x);
                            const cross_offset = switch (parent.config.child_alignment.x) {
                                .left => 0,
                                .center => (available_width - child.box.size.width) / 2,
                                .right => available_width - child.box.size.width,
                            };
                            child.box.pos.x = parent.box.pos.x + parent.config.padding.left + cross_offset;
                        },
                    }

                    try stack.append(self.gpa, child_handle);
                }
            }
        }
    }
};
