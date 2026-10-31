// io.Error can own an erased payload: it is viewed, mutated, recovered by type
// and handed back unchanged when the requested type does not match.
import std.io.{Error, ErrorKind}
import core.any.Any

type Detail { code: i32 }
type Other { code: i32 }

fn run(): i32 {
    let plain = Error.other()
    if plain.get_ref().is_present() { return 1 }

    var e = Error.new(ErrorKind.InvalidData, Detail(7))
    if !e.kind().is(ErrorKind.InvalidData) || e.is_os() { return 2 }
    match e.get_ref() {
        present(view) => {
            match core.any.downcast_ref<Detail>(view) {
                present(d) => { if d.code != 7 { return 3 } },
                none => { return 4 }
            }
            if core.any.is<Other>(view) { return 5 }
        },
        none => { return 6 }
    }
    match e.get_mut() {
        present(view) => {
            match core.any.downcast_mut<Detail>(view) {
                present(d) => { d.code = 9 },
                none => { return 7 }
            }
        },
        none => { return 8 }
    }

    // A mismatched downcast returns the same error with its payload intact.
    let wrong = capture e.downcast<Other>()
    let back = match take wrong {
        success(o) => { return 9 },
        failure(original) => original
    }
    if !back.kind().is(ErrorKind.InvalidData) || !back.get_ref().is_present() { return 10 }

    let right = capture back.downcast<Detail>()
    match take right {
        success(d) => { if d.code != 9 { return 11 } },
        failure(original) => { return 12 }
    }

    // An error without a payload is returned unchanged.
    let none_here = capture Error.from_raw_os_error(2).downcast<Detail>()
    match take none_here {
        success(d) => { return 13 },
        failure(original) => {
            if original.raw_os_error() != present(2) || !original.kind().is(ErrorKind.NotFound) { return 14 }
        }
    }

    // `into_inner` yields the owned payload and consumes the error.
    let taken = Error.new(ErrorKind.Other, Detail(3)).into_inner()
    if !taken.is_present() { return 15 }
    if Error.other().into_inner().is_present() { return 16 }
    0
}

fn main(): i32 { run() }
