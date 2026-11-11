// expect-error: name 8:5 ambiguous import for 'collide'
module a { pub fn collide(): i32 { 1 } }
module b { pub fn collide(): i32 { 2 } }
import a.*
import b.*

fn main(): i32 {
    collide()
}
