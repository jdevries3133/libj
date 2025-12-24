const std = @import("std");

/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.1
fn generate_code_verifier(random: std.Random, out_buf: []u8) !void {
    std.Random.bytes(random, out_buf);
    for (0..out_buf.len) |i| {
        const idx = @mod(out_buf[i], UnreserveCharacters.len);
        out_buf[i] = try UnreserveCharacters.at(idx);
    }
}

test "code verifier generation (Section 4.1)" {
    var fake_prng = std.Random.DefaultPrng.init(1);
    var buf = [_]u8{0} ** 128;
    try generate_code_verifier(fake_prng.random(), &buf);

    for (buf) |byte| {
        // all bytes in the buffer, which was initialized to zero, have been
        // overwritten
        try std.testing.expect(byte != 0);

        // all bytes are in UnreserveCharacters
        var found = false;
        for (0..UnreserveCharacters.len) |i| {
            if (try UnreserveCharacters.at(@intCast(i)) == byte) {
                found = true;
            }
        }
        try std.testing.expect(found);
    }
}

/// Unreserved characters.
///
///     unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
///
/// https://datatracker.ietf.org/doc/html/rfc3986#section-2.3
const UnreserveCharacters = struct {
    const CharsetRange = struct {
        run_length: u16,
        first_char: u8
    };

    const charset = [_]CharsetRange{
        CharsetRange {
            .run_length = 1,
            .first_char = '-'
        },
        CharsetRange {
            .run_length = 1,
            .first_char = '.'
        },
        CharsetRange{
            .run_length = 10,
            .first_char = '0'
        },
        CharsetRange {
            .run_length = 1,
            .first_char = '_'
        },
        CharsetRange {
            .run_length = 1,
            .first_char = '~'
        },
        CharsetRange{
            .run_length = 26,
            .first_char = 'a'
        },
        CharsetRange{
            .run_length = 26,
            .first_char = 'A'
        },
    };

    const len = blk: {
        var _len = 0;
        for (charset) |range| {
            _len += range.run_length;
        }
        break :blk _len;
    };

    fn at(idx: u16) !u8 {
        var absolute_idx: u16 = 0;
        var char: ?u8 = null;
        for (charset) |range| {
            if (range.run_length > idx - absolute_idx) {
                char = range.first_char + @as(u8, @intCast(idx - absolute_idx));
                break;
            }
            absolute_idx += range.run_length;
        }
        if (char) |c| {
            return c;
        }
        return error.IndexOutOfRange;
    }

};

test "unreserved chars" {
    try std.testing.expectEqual('-', try UnreserveCharacters.at(0));
    try std.testing.expectEqual('.', try UnreserveCharacters.at(1));
    try std.testing.expectEqual('0', try UnreserveCharacters.at(2));
    try std.testing.expectEqual('9', try UnreserveCharacters.at(11));
    try std.testing.expectEqual('_', try UnreserveCharacters.at(12));
    try std.testing.expectEqual('~', try UnreserveCharacters.at(13));
    try std.testing.expectEqual('a', try UnreserveCharacters.at(14));
    try std.testing.expectEqual('z', try UnreserveCharacters.at(39));
    try std.testing.expectError(error.IndexOutOfRange, UnreserveCharacters.at(UnreserveCharacters.len));
}

test "unreserved char len" {
    try std.testing.expectEqual(66, UnreserveCharacters.len);
}
