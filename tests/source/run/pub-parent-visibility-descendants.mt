module a {
    pub module b {
        pub parent fn answer(): i32 { 42 }
        pub type Node {
            pub parent: i32

            pub parent fn weight(): i32 { self.parent }
        }
    }
    module c {
        pub fn get(): i32 { super.b.answer() }
    }
    pub fn check(): i32 {
        let node = b.Node(parent: 1)
        b.answer() + c.get() + node.weight()
    }
}

fn main(): i32 { a.check() - 85 }
