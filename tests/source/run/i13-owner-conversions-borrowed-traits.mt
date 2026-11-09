import alloc.arc
import alloc.boxed
import alloc.rc
import core.borrow.{ AsRef, Borrow }
import core.convert.From
import core.text.Text

type Value { number: i32 }

type DropValue {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn as_ref_value<T: AsRef<Value>>(owner: read T): i32 {
    owner.as_ref().number
}

fn borrow_value<T: Borrow<Value>>(owner: read T): i32 {
    owner.borrow().number
}

fn as_ref_text<T: AsRef<Text>>(owner: read T): usize {
    owner.as_ref().len()
}

fn borrow_text<T: Borrow<Text>>(owner: read T): usize {
    owner.borrow().len()
}

fn main(): i32 {
    let boxed_owner = boxed.Box<Value>.(From<Value>).from(Value(31))
    let local_owner = rc.Rc<Value>.(From<Value>).from(Value(32))
    let atomic = arc.Arc<Value>.(From<Value>).from(Value(33))
    if as_ref_value(boxed_owner) != 31 ||
        borrow_value(boxed_owner) != 31 ||
        as_ref_value(local_owner) != 32 ||
        borrow_value(local_owner) != 32 ||
        as_ref_value(atomic) != 33 ||
        borrow_value(atomic) != 33 {
        return 1
    }

    let boxed_text = boxed.copy_text("box")
    let local_text = rc.copy_text("local")
    let atomic_text = arc.copy_text("atomic")
    if as_ref_text(boxed_text) != 3usize ||
        borrow_text(boxed_text) != 3usize ||
        as_ref_text(local_text) != 5usize ||
        borrow_text(local_text) != 5usize ||
        as_ref_text(atomic_text) != 6usize ||
        borrow_text(atomic_text) != 6usize {
        return 2
    }

    var drops = 0
    {
        let _boxed_drop = boxed.Box<DropValue>.(From<DropValue>).from(
            DropValue(core.ptr.from_mut(drops))
        )
        let _local_drop = rc.Rc<DropValue>.(From<DropValue>).from(
            DropValue(core.ptr.from_mut(drops))
        )
        let _atomic_drop = arc.Arc<DropValue>.(From<DropValue>).from(
            DropValue(core.ptr.from_mut(drops))
        )
    }
    if drops != 3 { return 3 }
    0
}
