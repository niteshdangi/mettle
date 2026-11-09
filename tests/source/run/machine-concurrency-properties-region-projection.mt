interface RegionCarrier {
    type Item<region r>: Transferable + Shareable;
}

type Borrowed<region r> { value: read i32 from r }

extend<region r> Borrowed<region r> implements RegionCarrier {
    type Item<region r> = read i32 from r
}

fn transfer<T: Transferable>(take value: T): Unit {}
fn observe<T: Shareable>(read value: T): Unit {}

fn carry<region source, region r, T: RegionCarrier>(
    read carrier: T from source,
    take value: T.(RegionCarrier).Item<region r>
): Unit {
    transfer(value)
}

fn keep_shared<region source, region r, T: RegionCarrier>(
    read carrier: T from source,
    read value: T.(RegionCarrier).Item<region r>
): Unit {
    observe(value)
}

fn main(): i32 {
    var number = 42
    let carrier = Borrowed(read number)
    carry(read carrier, read number)
    keep_shared(read carrier, read number)
    if number == 42 { 0 } else { 1 }
}
