const std = @import("std");
const assert = @import("std").debug.assert;

pub fn contains(substr: []const u8, str: []const u8) bool {
    return std.mem.findPos(u8, str, 0, substr) != null;
}

test contains {
    assert(contains("foo", "foobar"));
    assert(!contains("foo", "fozbar"));
    assert(contains("foo", "barfoobar"));
    assert(!contains("foo", "barfozbar"));
    // case sensitivity
    assert(!contains("Foo", "foo"));
}
