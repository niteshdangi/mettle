// expect-error: type 13:5 interface method is not dispatchable with this erased contract
interface Touch {
    fn touch(receiver take self: pinned mut Self): Unit;
}
type Value { hits: ptr<mut i32> }
extend Value implements Touch {
    fn touch(receiver take self: pinned mut Self): Unit {
        unsafe { *self.get_ref().hits += 1 }
    }
}
fn main(): i32 {
    var hits = 0
    var value: pinned heap any Touch =
        pinned heap Value(core.ptr.from_mut(hits))
    value.as_mut().touch()
    value.as_mut().touch()
    if hits == 2 { 0 } else { 1 }
}
