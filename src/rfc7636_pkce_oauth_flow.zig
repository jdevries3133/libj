const std = @import("std");
const string = @import("string.zig");
const dbg = @import("dbg.zig").dbg;
const libj = @import("root.zig");

const TokenTypes = enum { Bearer };

const AccessTokenResponseInner = struct {
    access_token: []const u8,
    token_type: TokenTypes,
    expires_in: u32,
    refresh_token: ?[]const u8 = null,
    refresh_token_expires_in: ?u32 = null,
};

pub const AccessTokenResponse = std.json.Parsed(AccessTokenResponseInner);

/// https://datatracker.ietf.org/doc/html/rfc6749#section-4.1.4
pub fn parse_access_token_response(alloc: std.mem.Allocator, response: []const u8) !AccessTokenResponse {
    const json = try std.json.parseFromSlice(
        AccessTokenResponseInner,
        alloc,
        response,
        .{ .ignore_unknown_fields = true, .allocate = std.json.AllocWhen.alloc_always },
    );
    return json;
}

test "parsing a typical auth server response" {
    const alloc = std.testing.allocator;
    const response =
        \\{
        \\  "access_token": "fish",
        \\  "expires_in": 3599,
        \\  "refresh_token": "sticks",
        \\  "scope": "https://www.googleapis.com/auth/calendar",
        \\  "token_type": "Bearer",
        \\  "refresh_token_expires_in": 604799
        \\}
    ;

    const parse_result = try parse_access_token_response(alloc, response);
    defer parse_result.deinit();
    try std.testing.expectEqualStrings("fish", parse_result.value.access_token);
    try std.testing.expectEqual(604799, parse_result.value.refresh_token_expires_in.?);
    try std.testing.expectEqualStrings("sticks", parse_result.value.refresh_token.?);
}

test "parsing without optional fields" {
    const alloc = std.testing.allocator;
    const response =
        \\{
        \\  "access_token": "fish",
        \\  "expires_in": 3599,
        \\  "scope": "https://www.googleapis.com/auth/calendar",
        \\  "token_type": "Bearer"
        \\}
    ;
    const parse_result = try parse_access_token_response(alloc, response);
    defer parse_result.deinit();
    try std.testing.expectEqualStrings("fish", parse_result.value.access_token);
    try std.testing.expectEqual(3599, parse_result.value.expires_in);
    try std.testing.expectEqual(null, parse_result.value.refresh_token);
    try std.testing.expectEqual(null, parse_result.value.refresh_token_expires_in);
}

const AccessTokenRequest = struct { uri: std.Uri, body: []const u8 };

/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.5
pub fn prepare_access_token_request(
    host: []const u8,
    path: []const u8,
    code_verifier: []const u8,
    code: []const u8,
    redirect_uri: []const u8,
    client_id: []const u8,
    client_secret: []const u8,
    request_body_buf: []u8,
) !AccessTokenRequest {
    const code_verifier_c = std.Uri.Component{ .raw = code_verifier };
    const code_c = std.Uri.Component{ .raw = code };
    const redirect_uri_c = std.Uri.Component{ .raw = redirect_uri };
    const client_id_c = std.Uri.Component{ .raw = client_id };
    const client_secret_c = std.Uri.Component{ .raw = client_secret };
    var wr = std.Io.Writer.fixed(request_body_buf);
    _ = try wr.write("code_verifier=");
    try code_verifier_c.formatQuery(&wr);
    _ = try wr.write("&code=");
    try code_c.formatQuery(&wr);
    _ = try wr.write("&redirect_uri=");
    try redirect_uri_c.formatQuery(&wr);
    _ = try wr.write("&client_id=");
    try client_id_c.formatQuery(&wr);
    _ = try wr.write("&client_secret=");
    try client_secret_c.formatQuery(&wr);
    _ = try wr.write("&grant_type=authorization_code");

    const body = request_body_buf[0..wr.end];

    return .{ .uri = std.Uri{
        .host = .{ .raw = host },
        .path = .{ .raw = path },
        .scheme = "https",
    }, .body = body };
}

test "prepare_access_token_request_uri" {
    var buf: libj.aliases.Buf1k = undefined;
    const request = try prepare_access_token_request(
        "google.com",
        "/foo",
        "bar",
        "baz",
        "http://127.0.0.1/callback",
        "1234",
        "5678",
        &buf,
    );
    var uri_str: [2048]u8 = undefined;
    var wr = std.Io.Writer.fixed(&uri_str);
    try request.uri.format(&wr);
    const uri_slice = uri_str[0..wr.end];
    const prefix = "https://google.com/foo";
    try std.testing.expectEqualStrings(prefix, uri_slice[0..prefix.len]);
    try std.testing.expect(string.contains("client_id=1234", request.body));
    try std.testing.expect(string.contains("client_secret=5678", request.body));
}

/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.5
pub fn get_code(code_callback_uri: []const u8) ![]const u8 {
    const uri = try std.Uri.parse(code_callback_uri);
    const query_c = uri.query orelse {
        return error.CodeNotFound;
    };
    const query = query_c.percent_encoded;
    const needle = "code=";
    const start = std.mem.find(u8, query, needle) orelse {
        return error.CodeNotFound;
    };
    const end = std.mem.findScalar(u8, query[start..], '&') orelse query.len;
    return query[start + needle.len .. end + start];
}

test "get code checks if uri has query" {
    const redirect_uri = "https://fish.com";
    try std.testing.expectError(error.CodeNotFound, get_code(redirect_uri));
}

test "get code checks if code query param is not there" {
    const redirect_uri = "https://fish.com?foo=bar";
    try std.testing.expectError(error.CodeNotFound, get_code(redirect_uri));
}

test "get code from redirect URI" {
    const redirect_uri = "http://127.0.0.1:8000/?code=4/0ASc3gC2q6yzYW9OCTLcFZa_is-G98S16Ba79G7hwfJvgXuVIAO7eX_Td2Z3udVHfuhwyLQ&scope=https://www.googleapis.com/auth/calendar";
    const code = try get_code(redirect_uri);
    try std.testing.expectEqualStrings("4/0ASc3gC2q6yzYW9OCTLcFZa_is-G98S16Ba79G7hwfJvgXuVIAO7eX_Td2Z3udVHfuhwyLQ", code);

    const redirect_uri2 = "http://127.0.0.12:8000/?code=4/0ASc3gC2q6yzYW9OCTLcFZa_is-G98Sa79G7hwfJvgXuVIAO7eX_Td2Z3udVHfuhwyLQ&scope=https://www.googleapis.com/auth/calendar";
    const code2 = try get_code(redirect_uri2);
    try std.testing.expectEqualStrings("4/0ASc3gC2q6yzYW9OCTLcFZa_is-G98Sa79G7hwfJvgXuVIAO7eX_Td2Z3udVHfuhwyLQ", code2);
}

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
pub fn prepare_authorization_request_uri(
    host: []const u8,
    path: []const u8,
    client_id: []const u8,
    scopes: []const u8,
    code_challenge: []const u8,
    redirect_uri: []const u8,
    query_param_write_buf: []u8,
) !std.Uri {
    const client_id_c = std.Uri.Component{ .raw = client_id };
    const scopes_c = std.Uri.Component{ .raw = scopes };
    const challenge_c = std.Uri.Component{ .raw = code_challenge };
    const redirect_uri_c = std.Uri.Component{ .raw = redirect_uri };
    var wr = std.Io.Writer.fixed(query_param_write_buf);
    _ = try wr.write("client_id=");
    try client_id_c.formatQuery(&wr);
    _ = try wr.write("&scope=");
    try scopes_c.formatQuery(&wr);
    _ = try wr.write("&code_challenge=");
    try challenge_c.formatQuery(&wr);
    _ = try wr.write("&code_challenge_method=S256");
    _ = try wr.write("&response_type=code");

    _ = try wr.write("&redirect_uri=");
    try redirect_uri_c.formatQuery(&wr);

    const query_params = query_param_write_buf[0..wr.end];

    return std.Uri{
        .host = .{ .raw = host },
        .path = .{ .raw = path },
        .scheme = "https",
        .query = .{ .percent_encoded = query_params },
    };
}

test "prepare authorization request URI" {
    var buf: [2048]u8 = undefined;
    const uri = try prepare_authorization_request_uri(
        "google.com",
        "/foo",
        "1234",
        "this that other",
        "rando",
        "localhost:123",
        &buf,
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
        prepare_authorization_request_uri("google.com", "/foo", "1234", "this that other", "rando", "localhost:123", &buf),
    );
}

pub const code_challenge_len = std.base64.url_safe_no_pad.Encoder.calcSize(std.crypto.hash.sha2.Sha256.digest_length);
/// code_verifier should have length std.crypto.hash.sha2.Sha256.digest_length
/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.2
pub fn create_code_challenge(io: std.Io, code_verifier: []u8, out_buf: []u8) !void {
    if (out_buf.len != code_challenge_len) {
        return error.WrongOutBufSize;
    }
    try generate_code_verifier(io, code_verifier);
    var verifier_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(code_verifier);
    hasher.final(&verifier_hash);

    _ = std.base64.url_safe_no_pad.Encoder.encode(out_buf, &verifier_hash);
}

test "create code challenge requires sufficiently large input buffer" {
    const io = std.testing.io;
    var in: [1]u8 = undefined;
    var out: [1]u8 = undefined;
    try std.testing.expectError(
        error.WrongOutBufSize,
        create_code_challenge(io, &in, &out),
    );
}

test "creates code challenge" {
    const io = std.testing.io;
    var in: [1028]u8 = undefined;
    var out: [code_challenge_len]u8 = undefined;
    const SENTINEL = "SENTINEL";
    for (0..SENTINEL.len) |idx| {
        out[idx] = SENTINEL[idx];
    }
    try create_code_challenge(io, &in, &out);
    try std.testing.expect(out[0..SENTINEL.len] != SENTINEL);
}

/// https://datatracker.ietf.org/doc/html/rfc7636#section-4.1
fn generate_code_verifier(io: std.Io, out_buf: []u8) !void {
    try io.randomSecure(out_buf);
    for (0..out_buf.len) |i| {
        const idx = @mod(out_buf[i], UnreserveCharacters.len);
        out_buf[i] = try UnreserveCharacters.at(idx);
    }
}

test "code verifier generation (Section 4.1)" {
    const io = std.testing.io;
    var buf = [_]u8{0} ** 128;
    try generate_code_verifier(io, &buf);

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
    const CharsetRange = struct { run_length: u16, first_char: u8 };

    const charset = [_]CharsetRange{
        CharsetRange{ .run_length = 1, .first_char = '-' },
        CharsetRange{ .run_length = 1, .first_char = '.' },
        CharsetRange{ .run_length = 10, .first_char = '0' },
        CharsetRange{ .run_length = 1, .first_char = '_' },
        CharsetRange{ .run_length = 1, .first_char = '~' },
        CharsetRange{ .run_length = 26, .first_char = 'a' },
        CharsetRange{ .run_length = 26, .first_char = 'A' },
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
