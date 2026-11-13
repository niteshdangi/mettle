// profiles: debug release
// expect-stderr: "forward=7\nforward=7\nforward=7\n"

import core.fmt.Message
import std.io

fn forward(message: format Message): Unit {
    io.eprint(message,)
    io.eprint(message: message)
    io.eprint((message))
}

fn main(): i32 {
    forward(f"forward={7}\n")
    0
}
