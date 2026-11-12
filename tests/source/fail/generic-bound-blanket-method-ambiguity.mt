// expect-error: type 14:56 ambiguous interface method; use explicit disambiguation
import conversion.{Render, Converted}

module conversion {
    pub interface Render { fn number(): i32; }
    pub interface Converted { fn converted(): i32; }
    extend<T: Render + unsized> T implements Converted {
        fn converted(): i32 { self.number() + 1 }
    }
}

interface Existing { fn converted(): i32; }

fn convert<T: Render + Existing>(read value: T): i32 { value.converted() }
fn main(): i32 { 0 }
