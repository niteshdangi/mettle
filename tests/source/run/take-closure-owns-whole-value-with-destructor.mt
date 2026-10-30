// Reading a copyable field in a take closure moves the whole value with a
// destructor into the closure, so it drops with the closure, not before.
type Guard { p: ptr<mut i32>; drop { unsafe { *self.p = *self.p + 1 } } }

fn main(): i32 {
    var dropped = 0
    {
        let g = Guard(core::ptr::from_mut(dropped))
        let peek = take fn(): i32 { unsafe { *g.p } }
        if dropped != 0 || peek() != 0 { return 1 }
        if dropped != 0 { return 2 }
    }
    if dropped != 1 { return 3 }
    0
}
