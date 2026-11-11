import alloc.string
import alloc.vec
import core.iter.Iterator
import std.io.{BufRead, BufferedReader, Error, ErrorKind, Reader}

type BreakOnce { at: usize; failed: bool }
extend BreakOnce implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        if bytes.is_empty() || self.at == 3usize { return 0usize }
        if self.at == 1usize && !self.failed {
            self.failed = true
            throw std.io.from_kind(ErrorKind.Other)
        }
        bytes[0usize] = if self.at == 0usize { 97u8 }
            else if self.at == 1usize { 10u8 } else { 98u8 }
        self.at += 1usize
        1usize
    }
}

fn source(): BufferedReader<BreakOnce> {
    BufferedReader.with_capacity(1usize, BreakOnce(0usize, false))
}

fn run(): i32 throws Error {
    var bytes = vec.new<u8>()
    bytes.push(120u8)
    var reader = source()
    match take capture reader.read_until(10u8, mut bytes) {
        failure(error) => {
            assert(error.kind().is(ErrorKind.Other), "preserve delimiter read error")
        },
        success(_) => { return 1 }
    }
    assert(bytes.as_slice() == "xa".as_bytes(), "retain the appended prefix on failure")
    assert(try reader.read_until(10u8, mut bytes) == 1usize &&
        bytes.as_slice() == "xa\n".as_bytes(), "resume at the unconsumed delimiter")

    var skipped = source()
    match take capture skipped.skip_until(10u8) {
        failure(error) => {
            assert(error.kind().is(ErrorKind.Other), "skip error is not EOF")
        },
        success(_) => { return 2 }
    }
    assert(try skipped.skip_until(10u8) == 1usize, "resume skipping after the error")
    assert(try skipped.skip_until(10u8) == 1usize, "skip final unterminated bytes")
    assert(try skipped.skip_until(10u8) == 0usize, "skip EOF")

    var text = string.from_text("prefix")
    var line_reader = source()
    match take capture line_reader.read_line(mut text) {
        failure(error) => {
            assert(error.kind().is(ErrorKind.Other), "line error propagates")
        },
        success(_) => { return 3 }
    }
    assert(text.as_text() == "prefix", "failed line leaves a valid unchanged destination")
    assert(try line_reader.read_line(mut text) == 1usize &&
        text.as_text() == "prefix\n", "line read resumes after the error")

    var lines = source().lines()
    match take lines.next() { present(failure(_)) => {}, _ => { return 4 } }
    match take lines.next() {
        present(success(line)) => { assert(line.is_empty(), "error does not finish lines") },
        _ => { return 5 }
    }
    match take lines.next() {
        present(success(line)) => { assert(line.as_text() == "b", "final line without LF") },
        _ => { return 6 }
    }
    assert(lines.next().is_none(), "lines finish at EOF")

    var parts = source().split(10u8)
    match take parts.next() { present(failure(_)) => {}, _ => { return 7 } }
    match take parts.next() {
        present(success(part)) => { assert(part.is_empty(), "error does not finish split") },
        _ => { return 8 }
    }
    match take parts.next() {
        present(success(part)) => { assert(part.as_slice() == "b".as_bytes(), "final segment") },
        _ => { return 9 }
    }
    assert(parts.next().is_none(), "split finishes at EOF")
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
