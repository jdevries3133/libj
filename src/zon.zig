const std = @import("std");
const Al = std.mem.Allocator;
const Io = std.Io;
const read = @import("dyn_rd.zig").read;

/// Uses `std.zon.parse.fromSliceAlloc`. To automatically free the result, see
/// `std.zon.parse.free`.
pub fn fromReader(T: anytype, rd: *std.Io.Reader, diag: *std.zon.parse.Diagnostics, alloc: Al) !T {
    const str =  try read(rd, alloc, .{});
    defer alloc.free(str);
    const strz = try alloc.dupeZ(u8, str);
    defer alloc.free(strz);
    return std.zon.parse.fromSliceAlloc(T, alloc, strz, diag, .{});
}

test "read simple zon from file" {
    var dba = std.heap.DebugAllocator(.{}){};
    const alloc = dba.allocator();
    const zonstr = 
        \\.{ .message = "hello world" }
        ;
    const T = struct {
        message: [:0]const u8
    };
    var rd = std.Io.Reader.fixed(zonstr);
    var diag: std.zon.parse.Diagnostics = .{};
    _ = try fromReader(T, &rd, &diag, alloc);
}
