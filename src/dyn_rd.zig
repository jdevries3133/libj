//! Reading with dynamic memory allocation.

const std = @import("std");

pub const DynRdErr = error{ ByteLimitOverflow, OutOfMemory, ReadFailed };

pub const ByteLimit = union(enum) { Unlimited, Limited: u64 };

const Opts = struct {
    chunk_size: comptime_int = 1024,
    byte_limit: comptime_int = 65_536,
};

/// Returns memory owned by the caller.
///
/// Warning: this doesn't work with HTTP responses because you can't read at
/// all past the end of the response or else a panic happens in the HTTP client
/// library.
pub fn read(
    reader: *std.Io.Reader,
    alloc: std.mem.Allocator,
    opts: Opts,
) DynRdErr![]u8 {
    var rd_buf = try alloc.alloc(u8, opts.chunk_size);
    defer alloc.free(rd_buf);
    var all_stdin = std.ArrayList(u8){};
    defer all_stdin.deinit(alloc);
    while (reader.readSliceShort(rd_buf)) |chunk| {
        if (all_stdin.items.len > opts.byte_limit) {
            return DynRdErr.ByteLimitOverflow;
        }
        try all_stdin.appendSlice(alloc, rd_buf[0..chunk]);
        if (chunk < rd_buf.len) {
            break;
        }
    } else |e| return e;
    return all_stdin.toOwnedSlice(alloc);
}

fn test_template(str: []const u8, opts: Opts) !void {
    var rd = std.Io.Reader.fixed(str);
    const alloc = std.testing.allocator;
    const result = try read(&rd, alloc, opts);
    defer alloc.free(result);
    try std.testing.expectEqualSlices(u8, str[0..], result);
}

test "read tiny string without options" {
    try test_template("hi", .{});
}

test "read bigger than chunk size without options" {
    const str = [_]u8{'z'} ** (2 << 12);
    try test_template(&str, .{});
}

test "read bigger than chunk size with tiny chunks" {
    const str = [_]u8{'z'} ** (2 << 12);
    try test_template(&str, .{ .chunk_size = 2 });
}

test "read binary" {
    const bytes = [_]u8{ 190, 175, 191, 148, 180, 122, 35, 66, 80, 182, 124, 18, 105, 210, 39 };
    try test_template(&bytes, .{});
}

test "read bigger than limit" {
    const str = [_]u8{'z'} ** (2 << 12);
    _ = test_template(&str, .{ .byte_limit = 2 << 10 }) catch |e| {
        try std.testing.expectEqual(DynRdErr.ByteLimitOverflow, e);
        return;
    };
    unreachable;
}
