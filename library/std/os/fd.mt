import alloc.alloc.Allocator
import alloc.arc.Shared
import core.clone.Clone
import core.iter.Phantom
import std.io
import std.sys

pub alias RawFd = i32
pub import std.sys.OwnedFd

pub copy type BorrowedFd<region r> {
    raw: RawFd
    marker: Phantom<read u8 from r>
}

extend<region r> BorrowedFd<region r> {
    // Safety: the descriptor remains live and usable throughout the chosen region.
    pub unsafe static fn borrow_raw<region s>(raw: RawFd): BorrowedFd<region s> {
        BorrowedFd(raw, Phantom<read u8 from s>())
    }

    pub fn as_raw_fd(): RawFd { self.raw }

    pub fn try_clone_to_owned(): OwnedFd throws io.Error {
        let raw = unsafe { sys.mettle_rt_dup(self.raw) }
        if raw < 0i32 { throw io.last_os_error() }
        unsafe { OwnedFd.from_raw_fd(raw) }
    }
}

extend<region r> BorrowedFd<region r> implements Clone {
    fn clone(): BorrowedFd<region r> { self }
}

pub interface AsRawFd {
    fn as_raw_fd(): RawFd;
}

pub interface AsFd {
    fn as_fd<region r>(receiver read self: Self from r): BorrowedFd<region r>;
}

pub interface FromRawFd: Sized {
    // Safety: the caller transfers the live descriptor's sole close obligation.
    unsafe static fn from_raw_fd(raw: RawFd): Self;
}

pub interface IntoRawFd: Sized {
    take fn into_raw_fd(): RawFd;
}

extend<region r> BorrowedFd<region r> implements AsRawFd {
    fn as_raw_fd(): RawFd { self.raw }
}

extend<region r> BorrowedFd<region r> implements AsFd {
    fn as_fd<region s>(receiver read self: Self from s): BorrowedFd<region s> {
        unsafe { BorrowedFd<region s>.borrow_raw(self.raw) }
    }
}

extend OwnedFd implements AsRawFd {
    fn as_raw_fd(): RawFd { self.as_raw_fd() }
}

extend OwnedFd implements AsFd {
    fn as_fd<region r>(receiver read self: Self from r): BorrowedFd<region r> {
        unsafe { BorrowedFd<region r>.borrow_raw(self.as_raw_fd()) }
    }
}

extend OwnedFd implements FromRawFd {
    unsafe static fn from_raw_fd(raw: RawFd): OwnedFd {
        unsafe { OwnedFd.from_raw_fd(raw) }
    }
}

extend OwnedFd implements IntoRawFd {
    take fn into_raw_fd(): RawFd { take self.into_raw_fd() }
}

extend OwnedFd {
    pub fn try_clone(): OwnedFd throws io.Error {
        let raw = unsafe { sys.mettle_rt_dup(self.as_raw_fd()) }
        if raw < 0i32 { throw io.last_os_error() }
        unsafe { OwnedFd.from_raw_fd(raw) }
    }
}

extend<T: AsRawFd + unsized, A: Allocator> Shared<T, A> implements AsRawFd {
    fn as_raw_fd(): RawFd { T.(AsRawFd).as_raw_fd(self.get()) }
}

extend<T: AsFd + unsized, A: Allocator> Shared<T, A> implements AsFd {
    fn as_fd<region r>(receiver read self: Self from r): BorrowedFd<region r> {
        T.(AsFd).as_fd(self.get())
    }
}

extend<region r> BorrowedFd<region r> implements io.IsTerminal {
    fn is_terminal(): bool { sys.is_terminal(self.raw) }
}
