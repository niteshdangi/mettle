import core.convert.From
import core.default.Default

fn main(): i32 {
    var default_cell = core.cell.UnsafeCell<i32>.(Default).default()
    var from_cell = core.cell.UnsafeCell<i32>.(From<i32>).from(7i32)
    if *default_cell.get_mut() != 0i32 { return 1 }
    if *from_cell.get_mut() != 7i32 { return 2 }
    0
}
