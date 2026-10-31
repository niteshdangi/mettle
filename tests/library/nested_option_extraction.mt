import core.option

fn main(): i32 {
    var full: i32?? = present(present(23))
    match take full {
        present(inner) => match take inner {
            present(value) => { if value != 23 { return 1 } },
            none => { return 2 }
        },
        none => { return 3 }
    }

    var inner_absent: i32?? = present(none)
    match take inner_absent {
        present(inner) => match take inner {
            present(_) => { return 4 },
            none => {}
        },
        none => { return 5 }
    }

    var outer_absent: i32?? = none
    match take outer_absent {
        present(_) => { return 6 },
        none => {}
    }
    0
}
