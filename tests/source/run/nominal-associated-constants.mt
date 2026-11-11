copy type Address4 { pub bits: u32 }
extend Address4 {
    const BROADCAST: Address4 = Address4(4294967295u32)
    const LOCALHOST: Address4 = Address4(2130706433u32)
    const UNSPECIFIED: Address4 = Address4(0u32)
    const ALIAS: Address4 = Self.LOCALHOST
}
copy type Address6 { pub octets: [u8;16] }
extend Address6 {
    const LOCALHOST: Address6 = Address6([0u8,0u8,0u8,0u8,0u8,0u8,0u8,0u8,
                  0u8,0u8,0u8,0u8,0u8,0u8,0u8,1u8])
    const UNSPECIFIED: Address6 = Address6([0u8;16usize])
}
copy enum Message { Bytes([u8;2]) }
extend Message { const VALUE: Message = Message.Bytes([2u8;2usize]) }
const fn message(): Message { Message.VALUE }
const MESSAGE: Message = message()
type Scalar<T> {}
extend<T> Scalar<T> { const LENGTH: usize = 2usize }
const ALIAS: Address4 = Address4.ALIAS
const PROJECTED: u32 = Address4.LOCALHOST.bits
const fn address(): Address4 { Address4.LOCALHOST }
const EVALUATED: Address4 = address()
fn pass<T>(take value: T): T { value }
fn main(): i32 {
    let a = pass(Address4.LOCALHOST)
    let b = Address4.LOCALHOST
    let zero = Address6.UNSPECIFIED
    let loopback = Address6.LOCALHOST
    let payload = match MESSAGE { Message.Bytes(bytes) => bytes[1] }
    let row: [u8;Scalar<i32>.LENGTH] = [9u8;Scalar<u8>.LENGTH]
    if a.bits == b.bits && ALIAS.bits == 2130706433u32 &&
       PROJECTED == ALIAS.bits && EVALUATED.bits == PROJECTED &&
       Address4.BROADCAST.bits == 4294967295u32 &&
       Address4.UNSPECIFIED.bits == 0u32 &&
       zero.octets[0] == 0u8 && zero.octets[15] == 0u8 &&
       loopback.octets[0] == 0u8 && loopback.octets[15] == 1u8 &&
       payload == 2u8 && row[1] == 9u8 { 0 } else { 1 }
}
