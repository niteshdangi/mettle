// expect-error: type 10:5 unsatisfied interface bound 'Transferable'
// expect-error: type 11:5 unsatisfied interface bound 'Transferable'
// expect-error: type 12:5 unsatisfied interface bound 'Shareable'
// expect-error: type 13:5 unsatisfied interface bound 'Shareable'
// expect-error: type 14:5 unsatisfied interface bound 'Transferable'
// expect-error-count: 5
fn send_ok<T: Transferable>() {}
fn sync_ok<T: Shareable>() {}
fn main(): i32 {
    send_ok<alloc.btree.EntryIter<region static, i32, core.cell.Cell<i32>, alloc.alloc.Global>>()
    send_ok<alloc.btree.Keys<region static, i32, core.cell.Cell<i32>, alloc.alloc.Global>>()
    sync_ok<alloc.btree.IterMut<region static, i32, core.cell.Cell<i32>, alloc.alloc.Global>>()
    sync_ok<alloc.btree.MapIntoIter<i32, core.cell.Cell<i32>, alloc.alloc.Global>>()
    send_ok<alloc.btree.Entry<region static, i32, alloc.rc.Rc<i32>, alloc.alloc.Global>>()
    0
}
