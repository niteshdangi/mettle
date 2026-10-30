
copy type Cell { left: i32; right: u8 }
fn main(): i32 {
    var grid = [[0u8; 300]; 300]
    var r = 0
    while r < 300 {
        var c = 0
        while c < 300 { grid[r][c] = (r + c) as u8; c = c + 1 }
        r = r + 1
    }
    var cells = [Cell(1, 2u8); 4]
    var k = 3
    cells[k].left = 40
    cells[k - 3].right = 7u8
    if grid[299][299] == 86u8 && grid[10][20] == 30u8 && cells[3].left + cells[0].left == 41 &&
       cells[0].right == 7u8 && cells[3].right == 2u8 { 0 } else { 1 }
}
