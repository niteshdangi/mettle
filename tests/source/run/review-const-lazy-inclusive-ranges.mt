const fn ranges(): i32 {
    var count = 0
    for _ in 255u8..=255u8 { count += 1 }
    for _ in 127i8..=127i8 { count += 1; continue }
    for _ in 340282366920938463463374607431768211455u128..=340282366920938463463374607431768211455u128 {
        count += 1
    }
    for _ in 0u128..=340282366920938463463374607431768211455u128 {
        count += 1
        break
    }
    for _ in 3u8..=2u8 { count += 100 }
    for _ in 'a'..='b' { count += 1 }
    for _ in '\u{d7ff}'..='\u{e000}' { count += 1 }
    for _ in '\u{d7ff}'..'\u{e000}' { count += 1 }
    for _ in '\u{10ffff}'..='\u{10ffff}' { count += 1 }
    count
}
const COUNT: i32 = ranges()
fn main(): i32 {
    if COUNT != 10 { return 1 }
    ranges() - 10
}
