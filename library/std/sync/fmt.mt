import super.condition
import core.fmt.{Debug, Error, Formatter}

extend condition.TimedOut implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("TimedOut")
        try debug.field("timed_out", self.timed_out())
        try debug.finish()
    }
}
