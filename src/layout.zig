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

    pub const zero: Box = .{
        .pos = .{ .x = 0, .y = 0 },
        .size = .{ .width = 0, .height = 0 },
        .preferred_size = .{ .width = 0, .height = 0 },
        .min_size = .{ .width = 0, .height = 0 },
    };
};

pub const Axis = enum { x, y };
pub const Handle = enum(u32) { none = std.math.maxInt(u32), _ };

pub const Node = struct {
    parent: Handle,
    first_child: Handle,
    last_child: Handle,
    next_sibling: Handle,

    box: Box,

    config: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        fitAxis: *const fn (layout: *const Layout, handle: Handle, config: *const anyopaque, axis: Axis) void,
        sizeAxis: *const fn (layout: *const Layout, handle: Handle, config: *const anyopaque, axis: Axis) void,
        position: *const fn (layout: *const Layout, handle: Handle, config: *const anyopaque) void,
    };
};

pub const Layout = struct {
    nodes: std.ArrayListUnmanaged(Node),
    free: std.ArrayListUnmanaged(Handle),

    open_stack: std.ArrayListUnmanaged(Handle),

    root: Handle,

    gpa: std.mem.Allocator,

    pub fn init(gpa: Allocator) Layout {
        return .{
            .gpa = gpa,
            .nodes = .empty,
            .free = .empty,
            .open_stack = .empty,
            .root = .none,
        };
    }

    pub fn getNode(self: *const Layout, handle: Handle) *Node {
        return &self.nodes.items[@intFromEnum(handle)];
    }

    pub fn getPreferedSize(self: *const Layout, handle: Handle, axis: Axis) f32 {
        const node = self.getNode(handle);
        node.vtable.sizeAxis(self, handle, node.config, axis);
    }

    pub const ChildIterator = struct {
        current: Handle,

        pub fn next(self: *ChildIterator, layout: *const Layout) ?Handle {
            if (self.current == .none) return null;
            defer self.current = layout.getNode(self.current).next_sibling;
            return self.current;
        }
    };

    pub fn children(self: Layout, handle: Handle) ChildIterator {
        return .{ .current = self.getNode(handle).first_child };
    }

    pub fn childCount(self: *const Layout, handle: Handle) u32 {
        var count: u32 = 0;
        var iter = self.children(handle);
        while (iter.next(self)) |_| count += 1;
        return count;
    }

    fn newNode(self: *Layout) !Handle {
        if (self.free.pop()) |handle| {
            self.nodes.items[@intFromEnum(handle)] = undefined;
            return handle;
        }
        try self.nodes.append(self.gpa, undefined);
        return @enumFromInt(self.nodes.items.len - 1);
    }

    pub fn removeNode(self: *Layout, handle: Handle) !void {
        self.getNode(handle).* = undefined;
        try self.free.append(self.gpa, handle);
    }

    pub fn open(self: *Layout, config: anytype) !Handle {
        const Config = @TypeOf(config);

        const vtable_wrapper = struct {
            pub fn fitAxis(layout: *const Layout, handle: Handle, conf: *const anyopaque, axis: Axis) void {
                Config.fitAxis(layout, handle, @ptrCast(@alignCast(conf)), axis);
            }
            pub fn sizeAxis(layout: *const Layout, handle: Handle, conf: *const anyopaque, axis: Axis) void {
                Config.sizeAxis(layout, handle, @ptrCast(@alignCast(conf)), axis);
            }
            pub fn position(layout: *const Layout, handle: Handle, conf: *const anyopaque) void {
                Config.position(layout, handle, @ptrCast(@alignCast(conf)));
            }
        };

        const conf = try self.gpa.create(@TypeOf(config));
        conf.* = config;

        return self.openRaw(&.{
            .fitAxis = vtable_wrapper.fitAxis,
            .sizeAxis = vtable_wrapper.sizeAxis,
            .position = vtable_wrapper.position,
        }, conf);
    }

    pub fn openRaw(
        self: *Layout,
        vtable: *const Node.VTable,
        config: *anyopaque,
    ) !Handle {
        const parent_handle = self.open_stack.getLastOrNull() orelse .none;
        const handle = try self.newNode();

        const node = self.getNode(handle);
        node.* = .{
            .parent = parent_handle,
            .first_child = .none,
            .last_child = .none,
            .next_sibling = .none,

            .box = .zero,

            .config = config,
            .vtable = vtable,
        };

        if (parent_handle != .none) {
            const parent = self.getNode(parent_handle);
            if (parent.first_child == .none) {
                parent.first_child = handle;
                parent.last_child = handle;
            } else {
                self.getNode(parent.last_child).next_sibling = handle;
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

    fn calculateAxisSizing(self: *Layout, axis: Axis) !void {
        if (self.root == .none) return;

        // Bottom-up pass: calculate min sizes
        {
            var stack: std.ArrayListUnmanaged(struct { Handle, bool }) = .empty;
            defer stack.deinit(self.gpa);
            try stack.append(self.gpa, .{ self.root, false });

            while (stack.pop()) |frame| {
                const node_handle, const visited = frame;

                if (visited) {
                    const node = self.getNode(node_handle);
                    const box = &node.box;

                    node.vtable.fitAxis(self, node_handle, node.config, axis);
                    box.size.axis(axis).* = box.min_size.axis(axis).*;
                } else {
                    try stack.append(self.gpa, .{ node_handle, true });
                    var it = self.children(node_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, .{ child_handle, false });
                    }
                }
            }
        }

        // Top-down pass: distribute sizes
        {
            var stack: std.ArrayListUnmanaged(Handle) = .empty;
            defer stack.deinit(self.gpa);
            try stack.append(self.gpa, self.root);

            while (stack.pop()) |parent_handle| {
                var it = self.children(parent_handle);
                while (it.next(self)) |child_handle| {
                    try stack.append(self.gpa, child_handle);
                }
                const node = self.getNode(parent_handle);
                node.vtable.sizeAxis(self, parent_handle, node.config, axis);
            }
        }
    }

    pub fn calculateLayout(self: *Layout) !void {
        if (self.root == .none) return;

        try self.calculateAxisSizing(.x);
        try self.calculateAxisSizing(.y);

        {
            var stack: std.ArrayListUnmanaged(Handle) = .empty;
            defer stack.deinit(self.gpa);
            try stack.append(self.gpa, self.root);

            while (stack.pop()) |parent_handle| {
                var it = self.children(parent_handle);
                while (it.next(self)) |child_handle| {
                    try stack.append(self.gpa, child_handle);
                }
                const node = self.getNode(parent_handle);
                node.vtable.position(self, parent_handle, node.config);
            }
        }
    }
};
