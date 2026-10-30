// profiles: debug release
// expect-error: type 5:22 const argument does not match its declared type

fn value<const N:u64>():u64{N}
fn main(){let result=value<42u128>();0}
