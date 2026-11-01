// profiles: debug release
import core.iter
import core.iter.{ Iterator, Sum, Product }

type Total { value: i32 }

extend<region r> Total implements Sum<read i32 from r> {
    static fn zero(): Total { Total(0) }
    fn plus(other: take read i32 from r): Total { Total(self.value + *other) }
}

extend<region r> Total implements Product<read i32 from r> {
    static fn one(): Total { Total(1) }
    fn times(other: take read i32 from r): Total { Total(self.value * *other) }
}

fn main(): i32 {
    var values = [2, 3]
    let total = values.iter().sum<Total>()
    let multiplied: Total = values.iter().product()
    values[0usize] = 9
    assert(total.value == 5 && multiplied.value == 6,
        "borrowed inputs produce independent owned results")
    assert(iter.sum(iter.once(2).chain(iter.once(3))) == 5,
        "owned sum keeps inferred output")
    assert(iter.product(iter.once(2).chain(iter.once(3))) == 6,
        "owned product keeps inferred output")
    0
}
