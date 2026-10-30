
interface Tag { fn tag(): i32; }
copy type Plain {}
extend Plain implements Tag { fn tag(): i32 { 7 } }
type Holder<A: Tag = Plain> { a: A }
fn peek(h: read Holder): i32 { h.a.tag() }
fn main(): i32 {
    let h = Holder(Plain())
    peek(h) - 7
}
