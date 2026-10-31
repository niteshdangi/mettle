interface Shape { fn area(): i32; }
type Circle {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}
extend Circle implements Shape { fn area(): i32 { 42 } }

fn main(): i32 {
    var dropped = 0
    let count = core.ptr.from_mut(dropped)
    let area = {
        let shape: heap any Shape = heap Circle(count)
        let payload = shape.get()
        if core.mem.size_of_val(payload) != core.mem.size_of<Circle>() ||
           core.mem.align_of_val(payload) != core.mem.align_of<Circle>() {
            return 1
        }
        payload.area()
    }
    if area == 42 && dropped == 1 { 0 } else { 2 }
}
