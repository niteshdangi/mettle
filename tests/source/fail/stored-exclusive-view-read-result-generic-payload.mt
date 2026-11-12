// expect-error: ownership 12:5 live read loan

type Cursor<T, region r> { v: mut T from r }
extend<T, region r> Cursor<T, region r> {
    fn peek(): read T from r { let p = core.ptr.from_ref(read *self.v)
        unsafe { read *p } }
}
fn main(): i32 {
    var n = 1
    var cur = Cursor(mut n)
    let a = cur.peek()
    *cur.v = 7
    *a
}
