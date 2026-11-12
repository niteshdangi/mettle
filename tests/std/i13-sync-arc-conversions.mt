// expect-exit: 0
// Evidence for Arc equality, the erased-owner downcast, the path/OS-string/C-string
// conversions into Arc, and RwLock write-guard downgrade.
import alloc.arc
import alloc.borrow.BorrowedOrOwned
import alloc.ffi.CString
import alloc.vec
import core.any.Any
import core.cmp.{Eq, PartialEq}
import core.convert.From
import core.ffi.CStr
import core.ops.DerefMut
import alloc.boxed.Box
import core.text.Text
import std.ffi.{OsStr, OsString, os_str_from_text, os_str_mut, os_string_from_text}
import std.path.{Path, PathBuf, path_buf_from_text, path_from_text}
import std.sync.rwlock

fn require_eq<T: Eq>(read value: T): Unit {}

fn checks_equality(): i32 {
    let left = arc.new(4)
    let same = arc.new(4)
    let other = arc.new(5)
    require_eq(read left)
    if left != same || !(left == same) { return 10 }
    if left == other || !(left != other) { return 11 }
    0
}

fn checks_downcast(): i32 {
    let erased: arc.Arc<any Any> = arc.new(25i32)
    match take erased.downcast<i32>() {
        success(value) => { if *value.get() != 25 { return 20 } },
        failure(_) => { return 21 }
    }
    let wrong: arc.Arc<any Any> = arc.new(26i32)
    match take wrong.downcast<u32>() {
        success(_) => { return 22 },
        failure(value) => {
            let observer = value.retain()
            match take value.downcast<i32>() {
                success(original) => {
                    if *original.get() != 26 || original.strong_count() != 2usize { return 23 }
                },
                failure(_) => { return 24 }
            }
            core.mem.drop(observer)
        }
    }
    0
}

fn checks_path_conversions(): i32 {
    let owned = arc.Arc<Path>.(From<PathBuf>).from(take path_buf_from_text("dir/file"))
    if owned.get().as_os_str().as_bytes() != "dir/file".as_bytes() { return 30 }
    let borrowed = arc.Arc<Path>.(From<read Path>).from(take path_from_text("a/b"))
    if borrowed.get().as_os_str().as_bytes() != "a/b".as_bytes() { return 31 }
    var buffer = path_buf_from_text("m/n")
    let mutable = arc.Arc<Path>.(From<mut Path>).from(take buffer.as_mut_path())
    if mutable.get().as_os_str().as_bytes() != "m/n".as_bytes() { return 32 }
    0
}

fn checks_os_string_conversions(): i32 {
    let owned = arc.Arc<OsStr>.(From<OsString>).from(take os_string_from_text("os"))
    if owned.get().as_bytes() != "os".as_bytes() { return 40 }
    let borrowed = arc.Arc<OsStr>.(From<read OsStr>).from(take os_str_from_text("view"))
    if borrowed.get().as_bytes() != "view".as_bytes() { return 41 }
    var bytes = [111u8, 107u8]
    let mutable = arc.Arc<OsStr>.(From<mut OsStr>).from(take os_str_mut(mut bytes))
    if mutable.get().as_bytes() != "ok".as_bytes() { return 42 }
    0
}

fn checks_c_string_conversions(): i32 {
    let source = match take capture CString.new(vec.from_array([104u8, 105u8])) {
        success(value) => value,
        failure(_) => { return 50 }
    }
    let borrowed = arc.Arc<CStr>.(From<read CStr>).from(take source.as_c_str())
    if borrowed.get().to_bytes() != "hi".as_bytes() { return 51 }
    let owned = arc.Arc<CStr>.(From<CString>).from(take source)
    if owned.get().to_bytes() != "hi".as_bytes() { return 52 }
    let other = match take capture CString.new(vec.from_array([121u8, 111u8])) {
        success(value) => value,
        failure(_) => { return 53 }
    }
    var boxed = other.into_boxed_c_str()
    let mutable = arc.Arc<CStr>.(From<mut CStr>).from(take Box<CStr>.(DerefMut).deref_mut(mut boxed))
    if mutable.get().to_bytes() != "yo".as_bytes() { return 54 }
    0
}

fn checks_borrowed_or_owned(): i32 {
    let borrowed: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("shared")
    let from_borrowed = arc.Arc<Text>.(From<BorrowedOrOwned<region static, Text>>).from(take borrowed)
    if from_borrowed.get() != "shared" { return 60 }
    let owned: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(alloc.string.from_text("moved"))
    let from_owned = arc.Arc<Text>.(From<BorrowedOrOwned<region static, Text>>).from(take owned)
    if from_owned.get() != "moved" { return 61 }
    0
}

fn checks_write_guard_downgrade(): i32 {
    let lock = rwlock.new(1)
    var writer = match take capture lock.write() { success(g) => g, failure(e) => e.into_inner() }
    *writer.get_mut() = 2
    let reader = writer.downgrade()
    if *reader.get() != 2 { return 70 }
    match take capture lock.try_write() {
        success(_) => { return 71 },
        failure(_) => {}
    }
    match take capture lock.try_read() {
        success(second) => { if *second.get() != 2 { return 72 } },
        failure(_) => { return 73 }
    }
    0
}

fn main(): i32 {
    let a = checks_equality()
    if a != 0 { return a }
    let b = checks_downcast()
    if b != 0 { return b }
    let c = checks_path_conversions()
    if c != 0 { return c }
    let d = checks_os_string_conversions()
    if d != 0 { return d }
    let e = checks_c_string_conversions()
    if e != 0 { return e }
    let f = checks_borrowed_or_owned()
    if f != 0 { return f }
    checks_write_guard_downgrade()
}
