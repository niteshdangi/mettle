// profiles: debug release
// expect-stdout: "\nvalue=3\nforward=4\nprobe\nworker\n"
// expect-stderr: "\nerror=5\nprobe\nworker\n"

import core.fmt
import std.io
import std.io.Writer
import std.macros.{eprintln, format, format_args, println}
import std.panic.{catch_panic, CatchResult}
import std.thread

static READY: core.sync.atomic.AtomicBool = core.sync.atomic.AtomicBool.new(false)
static ATTEMPTED: core.sync.atomic.AtomicBool = core.sync.atomic.AtomicBool.new(false)
static ACQUIRED: core.sync.atomic.AtomicBool = core.sync.atomic.AtomicBool.new(false)
static INTERLEAVED: core.sync.atomic.AtomicBool = core.sync.atomic.AtomicBool.new(false)

type BrokenDisplay {}
extend BrokenDisplay implements fmt.Display {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        try formatter.write_str("partial")
        throw fmt.Error()
    }
}

type LockProbe {}
extend LockProbe implements fmt.Display {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        READY.store(true, core.sync.atomic.Ordering.Release)
        while !ATTEMPTED.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
        var attempts = 0usize
        while attempts < 256usize {
            if ACQUIRED.load(core.sync.atomic.Ordering.Acquire) {
                INTERLEAVED.store(true, core.sync.atomic.Ordering.Release)
                break
            }
            thread.yield_now()
            attempts += 1usize
        }
        try formatter.write_str("probe")
    }
}

fn check_line_lock(stderr: bool): bool {
    READY.store(false, core.sync.atomic.Ordering.Relaxed)
    ATTEMPTED.store(false, core.sync.atomic.Ordering.Relaxed)
    ACQUIRED.store(false, core.sync.atomic.Ordering.Relaxed)
    INTERLEAVED.store(false, core.sync.atomic.Ordering.Relaxed)
    let worker = thread.spawn(take fn(): i32 {
        while !READY.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
        ATTEMPTED.store(true, core.sync.atomic.Ordering.Release)
        if stderr {
            var guard = io.stderr().lock()
            ACQUIRED.store(true, core.sync.atomic.Ordering.Release)
            match take capture guard.write_all("worker\n".as_bytes()) {
                success(_) => {},
                failure(_) => { return 1 }
            }
        } else {
            var guard = io.stdout().lock()
            ACQUIRED.store(true, core.sync.atomic.Ordering.Release)
            match take capture guard.write_all("worker\n".as_bytes()) {
                success(_) => {},
                failure(_) => { return 1 }
            }
        }
        0
    })
    if stderr { eprintln!(f"{LockProbe()}") } else { println!(f"{LockProbe()}") }
    match take capture worker.join() {
        success(code) => {
            code == 0 && ACQUIRED.load(core.sync.atomic.Ordering.Acquire) &&
                !INTERLEAVED.load(core.sync.atomic.Ordering.Acquire)
        },
        failure(_) => false
    }
}

fn next(mut count: i32): i32 {
    count += 1
    count
}

fn main(): i32 {
    var count = 0i32
    let text = format!(f"{next(mut count)}:{next(mut count)}",)
    if count != 2 || text.as_text() != "1:2" { return 1 }
    let plain = format!("plain")
    if plain.as_text() != "plain" { return 2 }

    println!()
    println!(f"value={next(mut count)}",)
    println!(format_args!(f"forward={next(mut count)}",))
    eprintln!()
    eprintln!(f"error={next(mut count)}",)
    if count != 5 { return 3 }

    if !check_line_lock(false) || !check_line_lock(true) { return 5 }
    match take catch_panic(fn(): i32 {
        let _ = format!(f"{BrokenDisplay()}")
        0
    }) {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 4 }
    }
    0
}
