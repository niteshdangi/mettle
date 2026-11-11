type ReadSlot<region r> { pointer: ptr<read (read i32 from r)> }
type Owned<T> { value: heap T }

fn shorten_pointer<region a, region b>(
    take value: ReadSlot<region a>
): ReadSlot<region b> where region a: b {
    take value
}

fn shorten_owner<region a, region b>(
    take value: Owned<read i32 from a>
): Owned<read i32 from b> where region a: b {
    take value
}

fn main(): i32 {
    let value = 42
    let _ = shorten_owner(Owned(heap (read value)))
    0
}
