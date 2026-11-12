// profiles: debug release
import core.future.Poll
import core.cmp.PartialEq
import core.option
import core.outcome

type Owned {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn main(): i32 {
    let ready: Poll<(Outcome<i32, i32>)?> = Poll.Ready(present(success(3)))
    if ready.map_ok(fn(value: i32): i64 { value as i64 + 1i64 }) !=
        Poll<(Outcome<i64, i32>)?>.Ready(present(success(4i64))) { return 1 }
    let failed: Poll<(Outcome<i32, i32>)?> = Poll.Ready(present(failure(5)))
    if failed.map_err(fn(error: i32): i64 { error as i64 + 1i64 }) !=
        Poll<(Outcome<i32, i64>)?>.Ready(present(failure(6i64))) { return 2 }

    let pending_ok: Poll<(Outcome<i32, i32>)?> = Poll.Pending
    if !pending_ok.map_ok(fn(value: i32): i32 {
        core.panic.panic("map_ok called on Pending")
    }).is_pending() { return 3 }
    let pending_err: Poll<(Outcome<i32, i32>)?> = Poll.Pending
    if !pending_err.map_err(fn(error: i32): i32 {
        core.panic.panic("map_err called on Pending")
    }).is_pending() { return 4 }
    let empty_ok: Poll<(Outcome<i32, i32>)?> = Poll.Ready(none)
    if empty_ok.map_ok(fn(value: i32): i32 {
        core.panic.panic("map_ok called on none")
    }) != Poll<(Outcome<i32, i32>)?>.Ready(none) { return 5 }
    let empty_err: Poll<(Outcome<i32, i32>)?> = Poll.Ready(none)
    if empty_err.map_err(fn(error: i32): i32 {
        core.panic.panic("map_err called on none")
    }) != Poll<(Outcome<i32, i32>)?>.Ready(none) { return 6 }

    var drops = 0usize
    let counter = core.ptr.from_mut(mut drops)
    {
        let failed_owned: Poll<(Outcome<i32, Owned>)?> =
            Poll.Ready(present(failure(Owned(7, counter))))
        match take failed_owned.map_ok(fn(value: i32): i64 {
            core.panic.panic("map_ok called on failure")
        }) {
            Poll.Ready(result) => {
                let error = result.unwrap().unwrap_err()
                if error.value != 7 || drops != 0usize { return 7 }
            },
            Poll.Pending => { return 8 }
        }
    }
    if drops != 1usize { return 9 }
    {
        let ready_owned: Poll<(Outcome<Owned, i32>)?> =
            Poll.Ready(present(success(Owned(8, counter))))
        match take ready_owned.map_err(fn(error: i32): i64 {
            core.panic.panic("map_err called on success")
        }) {
            Poll.Ready(result) => {
                let value = result.unwrap().unwrap()
                if value.value != 8 || drops != 1usize { return 10 }
            },
            Poll.Pending => { return 11 }
        }
    }
    if drops != 2usize { return 12 }
    let captured = Owned(9, counter)
    let pending_capture: Poll<(Outcome<i32, i32>)?> = Poll.Pending
    let skipped = pending_capture.map_ok(take fn(value: i32): i32 {
        value + captured.value
    })
    if !skipped.is_pending() || drops != 3usize { return 13 }
    let selected: Poll<(Outcome<Owned, i32>)?> =
        Poll.Ready(present(success(Owned(10, counter))))
    let mapped = selected.map_ok(take fn(take value: Owned): i32 { value.value })
    if mapped != Poll<(Outcome<i32, i32>)?>.Ready(present(success(10))) ||
        drops != 4usize { return 14 }
    0
}
