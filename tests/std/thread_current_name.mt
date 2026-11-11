import std.thread

fn main(): i32 {
    var builder = thread.Builder.new()
    builder.name("abcdefghijklmn\u{e9}-a-very-long-thread-name-abcdefghijklmnopqrstuvwxyz-0123456789")
    let started = capture builder.spawn(take fn(): i32 {
        match take thread.current_thread().name() {
            present(name) => {
                if name.as_text() != "abcdefghijklmn\u{e9}-a-very-long-thread-name-abcdefghijklmnopqrstuvwxyz-0123456789" {
                    return 1
                }
            },
            none => { return 2 }
        }
        0
    })
    let handle = match take started { success(value) => value, failure(_) => { return 3 } }
    match take capture handle.join() {
        success(value) => { if value != 0 { return value } },
        failure(_) => { return 4 }
    }

    let unnamed = thread.spawn(take fn(): i32 {
        match take thread.current_thread().name() {
            present(_) => 5,
            none => 0
        }
    })
    match take capture unnamed.join() {
        success(value) => { if value != 0 { return value } },
        failure(_) => { return 6 }
    }

    var empty_builder = thread.Builder.new()
    empty_builder.name("")
    let empty = capture empty_builder.spawn(take fn(): i32 {
        match take thread.current_thread().name() {
            present(name) => { if name.as_text() == "" { 0 } else { 7 } },
            none => 8
        }
    })
    let handle = match take empty { success(value) => value, failure(_) => { return 9 } }
    match take capture handle.join() { success(value) => value, failure(_) => 10 }
}
