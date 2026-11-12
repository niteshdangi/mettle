// profiles: debug release

import core.borrow.AsRef

type Owned {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += self.value } }
}

fn main(): i32 {
    let updated = core.cell.Cell.new(4i32)
    var calls = 0
    updated.update(fn(value: i32): i32 {
        calls += 1
        updated.set(100)
        value + 1
    })
    if updated.get() != 5 || calls != 1 { return 1 }

    var values = [1i32, 2, 3]
    {
        let cell = core.cell.Cell<[i32; 3]>.from_mut(mut values)
        let elements = cell.as_array_of_cells()
        elements[1].set(20)
        let as_array = core.cell.Cell<[i32; 3]>.(AsRef<[core.cell.Cell<i32>; 3]>).as_ref(cell)
        as_array[0].set(10)
        let as_slice = core.cell.Cell<[i32; 3]>.(AsRef<[core.cell.Cell<i32>]>).as_ref(cell)
        if as_slice.len() != 3usize { return 2 }
        as_slice[2].set(30)
        let sliced: read core.cell.Cell<[i32]> = cell
        let projected = sliced.as_slice_of_cells()
        if projected.len() != 3usize || projected[1].get() != 20 { return 3 }
        let projected_again = core.cell.Cell<[i32]>.(AsRef<[core.cell.Cell<i32>]>).as_ref(sliced)
        projected_again[1].update(fn(value: i32): i32 { value + 2 })
    }
    if values != [10i32, 22, 30] { return 4 }

    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var owned = [Owned(counter, 7), Owned(counter, 8)]
        {
            let cell = core.cell.Cell<[Owned; 2]>.from_mut(mut owned)
            let cells = cell.as_array_of_cells()
            let replaced = cells[1].replace(Owned(counter, 9))
            if replaced.value != 8 || drops != 0 { return 5 }
        }
        if owned[1].value != 9 || drops != 8 { return 6 }
    }
    if drops != 24 { return 9 }

    var empty = [0i32; 0]
    let empty_cell = core.cell.Cell<[i32; 0]>.from_mut(mut empty)
    let empty_slice: read core.cell.Cell<[i32]> = empty_cell
    if empty_slice.as_slice_of_cells().len() != 0usize { return 7 }
    let zero_sized = core.cell.Cell.new([(); 3])
    let zero_slice: read core.cell.Cell<[Unit]> = read zero_sized
    if zero_slice.as_slice_of_cells().len() != 3usize { return 8 }
    zero_slice.as_slice_of_cells()[2].set(())
    0
}
