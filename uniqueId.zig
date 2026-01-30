pub fn main() !void {
    const a = comptime srcId(@src());
    const b = comptime srcId(@src());
    @compileLog(a == b);
    std.debug.print("{}\n", .{@intFromPtr(a)});
    std.debug.print("{}\n", .{@intFromPtr(b)});
}

const SrcId = *const std.builtin.SourceLocation;

fn srcId(comptime src: std.builtin.SourceLocation) SrcId {
    return &src;
}

const std = @import("std");
