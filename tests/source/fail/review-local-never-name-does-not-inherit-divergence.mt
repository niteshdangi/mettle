// expect-error: type 4:31 expected i32
fn stop():Never { loop {} }
fn done():Unit {}
fn invoke(stop:fn():Unit):i32 { stop() }
fn main(){ invoke(done) }
