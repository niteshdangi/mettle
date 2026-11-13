// profiles: debug release
import core.num
import core.num.IntErrorKind
import core.text.Text

const fn three_bytes(read bytes: [u8; 3]): bool {
    bytes[0usize] == 0u8 && bytes[1usize] == 255u8 && bytes[2usize] == 10u8
}

const fn literal_scalars(): bool {
    match capture num.parse_radix<i32>("+7f", 16u32) {
        success(value) => { if value != 127i32 { return false } },
        failure(_) => { return false }
    }
    match capture num.parse_radix<i32>("\u{e9}", 10u32) {
        failure(error) => {
            if (error.kind as u8) != (IntErrorKind.InvalidDigit as u8) {
                return false
            }
        },
        success(_) => { return false }
    }
    let escaped = "\u{e9}\n\0\\"
    let bytes = escaped.as_bytes()
    if escaped.len() != 5usize || bytes[0usize] != 0xc3u8 ||
        bytes[1usize] != 0xa9u8 || bytes[2usize] != 10u8 ||
        bytes[3usize] != 0u8 || bytes[4usize] != 92u8 { return false }
    let raw = r"x\y"
    let raw_view = raw.as_bytes()
    if raw.len() != 3usize || raw_view[1usize] != 92u8 { return false }
    let raw_bytes: read [u8; 3] = br"x\y"
    if raw_bytes[1usize] != 92u8 || !three_bytes(b"\x00\xff\n") { return false }
    let text = "a\u{e9}z"
    if text.is_char_boundary(2usize) || !text.is_char_boundary(3usize) {
        return false
    }
    match text.get(1usize, 2usize) {
        present(_) => false,
        none => true
    }
}

const fn text_range(start: usize, end: usize): read Text from static {
    match ROOT.get(start, end) {
        present(value) => value,
        none => { core.panic.panic("invalid fixture text range") }
    }
}

const fn literal_bytes(): read [u8; 3] from static { b"\x00\xff\n" }
const fn middle_bytes(): read [u8] from static {
    text_range(1usize, 3usize).as_bytes()
}
const fn interior_pointer(): ptr<read u8> {
    unsafe { core.slice.data(ROOT.as_bytes()).add(1usize) }
}
const fn slice_pointer(): ptr<read [u8]> {
    core.ptr.from_ref(middle_bytes())
}
const fn empty_literal(): read Text from static { "" }

static ROOT: read Text = "a\u{e9}z"
static WHOLE: read Text = text_range(0usize, 4usize)
static MIDDLE: read Text = text_range(1usize, 3usize)
static EMPTY: read Text = text_range(1usize, 1usize)
static END: read Text = text_range(4usize, 4usize)
static BYTES: read [u8] = middle_bytes()
static BYTE_ARRAY: read [u8; 3] = literal_bytes()
static POINTER: ptr<read u8> = interior_pointer()
static SLICE_POINTER: ptr<read [u8]> = slice_pointer()
static EMPTY_LITERAL: read Text = empty_literal()

const fn nested_end(): read Text from static {
    match MIDDLE.get(2usize, 2usize) {
        present(value) => value,
        none => { core.panic.panic("invalid fixture nested range") }
    }
}
static NESTED_END: read Text = nested_end()

const fn reloaded(): bool {
    let base = core.slice.data(ROOT.as_bytes())
    let middle_bytes = MIDDLE.as_bytes()
    let middle = core.slice.data(middle_bytes)
    let end = core.slice.data(NESTED_END.as_bytes())
    MIDDLE.len() == 2usize && middle_bytes[0usize] == 0xc3u8 &&
        END.is_empty() && NESTED_END.is_empty() && three_bytes(BYTE_ARRAY) &&
        middle == unsafe { base.add(1usize) } &&
        end == unsafe { base.add(3usize) } &&
        POINTER == middle
}

const SCALARS: bool = literal_scalars()
const RELOADED: bool = reloaded()

fn main(): i32 {
    if !SCALARS || !RELOADED || WHOLE.len() != 4usize ||
        MIDDLE.len() != 2usize || !EMPTY.is_empty() || !END.is_empty() ||
        !NESTED_END.is_empty() || !EMPTY_LITERAL.is_empty() { return 1 }
    if BYTES.len() != 2usize || BYTES[0usize] != 0xc3u8 ||
        BYTES[1usize] != 0xa9u8 || !three_bytes(BYTE_ARRAY) { return 2 }
    let base = core.slice.data(ROOT.as_bytes())
    if core.slice.data(WHOLE.as_bytes()) != base ||
        core.slice.data(MIDDLE.as_bytes()) != unsafe { base.add(1usize) } ||
        core.slice.data(EMPTY.as_bytes()) != unsafe { base.add(1usize) } ||
        core.slice.data(END.as_bytes()) != unsafe { base.add(4usize) } ||
        core.slice.data(NESTED_END.as_bytes()) != unsafe { base.add(3usize) } ||
        core.slice.data(BYTES) != POINTER { return 3 }
    let pointed = unsafe { read *SLICE_POINTER }
    if pointed.len() != 2usize || pointed[1usize] != 0xa9u8 ||
        core.slice.data(pointed) != POINTER || unsafe { *POINTER } != 0xc3u8 {
        return 4
    }
    0
}
