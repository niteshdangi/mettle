interface ReadValue {
    fn value(): i32;
}

type View<region r> { item: read i32 from r }

extend<region r> View<region r> implements ReadValue {
    fn value(): i32 { *self.item }
}

fn inspect<T: ReadValue>(read value: T): i32 { value.value() }

fn choose<region a, region b>(
    read first: i32 from a,
    read second: i32 from b,
    flag: bool
): i32 {
    let joined = if flag { View(read first) } else { View(read second) }
    inspect(joined)
}

fn main(): i32 {
    let first = 7
    let second = 9
    if choose(first, second, true) != 7 { return 1 }
    if choose(first, second, false) != 9 { return 2 }
    0
}
