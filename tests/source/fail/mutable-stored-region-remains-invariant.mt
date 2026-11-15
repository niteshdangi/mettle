// expect-error: region 6:36 invariant payload
// expect-error: region 14:33 invariant payload
type Ref<region r> { value: mut (read i32 from r) from r }
fn bad<region a, region b>(
    take value: Ref<region a>
): Ref<region b> where region a: b { take value }
fn main() { 0 }

fn inspect<region r, T>(mut values: mut [T] from r): usize { values.len() }

fn bad_slice<region r, region s>(
    mut values: mut [Ref<region r>] from s
): usize {
    inspect<Ref<region static>>(mut values)
}
