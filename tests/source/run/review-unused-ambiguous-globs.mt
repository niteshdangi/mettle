module a { pub fn collide(): i32 { 1 } }
module b { pub fn collide(): i32 { 2 } }
import a.*
import b.*
fn main(): i32 { a.collide() + b.collide() - 3 }
