// expect-error: ownership 16:5 access or storage conflicts with a live read loan
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
}

fn main(): i32 {
    let shown = {
        let number = 7
        wrap(read number)
    }
    shown.value()
}
