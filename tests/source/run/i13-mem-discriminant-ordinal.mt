import core.cmp.PartialEq

enum State { Waiting; Ready(i32); Finished }
type Cell { value: i32 }

fn main(): i32 {
    let waiting = core.mem.discriminant(State.Waiting)
    if waiting != core.mem.discriminant(State.Waiting) { return 1 }
    if waiting == core.mem.discriminant(State.Ready(1)) { return 2 }
    if core.mem.discriminant(State.Ready(1)) != core.mem.discriminant(State.Ready(2)) {
        return 3
    }
    if waiting == core.mem.discriminant(State.Finished) { return 4 }
    if core.mem.discriminant(Cell(1)) != core.mem.discriminant(Cell(2)) { return 5 }
    0
}
