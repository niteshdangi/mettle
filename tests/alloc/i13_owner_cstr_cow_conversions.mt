import alloc.arc
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.{Box, copy_text}
import alloc.ffi.CString
import alloc.rc
import alloc.string.{String, ToString}
import alloc.vec
import core.clone.Clone
import core.convert.From
import core.ffi.CStr
import core.text.Text

type Item { value: i32; clones: ptr<mut i32> }

extend Item implements Clone {
    fn clone(): Item {
        unsafe { *self.clones += 1 }
        Item(self.value, self.clones)
    }
}

fn copy_items<region r>(read items: [Item] from r): arc.Arc<[Item]> {
    let cow: BorrowedOrOwned<region r, [Item]> = BorrowedOrOwned.Borrowed(read items)
    arc.Arc<[Item]>.(From<BorrowedOrOwned<region r, [Item]>>).from(cow)
}

fn copy_mut_items<region r>(mut items: [i32] from r): rc.Rc<[i32]> {
    rc.Rc<[i32]>.(From<mut [i32] from r>).from(mut items)
}

fn copy_mut_cstr<region r>(mut value: CStr from r): arc.Arc<CStr> {
    arc.Arc<CStr>.(From<mut CStr from r>).from(mut value)
}

fn copy_mut_local_cstr<region r>(mut value: CStr from r): rc.Rc<CStr> {
    rc.Rc<CStr>.(From<mut CStr from r>).from(mut value)
}

fn copy_mut_boxed_cstr<region r>(mut value: CStr from r): Box<CStr> {
    Box<CStr>.(From<mut CStr from r>).from(mut value)
}

fn copy_mut_text<region r>(mut value: Text from r): rc.Rc<Text> {
    rc.Rc<Text>.(From<mut Text from r>).from(mut value)
}

fn main(): i32 {
    let cstr = unsafe { CStr.from_bytes_with_nul_unchecked("a\u{0}".as_bytes()) }
    let boxed = Box<CStr>.(From<read CStr from static>).from(read *cstr)
    let local_owner = rc.Rc<CStr>.(From<read CStr from static>).from(read *cstr)
    let shared_owner = arc.Arc<CStr>.(From<read CStr from static>).from(read *cstr)
    assert(boxed.get().to_bytes_with_nul() == cstr.to_bytes_with_nul() &&
        local_owner.get().to_bytes_with_nul() == cstr.to_bytes_with_nul() &&
        shared_owner.get().to_bytes_with_nul() == cstr.to_bytes_with_nul(), "borrowed C strings preserve NUL metadata")
    assert(boxed.get().as_ptr() != cstr.as_ptr() && local_owner.get().as_ptr() != cstr.as_ptr() &&
        shared_owner.get().as_ptr() != cstr.as_ptr(), "borrowed conversions allocate independent storage")
    var mutable = cstr.to_owned().into_boxed_c_str()
    let copied_box = copy_mut_boxed_cstr(mutable.get_mut())
    let copied_local = copy_mut_local_cstr(mutable.get_mut())
    let copied_shared = copy_mut_cstr(mutable.get_mut())
    unsafe { *mutable.as_mut_ptr().cast<u8>() = 98u8 }
    assert(mutable.get().to_bytes()[0usize] == 98u8 &&
        copied_box.get().to_bytes()[0usize] == 97u8 &&
        copied_local.get().to_bytes()[0usize] == 97u8 &&
        copied_shared.get().to_bytes()[0usize] == 97u8, "exclusive C string conversions copy and release the loan")
    let owned_cstr = cstr.to_owned()
    let pointer = owned_cstr.as_ptr()
    let moved_box = Box<CStr>.(From<CString>).from(owned_cstr)
    assert(moved_box.get().as_ptr() == pointer, "CString to Box transfers the existing NUL-terminated allocation")
    let invalid = unsafe { CString.from_vec_with_nul_unchecked(vec.from_array([255u8, 0u8])) }
    let moved_local = rc.Rc<CStr>.(From<CString>).from(invalid)
    let empty = unsafe { CString.from_vec_with_nul_unchecked(vec.from_array([0u8])) }
    let moved_shared = arc.Arc<CStr>.(From<CString>).from(empty)
    assert(moved_local.get().to_bytes_with_nul().len() == 2usize &&
        moved_local.get().to_bytes()[0usize] == 255u8 &&
        moved_shared.get().to_bytes_with_nul().len() == 1usize &&
        moved_shared.get().is_empty(), "owned conversions preserve non-UTF8 and empty C strings")

    let borrowed_text: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("cow")
    let boxed_text = Box<Text>.(From<BorrowedOrOwned<region static, Text>>).from(borrowed_text.clone())
    let local_text = rc.Rc<Text>.(From<BorrowedOrOwned<region static, Text>>).from(borrowed_text.clone())
    let shared_text = arc.Arc<Text>.(From<BorrowedOrOwned<region static, Text>>).from(borrowed_text)
    assert(boxed_text.get() == "cow" && local_text.get() == "cow" && shared_text.get() == "cow",
        "borrowed Cow dispatches the selected view conversions")
    let boxed_source = String("owned")
    let text_pointer = boxed_source.as_ptr()
    let boxed_cow: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(boxed_source)
    let boxed_owned = Box<Text>.(From<BorrowedOrOwned<region static, Text>>).from(boxed_cow)
    assert(boxed_owned.get().as_bytes().as_ptr() == text_pointer, "owned text Cow to Box does not copy")
    let local_cow: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(String("local"))
    let shared_cow: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(String("shared"))
    let local_owned = rc.Rc<Text>.(From<BorrowedOrOwned<region static, Text>>).from(local_cow)
    let shared_owned = arc.Arc<Text>.(From<BorrowedOrOwned<region static, Text>>).from(shared_cow)
    assert(local_owned.get() == "local" && shared_owned.get() == "shared", "owned Cow selects owned conversion")
    let sibling = local_owned.clone()
    let local_pointer = local_owned.as_ptr().cast<u8>()
    let bytes = rc.Rc<[u8]>.(From<rc.Rc<Text>>).from(local_owned)
    assert(bytes.as_ptr().cast<u8>() == local_pointer &&
        bytes.strong_count() == 2usize && sibling.get() == "local", "Rc text to bytes preserves allocation and sibling counts")
    let borrowed_cstr: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Borrowed(read *cstr)
    let boxed_cstr = Box<CStr>.(From<BorrowedOrOwned<region static, CStr>>).from(borrowed_cstr.clone())
    let local_cstr = rc.Rc<CStr>.(From<BorrowedOrOwned<region static, CStr>>).from(borrowed_cstr.clone())
    let shared_cstr = arc.Arc<CStr>.(From<BorrowedOrOwned<region static, CStr>>).from(borrowed_cstr)
    assert(boxed_cstr.get().count_bytes() == 1usize && local_cstr.get().count_bytes() == 1usize &&
        shared_cstr.get().count_bytes() == 1usize, "C string Cow retains the terminator")
    let boxed_owned_cstr: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Owned(cstr.to_owned())
    let local_owned_cstr: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Owned(cstr.to_owned())
    let shared_owned_cstr: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Owned(cstr.to_owned())
    assert(Box<CStr>.(From<BorrowedOrOwned<region static, CStr>>).from(boxed_owned_cstr).get().count_bytes() == 1usize &&
        rc.Rc<CStr>.(From<BorrowedOrOwned<region static, CStr>>).from(local_owned_cstr).get().count_bytes() == 1usize &&
        arc.Arc<CStr>.(From<BorrowedOrOwned<region static, CStr>>).from(shared_owned_cstr).get().count_bytes() == 1usize,
        "owned C string Cow dispatches without retaining a source borrow")
    var text = copy_text("text")
    let independent_text = copy_mut_text(text.get_mut())
    unsafe { *text.as_mut_ptr().cast<u8>() = 110u8 }
    assert(text.get() == "next" && independent_text.get() == "text", "exclusive Rc text conversion copies")
    assert(boxed_text == copy_text("cow"), "unsized Box equality compares its payload")
    let message: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(String("owner error"))
    let error = Box<any core.error.Error>.(From<BorrowedOrOwned<region static, Text>>).from(message)
    assert(error.to_string().as_text() == "owner error", "boxed Cow errors retain their message")
    var clones = 0
    let counter = core.ptr.from_mut(clones)
    var items = vec.new<Item>()
    items.push(Item(71, counter))
    items.push(Item(73, counter))
    let copied_items = copy_items(items.as_slice())
    assert(clones == 2 && copied_items.get().len() == 2usize &&
        copied_items.get()[1usize].value == 73, "borrowed generic Cow clones each item once")
    let owned_items: BorrowedOrOwned<region static, [Item]> = BorrowedOrOwned.Owned(items)
    let moved_items = rc.Rc<[Item]>.(From<BorrowedOrOwned<region static, [Item]>>).from(owned_items)
    assert(clones == 2 && moved_items.get().len() == 2usize && moved_items.get()[0usize].value == 71,
        "owned generic Cow moves its List without cloning elements")
    var numbers = [79, 83]
    let copied_numbers = copy_mut_items(mut numbers)
    numbers[0usize] = 89
    assert(copied_numbers.get()[0usize] == 79 && numbers[0usize] == 89,
        "exclusive Rc slice conversion releases the source loan")
    0
}
