// profiles: debug release
import std.ffi.cstring
import std.sys.{close, mettle_rt_open, open_read, OwnedFd}

fn main(): i32 {
    let path = match take capture cstring("/dev/null".as_bytes()) {
        success(value) => value,
        failure(_) => { return 1 }
    }
    let fd = unsafe { mettle_rt_open(path.as_ptr(), open_read(), 0u32) }
    if fd < 0 { return 2 }

    // Safety: open succeeded and this is the unique owner of the descriptor.
    let owned = unsafe { OwnedFd.from_raw_fd(fd) }
    if owned.as_raw_fd() != fd { return 3 }
    let raw = owned.into_raw_fd()
    if raw != fd { return 4 }
    if unsafe { close(raw) } != 0 { return 5 }

    let drop_fd = unsafe { mettle_rt_open(path.as_ptr(), open_read(), 0u32) }
    if drop_fd < 0 { return 6 }
    {
        // Safety: open succeeded and this is the unique owner of the descriptor.
        let owned = unsafe { OwnedFd.from_raw_fd(drop_fd) }
        if owned.as_raw_fd() != drop_fd { return 7 }
    }
    if unsafe { close(drop_fd) } == 0 { return 8 }
    0
}
