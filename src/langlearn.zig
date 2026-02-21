//! Just a scratch pad to figure out what's not clear from the spec.

const std = @import("std");

const alloc = std.testing.allocator;

const do_panic_examples = false;

test "panic examples" {
    if (do_panic_examples) {
        const opt: ?struct { foo: i32 } = null;
        _ = opt.?.foo;
    }
}

test "JSON parsing: in the Basic struct definition here, baz has no default. Even though it's an optional field, parsing fails." {
    const basic =
        \\{"foo":"bar"}
    ;
    const Basic = struct { foo: []const u8, baz: ?usize };
    const result = std.json.parseFromSlice(Basic, alloc, basic, .{});
    try std.testing.expectError(error.MissingField, result);
}

test "JSON parsing w/ missing field that has a default" {
    const basic =
        \\{"foo":"bar"}
    ;
    // Actually, the field doesn't even need to be optional, though it'd need
    // to be optional if you wanted the default value to be `null`.
    const Basic = struct { foo: []const u8, baz: usize = 10 };
    const res = try std.json.parseFromSlice(Basic, alloc, basic, .{});
    defer res.deinit();
    try std.testing.expectEqualDeep(Basic{ .foo = "bar", .baz = 10 }, res.value);
}
