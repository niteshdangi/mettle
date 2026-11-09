// One type implements two instantiations of a generic interface; each call
// selects the instantiation whose method signature and bounds fit its argument.
import alloc.vec
import core.iter.{ ExtendItems, OwnedIterable, Iterator }

type Bag { total: i32 }

extend Bag implements ExtendItems<i32> {
    mut fn extend<I: OwnedIterable<Item = i32>>(take items: I): Unit {
        var source = items.into_iter()
        while let present(item) = source.next() { self.total += item }
    }
}

extend Bag implements ExtendItems<bool> {
    mut fn extend<I: OwnedIterable<Item = bool>>(take items: I): Unit {
        var source = items.into_iter()
        while let present(item) = source.next() {
            if item { self.total += 100 }
        }
    }
}

interface Accept<T> {
    mut fn accept(take value: T): Unit;
}

extend Bag implements Accept<i32> {
    mut fn accept(take value: i32): Unit { self.total += value }
}

extend Bag implements Accept<bool> {
    mut fn accept(take value: bool): Unit { if value { self.total += 1000 } }
}

fn main(): i32 {
    var bag = Bag(0)
    var numbers = vec.new<i32>()
    numbers.push(2)
    numbers.push(3)
    bag.extend(numbers)
    var flags = vec.new<bool>()
    flags.push(true)
    flags.push(false)
    bag.extend(flags)
    let count: i32 = 7
    bag.accept(count)
    bag.accept(true)
    if bag.total != 1112 { return 1 }
    0
}
