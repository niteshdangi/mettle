// profiles: debug release
import alloc.vec
import alloc.vec.List
import core.iter.{ExtendItems, FromItems, OwnedIterable}

fn gather<C: FromItems<X>, X, I: OwnedIterable<Item = X>>(take items: I): C { C.(FromItems<X>).from_iter(items) }
fn extend_with<C: ExtendItems<X>, X, I: OwnedIterable<Item = X>>(mut target: C, take items: I): Unit {
    target.extend(items)
}

fn main(): i32 {
    let units = [(), (), ()]
    let collected: Unit = gather(units)
    var nothing = ()
    extend_with(mut nothing, [(), ()])

    let singles: (List<i32>,) = gather([(1,), (2,), (3,)])
    if singles.0.len() != 3usize || singles.0[2usize] != 3 { return 1 }
    var target = (vec.new<i32>(),)
    extend_with(mut target, [(7,), (8,)])
    if target.0.len() != 2usize || target.0[0usize] != 7 { return 2 }
    0
}
