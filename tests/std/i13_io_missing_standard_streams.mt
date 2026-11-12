import core.fmt
import std.fs.File
import std.io.{BufRead, Error, Reader, Seek, SeekFrom, Writer}
import std.path.path_from_text
import std.sys

static ATTEMPTED: core.sync.atomic.AtomicBool = core.sync.atomic.AtomicBool.new(false)
static COMPLETED: core.sync.atomic.AtomicBool = core.sync.atomic.AtomicBool.new(false)

extern "C" {
    unsafe fn dup2(source: i32, target: i32): i32;
    unsafe fn pipe(descriptors: ptr<mut i32>): i32;
}

type Redirect {
    target: i32
    saved: i32
    drop {
        let _ = unsafe { dup2(self.saved, self.target) }
        let _ = unsafe { sys.close(self.saved) }
    }
}

fn redirect(source: i32, target: i32): Redirect throws Error {
    let saved = unsafe { sys.mettle_rt_dup(target) }
    if saved < 0i32 { throw std.io.last_os_error() }
    let owner = Redirect(target, saved)
    if unsafe { dup2(source, target) } < 0i32 { throw std.io.last_os_error() }
    owner
}

type RecursiveOutput {}
extend RecursiveOutput implements fmt.Display {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        var nested = std.io.stdout().lock()
        match take capture nested.write_all("nested".as_bytes()) {
            success(_) => {},
            failure(_) => { throw fmt.Error() }
        }
        try formatter.write_str("payload")
    }
}

type PanickingOutput {}
extend PanickingOutput implements fmt.Display {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        var nested = std.io.stdout().lock()
        match take capture nested.write_all("unwound\n".as_bytes()) {
            success(_) => {},
            failure(_) => { throw fmt.Error() }
        }
        panic("format callback")
    }
}

fn run(): i32 throws Error {
    let input = path_from_text("i13-io-standard-input")
    try std.fs.write(input, "alpha\nbeta\nend".as_bytes())
    let file = try File.open(input)
    {
        let redirected = try redirect(file.as_raw_fd(), 0i32)
        var first = std.io.stdin()
        let copied = first
        {
            var guard = first.lock()
            let available = try guard.fill_buf()
            match take std.panic.catch_panic(fn(): Unit {
                var nested = copied.lock()
                var byte = [0u8]
                let _ = capture nested.read_some(mut byte)
            }) {
                std.panic.CatchResult.Panicked(_) => {},
                _ => { return 1 }
            }
            assert(available[0usize] == 97u8, "recursive read cannot invalidate a live buffer view")
            guard.consume(1usize)
        }
        var second = copied
        var bytes = [0u8; 2]
        assert(try second.read_some(mut bytes) == 2usize && bytes[0usize] == 108u8 &&
            bytes[1usize] == 112u8, "copied handles share unread prefetched bytes")
        var line = alloc.string.new()
        assert(try first.read_line(mut line) == 3usize && line.as_text() == "ha\n",
            "read_line uses the same shared buffer")
        var lines = copied.lines()
        match take lines.next() {
            present(success(value)) => { assert(value.as_text() == "beta", "lines preserve shared position") },
            _ => { return 2 }
        }
        match take lines.next() {
            present(success(value)) => { assert(value.as_text() == "end", "final unterminated line") },
            _ => { return 3 }
        }
        assert(lines.next().is_none(), "EOF releases empty buffer loans")
        var empty = [0u8; 0]
        assert(try second.read_some(mut empty) == 0usize, "recursive empty reads need no payload borrow")
    }
    core.mem.drop(take file)
    try std.fs.remove_file(input)

    var descriptors = [-1i32; 2]
    if unsafe { pipe(core.ptr.from_mut(mut descriptors).cast<i32>()) } != 0i32 {
        throw std.io.last_os_error()
    }
    let reader = unsafe { sys.OwnedFd.from_raw_fd(descriptors[0usize]) }
    var writer = unsafe { sys.OwnedFd.from_raw_fd(descriptors[1usize]) }
    {
        let redirected = try redirect(reader.as_raw_fd(), 0i32)
        let _ = try std.io.write_fd(writer.as_raw_fd(), "xyz".as_bytes())
        var buffer = [0u8; 4096]
        var stdin = std.io.stdin()
        assert(try stdin.read_some(mut buffer) == 3usize && buffer[2usize] == 122u8,
            "a live pipe writer does not make one read wait for the buffer to fill")
        core.mem.drop(take writer)
        assert(try stdin.read_some(mut buffer) == 0usize, "pipe EOF")
    }

    let output = path_from_text("i13-io-standard-output")
    var options = File.options()
    options.`read`(true)
    options.write(true)
    options.create_new(true)
    var output_file = try options.open(output)
    {
        let redirected = try redirect(output_file.as_raw_fd(), 1i32)
        var outer = std.io.stdout().lock()
        try outer.write_all("held".as_bytes())
        assert((try output_file.metadata()).len() == 0u64, "stdout retains an incomplete line")
        {
            var nested = std.io.stdout().lock()
            try nested.write_all("\n".as_bytes())
        }
        try outer.write_line(f"{RecursiveOutput()}")
        try outer.flush()
        core.mem.drop(take outer)
        match take std.panic.catch_panic(fn(): Unit {
            var guard = std.io.stdout().lock()
            let _ = capture guard.write(f"{PanickingOutput()}")
        }) {
            std.panic.CatchResult.Panicked(_) => {},
            _ => { return 4 }
        }
        let shared_output = std.io.stdout()
        let copied_output = shared_output
        var held = shared_output.lock()
        let worker = std.thread.spawn(take fn(): i32 {
            ATTEMPTED.store(true, core.sync.atomic.Ordering.Release)
            var guard = copied_output.lock()
            match take capture guard.write_all("thread\n".as_bytes()) {
                success(_) => {},
                failure(_) => { return 1 }
            }
            COMPLETED.store(true, core.sync.atomic.Ordering.Release)
            0
        })
        while !ATTEMPTED.load(core.sync.atomic.Ordering.Acquire) {
            std.thread.yield_now()
        }
        assert(!COMPLETED.load(core.sync.atomic.Ordering.Acquire),
            "copied handles cannot complete output while another thread holds the stream lock")
        try held.write_all("owner\n".as_bytes())
        core.mem.drop(take held)
        match take capture worker.join() {
            success(code) => {
                assert(code == 0i32 && COMPLETED.load(core.sync.atomic.Ordering.Acquire),
                    "callback unwind releases every recursive lock level")
            },
            failure(_) => { return 5 }
        }
        var stderr = std.io.stderr().lock()
        var stderr_again = std.io.stderr().lock()
        assert(try stderr_again.write_some("".as_bytes()) == 0usize, "stderr locks are recursive")
        try stderr.flush()
    }
    try output_file.rewind()
    var text = alloc.string.new()
    let _ = try output_file.read_to_string(mut text)
    assert(text.as_text() == "held\nnestedpayload\nunwound\nowner\nthread\n",
        "formatting reentrancy releases chunk borrows and shares buffered output")
    core.mem.drop(take output_file)
    try std.fs.remove_file(output)
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
