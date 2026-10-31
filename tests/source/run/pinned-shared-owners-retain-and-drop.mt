type Counter { log: ptr<mut i32>; n: i32; drop { unsafe { *self.log = *self.log + 1 } } }
fn main(): i32 {
    var drops = 0
    let log = core.ptr.from_mut(drops)
    {
        let a = alloc.arc.pin(Counter(log, 3))
        let b = a.retain()
        if !a.ptr_eq(b) || b.get_ref().n != 3 { return 1 }
        let v = a.as_ref()
        if v.get_ref().n != 3 { return 2 }
    }
    if drops != 1 { return 3 }
    {
        let a = alloc.rc.pin(Counter(log, 4))
        let b = a.retain()
        { let c = a }
        if drops != 1 || b.get_ref().n != 4 { return 4 }
    }
    if drops != 2 { return 5 }
    0
}
