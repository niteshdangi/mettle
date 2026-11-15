// profiles: debug release

import core.cell.LazyCell
import core.fmt
import core.fmt.Debug
import core.convert.From
import core.default.Default
import core.ops.{Deref, DerefMut}
import core.text.Text
import std.panic.{catch_panic, CatchResult}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    var calls = 0
    let counter = core.ptr.from_mut(calls)
    var lazy = LazyCell.new(fn(): i32 {
        unsafe { *counter += 1 }
        41
    })
    if lazy.get().is_present() || !debug_is(lazy, "LazyCell(<uninit>)") {
        return 1
    }
    if lazy.get_mut().is_present() { return 2 }
    if *lazy.force() != 41 || *lazy.force() != 41 || calls != 1 ||
        !debug_is(lazy, "LazyCell(41)") {
        return 3
    }

    var mutable_lazy: LazyCell<i32> = LazyCell.new(fn(): i32 { 12 })
    if *mutable_lazy.force_mut() != 12 { return 4 }
    *mutable_lazy.force_mut() = 13
    if *LazyCell<i32>.(Deref).deref(read mutable_lazy) != 13 ||
        *LazyCell<i32>.(DerefMut).deref_mut(mut mutable_lazy) != 13 {
        return 5
    }

    let initialized = LazyCell<i32>.(From<i32>).from(17)
    match take initialized.into_inner() {
        success(value) => { if value != 17 { return 6 } },
        failure(_) => { return 7 }
    }

    let unforced = LazyCell.new(fn(): i32 { 22 })
    match take unforced.into_inner() {
        success(_) => { return 8 },
        failure(initializer) => { if initializer() != 22 { return 9 } }
    }

    let defaulted = LazyCell<i32>.(Default).default()
    if *defaulted.force() != 0 { return 10 }

    let poisoned = LazyCell.new(fn(): i32 { panic("initializer failed"); 0 })
    match catch_panic(fn(): Unit { let _ = poisoned.force() }) {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 11 }
    }
    match catch_panic(fn(): Unit { let _ = poisoned.force() }) {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 12 }
    }
    0
}
