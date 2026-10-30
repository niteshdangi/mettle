// profiles: debug release
// expect-error: type 4:21 required integer constant overflows

fn value<const N:u8=255u8+1>():u8{N}
fn main(){0}
