// Process arguments, environment variables and the working directory. Names
// and values are OS strings (arbitrary bytes), not text.
import package.alloc.string.String
import package.alloc.vec
import package.alloc.vec.List
import super.ffi
import super.ffi.{OsStr, OsString}
import super.io
import super.path.{PathBuf, PathInput}
import super.sys

// The command line, program name first.
pub fn args(): List<OsString> {
    var out = vec.new<OsString>()
    let n = unsafe { sys.mettle_rt_argc() }
    var i = 0
    while i < n {
        let p = unsafe { sys.mettle_rt_argv(i) }
        out.push(ffi.os_string_from_vec(unsafe { sys.bytes_from_c(p) }))
        i += 1
    }
    out
}

// One environment entry.
pub type EnvVar { pub name: OsString; pub value: OsString }

// The environment at the time of the call, in the operating system's order.
pub fn vars(): List<EnvVar> {
    var out = vec.new<EnvVar>()
    let values = unsafe { sys.mettle_rt_environ() }
    if values == core.ptr.null<ptr<read u8>>() { return out }
    var i = 0usize
    while true {
        let p = unsafe { *values.add(i) }
        if p == core.ptr.null<u8>() { break }
        let bytes = unsafe { sys.bytes_from_c(p) }
        var split = 0usize
        while split < bytes.len() && bytes[split] != 61u8 { split += 1usize }
        if split < bytes.len() {
            let name = ffi.os_string_from_bytes(bytes.as_slice().split_at(split).0)
            let value = ffi.os_string_from_bytes(bytes.as_slice().split_at(split + 1usize).1)
            out.push(EnvVar(name, value))
        }
        i += 1usize
    }
    out
}

// The value of `name`, or none when unset (or the name is not representable).
pub fn var_os(read name: OsStr): OsString? {
    let c = capture ffi.cstring(name.as_bytes())
    match take c {
        success(cname) => {
            let p = unsafe { sys.getenv(cname.as_ptr()) }
            if p == core.ptr.null<u8>() { none } else { present(ffi.os_string_from_vec(unsafe { sys.bytes_from_c(p) })) }
        },
        failure(e) => none
    }
}

// Why `var` failed: the name is unset, or its value is not valid UTF-8.
pub enum VarError { NotPresent, NotUnicode(OsString) }

// The value of `name` as text. Fails with `NotPresent` when unset.
pub fn `var`(read name: OsStr): String throws VarError {
    match take var_os(name) {
        present(value) => {
            match take capture value.into_string() {
                success(text) => text,
                failure(error) => throw VarError.NotUnicode(ffi.os_string_from_vec(error.bytes))
            }
        },
        none => throw VarError.NotPresent
    }
}

// The directory for temporary files: `$TMPDIR` when set, otherwise `/tmp`.
pub fn temp_dir(): PathBuf {
    match var_os(ffi.os_str_from_text("TMPDIR")) {
        present(value) => super.path.path_buf_from_bytes(value.as_bytes()),
        none => super.path.path_buf_from_text("/tmp")
    }
}

fn validate_env(read name: OsStr, read value: OsStr): Unit {
    if name.is_empty() { package.core.panic.panic("environment name is empty") }
    let bytes = name.as_bytes()
    var index = 0usize
    while index < bytes.len() {
        if bytes[index] == 0u8 || bytes[index] == 61u8 {
            package.core.panic.panic("invalid environment name")
        }
        index += 1usize
    }
    let bytes = value.as_bytes()
    index = 0usize
    while index < bytes.len() {
        if bytes[index] == 0u8 { package.core.panic.panic("invalid environment value") }
        index += 1usize
    }
}

// Safety: exclude concurrent environment access, including foreign and indirect readers.
pub unsafe fn set_var(read name: OsStr, read value: OsStr): Unit throws io.Error {
    validate_env(name, value)
    let cname = try ffi.cstring(name.as_bytes())
    let cvalue = try ffi.cstring(value.as_bytes())
    if unsafe { sys.setenv(cname.as_ptr(), cvalue.as_ptr(), 1) } != 0 { throw io.last_os_error() }
}

// Safety: exclude concurrent environment access, including foreign and indirect readers.
pub unsafe fn remove_var(read name: OsStr): Unit throws io.Error {
    validate_env(name, ffi.os_str_from_text(""))
    let cname = try ffi.cstring(name.as_bytes())
    if unsafe { sys.unsetenv(cname.as_ptr()) } != 0 { throw io.last_os_error() }
}

pub fn current_dir(): PathBuf throws io.Error {
    var size = 256usize
    while true {
        var buf = vec.with_capacity<u8>(size)
        buf.resize(size, 0u8)
        let p = unsafe { sys.getcwd(buf.as_mut_ptr(), size) }
        if p != core.ptr.null_mut<u8>() {
            let n = unsafe { sys.strlen(buf.as_ptr()) }
            buf.truncate(n)
            return super.path.path_buf_from_bytes(buf.as_slice())
        }
        let code = sys.errno()
        if unsafe { sys.mettle_rt_errno_is_range(code) } == 0 {
            throw io.from_raw_os_error(code)
        }
        size = match size.checked_mul(2usize) {
            present(next) => next,
            none => throw io.from_raw_os_error(code)
        }
    }
    super.path.new_path_buf()
}

pub fn set_current_dir(read input: PathInput): Unit throws io.Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    if unsafe { sys.chdir(c.as_ptr()) } != 0 { throw io.last_os_error() }
}
