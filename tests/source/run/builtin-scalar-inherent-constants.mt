extend char {
    const BULLET: char = '\u{2022}'
}
extend u16 {
    const HALF: u16 = 32768u16
}
fn main(): i32 {
    if char.BULLET != '\u{2022}' { return 1 }
    if u16.HALF != 32768u16 { return 2 }
    0
}
