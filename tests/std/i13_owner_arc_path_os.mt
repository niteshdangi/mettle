import alloc.arc.Shared
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.Heap
import alloc.rc.LocalShared
import core.clone.Clone
import core.convert.From
import std.ffi.{OsStr, OsString, bytes_equal, os_string_from_bytes}
import std.path.{Path, PathBuf, path_buf_from_bytes}

fn copy_path<region r>(read value: Path from r): Shared<Path> {
    Shared<Path>.(From<read Path from r>).from(read value)
}

fn copy_mut_path<region r>(mut value: Path from r): Shared<Path> {
    Shared<Path>.(From<mut Path from r>).from(mut value)
}

fn copy_os<region r>(read value: OsStr from r): Shared<OsStr> {
    Shared<OsStr>.(From<read OsStr from r>).from(read value)
}

fn copy_mut_os<region r>(mut value: OsStr from r): Shared<OsStr> {
    Shared<OsStr>.(From<mut OsStr from r>).from(mut value)
}

fn box_rc_path<region r>(read value: Path from r): (Heap<Path>, LocalShared<Path>) {
    (Heap<Path>.(From<read Path from r>).from(read value),
        LocalShared<Path>.(From<read Path from r>).from(read value))
}

fn box_rc_mut_path<region r>(mut value: Path from r): (Heap<Path>, LocalShared<Path>) {
    let boxed = Heap<Path>.(From<mut Path from r>).from(mut value)
    (boxed, LocalShared<Path>.(From<mut Path from r>).from(mut value))
}

fn box_rc_os<region r>(read value: OsStr from r): (Heap<OsStr>, LocalShared<OsStr>) {
    (Heap<OsStr>.(From<read OsStr from r>).from(read value),
        LocalShared<OsStr>.(From<read OsStr from r>).from(read value))
}

fn box_rc_mut_os<region r>(mut value: OsStr from r): (Heap<OsStr>, LocalShared<OsStr>) {
    let boxed = Heap<OsStr>.(From<mut OsStr from r>).from(mut value)
    (boxed, LocalShared<OsStr>.(From<mut OsStr from r>).from(mut value))
}

fn boxed_and_rc(read bytes: [u8]): Unit {
    var path = path_buf_from_bytes(bytes)
    let path_read = box_rc_path(path.as_path())
    let path_mut = box_rc_mut_path(path.as_mut_path())
    path.clear()
    assert(bytes_equal(path_read.0.get().as_bytes(), bytes) &&
        bytes_equal(path_read.1.get().as_bytes(), bytes) &&
        bytes_equal(path_mut.0.get().as_bytes(), bytes) &&
        bytes_equal(path_mut.1.get().as_bytes(), bytes),
        "boxed and LocalShared path copies retain raw bytes independently of either borrowed view")
    var os = os_string_from_bytes(bytes)
    let os_read = box_rc_os(os.as_os_str())
    let os_mut = box_rc_mut_os(os.as_mut_os_str())
    os.clear()
    assert(bytes_equal(os_read.0.get().as_bytes(), bytes) &&
        bytes_equal(os_read.1.get().as_bytes(), bytes) &&
        bytes_equal(os_mut.0.get().as_bytes(), bytes) &&
        bytes_equal(os_mut.1.get().as_bytes(), bytes),
        "boxed and LocalShared OS copies retain raw bytes after the source is cleared")

    let owned_path = LocalShared<Path>.(From<PathBuf>).from(path_buf_from_bytes(bytes))
    let owned_os = LocalShared<OsStr>.(From<OsString>).from(os_string_from_bytes(bytes))
    let sibling = owned_path.clone()
    let observer = sibling.downgrade()
    core.mem.drop(owned_path)
    assert(bytes_equal(sibling.get().as_bytes(), bytes) &&
        bytes_equal(owned_os.get().as_bytes(), bytes), "owned LocalShared conversions preserve dynamic byte tails")
    core.mem.drop(sibling)
    assert(observer.upgrade().is_none(), "LocalShared path payload retires on the last strong drop")

    let os_owner = os_string_from_bytes(bytes)
    let boxed_os = Heap<OsStr>.(From<OsString>).from(os_owner)
    assert(bytes_equal(boxed_os.get().as_bytes(), bytes),
        "owned OS boxing retains its byte extent")

    let path_owner = path_buf_from_bytes(bytes)
    let path_cow: BorrowedOrOwned<region static, Path> = BorrowedOrOwned.Owned(path_owner)
    let boxed_path = Heap<Path>.(From<BorrowedOrOwned<region static, Path>>).from(path_cow)
    assert(bytes_equal(boxed_path.get().as_bytes(), bytes),
        "owned path Cow boxing retains its byte extent")
    let os_cow: BorrowedOrOwned<region static, OsStr> =
        BorrowedOrOwned.Owned(os_string_from_bytes(bytes))
    assert(bytes_equal(Heap<OsStr>.(From<BorrowedOrOwned<region static, OsStr>>).from(os_cow).get().as_bytes(), bytes),
        "owned OS Cow boxing preserves all bytes")
    borrowed_cow_boxes(boxed_path.get(), boxed_os.get())
}

fn borrowed_cow_boxes<region r>(read path: Path from r, read os: OsStr from r): Unit {
    let path_cow: BorrowedOrOwned<region r, Path> = BorrowedOrOwned.Borrowed(read path)
    let os_cow: BorrowedOrOwned<region r, OsStr> = BorrowedOrOwned.Borrowed(read os)
    let boxed_path = Heap<Path>.(From<BorrowedOrOwned<region r, Path>>).from(path_cow)
    let boxed_os = Heap<OsStr>.(From<BorrowedOrOwned<region r, OsStr>>).from(os_cow)
    assert(bytes_equal(boxed_path.get().as_bytes(), path.as_bytes()) &&
        bytes_equal(boxed_os.get().as_bytes(), os.as_bytes()),
        "borrowed Cow boxing copies complete native byte views")
}

fn main(): i32 {
    let bytes = [97u8, 47u8, 255u8, 0u8, 122u8]
    boxed_and_rc(read bytes)
    var path = path_buf_from_bytes(read bytes)
    let shared_path = copy_path(path.as_path())
    let exclusive_path = copy_mut_path(path.as_mut_path())
    path.clear()
    assert(path.as_bytes().len() == 0usize &&
        bytes_equal(shared_path.get().as_bytes(), read bytes) &&
        bytes_equal(exclusive_path.get().as_bytes(), read bytes),
        "shared and exclusive path conversions copy arbitrary bytes and release their loans")
    let path_owner = path_buf_from_bytes(read bytes)
    let owned_path = Shared<Path>.(From<PathBuf>).from(path_owner)
    assert(bytes_equal(owned_path.get().as_bytes(), read bytes), "owned path conversion retains slice-tail length")
    let sibling = owned_path.clone()
    let observer = sibling.downgrade()
    core.mem.drop(owned_path)
    assert(sibling.strong_count() == 1usize && bytes_equal(sibling.get().as_bytes(), read bytes),
        "retained path survives the original owner")
    core.mem.drop(sibling)
    assert(observer.upgrade().is_none(), "last path strong drop prevents resurrection")

    var os = os_string_from_bytes(read bytes)
    let shared_os = copy_os(os.as_os_str())
    let exclusive_os = copy_mut_os(os.as_mut_os_str())
    os.clear()
    assert(os.as_bytes().len() == 0usize &&
        bytes_equal(shared_os.get().as_bytes(), read bytes) &&
        bytes_equal(exclusive_os.get().as_bytes(), read bytes),
        "shared and exclusive OS-string conversions preserve interior NUL and non-Unicode bytes")
    let owned_os = Shared<OsStr>.(From<OsString>).from(os_string_from_bytes(read bytes))
    assert(bytes_equal(owned_os.get().as_bytes(), read bytes), "owned OS-string conversion preserves metadata")
    let empty: [u8; 0] = []
    boxed_and_rc(read empty)
    let empty_path = Shared<Path>.(From<PathBuf>).from(path_buf_from_bytes(read empty))
    let empty_os = Shared<OsStr>.(From<OsString>).from(os_string_from_bytes(read empty))
    assert(empty_path.get().as_bytes().len() == 0usize && empty_os.get().as_bytes().len() == 0usize,
        "empty unsized payloads retain zero-length metadata with a live count header")
    let path_cow: BorrowedOrOwned<region static, Path> =
        BorrowedOrOwned.Owned(path_buf_from_bytes(read bytes))
    let os_cow: BorrowedOrOwned<region static, OsStr> =
        BorrowedOrOwned.Owned(os_string_from_bytes(read bytes))
    assert(bytes_equal(Shared<Path>.(From<BorrowedOrOwned<region static, Path>>).from(path_cow).get().as_bytes(), read bytes) &&
        bytes_equal(Shared<OsStr>.(From<BorrowedOrOwned<region static, OsStr>>).from(os_cow).get().as_bytes(), read bytes),
        "generic Cow conversions dispatch hosted associated owners without alloc importing std")
    0
}
