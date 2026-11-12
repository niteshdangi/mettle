// profiles: debug release

extend<T> core.cell.Cell<T> {
    static fn from_value<U>(take value: T, take tag: U): core.cell.Cell<T> {
        core.cell.Cell.new(value)
    }
}

extend<T, const N: usize> core.cell.Cell<[T; N]> {
    static fn from_array(take value: [T; N]): core.cell.Cell<[T; N]> {
        core.cell.Cell.new(value)
    }
}

fn main(): i32 {
    let scalar = core.cell.Cell<i64>.from_value<u8>(42i64, 1u8)
    let array = core.cell.Cell<[i32; 3]>.from_array([1i32, 2, 3])
    let builtin = core.cell.Cell.new(7i32)
    if scalar.get() == 42i64 && array.get()[1] == 2 && builtin.get() == 7 {
        0
    } else { 1 }
}
