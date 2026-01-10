const std = @import("std");
const libj = @import("root.zig");
const dbg = libj.dbg;


pub fn main() !void {
    try libj.caldav.authenticate();
}
