copy type View<region r> { value: read i32 from r }
extend<region r> View<region r> {
    fn get(): read i32 from r { self.value }
}

interface HasItem { type Item; fn item(): Self.Item; }
copy type Source<region r> { value: View<region r> }
extend<region r> Source<region r> implements HasItem {
    type Item = View<region r>
    fn item(): View<region r> { self.value }
}

fn inspect<region r, I: HasItem<Item = View<region r>>>(read source: I): i32 {
    let value = source.item()
    *value.get()
}

fn roundtrip<region r>(read number: i32 from r): i32 {
    let source = Source<region r>(View<region r>(read number))
    inspect<region r, Source<region r>>(read source)
}

fn main(): i32 {
    let number = 23
    if roundtrip(read number) == 23 { 0 } else { 1 }
}
