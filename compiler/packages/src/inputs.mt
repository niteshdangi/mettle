import alloc.string.{ String, from_text }
import alloc.vec.List
import core.iter.Iterator
import core.text.from_utf8
import mettle_foundation.SOURCE_BYTES
import std.{ fs, io }
import std.io.Reader
import std.path.{ Path, PathBuf, new_path_buf }
import super.data.{ Data, Range, parse }

pub copy enum PackagePhase { Manifest, Package, Lock, Io }
pub type PackageError {
    pub path: PathBuf
    pub begin: u32
    pub end: u32
    pub message: String
    pub phase: PackagePhase
}

pub fn error_at(read path: Path, span: Range, take message: String, phase: PackagePhase): PackageError {
    PackageError(path.to_path_buf(), span.begin, span.end, take message, phase)
}

pub fn io_result<T>(take result: Outcome<T, io.Error>, read path: Path, span: Range, phase: PackagePhase): T throws PackageError {
    match take result {
        success(value) => take value,
        failure(issue) => { throw error_at(path, span, issue.message(), phase) }
    }
}

fn read_data_bytes(mut file: fs.File): List<u8>? throws io.Error {
    let metadata = try file.metadata()
    if !metadata.is_file() || metadata.len() > SOURCE_BYTES as u64 { return none }
    var bytes = List<u8>()
    var chunk = [0u8; 4096]
    loop {
        let remaining = SOURCE_BYTES - bytes.len()
        let capacity = if remaining < 4096usize { remaining + 1 } else { 4096usize }
        let count = try file.read_some(chunk.split_at_mut(capacity).0)
        if count > remaining { return none }
        if count == 0 { return present(bytes) }
        bytes.extend_from_slice(chunk.split_at(count).0)
    }
}

pub fn read_data(read path: Path, phase: PackagePhase, optional: bool): Data? throws PackageError {
    let start = Range(0, 0)
    var file = match take capture fs.open(path) {
        success(opened) => take opened,
        failure(issue) => {
            if optional && issue.kind().is(io.ErrorKind.NotFound) { return none }
            throw error_at(path, start, issue.message(), phase)
        }
    }
    let present(bytes) = try io_result(take capture read_data_bytes(mut file), path, start, phase) else {
        throw error_at(path, start, from_text("package data must be a regular file smaller than 4 GiB"), phase)
    }
    let input = match from_utf8(bytes.as_slice()) {
        success(text) => text,
        failure(issue) => {
            let offset = issue.valid_up_to() as u32
            throw error_at(path, Range(offset, offset + 1), from_text("file is not valid UTF-8"), phase)
        }
    }
    match take capture parse(input) {
        success(tree) => present(take tree),
        failure(issue) => { throw error_at(path, issue.span, take issue.message, phase) }
    }
}

pub fn relative_to(read base: Path, read target: Path): PathBuf {
    var left = base.components()
    var right = target.components()
    var result = new_path_buf()
    loop {
        let rest = right.as_path()
        let a = left.next()
        let b = right.next()
        if a.is_present() && a == b { continue }
        if a.is_present() {
            result.push("..")
            while left.next().is_present() { result.push("..") }
        }
        if !rest.is_empty() { result.push(rest) }
        if result.is_empty() { result.push(".") }
        return result
    }
}
