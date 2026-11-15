import core.default.Default

type Text { bytes: [u8] }

interface StoredViewPattern {}
extend<region r> read Text from r implements StoredViewPattern {}

interface ReferentPattern {}
extend Text implements ReferentPattern {}

type Stored<region r> {
    by_value: read Text from r
    by_read: read Text from r
    by_mut: mut Text from r
}

fn accept_by_value<P: StoredViewPattern + Copy>(value: P): Unit {}
fn accept_by_read<P: unsized + ReferentPattern>(read value: P): Unit {}
fn accept_by_mut<P: unsized + ReferentPattern>(mut value: P): Unit {}

fn from_stored<region r>(mut stored: Stored<region r>): Unit {
    accept_by_value(stored.by_value)
    accept_by_read(stored.by_read)
    accept_by_mut(stored.by_mut)
}

type Slots<T, F> {
    value: core.cell.UnsafeCell<T?>
    initializer: core.cell.UnsafeCell<F?>
}
fn filled<T, F>(take value: T): Slots<T, F> {
    Slots(core.cell.UnsafeCell.new(present(value)),
          core.cell.UnsafeCell.new(none))
}
type Deferred<T, F = fn(): T> { initializer: F }
extend<T, F: take fn(): T> Deferred<T, F> {
    static fn new(take initializer: F): Deferred<T, F> { Deferred(initializer) }
}
fn deferred_value<T: Default>(): Deferred<T> {
    Deferred<T>.new(fn(): T { T.(Default).default() })
}

enum BorrowedView<region r, B: unsized> {
    Borrowed(read B from r);
    Empty
}
fn array_variant<region r, T, const N: usize>(
    take value: read [T; N] from r
): BorrowedView<region r, [T]> {
    BorrowedView<region r, [T]>.Borrowed(value)
}

interface Same<Rhs: unsized = Self> {
    fn same(read other: Rhs): bool
}
extend<region r, region s, T: Same<U> + unsized, U: unsized>
    read T from r implements Same<read U from s> {
    fn same(read other: read U from s): bool {
        T.(Same<U>).same(read *self, *other)
    }
}
extend i32 implements Same<i32> {
    fn same(read other: i32): bool { *self == *other }
}
fn stored_same<region r, region s, T: Same<U> + unsized, U: unsized>(
    take left: read T from r, take right: read U from s
): bool {
    left.same(right)
}

fn main(): i32 {
    let values = [7i32, 11i32]
    if !stored_same(read values[0], read values[0]) { return 3 }
    if stored_same(read values[0], read values[1]) { return 4 }
    match take array_variant(read values) {
        BorrowedView.Borrowed(view) => {
            if view.len() != 2usize || view[1] != 11i32 { return 1 }
        },
        BorrowedView.Empty => { return 2 }
    }
    0
}
