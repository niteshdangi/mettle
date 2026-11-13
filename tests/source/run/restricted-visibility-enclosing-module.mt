module family {
    pub module inner {
        pub parent fn answer(): i32 { 42 }
        pub parent macro value { () => { 20 }; }
        pub parent alias Number = i32
        pub parent const NUMBER: Number = 20
        pub parent static STATIC_NUMBER: Number = 22
        pub parent fn values(): Number { NUMBER + STATIC_NUMBER }
    }

    pub fn check(): i32 {
        inner.answer() + family.inner.value!() + inner.values()
    }
}

fn main(): i32 { family.check() - 104 }
