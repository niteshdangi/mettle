// profiles: debug release
interface Family { type Owner; }
extend i32 implements Family { type Owner = i32 }
type Envelope<T: Family> { value: T.Owner }
interface Choice<R> { fn choose(read value: R): i32; }
copy type Tag {}

extend Tag implements Choice<i32> {
    fn choose(read value: i32): i32 { value + 1 }
}
extend Tag implements Choice<Envelope<i32>> {
    fn choose(read value: Envelope<i32>): i32 { value.value }
}

fn main(): i32 {
    let tag = Tag()
    let wrapped = Envelope<i32>(42)
    if tag.choose(41) == 42 && tag.choose(wrapped) == 42 { 0 } else { 1 }
}
