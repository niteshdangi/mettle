fn add(x: i32, y: i32): i32 { x +
 y }
fn main(): i32 { let n = add(
 20,
 22,
)
if n == 42
{ 0 }
/* outer
/* inner */
*/else
{ 1 }
}
