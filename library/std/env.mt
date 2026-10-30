// Process arguments, environment variables and the working directory. Names
// and values are OS strings (arbitrary bytes), not text.
import package::alloc::vec;
import package::alloc::vec::Vec;
import super::ffi;
import super::ffi::{OsStr, OsString};
import super::io;
import super::path::{PathBuf, PathInput};
import super::sys;

// The command line, program name first.
pub fn args(): Vec<OsString> {
    var out = vec::new::<OsString>()
    let n = unsafe { sys::mettle_rt_argc() }
    var i = 0
    while i < n {
        let p = unsafe { sys::mettle_rt_argv(i) }
        out.push(ffi::os_string_from_vec(unsafe { sys::bytes_from_c(p) }))
        i += 1
    }
    out
}

// One environment entry.
pub type EnvVar { pub name: OsString; pub value: OsString }

// The environment at the time of the call, in the operating system's order.
pub fn vars(): Vec<EnvVar> {
    var out = vec::new::<EnvVar>()
    var i = 0
    while true {
        let p = unsafe { sys::mettle_rt_environ_at(i) }
        if p == core::ptr::null::<u8>() { break }
        let bytes = unsafe { sys::bytes_from_c(p) }
        var split = 0usize
        while split < bytes.len() && bytes[split] != 61u8 { split += 1usize }
        if split < bytes.len() {
            let name = ffi::os_string_from_bytes(bytes.as_slice().split_at(split).0)
            let value = ffi::os_string_from_bytes(bytes.as_slice().split_at(split + 1usize).1)
            out.push(EnvVar(name, value))
        }
        i += 1
    }
    out
}

// The value of `name`, or none when unset (or the name is not representable).
pub fn var_os(name: read OsStr): OsString? {
    let c = capture ffi::cstring(name.as_bytes())
    match take c {
        success(cname) => {
            let p = unsafe { sys::getenv(cname.as_ptr()) }
            if p == core::ptr::null::<u8>() { none } else { present(ffi::os_string_from_vec(unsafe { sys::bytes_from_c(p) })) }
        },
        failure(e) => none
    }
}

// Fails with `InvalidInput` for an empty name or one containing `=` or NUL.
pub fn set_var(name: read OsStr, value: read OsStr): Unit throws io::Error {
    if name.is_empty() { throw io::from_kind(io::ErrorKind::InvalidInput) }
    let cname = try ffi::cstring(name.as_bytes())
    let cvalue = try ffi::cstring(value.as_bytes())
    if unsafe { sys::setenv(cname.as_ptr(), cvalue.as_ptr(), 1) } != 0 { throw io::last_os_error() }
}

pub fn remove_var(name: read OsStr): Unit throws io::Error {
    if name.is_empty() { throw io::from_kind(io::ErrorKind::InvalidInput) }
    let cname = try ffi::cstring(name.as_bytes())
    if unsafe { sys::unsetenv(cname.as_ptr()) } != 0 { throw io::last_os_error() }
}

pub fn current_dir(): PathBuf throws io::Error {
    var size = 256usize
    while true {
        var buf = vec::with_capacity::<u8>(size)
        buf.resize(size, 0u8)
        let p = unsafe { sys::getcwd(buf.as_mut_ptr(), size) }
        if p != core::ptr::null_mut::<u8>() {
            let n = unsafe { sys::strlen(buf.as_ptr()) }
            buf.truncate(n)
            return super::path::path_buf_from_bytes(buf.as_slice())
        }
        let code = sys::errno()
        let e = io::from_raw_os_error(code)
        if !e.kind().is(io::ErrorKind::Other) || size > 65536usize { throw e }
        size *= 2usize
    }
    super::path::new_path_buf()
}

pub fn set_current_dir(input: read PathInput): Unit throws io::Error {
    let c = try ffi::cstring(input.as_path().as_bytes())
    if unsafe { sys::chdir(c.as_ptr()) } != 0 { throw io::last_os_error() }
}
