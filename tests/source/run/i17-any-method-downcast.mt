import core.any.{Any, TypeId}
import core.fmt.{Debug, formatter, spec, buffer_writer, written_text}
import alloc.string.{String, from_text}

copy type Payload { value: i32 }

fn debug_text<T: Debug + unsized>(read value: T): String? {
    var buffer = [0u8; 128]
    let length = {
        var writer = buffer_writer(mut buffer)
        {
            var f = formatter(mut writer, spec())
            match capture T.(Debug).fmt(value, mut f) {
                success(_) => {},
                failure(_) => { return none }
            }
        }
        writer.len()
    }
    match written_text(read buffer, length) {
        present(text) => present(from_text(text)),
        none => none
    }
}

fn main(): i32 {
    let payload = Payload(41i32)
    let erased: read any Any = read payload
    if TypeId.of<Payload>() != core.any.type_id<Payload>() { return 1 }
    if TypeId.of<[i32]>() != core.any.type_id<[i32]>() { return 2 }
    if !erased.is<Payload>() { return 3 }
    match debug_text(TypeId.of<Payload>()) {
        present(text) => { if text.len() == 0usize { return 8 } },
        none => { return 8 }
    }
    match debug_text(erased) {
        present(text) => { if text.as_text() != "Any { .. }" { return 9 } },
        none => { return 9 }
    }
    match erased.downcast_ref<Payload>() {
        present(value) => { if value.value != 41i32 { return 4 } },
        none => { return 4 }
    }
    if erased.is<i32>() { return 5 }
    var changed = Payload(7i32)
    {
        var mutable: mut any Any = mut changed
        match take mutable.downcast_mut<Payload>() {
            present(value) => { value.value = 9i32 },
            none => { return 6 }
        }
    }
    if changed.value != 9i32 { return 7 }
    0
}
