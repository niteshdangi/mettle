import mettle_foundation.{ Diagnostics, Phase, Span }

fn hex(byte: u8): u32? {
    if byte >= b'0' && byte <= b'9' { present((byte - b'0') as u32) }
    else if byte >= b'a' && byte <= b'f' { present((byte - b'a') as u32 + 10u32) }
    else if byte >= b'A' && byte <= b'F' { present((byte - b'A') as u32 + 10u32) }
    else { none }
}

pub fn character_value(read literal: [u8], byte: bool, span: Span, mut diagnostics: Diagnostics): u32? {
    let begin = if byte { 1usize } else { 0usize }
    if literal.len() < begin + 3 || literal[begin] != b'\'' || literal[literal.len() - 1] != b'\'' {
        diagnostics.report(Phase.Lex, span, "unterminated character literal")
        return none
    }
    let start = begin + 1
    let end = literal.len() - 1
    let length = end - start
    var value = 0u32
    if literal[start] == b'\\' {
        if length < 2 {
            diagnostics.report(Phase.Lex, span, "incomplete character escape")
            return none
        }
        let escape = literal[start + 1]
        if (escape == b'u' && !byte) || (escape == b'x' && byte) {
            let unicode = escape == b'u'
            if unicode && (length < 5 || literal[start + 2] != b'{' || literal[end - 1] != b'}') {
                diagnostics.report(Phase.Lex, span, "Unicode escape requires '\\u{hex}'")
                return none
            }
            if !unicode && length != 4 {
                diagnostics.report(Phase.Lex, span, "byte escape requires two hexadecimal digits")
                return none
            }
            let first = start + if unicode { 3usize } else { 2usize }
            let stop = end - if unicode { 1usize } else { 0usize }
            var valid = stop > first && stop - first <= 6
            var index = first
            while index < stop && valid {
                match hex(literal[index]) {
                    present(digit) => { value = value * 16u32 + digit },
                    none => { valid = false }
                }
                index += 1
            }
            if !valid {
                if unicode { diagnostics.report(Phase.Lex, span, "invalid Unicode scalar escape") }
                else { diagnostics.report(Phase.Lex, span, "invalid byte escape") }
                return none
            }
        } else {
            if length != 2 {
                diagnostics.report(Phase.Lex, span, "character literal must contain exactly one scalar")
                return none
            }
            value = match escape {
                b'n' => 10u32, b'r' => 13u32, b't' => 9u32, b'0' => 0u32,
                b'\\' => 92u32, b'\'' => 39u32,
                _ => {
                    diagnostics.report(Phase.Lex, span, "invalid character escape")
                    return none
                }
            }
        }
    } else {
        let first = literal[start]
        let width = if first < 128u8 { 1usize } else if first < 0xe0u8 { 2usize }
        else if first < 0xf0u8 { 3usize } else { 4usize }
        if length != width {
            diagnostics.report(Phase.Lex, span, "character literal must contain exactly one scalar")
            return none
        }
        if byte && width != 1 {
            diagnostics.report(Phase.Lex, span, "byte literal must contain exactly one ASCII byte")
            return none
        }
        value = if width == 1 { first as u32 } else { (first & (0x7fu8 >> width)) as u32 }
        var index = 1usize
        while index < width {
            value = (value << 6u32) | (literal[start + index] & 0x3fu8) as u32
            index += 1
        }
    }
    if value > (if byte { 255u32 } else { 0x10ffffu32 }) || (!byte && value >= 0xd800u32 && value <= 0xdfffu32) {
        diagnostics.report(Phase.Lex, span, "literal is not a valid Unicode scalar")
        return none
    }
    present(value)
}

pub fn validate_text(read literal: [u8], span: Span, mut diagnostics: Diagnostics): Unit {
    let bytes = literal.len() != 0 && literal[0usize] == b'b'
    var start = if bytes { 1usize } else { 0usize }
    if start < literal.len() && literal[start] == b'r' {
        start += 1
        let fence_begin = start
        while start < literal.len() && literal[start] == b'#' { start += 1 }
        let fence = start - fence_begin
        if start >= literal.len() || literal[start] != b'"' || literal.len() < start + fence + 2 {
            diagnostics.report(Phase.Lex, span, "unterminated raw text literal")
            return
        }
        let end = literal.len() - fence - 1
        if literal[end] != b'"' {
            diagnostics.report(Phase.Lex, span, "unterminated raw text literal")
            return
        }
        var index = end + 1
        while index < literal.len() {
            if literal[index] != b'#' { diagnostics.report(Phase.Lex, span, "unterminated raw text literal"); return }
            index += 1
        }
        index = start + 1
        while bytes && index < end {
            if literal[index] >= 128u8 { diagnostics.report(Phase.Lex, span, "byte text must contain only ASCII characters"); return }
            index += 1
        }
        return
    }
    if literal.len() < start + 2 || literal[start] != b'"' || literal[literal.len() - 1] != b'"' {
        diagnostics.report(Phase.Lex, span, "unterminated text literal")
        return
    }
    var index = start + 1
    let end = literal.len() - 1
    while index < end {
        let byte = literal[index]
        index += 1
        if byte != b'\\' {
            if bytes && byte >= 128u8 { diagnostics.report(Phase.Lex, span, "byte text must contain only ASCII characters"); return }
            continue
        }
        if index == end { diagnostics.report(Phase.Lex, span, "incomplete text escape"); return }
        let escape = literal[index]
        index += 1
        if escape == b'n' || escape == b'r' || escape == b't' || escape == b'0' || escape == b'\\' || escape == b'"' || escape == b'\'' { continue }
        if escape == b'x' {
            var value = 0u32
            var valid = end - index >= 2
            var digit = 0usize
            while valid && digit < 2 {
                match hex(literal[index + digit]) { present(part) => { value = value * 16u32 + part }, none => { valid = false } }
                digit += 1
            }
            if !valid || (!bytes && value > 127u32) {
                if bytes { diagnostics.report(Phase.Lex, span, "byte escape requires two hexadecimal digits") }
                else { diagnostics.report(Phase.Lex, span, "text byte escape requires two hexadecimal digits no greater than 7f") }
                return
            }
            index += 2
        } else if escape == b'u' && !bytes {
            if index == end || literal[index] != b'{' { diagnostics.report(Phase.Lex, span, "Unicode escape requires '\\u{hex}'"); return }
            index += 1
            let begin = index
            var close = index
            while close < end && literal[close] != b'}' { close += 1 }
            if close == end { diagnostics.report(Phase.Lex, span, "Unicode escape requires '\\u{hex}'"); return }
            var valid = close > begin && close - begin <= 6
            var value = 0u32
            while valid && index < close {
                match hex(literal[index]) { present(part) => { value = value * 16u32 + part }, none => { valid = false } }
                index += 1
            }
            if !valid || value > 0x10ffffu32 || (value >= 0xd800u32 && value <= 0xdfffu32) {
                diagnostics.report(Phase.Lex, span, "invalid Unicode scalar escape")
                return
            }
            index = close + 1
        } else { diagnostics.report(Phase.Lex, span, "invalid text escape"); return }
    }
}
