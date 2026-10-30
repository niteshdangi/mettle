
copy type Pair { first: i32; second: i32 }
fn sum((a,b): (i32,i32)) { a + b }
fn fields(Pair {first:a,second:b}: Pair) { a + b }
fn main() {
    let Pair { first, .. } = Pair(42,0)
    if first == 42 && sum((20,22)) == 42 && fields(Pair(20,22)) == 42 { 0 } else { 1 }
}
