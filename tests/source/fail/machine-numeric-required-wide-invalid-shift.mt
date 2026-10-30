// profiles: debug release
// expect-error: type 4:23 invalid shift

fn value<const N:u128=1u128<<128>():u128{N}
fn main(){0}
