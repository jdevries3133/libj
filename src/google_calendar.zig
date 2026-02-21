const std = @import("std");
const dbg = @import("dbg.zig").dbg;

pub fn list_calendars(
    alloc: std.mem.Allocator,
    http_client: *std.http.Client,
    oauth_access_token: []const u8,
) !void {
    var req = try http_client.request(
        .GET,
        std.Uri{
            .host = std.Uri.Component{ .percent_encoded = "www.googleapis.com" },
            .port = 443,
            .path = std.Uri.Component{ .percent_encoded = "/calendar/v3/users/me/calendarList" },
            .scheme = "https",
        },
        .{},
    );
    defer req.deinit();
    var wr = std.Io.Writer.Allocating.init(alloc);
    defer wr.deinit();
    try wr.writer.print("Bearer {s}", .{ oauth_access_token });
    req.headers.authorization = .{ .override = wr.written() };
    _ = try req.sendBodiless();
    const redir_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(redir_buf);
    var response = try req.receiveHead(redir_buf);
    const buf_tr = try alloc.alloc(u8, 1024);
    defer alloc.free(buf_tr);
    const buf_dc = try alloc.alloc(u8, std.compress.flate.max_window_len);
    defer alloc.free(buf_dc);
    var dc: std.http.Decompress = undefined;
    const rd = response.readerDecompressing(buf_tr, &dc, buf_dc);
    const res_text = try rd.allocRemaining(alloc, .limited(2 << 21));
    defer alloc.free(res_text);
    dbg(@src(), "{s}\n", .{res_text});
}
