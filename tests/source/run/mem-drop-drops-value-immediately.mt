type Guard { counter: ptr<mut i32>; drop { unsafe { *self.counter += 1 } } }

fn main(): i32 {
    var drops = 0i32
    let guard = Guard(core.ptr.from_mut(mut drops))
    core.mem.drop(guard)
    if drops == 1 { 0 } else { 1 }
}
