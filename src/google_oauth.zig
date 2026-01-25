const builtin = @import("builtin");
const std = @import("std");
const libj = @import("root.zig");
const Buf = libj.Buf1k;
const dbg = libj.dbg;

// Change to e.g, `std.Target.Os.Tag.linux` to test non-mac behavior.
const os = builtin.os.tag;

/// Working albeit ugly RFC 7636 Oauth flow for the Google Calendar and Caldav
/// API. Can be easily adapted to get scopes for other Google APIs. Can be less
/// easily adapted to talk to other RFC 7636 compliant authorization servers.
///
/// This is just the meat of the flow. It connects the dots between credential
/// pair and access key / refresh token. In a real-world desktop app, you'd
/// open up the browser while also opening up a http server to receive the
/// redirect to 127.0.0.1:8000.
///
/// Slightly different oauth flows are needed depending on context. This would
/// work for a CLI, Desktop, or iOS apps. Web apps should use "implicit grant
/// flow," which happens entirely inside the Browser's and depends on web
/// browsers' security features. Android won't allow this callback-to-loopback
/// pattern anymore
/// ([src](https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration)).
/// [Limited input
/// devices](https://developers.google.com/identity/protocols/oauth2/limited-input-device)
/// also have their own much simpler flow which can only yield limited
/// permissions.
pub fn authenticate(alloc: std.mem.Allocator, io: std.Io) !void {

    const client_id = std.posix.getenv("GOOGLE_CALDAV_OAUTH_CLIENT_ID") orelse {
        return error.MissingClientId;
    };
    const client_secret = std.posix.getenv("GOOGLE_CALDAV_OAUTH_CLIENT_SECRET") orelse {
        return error.MissingClientId;
    };

    const random = std.crypto.random;
    var verifier: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var challenge: [libj.rfc7636_pkce_oauth_flow.code_challenge_len]u8 = undefined;
    try libj.rfc7636_pkce_oauth_flow.create_code_challenge(
        random,
        &verifier,
        &challenge
    );

    var url_out: libj.aliases.Buf1k = undefined;

    const uri = try libj.rfc7636_pkce_oauth_flow.prepare_authorization_request_uri(
        "accounts.google.com",
        "/o/oauth2/v2/auth",
        client_id,
        "https://www.googleapis.com/auth/calendar",
        &challenge,
        "http://127.0.0.1:8000",
        &url_out
    );

    var uri_buf: libj.aliases.Buf1k = undefined;
    var wr = std.Io.Writer.fixed(&uri_buf);
    try uri.format(&wr);
    const uri_str = uri_buf[0..wr.end];

    switch (os) {
        .macos => {
            const argv = [_][]const u8{
                "open",
                uri_str
            };
            var child = std.process.Child.init(&argv, alloc);
            try child.spawn(io);
            const result = try child.wait(io);
            switch (result) {
                .Exited => |code| {
                    if (code != 0) {
                        return error.OpenFailedNonzeroExit;
                    }
                },
                .Signal => return error.OpenFailedTerminationSignal,
                .Stopped => return error.OpenFailedStopped,
                .Unknown => return error.OpenFailedUnknown,
            }
        },
         else => {
            std.debug.print("Visit Login URL in your browser: {s}\n\n", .{uri_str});
        }
    }
    const code_callback_uri = try libj.readline(alloc, io, "Paste back the http://127.0.0.1... URL you were redirected to in your browser");
    defer alloc.free(code_callback_uri);

    const code = try libj.rfc7636_pkce_oauth_flow.get_code(code_callback_uri);
    var access_token_request_query_param_buf: libj.aliases.Buf1k = undefined;
    var auth_request = try libj.rfc7636_pkce_oauth_flow.prepare_access_token_request(
        "oauth2.googleapis.com",
        "/token",
        &verifier,
        code,
        "http://127.0.0.1:8000",
        client_id,
        client_secret,
        &access_token_request_query_param_buf
    );
    var writer2 = std.Io.Writer.Allocating.init(alloc);
    try auth_request.uri.format(&writer2.writer);

    var http_c = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    var content_length_strbuf: [256]u8 = undefined;
    var auth_request_wr = std.Io.Writer.fixed(&content_length_strbuf);
    _ = try auth_request_wr.printInt(auth_request.body.len, 10, .lower, .{});
    const size_str = content_length_strbuf[0..auth_request_wr.end];
    var req = try http_c.request(std.http.Method.POST, auth_request.uri, .{
        .extra_headers = &.{
            .{
                .name = "Content-Length",
                .value = size_str
            },
            .{
                .name = "Content-Type",
                .value = "application/x-www-form-urlencoded"
            }
        }
    });
    req.transfer_encoding = std.http.Client.Request.TransferEncoding{
        .content_length = auth_request.body.len
    };
    const bd = try alloc.dupe(u8, auth_request.body);
    defer alloc.free(bd);
    _ = try req.sendBodyComplete(bd);
    var header_buf: libj.aliases.Buf1k = undefined;
    var res = try req.receiveHead(&header_buf);
    var dc_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var dc: std.http.Decompress = undefined;
    var body_buf: libj.aliases.Buf1k = undefined;
    const rd = res.readerDecompressing(&body_buf, &dc, &dc_buf);
    const response = try libj.read(rd, alloc, .{});
    defer alloc.free(response);
    if (res.head.status != std.http.Status.ok) {
        dbg(@src(), "err response\n{s}\n", .{ response });
       return error.AuthTokenResponseError;
    } else {
        dbg(@src(), "Token: {s}\n", .{ response });
    }
}
