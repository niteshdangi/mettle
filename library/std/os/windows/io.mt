import core.clone.Clone
import core.ffi.c_void
import core.iter.Phantom

pub alias RawHandle = ptr<mut c_void>
pub alias RawSocket = usize

@link("kernel32")
extern "C" {
    @link_name("CloseHandle")
    unsafe fn close_handle(handle: RawHandle): i32;
}

pub copy type BorrowedHandle<region r> {
    raw: RawHandle
    marker: Phantom<read u8 from r>
}

extend<region r> BorrowedHandle<region r> {
    // Safety: the handle must remain open and usable for the returned borrow.
    pub unsafe static fn borrow_raw<region s>(
        raw: RawHandle
    ): BorrowedHandle<region s> {
        BorrowedHandle(raw, Phantom<read u8 from s>())
    }

    pub fn as_raw_handle(): RawHandle { self.raw }
}

extend<region r> BorrowedHandle<region r> implements Clone {
    fn clone(): BorrowedHandle<region r> {
        BorrowedHandle(self.raw, Phantom<read u8 from r>())
    }
}

pub type OwnedHandle {
    raw: RawHandle
    drop {
        if self.raw != core.ptr.null_mut<c_void>() {
            let _closed = unsafe { close_handle(self.raw) }
        }
    }
}

extend OwnedHandle {
    // Safety: `raw` must be a live handle whose CloseHandle obligation transfers.
    pub unsafe static fn from_raw_handle(raw: RawHandle): OwnedHandle {
        OwnedHandle(raw)
    }

    pub fn as_raw_handle(): RawHandle { self.raw }

    pub take fn into_raw_handle(): RawHandle {
        var this = self
        let raw = this.raw
        this.raw = core.ptr.null_mut<c_void>()
        raw
    }
}

pub copy type BorrowedSocket<region r> {
    raw: RawSocket
    marker: Phantom<read u8 from r>
}

extend<region r> BorrowedSocket<region r> {
    // Safety: the socket must remain open and usable for the returned borrow.
    pub unsafe static fn borrow_raw<region s>(
        raw: RawSocket
    ): BorrowedSocket<region s> {
        BorrowedSocket(raw, Phantom<read u8 from s>())
    }

    pub fn as_raw_socket(): RawSocket { self.raw }
}

extend<region r> BorrowedSocket<region r> implements Clone {
    fn clone(): BorrowedSocket<region r> {
        BorrowedSocket(self.raw, Phantom<read u8 from r>())
    }
}
