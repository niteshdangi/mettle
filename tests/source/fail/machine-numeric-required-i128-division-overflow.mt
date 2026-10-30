// profiles: debug release
// expect-error: type 4:23 required integer constant overflows

fn value<const N:i128=-170141183460469231731687303715884105728i128 / -1>():i128{N}
fn main(){0}
