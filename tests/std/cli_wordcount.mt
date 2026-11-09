// args: input.txt report.txt
// file: input.txt=the quick brown fox\n\njumps over  the lazy dog\nlast line no newline
// expect-stdout: input.txt: 4 lines, 13 words, 66 bytes\n
// expect-file: report.txt=lines=4\nwords=13\nbytes=66\n
// File-processing CLI: reads a file line by line through BufferedReader, counts,
// then writes a report file through BufferedWriter and prints a summary.
import std.io.{BufRead, Error, Reader, Writer}
import std.ffi
import std.path
import alloc.vec.List

fn decimal(v: usize): List<u8> {
    var digits = alloc.vec.new<u8>()
    var x = v
    if x == 0usize { digits.push(48u8) }
    while x > 0usize { digits.push((48usize + x % 10usize) as u8); x = x / 10usize }
    var out = alloc.vec.new<u8>()
    var i = digits.len()
    while i > 0usize { i -= 1usize; let d = digits[i]; out.push(d) }
    out
}

fn words_in(read line: [u8]): usize {
    var words = 0usize
    var inside = false
    var i = 0usize
    while i < line.len() {
        let c = line[i]
        let space = c == 32u8 || c == 10u8 || c == 9u8
        if !space && !inside { words += 1usize }
        inside = !space
        i += 1usize
    }
    words
}

fn field(mut out: List<u8>, read name: Text, value: usize): Unit {
    out.extend_from_slice(name.as_bytes())
    out.extend_from_slice(decimal(value).as_slice())
    out.push(10u8)
}

fn count(read input: path.Path, read report: path.Path): i32 throws Error {
    let file = try std.fs.open(input)
    var reader = std.io.buf_reader(file)
    var lines = 0usize
    var words = 0usize
    var bytes = 0usize
    var line = alloc.vec.new<u8>()
    while true {
        line.clear()
        let n = try reader.read_until(10u8, line)
        if n == 0usize { break }
        lines += 1usize
        bytes += n
        words += words_in(line.as_slice())
    }
    var body = alloc.vec.new<u8>()
    field(body, "lines=", lines)
    field(body, "words=", words)
    field(body, "bytes=", bytes)
    {
        var w = std.io.buf_writer(try std.fs.create(report))
        try w.write_all(body.as_slice())
        try w.flush()
    }
    var summary = alloc.vec.new<u8>()
    summary.extend_from_slice(input.as_bytes())
    summary.extend_from_slice(": ".as_bytes())
    summary.extend_from_slice(decimal(lines).as_slice())
    summary.extend_from_slice(" lines, ".as_bytes())
    summary.extend_from_slice(decimal(words).as_slice())
    summary.extend_from_slice(" words, ".as_bytes())
    summary.extend_from_slice(decimal(bytes).as_slice())
    summary.extend_from_slice(" bytes\n".as_bytes())
    var out = std.io.stdout()
    try out.write_all(summary.as_slice())
    0
}

fn main(): i32 {
    let args = std.env.args()
    if args.len() != 3usize {
        std.io.eprint("usage: wordcount INPUT REPORT\n")
        return 2
    }
    let r = capture count(path.path_from_os_str(args[1usize].as_os_str()), path.path_from_os_str(args[2usize].as_os_str()))
    match take r {
        success(code) => code,
        failure(e) => { std.io.eprint("wordcount: "); std.io.eprint(e.message().as_text()); std.io.eprint("\n"); 1 }
    }
}
