import remote.relay.{Foreign as Reexported, ForeignType as ReexportedType}
alias Alias = ReexportedType
extend Alias implements Reexported {}
fn main(): i32 { 0 }
