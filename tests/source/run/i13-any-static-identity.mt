// expect-exit: 0
// profiles: debug release

import core.any
import core.any.{Any, TypeId}
import core.text.Text

copy type First { value: i32 }
copy type Second { value: i32 }
alias FirstAlias = First

fn identity<T: Any + unsized>(read value: T): TypeId {
    T.(Any).type_id(value)
}

fn main(): i32 {
    let first_id = core.hint.black_box(any.type_id<First>())
    let second_id = core.hint.black_box(any.type_id<Second>())
    if first_id == second_id || first_id != any.type_id<FirstAlias>() {
        return 1
    }
    let first = First(41)
    if identity(read first) != first_id ||
       identity<Text>("static type, borrowed text") != any.type_id<Text>() {
        return 2
    }
    let values = [1i32, 2i32]
    let slice: read [i32] = read values
    if identity<[i32]>(slice) != any.type_id<[i32]>() ||
       any.type_id<[i32]>() == any.type_id<[u32]>() {
        return 3
    }
    match any.downcast_ref<First>(read first) {
        present(value) => { if value.value != 41 { return 4 } },
        none => { return 4 }
    }
    match any.downcast_ref<Second>(read first) {
        present(_) => { return 5 },
        none => {}
    }
    var changed = First(7)
    match any.downcast_mut<Second>(mut changed) {
        present(_) => { return 6 },
        none => {}
    }
    match take any.downcast_mut<First>(mut changed) {
        present(value) => { value.value = 9 },
        none => { return 7 }
    }
    if changed.value != 9 { return 8 }
    0
}
