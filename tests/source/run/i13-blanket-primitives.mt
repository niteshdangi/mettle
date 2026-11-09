// expect-exit: 0
// profiles: debug release

import core.any.Any
import core.borrow.Borrow
import core.borrow.ToOwned
import core.convert.From
import core.convert.Into
import core.convert.{TryFrom, TryInto}
import alloc.string.ToString

fn any_ok<T: Any>() {}
fn borrow_ok<T: unsized + Borrow<T>>() {}
fn owned_ok<T: ToOwned>() {}
fn from_ok<T: From<T>>() {}
fn into_ok<T: Into<T>>() {}
fn tryfrom_ok<T: TryFrom<T>>() {}
fn tryinto_ok<T: TryInto<T>>() {}
fn string_ok<T: ToString>() {}
fn send_ok<T: Transferable>() {}
fn sync_ok<T: Shareable>() {}
fn any_unsized_ok<T: Any + unsized>() {}
fn send_unsized_ok<T: Transferable + unsized>() {}
fn sync_unsized_ok<T: Shareable + unsized>() {}
fn string_unsized_ok<T: ToString + unsized>() {}

fn main(): i32 {
    // primitive scalar i8
    any_ok<i8>()
    borrow_ok<i8>()
    from_ok<i8>()
    tryfrom_ok<i8>()
    tryinto_ok<i8>()
    into_ok<i8>()
    send_ok<i8>()
    sync_ok<i8>()
    owned_ok<i8>()
    string_ok<i8>()
    // primitive scalar i16
    any_ok<i16>()
    borrow_ok<i16>()
    from_ok<i16>()
    tryfrom_ok<i16>()
    tryinto_ok<i16>()
    into_ok<i16>()
    send_ok<i16>()
    sync_ok<i16>()
    owned_ok<i16>()
    string_ok<i16>()
    // primitive scalar i32
    any_ok<i32>()
    borrow_ok<i32>()
    from_ok<i32>()
    tryfrom_ok<i32>()
    tryinto_ok<i32>()
    into_ok<i32>()
    send_ok<i32>()
    sync_ok<i32>()
    owned_ok<i32>()
    string_ok<i32>()
    // primitive scalar i64
    any_ok<i64>()
    borrow_ok<i64>()
    from_ok<i64>()
    tryfrom_ok<i64>()
    tryinto_ok<i64>()
    into_ok<i64>()
    send_ok<i64>()
    sync_ok<i64>()
    owned_ok<i64>()
    string_ok<i64>()
    // primitive scalar i128
    any_ok<i128>()
    borrow_ok<i128>()
    from_ok<i128>()
    tryfrom_ok<i128>()
    tryinto_ok<i128>()
    into_ok<i128>()
    send_ok<i128>()
    sync_ok<i128>()
    owned_ok<i128>()
    string_ok<i128>()
    // primitive scalar isize
    any_ok<isize>()
    borrow_ok<isize>()
    from_ok<isize>()
    tryfrom_ok<isize>()
    tryinto_ok<isize>()
    into_ok<isize>()
    send_ok<isize>()
    sync_ok<isize>()
    owned_ok<isize>()
    string_ok<isize>()
    // primitive scalar u8
    any_ok<u8>()
    borrow_ok<u8>()
    from_ok<u8>()
    tryfrom_ok<u8>()
    tryinto_ok<u8>()
    into_ok<u8>()
    send_ok<u8>()
    sync_ok<u8>()
    owned_ok<u8>()
    string_ok<u8>()
    // primitive scalar u16
    any_ok<u16>()
    borrow_ok<u16>()
    from_ok<u16>()
    tryfrom_ok<u16>()
    tryinto_ok<u16>()
    into_ok<u16>()
    send_ok<u16>()
    sync_ok<u16>()
    owned_ok<u16>()
    string_ok<u16>()
    // primitive scalar u32
    any_ok<u32>()
    borrow_ok<u32>()
    from_ok<u32>()
    tryfrom_ok<u32>()
    tryinto_ok<u32>()
    into_ok<u32>()
    send_ok<u32>()
    sync_ok<u32>()
    owned_ok<u32>()
    string_ok<u32>()
    // primitive scalar u64
    any_ok<u64>()
    borrow_ok<u64>()
    from_ok<u64>()
    tryfrom_ok<u64>()
    tryinto_ok<u64>()
    into_ok<u64>()
    send_ok<u64>()
    sync_ok<u64>()
    owned_ok<u64>()
    string_ok<u64>()
    // primitive scalar u128
    any_ok<u128>()
    borrow_ok<u128>()
    from_ok<u128>()
    tryfrom_ok<u128>()
    tryinto_ok<u128>()
    into_ok<u128>()
    send_ok<u128>()
    sync_ok<u128>()
    owned_ok<u128>()
    string_ok<u128>()
    // primitive scalar usize
    any_ok<usize>()
    borrow_ok<usize>()
    from_ok<usize>()
    tryfrom_ok<usize>()
    tryinto_ok<usize>()
    into_ok<usize>()
    send_ok<usize>()
    sync_ok<usize>()
    owned_ok<usize>()
    string_ok<usize>()
    // primitive scalar f32
    any_ok<f32>()
    borrow_ok<f32>()
    from_ok<f32>()
    tryfrom_ok<f32>()
    tryinto_ok<f32>()
    into_ok<f32>()
    send_ok<f32>()
    sync_ok<f32>()
    owned_ok<f32>()
    string_ok<f32>()
    // primitive scalar f64
    any_ok<f64>()
    borrow_ok<f64>()
    from_ok<f64>()
    tryfrom_ok<f64>()
    tryinto_ok<f64>()
    into_ok<f64>()
    send_ok<f64>()
    sync_ok<f64>()
    owned_ok<f64>()
    string_ok<f64>()
    // primitive scalar bool
    any_ok<bool>()
    borrow_ok<bool>()
    from_ok<bool>()
    tryfrom_ok<bool>()
    tryinto_ok<bool>()
    into_ok<bool>()
    send_ok<bool>()
    sync_ok<bool>()
    owned_ok<bool>()
    string_ok<bool>()
    // primitive scalar char
    any_ok<char>()
    borrow_ok<char>()
    from_ok<char>()
    tryfrom_ok<char>()
    tryinto_ok<char>()
    into_ok<char>()
    send_ok<char>()
    sync_ok<char>()
    owned_ok<char>()
    string_ok<char>()
    // core.option.Option (T?): Any Borrow From Into Send Sync ToOwned
    any_ok<i32?>()
    borrow_ok<i32?>()
    from_ok<i32?>()
    tryfrom_ok<i32?>()
    tryinto_ok<i32?>()
    into_ok<i32?>()
    send_ok<i32?>()
    sync_ok<i32?>()
    owned_ok<i32?>()

    // core.outcome.Result (Outcome<T, E>): Any Borrow From Into Send Sync ToOwned
    any_ok<(Outcome<i32, i32>)>()
    borrow_ok<(Outcome<i32, i32>)>()
    from_ok<(Outcome<i32, i32>)>()
    tryfrom_ok<(Outcome<i32, i32>)>()
    tryinto_ok<(Outcome<i32, i32>)>()
    into_ok<(Outcome<i32, i32>)>()
    send_ok<(Outcome<i32, i32>)>()
    sync_ok<(Outcome<i32, i32>)>()

    // primitive::array ([T; N]): Any Borrow From Into Send Sync ToOwned
    any_ok<[i32; 3]>()
    borrow_ok<[i32; 3]>()
    from_ok<[i32; 3]>()
    tryfrom_ok<[i32; 3]>()
    tryinto_ok<[i32; 3]>()
    into_ok<[i32; 3]>()
    send_ok<[i32; 3]>()
    sync_ok<[i32; 3]>()

    // primitive::slice ([T]): Any Borrow Send Sync (unsized: no From/Into/ToOwned)
    any_unsized_ok<[i32]>()
    borrow_ok<[i32]>()
    send_unsized_ok<[i32]>()
    sync_unsized_ok<[i32]>()

    // primitive::str (core.text.Text): Any Borrow Send Sync ToString (unsized)
    any_unsized_ok<core.text.Text>()
    borrow_ok<core.text.Text>()
    send_unsized_ok<core.text.Text>()
    sync_unsized_ok<core.text.Text>()
    string_unsized_ok<core.text.Text>()
    0
}
