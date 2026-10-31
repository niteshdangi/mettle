// stdin: first\r\nsecond\nthird
// expect-stdout: locked out\n
// expect-stderr: locked err
// Stdin.read_line and lines read exactly one line at a time; Stdout/Stderr
// lock() handles write through the same descriptors as the unlocked streams.
import std.io.{Error, Writer}
import alloc.string

fn run(): i32 throws Error {
    var line = string.new()
    let first = try std.io.stdin().read_line(line)
    if first != 8usize || line.len() != 8usize { return 1 }
    var count = 0
    var last = string.new()
    for item in std.io.stdin().lines() {
        let text = match take item { success(t) => t, failure(e) => { throw e } }
        count += 1
        if count == 1 && text.len() != 6usize { return 2 }
        if count == 2 && text.len() != 5usize { return 3 }
        last = text
    }
    if count != 2 || last.len() != 5usize { return 4 }
    var out = std.io.stdout().lock()
    try out.write_all("locked out\n".as_bytes())
    try out.flush()
    var err = std.io.stderr().lock()
    try err.write_all("locked err\n".as_bytes())
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 100 }
}
