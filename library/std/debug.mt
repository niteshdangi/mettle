// Debug printing. `dbg` writes the value's alternate `Debug` form to standard
// error and returns the value unchanged. Source locations are not recorded.
import package.alloc.string
import package.core.fmt
import super.io

pub fn dbg<T: fmt.Debug>(value: take T): T {
    var text = string.new()
    {
        var options = fmt.spec()
        options.alternate = true
        var f = fmt.formatter(mut text, options)
        let outcome = capture T.(fmt.Debug).fmt(read value, mut f)
        match take outcome {
            success(_) => {},
            failure(_) => { package.core.panic.panic("a Debug implementation returned an error") }
        }
    }
    io.eprintln(f"[dbg] {text}")
    value
}
