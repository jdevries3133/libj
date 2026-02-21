const std = @import("std");
const google_oauth = @import("google_oauth.zig");
const google_calendar = @import("google_calendar.zig");
const dbg = @import("dbg.zig").dbg;

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    var threaded_io = std.Io.Threaded.init(alloc, .{ .environ = init.environ });
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const oauth_access_token = std.process.Environ.getPosix(init.environ, "GOOGLE_OAUTH_ACCESS_KEY") orelse blk: {
        const response = try google_oauth.authenticate(alloc, io, init.environ);
        defer response.deinit();
        const access_token = try alloc.dupe(u8, response.value.access_token);
        break :blk access_token;
    };

    dbg(@src(), "token: {s}\n", .{oauth_access_token});
}
