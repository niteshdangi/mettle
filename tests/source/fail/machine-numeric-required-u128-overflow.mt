// profiles: debug release
// expect-error: type 4:23 required integer constant overflows

fn value<const N:u128=340282366920938463463374607431768211455u128+1>():u128{N}
fn main(){0}
