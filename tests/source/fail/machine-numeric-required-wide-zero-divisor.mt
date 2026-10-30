// profiles: debug release
// expect-error: type 4:23 division by zero

fn value<const N:u128=1u128/0>():u128{N}
fn main(){0}
