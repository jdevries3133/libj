const std = @import("std");

pub const read = @import("dyn_rd.zig").read;
pub const zon = @import("zon.zig");

test {
    std.testing.refAllDecls(@This());
}
