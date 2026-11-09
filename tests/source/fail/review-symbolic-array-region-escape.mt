// expect-error: region 5:5 declared relationship

fn put<region a,region b,const N:i32>(
    mut dst:[read i32 from b;N],take src:[read i32 from a;N]):Unit {
    dst = src
}
fn main() { 0 }
