// profiles: debug release
// expect-stderr: "forward=7\nforward=7\nforward=7\n"

import core.fmt.Message
import std.io
import std.macros.format_args

fn forward(message: format Message): Unit {
    io.eprint(format_args!(message,))
    io.eprint(message: format_args!(format_args!(message,)))
    io.eprint((message))
}

fn main(): i32 {
    forward(f"forward={7}\n")
    0
}
