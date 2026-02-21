const std = @import("std");

pub const aliases = @import("aliases.zig");

pub const read = @import("dyn_rd.zig").read;
pub const zon = @import("zon.zig");
pub const dbg = @import("dbg.zig").dbg;
pub const readline = @import("readline.zig").readline;
pub const google_oauth = @import("google_oauth.zig");
pub const oauth_callback_server = @import("oauth_callback_server.zig");

test {
    _ = @import("langlearn.zig");
    std.testing.refAllDecls(@This());
}
