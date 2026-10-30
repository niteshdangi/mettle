// expect-exit: 42
// expect-stdout: buffered text\n
// process::exit ends the program with the given status; stdout is unbuffered
// in std, so earlier output is not lost.
fn main(): i32 {
    std::io::print("buffered text\n")
    std::process::exit(42)
}
