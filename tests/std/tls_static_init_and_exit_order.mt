// expect-stdout: WB\nWA\nMB\nMA\n
import std::thread;
import std::sync::tls;
import std::io;
import core::sync::atomic::{AtomicUsize, Ordering};

static MAIN_THREAD: AtomicUsize = AtomicUsize::new(0usize);
static FIRST: tls::LocalKey<Marker> = tls::LocalKey(make_first);
static SECOND: tls::LocalKey<Marker> = tls::LocalKey(make_second);

type Marker {
    main: bool
    code: u8
    drop {
        if self.main {
            if self.code == 2u8 { write_line("MB\n".as_bytes()) }
            else { write_line("MA\n".as_bytes()) }
        } else {
            if self.code == 2u8 { write_line("WB\n".as_bytes()) }
            else { write_line("WA\n".as_bytes()) }
        }
    }
}

fn make_first(): Marker {
    Marker(thread::current().raw == MAIN_THREAD.load(Ordering::Relaxed), 1u8)
}

fn make_second(): Marker {
    Marker(thread::current().raw == MAIN_THREAD.load(Ordering::Relaxed), 2u8)
}

fn write_line(text: read [u8]): Unit {
    let _written = capture io::write_fd(1, text)
}

fn main(): i32 {
    MAIN_THREAD.store(thread::current().raw, Ordering::Relaxed)
    let first = FIRST.with(take fn(value: read Marker): bool { value.main })
    match take first {
        present(value) => { if !value { return 1 } },
        none => { return 2 }
    }
    let second = SECOND.with(take fn(value: read Marker): bool { value.main })
    match take second {
        present(value) => { if !value { return 3 } },
        none => { return 4 }
    }

    let worker = thread::spawn(take fn(): i32 {
        let worker_first = FIRST.with(take fn(value: read Marker): bool { value.main })
        let worker_second = SECOND.with(take fn(value: read Marker): bool { value.main })
        let first_is_local = match take worker_first {
            present(value) => !value,
            none => false
        }
        let second_is_local = match take worker_second {
            present(value) => !value,
            none => false
        }
        if first_is_local && second_is_local { 0 } else { 5 }
    })
    let joined = capture worker.join()
    match take joined {
        success(value) => { if value != 0 { return 7 } },
        failure(_) => { return 8 }
    }
    0
}
