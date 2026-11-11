import alloc.boxed
import alloc.vec
import std.io.{BufRead, Error, ErrorKind, Reader, Writer}

type InvalidCountReader { calls: usize }

extend InvalidCountReader implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        if bytes.is_empty() { return 0usize }
        self.calls += 1usize
        if self.calls == 2usize { return bytes.len() + 1usize }
        if self.calls > 3usize { return 0usize }
        bytes[0usize] = if self.calls == 1usize { 97u8 } else { 98u8 }
        1usize
    }
}

fn invalid_count(take result: Outcome<usize, Error>): bool {
    match take result {
        failure(error) => error.kind().is(ErrorKind.InvalidData),
        success(_) => false
    }
}

fn run(): i32 throws Error {
    var output = vec.new<u8>()
    try output.write_all("seed".as_bytes())
    var reader = boxed.new(InvalidCountReader(0usize))
    if !invalid_count(capture reader.read_to_end(mut output)) { return 1 }
    if output.as_slice() != "seeda".as_bytes() { return 2 }
    if try reader.read_to_end(mut output) != 1usize ||
        output.as_slice() != "seedab".as_bytes() {
        return 3
    }

    var limited = InvalidCountReader(0usize).`take`(2u64)
    var bytes = [0u8; 4]
    if try limited.read_some(mut bytes) != 1usize ||
        bytes[0usize] != 97u8 {
        return 4
    }
    if !invalid_count(capture limited.read_some(mut bytes)) { return 5 }
    if try limited.read_some(mut bytes) != 1usize ||
        bytes[0usize] != 98u8 ||
        try limited.read_some(mut bytes) != 0usize {
        return 6
    }

    var individual = InvalidCountReader(0usize).bytes()
    match take individual.next() {
        present(success(97u8)) => {},
        _ => { return 7 }
    }
    match take individual.next() {
        present(failure(error)) => {
            if !error.kind().is(ErrorKind.InvalidData) { return 8 }
        },
        _ => { return 9 }
    }
    match take individual.next() {
        present(success(98u8)) => {},
        _ => { return 10 }
    }
    match take individual.next() {
        none => {},
        _ => { return 11 }
    }

    var buffered = std.io.buf_reader_with_capacity(1usize, InvalidCountReader(0usize))
    if (try buffered.fill_buf())[0usize] != 97u8 { return 12 }
    buffered.consume(1usize)
    match take capture buffered.fill_buf() {
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidData) { return 13 }
        },
        success(_) => { return 14 }
    }
    if !buffered.buffer().is_empty() { return 15 }
    if (try buffered.fill_buf())[0usize] != 98u8 { return 16 }
    buffered.consume(1usize)
    if !(try buffered.fill_buf()).is_empty() { return 17 }

    var source = InvalidCountReader(0usize)
    var destination = vec.new<u8>()
    match take capture std.io.`copy`(mut source, mut destination) {
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidData) { return 18 }
        },
        success(_) => { return 19 }
    }
    if destination.as_slice() != "a".as_bytes() { return 20 }
    if try std.io.`copy`(mut source, mut destination) != 1u64 ||
        destination.as_slice() != "ab".as_bytes() {
        return 21
    }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
