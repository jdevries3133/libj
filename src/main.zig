const std = @import("std");
const libj = @import("root.zig");

pub fn main() !void {

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const client_id = std.posix.getenv("GOOGLE_CALDAV_OAUTH_CLIENT_ID").?;

    const random = std.crypto.random;
    var scratch_buf: [1024]u8 = undefined;
    var challenge: [libj.rfc7636_pkce_oauth_flow.code_challenge_len]u8 = undefined;
    try libj.rfc7636_pkce_oauth_flow.create_code_challenge(
        random,
        &scratch_buf,
        &challenge
    );
    const uri = try libj.rfc7636_pkce_oauth_flow.prepare_authorization_request_uri(
        "google.com",
        client_id,
        "https://www.googleapis.com/auth/calendar",
        &challenge,
        &scratch_buf
    );

    // Prints to stderr, ignoring potential errors.
    var writer = std.Io.Writer.Allocating.init(alloc);
    try uri.format(&writer.writer);
    std.debug.print("challenge: {x}\nurl: {s}\n", .{challenge, writer.written()});
}
