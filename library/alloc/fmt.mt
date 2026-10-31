// Allocating formatting. `string` is the owned-result counterpart of the
// borrowed `format` parameter: it renders a message into a new `String`.
import package.core.fmt
import package.alloc.string.String

// Renders `message`. A formatter failure panics, because no sink can fail here.
pub fn string(message: format fmt.Message): String {
    var out = package.alloc.string.new()
    let outcome = capture message.write_to(mut out)
    match take outcome {
        success(_) => {},
        failure(_) => { package.core.panic.panic("a formatting implementation returned an error") }
    }
    out
}
