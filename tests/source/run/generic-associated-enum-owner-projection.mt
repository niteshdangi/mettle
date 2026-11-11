interface OwnedType { type Owned; }
interface ToOwned: OwnedType { fn to_owned(): Self.Owned; }

enum Storage<region r, B: OwnedType + unsized> {
    Borrowed(read B from r);
    Owned(B.Owned)
}
extend<T> [T] implements OwnedType { type Owned = [T; 1] }
extend<T: Copy> [T] implements ToOwned {
    fn to_owned(): [T; 1] { [self[0usize]] }
}
alias Cow<region r, T> = Storage<region r, [T]>

extend<region r, B: ToOwned + unsized> Storage<region r, B> {
    mut fn promote() {
        match self {
            Storage.Borrowed(value) => {
                let owner = value.to_owned()
                self = Storage<region r, B>.Owned(owner)
            },
            Storage.Owned(_) => {}
        }
    }
}

type Value { number: i32 }
extend Value implements OwnedType { type Owned = i32 }
extend Value implements ToOwned {
    fn to_owned(): i32 { self.number }
}

fn accept<T>(read value: T) { let _ = value }

fn into_owned<region r, B: ToOwned + unsized>(
    take value: Storage<region r, B>
): B.Owned {
    match take value {
        Storage.Borrowed(source) => source.to_owned(),
        Storage.Owned(owner) => owner
    }
}

fn forward<region r>(take value: Storage<region r, Value>): i32 {
    into_owned(value)
}

fn borrowed<region r>(read source: Value from r): Storage<region r, Value> {
    Storage<region r, Value>.Borrowed(read source)
}

fn choose<region r>(
    read source: Value from r, pick: bool
): Storage<region r, Value> {
    if pick { borrowed(read source) } else { Storage<region r, Value>.Owned(11) }
}

fn forward_slice<region r, T: Copy>(take value: Cow<region r, T>): [T; 1] {
    into_owned(value)
}

fn slice_roundtrip<region r>(read source: [i32] from r): i32 {
    let owned: Cow<region r, i32> = Cow.Owned([source[0usize]])
    if forward_slice(owned)[0usize] != 9 { return 7 }
    let value: Cow<region r, i32> = Cow.Borrowed(read source)
    if forward_slice(value)[0usize] == 9 { 0 } else { 6 }
}

fn borrowed_option<region r, T>(read value: T from r): (read T from r)? {
    present(read value)
}

fn roundtrip<region r>(read source: Value from r): i32 {
    let returned: Storage<region r, Value> = borrowed(read source)
    if forward(returned) != 7 { return 8 }
    if forward(choose(read source, false)) != 11 { return 9 }
    let forwarded: Storage<region r, Value> = Storage.Borrowed(read source)
    if forward(forwarded) != 7 { return 5 }
    var stored: Storage<region r, Value> = Storage.Borrowed(read source)
    stored.promote()
    accept(stored)
    let number: i32 = match take stored {
        Storage.Borrowed(_) => { return 1 },
        Storage.Owned(owner) => owner
    }
    if number == 7 { 0 } else { 2 }
}

fn main(): i32 {
    let array = [9]
    let slice_result = slice_roundtrip(read array)
    if slice_result != 0 { return slice_result }
    let value = Value(7)
    match borrowed_option(read value) {
        present(borrowed) => { if borrowed.number != 7 { return 3 } },
        absent => { return 4 }
    }
    roundtrip(read value)
}
