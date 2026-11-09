import core.iter.Iterator
import core.cmp.{Ord, Ordering}
import core.slice
import core.text
import core.char
import alloc.string
import alloc.vec
import alloc.vec_deque

fn main(): i32 {
    let text = "  a\u{e9} \t b \u{2003}c  "
    var words = text.split_whitespace()
    match words.next() {
        present(word) => { if word != "a\u{e9}" { return 1 } },
        none => { return 1 }
    }
    match words.next_back() {
        present(word) => { if word != "c" { return 3 } },
        none => { return 3 }
    }
    match words.next() {
        present(word) => { if word != "b" { return 2 } },
        none => { return 2 }
    }
    match words.next_back() { present(_) => { return 4 }, none => {} }
    match words.next() { present(_) => { return 4 }, none => {} }
    match words.next() { present(_) => { return 4 }, none => {} }

    var ascii_words = " \tleft\u{2003}right \n".split_ascii_whitespace()
    match ascii_words.next() {
        present(word) => { if word != "left\u{2003}right" { return 5 } },
        none => { return 5 }
    }
    match ascii_words.next_back() { present(_) => { return 6 }, none => {} }
    match ascii_words.next() { present(_) => { return 6 }, none => {} }
    var whitespace_only = "\u{2003} \t".split_whitespace()
    match whitespace_only.next_back() { present(_) => { return 141 }, none => {} }
    match whitespace_only.next() { present(_) => { return 141 }, none => {} }

    var limited = "a,b,c".splitn(2usize, ",")
    match limited.next() {
        present(part) => { if part != "a" { return 7 } },
        none => { return 7 }
    }
    match limited.next() {
        present(part) => { if part != "b,c" { return 8 } },
        none => { return 8 }
    }
    match limited.next() { present(_) => { return 9 }, none => {} }
    var zero_limit = "a,b".splitn(0usize, ",")
    match zero_limit.next() { present(_) => { return 35 }, none => {} }
    var no_match = "abc".splitn(3usize, ",")
    match no_match.next() { present(part) => { if part != "abc" { return 36 } }, none => { return 36 } }
    match no_match.next() { present(_) => { return 37 }, none => {} }

    var reversed = "a,b,c".rsplitn(2usize, ",")
    match reversed.next() {
        present(part) => { if part != "c" { return 10 } },
        none => { return 10 }
    }
    match reversed.next() {
        present(part) => { if part != "a,b" { return 11 } },
        none => { return 11 }
    }

    var terminated = "a,b,".split_terminator(",")
    match terminated.next() { present(part) => { if part != "a" { return 12 } }, none => { return 12 } }
    match terminated.next() { present(part) => { if part != "b" { return 13 } }, none => { return 13 } }
    match terminated.next() { present(_) => { return 14 }, none => {} }
    var reverse_terminated = "a,b,".rsplit_terminator(",")
    match reverse_terminated.next() { present(part) => { if part != "b" { return 130 } }, none => { return 130 } }
    match reverse_terminated.next() { present(part) => { if part != "a" { return 131 } }, none => { return 131 } }
    match reverse_terminated.next() { present(_) => { return 132 }, none => {} }

    var inclusive = "a,b,".split_inclusive(",")
    match inclusive.next() { present(part) => { if part != "a," { return 15 } }, none => { return 15 } }
    match inclusive.next() { present(part) => { if part != "b," { return 16 } }, none => { return 16 } }
    match inclusive.next() { present(_) => { return 17 }, none => {} }

    let unicode = "a\u{e9}b"
    if unicode.floor_char_boundary(2usize) != 1usize ||
        unicode.ceil_char_boundary(2usize) != 3usize ||
        unicode.floor_char_boundary(99usize) != unicode.len() ||
        unicode.ceil_char_boundary(99usize) != unicode.len() { return 18 }
    var chars = unicode.chars()
    if chars.as_str() != unicode { return 29 }
    match chars.next() { present(c) => { if c != 'a' { return 30 } }, none => { return 30 } }
    if chars.as_str() != "\u{e9}b" { return 31 }
    var indices = unicode.char_indices()
    if indices.offset() != 0usize || indices.as_str() != unicode { return 32 }
    match indices.next() {
        present(item) => { if item.0 != 0usize || item.1 != 'a' { return 33 } },
        none => { return 33 }
    }
    if indices.offset() != 1usize || indices.as_str() != "\u{e9}b" { return 34 }
    match unicode.strip_prefix("a") {
        present(rest) => { if rest != "\u{e9}b" { return 19 } },
        none => { return 19 }
    }
    match unicode.strip_suffix("b") {
        present(rest) => { if rest != "a\u{e9}" { return 20 } },
        none => { return 20 }
    }
    if unicode.trim_start_matches("a") != "\u{e9}b" ||
        unicode.trim_end_matches("b") != "a\u{e9}" ||
        "xybodyxy".trim_matches("xy") != "body" { return 40 }
    if !"\u{e9}ABC".eq_ignore_ascii_case("\u{e9}abc") { return 21 }
    var matches = "a\u{e9}\u{e9}b".matches("\u{e9}")
    match matches.next() { present(item) => { if item != "\u{e9}" { return 41 } }, none => { return 41 } }
    match matches.next_back() { present(item) => { if item != "\u{e9}" { return 42 } }, none => { return 42 } }
    match matches.next() { present(_) => { return 43 }, none => {} }
    var reverse_matches = "a\u{e9}\u{e9}b".rmatches("\u{e9}")
    match reverse_matches.next() { present(item) => { if item != "\u{e9}" { return 124 } }, none => { return 124 } }
    var match_indices = "a\u{e9}\u{e9}b".match_indices("\u{e9}")
    match match_indices.next() {
        present(item) => { if item.0 != 1usize || item.1 != "\u{e9}" { return 44 } },
        none => { return 44 }
    }
    match match_indices.next_back() {
        present(item) => { if item.0 != 3usize || item.1 != "\u{e9}" { return 45 } },
        none => { return 45 }
    }
    var reverse_indices = "a\u{e9}\u{e9}b".rmatch_indices("\u{e9}")
    match reverse_indices.next() {
        present(item) => { if item.0 != 3usize { return 46 } },
        none => { return 46 }
    }
    var empty_matches = "a\u{e9}".match_indices("")
    match empty_matches.next() { present(item) => { if item.0 != 0usize { return 47 } }, none => { return 47 } }
    match empty_matches.next() { present(item) => { if item.0 != 1usize { return 48 } }, none => { return 48 } }
    match empty_matches.next() { present(item) => { if item.0 != 3usize { return 49 } }, none => { return 49 } }
    match empty_matches.next() { present(_) => { return 50 }, none => {} }

    let repeated = "é".repeat(3usize)
    if repeated.as_text() != "ééé" { return 22 }
    let lowered = "HÉLLO".to_ascii_lowercase()
    if lowered.as_text() != "hÉllo" { return 23 }
    let uppered = "hÉllo".to_ascii_uppercase()
    if uppered.as_text() != "HÉLLO" { return 24 }
    var mutable_ascii = "hÉllo".repeat(1usize)
    mutable_ascii.make_ascii_uppercase()
    if mutable_ascii.as_text() != "HÉLLO" { return 38 }
    mutable_ascii.make_ascii_lowercase()
    if mutable_ascii.as_text() != "hÉllo" { return 39 }

    if !'A'.is_ascii_alphabetic() || !'9'.is_ascii_hexdigit() ||
        !'!'.is_ascii_punctuation() || !'\n'.is_ascii_control() ||
        'é'.is_ascii() { return 25 }
    if !'z'.is_ascii_alphanumeric() || !'7'.is_ascii_digit() ||
        !'~'.is_ascii_graphic() || !'a'.is_ascii_lowercase() ||
        !'Z'.is_ascii_uppercase() || !' '.is_ascii() || !' '.is_whitespace() { return 139 }
    if !' '.is_ascii_whitespace() || !'\t'.is_ascii_whitespace() ||
        !'\r'.is_ascii_whitespace() || '\u{2003}'.is_ascii_whitespace() {
        return 150
    }
    if !'\u{7f}'.is_control() { return 140 }
    match 'Z'.to_digit(36u32) {
        present(value) => { if value != 35u32 { return 26 } },
        none => { return 26 }
    }
    match core.char.from_digit(35u32, 36u32) {
        present(value) => { if value != 'z' { return 27 } },
        none => { return 27 }
    }
    if 'é'.len_utf8() != 2usize || 'é'.len_utf16() != 1usize ||
        '🦀'.len_utf8() != 4usize || '🦀'.len_utf16() != 2usize { return 28 }
    if !'7'.is_digit(8u32) || '9'.is_digit(8u32) { return 125 }
    var char_utf16_buffer = [0u16; 3]
    {
        let encoded_char = '🦀'.encode_utf16(mut char_utf16_buffer)
        if encoded_char.len() != 2usize || encoded_char[0usize] != 0xd83eu16 ||
            encoded_char[1usize] != 0xdd80u16 { return 51 }
        encoded_char[0usize] = 0xd83du16
    }
    if char_utf16_buffer[0usize] != 0xd83du16 ||
        char_utf16_buffer[2usize] != 0u16 { return 52 }
    var bmp_utf16_buffer = [0xffffu16; 2]
    {
        let encoded_bmp = 'A'.encode_utf16(mut bmp_utf16_buffer)
        if encoded_bmp.len() != 1usize || encoded_bmp[0usize] != 0x41u16 {
            return 153
        }
    }
    if bmp_utf16_buffer[1usize] != 0xffffu16 { return 154 }
    if '🦀'.to_ascii_lowercase() != '🦀' || 'z'.to_ascii_uppercase() != 'Z' ||
        !'A'.eq_ignore_ascii_case('a') { return 53 }
    var mutable_char = 'A'
    mutable_char.make_ascii_lowercase()
    if mutable_char != 'a' { return 54 }
    mutable_char.make_ascii_uppercase()
    if mutable_char != 'A' { return 126 }
    var debug_escape = '\n'.escape_debug()
    match debug_escape.next() { present(c) => { if c != '\\' { return 55 } }, none => { return 55 } }
    match debug_escape.next() { present(c) => { if c != 'n' { return 56 } }, none => { return 56 } }
    var unicode_escape = 'é'.escape_unicode()
    var escaped = string.new()
    while true {
        match unicode_escape.next() { present(c) => { escaped.push(c) }, none => { break } }
    }
    if escaped.as_text() != "\\u{e9}" { return 57 }
    var text_escape = "a\n".escape_default()
    var escaped_text = string.new()
    while true {
        match text_escape.next() { present(c) => { escaped_text.push(c) }, none => { break } }
    }
    if escaped_text.as_text() != "a\\n" { return 58 }
    var text_debug_escape = "\n".escape_debug()
    match text_debug_escape.next() { present(c) => { if c != '\\' { return 133 } }, none => { return 133 } }
    match text_debug_escape.next() { present(c) => { if c != 'n' { return 134 } }, none => { return 134 } }
    var text_unicode_escape = "é".escape_unicode()
    var text_unicode_escaped = string.new()
    while true {
        match text_unicode_escape.next() { present(c) => { text_unicode_escaped.push(c) }, none => { break } }
    }
    if text_unicode_escaped.as_text() != "\\u{e9}" { return 135 }
    var default_escape = '\u{1b}'.escape_default()
    match default_escape.next() { present(c) => { if c != '\\' { return 127 } }, none => { return 127 } }
    var utf16 = "a🦀".encode_utf16()
    match utf16.next() { present(unit) => { if unit != 0x61u16 { return 59 } }, none => { return 59 } }
    match utf16.next_back() { present(unit) => { if unit != 0xdd80u16 { return 60 } }, none => { return 60 } }
    match utf16.next_back() { present(unit) => { if unit != 0xd83eu16 { return 61 } }, none => { return 61 } }
    match utf16.next() { present(_) => { return 61 }, none => {} }
    var utf16_pair = "🦀".encode_utf16()
    match utf16_pair.next() { present(unit) => { if unit != 0xd83eu16 { return 142 } }, none => { return 142 } }
    match utf16_pair.next_back() { present(unit) => { if unit != 0xdd80u16 { return 143 } }, none => { return 143 } }
    match utf16_pair.next_back() { present(_) => { return 144 }, none => {} }
    match utf16_pair.next() { present(_) => { return 144 }, none => {} }
    var utf16_edges = "🦀🦀".encode_utf16()
    match utf16_edges.next() { present(unit) => { if unit != 0xd83eu16 { return 145 } }, none => { return 145 } }
    match utf16_edges.next_back() { present(unit) => { if unit != 0xdd80u16 { return 146 } }, none => { return 146 } }
    match utf16_edges.next() { present(unit) => { if unit != 0xdd80u16 { return 147 } }, none => { return 147 } }
    match utf16_edges.next_back() { present(unit) => { if unit != 0xd83eu16 { return 148 } }, none => { return 148 } }
    match utf16_edges.next() { present(_) => { return 149 }, none => {} }
    match utf16_edges.next_back() { present(_) => { return 149 }, none => {} }
    let words_source = string.from_text("alpha beta")
    var string_words = words_source.split_whitespace()
    match string_words.next() { present(word) => { if word != "alpha" { return 128 } }, none => { return 128 } }
    match string_words.next() { present(word) => { if word != "beta" { return 129 } }, none => { return 129 } }
    let units = [0x61u16, 0xd83eu16, 0xdd80u16]
    match capture string.from_utf16(units) {
        success(from_units) => { if from_units.as_text() != "a🦀" { return 62 } },
        failure(_) => { return 62 }
    }
    match capture string.from_utf16([0xd800u16]) {
        success(_) => { return 63 },
        failure(error) => { if error.index != 0usize { return 63 } }
    }
    let lossy_units = string.from_utf16_lossy([0xd800u16, 0x61u16, 0xdc00u16])
    if lossy_units.as_text() != "�a�" { return 64 }
    let lossy_bytes = string.from_utf8_lossy([0x61u8, 0xffu8, 0x62u8])
    if lossy_bytes.as_text() != "a�b" { return 65 }
    var changed = string.from_text("a\u{e9}bc")
    changed.replace_range(1usize, 3usize, "🦀")
    if changed.as_text() != "a🦀bc" { return 66 }
    changed.extend_from_within(0usize, 1usize)
    if changed.as_text() != "a🦀bca" { return 67 }
    var suffix = changed.split_off(6usize)
    if changed.as_text() != "a🦀b" || suffix.as_text() != "ca" { return 68 }
    suffix.shrink_to(1usize)
    if suffix.as_text() != "ca" { return 69 }
    var drained = string.from_text("a🦀b")
    {
        var drain = drained.drain(1usize, 5usize)
        if drain.as_str() != "🦀" { return 70 }
        match drain.next() { present(c) => { if c != '🦀' { return 71 } }, none => { return 71 } }
        if drain.as_str() != "" { return 72 }
    }
    if drained.as_text() != "ab" { return 73 }

    let slice_values = [1, 2, 3, 4, 5]
    var chunks = slice_values.chunks_exact(2usize)
    match chunks.next() { present(part) => { if part[0] != 1 || part[1] != 2 { return 74 } }, none => { return 74 } }
    match chunks.next_back() { present(part) => { if part[0] != 3 || part[1] != 4 { return 75 } }, none => { return 75 } }
    match chunks.next() { present(_) => { return 76 }, none => {} }
    var mutable_chunks_source = [1, 2, 3, 4, 5]
    {
        var mutable_chunks = mutable_chunks_source.chunks_exact_mut(2usize)
        match take mutable_chunks.next() {
            present(part) => { part[0] = 9 },
            none => { return 107 }
        }
    }
    if mutable_chunks_source[0] != 9 { return 108 }
    var reverse_chunks = slice_values.rchunks(2usize)
    match reverse_chunks.next() { present(part) => { if part.len() != 2usize || part[0] != 4 { return 77 } }, none => { return 77 } }
    match reverse_chunks.next_back() { present(part) => { if part[0] != 1 { return 78 } }, none => { return 78 } }
    var exact_reverse_chunks = slice_values.rchunks_exact(2usize)
    match exact_reverse_chunks.next() { present(part) => { if part[0] != 4 { return 79 } }, none => { return 79 } }
    match exact_reverse_chunks.next_back() { present(part) => { if part[0] != 2 { return 80 } }, none => { return 80 } }
    var reverse_mut_source = [1, 2, 3, 4, 5]
    {
        var reverse_mut = reverse_mut_source.rchunks_mut(2usize)
        match take reverse_mut.next() { present(part) => { part[0] = 9 }, none => { return 109 } }
    }
    if reverse_mut_source[3] != 9 { return 110 }
    var reverse_exact_mut_source = [1, 2, 3, 4, 5]
    {
        var reverse_exact_mut = reverse_exact_mut_source.rchunks_exact_mut(2usize)
        match take reverse_exact_mut.next() { present(part) => { part[1] = 9 }, none => { return 111 } }
    }
    if reverse_exact_mut_source[4] != 9 { return 112 }
    var even_split = slice_values.split(fn(read value: i32): bool { value == 3 })
    match even_split.next() { present(part) => { if part.len() != 2usize { return 81 } }, none => { return 81 } }
    match even_split.next() { present(part) => { if part[0] != 4 { return 82 } }, none => { return 82 } }
    var inclusive_split = slice_values.split_inclusive(fn(read value: i32): bool { value == 3 })
    match inclusive_split.next() { present(part) => { if part.len() != 3usize { return 83 } }, none => { return 83 } }
    var reverse_split = slice_values.rsplitn(2usize, fn(read value: i32): bool { value == 3 })
    match reverse_split.next() { present(part) => { if part[0] != 4 { return 84 } }, none => { return 84 } }
    var limited_split = slice_values.splitn(2usize, fn(read value: i32): bool { value == 3 })
    match limited_split.next() { present(part) => { if part.len() != 2usize { return 113 } }, none => { return 113 } }
    match limited_split.next() { present(part) => { if part.len() != 2usize { return 114 } }, none => { return 114 } }
    var mutable_split_source = [1, 0, 2, 3]
    {
        var mutable_split = mutable_split_source.split_mut(fn(read value: i32): bool { value == 0 })
        match take mutable_split.next() { present(part) => { part[0] = 8 }, none => { return 115 } }
    }
    if mutable_split_source[0] != 8 { return 116 }
    var mutable_inclusive_source = [1, 0, 2]
    {
        var mutable_inclusive = mutable_inclusive_source.split_inclusive_mut(
            fn(read value: i32): bool { value == 0 }
        )
        match take mutable_inclusive.next() {
            present(part) => { if part.len() != 2usize { return 117 }; part[0] = 9 },
            none => { return 117 }
        }
    }
    if mutable_inclusive_source[0] != 9 { return 118 }
    let grouped_values = [1, 1, 2, 2, 3]
    var groups = grouped_values.chunk_by(
        fn(read left: i32, read right: i32): bool { left == right }
    )
    match groups.next() { present(part) => { if part.len() != 2usize { return 85 } }, none => { return 85 } }
    match groups.next_back() { present(part) => { if part[0] != 3 { return 136 } }, none => { return 136 } }
    var mutable_groups_source = [1, 1, 2, 2]
    {
        var mutable_groups = mutable_groups_source.chunk_by_mut(
            fn(read left: i32, read right: i32): bool { left == right }
        )
        match take mutable_groups.next() {
            present(part) => { if part.len() != 2usize { return 119 }; part[0] = 7 },
            none => { return 119 }
        }
        match take mutable_groups.next_back() {
            present(part) => { if part.len() != 2usize { return 137 }; part[0] = 8 },
            none => { return 137 }
        }
    }
    if mutable_groups_source[0] != 7 || mutable_groups_source[2] != 8 { return 120 }
    var selected = [8, 2, 5, 1, 9]
    let median_parts = selected.select_nth_unstable(2usize)
    if *median_parts.1 != 5 || median_parts.0.len() != 2usize ||
        median_parts.2.len() != 2usize { return 86 }
    var duplicate_selection = [4, 4, 4, 4]
    let duplicate_parts = duplicate_selection.select_nth_unstable(2usize)
    if *duplicate_parts.1 != 4 || duplicate_parts.0.len() != 2usize { return 138 }
    var selected_by_key = [14, 22, 31, 43]
    let key_parts = selected_by_key.select_nth_unstable_by_key(
        1usize,
        fn(read value: i32): i32 { value % 10 }
    )
    if *key_parts.1 % 10 != 2 { return 87 }
    var selected_by_compare = [4, 1, 3, 2]
    let compare_parts = selected_by_compare.select_nth_unstable_by(
        1usize,
        fn(read left: i32, read right: i32): Ordering { left.cmp(right) }
    )
    if *compare_parts.1 != 2 { return 121 }
    var sorted_by_cached_key = [21, 12, 31, 22]
    sorted_by_cached_key.sort_by_cached_key(fn(read value: i32): i32 { value % 10 })
    if sorted_by_cached_key[0] != 21 || sorted_by_cached_key[1] != 31 ||
        sorted_by_cached_key[2] != 12 || sorted_by_cached_key[3] != 22 { return 88 }
    let array = [4, 5, 6]
    let array_ref = array.each_ref()
    if *array_ref[1] != 5 { return 89 }
    var array_mut = [4, 5, 6]
    var array_view = array_mut.each_mut()
    *array_view[1] = 9
    if array_mut[1] != 9 { return 90 }

    var list = vec.new<i32>()
    list.push(1)
    list.push(1)
    list.push(2)
    list.dedup_by(fn(mut current: i32, mut previous: i32): bool { current == previous })
    if list.len() != 2usize { return 91 }
    list.dedup_by_key(fn(mut value: i32): i32 { value })
    list.retain_mut(fn(mut value: i32): bool { value += 1; true })
    if list[0] != 2 || list[1] != 3 { return 92 }
    match list.pop_if(fn(mut value: i32): bool { value == 3 }) {
        present(value) => { if value != 3 { return 93 } },
        none => { return 93 }
    }
    var keyed_list = vec.new<i32>()
    keyed_list.push(11)
    keyed_list.push(12)
    keyed_list.push(23)
    keyed_list.dedup_by_key(fn(mut value: i32): i32 { value / 10 })
    if keyed_list.len() != 2usize || keyed_list[1] != 23 { return 106 }
    var extracted_source = vec.new<i32>()
    extracted_source.push(1)
    extracted_source.push(2)
    extracted_source.push(3)
    {
        let extracted_end = extracted_source.len()
        var extracted = extracted_source.extract_if(
            0usize..extracted_end,
            fn(mut value: i32): bool { value % 2 == 1 }
        )
        match extracted.next() { present(value) => { if value != 1 { return 94 } }, none => { return 94 } }
    }
    if extracted_source.len() != 2usize { return 95 }
        var spare_test = vec.with_capacity<i32>(3usize)
        spare_test.push(1)
        {
            var spare = spare_test.spare_capacity_mut()
            if spare.len() != 2usize { return 122 }
            spare[0] = core.mem.MaybeUninit.new(2)
        }
        unsafe { spare_test.set_len(2usize) }
        spare_test.shrink_to(1usize)
        if spare_test[0] != 1 || spare_test[1] != 2 { return 123 }
        var splice_source = vec.new<i32>()
        splice_source.push(1)
        splice_source.push(2)
        splice_source.push(3)
        var replacement = vec.new<i32>()
        replacement.push(8)
        replacement.push(9)
        {
            var splice = splice_source.splice(1usize..2usize, replacement)
        match splice.next() { present(value) => { if value != 2 { return 96 } }, none => { return 96 } }
    }
    if splice_source.len() != 4usize || splice_source[1] != 8 ||
        splice_source[2] != 9 { return 97 }
    let boxed = splice_source.into_boxed_slice()
    if boxed.get()[3] != 3 { return 98 }
    var leak_source = vec.new<i32>()
    leak_source.push(7)
    let leaked = leak_source.leak()
    if leaked[0] != 7 { return 99 }

    var deque = vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(3)
    {
        var range = deque.range_mut(1usize, 3usize)
        match take range.next() { present(value) => { *value += 2 }, none => { return 100 } }
    }
    deque.retain_mut(fn(mut value: i32): bool { value != 3 })
    if deque.len() != 2usize || deque[1] != 4 { return 101 }
    match deque.pop_front_if(fn(mut value: i32): bool { value == 1 }) {
        present(value) => { if value != 1 { return 102 } },
        none => { return 102 }
    }
    match deque.pop_back_if(fn(mut value: i32): bool { value == 4 }) {
        present(value) => { if value != 4 { return 103 } },
        none => { return 103 }
    }
    deque.push_back(5)
    deque.push_back(6)
    let contiguous = deque.make_contiguous()
    if contiguous.len() != 2usize || contiguous[0] != 5 { return 104 }
    deque.shrink_to(1usize)
    if deque.len() != 2usize { return 105 }
    0
}
