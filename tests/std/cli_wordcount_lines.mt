// args: input.txt report.txt
// file: input.txt=the quick brown fox\n\njumps over  the lazy dog\nlast line no newline
// expect-stdout: input.txt: 4 lines, 13 words, 66 bytes\n
// expect-file: report.txt=lines=4\nwords=13\nbytes=66\n
// Byte-oriented input preserves non-UTF-8 data and original line terminators.
import std.env
import std.fs
import std.io
import std.path.PathInput
import alloc.vec.List

fn words_in(read line: [u8]): usize {
    var words: usize = 0
    var inside = false
    for byte in line.bytes() {
        let space = byte == b' ' || byte == b'\n' || byte == b'\t'
        if !space && !inside { words += 1 }
        inside = !space
    }
    words
}

fn count(read input: PathInput, read report: PathInput): Unit throws io.Error {
    var reader = io.buf_reader(try fs.open(input))
    var buffer = List<u8>()
    var lines: usize = 0
    var words: usize = 0
    var bytes: usize = 0
    while let present(line) = try reader.read_bytes_line_into(buffer) {
        lines += 1
        bytes += line.len()
        words += words_in(line)
    }
    {
        var out = io.buf_writer(try fs.create(report))
        try out.write_line(f"lines={lines}")
        try out.write_line(f"words={words}")
        try out.write_line(f"bytes={bytes}")
        try out.flush()
    }
    var out = io.stdout()
    try out.write_path(input)
    try out.write_line(f": {lines} lines, {words} words, {bytes} bytes")
}

fn main(): i32 {
    let args = env.args()
    if args.len() != 3 {
        io.eprint("usage: wordcount INPUT REPORT\n")
        return 2
    }
    let result = capture count(args[1], args[2])
    match take result {
        success(_) => 0,
        failure(error) => {
            let message = error.message()
            io.eprint(f"wordcount: {message}\n")
            1
        }
    }
}
