module original {
    pub fn helper(): i32 { 20 }
    pub fn first(): i32 { 20 }
    pub macro first { () => { helper() }; }
    pub macro second { () => { 22 }; }
}

import original.first
import original.{second as another}

fn main(): i32 { first() + first!() + another!() - 62 }
