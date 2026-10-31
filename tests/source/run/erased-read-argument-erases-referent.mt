import core.any.{Any, TypeId, type_id}

// A `read i32` argument to a `read any Any` parameter erases the referent, not
// the view, even though the blanket `Any` implementation also covers views.
fn dynamic_id(value: read any Any): TypeId { value.type_id() }

fn main(): i32 {
    let number = 5i32
    if dynamic_id(read number) != type_id<i32>() { return 1 }
    0
}
