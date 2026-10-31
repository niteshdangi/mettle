module family {
    pub module inner {
        pub(super) fn answer(): i32 { 42 }
        pub(package.family) macro value { () => { 20 }; }
        pub(super) alias Number = i32
        pub(super) const NUMBER: Number = 20
        pub(super) static STATIC_NUMBER: Number = 22
        pub(super) fn values(): Number { NUMBER + STATIC_NUMBER }
    }

    pub fn check(): i32 {
        inner.answer() + family.inner.value!() + inner.values()
    }
}

fn main(): i32 { family.check() - 104 }
