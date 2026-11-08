// expect-exit: 101
// profiles: debug release
import core.option

fn main(): i32 {
    let absent: i32? = none
    absent.unwrap()
}
