// profiles: debug release

type Owned {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += self.value } }
}

fn make(value: i32, trace: ptr<mut i32>, drops: ptr<mut i32>): Owned {
    unsafe { *trace = *trace * 10 + value }
    Owned(value, drops)
}

fn choose<T>(condition: bool, take left: T, take right: T): T {
    core.hint.select_unpredictable(condition, take left, take right)
}

fn main(): i32 {
    var trace = 0
    var drops = 0
    let trace_pointer = core.ptr.from_mut(mut trace)
    let drops_pointer = core.ptr.from_mut(mut drops)
    {
        let selected = choose(true, make(1, trace_pointer, drops_pointer),
                              make(2, trace_pointer, drops_pointer))
        if trace != 12 || drops != 2 || selected.value != 1 { return 1 }
    }
    if drops != 3 { return 2 }
    {
        let selected = choose(false, make(3, trace_pointer, drops_pointer),
                              make(4, trace_pointer, drops_pointer))
        if trace != 1234 || drops != 6 || selected.value != 4 { return 3 }
    }
    if drops == 10 { 0 } else { 4 }
}
