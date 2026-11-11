module source_helpers;
import core.future.Future

interface Source {
    async(heap) fn total(n: i32): i32
    async(heap) mut fn bump(read by: i32): i32
}

type Fixed { base: i32 }
extend Fixed implements Source {
    async fn total(n: i32): i32 { self.base + n }
    async mut fn bump(read by: i32): i32 {
        self.base = self.base + by
        self.base
    }
}

type Twice { v: i32 }
extend Twice implements Source {
    async fn total(n: i32): i32 { self.v * 2 + n }
    async mut fn bump(read by: i32): i32 {
        self.v = self.v + by * 2
        self.v
    }
}

fn drive<F: Future<Output = i32>>(take future: F): i32 {
    source_helpers.drive!(future)
}

async fn use_it(read s: any Source): i32 { await s.total(1) }

fn main(): i32 {
    var f = Fixed(10)
    var t = Twice(3)
    if drive(use_it(read f)) != 11 { return 1 }
    if drive(use_it(read t)) != 7 { return 2 }
    let step = 5
    let m: mut any Source = mut t
    if drive(m.bump(read step)) != 13 { return 3 }
    if drive(m.bump(read step)) != 23 { return 5 }
    if drive(Fixed(1).total(2)) != 3 { return 4 }
    0
}
