import std.sync.tls
import std.panic.{catch_panic, CatchResult}

type Item { value: i32 }
fn initialize(): Item { Item(7) }
static KEY: tls.LocalKey<Item> = tls.LocalKey(initialize)

fn main(): i32 {
    let observed = KEY.with(fn(read old: Item): i32 {
        let nested = KEY.with(fn(read same: Item): i32 { same.value })
        if nested.or_panic() != 7 { return 1 }
        let result = catch_panic(fn(): Unit { KEY.set(Item(9)) })
        match result {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 2 }
        }
        if old.value == 7 { 0 } else { 3 }
    })
    if observed.or_panic() != 0 { return 4 }
    KEY.set(Item(11))
    if KEY.with(fn(read value: Item): i32 { value.value }).or_panic() != 11 { return 5 }

    let owned = tls.new<Item>()
    owned.set(Item(13))
    let observed = owned.with(fn(read old: Item): i32 {
        let result = catch_panic(fn(): Unit { owned.set(Item(15)) })
        match result {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 6 }
        }
        if old.value == 13 { 0 } else { 7 }
    })
    if observed.or_panic() != 0 { return 8 }
    let panicked = catch_panic(fn(): Unit {
        let _result = owned.with(fn(read old: Item): Unit { panic("callback") })
    })
    match panicked {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    owned.set(Item(17))
    if owned.with(fn(read value: Item): i32 { value.value }).or_panic() != 17 { return 10 }
    0
}
