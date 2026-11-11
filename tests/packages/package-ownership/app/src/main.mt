import remote.relay.{Foreign, ForeignType}
interface Local {}
type LocalType {}
type LocalGeneric<T> { value: T }
type LocalBorrowed<region r> { value: read i32 from r }
extend i32 implements Local {}
extend ForeignType implements Local {}
extend LocalType implements Foreign {}
extend<T> LocalGeneric<T> implements Foreign {}
extend<region r> LocalBorrowed<region r> implements Foreign {}
fn main(): i32 { 0 }
