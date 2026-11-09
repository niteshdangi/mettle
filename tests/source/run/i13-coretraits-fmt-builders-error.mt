import core.error.Error
import core.fmt
import core.fmt.Debug
import core.fmt.Display
import core.fmt.Formatter
import core.fmt.Spec
import core.fmt.Write
import core.option

type LocalError {}
type OuterError { cause: LocalError }
extend LocalError implements Debug {
    fn fmt(f: mut Formatter): Unit throws fmt.Error { try f.write_str("local") }
}
extend LocalError implements Display {
    fn fmt(f: mut Formatter): Unit throws fmt.Error { try f.write_str("local") }
}
extend LocalError implements Error {}
extend OuterError implements Debug {
    fn fmt(f: mut Formatter): Unit throws fmt.Error {
        var builder = try f.debug_struct("OuterError")
        try builder.field("cause", read self.cause)
        try builder.finish()
    }
}
extend OuterError implements Display {
    fn fmt(f: mut Formatter): Unit throws fmt.Error { try f.write_str("outer") }
}
extend OuterError implements Error {
    fn source<region r>(receiver self: read OuterError from r): (read any Error from r)? {
        let cause: read any Error = read self.cause
        present(cause)
    }
}

fn render(): i32 throws fmt.Error {
    var bytes = [0u8; 128]
    var output = fmt.buffer_writer(mut bytes)
    let options = Spec(' ', fmt.Align.Unknown, none, none, false, true, false, false)
    var f = fmt.formatter(mut output, options)
    if !f.sign_minus() || f.sign_plus() || f.sign_aware_zero_pad() { return 1 }

    var structure = try f.debug_struct("S")
    try structure.field("x", 1i32)
    try structure.finish()

    var tuple = try f.debug_tuple("T")
    try tuple.field(2i32)
    try tuple.finish()

    var list = try f.debug_list()
    try list.entry(3i32)
    try list.finish()

    var set = try f.debug_set()
    try set.entry(4i32)
    try set.finish()

    var map = try f.debug_map()
    try map.entry(5i32, 6i32)
    try map.finish()

    var split_map = try f.debug_map()
    try split_map.key(7i32)
    try split_map.value(8i32)
    try split_map.finish()

    let length = output.len()
    match fmt.written_text(read bytes, length) {
        present(text) => {
            if text != "S { x: 1 }T(2)[3]{4}{5: 6}{7: 8}" { return 2 }
        },
        none => { return 2 }
    }
    if LocalError().source().is_present() { return 3 }
    if OuterError(LocalError()).source().is_none() { return 4 }
    0
}

fn main(): i32 {
    match take capture render() {
        success(code) => code,
        failure(error) => 99
    }
}
