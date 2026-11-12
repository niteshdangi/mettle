import core.iter.Iterator
import std.env
import std.env.VarError
import std.ffi
import std.io.Error

fn sh(read script: Text): std.process.Command {
    var command = std.process.command_text("/bin/sh")
    command.arg_text("-c")
    command.arg_text(script)
    command
}

fn run(): i32 throws Error {
    let name = ffi.os_str_from_text("MT_ENVIRONMENT")
    let parent = ffi.os_str_from_text("parent")
    // This process has no concurrent environment access or foreign callbacks.
    unsafe { try env.set_var(name, parent) }
    match take capture env.`var`(name) {
        success(text) => { if text.as_text() != "parent" { return 1 } },
        failure(_) => { return 2 }
    }
    let snapshot = env.vars()
    let invalid = [255u8]
    unsafe { try env.set_var(name, ffi.os_str(invalid)) }
    match take capture env.`var`(name) {
        success(_) => { return 3 },
        failure(error) => match take error {
            VarError.NotUnicode(raw) => {
                if !raw.as_os_str().same(ffi.os_str(invalid)) { return 4 }
            },
            _ => { return 5 }
        }
    }
    var found = false
    var index = 0usize
    while index < snapshot.len() {
        if snapshot[index].name.as_os_str().same(name) {
            if !snapshot[index].value.as_os_str().same(parent) { return 6 }
            found = true
        }
        index += 1usize
    }
    if !found { return 7 }
    unsafe { try env.set_var(name, parent) }
    let inherited = try sh("printf '%s' \"$MT_ENVIRONMENT\"").output()
    if !inherited.status.succeeded() ||
       !ffi.os_str(inherited.stdout.as_slice()).same(parent) { return 8 }

    let other = ffi.os_str_from_text("MT_ENV_ORDER")
    var overridden = sh("printf '%s' \"$MT_ENVIRONMENT\"")
    overridden.env(other, ffi.os_str_from_text("first"))
    overridden.env(name, ffi.os_str_from_text("old"))
    overridden.env_remove(name)
    overridden.env(name, ffi.os_str_from_text("child"))
    overridden.env(other, ffi.os_str_from_text("last"))
    {
        var configured = overridden.get_envs()
        match configured.next() {
            present((key, value)) => {
                let value = match value { present(v) => v, none => { return 9 } }
                if !key.same(name) || !value.same(ffi.os_str_from_text("child")) { return 9 }
            },
            none => { return 10 }
        }
        match configured.next() {
            present((key, value)) => {
                let value = match value { present(v) => v, none => { return 11 } }
                if !key.same(other) || !value.same(ffi.os_str_from_text("last")) { return 11 }
            },
            none => { return 12 }
        }
        if configured.next().is_present() { return 13 }
    }
    let changed = try overridden.output()
    if !changed.status.succeeded() ||
       !ffi.os_str(changed.stdout.as_slice()).same(ffi.os_str_from_text("child")) { return 14 }
    var removed = sh("test -z \"${MT_ENVIRONMENT+x}\"")
    removed.env_remove(name)
    {
        var configured = removed.get_envs()
        match configured.next() {
            present((key, value)) => {
                if !key.same(name) || value.is_present() { return 15 }
            },
            none => { return 15 }
        }
        if configured.next().is_present() { return 15 }
    }
    if !(try removed.status()).succeeded() { return 16 }
    var cleared = std.process.command_text("/usr/bin/env")
    cleared.env(name, parent)
    cleared.env_clear()
    let empty = try cleared.output()
    if !empty.status.succeeded() || empty.stdout.len() != 0usize { return 17 }
    unsafe { try env.remove_var(name) }
    match take capture env.`var`(name) {
        success(_) => { return 18 },
        failure(error) => match error {
            VarError.NotPresent => {},
            _ => { return 19 }
        }
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
