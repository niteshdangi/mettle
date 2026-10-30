
const BASE: i32 = 5;
const LIMIT: i32 = BASE * 2 + 1;
const ALIAS: i32 = LIMIT;
const ENABLED: bool = true;
interface Width { const BITS: i32 = 8; }
type Narrow {}
impl Narrow implements Width { const BITS: i32 = 4; }
const NARROW_BITS: i32 = <Narrow implements Width>::BITS + 1;
pub module limits { pub const TOP: u8 = 200; }
fn classify(value: i32): i32 {
    match value { BASE => 1, ALIAS => 2, 0..=3 => 3, _ => 4 }
}
fn main(): i32 {
    let cells: [i32; 11] = [BASE; LIMIT]
    if classify(5) == 1 && classify(11) == 2 && classify(2) == 3 && classify(7) == 4 &&
       cells[10] == BASE && limits::TOP == 200 && NARROW_BITS == 5 && ENABLED { 0 } else { 1 }
}
