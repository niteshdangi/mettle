// expect-error: name 8:5 private or restricted field 'secret' is inaccessible
module definitions {
    pub type Vault { secret: i32 }
    pub fn make(): Vault { Vault(secret: 7) }
}
fn main(): i32 {
    let value = definitions.make()
    value.secret
}
