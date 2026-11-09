// Error composition stays allocation-free: a source is a borrowed erased
// error whose lifetime is bounded by the value returning it.
import super.fmt.Debug
import super.fmt.Display

pub interface Error: Debug + Display {
    fn source<region r>(receiver read self: Self from r): (read any Error from r)? {
        none
    }
}
