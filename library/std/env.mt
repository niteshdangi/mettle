// Process arguments, environment variables and the working directory. Names
// and values are OS strings (arbitrary bytes), not text.
import alloc.string.String
import alloc.vec
import alloc.vec.List
import core.clone.Clone
import core.cmp.PartialEq
import core.iter.Iterator
import core.iter.ExactSizeIterator
import core.iter.OwnedIterable
import core.ops.Index
import core.fmt
import super.ffi
import super.ffi.{OsStr, OsString}
import super.io
import super.path.{PathBuf, PathInput}
import super.sys

pub module consts

pub type ArgsOs { inner: vec.IntoIter<OsString> }
pub type Args { inner: ArgsOs }

extend ArgsOs implements Iterator {
    type Item = OsString
    mut fn next(): OsString? { self.inner.next() }
    fn size_hint(): (usize, usize?) {
        let length = self.inner.len()
        (length, present(length))
    }
}

extend Args implements Iterator {
    type Item = OsString
    mut fn next(): OsString? { self.inner.next() }
    fn size_hint(): (usize, usize?) {
        let length = self.inner.len()
        (length, present(length))
    }
}

extend ArgsOs implements ExactSizeIterator {}
extend Args implements ExactSizeIterator {}

extend ArgsOs implements Index<usize> {
    type Output = OsString
    fn index(read index: usize): read OsString from self {
        read self.inner.as_slice()[index]
    }
}

extend Args implements Index<usize> {
    type Output = OsString
    fn index(read index: usize): read OsString from self {
        read self.inner.inner.as_slice()[index]
    }
}

fn variable_text(take value: OsString): String {
    match take capture value.into_string() {
        success(text) => text,
        failure(_) => core.panic.panic("environment variable is not valid UTF-8")
    }
}

fn collect_args(): List<OsString> {
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

pub fn args_os(): ArgsOs { ArgsOs(collect_args().into_iter()) }

pub fn args(): Args { Args(ArgsOs(collect_args().into_iter())) }

// One environment entry.
pub type EnvVar { pub name: OsString; pub value: OsString }

pub type VarsOs { inner: vec.IntoIter<(OsString, OsString)> }
pub type Vars { inner: VarsOs }

extend ArgsOs {
    pub fn len(): usize { self.inner.len() }
}

extend Args {
    pub fn len(): usize { self.inner.inner.len() }
}

extend VarsOs {
    pub fn len(): usize { self.inner.len() }
}

extend Vars {
    pub fn len(): usize { self.inner.inner.len() }
}

extend VarsOs implements Iterator {
    type Item = (OsString, OsString)
    mut fn next(): (OsString, OsString)? { self.inner.next() }
    fn size_hint(): (usize, usize?) {
        let length = self.inner.len()
        (length, present(length))
    }
}

extend Vars implements Iterator {
    type Item = (String, String)
    mut fn next(): (String, String)? {
        match take self.inner.next() {
            present((name, value)) => {
                present((variable_text(take name), variable_text(take value)))
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}

extend VarsOs implements ExactSizeIterator {}
extend Vars implements ExactSizeIterator {}

fn collect_vars(): List<(OsString, OsString)> {
    var out = vec.new<(OsString, OsString)>()
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
            out.push((name, value))
        }
        i += 1usize
    }
    out
}

pub fn vars_os(): VarsOs { VarsOs(collect_vars().into_iter()) }

pub fn vars(): Vars { Vars(vars_os()) }

pub type SplitPaths<region r> {
    paths: read OsStr from r
    start: usize
    finished: bool
}

pub copy type JoinPathsError {}

extend JoinPathsError implements core.fmt.Debug {
    fn fmt(mut f: core.fmt.Formatter): Unit throws core.fmt.Error {
        var debug = try f.debug_struct("JoinPathsError")
        try debug.finish()
    }
}

extend JoinPathsError implements core.fmt.Display {
    fn fmt(mut f: core.fmt.Formatter): Unit throws core.fmt.Error {
        try f.write_str("failed to join paths")
    }
}

extend JoinPathsError implements core.error.Error {}

pub fn split_paths<region r>(read paths: OsStr from r): SplitPaths<region r> {
    SplitPaths(read paths, 0usize, false)
}

extend<region r> SplitPaths<region r> implements Iterator {
    type Item = PathBuf
    mut fn next(): PathBuf? {
        if self.finished { return none }
        let bytes = self.paths.as_bytes()
        var end = self.start
        while end < bytes.len() && bytes[end] != 58u8 { end += 1usize }
        let component = bytes.split_at(self.start).1.split_at(end - self.start).0
        if end == bytes.len() {
            self.finished = true
        } else {
            self.start = end + 1usize
        }
        present(super.path.path_buf_from_bytes(component))
    }
}

pub fn join_paths<I: OwnedIterable<Item = PathBuf>>(take paths: I): OsString throws JoinPathsError {
    var entries = paths.into_iter()
    var bytes = vec.new<u8>()
    var first = true
    while true {
        let path = match take entries.next() {
            present(path) => path,
            none => { break }
        }
        let value = path.as_path().as_bytes()
        var index = 0usize
        while index < value.len() {
            if value[index] == 0u8 || value[index] == 58u8 {
                throw JoinPathsError()
            }
            index += 1usize
        }
        if !first { bytes.push(58u8) }
        bytes.extend_from_slice(value)
        first = false
    }
    ffi.os_string_from_vec(take bytes)
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

extend VarError implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            VarError.NotPresent => { try f.write_str("NotPresent") },
            VarError.NotUnicode(value) => {
                var tuple = try f.debug_tuple("NotUnicode")
                try tuple.field(read value)
                try tuple.finish()
            }
        }
    }
}
extend VarError implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            VarError.NotPresent => { try f.write_str("environment variable not found") },
            VarError.NotUnicode(value) => {
                try f.write_str("environment variable was not valid unicode: ")
                try OsString.(fmt.Debug).fmt(read value, mut f)
            }
        }
    }
}

extend VarError implements Clone {
    fn clone(): VarError {
        match self {
            VarError.NotPresent => VarError.NotPresent,
            VarError.NotUnicode(value) => VarError.NotUnicode(value.clone())
        }
    }
}
extend VarError implements PartialEq {
    fn eq(read other: VarError): bool {
        match self {
            VarError.NotPresent => match other {
                VarError.NotPresent => true,
                VarError.NotUnicode(_) => false
            },
            VarError.NotUnicode(value) => match other {
                VarError.NotPresent => false,
                VarError.NotUnicode(other_value) => value == other_value
            }
        }
    }
}
extend VarError implements core.cmp.Eq {}
extend VarError implements core.error.Error {}

// The value of `name` as text. Fails with `NotPresent` when unset.
pub fn `var`(read name: OsStr): String throws VarError {
    match take var_os(name) {
        present(value) => {
            match take capture value.into_string() {
                success(text) => text,
                failure(error) => throw VarError.NotUnicode(ffi.os_string_from_vec(take error.bytes))
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
    if name.is_empty() { core.panic.panic("environment name is empty") }
    let bytes = name.as_bytes()
    var index = 0usize
    while index < bytes.len() {
        if bytes[index] == 0u8 || bytes[index] == 61u8 {
            core.panic.panic("invalid environment name")
        }
        index += 1usize
    }
    let bytes = value.as_bytes()
    index = 0usize
    while index < bytes.len() {
        if bytes[index] == 0u8 { core.panic.panic("invalid environment value") }
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

pub fn current_exe(): PathBuf throws io.Error {
    var size = 256usize
    while true {
        var buf = vec.with_capacity<u8>(size)
        buf.resize(size, 0u8)
        var length = 0usize
        let result = unsafe {
            sys.mettle_rt_current_exe(
                buf.as_mut_ptr(),
                size,
                core.ptr.from_mut(mut length)
            )
        }
        if result == 0 {
            buf.truncate(length)
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

pub fn home_dir(): PathBuf? {
    var size = 256usize
    while true {
        var buf = vec.with_capacity<u8>(size)
        buf.resize(size, 0u8)
        var length = 0usize
        let result = unsafe {
            sys.mettle_rt_home_dir(
                buf.as_mut_ptr(),
                size,
                core.ptr.from_mut(mut length)
            )
        }
        if result == 1 {
            buf.truncate(length)
            return present(super.path.path_buf_from_bytes(buf.as_slice()))
        }
        if result == 0 { return none }
        let code = sys.errno()
        if unsafe { sys.mettle_rt_errno_is_range(code) } == 0 { return none }
        size = match size.checked_mul(2usize) {
            present(next) => next,
            none => { return none }
        }
    }
    none
}

pub fn set_current_dir(read input: PathInput): Unit throws io.Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    if unsafe { sys.chdir(c.as_ptr()) } != 0 { throw io.last_os_error() }
}
