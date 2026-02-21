const std = @import("std");
const aliases = @import("aliases.zig");

/// Simple HTTP server that listens on 127.0.0.1:8000 for OAuth callback
/// Returns the full callback URI that was received
pub fn listen_for_callback(alloc: std.mem.Allocator, io: std.Io, port: u16) ![]const u8 {
    const localhost: std.Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var net_server = try localhost.listen(io, .{
        .reuse_address = true,
    });
    defer net_server.deinit(io);

    // Accept single connection
    var stream = try net_server.accept(io);
    defer stream.close(io);

    // Set up readers and writers for the HTTP server
    var buffer: [4096]u8 = undefined;
    var reader = stream.reader(io, &buffer);
    var writer = stream.writer(io, &.{});

    // Initialize HTTP server
    var http_server = std.http.Server.init(&reader.interface, &writer.interface);

    // Receive the HTTP request head
    var request = try http_server.receiveHead();

    // Ensure it's a GET request
    if (request.head.method != .GET) {
        try request.respond("Method not allowed\n", .{
            .status = .method_not_allowed,
        });
        return error.OnlyGetSupported;
    }

    // Build full callback URI with the request target (which includes query string)
    var full_uri: aliases.Buf1k = undefined;
    var uri_writer = std.Io.Writer.fixed(&full_uri);

    try uri_writer.writeAll("http://127.0.0.1:");
    var port_buf: [6]u8 = undefined;
    var port_writer = std.Io.Writer.fixed(&port_buf);
    _ = try port_writer.printInt(port, 10, .lower, .{});
    try uri_writer.writeAll(port_buf[0..port_writer.end]);
    try uri_writer.writeAll(request.head.target);

    const callback_uri = try alloc.dupe(u8, full_uri[0..uri_writer.end]);

    // Send HTTP response
    try request.respond("OK\n", .{
        .status = .ok,
    });

    return callback_uri;
}
