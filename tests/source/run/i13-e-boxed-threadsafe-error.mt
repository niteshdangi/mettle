// expect-exit: 0
import core.convert.From
import core.error.{Error, ThreadSafeError}
import core.fmt
import core.text.Text
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.Heap
import alloc.string.String

type OwnedThreadError { message: String }
extend OwnedThreadError implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str(self.message.as_text())
    }
}
extend OwnedThreadError implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str(self.message.as_text())
    }
}
extend OwnedThreadError implements Error {}

fn box_thread_error<region r>(
    take error: OwnedThreadError
): Heap<any ThreadSafeError from r> {
    Heap<any ThreadSafeError from r>.(From<OwnedThreadError from r>).from(error)
}

fn box_thread_error_from_text<region r>(
    read message: Text from r
): Heap<any ThreadSafeError from r> {
    Heap<any ThreadSafeError from r>.(From<read Text from r>).from(read message)
}

fn box_thread_error_from_string<region r>(
    take message: String
): Heap<any ThreadSafeError from r> {
    Heap<any ThreadSafeError from r>.(From<String>).from(message)
}

fn box_thread_error_from_cow<region r>(
    take message: BorrowedOrOwned<region r, Text>
): Heap<any ThreadSafeError from r> {
    Heap<any ThreadSafeError from r>.(From<BorrowedOrOwned<region r, Text>>).from(message)
}

fn borrowed_cow<region r>(read message: Text from r): BorrowedOrOwned<region r, Text> {
    BorrowedOrOwned<region r, Text>.Borrowed(read message)
}

fn owned_cow<region r>(take message: String): BorrowedOrOwned<region r, Text> {
    BorrowedOrOwned<region r, Text>.Owned(message)
}

fn error_view<region r>(
    read error: Heap<any ThreadSafeError from r> from r
): read any Error from r {
    read error.get()
}

fn main(): i32 {
    let owner = alloc.string.from_text("error")
    let owned = box_thread_error(OwnedThreadError(alloc.string.from_text("owned error")))
    let _parent: read any Error = error_view(read owned)
    let _text = box_thread_error_from_text(owner.as_text())
    let _string = box_thread_error_from_string(alloc.string.from_text("string error"))
    let _borrowed = box_thread_error_from_cow(borrowed_cow(owner.as_text()))
    let _cow_owned = box_thread_error_from_cow(owned_cow(alloc.string.from_text("cow error")))
    0
}
