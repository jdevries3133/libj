const std = @import("std");

/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.1
fn generate_code_verifier() void {
}

test "code verifier generation (Section 4.1)" {
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
    try std.testing.expectEqual('_', try UnreserveCharacters.at(2));
    try std.testing.expectEqual('~', try UnreserveCharacters.at(3));
    try std.testing.expectEqual('a', try UnreserveCharacters.at(4));
    try std.testing.expectEqual('b', try UnreserveCharacters.at(5));
    try std.testing.expectEqual('Z', try UnreserveCharacters.at(55));
    try std.testing.expectError(error.IndexOutOfRange, UnreserveCharacters.at(56));
}
