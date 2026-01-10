//! Just a scratch pad to figure out what's not clear from the spec.

const do_panic_examples = false;

test {
    if (do_panic_examples) {
        const opt: ?struct { foo: i32 } = null;
        _ = opt.?.foo;
    }
}
