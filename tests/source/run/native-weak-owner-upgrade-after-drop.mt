fn main(): i32 {
    let atomic: weak i32 = {
        let owner: shared i32 = shared 11
        weak owner
    }
    let single: local weak i32 = {
        let owner: local shared i32 = local shared 13
        weak owner
    }
    match take atomic.upgrade() {
        none => {},
        present(_) => { return 1 }
    }
    match take single.upgrade() {
        none => {},
        present(_) => { return 2 }
    }
    0
}
