import core.fmt.{Debug, Error, Formatter}
import super.env.{Args, ArgsOs, SplitPaths, Vars, VarsOs}
import super.io.{BufRead, Bytes, Empty, LineWriter, Reader, Repeat, Split, Writer}
import super.net.{Shutdown, UnixDatagram, UnixListener, UnixStream}
import super.process.ExitCode
import super.sync.mpsc.{IntoIter, Iter}

extend Empty implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("Empty") }
}

extend Repeat implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Repeat")
        try debug.finish_non_exhaustive()
    }
}

extend Args implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Args")
        try debug.field("remaining", self.len())
        try debug.finish_non_exhaustive()
    }
}

extend ArgsOs implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("ArgsOs")
        try debug.field("remaining", self.len())
        try debug.finish_non_exhaustive()
    }
}

extend Vars implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Vars")
        try debug.field("remaining", self.len())
        try debug.finish_non_exhaustive()
    }
}

extend VarsOs implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("VarsOs")
        try debug.field("remaining", self.len())
        try debug.finish_non_exhaustive()
    }
}

extend<region r> SplitPaths<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("SplitPaths")
        try debug.finish_non_exhaustive()
    }
}

extend<W: Writer + Debug + unsized> LineWriter<W> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("LineWriter")
        try debug.field("inner", self.get_ref())
        try debug.finish_non_exhaustive()
    }
}

extend<R: Reader + Debug> Bytes<R> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Bytes")
        try debug.field("inner", self.inner)
        try debug.finish()
    }
}

extend<B: BufRead + Debug> Split<B> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Split")
        try debug.field("buf", self.reader)
        try debug.field("delim", self.delimiter)
        try debug.finish()
    }
}

extend ExitCode implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("ExitCode")
        try debug.finish_non_exhaustive()
    }
}

extend Shutdown implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            Shutdown.Read => try f.write_str("Read"),
            Shutdown.Write => try f.write_str("Write"),
            Shutdown.Both => try f.write_str("Both")
        }
    }
}

extend UnixStream implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("UnixStream")
        try debug.finish_non_exhaustive()
    }
}

extend UnixListener implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("UnixListener")
        try debug.finish_non_exhaustive()
    }
}

extend UnixDatagram implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("UnixDatagram")
        try debug.finish_non_exhaustive()
    }
}

extend<region r, T: Debug> Iter<region r, T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Iter")
        try debug.finish_non_exhaustive()
    }
}

extend<T: Debug> IntoIter<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("IntoIter")
        try debug.finish_non_exhaustive()
    }
}
