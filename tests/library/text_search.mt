import core.text

fn main(): i32 {
    var hay = [97u8; 7]
    var pattern = [97u8; 5]
    var n = 0usize
    while n <= hay.len() {
        var bits = 0usize
        while bits < (1usize << n) {
            var i = 0usize
            while i < n {
                hay[i] = 97u8 + ((bits >> i) & 1usize) as u8
                i += 1usize
            }
            let input = match text.from_utf8(read hay[0usize..n]) {
                success(value) => value,
                failure(_) => { return 1 }
            }
            var m = 0usize
            while m <= pattern.len() {
                var needle_bits = 0usize
                while needle_bits < (1usize << m) {
                    i = 0usize
                    while i < m {
                        pattern[i] = 97u8 + ((needle_bits >> i) & 1usize) as u8
                        i += 1usize
                    }
                    let needle = match text.from_utf8(read pattern[0usize..m]) {
                        success(value) => value,
                        failure(_) => { return 2 }
                    }
                    var first: usize? = none
                    var last: usize? = none
                    var at = 0usize
                    while at + m <= n {
                        i = 0usize
                        while i < m && hay[at + i] == pattern[i] { i += 1usize }
                        if i == m {
                            if first.is_none() { first = present(at) }
                            last = present(at)
                        }
                        at += 1usize
                    }
                    if input.find(read *needle) != first ||
                        input.rfind(read *needle) != last {
                        return 3
                    }
                    needle_bits += 1usize
                }
                m += 1usize
            }
            bits += 1usize
        }
        n += 1usize
    }
    if "\u{e9}\u{e9}x\u{e9}".find("\u{e9}x") != present(2usize) ||
        "\u{e9}\u{e9}x\u{e9}".rfind("\u{e9}") != present(5usize) ||
        "\u{e9}\u{e9}x\u{e9}".rfind("") != present(7usize) { return 4 }
    var visited = 0u32
    if "1234".find(fn(value: char): bool {
        visited = visited * 10u32 + value as u32 - 48u32
        value == '3'
    }) != present(2usize) || visited != 123u32 { return 5 }
    visited = 0u32
    if "1234".rfind(fn(value: char): bool {
        visited = visited * 10u32 + value as u32 - 48u32
        value == '2'
    }) != present(1usize) || visited != 432u32 { return 6 }
    0
}
