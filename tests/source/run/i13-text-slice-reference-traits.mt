// profiles: debug release
import core.borrow.{AsMut, AsRef}
import core.text.Text
import std.ffi.OsStr
import std.path.Path

fn same_ref<T: unsized>(read value: T): read T from value { T.(AsRef<T>).as_ref(value) }
fn same_mut<T: unsized>(mut value: T): mut T from value { T.(AsMut<T>).as_mut(value) }

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
    0
}
