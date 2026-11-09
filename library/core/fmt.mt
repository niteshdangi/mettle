// Formatting without allocation. Output goes to any `Write` sink; failures of
// the sink propagate as `Error` through `try`. `BufferWriter` formats into a
// caller-provided byte buffer. Format specifications are built explicitly with
// `Spec` since text-interpolation syntax is not part of `core`.
import super.cmp.Ordering
import super.iter.Iterator
import super.slice
import super.text.Text
import super.text.from_utf8_unchecked

pub copy type Error {}

pub interface Write {
    mut fn write_str(text: read Text): Unit throws Error;

    mut fn write_char(value: char): Unit throws Error {
        var bytes = [0u8, 0u8, 0u8, 0u8]
        let scalar = value as u32
        var used = 1usize
        if scalar < 0x80u32 {
            bytes[0usize] = scalar as u8
        } else if scalar < 0x800u32 {
            bytes[0usize] = (0xc0u32 | (scalar >> 6u32)) as u8
            bytes[1usize] = (0x80u32 | (scalar & 0x3fu32)) as u8
            used = 2usize
        } else if scalar < 0x10000u32 {
            bytes[0usize] = (0xe0u32 | (scalar >> 12u32)) as u8
            bytes[1usize] = (0x80u32 | ((scalar >> 6u32) & 0x3fu32)) as u8
            bytes[2usize] = (0x80u32 | (scalar & 0x3fu32)) as u8
            used = 3usize
        } else {
            bytes[0usize] = (0xf0u32 | (scalar >> 18u32)) as u8
            bytes[1usize] = (0x80u32 | ((scalar >> 12u32) & 0x3fu32)) as u8
            bytes[2usize] = (0x80u32 | ((scalar >> 6u32) & 0x3fu32)) as u8
            bytes[3usize] = (0x80u32 | (scalar & 0x3fu32)) as u8
            used = 4usize
        }
        // The bytes were just encoded from a scalar value.
        try self.write_str(unsafe { from_utf8_unchecked(unsafe { slice.subslice_unchecked(read bytes, 0usize, used) }) })
    }
}

pub copy enum Align { Unknown, Left, Right, Center }

// Rendering options for one value: `width` pads, `precision` truncates text
// (or limits digits where a type defines it), sign flags select positive-sign
// behavior, `zero` pads numbers after the sign, and `alternate` adds prefixes.
pub copy type Spec {
    pub fill: char
    pub align: Align
    pub width: usize?
    pub precision: usize?
    pub plus: bool
    pub minus: bool
    pub alternate: bool
    pub zero: bool
}
pub fn spec(): Spec { Spec(' ', Align.Unknown, none, none, false, false, false, false) }

pub type Formatter<region r> { sink: mut any Write from r; options: Spec; indent: usize; line_start: bool }
pub fn formatter<W: Write>(sink: mut W, options: Spec): Formatter { Formatter(mut sink, options, 0usize, false) }

pub type DebugStruct<region s, region b> { f: mut Formatter<region s> from b; first: bool }
pub type DebugTuple<region s, region b> { f: mut Formatter<region s> from b; first: bool; count: usize; unnamed: bool }
pub type DebugList<region s, region b> { f: mut Formatter<region s> from b; first: bool }
pub type DebugSet<region s, region b> { f: mut Formatter<region s> from b; first: bool }
pub type DebugMap<region s, region b> {
    f: mut Formatter<region s> from b
    first: bool
    awaiting_value: bool
}

extend<region r> Formatter<region r> {
    pub fn options(): Spec { self.options }
    pub fn width(): usize? { self.options.width }
    pub fn precision(): usize? { self.options.precision }
    pub fn alternate(): bool { self.options.alternate }
    pub fn sign_plus(): bool { self.options.plus }
    pub fn sign_minus(): bool { self.options.minus }
    pub fn sign_aware_zero_pad(): bool { self.options.zero }
    pub fn debug_struct<region b>(
        receiver self: mut Formatter<region r> from b,
        name: read Text from b
    ): DebugStruct<region r, region b> throws Error {
        try self.write_str(name)
        try self.debug_open(" {")
        DebugStruct(mut self, true)
    }
    pub fn debug_tuple<region b>(
        receiver self: mut Formatter<region r> from b,
        name: read Text from b
    ): DebugTuple<region r, region b> throws Error {
        try self.write_str(name)
        try self.debug_open("(")
        DebugTuple(mut self, true, 0usize, name.is_empty())
    }
    pub fn debug_list<region b>(
        receiver self: mut Formatter<region r> from b
    ): DebugList<region r, region b> throws Error {
        try self.debug_open("[")
        DebugList(mut self, true)
    }
    pub fn debug_set<region b>(
        receiver self: mut Formatter<region r> from b
    ): DebugSet<region r, region b> throws Error {
        try self.debug_open("{")
        DebugSet(mut self, true)
    }
    pub fn debug_map<region b>(
        receiver self: mut Formatter<region r> from b
    ): DebugMap<region r, region b> throws Error {
        try self.debug_open("{")
        DebugMap(mut self, true, false)
    }
    pub mut fn write_str(text: read Text): Unit throws Error { try self.emit_str(text) }
    pub mut fn write_char(value: char): Unit throws Error { try self.emit_char(value) }
    pub mut fn write_fmt(message: format Message): Unit throws Error {
        try message.write_to(mut self)
    }

    // Every byte goes through `emit_char` so pretty (`alternate`) debug output
    // can indent lazily at the start of each non-empty line.
    mut fn emit_indent(): Unit throws Error {
        if self.line_start {
            self.line_start = false
            var column = 0usize
            while column < self.indent * 4usize {
                try self.sink.write_char(' ')
                column += 1usize
            }
        }
    }
    mut fn emit_char(value: char): Unit throws Error {
        if value == '\n' {
            self.line_start = true
            return try self.sink.write_char(value)
        }
        try self.emit_indent()
        try self.sink.write_char(value)
    }
    // `part` holds at most one newline, as its last byte.
    mut fn emit_line(part: read Text): Unit throws Error {
        let bytes = part.as_bytes()
        if bytes.len() == 1usize && bytes[0usize] == 10u8 { return try self.emit_char('\n') }
        try self.emit_indent()
        try self.sink.write_str(part)
        self.line_start = bytes[bytes.len() - 1usize] == 10u8
    }
    mut fn emit_str(text: read Text): Unit throws Error {
        if self.indent == 0usize && !self.line_start { return try self.sink.write_str(text) }
        let bytes = text.as_bytes()
        let n = bytes.len()
        var start = 0usize
        var i = 0usize
        while i < n {
            if bytes[i] == 10u8 {
                match text.get(start, i + 1usize) { present(part) => { try self.emit_line(part) }, none => {} }
                start = i + 1usize
            }
            i += 1usize
        }
        if start < n {
            match text.get(start, n) { present(part) => { try self.emit_line(part) }, none => {} }
        }
    }

    // Debug sequences/maps: `debug_open`, then per item `debug_item_start(first)`,
    // the item, `debug_item_end`, and finally `debug_close(close, empty)`.
    // With `alternate` each item sits on its own indented line with a trailing comma.
    pub mut fn debug_open(open: read Text): Unit throws Error {
        try self.emit_str(open)
        if self.options.alternate { self.indent += 1usize }
    }
    pub mut fn debug_item_start(first: bool): Unit throws Error {
        if self.options.alternate { try self.emit_char('\n') }
        else if !first { try self.emit_str(", ") }
    }
    pub mut fn debug_item_end(): Unit throws Error {
        if self.options.alternate { try self.emit_char(',') }
    }
    pub mut fn debug_close(close: read Text, empty: bool): Unit throws Error {
        if self.options.alternate {
            self.indent -= 1usize
            if !empty { try self.emit_char('\n') }
        }
        try self.emit_str(close)
    }

    mut fn fill_run(count: usize): Unit throws Error {
        var written = 0usize
        while written < count {
            try self.emit_char(self.options.fill)
            written += 1usize
        }
    }

    // Pads `content` (`length` characters) to the requested width.
    mut fn padded(content: read Text, length: usize, default_align: Align): Unit throws Error {
        let width = match self.options.width { present(w) => w, none => 0usize }
        if length >= width { return try self.emit_str(content) }
        let gap = width - length
        let chosen = match self.options.align { Align.Unknown => default_align, Align.Left => Align.Left, Align.Right => Align.Right, Align.Center => Align.Center }
        let before = match chosen { Align.Right => gap, Align.Center => gap / 2usize, Align.Left => 0usize, Align.Unknown => 0usize }
        try self.fill_run(before)
        try self.emit_str(content)
        try self.fill_run(gap - before)
    }

    // Text: precision truncates to that many characters, width pads (left-aligned by default).
    pub mut fn pad(content: read Text): Unit throws Error {
        let counted = prefix_extent(content, self.options.precision)
        let length = counted.0
        let end = counted.1
        match content.get(0usize, end) { present(part) => { try self.padded(part, length, Align.Left) }, none => {} }
    }

    // Numbers: `digits` has no sign or prefix; zero-padding goes after them.
    pub mut fn pad_integral(non_negative: bool, prefix: read Text, digits: read Text): Unit throws Error {
        var length = digits.len()
        var sign: char? = none
        if !non_negative { sign = present('-'); length += 1usize }
        else if self.options.plus { sign = present('+'); length += 1usize }
        let has_prefix = self.options.alternate
        if has_prefix { length += prefix.len() }
        let width = match self.options.width { present(w) => w, none => 0usize }
        if self.options.zero && length < width {
            match sign { present(c) => { try self.emit_char(c) }, none => {} }
            if has_prefix { try self.emit_str(prefix) }
            var zeros = width - length
            while zeros > 0usize { try self.emit_char('0'); zeros -= 1usize }
            return try self.emit_str(digits)
        }
        // Not zero-padded: build sign, prefix and digits as one padded unit.
        let before = if width > length { match self.options.align { Align.Left => 0usize, Align.Center => (width - length) / 2usize, Align.Right => width - length, Align.Unknown => width - length } } else { 0usize }
        try self.fill_run(before)
        match sign { present(c) => { try self.emit_char(c) }, none => {} }
        if has_prefix { try self.emit_str(prefix) }
        try self.emit_str(digits)
        if width > length { try self.fill_run(width - length - before) }
    }
}

extend<region s, region b> DebugStruct<region s, region b> {
    pub mut fn field<T: Debug + unsized>(name: read Text, value: read T): mut Self from self throws Error {
        if self.first && !self.f.alternate() { try self.f.write_str(" ") }
        try self.f.debug_item_start(self.first)
        try self.f.write_str(name)
        try self.f.write_str(": ")
        try T.(Debug).fmt(value, mut *self.f)
        try self.f.debug_item_end()
        self.first = false
        mut self
    }
    pub take fn finish(): Unit throws Error {
        if !self.first && !self.f.alternate() { try self.f.write_str(" ") }
        try self.f.debug_close("}", self.first)
    }
}

extend<region s, region b> DebugTuple<region s, region b> {
    pub mut fn field<T: Debug + unsized>(value: read T): mut Self from self throws Error {
        try self.f.debug_item_start(self.first)
        try T.(Debug).fmt(value, mut *self.f)
        try self.f.debug_item_end()
        self.first = false
        self.count += 1usize
        mut self
    }
    pub take fn finish(): Unit throws Error {
        if self.unnamed && self.count == 1usize && !self.f.alternate() { try self.f.write_str(",") }
        try self.f.debug_close(")", self.first)
    }
}

extend<region s, region b> DebugList<region s, region b> {
    pub mut fn entry<T: Debug>(value: read T): mut Self from self throws Error {
        try self.f.debug_item_start(self.first)
        try T.(Debug).fmt(value, mut *self.f)
        try self.f.debug_item_end()
        self.first = false
        mut self
    }
    pub take fn finish(): Unit throws Error { try self.f.debug_close("]", self.first) }
}

extend<region s, region b> DebugSet<region s, region b> {
    pub mut fn entry<T: Debug>(value: read T): mut Self from self throws Error {
        try self.f.debug_item_start(self.first)
        try T.(Debug).fmt(value, mut *self.f)
        try self.f.debug_item_end()
        self.first = false
        mut self
    }
    pub take fn finish(): Unit throws Error { try self.f.debug_close("}", self.first) }
}

extend<region s, region b> DebugMap<region s, region b> {
    pub mut fn key<K: Debug>(key: read K): mut Self from self throws Error {
        if self.awaiting_value { super.panic.panic("debug map key requires a value") }
        try self.f.debug_item_start(self.first)
        try K.(Debug).fmt(key, mut *self.f)
        try self.f.write_str(": ")
        self.awaiting_value = true
        mut self
    }
    pub mut fn value<V: Debug>(value: read V): mut Self from self throws Error {
        if !self.awaiting_value { super.panic.panic("debug map value requires a key") }
        try V.(Debug).fmt(value, mut *self.f)
        try self.f.debug_item_end()
        self.awaiting_value = false
        self.first = false
        mut self
    }
    pub mut fn entry<K: Debug, V: Debug>(key: read K, value: read V): mut Self from self throws Error {
        try self.key(key)
        try self.value(value)
        mut self
    }
    pub take fn finish(): Unit throws Error {
        if self.awaiting_value { super.panic.panic("debug map entry is missing a value") }
        try self.f.debug_close("}", self.first)
    }
}

extend<region r> Formatter<region r> implements Write {
    mut fn write_str(text: read Text): Unit throws Error { try self.emit_str(text) }
}

pub interface Display { fn fmt(f: mut Formatter): Unit throws Error; }
pub interface Debug { fn fmt(f: mut Formatter): Unit throws Error; }
pub interface Binary { fn fmt(f: mut Formatter): Unit throws Error; }
pub interface Octal { fn fmt(f: mut Formatter): Unit throws Error; }
pub interface LowerHex { fn fmt(f: mut Formatter): Unit throws Error; }
pub interface UpperHex { fn fmt(f: mut Formatter): Unit throws Error; }

pub fn write<W: Write, T: Display>(sink: mut W, value: read T): Unit throws Error {
    var f = formatter(mut sink, spec())
    try value.fmt(mut f)
}
pub fn write_with<W: Write, T: Display>(sink: mut W, value: read T, options: Spec): Unit throws Error {
    var f = formatter(mut sink, options)
    try value.fmt(mut f)
}


// Format recipes. An f-string passed to a `format` parameter is built by the
// compiler from `message`/`literal`/`field`: a fixed borrowed descriptor of
// literal pieces and a caller-stack array of fields (value pointer, renderer,
// metadata). It owns nothing and allocates nothing; `Field` carries no region,
// so these constructors are unsafe and only compiler-built recipes call them.
pub copy type Piece { data: ptr<read u8>; len: usize }

// Byte sink with a fixed shape, so renderers do not depend on the writer type.
pub type Sink { context: ptr<mut u8>; write: fn(ptr<mut u8>, read Text): Unit throws Error }
extend Sink implements Write {
    mut fn write_str(text: read Text): Unit throws Error { try (self.write)(self.context, text) }
}
fn sink_write<W: Write>(context: ptr<mut u8>, text: read Text): Unit throws Error {
    try (unsafe { mut *context.cast<W>() }).write_str(text)
}

pub copy type Field {
    prefix: Piece
    value: ptr<read u8>
    meta: usize
    render: fn(ptr<read u8>, usize, mut Sink): Unit throws Error
}
pub type Message<region r> { fields: read [Field] from r; tail: Piece }

fn piece(text: read Text): Piece {
    let bytes = text.as_bytes()
    Piece(slice.data(bytes), bytes.len())
}
// Safety: `data`/`len` describe UTF-8 text that outlives region `r`.
unsafe fn piece_text<region r>(p: Piece): read Text from r {
    unsafe { from_utf8_unchecked(unsafe { slice.from_raw_parts(p.data, p.len) }) }
}
fn render_sized<T: Display>(value: ptr<read u8>, meta: usize, sink: mut Sink): Unit throws Error {
    var f = formatter(mut sink, spec())
    try (unsafe { read *value.cast<T>() }).fmt(mut f)
}
fn render_text(value: ptr<read u8>, meta: usize, sink: mut Sink): Unit throws Error {
    try sink.write_str(unsafe { piece_text(Piece(value, meta)) })
}
fn sized<T: Display>(value: read T, prefix: read Text): Field {
    Field(piece(prefix), core.ptr.from_ref(read value).cast<u8>(), 0usize, render_sized<T>)
}
pub fn text_field(value: read Text, prefix: read Text): Field {
    let bytes = value.as_bytes()
    Field(piece(prefix), slice.data(bytes), bytes.len(), render_text)
}

// Values that can fill a `{hole}`: any sized `Display` type (integers, floats,
// `bool`, `char`, `String` and user types) through one blanket implementation,
// and `Text`, whose unsized view is carried directly.
pub interface Hole { fn hole(prefix: read Text): Field; }
extend<T: Display> T implements Hole {
    fn hole(prefix: read Text): Field { sized(read self, prefix) }
}
extend Text implements Hole {
    fn hole(prefix: read Text): Field { text_field(self, prefix) }
}

// Safety: the pointers in the result must not outlive `value`; the compiler
// keeps `value` alive through the enclosing call.
pub unsafe fn field<T: Hole + unsized>(value: read T, prefix: read Text): Field { value.hole(prefix) }
pub unsafe fn message<region r>(fields: read [Field] from r, tail: read Text): Message<region r> {
    Message(read fields, piece(tail))
}
unsafe fn no_fields<region r>(anchor: read Text from r): read [Field] from r {
    unsafe { slice.from_raw_parts(slice.data(anchor.as_bytes()).cast<Field>(), 0usize) }
}
pub unsafe fn literal<region r>(tail: read Text from r): Message<region r> {
    unsafe { message(no_fields(tail), tail) }
}

extend<region r> Message<region r> {
    // Renders pieces and fields in order into `sink`, stopping at the first failure.
    pub fn write_to<W: Write>(sink: mut W): Unit throws Error {
        var out = Sink(core.ptr.from_mut(mut sink).cast<u8>(), sink_write<W>)
        var i = 0usize
        while i < self.fields.len() {
            let f = self.fields[i]
            try out.write_str(unsafe { piece_text(f.prefix) })
            try (f.render)(f.value, f.meta, mut out)
            i += 1usize
        }
        try out.write_str(unsafe { piece_text(self.tail) })
    }
}

// Writes into a caller-owned byte buffer; fails (without partial characters) when full.
pub type BufferWriter<region r> { buffer: mut [u8] from r; length: usize }
pub fn buffer_writer(buffer: mut [u8]): BufferWriter<region buffer> { BufferWriter(mut buffer, 0usize) }
extend<region r> BufferWriter<region r> {
    pub fn len(): usize { self.length }
}
extend<region r> BufferWriter<region r> implements Write {
    mut fn write_str(text: read Text): Unit throws Error {
        let bytes = text.as_bytes()
        if self.buffer.len() - self.length < bytes.len() { throw Error() }
        var i = 0usize
        while i < bytes.len() {
            self.buffer[self.length + i] = bytes[i]
            i += 1usize
        }
        self.length += bytes.len()
    }
}

// The text a `BufferWriter` produced: the first `length` bytes of its buffer,
// which the writer no longer borrows once it is last used.
pub fn written_text(buffer: read [u8], length: usize): (read Text from buffer)? {
    match slice.subslice(buffer, 0usize, length) {
        present(bytes) => super.text.from_utf8(bytes),
        none => none
    }
}

// Counts the bytes that would be written.
pub type Counter { pub bytes: usize }
extend Counter implements Write {
    mut fn write_str(text: read Text): Unit throws Error { self.bytes += text.len() }
}

// Characters and bytes of the longest prefix of `content` within `limit` characters.
fn prefix_extent(content: read Text, limit: usize?): (usize, usize) {
    var length = 0usize
    var end = 0usize
    var scan = content.chars()
    while true {
        match scan.next() {
            present(c) => {
                if match limit { present(most) => length >= most, none => false } { break }
                length += 1usize
                end += utf8_len(c)
            },
            none => { break }
        }
    }
    (length, end)
}

fn utf8_len(value: char): usize {
    let scalar = value as u32
    if scalar < 0x80u32 { 1usize } else if scalar < 0x800u32 { 2usize } else if scalar < 0x10000u32 { 3usize } else { 4usize }
}

fn digit_char(digit: u64, upper: bool): u8 {
    if digit < 10u64 { return 0x30u8 + (digit as u8) }
    (if upper { 0x41u8 } else { 0x61u8 }) + ((digit - 10u64) as u8)
}

pub fn fmt_radix(f: mut Formatter, magnitude: u64, negative: bool, radix: u64, upper: bool, prefix: read Text): Unit throws Error {
    var digits = [0u8; 64]
    var start = 64usize
    var rest = magnitude
    while true {
        start -= 1usize
        digits[start] = digit_char(rest % radix, upper)
        rest = rest / radix
        if rest == 0u64 { break }
    }
    // ASCII digits only.
    let text = unsafe { from_utf8_unchecked(unsafe { slice.subslice_unchecked(read digits, start, 64usize) }) }
    try f.pad_integral(!negative, prefix, text)
}
fn fmt_radix128(f: mut Formatter, magnitude: u128, negative: bool, radix: u128, upper: bool, prefix: read Text): Unit throws Error {
    var digits = [0u8; 128]
    var start = 128usize
    var rest = magnitude
    while true {
        start -= 1usize
        digits[start] = digit_char((rest % radix) as u64, upper)
        rest = rest / radix
        if rest == 0u128 { break }
    }
    let text = unsafe { from_utf8_unchecked(unsafe { slice.subslice_unchecked(read digits, start, 128usize) }) }
    try f.pad_integral(!negative, prefix, text)
}
extend i8 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        let wide = self as i64
        try fmt_radix(mut f, (if wide < 0i64 { wide.wrapping_neg() } else { wide }) as u64, wide < 0i64, 10u64, false, "")
    }
}
extend i8 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try i8.(Display).fmt(self, mut f) }
}
extend i8 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 2u64, false, "0b") }
}
extend i8 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 8u64, false, "0o") }
}
extend i8 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 16u64, false, "0x") }
}
extend i8 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 16u64, true, "0x") }
}
extend i16 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        let wide = self as i64
        try fmt_radix(mut f, (if wide < 0i64 { wide.wrapping_neg() } else { wide }) as u64, wide < 0i64, 10u64, false, "")
    }
}
extend i16 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try i16.(Display).fmt(self, mut f) }
}
extend i16 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 2u64, false, "0b") }
}
extend i16 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 8u64, false, "0o") }
}
extend i16 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 16u64, false, "0x") }
}
extend i16 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 16u64, true, "0x") }
}
extend i32 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        let wide = self as i64
        try fmt_radix(mut f, (if wide < 0i64 { wide.wrapping_neg() } else { wide }) as u64, wide < 0i64, 10u64, false, "")
    }
}
extend i32 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try i32.(Display).fmt(self, mut f) }
}
extend i32 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 2u64, false, "0b") }
}
extend i32 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 8u64, false, "0o") }
}
extend i32 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 16u64, false, "0x") }
}
extend i32 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 16u64, true, "0x") }
}
extend i64 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        let wide = self as i64
        try fmt_radix(mut f, (if wide < 0i64 { wide.wrapping_neg() } else { wide }) as u64, wide < 0i64, 10u64, false, "")
    }
}
extend i64 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try i64.(Display).fmt(self, mut f) }
}
extend i64 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 2u64, false, "0b") }
}
extend i64 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 8u64, false, "0o") }
}
extend i64 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 16u64, false, "0x") }
}
extend i64 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 16u64, true, "0x") }
}
extend isize implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        let wide = self as i64
        try fmt_radix(mut f, (if wide < 0i64 { wide.wrapping_neg() } else { wide }) as u64, wide < 0i64, 10u64, false, "")
    }
}
extend isize implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try isize.(Display).fmt(self, mut f) }
}
extend isize implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 2u64, false, "0b") }
}
extend isize implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 8u64, false, "0o") }
}
extend isize implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 16u64, false, "0x") }
}
extend isize implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 16u64, true, "0x") }
}
extend u8 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u8 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u8 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 2u64, false, "0b") }
}
extend u8 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 8u64, false, "0o") }
}
extend u8 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 16u64, false, "0x") }
}
extend u8 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u8) as u64, false, 16u64, true, "0x") }
}
extend u16 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u16 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u16 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 2u64, false, "0b") }
}
extend u16 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 8u64, false, "0o") }
}
extend u16 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 16u64, false, "0x") }
}
extend u16 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u16) as u64, false, 16u64, true, "0x") }
}
extend u32 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u32 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u32 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 2u64, false, "0b") }
}
extend u32 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 8u64, false, "0o") }
}
extend u32 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 16u64, false, "0x") }
}
extend u32 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u32) as u64, false, 16u64, true, "0x") }
}
extend u64 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u64 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend u64 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 2u64, false, "0b") }
}
extend u64 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 8u64, false, "0o") }
}
extend u64 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 16u64, false, "0x") }
}
extend u64 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as u64) as u64, false, 16u64, true, "0x") }
}
extend usize implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend usize implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, self as u64, false, 10u64, false, "") }
}
extend usize implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 2u64, false, "0b") }
}
extend usize implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 8u64, false, "0o") }
}
extend usize implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 16u64, false, "0x") }
}
extend usize implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix(mut f, (self as usize) as u64, false, 16u64, true, "0x") }
}
extend i128 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        let negative = self < 0i128
        let magnitude = if negative { self.wrapping_neg() as u128 } else { self as u128 }
        try fmt_radix128(mut f, magnitude, negative, 10u128, false, "")
    }
}
extend i128 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try i128.(Display).fmt(self, mut f) }
}
extend i128 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self as u128, false, 2u128, false, "0b") }
}
extend i128 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self as u128, false, 8u128, false, "0o") }
}
extend i128 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self as u128, false, 16u128, false, "0x") }
}
extend i128 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self as u128, false, 16u128, true, "0x") }
}
extend u128 implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self, false, 10u128, false, "") }
}
extend u128 implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self, false, 10u128, false, "") }
}
extend u128 implements Binary {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self, false, 2u128, false, "0b") }
}
extend u128 implements Octal {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self, false, 8u128, false, "0o") }
}
extend u128 implements LowerHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self, false, 16u128, false, "0x") }
}
extend u128 implements UpperHex {
    fn fmt(f: mut Formatter): Unit throws Error { try fmt_radix128(mut f, self, false, 16u128, true, "0x") }
}

extend bool implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { if self { try f.pad("true") } else { try f.pad("false") } }
}
extend bool implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { if self { try f.pad("true") } else { try f.pad("false") } }
}
extend Text implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try f.pad(self) }
}
extend char implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        var buffer = [0u8; 4]
        var sink = buffer_writer(mut buffer)
        try sink.write_char(self)
        let n = sink.len()
        match written_text(read buffer, n) {
            present(t) => try f.pad(t),
            none => throw Error()
        }
    }
}

fn escape_char(f: mut Formatter, value: char, quote: char): Unit throws Error {
    if value == quote || value == '\\' { try f.write_char('\\'); return try f.write_char(value) }
    if value == '\n' { return try f.write_str("\\n") }
    if value == '\r' { return try f.write_str("\\r") }
    if value == '\t' { return try f.write_str("\\t") }
    try f.write_char(value)
}
extend Text implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_char('"')
        var scan = self.chars()
        while true {
            match scan.next() { present(c) => { try escape_char(mut f, c, '"') }, none => { break } }
        }
        try f.write_char('"')
    }
}
extend char implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_char('\'')
        try escape_char(mut f, self, '\'')
        try f.write_char('\'')
    }
}
extend Unit implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try f.write_str("()") }
}
extend Ordering implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        match self {
            Ordering.Less => { try f.write_str("Less") },
            Ordering.Equal => { try f.write_str("Equal") },
            Ordering.Greater => { try f.write_str("Greater") }
        }
    }
}
extend Error implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try f.write_str("Error") }
}
extend Error implements Display {
    fn fmt(f: mut Formatter): Unit throws Error { try f.write_str("an error occurred when formatting an argument") }
}
// Debug output of a slice, shared by arrays and slice-backed collections.
pub fn debug_slice<T: Debug>(items: read [T], f: mut Formatter): Unit throws Error {
    try f.debug_open("[")
    var i = 0usize
    while i < items.len() {
        try f.debug_item_start(i == 0usize)
        try T.(Debug).fmt(items[i], mut f)
        try f.debug_item_end()
        i += 1usize
    }
    try f.debug_close("]", items.len() == 0usize)
}
extend<T: Debug> [T] implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try debug_slice(self, mut f) }
}

// Tuples print as `(a, b)`; a one-element tuple keeps its trailing comma.
extend<A: Debug> (A,) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        if !f.options.alternate { try f.write_char(',') }
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug> (A, B) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug> (A, B, C) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug> (A, B, C, D) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug> (A, B, C, D, E) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug> (A, B, C, D, E, F) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug, G: Debug> (A, B, C, D, E, F, G) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try G.(Debug).fmt(self.6, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug, G: Debug, H: Debug> (A, B, C, D, E, F, G, H) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try G.(Debug).fmt(self.6, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try H.(Debug).fmt(self.7, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug, G: Debug, H: Debug, I: Debug> (A, B, C, D, E, F, G, H, I) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try G.(Debug).fmt(self.6, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try H.(Debug).fmt(self.7, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try I.(Debug).fmt(self.8, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug, G: Debug, H: Debug, I: Debug, J: Debug> (A, B, C, D, E, F, G, H, I, J) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try G.(Debug).fmt(self.6, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try H.(Debug).fmt(self.7, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try I.(Debug).fmt(self.8, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try J.(Debug).fmt(self.9, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug, G: Debug, H: Debug, I: Debug, J: Debug, K: Debug> (A, B, C, D, E, F, G, H, I, J, K) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try G.(Debug).fmt(self.6, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try H.(Debug).fmt(self.7, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try I.(Debug).fmt(self.8, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try J.(Debug).fmt(self.9, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try K.(Debug).fmt(self.10, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}
extend<A: Debug, B: Debug, C: Debug, D: Debug, E: Debug, F: Debug, G: Debug, H: Debug, I: Debug, J: Debug, K: Debug, L: Debug> (A, B, C, D, E, F, G, H, I, J, K, L) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.debug_open("(")
        try f.debug_item_start(true)
        try A.(Debug).fmt(self.0, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try B.(Debug).fmt(self.1, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try C.(Debug).fmt(self.2, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try D.(Debug).fmt(self.3, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try E.(Debug).fmt(self.4, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try F.(Debug).fmt(self.5, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try G.(Debug).fmt(self.6, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try H.(Debug).fmt(self.7, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try I.(Debug).fmt(self.8, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try J.(Debug).fmt(self.9, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try K.(Debug).fmt(self.10, mut f)
        try f.debug_item_end()
        try f.debug_item_start(false)
        try L.(Debug).fmt(self.11, mut f)
        try f.debug_item_end()
        try f.debug_close(")", false)
    }
}

extend<T: Debug> T? implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        match self {
            present(value) => {
                try f.debug_open("present(")
                try f.debug_item_start(true)
                try T.(Debug).fmt(value, mut f)
                try f.debug_item_end()
                try f.debug_close(")", false)
            },
            none => { try f.write_str("none") }
        }
    }
}
extend<T: Debug, E: Debug> (T throws E) implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        match self {
            success(value) => {
                try f.debug_open("success(")
                try f.debug_item_start(true)
                try T.(Debug).fmt(value, mut f)
                try f.debug_item_end()
                try f.debug_close(")", false)
            },
            failure(error) => {
                try f.debug_open("failure(")
                try f.debug_item_start(true)
                try E.(Debug).fmt(error, mut f)
                try f.debug_item_end()
                try f.debug_close(")", false)
            }
        }
    }
}
extend<T: Debug, const N: usize> [T; N] implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try debug_slice(read self[..], mut f)
    }
}
