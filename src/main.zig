const std = @import("std");
const libj = @import("root.zig");
const dbg = libj.dbg;


pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const alloc = arena.allocator();

    var threaded_io = std.Io.Threaded.init(alloc, .{
        .environ = init.environ
    });
    defer threaded_io.deinit();

    const io = threaded_io.io();
    try libj.google_oauth.authenticate(alloc, io, init.environ);
}
