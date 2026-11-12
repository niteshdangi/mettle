// profiles: debug release
import conversion.{Render, Converted}

module conversion {
    pub interface Render { fn number(): i32; }
    pub interface Converted { fn converted(): i32; }
    extend<T: Render + unsized> T implements Converted {
        fn converted(): i32 { self.number() + 1 }
    }
}

extend i32 implements Render { fn number(): i32 { self } }

fn convert<T: Render>(read value: T): i32 { value.converted() }

fn main(): i32 {
    if convert(41) == 42 { 0 } else { 1 }
}
