// profiles: debug release
import alloc.borrow.BorrowedOrOwned
import alloc.boxed
import alloc.boxed.Heap
import alloc.rc
import alloc.rc.LocalShared
import alloc.string
import core.borrow.AsRef
import core.clone.Clone
import core.convert.From
import core.text.Text

fn from_cow<region r>(take value: BorrowedOrOwned<region r, Text>): LocalShared<Text> {
    LocalShared<Text>.(From<BorrowedOrOwned<region r, Text>>).from(value)
}

fn as_ref_of<T>(read value: LocalShared<T>): read T { LocalShared<T>.(AsRef<T>).as_ref(value) }

fn main(): i32 {
    let from_string = LocalShared<Text>.(From<string.String>).from(string.from_text("owned"))
    if from_string.get() != "owned" { return 1 }
    let boxed_text = boxed.copy_text("boxed")
    let from_box = LocalShared<Text>.(From<Heap<Text>>).from(boxed_text)
    if from_box.get() != "boxed" { return 2 }
    let borrowed = from_cow(BorrowedOrOwned.Borrowed("cow"))
    let owned = from_cow(BorrowedOrOwned.Owned(string.from_text("cow")))
    if borrowed.get() != "cow" || owned.get() != "cow" { return 3 }
    let number = rc.new(41)
    if *as_ref_of(number) != 41 { return 4 }

    let strong = rc.new(7)
    let observer = strong.downgrade()
    let second = strong.clone()
    if strong.strong_count() != 2usize { return 5 }
    core.mem.drop(take second)
    if strong.strong_count() != 1usize { return 6 }
    if !observer.upgrade().is_present() { return 7 }
    core.mem.drop(take strong)
    if observer.upgrade().is_present() { return 8 }
    0
}
