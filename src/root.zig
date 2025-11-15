const std = @import("std");

pub const read = @import("./dyn_rd.zig").read;

test {
    std.testing.refAllDecls(@This());
}
