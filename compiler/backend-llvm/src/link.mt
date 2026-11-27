import std.env
import std.ffi.os_string_from_text
import std.fs
import std.io
import std.path.{ Path, PathBuf, path_from_text }
import std.process.{ ExitStatus, command }

pub enum LinkError {
    UnsupportedHost,
    Io(io.Error),
    Failed(ExitStatus)
}

fn absolute_path(read path: Path): PathBuf throws io.Error {
    if path.is_empty() { throw io.from_kind(io.ErrorKind.InvalidInput) }
    if path.is_absolute() { return path.to_path_buf() }
    let cwd = try env.current_dir()
    cwd.join(path)
}

fn invoke_link(read clang: Path, read input: Path, read output: Path,
    read runtime: Path): ExitStatus throws io.Error {
    let clang_path = try absolute_path(clang)
    let input_path = try absolute_path(input)
    let output_path = try absolute_path(output)
    let runtime_path = try absolute_path(runtime)
    if !(try fs.metadata(runtime_path.as_path())).is_file() {
        throw io.from_kind(io.ErrorKind.InvalidInput)
    }
    let present(tool_dir) = clang_path.parent() else { throw io.from_kind(io.ErrorKind.InvalidInput) }
    let lld = tool_dir.join(path_from_text("ld.lld"))
    var linker = os_string_from_text("--ld-path=")
    linker.push(lld.as_os_str())

    var child = command(clang_path.as_os_str())
    child.arg_text("--no-default-config")
    child.arg_text("--driver-mode=g++")
    child.arg_text("--target=x86_64-unknown-linux-gnu")
    child.arg_text("-fuse-ld=lld")
    child.arg(linker.as_os_str())
    child.arg_text("-Wno-override-module")
    child.arg_text("-x")
    child.arg_text("ir")
    child.arg(input_path.as_os_str())
    child.arg_text("-Xlinker")
    child.arg(runtime_path.as_os_str())
    child.arg_text("-pthread")
    child.arg_text("-o")
    child.arg(output_path.as_os_str())
    try child.status()
}

pub fn link_executable(read clang: Path, read input: Path, read output: Path,
    read runtime: Path): Unit throws LinkError {
    if env.consts.OS != "linux" || env.consts.ARCH != "x86_64" {
        throw LinkError.UnsupportedHost
    }
    match take capture invoke_link(clang, input, output, runtime) {
        success(status) => {
            if !status.succeeded() { throw LinkError.Failed(status) }
        },
        failure(error) => { throw LinkError.Io(take error) }
    }
}
