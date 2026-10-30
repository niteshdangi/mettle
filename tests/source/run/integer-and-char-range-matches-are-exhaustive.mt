
fn bucket(x: u8): i32 { match x { 0..=100 => 1, 101..200 => 2, 200..=255 => 3 } }
fn sign(x: i8): i32 { match x { -128..0 => -1, 0 => 0, 1..=127 => 1 } }
fn plane(c: char): i32 { match c { '\u{0}'..='\u{d7ff}' => 1, '\u{e000}'..='\u{10ffff}' => 2 } }
fn main(): i32 {
    if bucket(0u8) != 1 || bucket(150u8) != 2 || bucket(255u8) != 3 { return 1 }
    if sign(-128i8) != -1 || sign(0i8) != 0 || sign(127i8) != 1 { return 2 }
    if plane('a') != 1 || plane('\u{10ffff}') != 2 { return 3 }
    0
}
