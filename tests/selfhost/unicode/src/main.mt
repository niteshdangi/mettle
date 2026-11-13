import alloc.vec.{ List, new }
import alloc.string.String
import std.{ env, fs, io }
import mettle_syntax.{ tokenize, parse, Kind }
import mettle_syntax.identifiers.{ nfc, is_start, is_continue }

fn hexadecimal(byte: u8): u32? {
    if byte >= b'0' && byte <= b'9' { present((byte - b'0') as u32) }
    else if byte >= b'A' && byte <= b'F' { present((byte - b'A') as u32 + 10u32) }
    else if byte >= b'a' && byte <= b'f' { present((byte - b'a') as u32 + 10u32) }
    else { none }
}

fn number(read bytes: [u8], mut at: usize): u32 {
    var value = 0u32
    var digits = 0usize
    while at < bytes.len() {
        let present(digit) = hexadecimal(bytes[at]) else { break }
        value = value * 16u32 + digit
        at += 1usize
        digits += 1usize
    }
    assert(digits != 0usize, "missing UCD code point")
    value
}

fn column(read bytes: [u8], mut at: usize): String {
    var text = String("")
    while at < bytes.len() && bytes[at] != b';' {
        if bytes[at] == 32u8 { at += 1usize; continue }
        let scalar = number(bytes, mut at)
        text.push(core.char.from_u32(scalar).or_panic())
    }
    assert(at < bytes.len(), "missing UCD column separator")
    at += 1usize
    text
}

fn normalization(read input: Text): (usize, List<u32>) {
    var cases = 0usize
    var explicit = new<u32>()
    var part1 = false
    for line in input.lines() {
        let bytes = line.as_bytes()
        if bytes.is_empty() || bytes[0usize] == b'#' { continue }
        if bytes[0usize] == b'@' { part1 = line.starts_with("@Part1"); continue }
        var at = 0usize
        let c1 = column(bytes, mut at)
        let c2 = column(bytes, mut at)
        let c3 = column(bytes, mut at)
        let c4 = column(bytes, mut at)
        let c5 = column(bytes, mut at)
        if part1 {
            var characters = c1.as_text().chars()
            let scalar = characters.next().or_panic() as u32
            assert(characters.next().is_none(), "Part1 input must be a single scalar")
            explicit.push(scalar)
        }
        assert(nfc(c1.as_text().as_bytes()).or_panic().as_slice() == c2.as_text().as_bytes(), "NFC(c1) differs from c2")
        assert(nfc(c2.as_text().as_bytes()).or_panic().as_slice() == c2.as_text().as_bytes(), "NFC(c2) differs from c2")
        assert(nfc(c3.as_text().as_bytes()).or_panic().as_slice() == c2.as_text().as_bytes(), "NFC(c3) differs from c2")
        assert(nfc(c4.as_text().as_bytes()).or_panic().as_slice() == c4.as_text().as_bytes(), "NFC(c4) differs from c4")
        assert(nfc(c5.as_text().as_bytes()).or_panic().as_slice() == c4.as_text().as_bytes(), "NFC(c5) differs from c4")
        cases += 1usize
    }
    (cases, explicit)
}

fn unchanged_scalars(read explicit: [u32]): Unit {
    var scalar = 0u32
    var index = 0usize
    var buffer = [0u8; 4]
    while scalar < 0x110000u32 {
        if index < explicit.len() && scalar == explicit[index] { index += 1usize }
        else if scalar < 0xd800u32 || scalar > 0xdfffu32 {
            let character = core.char.from_u32(scalar).or_panic()
            let text = character.encode_utf8(mut buffer)
            assert(nfc(text.as_bytes()).or_panic().as_slice() == text.as_bytes(), "unlisted scalar changed under NFC")
        }
        scalar += 1u32
    }
    assert(index == explicit.len(), "Part1 scalar sequence is not ordered")
}

fn expected(read ranges: [(u32, u32)], scalar: u32, mut index: usize): bool {
    while index < ranges.len() && scalar > ranges[index].1 { index += 1usize }
    index < ranges.len() && scalar >= ranges[index].0
}

fn properties(read input: Text): Unit {
    var starts = new<(u32, u32)>()
    var continuations = new<(u32, u32)>()
    for line in input.lines() {
        let bytes = line.as_bytes()
        if bytes.is_empty() || hexadecimal(bytes[0usize]).is_none() { continue }
        var at = 0usize
        let first = number(bytes, mut at)
        var last = first
        if at < bytes.len() && bytes[at] == b'.' { at += 2usize; last = number(bytes, mut at) }
        while at < bytes.len() && bytes[at] != b';' { at += 1usize }
        at += 1usize
        while at < bytes.len() && bytes[at] == 32u8 { at += 1usize }
        let begin = at
        while at < bytes.len() && bytes[at] != 32u8 && bytes[at] != b'#' { at += 1usize }
        let property: read [u8] = read bytes[begin..at]
        if property == "XID_Start".as_bytes() { starts.push((first, last)) }
        else if property == "XID_Continue".as_bytes() { continuations.push((first, last)) }
    }
    assert(!starts.is_empty() && !continuations.is_empty(), "UCD identifier properties missing")
    var scalar = 0u32
    var start_at = 0usize
    var continuation_at = 0usize
    while scalar < 0x110000u32 {
        assert(is_start(scalar) == (scalar == 95u32 || expected(starts.as_slice(), scalar, mut start_at)), "XID_Start differs from UCD")
        assert(is_continue(scalar) == (scalar == 95u32 || expected(continuations.as_slice(), scalar, mut continuation_at)), "XID_Continue differs from UCD")
        scalar += 1u32
    }
    assert(!is_start(0x110000u32) && !is_continue(0xffffffffu32), "invalid scalar accepted")
}

fn integration(): Unit {
    let source = "café cafe\u{301} `café` `cafe\u{301}`"
    let lexed = tokenize(source.as_bytes(), 7u32)
    assert(lexed.diagnostics.error_count == 0usize, "Unicode word rejected")
    var names = 0usize
    for token in lexed.tokens.as_slice() {
        if token.kind.is(Kind.Word) || token.kind.is(Kind.QuotedWord) {
            let name = token.identifier(source.as_bytes()).or_panic()
            assert(name.as_slice() == "café".as_bytes(), "canonically equivalent identifier differs")
            assert(token.span.source == 7u32, "source identity changed")
            names += 1usize
        }
    }
    assert(names == 4usize, "Unicode word boundaries differ")
    let parsed = parse("fn café() { let cafe\u{301} = 1; cafe\u{301} }".as_bytes(), 3u32)
    assert(parsed.diagnostics.error_count == 0usize && parsed.root.is_present(), "Unicode parser integration failed")
    let invalid = [0xffu8]
    assert(nfc(read invalid).is_none(), "normalizer accepted invalid UTF-8")
    let invalid = [0xf0u8, 0x9fu8]
    assert(nfc(read invalid).is_none(), "normalizer accepted truncated UTF-8")
    var marks = String("")
    marks.push_str("a")
    var count = 0usize
    while count < 4096usize { marks.push('\u{315}'); count += 1usize }
    count = 0usize
    while count < 4096usize { marks.push('\u{300}'); count += 1usize }
    var ordered = String("")
    ordered.push_str("à")
    count = 1usize
    while count < 4096usize { ordered.push('\u{300}'); count += 1usize }
    count = 0usize
    while count < 4096usize { ordered.push('\u{315}'); count += 1usize }
    assert(nfc(marks.as_text().as_bytes()).or_panic().as_slice() == ordered.as_text().as_bytes(), "long combining run ordered incorrectly")
}

fn run(): i32 throws io.Error {
    let args = env.args()
    assert(args.len() == 3usize, "expected NormalizationTest.txt and DerivedCoreProperties.txt")
    integration()
    let normalization_data = try fs.read_to_string(args[1usize])
    let results = normalization(normalization_data.as_text())
    let cases = results.0
    unchanged_scalars(results.1.as_slice())
    let property_data = try fs.read_to_string(args[2usize])
    properties(property_data.as_text())
    io.print(f"normalization {cases}\nxid 1114112\nnfc-singletons 1112064\nintegration passed\n")
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => { let message = error.message(); io.eprint(f"{message}\n"); 1 }
    }
}
