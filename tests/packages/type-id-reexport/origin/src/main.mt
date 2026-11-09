pub type Shared {
    pub value: i32
}

extend Shared {
    pub fn number(): i32 { self.value }
}
