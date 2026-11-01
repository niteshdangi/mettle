import core.clone.Clone

type Borrowed<region r> { value: read i32 from r }

extend<region r> Borrowed<region r> implements Clone {
    fn clone(): Borrowed<region r> { Borrowed(self.value) }
}

fn main(): i32 {
    let first = 7
    let second = 9
    var original = Borrowed(read first)
    let cloned = original.clone()
    original = Borrowed(read second)
    if *cloned.value != 7 || *original.value != 9 { return 1 }
    0
}
