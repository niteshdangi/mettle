
interface Readable { fn value(): i32; }
interface Counter: Readable { mut fn increment(): Unit; }
type Number { value: i32 }
extend Number implements Readable { fn value(): i32 { self.value } }
extend Number implements Counter { mut fn increment(): Unit { self.value += 1 } }
fn increment(mut value: any Counter) { value.increment() }
fn inspect(read value: any Readable): i32 { value.value() }
fn main() {
    var value = Number(41)
    increment(value)
    let child: read any Counter = read value
    let parent: read any Readable = child
    if inspect(child) == 42 && inspect(parent) == 42 { 0 } else { 1 }
}
