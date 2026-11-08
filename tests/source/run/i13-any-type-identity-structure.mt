// expect-exit: 0
// profiles: debug release
// Type identity is structural and spelling-independent: alpha-equivalent
// binders agree, nesting and generic arguments are distinguished, and distinct
// closures with one signature stay distinct.

import core.any
import core.any.TypeId

alias Bound = for<region r> fn(read (read i32 from r)): read i32 from r
alias Renamed = for<region s> fn(read (read i32 from s)): read i32 from s
alias Unbound = fn(read (read i32 from static)): read i32 from static

fn type_of<T: Static>(value: read T): TypeId { any.type_id<T>() }

fn main(): i32 {
    if any.type_id<Bound>() != any.type_id<Renamed>() { return 1 }
    if any.type_id<Bound>() == any.type_id<Unbound>() { return 2 }
    if any.type_id<(i32, (i32, i32))>() == any.type_id<((i32, i32), i32)>() {
        return 3
    }
    if any.type_id<i32?>() == any.type_id<u32?>() { return 4 }
    if any.type_id<i32?>() != any.type_id<i32?>() { return 5 }
    if any.type_id<[i32; 2]>() == any.type_id<[i32; 3]>() { return 6 }
    let first = fn(value: i32): i32 { value + 1 }
    let second = fn(value: i32): i32 { value + 2 }
    if type_of(read first) == type_of(read second) { return 7 }
    if type_of(read first) != type_of(read first) { return 8 }
    0
}
