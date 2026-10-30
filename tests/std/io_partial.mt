// Partial reads and writes stay visible; the *_all helpers loop over them.
import std::io::{Read, Write, Error, ErrorKind};
import alloc::vec::Vec;

// Reads at most `step` bytes per call.
type Dribble { data: Vec<u8>; pos: usize; step: usize; calls: usize }
impl Dribble implements Read {
    mut fn read_some(buf: mut [u8]): usize throws Error {
        self.calls += 1usize
        var n = buf.len()
        if n > self.step { n = self.step }
        if n > self.data.len() - self.pos { n = self.data.len() - self.pos }
        var i = 0usize
        while i < n { buf[i] = self.data[self.pos + i]; i += 1usize }
        self.pos += n
        n
    }
}

// Accepts at most `step` bytes per call.
type Trickle { out: Vec<u8>; step: usize; calls: usize }
impl Trickle implements Write {
    mut fn write_some(buf: read [u8]): usize throws Error {
        self.calls += 1usize
        var n = buf.len()
        if n > self.step { n = self.step }
        self.out.extend_from_slice(buf.split_at(n).0)
        n
    }
    mut fn flush(): Unit throws Error {}
}

// A sink that stops accepting bytes.
type Full {}
impl Full implements Write {
    mut fn write_some(buf: read [u8]): usize throws Error { 0usize }
    mut fn flush(): Unit throws Error {}
}

fn source(len: usize, step: usize): Dribble {
    var data = alloc::vec::new::<u8>()
    var i = 0usize
    while i < len { data.push((i % 251usize) as u8); i += 1usize }
    Dribble(data, 0usize, step, 0usize)
}

fn run(): i32 throws Error {
    // One write_some moves a prefix only.
    var t = Trickle(alloc::vec::new::<u8>(), 3usize, 0usize)
    let first = try t.write_some("abcdefgh".as_bytes())
    if first != 3usize { return 1 }
    // write_all repeats until all bytes are accepted.
    try t.write_all("0123456789".as_bytes())
    if t.out.len() != 13usize || t.calls != 5usize { return 2 }
    // An empty write is a no-op.
    try t.write_all("".as_bytes())
    if t.calls != 5usize { return 3 }

    // One read_some may return fewer bytes than the buffer holds.
    var d = source(10usize, 4usize)
    var buf = [0u8; 16]
    let n = try d.read_some(buf)
    if n != 4usize || buf[3usize] != 3u8 || buf[4usize] != 0u8 { return 4 }
    // read_exact loops over short reads.
    var exact = [0u8; 6]
    try d.read_exact(exact)
    if exact[0usize] != 4u8 || exact[5usize] != 9u8 { return 5 }
    // Past the end read_exact fails with UnexpectedEof.
    var more = [0u8; 2]
    let eof = capture d.read_exact(more)
    match take eof {
        success(u) => { return 6 },
        failure(e) => { if !e.kind().is(ErrorKind::UnexpectedEof) || e.is_os() { return 7 } }
    }
    // read_to_end gathers everything across many short reads.
    var big = source(10000usize, 7usize)
    var all = alloc::vec::new::<u8>()
    let total = try big.read_to_end(all)
    if total != 10000usize || all.len() != 10000usize || all[9999usize] != (9999usize % 251usize) as u8 { return 8 }
    if big.calls < 1428usize { return 9 }
    // A sink that accepts nothing makes write_all fail with WriteZero.
    var full = Full()
    let zero = capture full.write_all("x".as_bytes())
    match take zero {
        success(u) => { return 10 },
        failure(e) => { if !e.kind().is(ErrorKind::WriteZero) { return 11 } }
    }
    // BufWriter coalesces small writes into one underlying write.
    var sink = Trickle(alloc::vec::new::<u8>(), 1000usize, 0usize)
    {
        var w = std::io::buf_writer_with_capacity(64usize, sink)
        var i = 0
        while i < 10 { try w.write_all("abc".as_bytes()); i += 1 }
        if w.buffered() != 30usize { return 12 }
        try w.flush()
        if w.buffered() != 0usize { return 13 }
    }
    // BufReader serves lines from large refills.
    var src = Dribble(alloc::vec::new::<u8>(), 0usize, 5usize, 0usize)
    src.data.extend_from_slice("one\ntwo\n\nlast".as_bytes())
    var r = std::io::buf_reader_with_capacity(4usize, src)
    var line = alloc::vec::new::<u8>()
    let l1 = try r.read_line(line)
    if l1 != 4usize || line[0usize] != 111u8 { return 14 }
    line.clear()
    let l2 = try r.read_line(line)
    line.clear()
    let l3 = try r.read_line(line)
    if l2 != 4usize || l3 != 1usize { return 15 }
    line.clear()
    let l4 = try r.read_line(line)
    if l4 != 4usize { return 16 }
    line.clear()
    let l5 = try r.read_line(line)
    if l5 != 0usize { return 17 }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 100 }
}
