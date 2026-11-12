// profiles: debug release

import core.cell.OnceCell

type Payload { value: i32 }

const EMPTY: i32 = match take OnceCell<i32>.new().into_inner() {
    present(value) => value,
    none => 42
}

const EMPTY_OWNED: bool = match take OnceCell<Payload>.new().into_inner() {
    present(value) => false,
    none => true
}

const fn project_array(): usize {
    var values = [1i32, 2]
    let cell = core.cell.Cell<[i32; 2]>.from_mut(mut values)
    let cells = cell.as_array_of_cells()
    if unsafe { *cells[1].as_ptr() } != 2 { return 0usize }
    cells.len()
}

const fn project_slice(): usize {
    var values = [3i32, 4]
    let view: mut [i32] = mut values
    let cell = core.cell.Cell<[i32]>.from_mut(mut *view)
    let cells = cell.as_slice_of_cells()
    if unsafe { *cells[1].as_ptr() } != 4 { return 0usize }
    cells.len()
}

const fn project_units(): usize {
    var values = [(); 3]
    let view: mut [Unit] = mut values
    let cell = core.cell.Cell<[Unit]>.from_mut(mut *view)
    cell.as_slice_of_cells().len()
}

const fn project_empty(): usize {
    var values: [i32; 0] = []
    let cell = core.cell.Cell<[i32; 0]>.from_mut(mut values)
    cell.as_array_of_cells().len()
}

const ARRAY: usize = project_array()
const SLICE: usize = project_slice()
const UNITS: usize = project_units()
const EMPTY_ARRAY: usize = project_empty()

fn main(): i32 {
    if EMPTY != 42 || ARRAY != 2usize || SLICE != 2usize { return 1 }
    if UNITS != 3usize || EMPTY_ARRAY != 0usize { return 2 }
    if !EMPTY_OWNED { return 3 }
    0
}
