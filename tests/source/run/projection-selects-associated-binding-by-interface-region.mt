interface Pick<region r> { type Item; }
type Owner {}
extend<region r> Owner implements Pick<region r> {
    type Item = read i32 from r
}
fn preserve<region a, region b,
    T: Pick<region a, Item = read i32 from a> +
       Pick<region b, Item = read i32 from b>>(
    take value: T.(Pick<region b>).Item
): read i32 from b { value }
fn main(): i32 { 0 }
