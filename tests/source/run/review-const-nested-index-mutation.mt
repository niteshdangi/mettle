const X: i32 = {
    var a = [[1i32, 2i32], [3i32, 4i32]]
    a[0usize][{ a = [[5i32, 6i32], [7i32, 8i32]]; 0usize }]
}
fn main(): i32 { X - 5 }
