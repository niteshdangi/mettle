// profiles: debug release

import core.cell
import std.panic.{catch_panic, CatchResult}

type Counted {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}
fn released(read cell: core.cell.RefCell<Counted>): bool {
    match cell.try_borrow_mut() { success(_) => true, failure(_) => false }
}
fn main(): i32 {
    var payload_drops = 0
    var callback_drops = 0
    let payload_counter = core.ptr.from_mut(payload_drops)
    let callback_counter = core.ptr.from_mut(callback_drops)
    {
        let cell = core.cell.RefCell.new(Counted(payload_counter, 7))
        var operation = 0
        while operation < 6 {
            let result = catch_panic(fn(): Unit {
                let marker = Counted(callback_counter, 1)
                if operation == 0 {
                    let _ = core.cell.Ref<Counted>.map(cell.borrow(),
                        take fn(read value: Counted): read i32 from value {
                            let owned = marker
                            panic("shared projection")
                        })
                } else if operation == 1 {
                    let _ = capture core.cell.Ref<Counted>.filter_map(cell.borrow(),
                        take fn(read value: Counted): (read i32 from value)? {
                            let owned = marker
                            panic("shared optional projection")
                        })
                } else if operation == 2 {
                    let _ = core.cell.Ref<Counted>.map_split(cell.borrow(),
                        take fn(read value: Counted): (
                            read i32 from value, read i32 from value
                        ) {
                            let owned = marker
                            panic("shared split")
                        })
                } else if operation == 3 {
                    let _ = core.cell.RefMut<Counted>.map(cell.borrow_mut(),
                        take fn(mut value: Counted): mut i32 from value {
                            let owned = marker
                            value.value += 1
                            panic("exclusive projection")
                        })
                } else if operation == 4 {
                    let _ = capture core.cell.RefMut<Counted>.filter_map(cell.borrow_mut(),
                        take fn(mut value: Counted): (mut i32 from value)? {
                            let owned = marker
                            value.value += 1
                            panic("exclusive optional projection")
                        })
                } else {
                    let _ = core.cell.RefMut<Counted>.map_split(cell.borrow_mut(),
                        take fn(mut value: Counted): (
                            mut i32 from value, mut i32 from value
                        ) {
                            let owned = marker
                            value.value += 1
                            panic("exclusive split")
                        })
                }
            })
            match result {
                CatchResult.Panicked(_) => {},
                CatchResult.Returned(_) => { return 1 }
            }
            if !released(cell) || callback_drops != operation + 1 ||
                payload_drops != 0 {
                return 2
            }
            operation += 1
        }
        if cell.borrow().get_ref().value != 10 { return 3 }
        {
            let projected = core.cell.Ref<Counted>.map(cell.borrow(),
                fn(read value: Counted): read i32 from value { read value.value })
            if *projected.get_ref() != 10 { return 4 }
        }
        if payload_drops != 0 || !released(cell) { return 5 }
    }
    if payload_drops != 1 || callback_drops != 6 { return 6 }
    0
}
