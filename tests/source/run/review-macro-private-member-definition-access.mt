// profiles: debug release
module definitions {
    pub type Vault {
        secret: i32
        fn hidden(): i32 { self.secret }
    }
    pub fn make(): Vault { Vault(secret: 7) }
    pub macro field { ($value:expr) => { $value.secret }; }
    pub macro method { ($value:expr) => { $value.hidden() }; }
}

fn main(): i32 {
    let value = definitions.make()
    definitions.field!(value) + definitions.method!(value) - 14
}
