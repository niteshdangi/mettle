import core.fmt.{Error, buffer_writer, formatter, spec, written_text}
import core.option

fn render(message: format core.fmt.Message): i32 throws Error {
    var bytes = [0u8; 8]
    var output = buffer_writer(mut bytes)
    var f = formatter(mut output, spec())
    if f.width().is_present() || f.precision().is_present() { return 1 }
    if f.alternate() || f.sign_plus() || f.sign_aware_zero_pad() { return 2 }

    try f.write_fmt(message)
    let length = output.len()
    match written_text(read bytes, length) {
        present(text) => { if text != "ok" { return 3 } },
        none => { return 3 }
    }
    0
}

fn main(): i32 {
    match take capture render("ok") {
        success(code) => code,
        failure(error) => 99
    }
}
