const fn answer() { 42 }
const VALUE: i32 = answer()
const fn pair() { (20, 22) }
const PAIR: (i32, i32) = pair()
const fn returned() { return 42 }
const RETURNED: i32 = returned()
const fn selected() { if true { 42 } else { 1000i64 } }
const SELECTED: i64 = selected()
const LAZY: i32 = if true { 42 } else { 1 / 0 }
const SHORT_CIRCUIT: bool = true || (1 / 0 == 0)
const fn width() { forwarded() }
const fn forwarded() { if true { 2 } else { OFFSET } }
const fn product_width() { width() }
const fn parameter_width() { width() }
const fn result_width() { width() }
const fn static_width() { width() }
const fn stored_width() { OFFSET }
const fn returned_width() { if OFFSET == 2 { return OFFSET }; 3usize }
const OFFSET: usize = 2
const ARRAY: [u8; static_width()] = [1, 2]
const ALIASED: Bytes = [7, 8]
const STORED: FromStorage = [3, 4]
const RETURN_ARRAY: FromReturn = [5, 6]
fn main(): i32 {
    let packet = Packet(ARRAY)
    let local_bytes: [u8; local_width()] = [1, 2]
    let produced = produce()
    if VALUE != 42 || PAIR.0 + PAIR.1 != 42 || RETURNED != 42 ||
       SELECTED != 42i64 || LAZY != 42 || !SHORT_CIRCUIT ||
       consume(packet.bytes) != 2 || STORED[1] != 4 ||
       RETURN_ARRAY[1] != 6 || ALIASED[1] != 8 ||
       local_bytes[1] != 2 || produced[1] != 2 { 1 } else { 0 }
}
const fn local_width() { OFFSET }
alias Bytes = [u8; width()]
alias FromStorage = [u8; stored_width()]
alias FromReturn = [u8; returned_width()]
copy type Packet { bytes: [u8; product_width()] }
fn consume(bytes: [u8; parameter_width()]): u8 { bytes[1] }
fn produce(): [u8; result_width()] { [1, 2] }
