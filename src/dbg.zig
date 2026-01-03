const std = @import("std");

/// Get `loc` by calling the `@src()` builtin.
pub fn dbg(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    comptime {
        // fmt template must end with newline
        std.debug.assert(fmt[fmt.len - 1] == '\n');
    }

    const prefixed_fmt = comptime pf: {
        const f = loc.file;

        const col = loc.column;
        var col_strbuf: [10]u8 = undefined;
        const col_str = std.fmt.bufPrint(&col_strbuf, "{d}", .{col}) catch unreachable;
        const ln = loc.line;
        var ln_strbf: [10]u8 = undefined;
        const ln_str = std.fmt.bufPrint(&ln_strbf, "{d}", .{ln}) catch unreachable;

        const mod = loc.module;
        const func = loc.fn_name;

        var fmt_buf: [
            f.len + col_str.len + ln_str.len + mod.len + func.len + 14 + fmt.len
        ]u8 = undefined;
        _ = std.fmt.bufPrint(&fmt_buf, "src/{s}:{s}:{s} || {s}::{s}\t{s}\n", .{ f, ln_str, col_str, mod, func, fmt }) catch unreachable;
        const final = fmt_buf;
        break :pf final;
    };
    std.debug.print(&prefixed_fmt, args);
}

