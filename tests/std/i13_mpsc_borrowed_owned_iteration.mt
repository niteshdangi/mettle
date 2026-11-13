import std.sync.mpsc
import core.iter.OwnedIterable

fn sum<I: OwnedIterable<Item = i32>>(take input: I): i32 {
    var total = 0
    for value in input { total += value }
    total
}

fn main(): i32 {
    let channel = mpsc.channel<i32>()
    let sender = channel.0
    let incoming = channel.1
    match capture sender.send(20) {
        success(_) => {},
        failure(_) => { return 1 }
    }
    match capture sender.send(22) {
        success(_) => {},
        failure(_) => { return 2 }
    }
    core.mem.drop(sender)
    if sum(read incoming) != 42 { return 3 }
    if sum(read incoming) != 0 { return 4 }
    if sum(incoming) != 0 { return 5 }
    0
}
