
fn put<region a,region b,const N:i32>(
    dst:mut [read i32 from b;N],src:take [read i32 from a;N]):Unit where region a:b {
    dst = src
}
fn main() { 0 }
