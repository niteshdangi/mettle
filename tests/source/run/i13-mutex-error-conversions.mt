import std.sync.mutex
import core.convert.From

fn main(): i32 {
    let error = mutex.PoisonError.new(17i32)
    let converted = mutex.TryLockError<i32>.(From<mutex.PoisonError<i32>>).from(error)
    match take converted {
        mutex.TryLockError.Poisoned(error) => {
            if error.into_inner() == 17i32 { 0 } else { 1 }
        },
        mutex.TryLockError.WouldBlock => { 2 }
    }
}
