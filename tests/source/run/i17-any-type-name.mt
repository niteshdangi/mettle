import core.any.{type_name, type_name_of_val}

copy type Payload { value: i32 }

fn main(): i32 {
    let payload = Payload(41i32)
    let name = type_name<Payload>()
    let value_name = type_name_of_val(read payload)
    if name.len() == 0usize || name != value_name { return 1 }
    let values = [1i32, 2i32]
    let slice: read [i32] = read values
    if type_name<[i32]>() != type_name_of_val(slice) { return 2 }
    0
}
