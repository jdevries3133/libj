const std = @import("std");
const libj = @import("root.zig");
const dbg = libj.dbg;


pub fn main() !void {

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var threaded_io = std.Io.Threaded.init(alloc, .{});
    defer threaded_io.deinit();

    const io = threaded_io.io();

    const client_id = std.posix.getenv("GOOGLE_CALDAV_OAUTH_CLIENT_ID").?;

    dbg(@src(), "client id {s}\n", .{ client_id });

    const random = std.crypto.random;
    var verifier: [1024]u8 = undefined;
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

    // Prints to stderr, ignoring potential errors.
    var writer = std.Io.Writer.Allocating.init(alloc);
    try uri.format(&writer.writer);
    std.debug.print("challenge: {x}\nurl: {s}\n", .{challenge, writer.written()});

    var transfer_buf: [1024]u8 = undefined;
    const auth_response = try libj.readline(alloc, io, &transfer_buf);
    std.debug.print("response: {s}\n", .{auth_response});
}
