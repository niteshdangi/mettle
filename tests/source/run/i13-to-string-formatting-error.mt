// expect-exit: trap
// profiles: debug release

import alloc.string.ToString
import core.fmt
import core.fmt.Write

type BrokenDisplay {}

extend BrokenDisplay implements fmt.Display {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        try formatter.write_str("partial output")
        throw fmt.Error()
    }
}

fn main(): i32 {
    let output = BrokenDisplay().to_string()
    output.len() as i32
}
