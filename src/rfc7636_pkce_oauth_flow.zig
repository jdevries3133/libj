const std = @import("std");
const string = @import("string.zig");

/// Note: redirect URI and state params are not included because this oauth
/// implementation has the PKCE flow in mind.
///
/// code_challenge_method also is not included because create_code_challenge
/// will only create S256-type challenges. The RFC recommends making S256
/// challenges, and to only use PLAIN if the client is incapable.
///
/// May return `error.WriteFailed` if `query_param_write_buf` is too small.
///
/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.3
fn prepare_authorization_request_uri(
    host: []const u8,
    client_id: []const u8,
    scopes: []const u8,
    code_challenge: []const u8,
    query_param_write_buf: []u8
) !std.Uri {
    const client_id_c = std.Uri.Component{
        .raw = client_id
    };
    const scopes_c = std.Uri.Component{
        .raw = scopes
    };
    const challenge_c = std.Uri.Component{
        .raw = code_challenge
    };
    var wr = std.Io.Writer.fixed(query_param_write_buf);
    _ = try wr.write("client_id=");
    try client_id_c.formatQuery(&wr);
    _ = try wr.write("&scope=");
    try scopes_c.formatQuery(&wr);
    _ = try wr.write("&code_challenge=");
    try challenge_c.formatQuery(&wr);
    _ = try wr.write("&code_challenge_method=S256");
    _ = try wr.write("&response_type=code");

    const query_params = query_param_write_buf[0..wr.end];

    return std.Uri{
        .host = .{ .raw = host },
        .path = .{ .raw = "/authorize" },
        .scheme = "https",
        .query = .{ .percent_encoded = query_params }
    };
}

test "prepare authorization request URI" {
    var buf: [2048]u8 = undefined;
    const uri = try prepare_authorization_request_uri(
        "google.com",
        "1234",
        "this that other",
        "rando",
        &buf
    );
    var uri_str: [2048]u8 = undefined;
    var wr = std.Io.Writer.fixed(&uri_str);
    try uri.format(&wr);
    const uri_slice = uri_str[0..wr.end];
    try std.testing.expect(string.contains("client_id=1234", uri_slice));
    try std.testing.expect(string.contains("scope=this%20that%20other", uri_slice));
}

test "prepare authorization request uri with small write buf" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(
        error.WriteFailed,
        prepare_authorization_request_uri(
            "google.com",
            "1234",
            "this that other",
            "rando",
            &buf
        )
    );
}


const code_challenge_len = std.base64.url_safe_no_pad.Encoder.calcSize(std.crypto.hash.sha2.Sha256.digest_length);
/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.2
fn create_code_challenge(random: std.Random, code_verifier: []const u8, out_buf: []u8) !void {
    if (out_buf.len != code_challenge_len) {
        return error.WrongOutBufSize;
    }
    try generate_code_verifier(random, out_buf);
    var verifier_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(code_verifier);
    hasher.final(&verifier_hash);

    _ = std.base64.url_safe_no_pad.Encoder.encode(out_buf, &verifier_hash);
}

test "create code challenge requires sufficiently large input buffer" {
    var fake_prng = std.Random.DefaultPrng.init(1);
    const in: [1]u8 = undefined;
    var out: [1]u8 = undefined;
    try std.testing.expectError(
        error.WrongOutBufSize,
        create_code_challenge(fake_prng.random(), &in, &out)
    );
}

test "creates code challenge" {
    var fake_prng = std.Random.DefaultPrng.init(1);
    const in: [1028]u8 = undefined;
    var out: [code_challenge_len]u8 = undefined;
    const SENTINEL = "SENTINEL";
    for (0..SENTINEL.len) |idx| {
        out[idx] = SENTINEL[idx];
    }
    try create_code_challenge(fake_prng.random(), &in, &out);
    try std.testing.expect(out[0..SENTINEL.len] != SENTINEL);
}

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
