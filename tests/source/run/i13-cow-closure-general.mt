import alloc.borrow.{BorrowedOrOwned, OwnedType, ToOwned}
import core.borrow.{AsRef, Borrow}
import core.clone.Clone
import core.ops.Deref

type ReadOnly { number: i32 }
type ReadOnlyOwner {
    value: ReadOnly
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

extend ReadOnly implements OwnedType { type Owned = ReadOnlyOwner }
extend ReadOnlyOwner implements Borrow<ReadOnly> {
    fn borrow(): read ReadOnly from self { read self.value }
}

fn project<C: AsRef<ReadOnly> + Borrow<ReadOnly> + Deref<Target = ReadOnly>>(
    read cow: C
): bool {
    C.(AsRef<ReadOnly>).as_ref(cow).number == 7 &&
        C.(Borrow<ReadOnly>).borrow(cow).number == 7 &&
        C.(Deref).deref(cow).number == 7
}

fn read_and_move<region r>(
    read source: ReadOnly from r, drops: ptr<mut i32>
): i32 {
    let borrowed: BorrowedOrOwned<region r, ReadOnly> =
        BorrowedOrOwned.Borrowed(read source)
    if !borrowed.is_borrowed() || borrowed.is_owned() || !project(borrowed) {
        return 1
    }
    let owned: BorrowedOrOwned<region r, ReadOnly> =
        BorrowedOrOwned.Owned(ReadOnlyOwner(ReadOnly(7), drops))
    if !owned.is_owned() || owned.is_borrowed() || !project(owned) { return 2 }
    let moved: ReadOnlyOwner = match take owned {
        BorrowedOrOwned.Borrowed(_) => { return 3 },
        BorrowedOrOwned.Owned(value) => value
    }
    if moved.value.number != 7 || unsafe { *drops } != 0 { return 4 }
    0
}

type View {
    number: i32
    copies: ptr<mut i32>
    drops: ptr<mut i32>
}
type Owner {
    value: View
    drop { unsafe { *self.value.drops += 1 } }
}

extend View implements OwnedType { type Owned = Owner }
extend Owner implements Borrow<View> {
    fn borrow(): read View from self { read self.value }
}
extend View implements ToOwned {
    fn to_owned(): Owner {
        unsafe { *self.copies += 1 }
        Owner(View(self.number, self.copies, self.drops))
    }
}

fn copying<region r>(read source: View from r): i32 {
    let borrowed: BorrowedOrOwned<region r, View> =
        BorrowedOrOwned.Borrowed(read source)
    let borrowed_clone = borrowed.clone()
    if !borrowed_clone.is_borrowed() || unsafe { *source.copies } != 0 {
        return 13
    }
    let first: View.(OwnedType).Owned = borrowed.into_owned()
    if first.value.number != 11 { return 5 }
    core.mem.drop(first)

    var cow: BorrowedOrOwned<region r, View> =
        BorrowedOrOwned.Borrowed(read source)
    cow.to_mut().value.number = 13
    if !cow.is_owned() || cow.as_ref().number != 13 || source.number != 11 {
        return 6
    }
    if unsafe { *source.copies } != 2 { return 7 }
    cow.to_mut().value.number = 17
    if unsafe { *source.copies } != 2 { return 8 }
    let owned_clone = cow.clone()
    if !owned_clone.is_owned() || owned_clone.as_ref().number != 17 {
        return 14
    }
    core.mem.drop(owned_clone)
    let moved: View.(OwnedType).Owned = cow.into_owned()
    if moved.value.number != 17 || unsafe { *source.copies } != 3 { return 9 }
    core.mem.drop(moved)

    var target = source.to_owned()
    source.clone_into(mut target)
    if target.value.number != 11 ||
        unsafe { *source.copies } != 5 ||
        unsafe { *source.drops } != 4 {
        return 10
    }
    0
}

fn main(): i32 {
    var drops = 0
    let source = ReadOnly(7)
    let result = read_and_move(read source, core.ptr.from_mut(drops))
    if result != 0 { return result }
    if drops != 1 || source.number != 7 { return 11 }

    var copies = 0
    var owner_drops = 0
    let view = View(11, core.ptr.from_mut(copies), core.ptr.from_mut(owner_drops))
    let result = copying(read view)
    if result != 0 { return result }
    if copies != 5 || owner_drops != 5 || view.number != 11 { return 12 }
    0
}
