interface Output { fn value(): i32; }
type Number { value: i32 }
extend Number implements Output { fn value(): i32 { self.value } }
type Slot<region r> { output: mut any Output from r }
interface Inspect { fn inspect(mut slot: Slot): Unit; }
type Value {}
extend Value implements Inspect { fn inspect(mut slot: Slot): Unit {} }

fn inspect<region r>(mut slot: Slot<region r>, read value: any Inspect): mut Slot<region r> from slot {
    value.inspect(mut slot)
    mut slot
}
fn main(): i32 {
    var number = Number(42)
    var slot = Slot(mut number)
    let value = Value()
    let result = inspect(mut slot, read value)
    if result.output.value() == 42 { 0 } else { 1 }
}
