// profiles: debug release

import core.cell.OnceCell
import core.clone.Clone
import core.borrow.{Borrow, ToOwned}
import core.any
import core.cmp.Eq
import core.convert.From
import core.convert.Into
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.text.Text

type Counted {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += self.value } }
}

extend Counted implements Clone {
    fn clone(): Counted { Counted(self.drops, self.value + 1) }
}

fn transferable<T: Transferable>() {}
fn equal<T: Eq>(read a: T, read b: T): bool { a == b }
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
    var value = OnceCell<i32>.new()
    if value.get().is_present() || value.get_mut().is_present() { return 1 }
    if !debug_is(value, "OnceCell(<uninit>)") { return 2 }
    if !equal(value, value.clone()) { return 3 }
    let defaulted = OnceCell<i32>.(Default).default()
    if !equal(value, defaulted) { return 4 }
    var calls = 0
    if *value.get_or_init(fn(): i32 { calls += 1; 42 }) != 42 { return 5 }
    if *value.get_or_init(fn(): i32 { calls += 1; 99 }) != 42 || calls != 1 {
        return 6
    }
    let held = value.get().or_panic()
    match capture value.set(17) {
        success(_) => { return 7 },
        failure(rejected) => { if rejected != 17 || *held != 42 { return 8 } }
    }
    if !debug_is(value, "OnceCell(42)") { return 9 }
    if equal(value, defaulted) || equal(defaulted, value) { return 26 }
    let borrowed = OnceCell<i32>.(Borrow<OnceCell<i32>>).borrow(read value)
    if core.ptr.from_ref(borrowed) != core.ptr.from_ref(value) ||
        *borrowed.get().or_panic() != 42 {
        return 27
    }
    match any.downcast_ref<OnceCell<i32>>(read value) {
        present(found) => { if *found.get().or_panic() != 42 { return 28 } },
        none => { return 29 }
    }
    if any.is<OnceCell<u32>>(read value) { return 30 }
    let copied = value.to_owned()
    let converted = OnceCell<i32>.(From<i32>).from(42)
    let converted_into: OnceCell<i32> = 42i32.into()
    if !equal(value, copied) || !equal(value, converted) ||
        !equal(value, converted_into) {
        return 10
    }
    *value.get_mut().or_panic() = 43
    if *value.get().or_panic() != 43 || *copied.get().or_panic() != 42 ||
        equal(value, copied) {
        return 11
    }
    if value.`take`().or_panic() != 43 || value.get().is_present() { return 12 }
    if value.`take`().is_present() { return 13 }
    match capture value.set(44) {
        success(_) => {},
        failure(_) => { return 14 }
    }
    if value.into_inner().or_panic() != 44 { return 15 }
    if OnceCell<i32>.new().into_inner().is_present() { return 16 }
    transferable<OnceCell<i32>>()
    transferable<OnceCell<core.cell.Cell<i32>>>()

    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var owned = OnceCell<Counted>.new()
        match capture owned.set(Counted(counter, 1)) {
            success(_) => {},
            failure(_) => { return 17 }
        }
        match take capture owned.set(Counted(counter, 10)) {
            success(_) => { return 18 },
            failure(rejected) => {
                if rejected.value != 10 || drops != 0 { return 19 }
            }
        }
        if drops != 10 { return 20 }
        let extracted = owned.`take`().or_panic()
        if extracted.value != 1 || owned.get().is_present() { return 21 }
        match capture owned.set(Counted(counter, 100)) {
            success(_) => {},
            failure(_) => { return 22 }
        }
        let consumed = owned.into_inner().or_panic()
        if consumed.value != 100 || drops != 10 { return 23 }
    }
    if drops != 111 { return 24 }
    {
        let owned = OnceCell<Counted>.(From<Counted>).from(Counted(counter, 1000))
    }
    if drops != 1111 { return 25 }
    {
        var owned = OnceCell<Counted>.(From<Counted>).from(Counted(counter, 10))
        let cloned = owned.clone()
        let copied = owned.to_owned()
        owned.get_mut().or_panic().value = 20
        if cloned.get().or_panic().value != 11 || copied.get().or_panic().value != 11 ||
            owned.get().or_panic().value != 20 || drops != 1111 {
            return 31
        }
    }
    if drops != 1153 { return 32 }
    0
}
