interface Step { fn apply(value: i32): i32; }

type Affine { scale: i32; offset: i32 }
type Xor { mask: i32 }
type Fold { modulus: i32 }

impl Affine implements Step { fn apply(value: i32): i32 { (value * self.scale + self.offset) % 1000003 } }
impl Xor implements Step { fn apply(value: i32): i32 { (value ^ self.mask) % 1000003 } }
impl Fold implements Step { fn apply(value: i32): i32 { value % self.modulus + value / 3 } }

fn seed(): i32 { 12345 } // bench-edit-point

fn drive<S: Step>(step: read S, rounds: i32, start: i32): i32 {
    var value = start
    var index = 0
    while index < rounds {
        value = step.apply(value)
        index += 1
    }
    value
}

fn main(): i32 {
    let a = drive(Affine(scale: 7, offset: 13), 30000000, seed())
    let b = drive(Xor(mask: 0x5a5a5), 30000000, a)
    let c = drive(Fold(modulus: 977), 30000000, b)
    (c % 128) as i32
}
