
interface Number { const VALUE:u128 = 18446744073709551616; }
type Tag {}
impl Tag implements Number { const VALUE:u128 = 340282366920938463463374607431768211455; }
fn get<T:Number>(): u128 { T::VALUE }
@layout(u128)
copy enum Value { First = 1u128 << 127; Next; Last = (1u128 << 127) + 2 }
fn main() {
    if get::<Tag>() == 340282366920938463463374607431768211455u128 &&
       Value::First as u128 == 170141183460469231731687303715884105728u128 &&
       Value::Next as u128 == 170141183460469231731687303715884105729u128 &&
       Value::Last as u128 == 170141183460469231731687303715884105730u128 {
        0
    } else { 1 }
}
