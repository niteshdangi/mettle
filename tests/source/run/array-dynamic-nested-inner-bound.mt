// expect-exit: trap
fn main(): i32 { var grid=[[0u8;300];300]; let row=299; let column=300; grid[row][column]=1u8; 0 }
