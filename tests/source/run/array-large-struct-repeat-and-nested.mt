
copy type Pt { x: i32; y: u8 }
fn main(): i32 {
    var pts = [Pt(7, 8); 100_000]
    pts[99_999].x = 1
    if pts[5].x != 7 || pts[99_999].x != 1 || pts[99_999].y != 8 { return 1 }
    var grid = [[1i32; 1000]; 500]
    grid[499][999] = 5
    var s = 0
    for row in read grid { for v in read row { s += v } }
    if s != 500 * 1000 + 4 { return 2 }
    var k = 0
    var pattern = [0x5Au8; 500_000]
    pattern[1] = 1
    if pattern[0] != 0x5A || pattern[499_999] != 0x5A || pattern[1] != 1 { return 3 }
    0
}
