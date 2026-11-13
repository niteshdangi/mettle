// profiles: debug release
import core.borrow.{AsMut, AsRef}
import core.convert.TryFrom
import core.text.Text
import std.ffi.OsStr
import std.path.Path

fn same_ref<T: unsized>(read value: T): read T from value { T.(AsRef<T>).as_ref(value) }
fn same_mut<T: unsized>(mut value: T): mut T from value { T.(AsMut<T>).as_mut(value) }

alias TextView<region r> = read Text from r

fn checked_text<region r>(take value: read OsStr from r): (Outcome<read Text from r, core.text.Utf8Error>) {
    TextView<region r>.(TryFrom<read OsStr from r>).try_from(value)
}

fn default_of<T: core.default.Default>(): T { T.(core.default.Default).default() }

fn main(): i32 {
    let text = "path/leaf"
    if same_ref(text) != "path/leaf" { return 1 }
    let bytes: read [u8] = Text.(AsRef<[u8]>).as_ref(text)
    if bytes.len() != 9usize || bytes[0usize] != 112u8 { return 2 }
    let os: read OsStr = Text.(AsRef<OsStr>).as_ref(text)
    if os.as_bytes().len() != 9usize { return 3 }
    let path: read Path = Text.(AsRef<Path>).as_ref(text)
    if path.as_os_str().as_bytes().len() != 9usize { return 4 }

    var values = [1, 2, 3]
    let slice: mut [i32] = mut values
    same_mut(slice)[0usize] = 7
    if values[0usize] != 7 || same_ref(read values[1usize..]).len() != 2usize { return 5 }

    match checked_text(os) {
        success(converted) => { if converted != "path/leaf" { return 7 } },
        failure(error) => { return 6 }
    }

    let empty_view: read [i32] = default_of()
    let empty_cstr: read core.ffi.CStr = default_of()
    var empty_storage: mut [i32] = default_of()
    if empty_view.len() != 0usize || empty_storage.len() != 0usize || empty_cstr.to_bytes().len() != 0usize { return 9 }

    var storage = [97u8, 98u8, 99u8, 100u8]
    var editable: mut Text = unsafe { core.text.from_utf8_unchecked_mut(mut storage) }
    var head: mut Text = mut editable[..2usize]
    if head != "ab" || same_mut(mut head) != "ab" { return 8 }
    0
}
