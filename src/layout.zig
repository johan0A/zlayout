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
    complete: bool,
    pos: Position,
    size: Size,
    preferred_size: Size,
    min_size: Size,

    pub const zero: Box = .{
        .complete = false,
        .pos = .{ .x = 0, .y = 0 },
        .size = .{ .width = 0, .height = 0 },
        .preferred_size = .{ .width = 0, .height = 0 },
        .min_size = .{ .width = 0, .height = 0 },
    };
};

pub const Axis = enum { x, y };

pub const Handle = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn from(idx: u32) Handle {
        return @enumFromInt(idx);
    }
};

pub const Node = struct {
    parent: Handle,
    first_child: Handle,
    last_child: Handle,
    next_sibling: Handle,
    box: Box,

    pub const empty: Node = .{
        .parent = .none,
        .first_child = .none,
        .last_child = .none,
        .next_sibling = .none,
        .box = .zero,
    };
};

pub const LayoutView = struct {
    nodes: *std.ArrayListUnmanaged(Node),
    free: *std.ArrayListUnmanaged(Handle),

    const Self = @This();

    pub const ChildIterator = struct {
        current: Handle,

        pub fn next(self: *ChildIterator, view: anytype) ?Handle {
            if (self.current == .none) return null;
            const handle = self.current;
            self.current = view.getNode(handle).next_sibling;
            return handle;
        }
    };

    pub fn getNode(self: Self, handle: Handle) *Node {
        return &self.nodes.items[@intFromEnum(handle)];
    }

    pub fn getBox(self: Self, handle: Handle) *Box {
        return &self.getNode(handle).box;
    }

    pub fn children(self: Self, handle: Handle) ChildIterator {
        return .{ .current = self.getNode(handle).first_child };
    }

    pub fn childCount(self: Self, handle: Handle) u32 {
        var count: u32 = 0;
        var iter = self.children(handle);
        while (iter.next(self)) |_| count += 1;
        return count;
    }
};

pub fn Layout(Config: type) type {
    return struct {
        gpa: Allocator,
        nodes: std.ArrayListUnmanaged(Node),
        free: std.ArrayListUnmanaged(Handle),
        open_stack: std.ArrayListUnmanaged(Handle),
        root: Handle,

        configs: std.ArrayListUnmanaged(Config),

        const Self = @This();

        pub const ChildIterator = LayoutView.ChildIterator;

        pub fn init(gpa: Allocator) Self {
            return .{
                .gpa = gpa,
                .nodes = .empty,
                .free = .empty,
                .open_stack = .empty,
                .root = .none,
                .configs = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit(self.gpa);
            self.free.deinit(self.gpa);
            self.open_stack.deinit(self.gpa);
            self.configs.deinit(self.gpa);
        }

        pub fn clear(self: *Self) void {
            self.nodes.clearRetainingCapacity();
            self.free.clearRetainingCapacity();
            self.open_stack.clearRetainingCapacity();
            self.configs.clearRetainingCapacity();
            self.root = .none;
        }

        /// Returns a non-generic view into the tree structure.
        pub fn treeView(self: *Self) LayoutView {
            return .{
                .nodes = &self.nodes,
                .free = &self.free,
            };
        }

        fn insert(self: *Self) !Handle {
            if (self.free.pop()) |handle| {
                self.nodes.items[@intFromEnum(handle)] = .empty;
                return handle;
            }
            try self.nodes.append(self.gpa, .empty);
            return Handle.from(@intCast(self.nodes.items.len - 1));
        }

        pub fn open(self: *Self, config: Config) !Handle {
            const parent_handle = self.open_stack.getLastOrNull() orelse .none;
            const handle = try self.insert();

            const node = self.getNode(handle);
            node.parent = parent_handle;

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

            const idx = @intFromEnum(handle);
            if (idx >= self.configs.items.len) {
                try self.configs.resize(self.gpa, self.nodes.items.len);
            }
            self.configs.items[idx] = config;

            return handle;
        }

        pub fn close(self: *Self) void {
            _ = self.open_stack.pop();
        }

        pub fn remove(self: *Self, handle: Handle) !void {
            self.getNode(handle).* = undefined;
            try self.free.append(self.gpa, handle);
        }

        pub fn getNode(self: *const Self, handle: Handle) *Node {
            return &self.nodes.items[@intFromEnum(handle)];
        }

        pub fn getBox(self: *const Self, handle: Handle) *Box {
            return &self.getNode(handle).box;
        }

        pub fn getConfig(self: *const Self, handle: Handle) *Config {
            return &self.configs.items[@intFromEnum(handle)];
        }

        pub fn children(self: *const Self, handle: Handle) ChildIterator {
            return .{ .current = self.getNode(handle).first_child };
        }

        pub fn childCount(self: *const Self, handle: Handle) u32 {
            var count: u32 = 0;
            var iter = self.children(handle);
            while (iter.next(self)) |_| count += 1;
            return count;
        }

        fn calculateAxisSizing(self: *Self, axis: Axis) !void {
            if (self.root == .none) return;

            const view = self.treeView();

            // Bottom-up pass: calculate min sizes
            {
                var stack: std.ArrayListUnmanaged(struct { Handle, bool }) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, .{ self.root, false });

                while (stack.pop()) |frame| {
                    const node_handle, const visited = frame;

                    if (visited) {
                        const config = self.getConfig(node_handle);
                        const box = self.getBox(node_handle);
                        switch (config.*) {
                            inline else => |config_union| {
                                @TypeOf(config_union).fitAxis(view, node_handle, config_union, axis);
                            },
                        }
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

                    const config = self.getConfig(parent_handle);
                    switch (config.*) {
                        inline else => |config_union| {
                            @TypeOf(config_union).sizeAxis(view, parent_handle, config_union, axis);
                        },
                    }
                }
            }
        }

        pub fn calculateLayout(self: *Self) !void {
            if (self.root == .none) return;

            const view = self.treeView();

            try self.calculateAxisSizing(.x);

            // Adjustment pass
            {
                var stack: std.ArrayListUnmanaged(Handle) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, self.root);

                while (stack.pop()) |parent_handle| {
                    var it = self.children(parent_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, child_handle);
                    }

                    const config = self.getConfig(parent_handle);
                    switch (config.*) {
                        inline else => |config_union| {
                            if (@hasDecl(@TypeOf(config_union), "adjust"))
                                @TypeOf(config_union).adjust(view, parent_handle, config_union);
                        },
                    }
                }
            }

            try self.calculateAxisSizing(.y);

            // Positioning pass
            {
                var stack: std.ArrayListUnmanaged(Handle) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, self.root);

                while (stack.pop()) |parent_handle| {
                    var it = self.children(parent_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, child_handle);
                    }

                    const config = self.getConfig(parent_handle);
                    switch (config.*) {
                        inline else => |config_union| {
                            @TypeOf(config_union).position(view, parent_handle, config_union);
                        },
                    }
                }
            }
        }
    };
}
