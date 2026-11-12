// profiles: debug release

import core.cell
import core.convert.{TryFrom, TryInto}
import core.fmt
import core.fmt.{Formatter, Message}
import core.iter.Phantom

fn from_self<T: TryFrom<T, Error = Never>>(take value: T): T {
    match take T.(TryFrom<T>).try_from(value) {
        success(result) => result
    }
}

fn into_self<T: TryInto<T, Error = Never>>(take value: T): T {
    match take T.(TryInto<T>).try_into(value) {
        success(result) => result
    }
}

type Counted {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1i32 } }
}

fn message_preserved(): bool {
    let fields = [fmt.text_field("31", "value=")]
    let message = unsafe { fmt.message(read fields, "") }
    var bytes = [0u8; 8]
    var writer = fmt.buffer_writer(mut bytes)
    let converted = into_self(from_self(message))
    match take capture converted.write_to(mut writer) {
        success(_) => {},
        failure(_) => { return false }
    }
    if writer.len() != 8usize { return false }
    let expected = b"value=31"
    var index = 0usize
    while index < 8usize {
        if bytes[index] != expected[index] { return false }
        index += 1usize
    }
    true
}

fn main(): i32 {
    var drops = 0i32
    {
        var cell = core.cell.OnceCell<Counted>.new()
        match take capture cell.set(Counted(core.ptr.from_mut(mut drops), 17i32)) {
            success(_) => {},
            failure(_) => { return 1 }
        }
        let converted = into_self(from_self(cell))
        if converted.get().unwrap().value != 17i32 || drops != 0i32 { return 2 }
    }
    if drops != 1i32 { return 3 }

    var cell = core.cell.RefCell.new(23i32)
    {
        let guard = into_self(from_self(cell.borrow()))
        if *guard.get_ref() != 23i32 { return 4 }
        match cell.try_borrow_mut() {
            success(_) => { return 5 },
            failure(_) => {}
        }
    }
    {
        var guard = into_self(from_self(cell.borrow_mut()))
        *guard.get_mut() = 29i32
        match cell.try_borrow() {
            success(_) => { return 6 },
            failure(_) => {}
        }
    }
    if *cell.borrow().get_ref() != 29i32 { return 7 }
    match cell.try_borrow_mut() {
        success(_) => {},
        failure(_) => { return 8 }
    }

    var bytes = [0u8; 8]
    var writer = fmt.buffer_writer(mut bytes)
    {
        var formatter = into_self(from_self(fmt.formatter(mut writer, fmt.spec())))
        match take capture formatter.write_str("kept") {
            success(_) => {},
            failure(_) => { return 9 }
        }
    }
    if writer.len() != 4usize { return 10 }
    if !message_preserved() { return 11 }

    let marker = into_self(from_self(Phantom<Counted>()))
    if core.mem.size_of<Phantom<Counted>>() != 0usize { return 12 }
    core.mem.drop(marker)
    if drops != 1i32 { return 13 }

    var number = 37i32
    {
        let pin = core.pin.Pin.new(mut number)
        var converted = into_self(from_self(pin))
        *converted.get_mut() = 41i32
    }
    if number != 41i32 { return 14 }
    let read_pin = core.pin.Pin.new(read number)
    let converted = into_self(from_self(read_pin))
    if *converted.get_ref() != 41i32 { return 15 }
    0
}
