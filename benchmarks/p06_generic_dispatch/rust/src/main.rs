trait Step {
    fn apply(&self, value: i32) -> i32;
}

struct Affine { scale: i32, offset: i32 }
struct Xor { mask: i32 }
struct Fold { modulus: i32 }

impl Step for Affine { fn apply(&self, value: i32) -> i32 { (value * self.scale + self.offset) % 1000003 } }
impl Step for Xor { fn apply(&self, value: i32) -> i32 { (value ^ self.mask) % 1000003 } }
impl Step for Fold { fn apply(&self, value: i32) -> i32 { value % self.modulus + value / 3 } }

fn seed() -> i32 { 12345 } // bench-edit-point

fn drive<S: Step>(step: &S, rounds: i32, start: i32) -> i32 {
    let mut value = start;
    let mut index = 0;
    while index < rounds {
        value = step.apply(value);
        index += 1;
    }
    value
}

fn main() {
    let a = drive(&Affine { scale: 7, offset: 13 }, 30000000, seed());
    let b = drive(&Xor { mask: 0x5a5a5 }, 30000000, a);
    let c = drive(&Fold { modulus: 977 }, 30000000, b);
    std::process::exit(c % 128);
}
