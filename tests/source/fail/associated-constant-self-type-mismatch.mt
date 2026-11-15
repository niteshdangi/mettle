// expect-error: type 5:1 associated constant type does not match its declaration
interface StartingValue {
    const START: Self;
}
extend u8 implements StartingValue {
    const START: u16 = 1u16
}
fn main(): i32 { 0 }
