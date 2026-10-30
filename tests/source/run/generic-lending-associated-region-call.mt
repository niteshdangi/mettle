
interface Lending { type Item<region r>; }
type Owner {}
impl Owner implements Lending { type Item<region r> = read i32 from r; }
fn preserve<region r, T: Lending>(
    value: take <T implements Lending>::Item<region r>
): <T implements Lending>::Item<region r> { value }
fn main() {
    let value = 42
    if *preserve::<Owner>(read value) == 42 { 0 } else { 1 }
}
