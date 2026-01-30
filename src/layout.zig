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
    max_size: Size,

    pub const zero: Box = .{
        .complete = false,
        .pos = .{ .x = 0, .y = 0 },
        .size = .{ .width = 0, .height = 0 },
        .preferred_size = .{ .width = 0, .height = 0 },
        .min_size = .{ .width = 0, .height = 0 },
        .max_size = .{ .width = 0, .height = 0 },
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

pub fn Layout(Config: type) type {
    return struct {
        gpa: Allocator,
        nodes: std.ArrayListUnmanaged(Node),
        free: std.ArrayListUnmanaged(Handle),
        open_stack: std.ArrayListUnmanaged(Handle),
        root: Handle,
        contexts: Contexts,

        const Contexts: type = blk: {
            const fields = @typeInfo(Config).@"union".fields;

            var contexts_fields: []const std.builtin.Type.StructField = &.{};
            for (fields) |field| {
                if (@hasDecl(field.type, "Context")) {
                    contexts_fields = contexts_fields ++
                        @as(@TypeOf(contexts_fields), &.{.{
                            .name = field.name,
                            .type = &field.type.Context,
                            .default_value_ptr = null,
                            .is_comptime = false,
                            .alignment = @alignOf(&field.type.Context),
                        }});
                }
            }

            break :blk @Type(.{ .@"struct" = .{
                .is_tuple = false,
                .layout = .auto,
                .decls = &.{},
                .fields = contexts_fields,
            } });
        };

        pub const Node = struct {
            parent: Handle,
            first_child: Handle,
            last_child: Handle,
            next_sibling: Handle,
            config: Config,
            box: Box,
        };

        pub const ChildIterator = struct {
            current: Handle,

            pub fn next(self: *ChildIterator, layout: *const Self) ?Handle {
                if (self.current == .none) return null;
                const handle = self.current;
                self.current = layout.get(handle).next_sibling;
                return handle;
            }
        };

        const Self = @This();

        pub fn init(gpa: Allocator, contexts: Contexts) Self {
            return .{ .gpa = gpa, .contexts = contexts, .free = .empty, .nodes = .empty, .open_stack = .empty, .root = .none };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit(self.gpa);
            self.free.deinit(self.gpa);
            self.open_stack.deinit(self.gpa);
        }

        pub fn clear(self: *Self) void {
            self.nodes.clearRetainingCapacity();
            self.free.clearRetainingCapacity();
            self.open_stack.clearRetainingCapacity();
            self.root = .none;
        }

        fn insert(self: *Self, node: Node) !Handle {
            if (self.free.pop()) |handle| {
                self.nodes.items[@intFromEnum(handle)] = node;
                return handle;
            }
            try self.nodes.append(self.gpa, node);
            return Handle.from(@intCast(self.nodes.items.len - 1));
        }

        pub fn remove(self: *Self, handle: Handle) !void {
            self.get(handle).* = undefined;
            try self.free.append(self.gpa, handle);
        }

        pub fn open(self: *Self, config: Config) !Handle {
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

        pub fn close(self: *Self) void {
            _ = self.open_stack.pop();
        }

        pub fn get(self: *const Self, handle: Handle) *Node {
            return &self.nodes.items[@intFromEnum(handle)];
        }

        pub fn children(self: *const Self, handle: Handle) ChildIterator {
            return .{ .current = self.get(handle).first_child };
        }

        pub fn childCount(self: *const Self, handle: Handle) u32 {
            var count: u32 = 0;
            var iter = self.children(handle);
            while (iter.next(self)) |_| count += 1;
            return count;
        }

        fn calculateAxisSizing(self: *Self, axis: Axis) !void {
            if (self.root == .none) return;

            {
                var stack: std.ArrayList(struct { Handle, bool }) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, .{ self.root, false });

                while (stack.pop()) |frame| {
                    const node_handle, const visited = frame;

                    if (visited) {
                        const parent = self.get(node_handle);
                        switch (parent.config) {
                            inline else => |config_union, tag| {
                                const context = if (@hasDecl(@TypeOf(config_union), "Context")) @field(self.contexts, @tagName(tag)) else {};
                                @TypeOf(config_union).fitAxis(context, self, node_handle, config_union, axis);
                            },
                        }
                        parent.box.size.axis(axis).* = parent.box.min_size.axis(axis).*;
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
                var stack: std.ArrayList(Handle) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, self.root);

                while (stack.pop()) |parent_handle| {
                    var it = self.children(parent_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, child_handle);
                    }

                    const parent = self.get(parent_handle);
                    switch (parent.config) {
                        inline else => |config_union, tag| {
                            const context = if (@hasDecl(@TypeOf(config_union), "Context")) @field(self.contexts, @tagName(tag)) else {};
                            @TypeOf(config_union).sizeAxis(context, self, parent_handle, config_union, axis);
                        },
                    }
                }
            }
        }

        pub fn calculateLayout(self: *Self) !void {
            if (self.root == .none) return;

            try self.calculateAxisSizing(.x);
            {
                var stack: std.ArrayList(Handle) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, self.root);

                while (stack.pop()) |parent_handle| {
                    var it = self.children(parent_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, child_handle);
                    }

                    const parent = self.get(parent_handle);
                    switch (parent.config) {
                        inline else => |config_union| {
                            if (@hasDecl(@TypeOf(config_union), "adjust"))
                                @TypeOf(config_union).adjust(self, parent_handle, config_union);
                        },
                    }
                }
            }
            try self.calculateAxisSizing(.y);

            {
                var stack: std.ArrayList(Handle) = .empty;
                defer stack.deinit(self.gpa);
                try stack.append(self.gpa, self.root);

                while (stack.pop()) |parent_handle| {
                    var it = self.children(parent_handle);
                    while (it.next(self)) |child_handle| {
                        try stack.append(self.gpa, child_handle);
                    }

                    const parent = self.get(parent_handle);
                    switch (parent.config) {
                        inline else => |config_union, tag| {
                            const context = if (@hasDecl(@TypeOf(config_union), "Context")) @field(self.contexts, @tagName(tag)) else {};
                            @TypeOf(config_union).position(context, self, parent_handle, config_union);
                        },
                    }
                }
            }
        }
    };
}
