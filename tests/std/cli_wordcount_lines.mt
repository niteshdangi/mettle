// args: input.txt report.txt
// file: input.txt=the quick brown fox\n\njumps over  the lazy dog\nlast line no newline
// expect-stdout: input.txt: 4 lines, 13 words, 66 bytes\n
// expect-file: report.txt=lines=4\nwords=13\nbytes=66\n
// As cli_wordcount, using the borrowed-line API: read_bytes_line_into reuses
// one buffer, [u8].bytes() iterates Copy bytes, paths are passed as OsString
// through PathInput, and write_path prints the input name.
import std.io.{Error, Reader, Writer};
import std.ffi;
import std.path.PathInput;
import alloc.vec.List;

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

fn words_in(line: read [u8]): usize {
    var words = 0usize
    var inside = false
    for c in line.bytes() {
        let space = c == 32u8 || c == 10u8 || c == 9u8
        if !space && !inside { words += 1usize }
        inside = !space
    }
    words
}

fn field(out: mut List<u8>, name: read Text, value: usize): Unit {
    out.extend_from_slice(name.as_bytes())
    out.extend_from_slice(decimal(value).as_slice())
    out.push(10u8)
}

fn count(input: read PathInput, report: read PathInput): i32 throws Error {
    let file = try std.fs.open(input)
    var reader = std.io.buf_reader(file)
    var lines = 0usize
    var words = 0usize
    var bytes = 0usize
    var line = alloc.vec.new<u8>()
    while true {
        match try reader.read_bytes_line_into(line) {
            present(l) => {
                lines += 1usize
                bytes += l.len()
                words += words_in(l)
            },
            none => { break }
        }
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
    var out = std.io.stdout()
    try out.write_path(input)
    var tail = alloc.vec.new<u8>()
    tail.extend_from_slice(": ".as_bytes())
    tail.extend_from_slice(decimal(lines).as_slice())
    tail.extend_from_slice(" lines, ".as_bytes())
    tail.extend_from_slice(decimal(words).as_slice())
    tail.extend_from_slice(" words, ".as_bytes())
    tail.extend_from_slice(decimal(bytes).as_slice())
    tail.extend_from_slice(" bytes\n".as_bytes())
    try out.write_all(tail.as_slice())
    0
}

fn main(): i32 {
    let args = std.env.args()
    if args.len() != 3usize {
        std.io.eprint("usage: wordcount INPUT REPORT\n")
        return 2
    }
    let r = capture count(args[1usize], args[2usize])
    match take r {
        success(code) => code,
        failure(e) => { std.io.eprint("wordcount: "); std.io.eprint(e.message().as_text()); std.io.eprint("\n"); 1 }
    }
}
