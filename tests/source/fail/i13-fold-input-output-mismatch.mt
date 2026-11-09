// expect-error: type 12:13 unsatisfied interface obligation
import core.iter.{ Iterator, Sum }

type Total { value: i32 }
extend Total implements Sum<bool> {
    static fn zero(): Total { Total(0) }
    fn plus(take other: bool): Total { Total(self.value + if other { 1 } else { 0 }) }
}

fn main(): i32 {
    let values = [1, 2]
    let _ = values.iter().sum<Total>()
    0
}
