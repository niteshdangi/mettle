// expect-error: type 7:5 non-exhaustive match
fn missing(value: (
    bool, bool, bool, bool, bool, bool, bool, bool,
    bool, bool, bool, bool, bool, bool, bool, bool,
    bool, bool, bool, bool, bool, bool, bool, bool
)): i32 {
    match value {
        (_, _, _, _, _, _, _, _, _, _, _, _,
         _, _, _, _, _, _, _, _, _, _, _, true) => 0,
        _ if true => 1
    }
}
fn main() { 0 }
