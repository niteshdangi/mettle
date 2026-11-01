// Path iteration is byte-preserving and normalizes only separators and dot
// components; ancestors retain lexical parent components without resolving them.
import core.iter.{ BidirectionalIterator, Iterator }
import core.clone.Clone
import std.ffi
import std.path.{ Component, path, path_from_text }

fn main(): i32 {
    let raw: [u8; 13] = [
        46u8, 47u8, 97u8, 47u8, 47u8, 46u8, 47u8,
        46u8, 46u8, 47u8, 255u8, 47u8, 47u8
    ]
    let bad_name: [u8; 1] = [255u8]
    let ordinary_name: [u8; 1] = [97u8]
    let last_name: [u8; 1] = [98u8]
    let dot_name: [u8; 1] = [46u8]
    let source = path(raw)
    var components = (*source).components()
    if !(*components.as_path()).same(*source) { return 1 }
    match components.next() {
        present(Component.CurDir) => {},
        _ => { return 2 }
    }
    var cloned_components = components.clone()
    match components.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), bad_name) { return 3 }
        },
        _ => { return 4 }
    }
    match components.next_back() {
        present(Component.ParentDir) => {},
        _ => { return 5 }
    }
    match components.next() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 6 }
        },
        _ => { return 7 }
    }
    match components.next() {
        none => {},
        _ => { return 8 }
    }
    match components.next_back() {
        none => {},
        _ => { return 9 }
    }
    match cloned_components.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), bad_name) { return 35 }
        },
        _ => { return 36 }
    }
    match cloned_components.next_back() {
        present(Component.ParentDir) => {},
        _ => { return 37 }
    }
    match cloned_components.next() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 38 }
        },
        _ => { return 39 }
    }

    var pieces = (*source).iter()
    var cloned_pieces = pieces.clone()
    match pieces.next() {
        present(part) => {
            if !ffi.bytes_equal((*part).as_bytes(), dot_name) { return 10 }
        },
        none => { return 11 }
    }
    match cloned_pieces.next() {
        present(part) => {
            if !ffi.bytes_equal((*part).as_bytes(), dot_name) { return 40 }
        },
        none => { return 41 }
    }
    match pieces.next_back() {
        present(part) => {
            if !ffi.bytes_equal((*part).as_bytes(), bad_name) { return 12 }
        },
        none => { return 13 }
    }
    if !pieces.as_path().same(path_from_text("a//./..")) { return 14 }

    var front_advanced = path_from_text("a//./../b///").components()
    match front_advanced.next() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 45 }
        },
        _ => { return 46 }
    }
    if !front_advanced.as_path().same(path_from_text("../b///")) { return 47 }

    var back_advanced = path_from_text("a///./../b").components()
    match back_advanced.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), last_name) { return 48 }
        },
        _ => { return 49 }
    }
    if !back_advanced.as_path().same(path_from_text("a///./..")) { return 50 }

    var only_skipped = path_from_text("a/./b").components()
    match only_skipped.next() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 51 }
        },
        _ => { return 52 }
    }
    match only_skipped.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), last_name) { return 53 }
        },
        _ => { return 54 }
    }
    if !only_skipped.as_path().is_empty() { return 55 }

    var pending_cur_dir = path_from_text("./a").components()
    match pending_cur_dir.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 56 }
        },
        _ => { return 57 }
    }
    if !pending_cur_dir.as_path().same(path_from_text(".")) { return 58 }

    var pending_absolute = path_from_text("///a//b").components()
    match pending_absolute.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), last_name) { return 59 }
        },
        _ => { return 60 }
    }
    let remaining_absolute = pending_absolute.as_path()
    if !(*remaining_absolute).is_absolute() { return 61 }
    if !(*remaining_absolute).same(path_from_text("///a")) { return 62 }

    var pending_root = path_from_text("///./a").components()
    match pending_root.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 69 }
        },
        _ => { return 70 }
    }
    if !pending_root.as_path().same(path_from_text("/")) { return 71 }
    match pending_root.next() {
        present(Component.RootDir) => {},
        _ => { return 72 }
    }
    if !pending_root.as_path().is_empty() { return 73 }

    var front_absolute = path_from_text("///a//./b///").components()
    match front_absolute.next() {
        present(Component.RootDir) => {},
        _ => { return 63 }
    }
    if !front_absolute.as_path().same(path_from_text("a//./b///")) { return 64 }
    match front_absolute.next() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), ordinary_name) { return 65 }
        },
        _ => { return 66 }
    }
    let remaining_relative = front_absolute.as_path()
    if !(*remaining_relative).is_relative() { return 67 }
    if !(*remaining_relative).same(path_from_text("b///")) { return 68 }

    let owned = (*source).to_path_buf()
    var owned_components = owned.components()
    match owned_components.next_back() {
        present(Component.Normal(name)) => {
            if !ffi.bytes_equal((*name).as_bytes(), bad_name) { return 15 }
        },
        _ => { return 16 }
    }

    var root = path_from_text("///").components()
    match root.next_back() {
        present(component) => {
            match component.clone() {
                Component.RootDir => {},
                _ => { return 42 }
            }
        },
        _ => { return 17 }
    }
    match root.next() {
        none => {},
        _ => { return 18 }
    }

    var ancestors = path_from_text("./a/../").ancestors()
    match ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("./a/../")) { return 19 }
        },
        none => { return 20 }
    }
    var cloned_ancestors = ancestors.clone()
    match ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("./a")) { return 21 }
        },
        none => { return 22 }
    }
    match cloned_ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("./a")) { return 43 }
        },
        none => { return 44 }
    }
    match ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text(".")) { return 23 }
        },
        none => { return 24 }
    }
    match ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("")) { return 25 }
        },
        none => { return 26 }
    }
    match ancestors.next() {
        none => {},
        present(current) => { return 27 }
    }

    var absolute_ancestors = path_from_text("///a//b///").ancestors()
    match absolute_ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("///a//b///")) { return 28 }
        },
        none => { return 29 }
    }
    match absolute_ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("///a")) { return 30 }
        },
        none => { return 31 }
    }
    match absolute_ancestors.next() {
        present(current) => {
            if !(*current).same(path_from_text("/")) { return 32 }
        },
        none => { return 33 }
    }
    match absolute_ancestors.next() {
        none => {},
        present(current) => { return 34 }
    }
    0
}
