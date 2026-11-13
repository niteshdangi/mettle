// profiles: debug release

import core.pin

fn main(): i32 {
    var value = present(3i32)
    {
        var pin = core.pin.Pin.new(mut value)
        match pin.as_ref().as_pin_ref() {
            present(projected) => {
                if *projected.get_ref() != 3 { return 1 }
            },
            none => { return 2 }
        }
        match take pin.as_mut().as_pin_mut() {
            present(projected) => {
                var target = projected
                *target.get_mut() = 4
            },
            none => { return 3 }
        }
    }
    if value.or_panic() != 4 { return 4 }

    var empty: i32? = none
    {
        var pin = core.pin.Pin.new(mut empty)
        match pin.as_ref().as_pin_ref() {
            present(_) => { return 5 },
            none => {}
        }
        match pin.as_mut().as_pin_mut() {
            present(_) => { return 6 },
            none => {}
        }
    }
    if !empty.is_none() { return 7 }
    0
}
