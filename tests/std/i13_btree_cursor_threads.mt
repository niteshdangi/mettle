import alloc.arc
import alloc.btree
import core.clone.Clone
import core.iter.{ExactSizeIterator, Iterator, OwnedIterable}
import std.thread

type Tracked {
    value: i32
    drops: arc.Arc<core.sync.atomic.AtomicUsize>
    drop { let _ = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var owning = btree.new<i32, Tracked>()
    owning.insert(1, Tracked(11, drops.retain()))
    owning.insert(2, Tracked(22, drops.retain()))
    owning.insert(3, Tracked(33, drops.retain()))
    let moved = owning.into_iter()
    let worker = thread.spawn(take fn(): i32 {
        var items = take moved
        let first = items.next().or_panic()
        first.value.value
    })
    match capture worker.join() {
        success(value) => { assert(value == 11, "owning cursor transfers its elements") },
        failure(_) => { panic("owning cursor worker panicked") }
    }
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 3usize,
        "worker drops consumed and remaining entries exactly once")

    var tree = btree.new<i32, i32>()
    tree.insert(1, 11)
    tree.insert(2, 22)
    tree.insert(3, 33)
    {
        let read_cursor = tree.iter()
        thread.scope(fn(read scope: thread.Scope): Unit {
            let transferred = read_cursor.clone()
            let reader = scope.spawn(take fn(): usize { transferred.count() })
            let observer = scope.spawn(fn(): usize { read_cursor.len() })
            assert(read_cursor.len() == 3usize, "parent shares a read cursor")
            match capture reader.join() {
                success(count) => { assert(count == 3usize, "borrowed cursor transfers") },
                failure(_) => { panic("read cursor worker panicked") }
            }
            match capture observer.join() {
                success(count) => { assert(count == 3usize, "read cursor shares") },
                failure(_) => { panic("shared cursor worker panicked") }
            }
        })
    }
    {
        let pending = core.cell.Cell.new(present(tree.entry(4)))
        thread.scope(fn(read scope: thread.Scope): Unit {
            let moved_entry = pending.replace(none).or_panic()
            let child = scope.spawn(take fn(): i32 {
                *moved_entry.or_insert(44)
            })
            match capture child.join() {
                success(value) => { assert(value == 44, "entry transfers its map loan") },
                failure(_) => { panic("entry worker panicked") }
            }
        })
    }
    {
        let pending = core.cell.Cell.new(present(tree.iter_mut()))
        thread.scope(fn(read scope: thread.Scope): Unit {
            let moved_cursor = pending.replace(none).or_panic()
            let child = scope.spawn(take fn(): usize {
                var items = take moved_cursor
                var count = 0usize
                while true {
                    match take items.next() {
                        present(pair) => { *pair.1 += 1; count += 1usize },
                        none => { break }
                    }
                }
                count
            })
            match capture child.join() {
                success(count) => { assert(count == 4usize, "exclusive cursor transfers") },
                failure(_) => { panic("exclusive cursor worker panicked") }
            }
        })
    }
    assert(*tree.get(1).or_panic() == 12 && *tree.get(4).or_panic() == 45,
        "joined cursor writes are visible to the original owner")
    0
}
