const std = @import("std");
const Buf = @import("root.zig").Buf;

/// Read one line from STDIN.
///
/// Warning: only ASCII!
pub fn readline(alloc: std.mem.Allocator, io: std.Io, prompt: ?[]const u8) ![]u8 {
    std.debug.print("{s}: ", .{ prompt orelse "Input" });
    const file = std.Io.File.stdin();

    var buf: Buf = undefined;
    var reader = file.reader(io, &buf);

    return _readline(alloc, &reader.interface);
}

fn _readline(alloc: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    var rd_buf: [1]u8 = undefined;
    var out = std.ArrayList(u8){};
    errdefer out.clearAndFree(alloc);
    while (try reader.readSliceShort(&rd_buf) != 0) {
        const byte = rd_buf[0];
        if (!std.ascii.isAscii(byte)) {
            return error.NotAscii;
        }
        try out.append(alloc, byte);
        if (byte == '\n') {
            break;
        }
    }
    return out.toOwnedSlice(alloc);
}

test "readline rejects non-ascii text" {
    const alloc = std.testing.allocator;
    const buf = "hi ☺️";
    var rd = std.Io.Reader.fixed(buf);
    try std.testing.expectError(
        error.NotAscii,
        _readline(alloc, &rd)
    );
}

test "readline reads one line" {
    const alloc = std.testing.allocator;
    const buf = "hi\nthere";
    var rd = std.Io.Reader.fixed(buf);
    const line = try _readline(alloc, &rd);
    defer alloc.free(line);
    try std.testing.expectEqualStrings("hi\n", line);
}

test "readline does not advance the reader past the newline" {
    const alloc = std.testing.allocator;
    const buf = "hi\nthere";
    var rd = std.Io.Reader.fixed(buf);
    const line = try _readline(alloc, &rd);
    defer alloc.free(line);
    try std.testing.expectEqual(3, rd.seek);
}
