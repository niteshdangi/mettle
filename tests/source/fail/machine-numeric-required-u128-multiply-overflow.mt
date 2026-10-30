// profiles: debug release
// expect-error: type 4:23 required integer constant overflows

fn value<const N:u128=(1u128<<64)*(1u128<<64)>():u128{N}
fn main(){0}
