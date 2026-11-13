// expect-error: ownership 16:5 access or storage conflicts with a live read loan
interface Show { fn value(): i32; }
type Held { value: read i32 from static; drop {} }
extend Held implements Show { fn value(): i32 { *self.value } }
type Source { value: read i32 from static }
static mut NUMBER: i32 = 7
fn wrap(read source: Source): heap any Show {
    heap Held(source.value)
}
fn main(): i32 {
    let writer = unsafe { mut NUMBER }
    let shown = {
        let source = Source(read *writer)
        wrap(read source)
    }
    *writer = 8
    shown.value()
}
