// expect-exit: 0
// profiles: debug release

import core.any
import core.any.{Any, TypeId}
import core.text.Text

fn bound_id<T: Any + unsized>(): TypeId { any.type_id<T>() }

fn erased_id(read value: any Any): TypeId { value.type_id() }

fn main(): i32 {
    if bound_id<i32>() != any.type_id<i32>() {
        return 1
    }
    let text: read Text = "unsized"
    if bound_id<Text>() != erased_id(text) { return 2 }
    let values = [1i32, 2i32]
    let slice: read [i32] = read values
    if bound_id<[i32]>() != erased_id(slice) { return 3 }
    0
}
