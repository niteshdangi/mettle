// profiles: debug release
alias First = for<region r> fn(read (read i32 from r)): read i32 from r
alias Second = fn(read (read i32 from static)): read i32 from static

fn main(): i32 {
    let first_id = core.intrinsics.type_id<First>()
    let second_id = core.intrinsics.type_id<Second>()
    if first_id == second_id { return 1 }
    0
}
