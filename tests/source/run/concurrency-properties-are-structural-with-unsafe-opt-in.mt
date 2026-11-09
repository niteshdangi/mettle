
type Plain { a: i32; b: bool }
type Raw { p: ptr<mut u8> }
type Handle<T> { p: ptr<mut T> }
unsafe extend Raw implements Transferable {}
unsafe extend<T: Transferable> Handle<T> implements Transferable {}
unsafe extend<T: Shareable> Handle<T> implements Shareable {}
type Holder<T> { value: T }
type Cellular { c: core.cell.Cell<i32> }
fn send<T: Transferable>(take value: T): Unit {}
fn share<T: Shareable>(read value: T): Unit {}
fn owned<T: Transferable + Static>(take value: T): Unit {}
fn forward<T: Transferable>(take value: T): Unit { send(value) }
fn main(): i32 {
    send(Plain(1, true))
    send(Holder(Plain(1, true)))
    send(Raw(core.ptr.null_mut<u8>()))
    send(Holder(Handle(core.ptr.null_mut<i32>())))
    share(Plain(1, true))
    send(Cellular(core.cell.Cell.new(1)))
    forward(Holder(4))
    let k = 4
    owned(take fn(): i32 { k })
    0
}
