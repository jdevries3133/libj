const std = @import("std");
const libj = @import("root.zig");
const dbg = libj.dbg;

pub fn authenticate() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const alloc = arena.allocator();

    var threaded_io = std.Io.Threaded.init(alloc, .{});
    defer threaded_io.deinit();

    const io = threaded_io.io();

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

    var url_out: [1024]u8 = undefined;

    const uri = try libj.rfc7636_pkce_oauth_flow.prepare_authorization_request_uri(
        "accounts.google.com",
        "/o/oauth2/v2/auth",
        client_id,
        "https://www.googleapis.com/auth/calendar",
        &challenge,
        "http://127.0.0.1:8000",
        &url_out
    );

    var writer = std.Io.Writer.Allocating.init(alloc);
    defer writer.deinit();
    try uri.format(&writer.writer);
    dbg(@src(), "oauth URL copied to the clipboard\n", .{});

    var child = std.process.Child.init(&[_][]const u8{"pbcopy"}, alloc);

    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Ignore; child.stderr_behavior = .Ignore;

    try child.spawn(io);

    var buf: [1024]u8 = undefined;
    var wr = child.stdin.?.writer(io, &buf);
    try uri.format(&wr.interface);
    try wr.interface.writeByte(4);
    try wr.interface.flush();
    child.stdin.?.close(io);
    child.stdin = null;
    const result = try child.wait(io);
    switch (result) {
        .Exited => |code| {
            if (code != 0) {
                return error.CopyToClipboardFailedNonzeroExit;
            }
        },
        .Signal => return error.CopyToClipboardFailedTerminationSignal,
        .Stopped => return error.CopyToClipboardFailedStopped,
        .Unknown => return error.CopyToClipboardFailedUnknown,
    }

    var transfer_buf: [1024]u8 = undefined;
    const code_callback_uri = try libj.readline(alloc, io, &transfer_buf);
    defer alloc.free(code_callback_uri);

    const code = try libj.rfc7636_pkce_oauth_flow.get_code(code_callback_uri);
    var auth_request = try libj.rfc7636_pkce_oauth_flow.prepare_access_token_request(
        "oauth2.googleapis.com",
        "/token",
        &verifier,
        code,
        "http://localhost:3000/oauth/callback",
        client_id,
        client_secret,
        &buf
    );
    var writer2 = std.Io.Writer.Allocating.init(alloc);
    try auth_request.uri.format(&writer2.writer);
    dbg(@src(), "access token URI: {s}\nbody: {s}\n", .{ writer2.written(), auth_request.body });

    var http_c = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    var size_str_buf: [256]u8 = undefined;
    var wr3 = std.Io.Writer.fixed(&size_str_buf);
    _ = try wr3.printInt(auth_request.body.len, 10, .lower, .{});
    const size_str = size_str_buf[0..wr3.end];
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
    dbg(@src(), "\n", .{});
    const bd = try alloc.dupe(u8, auth_request.body);
    dbg(@src(), "\n", .{});
    defer alloc.free(bd);
    dbg(@src(), "\n", .{});
    _ = try req.sendBodyComplete(bd);
    dbg(@src(), "\n", .{});
    var res = try req.receiveHead(&buf);
    dbg(@src(), "---\nHEAD\n---\n{s}\n---\n", .{ res.head.bytes });
    if (res.head.status != std.http.Status.ok) {
        var dc_buf: [std.compress.flate.max_window_len]u8 = undefined;
        var dc: std.http.Decompress = undefined;
        const rd = res.readerDecompressing(&buf, &dc, &dc_buf);
        const response = try libj.read(rd, alloc, .{});
        defer alloc.free(response);
        dbg(@src(), "err response\n{s}\n", .{ response });
       return error.AuthTokenResponseError;
    }
    const rd = res.reader(&buf);
    _ = try rd.readAlloc(alloc, res.head.content_length orelse 2 << 15);
    dbg(@src(), "Token: {s}\n", .{ rd.buffer[0..rd.end] });

}
