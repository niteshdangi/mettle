// expect-stdout: a1b\nc\n2\n
// expect-stderr: e\n
// print, println and eprint/eprintln take format parameters; no newline is implicit.
import std.io

fn main(): i32 {
    let n = 1
    io.print(f"a{n}b")
    io.print("\n")
    io.println("c")
    io.println(f"{n + 1}")
    io.eprint("e")
    io.eprintln("")
    0
}
