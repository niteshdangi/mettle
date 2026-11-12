// profiles: debug release
import alloc.string.String
import core.cmp.PartialEq
import core.fmt
import core.fmt.Debug
import core.iter.{ExactSizeIterator, Iterable, Iterator}
import core.option
import std.ffi
import std.process.{Command, Stdio}

type Arguments { index: usize }
extend Arguments implements Iterator {
    type Item = String
    mut fn next(): String? {
        if self.index == 2usize { return none }
        self.index += 1usize
        present(String(if self.index == 1usize { "first" } else { "second" }))
    }
}

fn render<T: Debug>(read value: T): String throws fmt.Error {
    var output = String("")
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try value.fmt(mut formatter)
    }
    output
}

fn check(): i32 throws fmt.Error {
    var command = Command.new("/bin/true")
    command.args(Arguments(0usize)).envs([
        (String("SET"), String("old")),
        (String("SET"), String("new")),
        (String("EMPTY"), String(""))
    ]).stdin(Stdio.Null).stdout(Stdio.Piped).stderr(Stdio.Null)
    let owners = [ffi.os_string_from_text("borrowed")]
    command.args(owners.iter())
    command.env_remove(ffi.os_str_from_text("REMOVED"))
    {
        var args = command.get_args()
        if args.len() != 3usize || args.size_hint() != (3usize, present(3usize)) { return 1 }
        let before = try render(read args)
        if args.len() != 3usize { return 2 }
        match args.next() {
            present(value) => { if !value.same(ffi.os_str_from_text("first")) { return 3 } },
            none => { return 4 }
        }
        if args.len() != 2usize || args.size_hint() != (2usize, present(2usize)) { return 5 }
        if (try render(read args)).as_text() == before.as_text() { return 6 }
        match args.next() {
            present(value) => { if !value.same(ffi.os_str_from_text("second")) { return 7 } },
            none => { return 8 }
        }
        match args.next() {
            present(value) => { if !value.same(owners[0usize].as_os_str()) { return 9 } },
            none => { return 10 }
        }
        if args.next().is_present() || args.len() != 0usize ||
            args.size_hint() != (0usize, present(0usize)) { return 11 }
    }
    {
        var entries = command.get_envs()
        if entries.len() != 3usize { return 12 }
        let before = try render(read entries)
        if entries.len() != 3usize || entries.size_hint() != (3usize, present(3usize)) { return 13 }
        var set = false
        var empty = false
        var removed = false
        while true {
            match entries.next() {
                present((key, value)) => {
                    if key.same(ffi.os_str_from_text("SET")) {
                        match value {
                            present(text) => { if !text.same(ffi.os_str_from_text("new")) { return 14 } },
                            none => { return 15 }
                        }
                        set = true
                    } else if key.same(ffi.os_str_from_text("EMPTY")) {
                        match value {
                            present(text) => { if !text.is_empty() { return 16 } },
                            none => { return 17 }
                        }
                        empty = true
                    } else if key.same(ffi.os_str_from_text("REMOVED")) {
                        if value.is_present() { return 18 }
                        removed = true
                    } else { return 19 }
                },
                none => { break }
            }
        }
        if !set || !empty || !removed || entries.len() != 0usize ||
            entries.size_hint() != (0usize, present(0usize)) { return 20 }
        if (try render(read entries)).as_text() == before.as_text() { return 21 }
    }
    command.env_clear().envs([(String("TEMP"), String("1"))])
    command.env_remove(ffi.os_str_from_text("TEMP"))
    if command.get_envs().len() != 0usize { return 22 }
    0
}

fn main(): i32 {
    match take capture check() {
        success(code) => code,
        failure(_) => 100
    }
}
