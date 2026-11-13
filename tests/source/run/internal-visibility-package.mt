module data {
    pub module inner {
        internal fn answer(): i32 { 20 }
        internal alias Number = i32
        internal const NUMBER: Number = 10
        internal static STATIC_NUMBER: Number = 8
        internal macro value { () => { 4 }; }
        pub type Counter {
            internal count: i32

            internal fn bump(): i32 { self.count + 1 }
        }
    }
}

module other {
    pub fn check(): i32 {
        let counter = super.data.inner.Counter(count: 0)
        let constants = super.data.inner.NUMBER + super.data.inner.STATIC_NUMBER
        super.data.inner.answer() + constants + super.data.inner.value!() + counter.bump()
    }
}

fn main(): i32 { other.check() - 43 }
