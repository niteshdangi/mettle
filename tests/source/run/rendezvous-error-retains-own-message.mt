import std.sync.mpsc
import std.thread

fn producer(read tx: mpsc.SyncSender<i32>, base: i32): i32 {
    var index = 0
    while index < 256 {
        let value = base + index
        let expected = value
        let result = capture tx.send_timeout(value, 100000u64)
        match take result {
            success(_) => {},
            failure(error) => {
                if error.value != expected { return 1 }
                if error.disconnected { return 2 }
            }
        }
        index += 1
    }
    0
}

fn main(): i32 {
    let pair = mpsc.sync_channel<i32>(0usize)
    let left = pair.0.duplicate()
    let right = pair.0
    let a = thread.spawn(take fn(): i32 { producer(read left, 1000) })
    let b = thread.spawn(take fn(): i32 { producer(read right, 2000) })
    var seen = [false; 512]
    while true {
        match take capture pair.1.recv() {
            success(value) => {
                let index = if value >= 2000 { value - 2000 + 256 } else { value - 1000 }
                if index < 0 || index >= 512 { return 3 }
                if seen[index as usize] { return 4 }
                seen[index as usize] = true
            },
            failure(_) => { break }
        }
    }
    match take capture a.join() { success(0) => {}, _ => { return 5 } }
    match take capture b.join() { success(0) => {}, _ => { return 6 } }
    0
}
