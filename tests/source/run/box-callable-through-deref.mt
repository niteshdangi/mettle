// profiles: debug release
import alloc.boxed

fn main(): i32 {
    let add_one = boxed.new(fn(x: i32): i32 { x + 1 })
    if add_one(3) != 4 { return 1 }
    let view = read add_one
    if view(9) != 10 { return 2 }
    let offset = 20
    let shifted = boxed.new(fn(x: i32): i32 { x + offset })
    if shifted(1) != 21 { return 3 }
    var count = 0
    var counter = boxed.new(fn(): i32 { count += 1; count })
    if counter() != 1 || counter() != 2 { return 4 }
    0
}
