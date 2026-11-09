// profiles: debug release
// Integer and bool operator interfaces in generic code: value and view
// operands, every integer shift-count type (and its view), compound
// assignment, Not/Neg, and the lossless From / range-checked TryFrom
// conversions. Expected values are computed independently.
import core.num
import core.num.TryFromIntError
import core.convert.{From, Into, TryFrom, TryInto}
import core.ops.{Add, Sub, Mul, Div, Rem, BitAnd, BitOr, BitXor, Shl, Shr, Not, Neg}
import core.ops.{AddAssign, SubAssign, MulAssign, DivAssign, RemAssign}
import core.ops.{BitAndAssign, BitOrAssign, BitXorAssign, ShlAssign, ShrAssign}
import core.panic.panic

fn add<A: Add<B>, B>(a: A, b: B): A.Output { a.add(b) }
fn sub<A: Sub<B>, B>(a: A, b: B): A.Output { a.sub(b) }
fn mul<A: Mul<B>, B>(a: A, b: B): A.Output { a.mul(b) }
fn div<A: Div<B>, B>(a: A, b: B): A.Output { a.div(b) }
fn rem<A: Rem<B>, B>(a: A, b: B): A.Output { a.rem(b) }
fn and<A: BitAnd<B>, B>(a: A, b: B): A.Output { a.bitand(b) }
fn or<A: BitOr<B>, B>(a: A, b: B): A.Output { a.bitor(b) }
fn xor<A: BitXor<B>, B>(a: A, b: B): A.Output { a.bitxor(b) }
fn shl<A: Shl<B>, B>(a: A, b: B): A.Output { a.shl(b) }
fn shr<A: Shr<B>, B>(a: A, b: B): A.Output { a.shr(b) }
fn not<A: Not>(a: A): A.Output { a.not() }
fn neg<A: Neg>(a: A): A.Output { a.neg() }
fn add_assign<A: AddAssign<B>, B>(a: take A, b: B): A { var x = a; x.add_assign(b); x }
fn sub_assign<A: SubAssign<B>, B>(a: take A, b: B): A { var x = a; x.sub_assign(b); x }
fn mul_assign<A: MulAssign<B>, B>(a: take A, b: B): A { var x = a; x.mul_assign(b); x }
fn div_assign<A: DivAssign<B>, B>(a: take A, b: B): A { var x = a; x.div_assign(b); x }
fn rem_assign<A: RemAssign<B>, B>(a: take A, b: B): A { var x = a; x.rem_assign(b); x }
fn and_assign<A: BitAndAssign<B>, B>(a: take A, b: B): A { var x = a; x.bitand_assign(b); x }
fn or_assign<A: BitOrAssign<B>, B>(a: take A, b: B): A { var x = a; x.bitor_assign(b); x }
fn xor_assign<A: BitXorAssign<B>, B>(a: take A, b: B): A { var x = a; x.bitxor_assign(b); x }
fn shl_assign<A: ShlAssign<B>, B>(a: take A, b: B): A { var x = a; x.shl_assign(b); x }
fn shr_assign<A: ShrAssign<B>, B>(a: take A, b: B): A { var x = a; x.shr_assign(b); x }
fn widen<A, B: From<A>>(a: take A): B { B.(From<A>).from(a) }
fn widen_into<A: Into<B>, B>(a: take A): B { A.(Into<B>).into(a) }
fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(_) => false }
}
fn narrow<A, B: TryFrom<A>>(a: take A): B? {
    match take B.(TryFrom<A>).try_from(a) { success(value) => present(value), failure(_) => none }
}

fn group0() {
    if !(add((-10i8), 7i8) == (-3i8)) { panic("add #1") }
    if !(add((read (-10i8)), 7i8) == (-3i8)) { panic("add #2") }
    if !(add((-10i8), (read 7i8)) == (-3i8)) { panic("add #3") }
    if !(add((read (-10i8)), (read 7i8)) == (-3i8)) { panic("add #4") }
    if !(add_assign((-10i8), 7i8) == (-3i8)) { panic("add_assign #5") }
    if !(add_assign((-10i8), (read 7i8)) == (-3i8)) { panic("add_assign #6") }
    if !(sub((-10i8), 7i8) == (-17i8)) { panic("sub #7") }
    if !(sub((read (-10i8)), 7i8) == (-17i8)) { panic("sub #8") }
    if !(sub((-10i8), (read 7i8)) == (-17i8)) { panic("sub #9") }
    if !(sub((read (-10i8)), (read 7i8)) == (-17i8)) { panic("sub #10") }
    if !(sub_assign((-10i8), 7i8) == (-17i8)) { panic("sub_assign #11") }
    if !(sub_assign((-10i8), (read 7i8)) == (-17i8)) { panic("sub_assign #12") }
    if !(mul((-10i8), 7i8) == (-70i8)) { panic("mul #13") }
    if !(mul((read (-10i8)), 7i8) == (-70i8)) { panic("mul #14") }
    if !(mul((-10i8), (read 7i8)) == (-70i8)) { panic("mul #15") }
    if !(mul((read (-10i8)), (read 7i8)) == (-70i8)) { panic("mul #16") }
    if !(mul_assign((-10i8), 7i8) == (-70i8)) { panic("mul_assign #17") }
    if !(mul_assign((-10i8), (read 7i8)) == (-70i8)) { panic("mul_assign #18") }
    if !(div((-10i8), 7i8) == (-1i8)) { panic("div #19") }
    if !(div((read (-10i8)), 7i8) == (-1i8)) { panic("div #20") }
    if !(div((-10i8), (read 7i8)) == (-1i8)) { panic("div #21") }
    if !(div((read (-10i8)), (read 7i8)) == (-1i8)) { panic("div #22") }
    if !(div_assign((-10i8), 7i8) == (-1i8)) { panic("div_assign #23") }
    if !(div_assign((-10i8), (read 7i8)) == (-1i8)) { panic("div_assign #24") }
    if !(rem((-10i8), 7i8) == (-3i8)) { panic("rem #25") }
    if !(rem((read (-10i8)), 7i8) == (-3i8)) { panic("rem #26") }
    if !(rem((-10i8), (read 7i8)) == (-3i8)) { panic("rem #27") }
    if !(rem((read (-10i8)), (read 7i8)) == (-3i8)) { panic("rem #28") }
    if !(rem_assign((-10i8), 7i8) == (-3i8)) { panic("rem_assign #29") }
    if !(rem_assign((-10i8), (read 7i8)) == (-3i8)) { panic("rem_assign #30") }
    if !(and((-10i8), 7i8) == 6i8) { panic("and #31") }
    if !(and((read (-10i8)), 7i8) == 6i8) { panic("and #32") }
    if !(and((-10i8), (read 7i8)) == 6i8) { panic("and #33") }
    if !(and((read (-10i8)), (read 7i8)) == 6i8) { panic("and #34") }
    if !(and_assign((-10i8), 7i8) == 6i8) { panic("and_assign #35") }
    if !(and_assign((-10i8), (read 7i8)) == 6i8) { panic("and_assign #36") }
    if !(or((-10i8), 7i8) == (-9i8)) { panic("or #37") }
    if !(or((read (-10i8)), 7i8) == (-9i8)) { panic("or #38") }
    if !(or((-10i8), (read 7i8)) == (-9i8)) { panic("or #39") }
    if !(or((read (-10i8)), (read 7i8)) == (-9i8)) { panic("or #40") }
    if !(or_assign((-10i8), 7i8) == (-9i8)) { panic("or_assign #41") }
    if !(or_assign((-10i8), (read 7i8)) == (-9i8)) { panic("or_assign #42") }
    if !(xor((-10i8), 7i8) == (-15i8)) { panic("xor #43") }
    if !(xor((read (-10i8)), 7i8) == (-15i8)) { panic("xor #44") }
    if !(xor((-10i8), (read 7i8)) == (-15i8)) { panic("xor #45") }
    if !(xor((read (-10i8)), (read 7i8)) == (-15i8)) { panic("xor #46") }
    if !(xor_assign((-10i8), 7i8) == (-15i8)) { panic("xor_assign #47") }
    if !(xor_assign((-10i8), (read 7i8)) == (-15i8)) { panic("xor_assign #48") }
    if !(not((-10i8)) == 9i8) { panic("not #49") }
    if !(not((read (-10i8))) == 9i8) { panic("not #50") }
    if !(neg((-10i8)) == 10i8) { panic("neg #51") }
    if !(neg((read (-10i8))) == 10i8) { panic("neg #52") }
    if !(shl((-10i8), 3i8) == (-80i8)) { panic("shl #53") }
    if !(shr((-10i8), 3i8) == (-2i8)) { panic("shr #54") }
    if !(shl((read (-10i8)), 3i8) == (-80i8)) { panic("shl #55") }
    if !(shr((read (-10i8)), 3i8) == (-2i8)) { panic("shr #56") }
    if !(shl_assign((-10i8), 3i8) == (-80i8)) { panic("shl_assign #57") }
    if !(shr_assign((-10i8), 3i8) == (-2i8)) { panic("shr_assign #58") }
    if !(shl((-10i8), (read 3i8)) == (-80i8)) { panic("shl #59") }
    if !(shr((-10i8), (read 3i8)) == (-2i8)) { panic("shr #60") }
    if !(shl((read (-10i8)), (read 3i8)) == (-80i8)) { panic("shl #61") }
    if !(shr((read (-10i8)), (read 3i8)) == (-2i8)) { panic("shr #62") }
    if !(shl_assign((-10i8), (read 3i8)) == (-80i8)) { panic("shl_assign #63") }
    if !(shr_assign((-10i8), (read 3i8)) == (-2i8)) { panic("shr_assign #64") }
    if !(shl((-10i8), 3i16) == (-80i8)) { panic("shl #65") }
    if !(shr((-10i8), 3i16) == (-2i8)) { panic("shr #66") }
    if !(shl((read (-10i8)), 3i16) == (-80i8)) { panic("shl #67") }
    if !(shr((read (-10i8)), 3i16) == (-2i8)) { panic("shr #68") }
    if !(shl_assign((-10i8), 3i16) == (-80i8)) { panic("shl_assign #69") }
    if !(shr_assign((-10i8), 3i16) == (-2i8)) { panic("shr_assign #70") }
    if !(shl((-10i8), (read 3i16)) == (-80i8)) { panic("shl #71") }
    if !(shr((-10i8), (read 3i16)) == (-2i8)) { panic("shr #72") }
    if !(shl((read (-10i8)), (read 3i16)) == (-80i8)) { panic("shl #73") }
    if !(shr((read (-10i8)), (read 3i16)) == (-2i8)) { panic("shr #74") }
    if !(shl_assign((-10i8), (read 3i16)) == (-80i8)) { panic("shl_assign #75") }
    if !(shr_assign((-10i8), (read 3i16)) == (-2i8)) { panic("shr_assign #76") }
    if !(shl((-10i8), 3i32) == (-80i8)) { panic("shl #77") }
    if !(shr((-10i8), 3i32) == (-2i8)) { panic("shr #78") }
    if !(shl((read (-10i8)), 3i32) == (-80i8)) { panic("shl #79") }
    if !(shr((read (-10i8)), 3i32) == (-2i8)) { panic("shr #80") }
    if !(shl_assign((-10i8), 3i32) == (-80i8)) { panic("shl_assign #81") }
    if !(shr_assign((-10i8), 3i32) == (-2i8)) { panic("shr_assign #82") }
    if !(shl((-10i8), (read 3i32)) == (-80i8)) { panic("shl #83") }
    if !(shr((-10i8), (read 3i32)) == (-2i8)) { panic("shr #84") }
    if !(shl((read (-10i8)), (read 3i32)) == (-80i8)) { panic("shl #85") }
    if !(shr((read (-10i8)), (read 3i32)) == (-2i8)) { panic("shr #86") }
    if !(shl_assign((-10i8), (read 3i32)) == (-80i8)) { panic("shl_assign #87") }
    if !(shr_assign((-10i8), (read 3i32)) == (-2i8)) { panic("shr_assign #88") }
    if !(shl((-10i8), 3i64) == (-80i8)) { panic("shl #89") }
    if !(shr((-10i8), 3i64) == (-2i8)) { panic("shr #90") }
    if !(shl((read (-10i8)), 3i64) == (-80i8)) { panic("shl #91") }
    if !(shr((read (-10i8)), 3i64) == (-2i8)) { panic("shr #92") }
    if !(shl_assign((-10i8), 3i64) == (-80i8)) { panic("shl_assign #93") }
    if !(shr_assign((-10i8), 3i64) == (-2i8)) { panic("shr_assign #94") }
    if !(shl((-10i8), (read 3i64)) == (-80i8)) { panic("shl #95") }
    if !(shr((-10i8), (read 3i64)) == (-2i8)) { panic("shr #96") }
    if !(shl((read (-10i8)), (read 3i64)) == (-80i8)) { panic("shl #97") }
    if !(shr((read (-10i8)), (read 3i64)) == (-2i8)) { panic("shr #98") }
    if !(shl_assign((-10i8), (read 3i64)) == (-80i8)) { panic("shl_assign #99") }
    if !(shr_assign((-10i8), (read 3i64)) == (-2i8)) { panic("shr_assign #100") }
    if !(shl((-10i8), 3i128) == (-80i8)) { panic("shl #101") }
    if !(shr((-10i8), 3i128) == (-2i8)) { panic("shr #102") }
    if !(shl((read (-10i8)), 3i128) == (-80i8)) { panic("shl #103") }
    if !(shr((read (-10i8)), 3i128) == (-2i8)) { panic("shr #104") }
    if !(shl_assign((-10i8), 3i128) == (-80i8)) { panic("shl_assign #105") }
    if !(shr_assign((-10i8), 3i128) == (-2i8)) { panic("shr_assign #106") }
    if !(shl((-10i8), (read 3i128)) == (-80i8)) { panic("shl #107") }
    if !(shr((-10i8), (read 3i128)) == (-2i8)) { panic("shr #108") }
    if !(shl((read (-10i8)), (read 3i128)) == (-80i8)) { panic("shl #109") }
    if !(shr((read (-10i8)), (read 3i128)) == (-2i8)) { panic("shr #110") }
    if !(shl_assign((-10i8), (read 3i128)) == (-80i8)) { panic("shl_assign #111") }
    if !(shr_assign((-10i8), (read 3i128)) == (-2i8)) { panic("shr_assign #112") }
    if !(shl((-10i8), 3isize) == (-80i8)) { panic("shl #113") }
    if !(shr((-10i8), 3isize) == (-2i8)) { panic("shr #114") }
    if !(shl((read (-10i8)), 3isize) == (-80i8)) { panic("shl #115") }
    if !(shr((read (-10i8)), 3isize) == (-2i8)) { panic("shr #116") }
    if !(shl_assign((-10i8), 3isize) == (-80i8)) { panic("shl_assign #117") }
    if !(shr_assign((-10i8), 3isize) == (-2i8)) { panic("shr_assign #118") }
    if !(shl((-10i8), (read 3isize)) == (-80i8)) { panic("shl #119") }
    if !(shr((-10i8), (read 3isize)) == (-2i8)) { panic("shr #120") }
    if !(shl((read (-10i8)), (read 3isize)) == (-80i8)) { panic("shl #121") }
    if !(shr((read (-10i8)), (read 3isize)) == (-2i8)) { panic("shr #122") }
    if !(shl_assign((-10i8), (read 3isize)) == (-80i8)) { panic("shl_assign #123") }
    if !(shr_assign((-10i8), (read 3isize)) == (-2i8)) { panic("shr_assign #124") }
    if !(shl((-10i8), 3u8) == (-80i8)) { panic("shl #125") }
    if !(shr((-10i8), 3u8) == (-2i8)) { panic("shr #126") }
    if !(shl((read (-10i8)), 3u8) == (-80i8)) { panic("shl #127") }
    if !(shr((read (-10i8)), 3u8) == (-2i8)) { panic("shr #128") }
    if !(shl_assign((-10i8), 3u8) == (-80i8)) { panic("shl_assign #129") }
    if !(shr_assign((-10i8), 3u8) == (-2i8)) { panic("shr_assign #130") }
    if !(shl((-10i8), (read 3u8)) == (-80i8)) { panic("shl #131") }
    if !(shr((-10i8), (read 3u8)) == (-2i8)) { panic("shr #132") }
    if !(shl((read (-10i8)), (read 3u8)) == (-80i8)) { panic("shl #133") }
    if !(shr((read (-10i8)), (read 3u8)) == (-2i8)) { panic("shr #134") }
    if !(shl_assign((-10i8), (read 3u8)) == (-80i8)) { panic("shl_assign #135") }
    if !(shr_assign((-10i8), (read 3u8)) == (-2i8)) { panic("shr_assign #136") }
    if !(shl((-10i8), 3u16) == (-80i8)) { panic("shl #137") }
    if !(shr((-10i8), 3u16) == (-2i8)) { panic("shr #138") }
    if !(shl((read (-10i8)), 3u16) == (-80i8)) { panic("shl #139") }
    if !(shr((read (-10i8)), 3u16) == (-2i8)) { panic("shr #140") }
    if !(shl_assign((-10i8), 3u16) == (-80i8)) { panic("shl_assign #141") }
    if !(shr_assign((-10i8), 3u16) == (-2i8)) { panic("shr_assign #142") }
    if !(shl((-10i8), (read 3u16)) == (-80i8)) { panic("shl #143") }
    if !(shr((-10i8), (read 3u16)) == (-2i8)) { panic("shr #144") }
    if !(shl((read (-10i8)), (read 3u16)) == (-80i8)) { panic("shl #145") }
    if !(shr((read (-10i8)), (read 3u16)) == (-2i8)) { panic("shr #146") }
    if !(shl_assign((-10i8), (read 3u16)) == (-80i8)) { panic("shl_assign #147") }
    if !(shr_assign((-10i8), (read 3u16)) == (-2i8)) { panic("shr_assign #148") }
    if !(shl((-10i8), 3u32) == (-80i8)) { panic("shl #149") }
    if !(shr((-10i8), 3u32) == (-2i8)) { panic("shr #150") }
}

fn group1() {
    if !(shl((read (-10i8)), 3u32) == (-80i8)) { panic("shl #151") }
    if !(shr((read (-10i8)), 3u32) == (-2i8)) { panic("shr #152") }
    if !(shl_assign((-10i8), 3u32) == (-80i8)) { panic("shl_assign #153") }
    if !(shr_assign((-10i8), 3u32) == (-2i8)) { panic("shr_assign #154") }
    if !(shl((-10i8), (read 3u32)) == (-80i8)) { panic("shl #155") }
    if !(shr((-10i8), (read 3u32)) == (-2i8)) { panic("shr #156") }
    if !(shl((read (-10i8)), (read 3u32)) == (-80i8)) { panic("shl #157") }
    if !(shr((read (-10i8)), (read 3u32)) == (-2i8)) { panic("shr #158") }
    if !(shl_assign((-10i8), (read 3u32)) == (-80i8)) { panic("shl_assign #159") }
    if !(shr_assign((-10i8), (read 3u32)) == (-2i8)) { panic("shr_assign #160") }
    if !(shl((-10i8), 3u64) == (-80i8)) { panic("shl #161") }
    if !(shr((-10i8), 3u64) == (-2i8)) { panic("shr #162") }
    if !(shl((read (-10i8)), 3u64) == (-80i8)) { panic("shl #163") }
    if !(shr((read (-10i8)), 3u64) == (-2i8)) { panic("shr #164") }
    if !(shl_assign((-10i8), 3u64) == (-80i8)) { panic("shl_assign #165") }
    if !(shr_assign((-10i8), 3u64) == (-2i8)) { panic("shr_assign #166") }
    if !(shl((-10i8), (read 3u64)) == (-80i8)) { panic("shl #167") }
    if !(shr((-10i8), (read 3u64)) == (-2i8)) { panic("shr #168") }
    if !(shl((read (-10i8)), (read 3u64)) == (-80i8)) { panic("shl #169") }
    if !(shr((read (-10i8)), (read 3u64)) == (-2i8)) { panic("shr #170") }
    if !(shl_assign((-10i8), (read 3u64)) == (-80i8)) { panic("shl_assign #171") }
    if !(shr_assign((-10i8), (read 3u64)) == (-2i8)) { panic("shr_assign #172") }
    if !(shl((-10i8), 3u128) == (-80i8)) { panic("shl #173") }
    if !(shr((-10i8), 3u128) == (-2i8)) { panic("shr #174") }
    if !(shl((read (-10i8)), 3u128) == (-80i8)) { panic("shl #175") }
    if !(shr((read (-10i8)), 3u128) == (-2i8)) { panic("shr #176") }
    if !(shl_assign((-10i8), 3u128) == (-80i8)) { panic("shl_assign #177") }
    if !(shr_assign((-10i8), 3u128) == (-2i8)) { panic("shr_assign #178") }
    if !(shl((-10i8), (read 3u128)) == (-80i8)) { panic("shl #179") }
    if !(shr((-10i8), (read 3u128)) == (-2i8)) { panic("shr #180") }
    if !(shl((read (-10i8)), (read 3u128)) == (-80i8)) { panic("shl #181") }
    if !(shr((read (-10i8)), (read 3u128)) == (-2i8)) { panic("shr #182") }
    if !(shl_assign((-10i8), (read 3u128)) == (-80i8)) { panic("shl_assign #183") }
    if !(shr_assign((-10i8), (read 3u128)) == (-2i8)) { panic("shr_assign #184") }
    if !(shl((-10i8), 3usize) == (-80i8)) { panic("shl #185") }
    if !(shr((-10i8), 3usize) == (-2i8)) { panic("shr #186") }
    if !(shl((read (-10i8)), 3usize) == (-80i8)) { panic("shl #187") }
    if !(shr((read (-10i8)), 3usize) == (-2i8)) { panic("shr #188") }
    if !(shl_assign((-10i8), 3usize) == (-80i8)) { panic("shl_assign #189") }
    if !(shr_assign((-10i8), 3usize) == (-2i8)) { panic("shr_assign #190") }
    if !(shl((-10i8), (read 3usize)) == (-80i8)) { panic("shl #191") }
    if !(shr((-10i8), (read 3usize)) == (-2i8)) { panic("shr #192") }
    if !(shl((read (-10i8)), (read 3usize)) == (-80i8)) { panic("shl #193") }
    if !(shr((read (-10i8)), (read 3usize)) == (-2i8)) { panic("shr #194") }
    if !(shl_assign((-10i8), (read 3usize)) == (-80i8)) { panic("shl_assign #195") }
    if !(shr_assign((-10i8), (read 3usize)) == (-2i8)) { panic("shr_assign #196") }
    if !(add((-10i16), 7i16) == (-3i16)) { panic("add #197") }
    if !(add((read (-10i16)), 7i16) == (-3i16)) { panic("add #198") }
    if !(add((-10i16), (read 7i16)) == (-3i16)) { panic("add #199") }
    if !(add((read (-10i16)), (read 7i16)) == (-3i16)) { panic("add #200") }
    if !(add_assign((-10i16), 7i16) == (-3i16)) { panic("add_assign #201") }
    if !(add_assign((-10i16), (read 7i16)) == (-3i16)) { panic("add_assign #202") }
    if !(sub((-10i16), 7i16) == (-17i16)) { panic("sub #203") }
    if !(sub((read (-10i16)), 7i16) == (-17i16)) { panic("sub #204") }
    if !(sub((-10i16), (read 7i16)) == (-17i16)) { panic("sub #205") }
    if !(sub((read (-10i16)), (read 7i16)) == (-17i16)) { panic("sub #206") }
    if !(sub_assign((-10i16), 7i16) == (-17i16)) { panic("sub_assign #207") }
    if !(sub_assign((-10i16), (read 7i16)) == (-17i16)) { panic("sub_assign #208") }
    if !(mul((-10i16), 7i16) == (-70i16)) { panic("mul #209") }
    if !(mul((read (-10i16)), 7i16) == (-70i16)) { panic("mul #210") }
    if !(mul((-10i16), (read 7i16)) == (-70i16)) { panic("mul #211") }
    if !(mul((read (-10i16)), (read 7i16)) == (-70i16)) { panic("mul #212") }
    if !(mul_assign((-10i16), 7i16) == (-70i16)) { panic("mul_assign #213") }
    if !(mul_assign((-10i16), (read 7i16)) == (-70i16)) { panic("mul_assign #214") }
    if !(div((-10i16), 7i16) == (-1i16)) { panic("div #215") }
    if !(div((read (-10i16)), 7i16) == (-1i16)) { panic("div #216") }
    if !(div((-10i16), (read 7i16)) == (-1i16)) { panic("div #217") }
    if !(div((read (-10i16)), (read 7i16)) == (-1i16)) { panic("div #218") }
    if !(div_assign((-10i16), 7i16) == (-1i16)) { panic("div_assign #219") }
    if !(div_assign((-10i16), (read 7i16)) == (-1i16)) { panic("div_assign #220") }
    if !(rem((-10i16), 7i16) == (-3i16)) { panic("rem #221") }
    if !(rem((read (-10i16)), 7i16) == (-3i16)) { panic("rem #222") }
    if !(rem((-10i16), (read 7i16)) == (-3i16)) { panic("rem #223") }
    if !(rem((read (-10i16)), (read 7i16)) == (-3i16)) { panic("rem #224") }
    if !(rem_assign((-10i16), 7i16) == (-3i16)) { panic("rem_assign #225") }
    if !(rem_assign((-10i16), (read 7i16)) == (-3i16)) { panic("rem_assign #226") }
    if !(and((-10i16), 7i16) == 6i16) { panic("and #227") }
    if !(and((read (-10i16)), 7i16) == 6i16) { panic("and #228") }
    if !(and((-10i16), (read 7i16)) == 6i16) { panic("and #229") }
    if !(and((read (-10i16)), (read 7i16)) == 6i16) { panic("and #230") }
    if !(and_assign((-10i16), 7i16) == 6i16) { panic("and_assign #231") }
    if !(and_assign((-10i16), (read 7i16)) == 6i16) { panic("and_assign #232") }
    if !(or((-10i16), 7i16) == (-9i16)) { panic("or #233") }
    if !(or((read (-10i16)), 7i16) == (-9i16)) { panic("or #234") }
    if !(or((-10i16), (read 7i16)) == (-9i16)) { panic("or #235") }
    if !(or((read (-10i16)), (read 7i16)) == (-9i16)) { panic("or #236") }
    if !(or_assign((-10i16), 7i16) == (-9i16)) { panic("or_assign #237") }
    if !(or_assign((-10i16), (read 7i16)) == (-9i16)) { panic("or_assign #238") }
    if !(xor((-10i16), 7i16) == (-15i16)) { panic("xor #239") }
    if !(xor((read (-10i16)), 7i16) == (-15i16)) { panic("xor #240") }
    if !(xor((-10i16), (read 7i16)) == (-15i16)) { panic("xor #241") }
    if !(xor((read (-10i16)), (read 7i16)) == (-15i16)) { panic("xor #242") }
    if !(xor_assign((-10i16), 7i16) == (-15i16)) { panic("xor_assign #243") }
    if !(xor_assign((-10i16), (read 7i16)) == (-15i16)) { panic("xor_assign #244") }
    if !(not((-10i16)) == 9i16) { panic("not #245") }
    if !(not((read (-10i16))) == 9i16) { panic("not #246") }
    if !(neg((-10i16)) == 10i16) { panic("neg #247") }
    if !(neg((read (-10i16))) == 10i16) { panic("neg #248") }
    if !(shl((-10i16), 3i8) == (-80i16)) { panic("shl #249") }
    if !(shr((-10i16), 3i8) == (-2i16)) { panic("shr #250") }
    if !(shl((read (-10i16)), 3i8) == (-80i16)) { panic("shl #251") }
    if !(shr((read (-10i16)), 3i8) == (-2i16)) { panic("shr #252") }
    if !(shl_assign((-10i16), 3i8) == (-80i16)) { panic("shl_assign #253") }
    if !(shr_assign((-10i16), 3i8) == (-2i16)) { panic("shr_assign #254") }
    if !(shl((-10i16), (read 3i8)) == (-80i16)) { panic("shl #255") }
    if !(shr((-10i16), (read 3i8)) == (-2i16)) { panic("shr #256") }
    if !(shl((read (-10i16)), (read 3i8)) == (-80i16)) { panic("shl #257") }
    if !(shr((read (-10i16)), (read 3i8)) == (-2i16)) { panic("shr #258") }
    if !(shl_assign((-10i16), (read 3i8)) == (-80i16)) { panic("shl_assign #259") }
    if !(shr_assign((-10i16), (read 3i8)) == (-2i16)) { panic("shr_assign #260") }
    if !(shl((-10i16), 3i16) == (-80i16)) { panic("shl #261") }
    if !(shr((-10i16), 3i16) == (-2i16)) { panic("shr #262") }
    if !(shl((read (-10i16)), 3i16) == (-80i16)) { panic("shl #263") }
    if !(shr((read (-10i16)), 3i16) == (-2i16)) { panic("shr #264") }
    if !(shl_assign((-10i16), 3i16) == (-80i16)) { panic("shl_assign #265") }
    if !(shr_assign((-10i16), 3i16) == (-2i16)) { panic("shr_assign #266") }
    if !(shl((-10i16), (read 3i16)) == (-80i16)) { panic("shl #267") }
    if !(shr((-10i16), (read 3i16)) == (-2i16)) { panic("shr #268") }
    if !(shl((read (-10i16)), (read 3i16)) == (-80i16)) { panic("shl #269") }
    if !(shr((read (-10i16)), (read 3i16)) == (-2i16)) { panic("shr #270") }
    if !(shl_assign((-10i16), (read 3i16)) == (-80i16)) { panic("shl_assign #271") }
    if !(shr_assign((-10i16), (read 3i16)) == (-2i16)) { panic("shr_assign #272") }
    if !(shl((-10i16), 3i32) == (-80i16)) { panic("shl #273") }
    if !(shr((-10i16), 3i32) == (-2i16)) { panic("shr #274") }
    if !(shl((read (-10i16)), 3i32) == (-80i16)) { panic("shl #275") }
    if !(shr((read (-10i16)), 3i32) == (-2i16)) { panic("shr #276") }
    if !(shl_assign((-10i16), 3i32) == (-80i16)) { panic("shl_assign #277") }
    if !(shr_assign((-10i16), 3i32) == (-2i16)) { panic("shr_assign #278") }
    if !(shl((-10i16), (read 3i32)) == (-80i16)) { panic("shl #279") }
    if !(shr((-10i16), (read 3i32)) == (-2i16)) { panic("shr #280") }
    if !(shl((read (-10i16)), (read 3i32)) == (-80i16)) { panic("shl #281") }
    if !(shr((read (-10i16)), (read 3i32)) == (-2i16)) { panic("shr #282") }
    if !(shl_assign((-10i16), (read 3i32)) == (-80i16)) { panic("shl_assign #283") }
    if !(shr_assign((-10i16), (read 3i32)) == (-2i16)) { panic("shr_assign #284") }
    if !(shl((-10i16), 3i64) == (-80i16)) { panic("shl #285") }
    if !(shr((-10i16), 3i64) == (-2i16)) { panic("shr #286") }
    if !(shl((read (-10i16)), 3i64) == (-80i16)) { panic("shl #287") }
    if !(shr((read (-10i16)), 3i64) == (-2i16)) { panic("shr #288") }
    if !(shl_assign((-10i16), 3i64) == (-80i16)) { panic("shl_assign #289") }
    if !(shr_assign((-10i16), 3i64) == (-2i16)) { panic("shr_assign #290") }
    if !(shl((-10i16), (read 3i64)) == (-80i16)) { panic("shl #291") }
    if !(shr((-10i16), (read 3i64)) == (-2i16)) { panic("shr #292") }
    if !(shl((read (-10i16)), (read 3i64)) == (-80i16)) { panic("shl #293") }
    if !(shr((read (-10i16)), (read 3i64)) == (-2i16)) { panic("shr #294") }
    if !(shl_assign((-10i16), (read 3i64)) == (-80i16)) { panic("shl_assign #295") }
    if !(shr_assign((-10i16), (read 3i64)) == (-2i16)) { panic("shr_assign #296") }
    if !(shl((-10i16), 3i128) == (-80i16)) { panic("shl #297") }
    if !(shr((-10i16), 3i128) == (-2i16)) { panic("shr #298") }
    if !(shl((read (-10i16)), 3i128) == (-80i16)) { panic("shl #299") }
    if !(shr((read (-10i16)), 3i128) == (-2i16)) { panic("shr #300") }
}

fn group2() {
    if !(shl_assign((-10i16), 3i128) == (-80i16)) { panic("shl_assign #301") }
    if !(shr_assign((-10i16), 3i128) == (-2i16)) { panic("shr_assign #302") }
    if !(shl((-10i16), (read 3i128)) == (-80i16)) { panic("shl #303") }
    if !(shr((-10i16), (read 3i128)) == (-2i16)) { panic("shr #304") }
    if !(shl((read (-10i16)), (read 3i128)) == (-80i16)) { panic("shl #305") }
    if !(shr((read (-10i16)), (read 3i128)) == (-2i16)) { panic("shr #306") }
    if !(shl_assign((-10i16), (read 3i128)) == (-80i16)) { panic("shl_assign #307") }
    if !(shr_assign((-10i16), (read 3i128)) == (-2i16)) { panic("shr_assign #308") }
    if !(shl((-10i16), 3isize) == (-80i16)) { panic("shl #309") }
    if !(shr((-10i16), 3isize) == (-2i16)) { panic("shr #310") }
    if !(shl((read (-10i16)), 3isize) == (-80i16)) { panic("shl #311") }
    if !(shr((read (-10i16)), 3isize) == (-2i16)) { panic("shr #312") }
    if !(shl_assign((-10i16), 3isize) == (-80i16)) { panic("shl_assign #313") }
    if !(shr_assign((-10i16), 3isize) == (-2i16)) { panic("shr_assign #314") }
    if !(shl((-10i16), (read 3isize)) == (-80i16)) { panic("shl #315") }
    if !(shr((-10i16), (read 3isize)) == (-2i16)) { panic("shr #316") }
    if !(shl((read (-10i16)), (read 3isize)) == (-80i16)) { panic("shl #317") }
    if !(shr((read (-10i16)), (read 3isize)) == (-2i16)) { panic("shr #318") }
    if !(shl_assign((-10i16), (read 3isize)) == (-80i16)) { panic("shl_assign #319") }
    if !(shr_assign((-10i16), (read 3isize)) == (-2i16)) { panic("shr_assign #320") }
    if !(shl((-10i16), 3u8) == (-80i16)) { panic("shl #321") }
    if !(shr((-10i16), 3u8) == (-2i16)) { panic("shr #322") }
    if !(shl((read (-10i16)), 3u8) == (-80i16)) { panic("shl #323") }
    if !(shr((read (-10i16)), 3u8) == (-2i16)) { panic("shr #324") }
    if !(shl_assign((-10i16), 3u8) == (-80i16)) { panic("shl_assign #325") }
    if !(shr_assign((-10i16), 3u8) == (-2i16)) { panic("shr_assign #326") }
    if !(shl((-10i16), (read 3u8)) == (-80i16)) { panic("shl #327") }
    if !(shr((-10i16), (read 3u8)) == (-2i16)) { panic("shr #328") }
    if !(shl((read (-10i16)), (read 3u8)) == (-80i16)) { panic("shl #329") }
    if !(shr((read (-10i16)), (read 3u8)) == (-2i16)) { panic("shr #330") }
    if !(shl_assign((-10i16), (read 3u8)) == (-80i16)) { panic("shl_assign #331") }
    if !(shr_assign((-10i16), (read 3u8)) == (-2i16)) { panic("shr_assign #332") }
    if !(shl((-10i16), 3u16) == (-80i16)) { panic("shl #333") }
    if !(shr((-10i16), 3u16) == (-2i16)) { panic("shr #334") }
    if !(shl((read (-10i16)), 3u16) == (-80i16)) { panic("shl #335") }
    if !(shr((read (-10i16)), 3u16) == (-2i16)) { panic("shr #336") }
    if !(shl_assign((-10i16), 3u16) == (-80i16)) { panic("shl_assign #337") }
    if !(shr_assign((-10i16), 3u16) == (-2i16)) { panic("shr_assign #338") }
    if !(shl((-10i16), (read 3u16)) == (-80i16)) { panic("shl #339") }
    if !(shr((-10i16), (read 3u16)) == (-2i16)) { panic("shr #340") }
    if !(shl((read (-10i16)), (read 3u16)) == (-80i16)) { panic("shl #341") }
    if !(shr((read (-10i16)), (read 3u16)) == (-2i16)) { panic("shr #342") }
    if !(shl_assign((-10i16), (read 3u16)) == (-80i16)) { panic("shl_assign #343") }
    if !(shr_assign((-10i16), (read 3u16)) == (-2i16)) { panic("shr_assign #344") }
    if !(shl((-10i16), 3u32) == (-80i16)) { panic("shl #345") }
    if !(shr((-10i16), 3u32) == (-2i16)) { panic("shr #346") }
    if !(shl((read (-10i16)), 3u32) == (-80i16)) { panic("shl #347") }
    if !(shr((read (-10i16)), 3u32) == (-2i16)) { panic("shr #348") }
    if !(shl_assign((-10i16), 3u32) == (-80i16)) { panic("shl_assign #349") }
    if !(shr_assign((-10i16), 3u32) == (-2i16)) { panic("shr_assign #350") }
    if !(shl((-10i16), (read 3u32)) == (-80i16)) { panic("shl #351") }
    if !(shr((-10i16), (read 3u32)) == (-2i16)) { panic("shr #352") }
    if !(shl((read (-10i16)), (read 3u32)) == (-80i16)) { panic("shl #353") }
    if !(shr((read (-10i16)), (read 3u32)) == (-2i16)) { panic("shr #354") }
    if !(shl_assign((-10i16), (read 3u32)) == (-80i16)) { panic("shl_assign #355") }
    if !(shr_assign((-10i16), (read 3u32)) == (-2i16)) { panic("shr_assign #356") }
    if !(shl((-10i16), 3u64) == (-80i16)) { panic("shl #357") }
    if !(shr((-10i16), 3u64) == (-2i16)) { panic("shr #358") }
    if !(shl((read (-10i16)), 3u64) == (-80i16)) { panic("shl #359") }
    if !(shr((read (-10i16)), 3u64) == (-2i16)) { panic("shr #360") }
    if !(shl_assign((-10i16), 3u64) == (-80i16)) { panic("shl_assign #361") }
    if !(shr_assign((-10i16), 3u64) == (-2i16)) { panic("shr_assign #362") }
    if !(shl((-10i16), (read 3u64)) == (-80i16)) { panic("shl #363") }
    if !(shr((-10i16), (read 3u64)) == (-2i16)) { panic("shr #364") }
    if !(shl((read (-10i16)), (read 3u64)) == (-80i16)) { panic("shl #365") }
    if !(shr((read (-10i16)), (read 3u64)) == (-2i16)) { panic("shr #366") }
    if !(shl_assign((-10i16), (read 3u64)) == (-80i16)) { panic("shl_assign #367") }
    if !(shr_assign((-10i16), (read 3u64)) == (-2i16)) { panic("shr_assign #368") }
    if !(shl((-10i16), 3u128) == (-80i16)) { panic("shl #369") }
    if !(shr((-10i16), 3u128) == (-2i16)) { panic("shr #370") }
    if !(shl((read (-10i16)), 3u128) == (-80i16)) { panic("shl #371") }
    if !(shr((read (-10i16)), 3u128) == (-2i16)) { panic("shr #372") }
    if !(shl_assign((-10i16), 3u128) == (-80i16)) { panic("shl_assign #373") }
    if !(shr_assign((-10i16), 3u128) == (-2i16)) { panic("shr_assign #374") }
    if !(shl((-10i16), (read 3u128)) == (-80i16)) { panic("shl #375") }
    if !(shr((-10i16), (read 3u128)) == (-2i16)) { panic("shr #376") }
    if !(shl((read (-10i16)), (read 3u128)) == (-80i16)) { panic("shl #377") }
    if !(shr((read (-10i16)), (read 3u128)) == (-2i16)) { panic("shr #378") }
    if !(shl_assign((-10i16), (read 3u128)) == (-80i16)) { panic("shl_assign #379") }
    if !(shr_assign((-10i16), (read 3u128)) == (-2i16)) { panic("shr_assign #380") }
    if !(shl((-10i16), 3usize) == (-80i16)) { panic("shl #381") }
    if !(shr((-10i16), 3usize) == (-2i16)) { panic("shr #382") }
    if !(shl((read (-10i16)), 3usize) == (-80i16)) { panic("shl #383") }
    if !(shr((read (-10i16)), 3usize) == (-2i16)) { panic("shr #384") }
    if !(shl_assign((-10i16), 3usize) == (-80i16)) { panic("shl_assign #385") }
    if !(shr_assign((-10i16), 3usize) == (-2i16)) { panic("shr_assign #386") }
    if !(shl((-10i16), (read 3usize)) == (-80i16)) { panic("shl #387") }
    if !(shr((-10i16), (read 3usize)) == (-2i16)) { panic("shr #388") }
    if !(shl((read (-10i16)), (read 3usize)) == (-80i16)) { panic("shl #389") }
    if !(shr((read (-10i16)), (read 3usize)) == (-2i16)) { panic("shr #390") }
    if !(shl_assign((-10i16), (read 3usize)) == (-80i16)) { panic("shl_assign #391") }
    if !(shr_assign((-10i16), (read 3usize)) == (-2i16)) { panic("shr_assign #392") }
    if !(add((-10i32), 7i32) == (-3i32)) { panic("add #393") }
    if !(add((read (-10i32)), 7i32) == (-3i32)) { panic("add #394") }
    if !(add((-10i32), (read 7i32)) == (-3i32)) { panic("add #395") }
    if !(add((read (-10i32)), (read 7i32)) == (-3i32)) { panic("add #396") }
    if !(add_assign((-10i32), 7i32) == (-3i32)) { panic("add_assign #397") }
    if !(add_assign((-10i32), (read 7i32)) == (-3i32)) { panic("add_assign #398") }
    if !(sub((-10i32), 7i32) == (-17i32)) { panic("sub #399") }
    if !(sub((read (-10i32)), 7i32) == (-17i32)) { panic("sub #400") }
    if !(sub((-10i32), (read 7i32)) == (-17i32)) { panic("sub #401") }
    if !(sub((read (-10i32)), (read 7i32)) == (-17i32)) { panic("sub #402") }
    if !(sub_assign((-10i32), 7i32) == (-17i32)) { panic("sub_assign #403") }
    if !(sub_assign((-10i32), (read 7i32)) == (-17i32)) { panic("sub_assign #404") }
    if !(mul((-10i32), 7i32) == (-70i32)) { panic("mul #405") }
    if !(mul((read (-10i32)), 7i32) == (-70i32)) { panic("mul #406") }
    if !(mul((-10i32), (read 7i32)) == (-70i32)) { panic("mul #407") }
    if !(mul((read (-10i32)), (read 7i32)) == (-70i32)) { panic("mul #408") }
    if !(mul_assign((-10i32), 7i32) == (-70i32)) { panic("mul_assign #409") }
    if !(mul_assign((-10i32), (read 7i32)) == (-70i32)) { panic("mul_assign #410") }
    if !(div((-10i32), 7i32) == (-1i32)) { panic("div #411") }
    if !(div((read (-10i32)), 7i32) == (-1i32)) { panic("div #412") }
    if !(div((-10i32), (read 7i32)) == (-1i32)) { panic("div #413") }
    if !(div((read (-10i32)), (read 7i32)) == (-1i32)) { panic("div #414") }
    if !(div_assign((-10i32), 7i32) == (-1i32)) { panic("div_assign #415") }
    if !(div_assign((-10i32), (read 7i32)) == (-1i32)) { panic("div_assign #416") }
    if !(rem((-10i32), 7i32) == (-3i32)) { panic("rem #417") }
    if !(rem((read (-10i32)), 7i32) == (-3i32)) { panic("rem #418") }
    if !(rem((-10i32), (read 7i32)) == (-3i32)) { panic("rem #419") }
    if !(rem((read (-10i32)), (read 7i32)) == (-3i32)) { panic("rem #420") }
    if !(rem_assign((-10i32), 7i32) == (-3i32)) { panic("rem_assign #421") }
    if !(rem_assign((-10i32), (read 7i32)) == (-3i32)) { panic("rem_assign #422") }
    if !(and((-10i32), 7i32) == 6i32) { panic("and #423") }
    if !(and((read (-10i32)), 7i32) == 6i32) { panic("and #424") }
    if !(and((-10i32), (read 7i32)) == 6i32) { panic("and #425") }
    if !(and((read (-10i32)), (read 7i32)) == 6i32) { panic("and #426") }
    if !(and_assign((-10i32), 7i32) == 6i32) { panic("and_assign #427") }
    if !(and_assign((-10i32), (read 7i32)) == 6i32) { panic("and_assign #428") }
    if !(or((-10i32), 7i32) == (-9i32)) { panic("or #429") }
    if !(or((read (-10i32)), 7i32) == (-9i32)) { panic("or #430") }
    if !(or((-10i32), (read 7i32)) == (-9i32)) { panic("or #431") }
    if !(or((read (-10i32)), (read 7i32)) == (-9i32)) { panic("or #432") }
    if !(or_assign((-10i32), 7i32) == (-9i32)) { panic("or_assign #433") }
    if !(or_assign((-10i32), (read 7i32)) == (-9i32)) { panic("or_assign #434") }
    if !(xor((-10i32), 7i32) == (-15i32)) { panic("xor #435") }
    if !(xor((read (-10i32)), 7i32) == (-15i32)) { panic("xor #436") }
    if !(xor((-10i32), (read 7i32)) == (-15i32)) { panic("xor #437") }
    if !(xor((read (-10i32)), (read 7i32)) == (-15i32)) { panic("xor #438") }
    if !(xor_assign((-10i32), 7i32) == (-15i32)) { panic("xor_assign #439") }
    if !(xor_assign((-10i32), (read 7i32)) == (-15i32)) { panic("xor_assign #440") }
    if !(not((-10i32)) == 9i32) { panic("not #441") }
    if !(not((read (-10i32))) == 9i32) { panic("not #442") }
    if !(neg((-10i32)) == 10i32) { panic("neg #443") }
    if !(neg((read (-10i32))) == 10i32) { panic("neg #444") }
    if !(shl((-10i32), 3i8) == (-80i32)) { panic("shl #445") }
    if !(shr((-10i32), 3i8) == (-2i32)) { panic("shr #446") }
    if !(shl((read (-10i32)), 3i8) == (-80i32)) { panic("shl #447") }
    if !(shr((read (-10i32)), 3i8) == (-2i32)) { panic("shr #448") }
    if !(shl_assign((-10i32), 3i8) == (-80i32)) { panic("shl_assign #449") }
    if !(shr_assign((-10i32), 3i8) == (-2i32)) { panic("shr_assign #450") }
}

fn group3() {
    if !(shl((-10i32), (read 3i8)) == (-80i32)) { panic("shl #451") }
    if !(shr((-10i32), (read 3i8)) == (-2i32)) { panic("shr #452") }
    if !(shl((read (-10i32)), (read 3i8)) == (-80i32)) { panic("shl #453") }
    if !(shr((read (-10i32)), (read 3i8)) == (-2i32)) { panic("shr #454") }
    if !(shl_assign((-10i32), (read 3i8)) == (-80i32)) { panic("shl_assign #455") }
    if !(shr_assign((-10i32), (read 3i8)) == (-2i32)) { panic("shr_assign #456") }
    if !(shl((-10i32), 3i16) == (-80i32)) { panic("shl #457") }
    if !(shr((-10i32), 3i16) == (-2i32)) { panic("shr #458") }
    if !(shl((read (-10i32)), 3i16) == (-80i32)) { panic("shl #459") }
    if !(shr((read (-10i32)), 3i16) == (-2i32)) { panic("shr #460") }
    if !(shl_assign((-10i32), 3i16) == (-80i32)) { panic("shl_assign #461") }
    if !(shr_assign((-10i32), 3i16) == (-2i32)) { panic("shr_assign #462") }
    if !(shl((-10i32), (read 3i16)) == (-80i32)) { panic("shl #463") }
    if !(shr((-10i32), (read 3i16)) == (-2i32)) { panic("shr #464") }
    if !(shl((read (-10i32)), (read 3i16)) == (-80i32)) { panic("shl #465") }
    if !(shr((read (-10i32)), (read 3i16)) == (-2i32)) { panic("shr #466") }
    if !(shl_assign((-10i32), (read 3i16)) == (-80i32)) { panic("shl_assign #467") }
    if !(shr_assign((-10i32), (read 3i16)) == (-2i32)) { panic("shr_assign #468") }
    if !(shl((-10i32), 3i32) == (-80i32)) { panic("shl #469") }
    if !(shr((-10i32), 3i32) == (-2i32)) { panic("shr #470") }
    if !(shl((read (-10i32)), 3i32) == (-80i32)) { panic("shl #471") }
    if !(shr((read (-10i32)), 3i32) == (-2i32)) { panic("shr #472") }
    if !(shl_assign((-10i32), 3i32) == (-80i32)) { panic("shl_assign #473") }
    if !(shr_assign((-10i32), 3i32) == (-2i32)) { panic("shr_assign #474") }
    if !(shl((-10i32), (read 3i32)) == (-80i32)) { panic("shl #475") }
    if !(shr((-10i32), (read 3i32)) == (-2i32)) { panic("shr #476") }
    if !(shl((read (-10i32)), (read 3i32)) == (-80i32)) { panic("shl #477") }
    if !(shr((read (-10i32)), (read 3i32)) == (-2i32)) { panic("shr #478") }
    if !(shl_assign((-10i32), (read 3i32)) == (-80i32)) { panic("shl_assign #479") }
    if !(shr_assign((-10i32), (read 3i32)) == (-2i32)) { panic("shr_assign #480") }
    if !(shl((-10i32), 3i64) == (-80i32)) { panic("shl #481") }
    if !(shr((-10i32), 3i64) == (-2i32)) { panic("shr #482") }
    if !(shl((read (-10i32)), 3i64) == (-80i32)) { panic("shl #483") }
    if !(shr((read (-10i32)), 3i64) == (-2i32)) { panic("shr #484") }
    if !(shl_assign((-10i32), 3i64) == (-80i32)) { panic("shl_assign #485") }
    if !(shr_assign((-10i32), 3i64) == (-2i32)) { panic("shr_assign #486") }
    if !(shl((-10i32), (read 3i64)) == (-80i32)) { panic("shl #487") }
    if !(shr((-10i32), (read 3i64)) == (-2i32)) { panic("shr #488") }
    if !(shl((read (-10i32)), (read 3i64)) == (-80i32)) { panic("shl #489") }
    if !(shr((read (-10i32)), (read 3i64)) == (-2i32)) { panic("shr #490") }
    if !(shl_assign((-10i32), (read 3i64)) == (-80i32)) { panic("shl_assign #491") }
    if !(shr_assign((-10i32), (read 3i64)) == (-2i32)) { panic("shr_assign #492") }
    if !(shl((-10i32), 3i128) == (-80i32)) { panic("shl #493") }
    if !(shr((-10i32), 3i128) == (-2i32)) { panic("shr #494") }
    if !(shl((read (-10i32)), 3i128) == (-80i32)) { panic("shl #495") }
    if !(shr((read (-10i32)), 3i128) == (-2i32)) { panic("shr #496") }
    if !(shl_assign((-10i32), 3i128) == (-80i32)) { panic("shl_assign #497") }
    if !(shr_assign((-10i32), 3i128) == (-2i32)) { panic("shr_assign #498") }
    if !(shl((-10i32), (read 3i128)) == (-80i32)) { panic("shl #499") }
    if !(shr((-10i32), (read 3i128)) == (-2i32)) { panic("shr #500") }
    if !(shl((read (-10i32)), (read 3i128)) == (-80i32)) { panic("shl #501") }
    if !(shr((read (-10i32)), (read 3i128)) == (-2i32)) { panic("shr #502") }
    if !(shl_assign((-10i32), (read 3i128)) == (-80i32)) { panic("shl_assign #503") }
    if !(shr_assign((-10i32), (read 3i128)) == (-2i32)) { panic("shr_assign #504") }
    if !(shl((-10i32), 3isize) == (-80i32)) { panic("shl #505") }
    if !(shr((-10i32), 3isize) == (-2i32)) { panic("shr #506") }
    if !(shl((read (-10i32)), 3isize) == (-80i32)) { panic("shl #507") }
    if !(shr((read (-10i32)), 3isize) == (-2i32)) { panic("shr #508") }
    if !(shl_assign((-10i32), 3isize) == (-80i32)) { panic("shl_assign #509") }
    if !(shr_assign((-10i32), 3isize) == (-2i32)) { panic("shr_assign #510") }
    if !(shl((-10i32), (read 3isize)) == (-80i32)) { panic("shl #511") }
    if !(shr((-10i32), (read 3isize)) == (-2i32)) { panic("shr #512") }
    if !(shl((read (-10i32)), (read 3isize)) == (-80i32)) { panic("shl #513") }
    if !(shr((read (-10i32)), (read 3isize)) == (-2i32)) { panic("shr #514") }
    if !(shl_assign((-10i32), (read 3isize)) == (-80i32)) { panic("shl_assign #515") }
    if !(shr_assign((-10i32), (read 3isize)) == (-2i32)) { panic("shr_assign #516") }
    if !(shl((-10i32), 3u8) == (-80i32)) { panic("shl #517") }
    if !(shr((-10i32), 3u8) == (-2i32)) { panic("shr #518") }
    if !(shl((read (-10i32)), 3u8) == (-80i32)) { panic("shl #519") }
    if !(shr((read (-10i32)), 3u8) == (-2i32)) { panic("shr #520") }
    if !(shl_assign((-10i32), 3u8) == (-80i32)) { panic("shl_assign #521") }
    if !(shr_assign((-10i32), 3u8) == (-2i32)) { panic("shr_assign #522") }
    if !(shl((-10i32), (read 3u8)) == (-80i32)) { panic("shl #523") }
    if !(shr((-10i32), (read 3u8)) == (-2i32)) { panic("shr #524") }
    if !(shl((read (-10i32)), (read 3u8)) == (-80i32)) { panic("shl #525") }
    if !(shr((read (-10i32)), (read 3u8)) == (-2i32)) { panic("shr #526") }
    if !(shl_assign((-10i32), (read 3u8)) == (-80i32)) { panic("shl_assign #527") }
    if !(shr_assign((-10i32), (read 3u8)) == (-2i32)) { panic("shr_assign #528") }
    if !(shl((-10i32), 3u16) == (-80i32)) { panic("shl #529") }
    if !(shr((-10i32), 3u16) == (-2i32)) { panic("shr #530") }
    if !(shl((read (-10i32)), 3u16) == (-80i32)) { panic("shl #531") }
    if !(shr((read (-10i32)), 3u16) == (-2i32)) { panic("shr #532") }
    if !(shl_assign((-10i32), 3u16) == (-80i32)) { panic("shl_assign #533") }
    if !(shr_assign((-10i32), 3u16) == (-2i32)) { panic("shr_assign #534") }
    if !(shl((-10i32), (read 3u16)) == (-80i32)) { panic("shl #535") }
    if !(shr((-10i32), (read 3u16)) == (-2i32)) { panic("shr #536") }
    if !(shl((read (-10i32)), (read 3u16)) == (-80i32)) { panic("shl #537") }
    if !(shr((read (-10i32)), (read 3u16)) == (-2i32)) { panic("shr #538") }
    if !(shl_assign((-10i32), (read 3u16)) == (-80i32)) { panic("shl_assign #539") }
    if !(shr_assign((-10i32), (read 3u16)) == (-2i32)) { panic("shr_assign #540") }
    if !(shl((-10i32), 3u32) == (-80i32)) { panic("shl #541") }
    if !(shr((-10i32), 3u32) == (-2i32)) { panic("shr #542") }
    if !(shl((read (-10i32)), 3u32) == (-80i32)) { panic("shl #543") }
    if !(shr((read (-10i32)), 3u32) == (-2i32)) { panic("shr #544") }
    if !(shl_assign((-10i32), 3u32) == (-80i32)) { panic("shl_assign #545") }
    if !(shr_assign((-10i32), 3u32) == (-2i32)) { panic("shr_assign #546") }
    if !(shl((-10i32), (read 3u32)) == (-80i32)) { panic("shl #547") }
    if !(shr((-10i32), (read 3u32)) == (-2i32)) { panic("shr #548") }
    if !(shl((read (-10i32)), (read 3u32)) == (-80i32)) { panic("shl #549") }
    if !(shr((read (-10i32)), (read 3u32)) == (-2i32)) { panic("shr #550") }
    if !(shl_assign((-10i32), (read 3u32)) == (-80i32)) { panic("shl_assign #551") }
    if !(shr_assign((-10i32), (read 3u32)) == (-2i32)) { panic("shr_assign #552") }
    if !(shl((-10i32), 3u64) == (-80i32)) { panic("shl #553") }
    if !(shr((-10i32), 3u64) == (-2i32)) { panic("shr #554") }
    if !(shl((read (-10i32)), 3u64) == (-80i32)) { panic("shl #555") }
    if !(shr((read (-10i32)), 3u64) == (-2i32)) { panic("shr #556") }
    if !(shl_assign((-10i32), 3u64) == (-80i32)) { panic("shl_assign #557") }
    if !(shr_assign((-10i32), 3u64) == (-2i32)) { panic("shr_assign #558") }
    if !(shl((-10i32), (read 3u64)) == (-80i32)) { panic("shl #559") }
    if !(shr((-10i32), (read 3u64)) == (-2i32)) { panic("shr #560") }
    if !(shl((read (-10i32)), (read 3u64)) == (-80i32)) { panic("shl #561") }
    if !(shr((read (-10i32)), (read 3u64)) == (-2i32)) { panic("shr #562") }
    if !(shl_assign((-10i32), (read 3u64)) == (-80i32)) { panic("shl_assign #563") }
    if !(shr_assign((-10i32), (read 3u64)) == (-2i32)) { panic("shr_assign #564") }
    if !(shl((-10i32), 3u128) == (-80i32)) { panic("shl #565") }
    if !(shr((-10i32), 3u128) == (-2i32)) { panic("shr #566") }
    if !(shl((read (-10i32)), 3u128) == (-80i32)) { panic("shl #567") }
    if !(shr((read (-10i32)), 3u128) == (-2i32)) { panic("shr #568") }
    if !(shl_assign((-10i32), 3u128) == (-80i32)) { panic("shl_assign #569") }
    if !(shr_assign((-10i32), 3u128) == (-2i32)) { panic("shr_assign #570") }
    if !(shl((-10i32), (read 3u128)) == (-80i32)) { panic("shl #571") }
    if !(shr((-10i32), (read 3u128)) == (-2i32)) { panic("shr #572") }
    if !(shl((read (-10i32)), (read 3u128)) == (-80i32)) { panic("shl #573") }
    if !(shr((read (-10i32)), (read 3u128)) == (-2i32)) { panic("shr #574") }
    if !(shl_assign((-10i32), (read 3u128)) == (-80i32)) { panic("shl_assign #575") }
    if !(shr_assign((-10i32), (read 3u128)) == (-2i32)) { panic("shr_assign #576") }
    if !(shl((-10i32), 3usize) == (-80i32)) { panic("shl #577") }
    if !(shr((-10i32), 3usize) == (-2i32)) { panic("shr #578") }
    if !(shl((read (-10i32)), 3usize) == (-80i32)) { panic("shl #579") }
    if !(shr((read (-10i32)), 3usize) == (-2i32)) { panic("shr #580") }
    if !(shl_assign((-10i32), 3usize) == (-80i32)) { panic("shl_assign #581") }
    if !(shr_assign((-10i32), 3usize) == (-2i32)) { panic("shr_assign #582") }
    if !(shl((-10i32), (read 3usize)) == (-80i32)) { panic("shl #583") }
    if !(shr((-10i32), (read 3usize)) == (-2i32)) { panic("shr #584") }
    if !(shl((read (-10i32)), (read 3usize)) == (-80i32)) { panic("shl #585") }
    if !(shr((read (-10i32)), (read 3usize)) == (-2i32)) { panic("shr #586") }
    if !(shl_assign((-10i32), (read 3usize)) == (-80i32)) { panic("shl_assign #587") }
    if !(shr_assign((-10i32), (read 3usize)) == (-2i32)) { panic("shr_assign #588") }
    if !(add((-10i64), 7i64) == (-3i64)) { panic("add #589") }
    if !(add((read (-10i64)), 7i64) == (-3i64)) { panic("add #590") }
    if !(add((-10i64), (read 7i64)) == (-3i64)) { panic("add #591") }
    if !(add((read (-10i64)), (read 7i64)) == (-3i64)) { panic("add #592") }
    if !(add_assign((-10i64), 7i64) == (-3i64)) { panic("add_assign #593") }
    if !(add_assign((-10i64), (read 7i64)) == (-3i64)) { panic("add_assign #594") }
    if !(sub((-10i64), 7i64) == (-17i64)) { panic("sub #595") }
    if !(sub((read (-10i64)), 7i64) == (-17i64)) { panic("sub #596") }
    if !(sub((-10i64), (read 7i64)) == (-17i64)) { panic("sub #597") }
    if !(sub((read (-10i64)), (read 7i64)) == (-17i64)) { panic("sub #598") }
    if !(sub_assign((-10i64), 7i64) == (-17i64)) { panic("sub_assign #599") }
    if !(sub_assign((-10i64), (read 7i64)) == (-17i64)) { panic("sub_assign #600") }
}

fn group4() {
    if !(mul((-10i64), 7i64) == (-70i64)) { panic("mul #601") }
    if !(mul((read (-10i64)), 7i64) == (-70i64)) { panic("mul #602") }
    if !(mul((-10i64), (read 7i64)) == (-70i64)) { panic("mul #603") }
    if !(mul((read (-10i64)), (read 7i64)) == (-70i64)) { panic("mul #604") }
    if !(mul_assign((-10i64), 7i64) == (-70i64)) { panic("mul_assign #605") }
    if !(mul_assign((-10i64), (read 7i64)) == (-70i64)) { panic("mul_assign #606") }
    if !(div((-10i64), 7i64) == (-1i64)) { panic("div #607") }
    if !(div((read (-10i64)), 7i64) == (-1i64)) { panic("div #608") }
    if !(div((-10i64), (read 7i64)) == (-1i64)) { panic("div #609") }
    if !(div((read (-10i64)), (read 7i64)) == (-1i64)) { panic("div #610") }
    if !(div_assign((-10i64), 7i64) == (-1i64)) { panic("div_assign #611") }
    if !(div_assign((-10i64), (read 7i64)) == (-1i64)) { panic("div_assign #612") }
    if !(rem((-10i64), 7i64) == (-3i64)) { panic("rem #613") }
    if !(rem((read (-10i64)), 7i64) == (-3i64)) { panic("rem #614") }
    if !(rem((-10i64), (read 7i64)) == (-3i64)) { panic("rem #615") }
    if !(rem((read (-10i64)), (read 7i64)) == (-3i64)) { panic("rem #616") }
    if !(rem_assign((-10i64), 7i64) == (-3i64)) { panic("rem_assign #617") }
    if !(rem_assign((-10i64), (read 7i64)) == (-3i64)) { panic("rem_assign #618") }
    if !(and((-10i64), 7i64) == 6i64) { panic("and #619") }
    if !(and((read (-10i64)), 7i64) == 6i64) { panic("and #620") }
    if !(and((-10i64), (read 7i64)) == 6i64) { panic("and #621") }
    if !(and((read (-10i64)), (read 7i64)) == 6i64) { panic("and #622") }
    if !(and_assign((-10i64), 7i64) == 6i64) { panic("and_assign #623") }
    if !(and_assign((-10i64), (read 7i64)) == 6i64) { panic("and_assign #624") }
    if !(or((-10i64), 7i64) == (-9i64)) { panic("or #625") }
    if !(or((read (-10i64)), 7i64) == (-9i64)) { panic("or #626") }
    if !(or((-10i64), (read 7i64)) == (-9i64)) { panic("or #627") }
    if !(or((read (-10i64)), (read 7i64)) == (-9i64)) { panic("or #628") }
    if !(or_assign((-10i64), 7i64) == (-9i64)) { panic("or_assign #629") }
    if !(or_assign((-10i64), (read 7i64)) == (-9i64)) { panic("or_assign #630") }
    if !(xor((-10i64), 7i64) == (-15i64)) { panic("xor #631") }
    if !(xor((read (-10i64)), 7i64) == (-15i64)) { panic("xor #632") }
    if !(xor((-10i64), (read 7i64)) == (-15i64)) { panic("xor #633") }
    if !(xor((read (-10i64)), (read 7i64)) == (-15i64)) { panic("xor #634") }
    if !(xor_assign((-10i64), 7i64) == (-15i64)) { panic("xor_assign #635") }
    if !(xor_assign((-10i64), (read 7i64)) == (-15i64)) { panic("xor_assign #636") }
    if !(not((-10i64)) == 9i64) { panic("not #637") }
    if !(not((read (-10i64))) == 9i64) { panic("not #638") }
    if !(neg((-10i64)) == 10i64) { panic("neg #639") }
    if !(neg((read (-10i64))) == 10i64) { panic("neg #640") }
    if !(shl((-10i64), 3i8) == (-80i64)) { panic("shl #641") }
    if !(shr((-10i64), 3i8) == (-2i64)) { panic("shr #642") }
    if !(shl((read (-10i64)), 3i8) == (-80i64)) { panic("shl #643") }
    if !(shr((read (-10i64)), 3i8) == (-2i64)) { panic("shr #644") }
    if !(shl_assign((-10i64), 3i8) == (-80i64)) { panic("shl_assign #645") }
    if !(shr_assign((-10i64), 3i8) == (-2i64)) { panic("shr_assign #646") }
    if !(shl((-10i64), (read 3i8)) == (-80i64)) { panic("shl #647") }
    if !(shr((-10i64), (read 3i8)) == (-2i64)) { panic("shr #648") }
    if !(shl((read (-10i64)), (read 3i8)) == (-80i64)) { panic("shl #649") }
    if !(shr((read (-10i64)), (read 3i8)) == (-2i64)) { panic("shr #650") }
    if !(shl_assign((-10i64), (read 3i8)) == (-80i64)) { panic("shl_assign #651") }
    if !(shr_assign((-10i64), (read 3i8)) == (-2i64)) { panic("shr_assign #652") }
    if !(shl((-10i64), 3i16) == (-80i64)) { panic("shl #653") }
    if !(shr((-10i64), 3i16) == (-2i64)) { panic("shr #654") }
    if !(shl((read (-10i64)), 3i16) == (-80i64)) { panic("shl #655") }
    if !(shr((read (-10i64)), 3i16) == (-2i64)) { panic("shr #656") }
    if !(shl_assign((-10i64), 3i16) == (-80i64)) { panic("shl_assign #657") }
    if !(shr_assign((-10i64), 3i16) == (-2i64)) { panic("shr_assign #658") }
    if !(shl((-10i64), (read 3i16)) == (-80i64)) { panic("shl #659") }
    if !(shr((-10i64), (read 3i16)) == (-2i64)) { panic("shr #660") }
    if !(shl((read (-10i64)), (read 3i16)) == (-80i64)) { panic("shl #661") }
    if !(shr((read (-10i64)), (read 3i16)) == (-2i64)) { panic("shr #662") }
    if !(shl_assign((-10i64), (read 3i16)) == (-80i64)) { panic("shl_assign #663") }
    if !(shr_assign((-10i64), (read 3i16)) == (-2i64)) { panic("shr_assign #664") }
    if !(shl((-10i64), 3i32) == (-80i64)) { panic("shl #665") }
    if !(shr((-10i64), 3i32) == (-2i64)) { panic("shr #666") }
    if !(shl((read (-10i64)), 3i32) == (-80i64)) { panic("shl #667") }
    if !(shr((read (-10i64)), 3i32) == (-2i64)) { panic("shr #668") }
    if !(shl_assign((-10i64), 3i32) == (-80i64)) { panic("shl_assign #669") }
    if !(shr_assign((-10i64), 3i32) == (-2i64)) { panic("shr_assign #670") }
    if !(shl((-10i64), (read 3i32)) == (-80i64)) { panic("shl #671") }
    if !(shr((-10i64), (read 3i32)) == (-2i64)) { panic("shr #672") }
    if !(shl((read (-10i64)), (read 3i32)) == (-80i64)) { panic("shl #673") }
    if !(shr((read (-10i64)), (read 3i32)) == (-2i64)) { panic("shr #674") }
    if !(shl_assign((-10i64), (read 3i32)) == (-80i64)) { panic("shl_assign #675") }
    if !(shr_assign((-10i64), (read 3i32)) == (-2i64)) { panic("shr_assign #676") }
    if !(shl((-10i64), 3i64) == (-80i64)) { panic("shl #677") }
    if !(shr((-10i64), 3i64) == (-2i64)) { panic("shr #678") }
    if !(shl((read (-10i64)), 3i64) == (-80i64)) { panic("shl #679") }
    if !(shr((read (-10i64)), 3i64) == (-2i64)) { panic("shr #680") }
    if !(shl_assign((-10i64), 3i64) == (-80i64)) { panic("shl_assign #681") }
    if !(shr_assign((-10i64), 3i64) == (-2i64)) { panic("shr_assign #682") }
    if !(shl((-10i64), (read 3i64)) == (-80i64)) { panic("shl #683") }
    if !(shr((-10i64), (read 3i64)) == (-2i64)) { panic("shr #684") }
    if !(shl((read (-10i64)), (read 3i64)) == (-80i64)) { panic("shl #685") }
    if !(shr((read (-10i64)), (read 3i64)) == (-2i64)) { panic("shr #686") }
    if !(shl_assign((-10i64), (read 3i64)) == (-80i64)) { panic("shl_assign #687") }
    if !(shr_assign((-10i64), (read 3i64)) == (-2i64)) { panic("shr_assign #688") }
    if !(shl((-10i64), 3i128) == (-80i64)) { panic("shl #689") }
    if !(shr((-10i64), 3i128) == (-2i64)) { panic("shr #690") }
    if !(shl((read (-10i64)), 3i128) == (-80i64)) { panic("shl #691") }
    if !(shr((read (-10i64)), 3i128) == (-2i64)) { panic("shr #692") }
    if !(shl_assign((-10i64), 3i128) == (-80i64)) { panic("shl_assign #693") }
    if !(shr_assign((-10i64), 3i128) == (-2i64)) { panic("shr_assign #694") }
    if !(shl((-10i64), (read 3i128)) == (-80i64)) { panic("shl #695") }
    if !(shr((-10i64), (read 3i128)) == (-2i64)) { panic("shr #696") }
    if !(shl((read (-10i64)), (read 3i128)) == (-80i64)) { panic("shl #697") }
    if !(shr((read (-10i64)), (read 3i128)) == (-2i64)) { panic("shr #698") }
    if !(shl_assign((-10i64), (read 3i128)) == (-80i64)) { panic("shl_assign #699") }
    if !(shr_assign((-10i64), (read 3i128)) == (-2i64)) { panic("shr_assign #700") }
    if !(shl((-10i64), 3isize) == (-80i64)) { panic("shl #701") }
    if !(shr((-10i64), 3isize) == (-2i64)) { panic("shr #702") }
    if !(shl((read (-10i64)), 3isize) == (-80i64)) { panic("shl #703") }
    if !(shr((read (-10i64)), 3isize) == (-2i64)) { panic("shr #704") }
    if !(shl_assign((-10i64), 3isize) == (-80i64)) { panic("shl_assign #705") }
    if !(shr_assign((-10i64), 3isize) == (-2i64)) { panic("shr_assign #706") }
    if !(shl((-10i64), (read 3isize)) == (-80i64)) { panic("shl #707") }
    if !(shr((-10i64), (read 3isize)) == (-2i64)) { panic("shr #708") }
    if !(shl((read (-10i64)), (read 3isize)) == (-80i64)) { panic("shl #709") }
    if !(shr((read (-10i64)), (read 3isize)) == (-2i64)) { panic("shr #710") }
    if !(shl_assign((-10i64), (read 3isize)) == (-80i64)) { panic("shl_assign #711") }
    if !(shr_assign((-10i64), (read 3isize)) == (-2i64)) { panic("shr_assign #712") }
    if !(shl((-10i64), 3u8) == (-80i64)) { panic("shl #713") }
    if !(shr((-10i64), 3u8) == (-2i64)) { panic("shr #714") }
    if !(shl((read (-10i64)), 3u8) == (-80i64)) { panic("shl #715") }
    if !(shr((read (-10i64)), 3u8) == (-2i64)) { panic("shr #716") }
    if !(shl_assign((-10i64), 3u8) == (-80i64)) { panic("shl_assign #717") }
    if !(shr_assign((-10i64), 3u8) == (-2i64)) { panic("shr_assign #718") }
    if !(shl((-10i64), (read 3u8)) == (-80i64)) { panic("shl #719") }
    if !(shr((-10i64), (read 3u8)) == (-2i64)) { panic("shr #720") }
    if !(shl((read (-10i64)), (read 3u8)) == (-80i64)) { panic("shl #721") }
    if !(shr((read (-10i64)), (read 3u8)) == (-2i64)) { panic("shr #722") }
    if !(shl_assign((-10i64), (read 3u8)) == (-80i64)) { panic("shl_assign #723") }
    if !(shr_assign((-10i64), (read 3u8)) == (-2i64)) { panic("shr_assign #724") }
    if !(shl((-10i64), 3u16) == (-80i64)) { panic("shl #725") }
    if !(shr((-10i64), 3u16) == (-2i64)) { panic("shr #726") }
    if !(shl((read (-10i64)), 3u16) == (-80i64)) { panic("shl #727") }
    if !(shr((read (-10i64)), 3u16) == (-2i64)) { panic("shr #728") }
    if !(shl_assign((-10i64), 3u16) == (-80i64)) { panic("shl_assign #729") }
    if !(shr_assign((-10i64), 3u16) == (-2i64)) { panic("shr_assign #730") }
    if !(shl((-10i64), (read 3u16)) == (-80i64)) { panic("shl #731") }
    if !(shr((-10i64), (read 3u16)) == (-2i64)) { panic("shr #732") }
    if !(shl((read (-10i64)), (read 3u16)) == (-80i64)) { panic("shl #733") }
    if !(shr((read (-10i64)), (read 3u16)) == (-2i64)) { panic("shr #734") }
    if !(shl_assign((-10i64), (read 3u16)) == (-80i64)) { panic("shl_assign #735") }
    if !(shr_assign((-10i64), (read 3u16)) == (-2i64)) { panic("shr_assign #736") }
    if !(shl((-10i64), 3u32) == (-80i64)) { panic("shl #737") }
    if !(shr((-10i64), 3u32) == (-2i64)) { panic("shr #738") }
    if !(shl((read (-10i64)), 3u32) == (-80i64)) { panic("shl #739") }
    if !(shr((read (-10i64)), 3u32) == (-2i64)) { panic("shr #740") }
    if !(shl_assign((-10i64), 3u32) == (-80i64)) { panic("shl_assign #741") }
    if !(shr_assign((-10i64), 3u32) == (-2i64)) { panic("shr_assign #742") }
    if !(shl((-10i64), (read 3u32)) == (-80i64)) { panic("shl #743") }
    if !(shr((-10i64), (read 3u32)) == (-2i64)) { panic("shr #744") }
    if !(shl((read (-10i64)), (read 3u32)) == (-80i64)) { panic("shl #745") }
    if !(shr((read (-10i64)), (read 3u32)) == (-2i64)) { panic("shr #746") }
    if !(shl_assign((-10i64), (read 3u32)) == (-80i64)) { panic("shl_assign #747") }
    if !(shr_assign((-10i64), (read 3u32)) == (-2i64)) { panic("shr_assign #748") }
    if !(shl((-10i64), 3u64) == (-80i64)) { panic("shl #749") }
    if !(shr((-10i64), 3u64) == (-2i64)) { panic("shr #750") }
}

fn group5() {
    if !(shl((read (-10i64)), 3u64) == (-80i64)) { panic("shl #751") }
    if !(shr((read (-10i64)), 3u64) == (-2i64)) { panic("shr #752") }
    if !(shl_assign((-10i64), 3u64) == (-80i64)) { panic("shl_assign #753") }
    if !(shr_assign((-10i64), 3u64) == (-2i64)) { panic("shr_assign #754") }
    if !(shl((-10i64), (read 3u64)) == (-80i64)) { panic("shl #755") }
    if !(shr((-10i64), (read 3u64)) == (-2i64)) { panic("shr #756") }
    if !(shl((read (-10i64)), (read 3u64)) == (-80i64)) { panic("shl #757") }
    if !(shr((read (-10i64)), (read 3u64)) == (-2i64)) { panic("shr #758") }
    if !(shl_assign((-10i64), (read 3u64)) == (-80i64)) { panic("shl_assign #759") }
    if !(shr_assign((-10i64), (read 3u64)) == (-2i64)) { panic("shr_assign #760") }
    if !(shl((-10i64), 3u128) == (-80i64)) { panic("shl #761") }
    if !(shr((-10i64), 3u128) == (-2i64)) { panic("shr #762") }
    if !(shl((read (-10i64)), 3u128) == (-80i64)) { panic("shl #763") }
    if !(shr((read (-10i64)), 3u128) == (-2i64)) { panic("shr #764") }
    if !(shl_assign((-10i64), 3u128) == (-80i64)) { panic("shl_assign #765") }
    if !(shr_assign((-10i64), 3u128) == (-2i64)) { panic("shr_assign #766") }
    if !(shl((-10i64), (read 3u128)) == (-80i64)) { panic("shl #767") }
    if !(shr((-10i64), (read 3u128)) == (-2i64)) { panic("shr #768") }
    if !(shl((read (-10i64)), (read 3u128)) == (-80i64)) { panic("shl #769") }
    if !(shr((read (-10i64)), (read 3u128)) == (-2i64)) { panic("shr #770") }
    if !(shl_assign((-10i64), (read 3u128)) == (-80i64)) { panic("shl_assign #771") }
    if !(shr_assign((-10i64), (read 3u128)) == (-2i64)) { panic("shr_assign #772") }
    if !(shl((-10i64), 3usize) == (-80i64)) { panic("shl #773") }
    if !(shr((-10i64), 3usize) == (-2i64)) { panic("shr #774") }
    if !(shl((read (-10i64)), 3usize) == (-80i64)) { panic("shl #775") }
    if !(shr((read (-10i64)), 3usize) == (-2i64)) { panic("shr #776") }
    if !(shl_assign((-10i64), 3usize) == (-80i64)) { panic("shl_assign #777") }
    if !(shr_assign((-10i64), 3usize) == (-2i64)) { panic("shr_assign #778") }
    if !(shl((-10i64), (read 3usize)) == (-80i64)) { panic("shl #779") }
    if !(shr((-10i64), (read 3usize)) == (-2i64)) { panic("shr #780") }
    if !(shl((read (-10i64)), (read 3usize)) == (-80i64)) { panic("shl #781") }
    if !(shr((read (-10i64)), (read 3usize)) == (-2i64)) { panic("shr #782") }
    if !(shl_assign((-10i64), (read 3usize)) == (-80i64)) { panic("shl_assign #783") }
    if !(shr_assign((-10i64), (read 3usize)) == (-2i64)) { panic("shr_assign #784") }
    if !(add((-10i128), 7i128) == (-3i128)) { panic("add #785") }
    if !(add((read (-10i128)), 7i128) == (-3i128)) { panic("add #786") }
    if !(add((-10i128), (read 7i128)) == (-3i128)) { panic("add #787") }
    if !(add((read (-10i128)), (read 7i128)) == (-3i128)) { panic("add #788") }
    if !(add_assign((-10i128), 7i128) == (-3i128)) { panic("add_assign #789") }
    if !(add_assign((-10i128), (read 7i128)) == (-3i128)) { panic("add_assign #790") }
    if !(sub((-10i128), 7i128) == (-17i128)) { panic("sub #791") }
    if !(sub((read (-10i128)), 7i128) == (-17i128)) { panic("sub #792") }
    if !(sub((-10i128), (read 7i128)) == (-17i128)) { panic("sub #793") }
    if !(sub((read (-10i128)), (read 7i128)) == (-17i128)) { panic("sub #794") }
    if !(sub_assign((-10i128), 7i128) == (-17i128)) { panic("sub_assign #795") }
    if !(sub_assign((-10i128), (read 7i128)) == (-17i128)) { panic("sub_assign #796") }
    if !(mul((-10i128), 7i128) == (-70i128)) { panic("mul #797") }
    if !(mul((read (-10i128)), 7i128) == (-70i128)) { panic("mul #798") }
    if !(mul((-10i128), (read 7i128)) == (-70i128)) { panic("mul #799") }
    if !(mul((read (-10i128)), (read 7i128)) == (-70i128)) { panic("mul #800") }
    if !(mul_assign((-10i128), 7i128) == (-70i128)) { panic("mul_assign #801") }
    if !(mul_assign((-10i128), (read 7i128)) == (-70i128)) { panic("mul_assign #802") }
    if !(div((-10i128), 7i128) == (-1i128)) { panic("div #803") }
    if !(div((read (-10i128)), 7i128) == (-1i128)) { panic("div #804") }
    if !(div((-10i128), (read 7i128)) == (-1i128)) { panic("div #805") }
    if !(div((read (-10i128)), (read 7i128)) == (-1i128)) { panic("div #806") }
    if !(div_assign((-10i128), 7i128) == (-1i128)) { panic("div_assign #807") }
    if !(div_assign((-10i128), (read 7i128)) == (-1i128)) { panic("div_assign #808") }
    if !(rem((-10i128), 7i128) == (-3i128)) { panic("rem #809") }
    if !(rem((read (-10i128)), 7i128) == (-3i128)) { panic("rem #810") }
    if !(rem((-10i128), (read 7i128)) == (-3i128)) { panic("rem #811") }
    if !(rem((read (-10i128)), (read 7i128)) == (-3i128)) { panic("rem #812") }
    if !(rem_assign((-10i128), 7i128) == (-3i128)) { panic("rem_assign #813") }
    if !(rem_assign((-10i128), (read 7i128)) == (-3i128)) { panic("rem_assign #814") }
    if !(and((-10i128), 7i128) == 6i128) { panic("and #815") }
    if !(and((read (-10i128)), 7i128) == 6i128) { panic("and #816") }
    if !(and((-10i128), (read 7i128)) == 6i128) { panic("and #817") }
    if !(and((read (-10i128)), (read 7i128)) == 6i128) { panic("and #818") }
    if !(and_assign((-10i128), 7i128) == 6i128) { panic("and_assign #819") }
    if !(and_assign((-10i128), (read 7i128)) == 6i128) { panic("and_assign #820") }
    if !(or((-10i128), 7i128) == (-9i128)) { panic("or #821") }
    if !(or((read (-10i128)), 7i128) == (-9i128)) { panic("or #822") }
    if !(or((-10i128), (read 7i128)) == (-9i128)) { panic("or #823") }
    if !(or((read (-10i128)), (read 7i128)) == (-9i128)) { panic("or #824") }
    if !(or_assign((-10i128), 7i128) == (-9i128)) { panic("or_assign #825") }
    if !(or_assign((-10i128), (read 7i128)) == (-9i128)) { panic("or_assign #826") }
    if !(xor((-10i128), 7i128) == (-15i128)) { panic("xor #827") }
    if !(xor((read (-10i128)), 7i128) == (-15i128)) { panic("xor #828") }
    if !(xor((-10i128), (read 7i128)) == (-15i128)) { panic("xor #829") }
    if !(xor((read (-10i128)), (read 7i128)) == (-15i128)) { panic("xor #830") }
    if !(xor_assign((-10i128), 7i128) == (-15i128)) { panic("xor_assign #831") }
    if !(xor_assign((-10i128), (read 7i128)) == (-15i128)) { panic("xor_assign #832") }
    if !(not((-10i128)) == 9i128) { panic("not #833") }
    if !(not((read (-10i128))) == 9i128) { panic("not #834") }
    if !(neg((-10i128)) == 10i128) { panic("neg #835") }
    if !(neg((read (-10i128))) == 10i128) { panic("neg #836") }
    if !(shl((-10i128), 3i8) == (-80i128)) { panic("shl #837") }
    if !(shr((-10i128), 3i8) == (-2i128)) { panic("shr #838") }
    if !(shl((read (-10i128)), 3i8) == (-80i128)) { panic("shl #839") }
    if !(shr((read (-10i128)), 3i8) == (-2i128)) { panic("shr #840") }
    if !(shl_assign((-10i128), 3i8) == (-80i128)) { panic("shl_assign #841") }
    if !(shr_assign((-10i128), 3i8) == (-2i128)) { panic("shr_assign #842") }
    if !(shl((-10i128), (read 3i8)) == (-80i128)) { panic("shl #843") }
    if !(shr((-10i128), (read 3i8)) == (-2i128)) { panic("shr #844") }
    if !(shl((read (-10i128)), (read 3i8)) == (-80i128)) { panic("shl #845") }
    if !(shr((read (-10i128)), (read 3i8)) == (-2i128)) { panic("shr #846") }
    if !(shl_assign((-10i128), (read 3i8)) == (-80i128)) { panic("shl_assign #847") }
    if !(shr_assign((-10i128), (read 3i8)) == (-2i128)) { panic("shr_assign #848") }
    if !(shl((-10i128), 3i16) == (-80i128)) { panic("shl #849") }
    if !(shr((-10i128), 3i16) == (-2i128)) { panic("shr #850") }
    if !(shl((read (-10i128)), 3i16) == (-80i128)) { panic("shl #851") }
    if !(shr((read (-10i128)), 3i16) == (-2i128)) { panic("shr #852") }
    if !(shl_assign((-10i128), 3i16) == (-80i128)) { panic("shl_assign #853") }
    if !(shr_assign((-10i128), 3i16) == (-2i128)) { panic("shr_assign #854") }
    if !(shl((-10i128), (read 3i16)) == (-80i128)) { panic("shl #855") }
    if !(shr((-10i128), (read 3i16)) == (-2i128)) { panic("shr #856") }
    if !(shl((read (-10i128)), (read 3i16)) == (-80i128)) { panic("shl #857") }
    if !(shr((read (-10i128)), (read 3i16)) == (-2i128)) { panic("shr #858") }
    if !(shl_assign((-10i128), (read 3i16)) == (-80i128)) { panic("shl_assign #859") }
    if !(shr_assign((-10i128), (read 3i16)) == (-2i128)) { panic("shr_assign #860") }
    if !(shl((-10i128), 3i32) == (-80i128)) { panic("shl #861") }
    if !(shr((-10i128), 3i32) == (-2i128)) { panic("shr #862") }
    if !(shl((read (-10i128)), 3i32) == (-80i128)) { panic("shl #863") }
    if !(shr((read (-10i128)), 3i32) == (-2i128)) { panic("shr #864") }
    if !(shl_assign((-10i128), 3i32) == (-80i128)) { panic("shl_assign #865") }
    if !(shr_assign((-10i128), 3i32) == (-2i128)) { panic("shr_assign #866") }
    if !(shl((-10i128), (read 3i32)) == (-80i128)) { panic("shl #867") }
    if !(shr((-10i128), (read 3i32)) == (-2i128)) { panic("shr #868") }
    if !(shl((read (-10i128)), (read 3i32)) == (-80i128)) { panic("shl #869") }
    if !(shr((read (-10i128)), (read 3i32)) == (-2i128)) { panic("shr #870") }
    if !(shl_assign((-10i128), (read 3i32)) == (-80i128)) { panic("shl_assign #871") }
    if !(shr_assign((-10i128), (read 3i32)) == (-2i128)) { panic("shr_assign #872") }
    if !(shl((-10i128), 3i64) == (-80i128)) { panic("shl #873") }
    if !(shr((-10i128), 3i64) == (-2i128)) { panic("shr #874") }
    if !(shl((read (-10i128)), 3i64) == (-80i128)) { panic("shl #875") }
    if !(shr((read (-10i128)), 3i64) == (-2i128)) { panic("shr #876") }
    if !(shl_assign((-10i128), 3i64) == (-80i128)) { panic("shl_assign #877") }
    if !(shr_assign((-10i128), 3i64) == (-2i128)) { panic("shr_assign #878") }
    if !(shl((-10i128), (read 3i64)) == (-80i128)) { panic("shl #879") }
    if !(shr((-10i128), (read 3i64)) == (-2i128)) { panic("shr #880") }
    if !(shl((read (-10i128)), (read 3i64)) == (-80i128)) { panic("shl #881") }
    if !(shr((read (-10i128)), (read 3i64)) == (-2i128)) { panic("shr #882") }
    if !(shl_assign((-10i128), (read 3i64)) == (-80i128)) { panic("shl_assign #883") }
    if !(shr_assign((-10i128), (read 3i64)) == (-2i128)) { panic("shr_assign #884") }
    if !(shl((-10i128), 3i128) == (-80i128)) { panic("shl #885") }
    if !(shr((-10i128), 3i128) == (-2i128)) { panic("shr #886") }
    if !(shl((read (-10i128)), 3i128) == (-80i128)) { panic("shl #887") }
    if !(shr((read (-10i128)), 3i128) == (-2i128)) { panic("shr #888") }
    if !(shl_assign((-10i128), 3i128) == (-80i128)) { panic("shl_assign #889") }
    if !(shr_assign((-10i128), 3i128) == (-2i128)) { panic("shr_assign #890") }
    if !(shl((-10i128), (read 3i128)) == (-80i128)) { panic("shl #891") }
    if !(shr((-10i128), (read 3i128)) == (-2i128)) { panic("shr #892") }
    if !(shl((read (-10i128)), (read 3i128)) == (-80i128)) { panic("shl #893") }
    if !(shr((read (-10i128)), (read 3i128)) == (-2i128)) { panic("shr #894") }
    if !(shl_assign((-10i128), (read 3i128)) == (-80i128)) { panic("shl_assign #895") }
    if !(shr_assign((-10i128), (read 3i128)) == (-2i128)) { panic("shr_assign #896") }
    if !(shl((-10i128), 3isize) == (-80i128)) { panic("shl #897") }
    if !(shr((-10i128), 3isize) == (-2i128)) { panic("shr #898") }
    if !(shl((read (-10i128)), 3isize) == (-80i128)) { panic("shl #899") }
    if !(shr((read (-10i128)), 3isize) == (-2i128)) { panic("shr #900") }
}

fn group6() {
    if !(shl_assign((-10i128), 3isize) == (-80i128)) { panic("shl_assign #901") }
    if !(shr_assign((-10i128), 3isize) == (-2i128)) { panic("shr_assign #902") }
    if !(shl((-10i128), (read 3isize)) == (-80i128)) { panic("shl #903") }
    if !(shr((-10i128), (read 3isize)) == (-2i128)) { panic("shr #904") }
    if !(shl((read (-10i128)), (read 3isize)) == (-80i128)) { panic("shl #905") }
    if !(shr((read (-10i128)), (read 3isize)) == (-2i128)) { panic("shr #906") }
    if !(shl_assign((-10i128), (read 3isize)) == (-80i128)) { panic("shl_assign #907") }
    if !(shr_assign((-10i128), (read 3isize)) == (-2i128)) { panic("shr_assign #908") }
    if !(shl((-10i128), 3u8) == (-80i128)) { panic("shl #909") }
    if !(shr((-10i128), 3u8) == (-2i128)) { panic("shr #910") }
    if !(shl((read (-10i128)), 3u8) == (-80i128)) { panic("shl #911") }
    if !(shr((read (-10i128)), 3u8) == (-2i128)) { panic("shr #912") }
    if !(shl_assign((-10i128), 3u8) == (-80i128)) { panic("shl_assign #913") }
    if !(shr_assign((-10i128), 3u8) == (-2i128)) { panic("shr_assign #914") }
    if !(shl((-10i128), (read 3u8)) == (-80i128)) { panic("shl #915") }
    if !(shr((-10i128), (read 3u8)) == (-2i128)) { panic("shr #916") }
    if !(shl((read (-10i128)), (read 3u8)) == (-80i128)) { panic("shl #917") }
    if !(shr((read (-10i128)), (read 3u8)) == (-2i128)) { panic("shr #918") }
    if !(shl_assign((-10i128), (read 3u8)) == (-80i128)) { panic("shl_assign #919") }
    if !(shr_assign((-10i128), (read 3u8)) == (-2i128)) { panic("shr_assign #920") }
    if !(shl((-10i128), 3u16) == (-80i128)) { panic("shl #921") }
    if !(shr((-10i128), 3u16) == (-2i128)) { panic("shr #922") }
    if !(shl((read (-10i128)), 3u16) == (-80i128)) { panic("shl #923") }
    if !(shr((read (-10i128)), 3u16) == (-2i128)) { panic("shr #924") }
    if !(shl_assign((-10i128), 3u16) == (-80i128)) { panic("shl_assign #925") }
    if !(shr_assign((-10i128), 3u16) == (-2i128)) { panic("shr_assign #926") }
    if !(shl((-10i128), (read 3u16)) == (-80i128)) { panic("shl #927") }
    if !(shr((-10i128), (read 3u16)) == (-2i128)) { panic("shr #928") }
    if !(shl((read (-10i128)), (read 3u16)) == (-80i128)) { panic("shl #929") }
    if !(shr((read (-10i128)), (read 3u16)) == (-2i128)) { panic("shr #930") }
    if !(shl_assign((-10i128), (read 3u16)) == (-80i128)) { panic("shl_assign #931") }
    if !(shr_assign((-10i128), (read 3u16)) == (-2i128)) { panic("shr_assign #932") }
    if !(shl((-10i128), 3u32) == (-80i128)) { panic("shl #933") }
    if !(shr((-10i128), 3u32) == (-2i128)) { panic("shr #934") }
    if !(shl((read (-10i128)), 3u32) == (-80i128)) { panic("shl #935") }
    if !(shr((read (-10i128)), 3u32) == (-2i128)) { panic("shr #936") }
    if !(shl_assign((-10i128), 3u32) == (-80i128)) { panic("shl_assign #937") }
    if !(shr_assign((-10i128), 3u32) == (-2i128)) { panic("shr_assign #938") }
    if !(shl((-10i128), (read 3u32)) == (-80i128)) { panic("shl #939") }
    if !(shr((-10i128), (read 3u32)) == (-2i128)) { panic("shr #940") }
    if !(shl((read (-10i128)), (read 3u32)) == (-80i128)) { panic("shl #941") }
    if !(shr((read (-10i128)), (read 3u32)) == (-2i128)) { panic("shr #942") }
    if !(shl_assign((-10i128), (read 3u32)) == (-80i128)) { panic("shl_assign #943") }
    if !(shr_assign((-10i128), (read 3u32)) == (-2i128)) { panic("shr_assign #944") }
    if !(shl((-10i128), 3u64) == (-80i128)) { panic("shl #945") }
    if !(shr((-10i128), 3u64) == (-2i128)) { panic("shr #946") }
    if !(shl((read (-10i128)), 3u64) == (-80i128)) { panic("shl #947") }
    if !(shr((read (-10i128)), 3u64) == (-2i128)) { panic("shr #948") }
    if !(shl_assign((-10i128), 3u64) == (-80i128)) { panic("shl_assign #949") }
    if !(shr_assign((-10i128), 3u64) == (-2i128)) { panic("shr_assign #950") }
    if !(shl((-10i128), (read 3u64)) == (-80i128)) { panic("shl #951") }
    if !(shr((-10i128), (read 3u64)) == (-2i128)) { panic("shr #952") }
    if !(shl((read (-10i128)), (read 3u64)) == (-80i128)) { panic("shl #953") }
    if !(shr((read (-10i128)), (read 3u64)) == (-2i128)) { panic("shr #954") }
    if !(shl_assign((-10i128), (read 3u64)) == (-80i128)) { panic("shl_assign #955") }
    if !(shr_assign((-10i128), (read 3u64)) == (-2i128)) { panic("shr_assign #956") }
    if !(shl((-10i128), 3u128) == (-80i128)) { panic("shl #957") }
    if !(shr((-10i128), 3u128) == (-2i128)) { panic("shr #958") }
    if !(shl((read (-10i128)), 3u128) == (-80i128)) { panic("shl #959") }
    if !(shr((read (-10i128)), 3u128) == (-2i128)) { panic("shr #960") }
    if !(shl_assign((-10i128), 3u128) == (-80i128)) { panic("shl_assign #961") }
    if !(shr_assign((-10i128), 3u128) == (-2i128)) { panic("shr_assign #962") }
    if !(shl((-10i128), (read 3u128)) == (-80i128)) { panic("shl #963") }
    if !(shr((-10i128), (read 3u128)) == (-2i128)) { panic("shr #964") }
    if !(shl((read (-10i128)), (read 3u128)) == (-80i128)) { panic("shl #965") }
    if !(shr((read (-10i128)), (read 3u128)) == (-2i128)) { panic("shr #966") }
    if !(shl_assign((-10i128), (read 3u128)) == (-80i128)) { panic("shl_assign #967") }
    if !(shr_assign((-10i128), (read 3u128)) == (-2i128)) { panic("shr_assign #968") }
    if !(shl((-10i128), 3usize) == (-80i128)) { panic("shl #969") }
    if !(shr((-10i128), 3usize) == (-2i128)) { panic("shr #970") }
    if !(shl((read (-10i128)), 3usize) == (-80i128)) { panic("shl #971") }
    if !(shr((read (-10i128)), 3usize) == (-2i128)) { panic("shr #972") }
    if !(shl_assign((-10i128), 3usize) == (-80i128)) { panic("shl_assign #973") }
    if !(shr_assign((-10i128), 3usize) == (-2i128)) { panic("shr_assign #974") }
    if !(shl((-10i128), (read 3usize)) == (-80i128)) { panic("shl #975") }
    if !(shr((-10i128), (read 3usize)) == (-2i128)) { panic("shr #976") }
    if !(shl((read (-10i128)), (read 3usize)) == (-80i128)) { panic("shl #977") }
    if !(shr((read (-10i128)), (read 3usize)) == (-2i128)) { panic("shr #978") }
    if !(shl_assign((-10i128), (read 3usize)) == (-80i128)) { panic("shl_assign #979") }
    if !(shr_assign((-10i128), (read 3usize)) == (-2i128)) { panic("shr_assign #980") }
    if !(add((-10isize), 7isize) == (-3isize)) { panic("add #981") }
    if !(add((read (-10isize)), 7isize) == (-3isize)) { panic("add #982") }
    if !(add((-10isize), (read 7isize)) == (-3isize)) { panic("add #983") }
    if !(add((read (-10isize)), (read 7isize)) == (-3isize)) { panic("add #984") }
    if !(add_assign((-10isize), 7isize) == (-3isize)) { panic("add_assign #985") }
    if !(add_assign((-10isize), (read 7isize)) == (-3isize)) { panic("add_assign #986") }
    if !(sub((-10isize), 7isize) == (-17isize)) { panic("sub #987") }
    if !(sub((read (-10isize)), 7isize) == (-17isize)) { panic("sub #988") }
    if !(sub((-10isize), (read 7isize)) == (-17isize)) { panic("sub #989") }
    if !(sub((read (-10isize)), (read 7isize)) == (-17isize)) { panic("sub #990") }
    if !(sub_assign((-10isize), 7isize) == (-17isize)) { panic("sub_assign #991") }
    if !(sub_assign((-10isize), (read 7isize)) == (-17isize)) { panic("sub_assign #992") }
    if !(mul((-10isize), 7isize) == (-70isize)) { panic("mul #993") }
    if !(mul((read (-10isize)), 7isize) == (-70isize)) { panic("mul #994") }
    if !(mul((-10isize), (read 7isize)) == (-70isize)) { panic("mul #995") }
    if !(mul((read (-10isize)), (read 7isize)) == (-70isize)) { panic("mul #996") }
    if !(mul_assign((-10isize), 7isize) == (-70isize)) { panic("mul_assign #997") }
    if !(mul_assign((-10isize), (read 7isize)) == (-70isize)) { panic("mul_assign #998") }
    if !(div((-10isize), 7isize) == (-1isize)) { panic("div #999") }
    if !(div((read (-10isize)), 7isize) == (-1isize)) { panic("div #1000") }
    if !(div((-10isize), (read 7isize)) == (-1isize)) { panic("div #1001") }
    if !(div((read (-10isize)), (read 7isize)) == (-1isize)) { panic("div #1002") }
    if !(div_assign((-10isize), 7isize) == (-1isize)) { panic("div_assign #1003") }
    if !(div_assign((-10isize), (read 7isize)) == (-1isize)) { panic("div_assign #1004") }
    if !(rem((-10isize), 7isize) == (-3isize)) { panic("rem #1005") }
    if !(rem((read (-10isize)), 7isize) == (-3isize)) { panic("rem #1006") }
    if !(rem((-10isize), (read 7isize)) == (-3isize)) { panic("rem #1007") }
    if !(rem((read (-10isize)), (read 7isize)) == (-3isize)) { panic("rem #1008") }
    if !(rem_assign((-10isize), 7isize) == (-3isize)) { panic("rem_assign #1009") }
    if !(rem_assign((-10isize), (read 7isize)) == (-3isize)) { panic("rem_assign #1010") }
    if !(and((-10isize), 7isize) == 6isize) { panic("and #1011") }
    if !(and((read (-10isize)), 7isize) == 6isize) { panic("and #1012") }
    if !(and((-10isize), (read 7isize)) == 6isize) { panic("and #1013") }
    if !(and((read (-10isize)), (read 7isize)) == 6isize) { panic("and #1014") }
    if !(and_assign((-10isize), 7isize) == 6isize) { panic("and_assign #1015") }
    if !(and_assign((-10isize), (read 7isize)) == 6isize) { panic("and_assign #1016") }
    if !(or((-10isize), 7isize) == (-9isize)) { panic("or #1017") }
    if !(or((read (-10isize)), 7isize) == (-9isize)) { panic("or #1018") }
    if !(or((-10isize), (read 7isize)) == (-9isize)) { panic("or #1019") }
    if !(or((read (-10isize)), (read 7isize)) == (-9isize)) { panic("or #1020") }
    if !(or_assign((-10isize), 7isize) == (-9isize)) { panic("or_assign #1021") }
    if !(or_assign((-10isize), (read 7isize)) == (-9isize)) { panic("or_assign #1022") }
    if !(xor((-10isize), 7isize) == (-15isize)) { panic("xor #1023") }
    if !(xor((read (-10isize)), 7isize) == (-15isize)) { panic("xor #1024") }
    if !(xor((-10isize), (read 7isize)) == (-15isize)) { panic("xor #1025") }
    if !(xor((read (-10isize)), (read 7isize)) == (-15isize)) { panic("xor #1026") }
    if !(xor_assign((-10isize), 7isize) == (-15isize)) { panic("xor_assign #1027") }
    if !(xor_assign((-10isize), (read 7isize)) == (-15isize)) { panic("xor_assign #1028") }
    if !(not((-10isize)) == 9isize) { panic("not #1029") }
    if !(not((read (-10isize))) == 9isize) { panic("not #1030") }
    if !(neg((-10isize)) == 10isize) { panic("neg #1031") }
    if !(neg((read (-10isize))) == 10isize) { panic("neg #1032") }
    if !(shl((-10isize), 3i8) == (-80isize)) { panic("shl #1033") }
    if !(shr((-10isize), 3i8) == (-2isize)) { panic("shr #1034") }
    if !(shl((read (-10isize)), 3i8) == (-80isize)) { panic("shl #1035") }
    if !(shr((read (-10isize)), 3i8) == (-2isize)) { panic("shr #1036") }
    if !(shl_assign((-10isize), 3i8) == (-80isize)) { panic("shl_assign #1037") }
    if !(shr_assign((-10isize), 3i8) == (-2isize)) { panic("shr_assign #1038") }
    if !(shl((-10isize), (read 3i8)) == (-80isize)) { panic("shl #1039") }
    if !(shr((-10isize), (read 3i8)) == (-2isize)) { panic("shr #1040") }
    if !(shl((read (-10isize)), (read 3i8)) == (-80isize)) { panic("shl #1041") }
    if !(shr((read (-10isize)), (read 3i8)) == (-2isize)) { panic("shr #1042") }
    if !(shl_assign((-10isize), (read 3i8)) == (-80isize)) { panic("shl_assign #1043") }
    if !(shr_assign((-10isize), (read 3i8)) == (-2isize)) { panic("shr_assign #1044") }
    if !(shl((-10isize), 3i16) == (-80isize)) { panic("shl #1045") }
    if !(shr((-10isize), 3i16) == (-2isize)) { panic("shr #1046") }
    if !(shl((read (-10isize)), 3i16) == (-80isize)) { panic("shl #1047") }
    if !(shr((read (-10isize)), 3i16) == (-2isize)) { panic("shr #1048") }
    if !(shl_assign((-10isize), 3i16) == (-80isize)) { panic("shl_assign #1049") }
    if !(shr_assign((-10isize), 3i16) == (-2isize)) { panic("shr_assign #1050") }
}

fn group7() {
    if !(shl((-10isize), (read 3i16)) == (-80isize)) { panic("shl #1051") }
    if !(shr((-10isize), (read 3i16)) == (-2isize)) { panic("shr #1052") }
    if !(shl((read (-10isize)), (read 3i16)) == (-80isize)) { panic("shl #1053") }
    if !(shr((read (-10isize)), (read 3i16)) == (-2isize)) { panic("shr #1054") }
    if !(shl_assign((-10isize), (read 3i16)) == (-80isize)) { panic("shl_assign #1055") }
    if !(shr_assign((-10isize), (read 3i16)) == (-2isize)) { panic("shr_assign #1056") }
    if !(shl((-10isize), 3i32) == (-80isize)) { panic("shl #1057") }
    if !(shr((-10isize), 3i32) == (-2isize)) { panic("shr #1058") }
    if !(shl((read (-10isize)), 3i32) == (-80isize)) { panic("shl #1059") }
    if !(shr((read (-10isize)), 3i32) == (-2isize)) { panic("shr #1060") }
    if !(shl_assign((-10isize), 3i32) == (-80isize)) { panic("shl_assign #1061") }
    if !(shr_assign((-10isize), 3i32) == (-2isize)) { panic("shr_assign #1062") }
    if !(shl((-10isize), (read 3i32)) == (-80isize)) { panic("shl #1063") }
    if !(shr((-10isize), (read 3i32)) == (-2isize)) { panic("shr #1064") }
    if !(shl((read (-10isize)), (read 3i32)) == (-80isize)) { panic("shl #1065") }
    if !(shr((read (-10isize)), (read 3i32)) == (-2isize)) { panic("shr #1066") }
    if !(shl_assign((-10isize), (read 3i32)) == (-80isize)) { panic("shl_assign #1067") }
    if !(shr_assign((-10isize), (read 3i32)) == (-2isize)) { panic("shr_assign #1068") }
    if !(shl((-10isize), 3i64) == (-80isize)) { panic("shl #1069") }
    if !(shr((-10isize), 3i64) == (-2isize)) { panic("shr #1070") }
    if !(shl((read (-10isize)), 3i64) == (-80isize)) { panic("shl #1071") }
    if !(shr((read (-10isize)), 3i64) == (-2isize)) { panic("shr #1072") }
    if !(shl_assign((-10isize), 3i64) == (-80isize)) { panic("shl_assign #1073") }
    if !(shr_assign((-10isize), 3i64) == (-2isize)) { panic("shr_assign #1074") }
    if !(shl((-10isize), (read 3i64)) == (-80isize)) { panic("shl #1075") }
    if !(shr((-10isize), (read 3i64)) == (-2isize)) { panic("shr #1076") }
    if !(shl((read (-10isize)), (read 3i64)) == (-80isize)) { panic("shl #1077") }
    if !(shr((read (-10isize)), (read 3i64)) == (-2isize)) { panic("shr #1078") }
    if !(shl_assign((-10isize), (read 3i64)) == (-80isize)) { panic("shl_assign #1079") }
    if !(shr_assign((-10isize), (read 3i64)) == (-2isize)) { panic("shr_assign #1080") }
    if !(shl((-10isize), 3i128) == (-80isize)) { panic("shl #1081") }
    if !(shr((-10isize), 3i128) == (-2isize)) { panic("shr #1082") }
    if !(shl((read (-10isize)), 3i128) == (-80isize)) { panic("shl #1083") }
    if !(shr((read (-10isize)), 3i128) == (-2isize)) { panic("shr #1084") }
    if !(shl_assign((-10isize), 3i128) == (-80isize)) { panic("shl_assign #1085") }
    if !(shr_assign((-10isize), 3i128) == (-2isize)) { panic("shr_assign #1086") }
    if !(shl((-10isize), (read 3i128)) == (-80isize)) { panic("shl #1087") }
    if !(shr((-10isize), (read 3i128)) == (-2isize)) { panic("shr #1088") }
    if !(shl((read (-10isize)), (read 3i128)) == (-80isize)) { panic("shl #1089") }
    if !(shr((read (-10isize)), (read 3i128)) == (-2isize)) { panic("shr #1090") }
    if !(shl_assign((-10isize), (read 3i128)) == (-80isize)) { panic("shl_assign #1091") }
    if !(shr_assign((-10isize), (read 3i128)) == (-2isize)) { panic("shr_assign #1092") }
    if !(shl((-10isize), 3isize) == (-80isize)) { panic("shl #1093") }
    if !(shr((-10isize), 3isize) == (-2isize)) { panic("shr #1094") }
    if !(shl((read (-10isize)), 3isize) == (-80isize)) { panic("shl #1095") }
    if !(shr((read (-10isize)), 3isize) == (-2isize)) { panic("shr #1096") }
    if !(shl_assign((-10isize), 3isize) == (-80isize)) { panic("shl_assign #1097") }
    if !(shr_assign((-10isize), 3isize) == (-2isize)) { panic("shr_assign #1098") }
    if !(shl((-10isize), (read 3isize)) == (-80isize)) { panic("shl #1099") }
    if !(shr((-10isize), (read 3isize)) == (-2isize)) { panic("shr #1100") }
    if !(shl((read (-10isize)), (read 3isize)) == (-80isize)) { panic("shl #1101") }
    if !(shr((read (-10isize)), (read 3isize)) == (-2isize)) { panic("shr #1102") }
    if !(shl_assign((-10isize), (read 3isize)) == (-80isize)) { panic("shl_assign #1103") }
    if !(shr_assign((-10isize), (read 3isize)) == (-2isize)) { panic("shr_assign #1104") }
    if !(shl((-10isize), 3u8) == (-80isize)) { panic("shl #1105") }
    if !(shr((-10isize), 3u8) == (-2isize)) { panic("shr #1106") }
    if !(shl((read (-10isize)), 3u8) == (-80isize)) { panic("shl #1107") }
    if !(shr((read (-10isize)), 3u8) == (-2isize)) { panic("shr #1108") }
    if !(shl_assign((-10isize), 3u8) == (-80isize)) { panic("shl_assign #1109") }
    if !(shr_assign((-10isize), 3u8) == (-2isize)) { panic("shr_assign #1110") }
    if !(shl((-10isize), (read 3u8)) == (-80isize)) { panic("shl #1111") }
    if !(shr((-10isize), (read 3u8)) == (-2isize)) { panic("shr #1112") }
    if !(shl((read (-10isize)), (read 3u8)) == (-80isize)) { panic("shl #1113") }
    if !(shr((read (-10isize)), (read 3u8)) == (-2isize)) { panic("shr #1114") }
    if !(shl_assign((-10isize), (read 3u8)) == (-80isize)) { panic("shl_assign #1115") }
    if !(shr_assign((-10isize), (read 3u8)) == (-2isize)) { panic("shr_assign #1116") }
    if !(shl((-10isize), 3u16) == (-80isize)) { panic("shl #1117") }
    if !(shr((-10isize), 3u16) == (-2isize)) { panic("shr #1118") }
    if !(shl((read (-10isize)), 3u16) == (-80isize)) { panic("shl #1119") }
    if !(shr((read (-10isize)), 3u16) == (-2isize)) { panic("shr #1120") }
    if !(shl_assign((-10isize), 3u16) == (-80isize)) { panic("shl_assign #1121") }
    if !(shr_assign((-10isize), 3u16) == (-2isize)) { panic("shr_assign #1122") }
    if !(shl((-10isize), (read 3u16)) == (-80isize)) { panic("shl #1123") }
    if !(shr((-10isize), (read 3u16)) == (-2isize)) { panic("shr #1124") }
    if !(shl((read (-10isize)), (read 3u16)) == (-80isize)) { panic("shl #1125") }
    if !(shr((read (-10isize)), (read 3u16)) == (-2isize)) { panic("shr #1126") }
    if !(shl_assign((-10isize), (read 3u16)) == (-80isize)) { panic("shl_assign #1127") }
    if !(shr_assign((-10isize), (read 3u16)) == (-2isize)) { panic("shr_assign #1128") }
    if !(shl((-10isize), 3u32) == (-80isize)) { panic("shl #1129") }
    if !(shr((-10isize), 3u32) == (-2isize)) { panic("shr #1130") }
    if !(shl((read (-10isize)), 3u32) == (-80isize)) { panic("shl #1131") }
    if !(shr((read (-10isize)), 3u32) == (-2isize)) { panic("shr #1132") }
    if !(shl_assign((-10isize), 3u32) == (-80isize)) { panic("shl_assign #1133") }
    if !(shr_assign((-10isize), 3u32) == (-2isize)) { panic("shr_assign #1134") }
    if !(shl((-10isize), (read 3u32)) == (-80isize)) { panic("shl #1135") }
    if !(shr((-10isize), (read 3u32)) == (-2isize)) { panic("shr #1136") }
    if !(shl((read (-10isize)), (read 3u32)) == (-80isize)) { panic("shl #1137") }
    if !(shr((read (-10isize)), (read 3u32)) == (-2isize)) { panic("shr #1138") }
    if !(shl_assign((-10isize), (read 3u32)) == (-80isize)) { panic("shl_assign #1139") }
    if !(shr_assign((-10isize), (read 3u32)) == (-2isize)) { panic("shr_assign #1140") }
    if !(shl((-10isize), 3u64) == (-80isize)) { panic("shl #1141") }
    if !(shr((-10isize), 3u64) == (-2isize)) { panic("shr #1142") }
    if !(shl((read (-10isize)), 3u64) == (-80isize)) { panic("shl #1143") }
    if !(shr((read (-10isize)), 3u64) == (-2isize)) { panic("shr #1144") }
    if !(shl_assign((-10isize), 3u64) == (-80isize)) { panic("shl_assign #1145") }
    if !(shr_assign((-10isize), 3u64) == (-2isize)) { panic("shr_assign #1146") }
    if !(shl((-10isize), (read 3u64)) == (-80isize)) { panic("shl #1147") }
    if !(shr((-10isize), (read 3u64)) == (-2isize)) { panic("shr #1148") }
    if !(shl((read (-10isize)), (read 3u64)) == (-80isize)) { panic("shl #1149") }
    if !(shr((read (-10isize)), (read 3u64)) == (-2isize)) { panic("shr #1150") }
    if !(shl_assign((-10isize), (read 3u64)) == (-80isize)) { panic("shl_assign #1151") }
    if !(shr_assign((-10isize), (read 3u64)) == (-2isize)) { panic("shr_assign #1152") }
    if !(shl((-10isize), 3u128) == (-80isize)) { panic("shl #1153") }
    if !(shr((-10isize), 3u128) == (-2isize)) { panic("shr #1154") }
    if !(shl((read (-10isize)), 3u128) == (-80isize)) { panic("shl #1155") }
    if !(shr((read (-10isize)), 3u128) == (-2isize)) { panic("shr #1156") }
    if !(shl_assign((-10isize), 3u128) == (-80isize)) { panic("shl_assign #1157") }
    if !(shr_assign((-10isize), 3u128) == (-2isize)) { panic("shr_assign #1158") }
    if !(shl((-10isize), (read 3u128)) == (-80isize)) { panic("shl #1159") }
    if !(shr((-10isize), (read 3u128)) == (-2isize)) { panic("shr #1160") }
    if !(shl((read (-10isize)), (read 3u128)) == (-80isize)) { panic("shl #1161") }
    if !(shr((read (-10isize)), (read 3u128)) == (-2isize)) { panic("shr #1162") }
    if !(shl_assign((-10isize), (read 3u128)) == (-80isize)) { panic("shl_assign #1163") }
    if !(shr_assign((-10isize), (read 3u128)) == (-2isize)) { panic("shr_assign #1164") }
    if !(shl((-10isize), 3usize) == (-80isize)) { panic("shl #1165") }
    if !(shr((-10isize), 3usize) == (-2isize)) { panic("shr #1166") }
    if !(shl((read (-10isize)), 3usize) == (-80isize)) { panic("shl #1167") }
    if !(shr((read (-10isize)), 3usize) == (-2isize)) { panic("shr #1168") }
    if !(shl_assign((-10isize), 3usize) == (-80isize)) { panic("shl_assign #1169") }
    if !(shr_assign((-10isize), 3usize) == (-2isize)) { panic("shr_assign #1170") }
    if !(shl((-10isize), (read 3usize)) == (-80isize)) { panic("shl #1171") }
    if !(shr((-10isize), (read 3usize)) == (-2isize)) { panic("shr #1172") }
    if !(shl((read (-10isize)), (read 3usize)) == (-80isize)) { panic("shl #1173") }
    if !(shr((read (-10isize)), (read 3usize)) == (-2isize)) { panic("shr #1174") }
    if !(shl_assign((-10isize), (read 3usize)) == (-80isize)) { panic("shl_assign #1175") }
    if !(shr_assign((-10isize), (read 3usize)) == (-2isize)) { panic("shr_assign #1176") }
    if !(add(20u8, 7u8) == 27u8) { panic("add #1177") }
    if !(add((read 20u8), 7u8) == 27u8) { panic("add #1178") }
    if !(add(20u8, (read 7u8)) == 27u8) { panic("add #1179") }
    if !(add((read 20u8), (read 7u8)) == 27u8) { panic("add #1180") }
    if !(add_assign(20u8, 7u8) == 27u8) { panic("add_assign #1181") }
    if !(add_assign(20u8, (read 7u8)) == 27u8) { panic("add_assign #1182") }
    if !(sub(20u8, 7u8) == 13u8) { panic("sub #1183") }
    if !(sub((read 20u8), 7u8) == 13u8) { panic("sub #1184") }
    if !(sub(20u8, (read 7u8)) == 13u8) { panic("sub #1185") }
    if !(sub((read 20u8), (read 7u8)) == 13u8) { panic("sub #1186") }
    if !(sub_assign(20u8, 7u8) == 13u8) { panic("sub_assign #1187") }
    if !(sub_assign(20u8, (read 7u8)) == 13u8) { panic("sub_assign #1188") }
    if !(mul(20u8, 7u8) == 140u8) { panic("mul #1189") }
    if !(mul((read 20u8), 7u8) == 140u8) { panic("mul #1190") }
    if !(mul(20u8, (read 7u8)) == 140u8) { panic("mul #1191") }
    if !(mul((read 20u8), (read 7u8)) == 140u8) { panic("mul #1192") }
    if !(mul_assign(20u8, 7u8) == 140u8) { panic("mul_assign #1193") }
    if !(mul_assign(20u8, (read 7u8)) == 140u8) { panic("mul_assign #1194") }
    if !(div(20u8, 7u8) == 2u8) { panic("div #1195") }
    if !(div((read 20u8), 7u8) == 2u8) { panic("div #1196") }
    if !(div(20u8, (read 7u8)) == 2u8) { panic("div #1197") }
    if !(div((read 20u8), (read 7u8)) == 2u8) { panic("div #1198") }
    if !(div_assign(20u8, 7u8) == 2u8) { panic("div_assign #1199") }
    if !(div_assign(20u8, (read 7u8)) == 2u8) { panic("div_assign #1200") }
}

fn group8() {
    if !(rem(20u8, 7u8) == 6u8) { panic("rem #1201") }
    if !(rem((read 20u8), 7u8) == 6u8) { panic("rem #1202") }
    if !(rem(20u8, (read 7u8)) == 6u8) { panic("rem #1203") }
    if !(rem((read 20u8), (read 7u8)) == 6u8) { panic("rem #1204") }
    if !(rem_assign(20u8, 7u8) == 6u8) { panic("rem_assign #1205") }
    if !(rem_assign(20u8, (read 7u8)) == 6u8) { panic("rem_assign #1206") }
    if !(and(20u8, 7u8) == 4u8) { panic("and #1207") }
    if !(and((read 20u8), 7u8) == 4u8) { panic("and #1208") }
    if !(and(20u8, (read 7u8)) == 4u8) { panic("and #1209") }
    if !(and((read 20u8), (read 7u8)) == 4u8) { panic("and #1210") }
    if !(and_assign(20u8, 7u8) == 4u8) { panic("and_assign #1211") }
    if !(and_assign(20u8, (read 7u8)) == 4u8) { panic("and_assign #1212") }
    if !(or(20u8, 7u8) == 23u8) { panic("or #1213") }
    if !(or((read 20u8), 7u8) == 23u8) { panic("or #1214") }
    if !(or(20u8, (read 7u8)) == 23u8) { panic("or #1215") }
    if !(or((read 20u8), (read 7u8)) == 23u8) { panic("or #1216") }
    if !(or_assign(20u8, 7u8) == 23u8) { panic("or_assign #1217") }
    if !(or_assign(20u8, (read 7u8)) == 23u8) { panic("or_assign #1218") }
    if !(xor(20u8, 7u8) == 19u8) { panic("xor #1219") }
    if !(xor((read 20u8), 7u8) == 19u8) { panic("xor #1220") }
    if !(xor(20u8, (read 7u8)) == 19u8) { panic("xor #1221") }
    if !(xor((read 20u8), (read 7u8)) == 19u8) { panic("xor #1222") }
    if !(xor_assign(20u8, 7u8) == 19u8) { panic("xor_assign #1223") }
    if !(xor_assign(20u8, (read 7u8)) == 19u8) { panic("xor_assign #1224") }
    if !(not(20u8) == 235u8) { panic("not #1225") }
    if !(not((read 20u8)) == 235u8) { panic("not #1226") }
    if !(shl(20u8, 3i8) == 160u8) { panic("shl #1227") }
    if !(shr(20u8, 3i8) == 2u8) { panic("shr #1228") }
    if !(shl((read 20u8), 3i8) == 160u8) { panic("shl #1229") }
    if !(shr((read 20u8), 3i8) == 2u8) { panic("shr #1230") }
    if !(shl_assign(20u8, 3i8) == 160u8) { panic("shl_assign #1231") }
    if !(shr_assign(20u8, 3i8) == 2u8) { panic("shr_assign #1232") }
    if !(shl(20u8, (read 3i8)) == 160u8) { panic("shl #1233") }
    if !(shr(20u8, (read 3i8)) == 2u8) { panic("shr #1234") }
    if !(shl((read 20u8), (read 3i8)) == 160u8) { panic("shl #1235") }
    if !(shr((read 20u8), (read 3i8)) == 2u8) { panic("shr #1236") }
    if !(shl_assign(20u8, (read 3i8)) == 160u8) { panic("shl_assign #1237") }
    if !(shr_assign(20u8, (read 3i8)) == 2u8) { panic("shr_assign #1238") }
    if !(shl(20u8, 3i16) == 160u8) { panic("shl #1239") }
    if !(shr(20u8, 3i16) == 2u8) { panic("shr #1240") }
    if !(shl((read 20u8), 3i16) == 160u8) { panic("shl #1241") }
    if !(shr((read 20u8), 3i16) == 2u8) { panic("shr #1242") }
    if !(shl_assign(20u8, 3i16) == 160u8) { panic("shl_assign #1243") }
    if !(shr_assign(20u8, 3i16) == 2u8) { panic("shr_assign #1244") }
    if !(shl(20u8, (read 3i16)) == 160u8) { panic("shl #1245") }
    if !(shr(20u8, (read 3i16)) == 2u8) { panic("shr #1246") }
    if !(shl((read 20u8), (read 3i16)) == 160u8) { panic("shl #1247") }
    if !(shr((read 20u8), (read 3i16)) == 2u8) { panic("shr #1248") }
    if !(shl_assign(20u8, (read 3i16)) == 160u8) { panic("shl_assign #1249") }
    if !(shr_assign(20u8, (read 3i16)) == 2u8) { panic("shr_assign #1250") }
    if !(shl(20u8, 3i32) == 160u8) { panic("shl #1251") }
    if !(shr(20u8, 3i32) == 2u8) { panic("shr #1252") }
    if !(shl((read 20u8), 3i32) == 160u8) { panic("shl #1253") }
    if !(shr((read 20u8), 3i32) == 2u8) { panic("shr #1254") }
    if !(shl_assign(20u8, 3i32) == 160u8) { panic("shl_assign #1255") }
    if !(shr_assign(20u8, 3i32) == 2u8) { panic("shr_assign #1256") }
    if !(shl(20u8, (read 3i32)) == 160u8) { panic("shl #1257") }
    if !(shr(20u8, (read 3i32)) == 2u8) { panic("shr #1258") }
    if !(shl((read 20u8), (read 3i32)) == 160u8) { panic("shl #1259") }
    if !(shr((read 20u8), (read 3i32)) == 2u8) { panic("shr #1260") }
    if !(shl_assign(20u8, (read 3i32)) == 160u8) { panic("shl_assign #1261") }
    if !(shr_assign(20u8, (read 3i32)) == 2u8) { panic("shr_assign #1262") }
    if !(shl(20u8, 3i64) == 160u8) { panic("shl #1263") }
    if !(shr(20u8, 3i64) == 2u8) { panic("shr #1264") }
    if !(shl((read 20u8), 3i64) == 160u8) { panic("shl #1265") }
    if !(shr((read 20u8), 3i64) == 2u8) { panic("shr #1266") }
    if !(shl_assign(20u8, 3i64) == 160u8) { panic("shl_assign #1267") }
    if !(shr_assign(20u8, 3i64) == 2u8) { panic("shr_assign #1268") }
    if !(shl(20u8, (read 3i64)) == 160u8) { panic("shl #1269") }
    if !(shr(20u8, (read 3i64)) == 2u8) { panic("shr #1270") }
    if !(shl((read 20u8), (read 3i64)) == 160u8) { panic("shl #1271") }
    if !(shr((read 20u8), (read 3i64)) == 2u8) { panic("shr #1272") }
    if !(shl_assign(20u8, (read 3i64)) == 160u8) { panic("shl_assign #1273") }
    if !(shr_assign(20u8, (read 3i64)) == 2u8) { panic("shr_assign #1274") }
    if !(shl(20u8, 3i128) == 160u8) { panic("shl #1275") }
    if !(shr(20u8, 3i128) == 2u8) { panic("shr #1276") }
    if !(shl((read 20u8), 3i128) == 160u8) { panic("shl #1277") }
    if !(shr((read 20u8), 3i128) == 2u8) { panic("shr #1278") }
    if !(shl_assign(20u8, 3i128) == 160u8) { panic("shl_assign #1279") }
    if !(shr_assign(20u8, 3i128) == 2u8) { panic("shr_assign #1280") }
    if !(shl(20u8, (read 3i128)) == 160u8) { panic("shl #1281") }
    if !(shr(20u8, (read 3i128)) == 2u8) { panic("shr #1282") }
    if !(shl((read 20u8), (read 3i128)) == 160u8) { panic("shl #1283") }
    if !(shr((read 20u8), (read 3i128)) == 2u8) { panic("shr #1284") }
    if !(shl_assign(20u8, (read 3i128)) == 160u8) { panic("shl_assign #1285") }
    if !(shr_assign(20u8, (read 3i128)) == 2u8) { panic("shr_assign #1286") }
    if !(shl(20u8, 3isize) == 160u8) { panic("shl #1287") }
    if !(shr(20u8, 3isize) == 2u8) { panic("shr #1288") }
    if !(shl((read 20u8), 3isize) == 160u8) { panic("shl #1289") }
    if !(shr((read 20u8), 3isize) == 2u8) { panic("shr #1290") }
    if !(shl_assign(20u8, 3isize) == 160u8) { panic("shl_assign #1291") }
    if !(shr_assign(20u8, 3isize) == 2u8) { panic("shr_assign #1292") }
    if !(shl(20u8, (read 3isize)) == 160u8) { panic("shl #1293") }
    if !(shr(20u8, (read 3isize)) == 2u8) { panic("shr #1294") }
    if !(shl((read 20u8), (read 3isize)) == 160u8) { panic("shl #1295") }
    if !(shr((read 20u8), (read 3isize)) == 2u8) { panic("shr #1296") }
    if !(shl_assign(20u8, (read 3isize)) == 160u8) { panic("shl_assign #1297") }
    if !(shr_assign(20u8, (read 3isize)) == 2u8) { panic("shr_assign #1298") }
    if !(shl(20u8, 3u8) == 160u8) { panic("shl #1299") }
    if !(shr(20u8, 3u8) == 2u8) { panic("shr #1300") }
    if !(shl((read 20u8), 3u8) == 160u8) { panic("shl #1301") }
    if !(shr((read 20u8), 3u8) == 2u8) { panic("shr #1302") }
    if !(shl_assign(20u8, 3u8) == 160u8) { panic("shl_assign #1303") }
    if !(shr_assign(20u8, 3u8) == 2u8) { panic("shr_assign #1304") }
    if !(shl(20u8, (read 3u8)) == 160u8) { panic("shl #1305") }
    if !(shr(20u8, (read 3u8)) == 2u8) { panic("shr #1306") }
    if !(shl((read 20u8), (read 3u8)) == 160u8) { panic("shl #1307") }
    if !(shr((read 20u8), (read 3u8)) == 2u8) { panic("shr #1308") }
    if !(shl_assign(20u8, (read 3u8)) == 160u8) { panic("shl_assign #1309") }
    if !(shr_assign(20u8, (read 3u8)) == 2u8) { panic("shr_assign #1310") }
    if !(shl(20u8, 3u16) == 160u8) { panic("shl #1311") }
    if !(shr(20u8, 3u16) == 2u8) { panic("shr #1312") }
    if !(shl((read 20u8), 3u16) == 160u8) { panic("shl #1313") }
    if !(shr((read 20u8), 3u16) == 2u8) { panic("shr #1314") }
    if !(shl_assign(20u8, 3u16) == 160u8) { panic("shl_assign #1315") }
    if !(shr_assign(20u8, 3u16) == 2u8) { panic("shr_assign #1316") }
    if !(shl(20u8, (read 3u16)) == 160u8) { panic("shl #1317") }
    if !(shr(20u8, (read 3u16)) == 2u8) { panic("shr #1318") }
    if !(shl((read 20u8), (read 3u16)) == 160u8) { panic("shl #1319") }
    if !(shr((read 20u8), (read 3u16)) == 2u8) { panic("shr #1320") }
    if !(shl_assign(20u8, (read 3u16)) == 160u8) { panic("shl_assign #1321") }
    if !(shr_assign(20u8, (read 3u16)) == 2u8) { panic("shr_assign #1322") }
    if !(shl(20u8, 3u32) == 160u8) { panic("shl #1323") }
    if !(shr(20u8, 3u32) == 2u8) { panic("shr #1324") }
    if !(shl((read 20u8), 3u32) == 160u8) { panic("shl #1325") }
    if !(shr((read 20u8), 3u32) == 2u8) { panic("shr #1326") }
    if !(shl_assign(20u8, 3u32) == 160u8) { panic("shl_assign #1327") }
    if !(shr_assign(20u8, 3u32) == 2u8) { panic("shr_assign #1328") }
    if !(shl(20u8, (read 3u32)) == 160u8) { panic("shl #1329") }
    if !(shr(20u8, (read 3u32)) == 2u8) { panic("shr #1330") }
    if !(shl((read 20u8), (read 3u32)) == 160u8) { panic("shl #1331") }
    if !(shr((read 20u8), (read 3u32)) == 2u8) { panic("shr #1332") }
    if !(shl_assign(20u8, (read 3u32)) == 160u8) { panic("shl_assign #1333") }
    if !(shr_assign(20u8, (read 3u32)) == 2u8) { panic("shr_assign #1334") }
    if !(shl(20u8, 3u64) == 160u8) { panic("shl #1335") }
    if !(shr(20u8, 3u64) == 2u8) { panic("shr #1336") }
    if !(shl((read 20u8), 3u64) == 160u8) { panic("shl #1337") }
    if !(shr((read 20u8), 3u64) == 2u8) { panic("shr #1338") }
    if !(shl_assign(20u8, 3u64) == 160u8) { panic("shl_assign #1339") }
    if !(shr_assign(20u8, 3u64) == 2u8) { panic("shr_assign #1340") }
    if !(shl(20u8, (read 3u64)) == 160u8) { panic("shl #1341") }
    if !(shr(20u8, (read 3u64)) == 2u8) { panic("shr #1342") }
    if !(shl((read 20u8), (read 3u64)) == 160u8) { panic("shl #1343") }
    if !(shr((read 20u8), (read 3u64)) == 2u8) { panic("shr #1344") }
    if !(shl_assign(20u8, (read 3u64)) == 160u8) { panic("shl_assign #1345") }
    if !(shr_assign(20u8, (read 3u64)) == 2u8) { panic("shr_assign #1346") }
    if !(shl(20u8, 3u128) == 160u8) { panic("shl #1347") }
    if !(shr(20u8, 3u128) == 2u8) { panic("shr #1348") }
    if !(shl((read 20u8), 3u128) == 160u8) { panic("shl #1349") }
    if !(shr((read 20u8), 3u128) == 2u8) { panic("shr #1350") }
}

fn group9() {
    if !(shl_assign(20u8, 3u128) == 160u8) { panic("shl_assign #1351") }
    if !(shr_assign(20u8, 3u128) == 2u8) { panic("shr_assign #1352") }
    if !(shl(20u8, (read 3u128)) == 160u8) { panic("shl #1353") }
    if !(shr(20u8, (read 3u128)) == 2u8) { panic("shr #1354") }
    if !(shl((read 20u8), (read 3u128)) == 160u8) { panic("shl #1355") }
    if !(shr((read 20u8), (read 3u128)) == 2u8) { panic("shr #1356") }
    if !(shl_assign(20u8, (read 3u128)) == 160u8) { panic("shl_assign #1357") }
    if !(shr_assign(20u8, (read 3u128)) == 2u8) { panic("shr_assign #1358") }
    if !(shl(20u8, 3usize) == 160u8) { panic("shl #1359") }
    if !(shr(20u8, 3usize) == 2u8) { panic("shr #1360") }
    if !(shl((read 20u8), 3usize) == 160u8) { panic("shl #1361") }
    if !(shr((read 20u8), 3usize) == 2u8) { panic("shr #1362") }
    if !(shl_assign(20u8, 3usize) == 160u8) { panic("shl_assign #1363") }
    if !(shr_assign(20u8, 3usize) == 2u8) { panic("shr_assign #1364") }
    if !(shl(20u8, (read 3usize)) == 160u8) { panic("shl #1365") }
    if !(shr(20u8, (read 3usize)) == 2u8) { panic("shr #1366") }
    if !(shl((read 20u8), (read 3usize)) == 160u8) { panic("shl #1367") }
    if !(shr((read 20u8), (read 3usize)) == 2u8) { panic("shr #1368") }
    if !(shl_assign(20u8, (read 3usize)) == 160u8) { panic("shl_assign #1369") }
    if !(shr_assign(20u8, (read 3usize)) == 2u8) { panic("shr_assign #1370") }
    if !(add(20u16, 7u16) == 27u16) { panic("add #1371") }
    if !(add((read 20u16), 7u16) == 27u16) { panic("add #1372") }
    if !(add(20u16, (read 7u16)) == 27u16) { panic("add #1373") }
    if !(add((read 20u16), (read 7u16)) == 27u16) { panic("add #1374") }
    if !(add_assign(20u16, 7u16) == 27u16) { panic("add_assign #1375") }
    if !(add_assign(20u16, (read 7u16)) == 27u16) { panic("add_assign #1376") }
    if !(sub(20u16, 7u16) == 13u16) { panic("sub #1377") }
    if !(sub((read 20u16), 7u16) == 13u16) { panic("sub #1378") }
    if !(sub(20u16, (read 7u16)) == 13u16) { panic("sub #1379") }
    if !(sub((read 20u16), (read 7u16)) == 13u16) { panic("sub #1380") }
    if !(sub_assign(20u16, 7u16) == 13u16) { panic("sub_assign #1381") }
    if !(sub_assign(20u16, (read 7u16)) == 13u16) { panic("sub_assign #1382") }
    if !(mul(20u16, 7u16) == 140u16) { panic("mul #1383") }
    if !(mul((read 20u16), 7u16) == 140u16) { panic("mul #1384") }
    if !(mul(20u16, (read 7u16)) == 140u16) { panic("mul #1385") }
    if !(mul((read 20u16), (read 7u16)) == 140u16) { panic("mul #1386") }
    if !(mul_assign(20u16, 7u16) == 140u16) { panic("mul_assign #1387") }
    if !(mul_assign(20u16, (read 7u16)) == 140u16) { panic("mul_assign #1388") }
    if !(div(20u16, 7u16) == 2u16) { panic("div #1389") }
    if !(div((read 20u16), 7u16) == 2u16) { panic("div #1390") }
    if !(div(20u16, (read 7u16)) == 2u16) { panic("div #1391") }
    if !(div((read 20u16), (read 7u16)) == 2u16) { panic("div #1392") }
    if !(div_assign(20u16, 7u16) == 2u16) { panic("div_assign #1393") }
    if !(div_assign(20u16, (read 7u16)) == 2u16) { panic("div_assign #1394") }
    if !(rem(20u16, 7u16) == 6u16) { panic("rem #1395") }
    if !(rem((read 20u16), 7u16) == 6u16) { panic("rem #1396") }
    if !(rem(20u16, (read 7u16)) == 6u16) { panic("rem #1397") }
    if !(rem((read 20u16), (read 7u16)) == 6u16) { panic("rem #1398") }
    if !(rem_assign(20u16, 7u16) == 6u16) { panic("rem_assign #1399") }
    if !(rem_assign(20u16, (read 7u16)) == 6u16) { panic("rem_assign #1400") }
    if !(and(20u16, 7u16) == 4u16) { panic("and #1401") }
    if !(and((read 20u16), 7u16) == 4u16) { panic("and #1402") }
    if !(and(20u16, (read 7u16)) == 4u16) { panic("and #1403") }
    if !(and((read 20u16), (read 7u16)) == 4u16) { panic("and #1404") }
    if !(and_assign(20u16, 7u16) == 4u16) { panic("and_assign #1405") }
    if !(and_assign(20u16, (read 7u16)) == 4u16) { panic("and_assign #1406") }
    if !(or(20u16, 7u16) == 23u16) { panic("or #1407") }
    if !(or((read 20u16), 7u16) == 23u16) { panic("or #1408") }
    if !(or(20u16, (read 7u16)) == 23u16) { panic("or #1409") }
    if !(or((read 20u16), (read 7u16)) == 23u16) { panic("or #1410") }
    if !(or_assign(20u16, 7u16) == 23u16) { panic("or_assign #1411") }
    if !(or_assign(20u16, (read 7u16)) == 23u16) { panic("or_assign #1412") }
    if !(xor(20u16, 7u16) == 19u16) { panic("xor #1413") }
    if !(xor((read 20u16), 7u16) == 19u16) { panic("xor #1414") }
    if !(xor(20u16, (read 7u16)) == 19u16) { panic("xor #1415") }
    if !(xor((read 20u16), (read 7u16)) == 19u16) { panic("xor #1416") }
    if !(xor_assign(20u16, 7u16) == 19u16) { panic("xor_assign #1417") }
    if !(xor_assign(20u16, (read 7u16)) == 19u16) { panic("xor_assign #1418") }
    if !(not(20u16) == 65515u16) { panic("not #1419") }
    if !(not((read 20u16)) == 65515u16) { panic("not #1420") }
    if !(shl(20u16, 3i8) == 160u16) { panic("shl #1421") }
    if !(shr(20u16, 3i8) == 2u16) { panic("shr #1422") }
    if !(shl((read 20u16), 3i8) == 160u16) { panic("shl #1423") }
    if !(shr((read 20u16), 3i8) == 2u16) { panic("shr #1424") }
    if !(shl_assign(20u16, 3i8) == 160u16) { panic("shl_assign #1425") }
    if !(shr_assign(20u16, 3i8) == 2u16) { panic("shr_assign #1426") }
    if !(shl(20u16, (read 3i8)) == 160u16) { panic("shl #1427") }
    if !(shr(20u16, (read 3i8)) == 2u16) { panic("shr #1428") }
    if !(shl((read 20u16), (read 3i8)) == 160u16) { panic("shl #1429") }
    if !(shr((read 20u16), (read 3i8)) == 2u16) { panic("shr #1430") }
    if !(shl_assign(20u16, (read 3i8)) == 160u16) { panic("shl_assign #1431") }
    if !(shr_assign(20u16, (read 3i8)) == 2u16) { panic("shr_assign #1432") }
    if !(shl(20u16, 3i16) == 160u16) { panic("shl #1433") }
    if !(shr(20u16, 3i16) == 2u16) { panic("shr #1434") }
    if !(shl((read 20u16), 3i16) == 160u16) { panic("shl #1435") }
    if !(shr((read 20u16), 3i16) == 2u16) { panic("shr #1436") }
    if !(shl_assign(20u16, 3i16) == 160u16) { panic("shl_assign #1437") }
    if !(shr_assign(20u16, 3i16) == 2u16) { panic("shr_assign #1438") }
    if !(shl(20u16, (read 3i16)) == 160u16) { panic("shl #1439") }
    if !(shr(20u16, (read 3i16)) == 2u16) { panic("shr #1440") }
    if !(shl((read 20u16), (read 3i16)) == 160u16) { panic("shl #1441") }
    if !(shr((read 20u16), (read 3i16)) == 2u16) { panic("shr #1442") }
    if !(shl_assign(20u16, (read 3i16)) == 160u16) { panic("shl_assign #1443") }
    if !(shr_assign(20u16, (read 3i16)) == 2u16) { panic("shr_assign #1444") }
    if !(shl(20u16, 3i32) == 160u16) { panic("shl #1445") }
    if !(shr(20u16, 3i32) == 2u16) { panic("shr #1446") }
    if !(shl((read 20u16), 3i32) == 160u16) { panic("shl #1447") }
    if !(shr((read 20u16), 3i32) == 2u16) { panic("shr #1448") }
    if !(shl_assign(20u16, 3i32) == 160u16) { panic("shl_assign #1449") }
    if !(shr_assign(20u16, 3i32) == 2u16) { panic("shr_assign #1450") }
    if !(shl(20u16, (read 3i32)) == 160u16) { panic("shl #1451") }
    if !(shr(20u16, (read 3i32)) == 2u16) { panic("shr #1452") }
    if !(shl((read 20u16), (read 3i32)) == 160u16) { panic("shl #1453") }
    if !(shr((read 20u16), (read 3i32)) == 2u16) { panic("shr #1454") }
    if !(shl_assign(20u16, (read 3i32)) == 160u16) { panic("shl_assign #1455") }
    if !(shr_assign(20u16, (read 3i32)) == 2u16) { panic("shr_assign #1456") }
    if !(shl(20u16, 3i64) == 160u16) { panic("shl #1457") }
    if !(shr(20u16, 3i64) == 2u16) { panic("shr #1458") }
    if !(shl((read 20u16), 3i64) == 160u16) { panic("shl #1459") }
    if !(shr((read 20u16), 3i64) == 2u16) { panic("shr #1460") }
    if !(shl_assign(20u16, 3i64) == 160u16) { panic("shl_assign #1461") }
    if !(shr_assign(20u16, 3i64) == 2u16) { panic("shr_assign #1462") }
    if !(shl(20u16, (read 3i64)) == 160u16) { panic("shl #1463") }
    if !(shr(20u16, (read 3i64)) == 2u16) { panic("shr #1464") }
    if !(shl((read 20u16), (read 3i64)) == 160u16) { panic("shl #1465") }
    if !(shr((read 20u16), (read 3i64)) == 2u16) { panic("shr #1466") }
    if !(shl_assign(20u16, (read 3i64)) == 160u16) { panic("shl_assign #1467") }
    if !(shr_assign(20u16, (read 3i64)) == 2u16) { panic("shr_assign #1468") }
    if !(shl(20u16, 3i128) == 160u16) { panic("shl #1469") }
    if !(shr(20u16, 3i128) == 2u16) { panic("shr #1470") }
    if !(shl((read 20u16), 3i128) == 160u16) { panic("shl #1471") }
    if !(shr((read 20u16), 3i128) == 2u16) { panic("shr #1472") }
    if !(shl_assign(20u16, 3i128) == 160u16) { panic("shl_assign #1473") }
    if !(shr_assign(20u16, 3i128) == 2u16) { panic("shr_assign #1474") }
    if !(shl(20u16, (read 3i128)) == 160u16) { panic("shl #1475") }
    if !(shr(20u16, (read 3i128)) == 2u16) { panic("shr #1476") }
    if !(shl((read 20u16), (read 3i128)) == 160u16) { panic("shl #1477") }
    if !(shr((read 20u16), (read 3i128)) == 2u16) { panic("shr #1478") }
    if !(shl_assign(20u16, (read 3i128)) == 160u16) { panic("shl_assign #1479") }
    if !(shr_assign(20u16, (read 3i128)) == 2u16) { panic("shr_assign #1480") }
    if !(shl(20u16, 3isize) == 160u16) { panic("shl #1481") }
    if !(shr(20u16, 3isize) == 2u16) { panic("shr #1482") }
    if !(shl((read 20u16), 3isize) == 160u16) { panic("shl #1483") }
    if !(shr((read 20u16), 3isize) == 2u16) { panic("shr #1484") }
    if !(shl_assign(20u16, 3isize) == 160u16) { panic("shl_assign #1485") }
    if !(shr_assign(20u16, 3isize) == 2u16) { panic("shr_assign #1486") }
    if !(shl(20u16, (read 3isize)) == 160u16) { panic("shl #1487") }
    if !(shr(20u16, (read 3isize)) == 2u16) { panic("shr #1488") }
    if !(shl((read 20u16), (read 3isize)) == 160u16) { panic("shl #1489") }
    if !(shr((read 20u16), (read 3isize)) == 2u16) { panic("shr #1490") }
    if !(shl_assign(20u16, (read 3isize)) == 160u16) { panic("shl_assign #1491") }
    if !(shr_assign(20u16, (read 3isize)) == 2u16) { panic("shr_assign #1492") }
    if !(shl(20u16, 3u8) == 160u16) { panic("shl #1493") }
    if !(shr(20u16, 3u8) == 2u16) { panic("shr #1494") }
    if !(shl((read 20u16), 3u8) == 160u16) { panic("shl #1495") }
    if !(shr((read 20u16), 3u8) == 2u16) { panic("shr #1496") }
    if !(shl_assign(20u16, 3u8) == 160u16) { panic("shl_assign #1497") }
    if !(shr_assign(20u16, 3u8) == 2u16) { panic("shr_assign #1498") }
    if !(shl(20u16, (read 3u8)) == 160u16) { panic("shl #1499") }
    if !(shr(20u16, (read 3u8)) == 2u16) { panic("shr #1500") }
}

fn group10() {
    if !(shl((read 20u16), (read 3u8)) == 160u16) { panic("shl #1501") }
    if !(shr((read 20u16), (read 3u8)) == 2u16) { panic("shr #1502") }
    if !(shl_assign(20u16, (read 3u8)) == 160u16) { panic("shl_assign #1503") }
    if !(shr_assign(20u16, (read 3u8)) == 2u16) { panic("shr_assign #1504") }
    if !(shl(20u16, 3u16) == 160u16) { panic("shl #1505") }
    if !(shr(20u16, 3u16) == 2u16) { panic("shr #1506") }
    if !(shl((read 20u16), 3u16) == 160u16) { panic("shl #1507") }
    if !(shr((read 20u16), 3u16) == 2u16) { panic("shr #1508") }
    if !(shl_assign(20u16, 3u16) == 160u16) { panic("shl_assign #1509") }
    if !(shr_assign(20u16, 3u16) == 2u16) { panic("shr_assign #1510") }
    if !(shl(20u16, (read 3u16)) == 160u16) { panic("shl #1511") }
    if !(shr(20u16, (read 3u16)) == 2u16) { panic("shr #1512") }
    if !(shl((read 20u16), (read 3u16)) == 160u16) { panic("shl #1513") }
    if !(shr((read 20u16), (read 3u16)) == 2u16) { panic("shr #1514") }
    if !(shl_assign(20u16, (read 3u16)) == 160u16) { panic("shl_assign #1515") }
    if !(shr_assign(20u16, (read 3u16)) == 2u16) { panic("shr_assign #1516") }
    if !(shl(20u16, 3u32) == 160u16) { panic("shl #1517") }
    if !(shr(20u16, 3u32) == 2u16) { panic("shr #1518") }
    if !(shl((read 20u16), 3u32) == 160u16) { panic("shl #1519") }
    if !(shr((read 20u16), 3u32) == 2u16) { panic("shr #1520") }
    if !(shl_assign(20u16, 3u32) == 160u16) { panic("shl_assign #1521") }
    if !(shr_assign(20u16, 3u32) == 2u16) { panic("shr_assign #1522") }
    if !(shl(20u16, (read 3u32)) == 160u16) { panic("shl #1523") }
    if !(shr(20u16, (read 3u32)) == 2u16) { panic("shr #1524") }
    if !(shl((read 20u16), (read 3u32)) == 160u16) { panic("shl #1525") }
    if !(shr((read 20u16), (read 3u32)) == 2u16) { panic("shr #1526") }
    if !(shl_assign(20u16, (read 3u32)) == 160u16) { panic("shl_assign #1527") }
    if !(shr_assign(20u16, (read 3u32)) == 2u16) { panic("shr_assign #1528") }
    if !(shl(20u16, 3u64) == 160u16) { panic("shl #1529") }
    if !(shr(20u16, 3u64) == 2u16) { panic("shr #1530") }
    if !(shl((read 20u16), 3u64) == 160u16) { panic("shl #1531") }
    if !(shr((read 20u16), 3u64) == 2u16) { panic("shr #1532") }
    if !(shl_assign(20u16, 3u64) == 160u16) { panic("shl_assign #1533") }
    if !(shr_assign(20u16, 3u64) == 2u16) { panic("shr_assign #1534") }
    if !(shl(20u16, (read 3u64)) == 160u16) { panic("shl #1535") }
    if !(shr(20u16, (read 3u64)) == 2u16) { panic("shr #1536") }
    if !(shl((read 20u16), (read 3u64)) == 160u16) { panic("shl #1537") }
    if !(shr((read 20u16), (read 3u64)) == 2u16) { panic("shr #1538") }
    if !(shl_assign(20u16, (read 3u64)) == 160u16) { panic("shl_assign #1539") }
    if !(shr_assign(20u16, (read 3u64)) == 2u16) { panic("shr_assign #1540") }
    if !(shl(20u16, 3u128) == 160u16) { panic("shl #1541") }
    if !(shr(20u16, 3u128) == 2u16) { panic("shr #1542") }
    if !(shl((read 20u16), 3u128) == 160u16) { panic("shl #1543") }
    if !(shr((read 20u16), 3u128) == 2u16) { panic("shr #1544") }
    if !(shl_assign(20u16, 3u128) == 160u16) { panic("shl_assign #1545") }
    if !(shr_assign(20u16, 3u128) == 2u16) { panic("shr_assign #1546") }
    if !(shl(20u16, (read 3u128)) == 160u16) { panic("shl #1547") }
    if !(shr(20u16, (read 3u128)) == 2u16) { panic("shr #1548") }
    if !(shl((read 20u16), (read 3u128)) == 160u16) { panic("shl #1549") }
    if !(shr((read 20u16), (read 3u128)) == 2u16) { panic("shr #1550") }
    if !(shl_assign(20u16, (read 3u128)) == 160u16) { panic("shl_assign #1551") }
    if !(shr_assign(20u16, (read 3u128)) == 2u16) { panic("shr_assign #1552") }
    if !(shl(20u16, 3usize) == 160u16) { panic("shl #1553") }
    if !(shr(20u16, 3usize) == 2u16) { panic("shr #1554") }
    if !(shl((read 20u16), 3usize) == 160u16) { panic("shl #1555") }
    if !(shr((read 20u16), 3usize) == 2u16) { panic("shr #1556") }
    if !(shl_assign(20u16, 3usize) == 160u16) { panic("shl_assign #1557") }
    if !(shr_assign(20u16, 3usize) == 2u16) { panic("shr_assign #1558") }
    if !(shl(20u16, (read 3usize)) == 160u16) { panic("shl #1559") }
    if !(shr(20u16, (read 3usize)) == 2u16) { panic("shr #1560") }
    if !(shl((read 20u16), (read 3usize)) == 160u16) { panic("shl #1561") }
    if !(shr((read 20u16), (read 3usize)) == 2u16) { panic("shr #1562") }
    if !(shl_assign(20u16, (read 3usize)) == 160u16) { panic("shl_assign #1563") }
    if !(shr_assign(20u16, (read 3usize)) == 2u16) { panic("shr_assign #1564") }
    if !(add(20u32, 7u32) == 27u32) { panic("add #1565") }
    if !(add((read 20u32), 7u32) == 27u32) { panic("add #1566") }
    if !(add(20u32, (read 7u32)) == 27u32) { panic("add #1567") }
    if !(add((read 20u32), (read 7u32)) == 27u32) { panic("add #1568") }
    if !(add_assign(20u32, 7u32) == 27u32) { panic("add_assign #1569") }
    if !(add_assign(20u32, (read 7u32)) == 27u32) { panic("add_assign #1570") }
    if !(sub(20u32, 7u32) == 13u32) { panic("sub #1571") }
    if !(sub((read 20u32), 7u32) == 13u32) { panic("sub #1572") }
    if !(sub(20u32, (read 7u32)) == 13u32) { panic("sub #1573") }
    if !(sub((read 20u32), (read 7u32)) == 13u32) { panic("sub #1574") }
    if !(sub_assign(20u32, 7u32) == 13u32) { panic("sub_assign #1575") }
    if !(sub_assign(20u32, (read 7u32)) == 13u32) { panic("sub_assign #1576") }
    if !(mul(20u32, 7u32) == 140u32) { panic("mul #1577") }
    if !(mul((read 20u32), 7u32) == 140u32) { panic("mul #1578") }
    if !(mul(20u32, (read 7u32)) == 140u32) { panic("mul #1579") }
    if !(mul((read 20u32), (read 7u32)) == 140u32) { panic("mul #1580") }
    if !(mul_assign(20u32, 7u32) == 140u32) { panic("mul_assign #1581") }
    if !(mul_assign(20u32, (read 7u32)) == 140u32) { panic("mul_assign #1582") }
    if !(div(20u32, 7u32) == 2u32) { panic("div #1583") }
    if !(div((read 20u32), 7u32) == 2u32) { panic("div #1584") }
    if !(div(20u32, (read 7u32)) == 2u32) { panic("div #1585") }
    if !(div((read 20u32), (read 7u32)) == 2u32) { panic("div #1586") }
    if !(div_assign(20u32, 7u32) == 2u32) { panic("div_assign #1587") }
    if !(div_assign(20u32, (read 7u32)) == 2u32) { panic("div_assign #1588") }
    if !(rem(20u32, 7u32) == 6u32) { panic("rem #1589") }
    if !(rem((read 20u32), 7u32) == 6u32) { panic("rem #1590") }
    if !(rem(20u32, (read 7u32)) == 6u32) { panic("rem #1591") }
    if !(rem((read 20u32), (read 7u32)) == 6u32) { panic("rem #1592") }
    if !(rem_assign(20u32, 7u32) == 6u32) { panic("rem_assign #1593") }
    if !(rem_assign(20u32, (read 7u32)) == 6u32) { panic("rem_assign #1594") }
    if !(and(20u32, 7u32) == 4u32) { panic("and #1595") }
    if !(and((read 20u32), 7u32) == 4u32) { panic("and #1596") }
    if !(and(20u32, (read 7u32)) == 4u32) { panic("and #1597") }
    if !(and((read 20u32), (read 7u32)) == 4u32) { panic("and #1598") }
    if !(and_assign(20u32, 7u32) == 4u32) { panic("and_assign #1599") }
    if !(and_assign(20u32, (read 7u32)) == 4u32) { panic("and_assign #1600") }
    if !(or(20u32, 7u32) == 23u32) { panic("or #1601") }
    if !(or((read 20u32), 7u32) == 23u32) { panic("or #1602") }
    if !(or(20u32, (read 7u32)) == 23u32) { panic("or #1603") }
    if !(or((read 20u32), (read 7u32)) == 23u32) { panic("or #1604") }
    if !(or_assign(20u32, 7u32) == 23u32) { panic("or_assign #1605") }
    if !(or_assign(20u32, (read 7u32)) == 23u32) { panic("or_assign #1606") }
    if !(xor(20u32, 7u32) == 19u32) { panic("xor #1607") }
    if !(xor((read 20u32), 7u32) == 19u32) { panic("xor #1608") }
    if !(xor(20u32, (read 7u32)) == 19u32) { panic("xor #1609") }
    if !(xor((read 20u32), (read 7u32)) == 19u32) { panic("xor #1610") }
    if !(xor_assign(20u32, 7u32) == 19u32) { panic("xor_assign #1611") }
    if !(xor_assign(20u32, (read 7u32)) == 19u32) { panic("xor_assign #1612") }
    if !(not(20u32) == 4294967275u32) { panic("not #1613") }
    if !(not((read 20u32)) == 4294967275u32) { panic("not #1614") }
    if !(shl(20u32, 3i8) == 160u32) { panic("shl #1615") }
    if !(shr(20u32, 3i8) == 2u32) { panic("shr #1616") }
    if !(shl((read 20u32), 3i8) == 160u32) { panic("shl #1617") }
    if !(shr((read 20u32), 3i8) == 2u32) { panic("shr #1618") }
    if !(shl_assign(20u32, 3i8) == 160u32) { panic("shl_assign #1619") }
    if !(shr_assign(20u32, 3i8) == 2u32) { panic("shr_assign #1620") }
    if !(shl(20u32, (read 3i8)) == 160u32) { panic("shl #1621") }
    if !(shr(20u32, (read 3i8)) == 2u32) { panic("shr #1622") }
    if !(shl((read 20u32), (read 3i8)) == 160u32) { panic("shl #1623") }
    if !(shr((read 20u32), (read 3i8)) == 2u32) { panic("shr #1624") }
    if !(shl_assign(20u32, (read 3i8)) == 160u32) { panic("shl_assign #1625") }
    if !(shr_assign(20u32, (read 3i8)) == 2u32) { panic("shr_assign #1626") }
    if !(shl(20u32, 3i16) == 160u32) { panic("shl #1627") }
    if !(shr(20u32, 3i16) == 2u32) { panic("shr #1628") }
    if !(shl((read 20u32), 3i16) == 160u32) { panic("shl #1629") }
    if !(shr((read 20u32), 3i16) == 2u32) { panic("shr #1630") }
    if !(shl_assign(20u32, 3i16) == 160u32) { panic("shl_assign #1631") }
    if !(shr_assign(20u32, 3i16) == 2u32) { panic("shr_assign #1632") }
    if !(shl(20u32, (read 3i16)) == 160u32) { panic("shl #1633") }
    if !(shr(20u32, (read 3i16)) == 2u32) { panic("shr #1634") }
    if !(shl((read 20u32), (read 3i16)) == 160u32) { panic("shl #1635") }
    if !(shr((read 20u32), (read 3i16)) == 2u32) { panic("shr #1636") }
    if !(shl_assign(20u32, (read 3i16)) == 160u32) { panic("shl_assign #1637") }
    if !(shr_assign(20u32, (read 3i16)) == 2u32) { panic("shr_assign #1638") }
    if !(shl(20u32, 3i32) == 160u32) { panic("shl #1639") }
    if !(shr(20u32, 3i32) == 2u32) { panic("shr #1640") }
    if !(shl((read 20u32), 3i32) == 160u32) { panic("shl #1641") }
    if !(shr((read 20u32), 3i32) == 2u32) { panic("shr #1642") }
    if !(shl_assign(20u32, 3i32) == 160u32) { panic("shl_assign #1643") }
    if !(shr_assign(20u32, 3i32) == 2u32) { panic("shr_assign #1644") }
    if !(shl(20u32, (read 3i32)) == 160u32) { panic("shl #1645") }
    if !(shr(20u32, (read 3i32)) == 2u32) { panic("shr #1646") }
    if !(shl((read 20u32), (read 3i32)) == 160u32) { panic("shl #1647") }
    if !(shr((read 20u32), (read 3i32)) == 2u32) { panic("shr #1648") }
    if !(shl_assign(20u32, (read 3i32)) == 160u32) { panic("shl_assign #1649") }
    if !(shr_assign(20u32, (read 3i32)) == 2u32) { panic("shr_assign #1650") }
}

fn group11() {
    if !(shl(20u32, 3i64) == 160u32) { panic("shl #1651") }
    if !(shr(20u32, 3i64) == 2u32) { panic("shr #1652") }
    if !(shl((read 20u32), 3i64) == 160u32) { panic("shl #1653") }
    if !(shr((read 20u32), 3i64) == 2u32) { panic("shr #1654") }
    if !(shl_assign(20u32, 3i64) == 160u32) { panic("shl_assign #1655") }
    if !(shr_assign(20u32, 3i64) == 2u32) { panic("shr_assign #1656") }
    if !(shl(20u32, (read 3i64)) == 160u32) { panic("shl #1657") }
    if !(shr(20u32, (read 3i64)) == 2u32) { panic("shr #1658") }
    if !(shl((read 20u32), (read 3i64)) == 160u32) { panic("shl #1659") }
    if !(shr((read 20u32), (read 3i64)) == 2u32) { panic("shr #1660") }
    if !(shl_assign(20u32, (read 3i64)) == 160u32) { panic("shl_assign #1661") }
    if !(shr_assign(20u32, (read 3i64)) == 2u32) { panic("shr_assign #1662") }
    if !(shl(20u32, 3i128) == 160u32) { panic("shl #1663") }
    if !(shr(20u32, 3i128) == 2u32) { panic("shr #1664") }
    if !(shl((read 20u32), 3i128) == 160u32) { panic("shl #1665") }
    if !(shr((read 20u32), 3i128) == 2u32) { panic("shr #1666") }
    if !(shl_assign(20u32, 3i128) == 160u32) { panic("shl_assign #1667") }
    if !(shr_assign(20u32, 3i128) == 2u32) { panic("shr_assign #1668") }
    if !(shl(20u32, (read 3i128)) == 160u32) { panic("shl #1669") }
    if !(shr(20u32, (read 3i128)) == 2u32) { panic("shr #1670") }
    if !(shl((read 20u32), (read 3i128)) == 160u32) { panic("shl #1671") }
    if !(shr((read 20u32), (read 3i128)) == 2u32) { panic("shr #1672") }
    if !(shl_assign(20u32, (read 3i128)) == 160u32) { panic("shl_assign #1673") }
    if !(shr_assign(20u32, (read 3i128)) == 2u32) { panic("shr_assign #1674") }
    if !(shl(20u32, 3isize) == 160u32) { panic("shl #1675") }
    if !(shr(20u32, 3isize) == 2u32) { panic("shr #1676") }
    if !(shl((read 20u32), 3isize) == 160u32) { panic("shl #1677") }
    if !(shr((read 20u32), 3isize) == 2u32) { panic("shr #1678") }
    if !(shl_assign(20u32, 3isize) == 160u32) { panic("shl_assign #1679") }
    if !(shr_assign(20u32, 3isize) == 2u32) { panic("shr_assign #1680") }
    if !(shl(20u32, (read 3isize)) == 160u32) { panic("shl #1681") }
    if !(shr(20u32, (read 3isize)) == 2u32) { panic("shr #1682") }
    if !(shl((read 20u32), (read 3isize)) == 160u32) { panic("shl #1683") }
    if !(shr((read 20u32), (read 3isize)) == 2u32) { panic("shr #1684") }
    if !(shl_assign(20u32, (read 3isize)) == 160u32) { panic("shl_assign #1685") }
    if !(shr_assign(20u32, (read 3isize)) == 2u32) { panic("shr_assign #1686") }
    if !(shl(20u32, 3u8) == 160u32) { panic("shl #1687") }
    if !(shr(20u32, 3u8) == 2u32) { panic("shr #1688") }
    if !(shl((read 20u32), 3u8) == 160u32) { panic("shl #1689") }
    if !(shr((read 20u32), 3u8) == 2u32) { panic("shr #1690") }
    if !(shl_assign(20u32, 3u8) == 160u32) { panic("shl_assign #1691") }
    if !(shr_assign(20u32, 3u8) == 2u32) { panic("shr_assign #1692") }
    if !(shl(20u32, (read 3u8)) == 160u32) { panic("shl #1693") }
    if !(shr(20u32, (read 3u8)) == 2u32) { panic("shr #1694") }
    if !(shl((read 20u32), (read 3u8)) == 160u32) { panic("shl #1695") }
    if !(shr((read 20u32), (read 3u8)) == 2u32) { panic("shr #1696") }
    if !(shl_assign(20u32, (read 3u8)) == 160u32) { panic("shl_assign #1697") }
    if !(shr_assign(20u32, (read 3u8)) == 2u32) { panic("shr_assign #1698") }
    if !(shl(20u32, 3u16) == 160u32) { panic("shl #1699") }
    if !(shr(20u32, 3u16) == 2u32) { panic("shr #1700") }
    if !(shl((read 20u32), 3u16) == 160u32) { panic("shl #1701") }
    if !(shr((read 20u32), 3u16) == 2u32) { panic("shr #1702") }
    if !(shl_assign(20u32, 3u16) == 160u32) { panic("shl_assign #1703") }
    if !(shr_assign(20u32, 3u16) == 2u32) { panic("shr_assign #1704") }
    if !(shl(20u32, (read 3u16)) == 160u32) { panic("shl #1705") }
    if !(shr(20u32, (read 3u16)) == 2u32) { panic("shr #1706") }
    if !(shl((read 20u32), (read 3u16)) == 160u32) { panic("shl #1707") }
    if !(shr((read 20u32), (read 3u16)) == 2u32) { panic("shr #1708") }
    if !(shl_assign(20u32, (read 3u16)) == 160u32) { panic("shl_assign #1709") }
    if !(shr_assign(20u32, (read 3u16)) == 2u32) { panic("shr_assign #1710") }
    if !(shl(20u32, 3u32) == 160u32) { panic("shl #1711") }
    if !(shr(20u32, 3u32) == 2u32) { panic("shr #1712") }
    if !(shl((read 20u32), 3u32) == 160u32) { panic("shl #1713") }
    if !(shr((read 20u32), 3u32) == 2u32) { panic("shr #1714") }
    if !(shl_assign(20u32, 3u32) == 160u32) { panic("shl_assign #1715") }
    if !(shr_assign(20u32, 3u32) == 2u32) { panic("shr_assign #1716") }
    if !(shl(20u32, (read 3u32)) == 160u32) { panic("shl #1717") }
    if !(shr(20u32, (read 3u32)) == 2u32) { panic("shr #1718") }
    if !(shl((read 20u32), (read 3u32)) == 160u32) { panic("shl #1719") }
    if !(shr((read 20u32), (read 3u32)) == 2u32) { panic("shr #1720") }
    if !(shl_assign(20u32, (read 3u32)) == 160u32) { panic("shl_assign #1721") }
    if !(shr_assign(20u32, (read 3u32)) == 2u32) { panic("shr_assign #1722") }
    if !(shl(20u32, 3u64) == 160u32) { panic("shl #1723") }
    if !(shr(20u32, 3u64) == 2u32) { panic("shr #1724") }
    if !(shl((read 20u32), 3u64) == 160u32) { panic("shl #1725") }
    if !(shr((read 20u32), 3u64) == 2u32) { panic("shr #1726") }
    if !(shl_assign(20u32, 3u64) == 160u32) { panic("shl_assign #1727") }
    if !(shr_assign(20u32, 3u64) == 2u32) { panic("shr_assign #1728") }
    if !(shl(20u32, (read 3u64)) == 160u32) { panic("shl #1729") }
    if !(shr(20u32, (read 3u64)) == 2u32) { panic("shr #1730") }
    if !(shl((read 20u32), (read 3u64)) == 160u32) { panic("shl #1731") }
    if !(shr((read 20u32), (read 3u64)) == 2u32) { panic("shr #1732") }
    if !(shl_assign(20u32, (read 3u64)) == 160u32) { panic("shl_assign #1733") }
    if !(shr_assign(20u32, (read 3u64)) == 2u32) { panic("shr_assign #1734") }
    if !(shl(20u32, 3u128) == 160u32) { panic("shl #1735") }
    if !(shr(20u32, 3u128) == 2u32) { panic("shr #1736") }
    if !(shl((read 20u32), 3u128) == 160u32) { panic("shl #1737") }
    if !(shr((read 20u32), 3u128) == 2u32) { panic("shr #1738") }
    if !(shl_assign(20u32, 3u128) == 160u32) { panic("shl_assign #1739") }
    if !(shr_assign(20u32, 3u128) == 2u32) { panic("shr_assign #1740") }
    if !(shl(20u32, (read 3u128)) == 160u32) { panic("shl #1741") }
    if !(shr(20u32, (read 3u128)) == 2u32) { panic("shr #1742") }
    if !(shl((read 20u32), (read 3u128)) == 160u32) { panic("shl #1743") }
    if !(shr((read 20u32), (read 3u128)) == 2u32) { panic("shr #1744") }
    if !(shl_assign(20u32, (read 3u128)) == 160u32) { panic("shl_assign #1745") }
    if !(shr_assign(20u32, (read 3u128)) == 2u32) { panic("shr_assign #1746") }
    if !(shl(20u32, 3usize) == 160u32) { panic("shl #1747") }
    if !(shr(20u32, 3usize) == 2u32) { panic("shr #1748") }
    if !(shl((read 20u32), 3usize) == 160u32) { panic("shl #1749") }
    if !(shr((read 20u32), 3usize) == 2u32) { panic("shr #1750") }
    if !(shl_assign(20u32, 3usize) == 160u32) { panic("shl_assign #1751") }
    if !(shr_assign(20u32, 3usize) == 2u32) { panic("shr_assign #1752") }
    if !(shl(20u32, (read 3usize)) == 160u32) { panic("shl #1753") }
    if !(shr(20u32, (read 3usize)) == 2u32) { panic("shr #1754") }
    if !(shl((read 20u32), (read 3usize)) == 160u32) { panic("shl #1755") }
    if !(shr((read 20u32), (read 3usize)) == 2u32) { panic("shr #1756") }
    if !(shl_assign(20u32, (read 3usize)) == 160u32) { panic("shl_assign #1757") }
    if !(shr_assign(20u32, (read 3usize)) == 2u32) { panic("shr_assign #1758") }
    if !(add(20u64, 7u64) == 27u64) { panic("add #1759") }
    if !(add((read 20u64), 7u64) == 27u64) { panic("add #1760") }
    if !(add(20u64, (read 7u64)) == 27u64) { panic("add #1761") }
    if !(add((read 20u64), (read 7u64)) == 27u64) { panic("add #1762") }
    if !(add_assign(20u64, 7u64) == 27u64) { panic("add_assign #1763") }
    if !(add_assign(20u64, (read 7u64)) == 27u64) { panic("add_assign #1764") }
    if !(sub(20u64, 7u64) == 13u64) { panic("sub #1765") }
    if !(sub((read 20u64), 7u64) == 13u64) { panic("sub #1766") }
    if !(sub(20u64, (read 7u64)) == 13u64) { panic("sub #1767") }
    if !(sub((read 20u64), (read 7u64)) == 13u64) { panic("sub #1768") }
    if !(sub_assign(20u64, 7u64) == 13u64) { panic("sub_assign #1769") }
    if !(sub_assign(20u64, (read 7u64)) == 13u64) { panic("sub_assign #1770") }
    if !(mul(20u64, 7u64) == 140u64) { panic("mul #1771") }
    if !(mul((read 20u64), 7u64) == 140u64) { panic("mul #1772") }
    if !(mul(20u64, (read 7u64)) == 140u64) { panic("mul #1773") }
    if !(mul((read 20u64), (read 7u64)) == 140u64) { panic("mul #1774") }
    if !(mul_assign(20u64, 7u64) == 140u64) { panic("mul_assign #1775") }
    if !(mul_assign(20u64, (read 7u64)) == 140u64) { panic("mul_assign #1776") }
    if !(div(20u64, 7u64) == 2u64) { panic("div #1777") }
    if !(div((read 20u64), 7u64) == 2u64) { panic("div #1778") }
    if !(div(20u64, (read 7u64)) == 2u64) { panic("div #1779") }
    if !(div((read 20u64), (read 7u64)) == 2u64) { panic("div #1780") }
    if !(div_assign(20u64, 7u64) == 2u64) { panic("div_assign #1781") }
    if !(div_assign(20u64, (read 7u64)) == 2u64) { panic("div_assign #1782") }
    if !(rem(20u64, 7u64) == 6u64) { panic("rem #1783") }
    if !(rem((read 20u64), 7u64) == 6u64) { panic("rem #1784") }
    if !(rem(20u64, (read 7u64)) == 6u64) { panic("rem #1785") }
    if !(rem((read 20u64), (read 7u64)) == 6u64) { panic("rem #1786") }
    if !(rem_assign(20u64, 7u64) == 6u64) { panic("rem_assign #1787") }
    if !(rem_assign(20u64, (read 7u64)) == 6u64) { panic("rem_assign #1788") }
    if !(and(20u64, 7u64) == 4u64) { panic("and #1789") }
    if !(and((read 20u64), 7u64) == 4u64) { panic("and #1790") }
    if !(and(20u64, (read 7u64)) == 4u64) { panic("and #1791") }
    if !(and((read 20u64), (read 7u64)) == 4u64) { panic("and #1792") }
    if !(and_assign(20u64, 7u64) == 4u64) { panic("and_assign #1793") }
    if !(and_assign(20u64, (read 7u64)) == 4u64) { panic("and_assign #1794") }
    if !(or(20u64, 7u64) == 23u64) { panic("or #1795") }
    if !(or((read 20u64), 7u64) == 23u64) { panic("or #1796") }
    if !(or(20u64, (read 7u64)) == 23u64) { panic("or #1797") }
    if !(or((read 20u64), (read 7u64)) == 23u64) { panic("or #1798") }
    if !(or_assign(20u64, 7u64) == 23u64) { panic("or_assign #1799") }
    if !(or_assign(20u64, (read 7u64)) == 23u64) { panic("or_assign #1800") }
}

fn group12() {
    if !(xor(20u64, 7u64) == 19u64) { panic("xor #1801") }
    if !(xor((read 20u64), 7u64) == 19u64) { panic("xor #1802") }
    if !(xor(20u64, (read 7u64)) == 19u64) { panic("xor #1803") }
    if !(xor((read 20u64), (read 7u64)) == 19u64) { panic("xor #1804") }
    if !(xor_assign(20u64, 7u64) == 19u64) { panic("xor_assign #1805") }
    if !(xor_assign(20u64, (read 7u64)) == 19u64) { panic("xor_assign #1806") }
    if !(not(20u64) == 18446744073709551595u64) { panic("not #1807") }
    if !(not((read 20u64)) == 18446744073709551595u64) { panic("not #1808") }
    if !(shl(20u64, 3i8) == 160u64) { panic("shl #1809") }
    if !(shr(20u64, 3i8) == 2u64) { panic("shr #1810") }
    if !(shl((read 20u64), 3i8) == 160u64) { panic("shl #1811") }
    if !(shr((read 20u64), 3i8) == 2u64) { panic("shr #1812") }
    if !(shl_assign(20u64, 3i8) == 160u64) { panic("shl_assign #1813") }
    if !(shr_assign(20u64, 3i8) == 2u64) { panic("shr_assign #1814") }
    if !(shl(20u64, (read 3i8)) == 160u64) { panic("shl #1815") }
    if !(shr(20u64, (read 3i8)) == 2u64) { panic("shr #1816") }
    if !(shl((read 20u64), (read 3i8)) == 160u64) { panic("shl #1817") }
    if !(shr((read 20u64), (read 3i8)) == 2u64) { panic("shr #1818") }
    if !(shl_assign(20u64, (read 3i8)) == 160u64) { panic("shl_assign #1819") }
    if !(shr_assign(20u64, (read 3i8)) == 2u64) { panic("shr_assign #1820") }
    if !(shl(20u64, 3i16) == 160u64) { panic("shl #1821") }
    if !(shr(20u64, 3i16) == 2u64) { panic("shr #1822") }
    if !(shl((read 20u64), 3i16) == 160u64) { panic("shl #1823") }
    if !(shr((read 20u64), 3i16) == 2u64) { panic("shr #1824") }
    if !(shl_assign(20u64, 3i16) == 160u64) { panic("shl_assign #1825") }
    if !(shr_assign(20u64, 3i16) == 2u64) { panic("shr_assign #1826") }
    if !(shl(20u64, (read 3i16)) == 160u64) { panic("shl #1827") }
    if !(shr(20u64, (read 3i16)) == 2u64) { panic("shr #1828") }
    if !(shl((read 20u64), (read 3i16)) == 160u64) { panic("shl #1829") }
    if !(shr((read 20u64), (read 3i16)) == 2u64) { panic("shr #1830") }
    if !(shl_assign(20u64, (read 3i16)) == 160u64) { panic("shl_assign #1831") }
    if !(shr_assign(20u64, (read 3i16)) == 2u64) { panic("shr_assign #1832") }
    if !(shl(20u64, 3i32) == 160u64) { panic("shl #1833") }
    if !(shr(20u64, 3i32) == 2u64) { panic("shr #1834") }
    if !(shl((read 20u64), 3i32) == 160u64) { panic("shl #1835") }
    if !(shr((read 20u64), 3i32) == 2u64) { panic("shr #1836") }
    if !(shl_assign(20u64, 3i32) == 160u64) { panic("shl_assign #1837") }
    if !(shr_assign(20u64, 3i32) == 2u64) { panic("shr_assign #1838") }
    if !(shl(20u64, (read 3i32)) == 160u64) { panic("shl #1839") }
    if !(shr(20u64, (read 3i32)) == 2u64) { panic("shr #1840") }
    if !(shl((read 20u64), (read 3i32)) == 160u64) { panic("shl #1841") }
    if !(shr((read 20u64), (read 3i32)) == 2u64) { panic("shr #1842") }
    if !(shl_assign(20u64, (read 3i32)) == 160u64) { panic("shl_assign #1843") }
    if !(shr_assign(20u64, (read 3i32)) == 2u64) { panic("shr_assign #1844") }
    if !(shl(20u64, 3i64) == 160u64) { panic("shl #1845") }
    if !(shr(20u64, 3i64) == 2u64) { panic("shr #1846") }
    if !(shl((read 20u64), 3i64) == 160u64) { panic("shl #1847") }
    if !(shr((read 20u64), 3i64) == 2u64) { panic("shr #1848") }
    if !(shl_assign(20u64, 3i64) == 160u64) { panic("shl_assign #1849") }
    if !(shr_assign(20u64, 3i64) == 2u64) { panic("shr_assign #1850") }
    if !(shl(20u64, (read 3i64)) == 160u64) { panic("shl #1851") }
    if !(shr(20u64, (read 3i64)) == 2u64) { panic("shr #1852") }
    if !(shl((read 20u64), (read 3i64)) == 160u64) { panic("shl #1853") }
    if !(shr((read 20u64), (read 3i64)) == 2u64) { panic("shr #1854") }
    if !(shl_assign(20u64, (read 3i64)) == 160u64) { panic("shl_assign #1855") }
    if !(shr_assign(20u64, (read 3i64)) == 2u64) { panic("shr_assign #1856") }
    if !(shl(20u64, 3i128) == 160u64) { panic("shl #1857") }
    if !(shr(20u64, 3i128) == 2u64) { panic("shr #1858") }
    if !(shl((read 20u64), 3i128) == 160u64) { panic("shl #1859") }
    if !(shr((read 20u64), 3i128) == 2u64) { panic("shr #1860") }
    if !(shl_assign(20u64, 3i128) == 160u64) { panic("shl_assign #1861") }
    if !(shr_assign(20u64, 3i128) == 2u64) { panic("shr_assign #1862") }
    if !(shl(20u64, (read 3i128)) == 160u64) { panic("shl #1863") }
    if !(shr(20u64, (read 3i128)) == 2u64) { panic("shr #1864") }
    if !(shl((read 20u64), (read 3i128)) == 160u64) { panic("shl #1865") }
    if !(shr((read 20u64), (read 3i128)) == 2u64) { panic("shr #1866") }
    if !(shl_assign(20u64, (read 3i128)) == 160u64) { panic("shl_assign #1867") }
    if !(shr_assign(20u64, (read 3i128)) == 2u64) { panic("shr_assign #1868") }
    if !(shl(20u64, 3isize) == 160u64) { panic("shl #1869") }
    if !(shr(20u64, 3isize) == 2u64) { panic("shr #1870") }
    if !(shl((read 20u64), 3isize) == 160u64) { panic("shl #1871") }
    if !(shr((read 20u64), 3isize) == 2u64) { panic("shr #1872") }
    if !(shl_assign(20u64, 3isize) == 160u64) { panic("shl_assign #1873") }
    if !(shr_assign(20u64, 3isize) == 2u64) { panic("shr_assign #1874") }
    if !(shl(20u64, (read 3isize)) == 160u64) { panic("shl #1875") }
    if !(shr(20u64, (read 3isize)) == 2u64) { panic("shr #1876") }
    if !(shl((read 20u64), (read 3isize)) == 160u64) { panic("shl #1877") }
    if !(shr((read 20u64), (read 3isize)) == 2u64) { panic("shr #1878") }
    if !(shl_assign(20u64, (read 3isize)) == 160u64) { panic("shl_assign #1879") }
    if !(shr_assign(20u64, (read 3isize)) == 2u64) { panic("shr_assign #1880") }
    if !(shl(20u64, 3u8) == 160u64) { panic("shl #1881") }
    if !(shr(20u64, 3u8) == 2u64) { panic("shr #1882") }
    if !(shl((read 20u64), 3u8) == 160u64) { panic("shl #1883") }
    if !(shr((read 20u64), 3u8) == 2u64) { panic("shr #1884") }
    if !(shl_assign(20u64, 3u8) == 160u64) { panic("shl_assign #1885") }
    if !(shr_assign(20u64, 3u8) == 2u64) { panic("shr_assign #1886") }
    if !(shl(20u64, (read 3u8)) == 160u64) { panic("shl #1887") }
    if !(shr(20u64, (read 3u8)) == 2u64) { panic("shr #1888") }
    if !(shl((read 20u64), (read 3u8)) == 160u64) { panic("shl #1889") }
    if !(shr((read 20u64), (read 3u8)) == 2u64) { panic("shr #1890") }
    if !(shl_assign(20u64, (read 3u8)) == 160u64) { panic("shl_assign #1891") }
    if !(shr_assign(20u64, (read 3u8)) == 2u64) { panic("shr_assign #1892") }
    if !(shl(20u64, 3u16) == 160u64) { panic("shl #1893") }
    if !(shr(20u64, 3u16) == 2u64) { panic("shr #1894") }
    if !(shl((read 20u64), 3u16) == 160u64) { panic("shl #1895") }
    if !(shr((read 20u64), 3u16) == 2u64) { panic("shr #1896") }
    if !(shl_assign(20u64, 3u16) == 160u64) { panic("shl_assign #1897") }
    if !(shr_assign(20u64, 3u16) == 2u64) { panic("shr_assign #1898") }
    if !(shl(20u64, (read 3u16)) == 160u64) { panic("shl #1899") }
    if !(shr(20u64, (read 3u16)) == 2u64) { panic("shr #1900") }
    if !(shl((read 20u64), (read 3u16)) == 160u64) { panic("shl #1901") }
    if !(shr((read 20u64), (read 3u16)) == 2u64) { panic("shr #1902") }
    if !(shl_assign(20u64, (read 3u16)) == 160u64) { panic("shl_assign #1903") }
    if !(shr_assign(20u64, (read 3u16)) == 2u64) { panic("shr_assign #1904") }
    if !(shl(20u64, 3u32) == 160u64) { panic("shl #1905") }
    if !(shr(20u64, 3u32) == 2u64) { panic("shr #1906") }
    if !(shl((read 20u64), 3u32) == 160u64) { panic("shl #1907") }
    if !(shr((read 20u64), 3u32) == 2u64) { panic("shr #1908") }
    if !(shl_assign(20u64, 3u32) == 160u64) { panic("shl_assign #1909") }
    if !(shr_assign(20u64, 3u32) == 2u64) { panic("shr_assign #1910") }
    if !(shl(20u64, (read 3u32)) == 160u64) { panic("shl #1911") }
    if !(shr(20u64, (read 3u32)) == 2u64) { panic("shr #1912") }
    if !(shl((read 20u64), (read 3u32)) == 160u64) { panic("shl #1913") }
    if !(shr((read 20u64), (read 3u32)) == 2u64) { panic("shr #1914") }
    if !(shl_assign(20u64, (read 3u32)) == 160u64) { panic("shl_assign #1915") }
    if !(shr_assign(20u64, (read 3u32)) == 2u64) { panic("shr_assign #1916") }
    if !(shl(20u64, 3u64) == 160u64) { panic("shl #1917") }
    if !(shr(20u64, 3u64) == 2u64) { panic("shr #1918") }
    if !(shl((read 20u64), 3u64) == 160u64) { panic("shl #1919") }
    if !(shr((read 20u64), 3u64) == 2u64) { panic("shr #1920") }
    if !(shl_assign(20u64, 3u64) == 160u64) { panic("shl_assign #1921") }
    if !(shr_assign(20u64, 3u64) == 2u64) { panic("shr_assign #1922") }
    if !(shl(20u64, (read 3u64)) == 160u64) { panic("shl #1923") }
    if !(shr(20u64, (read 3u64)) == 2u64) { panic("shr #1924") }
    if !(shl((read 20u64), (read 3u64)) == 160u64) { panic("shl #1925") }
    if !(shr((read 20u64), (read 3u64)) == 2u64) { panic("shr #1926") }
    if !(shl_assign(20u64, (read 3u64)) == 160u64) { panic("shl_assign #1927") }
    if !(shr_assign(20u64, (read 3u64)) == 2u64) { panic("shr_assign #1928") }
    if !(shl(20u64, 3u128) == 160u64) { panic("shl #1929") }
    if !(shr(20u64, 3u128) == 2u64) { panic("shr #1930") }
    if !(shl((read 20u64), 3u128) == 160u64) { panic("shl #1931") }
    if !(shr((read 20u64), 3u128) == 2u64) { panic("shr #1932") }
    if !(shl_assign(20u64, 3u128) == 160u64) { panic("shl_assign #1933") }
    if !(shr_assign(20u64, 3u128) == 2u64) { panic("shr_assign #1934") }
    if !(shl(20u64, (read 3u128)) == 160u64) { panic("shl #1935") }
    if !(shr(20u64, (read 3u128)) == 2u64) { panic("shr #1936") }
    if !(shl((read 20u64), (read 3u128)) == 160u64) { panic("shl #1937") }
    if !(shr((read 20u64), (read 3u128)) == 2u64) { panic("shr #1938") }
    if !(shl_assign(20u64, (read 3u128)) == 160u64) { panic("shl_assign #1939") }
    if !(shr_assign(20u64, (read 3u128)) == 2u64) { panic("shr_assign #1940") }
    if !(shl(20u64, 3usize) == 160u64) { panic("shl #1941") }
    if !(shr(20u64, 3usize) == 2u64) { panic("shr #1942") }
    if !(shl((read 20u64), 3usize) == 160u64) { panic("shl #1943") }
    if !(shr((read 20u64), 3usize) == 2u64) { panic("shr #1944") }
    if !(shl_assign(20u64, 3usize) == 160u64) { panic("shl_assign #1945") }
    if !(shr_assign(20u64, 3usize) == 2u64) { panic("shr_assign #1946") }
    if !(shl(20u64, (read 3usize)) == 160u64) { panic("shl #1947") }
    if !(shr(20u64, (read 3usize)) == 2u64) { panic("shr #1948") }
    if !(shl((read 20u64), (read 3usize)) == 160u64) { panic("shl #1949") }
    if !(shr((read 20u64), (read 3usize)) == 2u64) { panic("shr #1950") }
}

fn group13() {
    if !(shl_assign(20u64, (read 3usize)) == 160u64) { panic("shl_assign #1951") }
    if !(shr_assign(20u64, (read 3usize)) == 2u64) { panic("shr_assign #1952") }
    if !(add(20u128, 7u128) == 27u128) { panic("add #1953") }
    if !(add((read 20u128), 7u128) == 27u128) { panic("add #1954") }
    if !(add(20u128, (read 7u128)) == 27u128) { panic("add #1955") }
    if !(add((read 20u128), (read 7u128)) == 27u128) { panic("add #1956") }
    if !(add_assign(20u128, 7u128) == 27u128) { panic("add_assign #1957") }
    if !(add_assign(20u128, (read 7u128)) == 27u128) { panic("add_assign #1958") }
    if !(sub(20u128, 7u128) == 13u128) { panic("sub #1959") }
    if !(sub((read 20u128), 7u128) == 13u128) { panic("sub #1960") }
    if !(sub(20u128, (read 7u128)) == 13u128) { panic("sub #1961") }
    if !(sub((read 20u128), (read 7u128)) == 13u128) { panic("sub #1962") }
    if !(sub_assign(20u128, 7u128) == 13u128) { panic("sub_assign #1963") }
    if !(sub_assign(20u128, (read 7u128)) == 13u128) { panic("sub_assign #1964") }
    if !(mul(20u128, 7u128) == 140u128) { panic("mul #1965") }
    if !(mul((read 20u128), 7u128) == 140u128) { panic("mul #1966") }
    if !(mul(20u128, (read 7u128)) == 140u128) { panic("mul #1967") }
    if !(mul((read 20u128), (read 7u128)) == 140u128) { panic("mul #1968") }
    if !(mul_assign(20u128, 7u128) == 140u128) { panic("mul_assign #1969") }
    if !(mul_assign(20u128, (read 7u128)) == 140u128) { panic("mul_assign #1970") }
    if !(div(20u128, 7u128) == 2u128) { panic("div #1971") }
    if !(div((read 20u128), 7u128) == 2u128) { panic("div #1972") }
    if !(div(20u128, (read 7u128)) == 2u128) { panic("div #1973") }
    if !(div((read 20u128), (read 7u128)) == 2u128) { panic("div #1974") }
    if !(div_assign(20u128, 7u128) == 2u128) { panic("div_assign #1975") }
    if !(div_assign(20u128, (read 7u128)) == 2u128) { panic("div_assign #1976") }
    if !(rem(20u128, 7u128) == 6u128) { panic("rem #1977") }
    if !(rem((read 20u128), 7u128) == 6u128) { panic("rem #1978") }
    if !(rem(20u128, (read 7u128)) == 6u128) { panic("rem #1979") }
    if !(rem((read 20u128), (read 7u128)) == 6u128) { panic("rem #1980") }
    if !(rem_assign(20u128, 7u128) == 6u128) { panic("rem_assign #1981") }
    if !(rem_assign(20u128, (read 7u128)) == 6u128) { panic("rem_assign #1982") }
    if !(and(20u128, 7u128) == 4u128) { panic("and #1983") }
    if !(and((read 20u128), 7u128) == 4u128) { panic("and #1984") }
    if !(and(20u128, (read 7u128)) == 4u128) { panic("and #1985") }
    if !(and((read 20u128), (read 7u128)) == 4u128) { panic("and #1986") }
    if !(and_assign(20u128, 7u128) == 4u128) { panic("and_assign #1987") }
    if !(and_assign(20u128, (read 7u128)) == 4u128) { panic("and_assign #1988") }
    if !(or(20u128, 7u128) == 23u128) { panic("or #1989") }
    if !(or((read 20u128), 7u128) == 23u128) { panic("or #1990") }
    if !(or(20u128, (read 7u128)) == 23u128) { panic("or #1991") }
    if !(or((read 20u128), (read 7u128)) == 23u128) { panic("or #1992") }
    if !(or_assign(20u128, 7u128) == 23u128) { panic("or_assign #1993") }
    if !(or_assign(20u128, (read 7u128)) == 23u128) { panic("or_assign #1994") }
    if !(xor(20u128, 7u128) == 19u128) { panic("xor #1995") }
    if !(xor((read 20u128), 7u128) == 19u128) { panic("xor #1996") }
    if !(xor(20u128, (read 7u128)) == 19u128) { panic("xor #1997") }
    if !(xor((read 20u128), (read 7u128)) == 19u128) { panic("xor #1998") }
    if !(xor_assign(20u128, 7u128) == 19u128) { panic("xor_assign #1999") }
    if !(xor_assign(20u128, (read 7u128)) == 19u128) { panic("xor_assign #2000") }
    if !(not(20u128) == 340282366920938463463374607431768211435u128) { panic("not #2001") }
    if !(not((read 20u128)) == 340282366920938463463374607431768211435u128) { panic("not #2002") }
    if !(shl(20u128, 3i8) == 160u128) { panic("shl #2003") }
    if !(shr(20u128, 3i8) == 2u128) { panic("shr #2004") }
    if !(shl((read 20u128), 3i8) == 160u128) { panic("shl #2005") }
    if !(shr((read 20u128), 3i8) == 2u128) { panic("shr #2006") }
    if !(shl_assign(20u128, 3i8) == 160u128) { panic("shl_assign #2007") }
    if !(shr_assign(20u128, 3i8) == 2u128) { panic("shr_assign #2008") }
    if !(shl(20u128, (read 3i8)) == 160u128) { panic("shl #2009") }
    if !(shr(20u128, (read 3i8)) == 2u128) { panic("shr #2010") }
    if !(shl((read 20u128), (read 3i8)) == 160u128) { panic("shl #2011") }
    if !(shr((read 20u128), (read 3i8)) == 2u128) { panic("shr #2012") }
    if !(shl_assign(20u128, (read 3i8)) == 160u128) { panic("shl_assign #2013") }
    if !(shr_assign(20u128, (read 3i8)) == 2u128) { panic("shr_assign #2014") }
    if !(shl(20u128, 3i16) == 160u128) { panic("shl #2015") }
    if !(shr(20u128, 3i16) == 2u128) { panic("shr #2016") }
    if !(shl((read 20u128), 3i16) == 160u128) { panic("shl #2017") }
    if !(shr((read 20u128), 3i16) == 2u128) { panic("shr #2018") }
    if !(shl_assign(20u128, 3i16) == 160u128) { panic("shl_assign #2019") }
    if !(shr_assign(20u128, 3i16) == 2u128) { panic("shr_assign #2020") }
    if !(shl(20u128, (read 3i16)) == 160u128) { panic("shl #2021") }
    if !(shr(20u128, (read 3i16)) == 2u128) { panic("shr #2022") }
    if !(shl((read 20u128), (read 3i16)) == 160u128) { panic("shl #2023") }
    if !(shr((read 20u128), (read 3i16)) == 2u128) { panic("shr #2024") }
    if !(shl_assign(20u128, (read 3i16)) == 160u128) { panic("shl_assign #2025") }
    if !(shr_assign(20u128, (read 3i16)) == 2u128) { panic("shr_assign #2026") }
    if !(shl(20u128, 3i32) == 160u128) { panic("shl #2027") }
    if !(shr(20u128, 3i32) == 2u128) { panic("shr #2028") }
    if !(shl((read 20u128), 3i32) == 160u128) { panic("shl #2029") }
    if !(shr((read 20u128), 3i32) == 2u128) { panic("shr #2030") }
    if !(shl_assign(20u128, 3i32) == 160u128) { panic("shl_assign #2031") }
    if !(shr_assign(20u128, 3i32) == 2u128) { panic("shr_assign #2032") }
    if !(shl(20u128, (read 3i32)) == 160u128) { panic("shl #2033") }
    if !(shr(20u128, (read 3i32)) == 2u128) { panic("shr #2034") }
    if !(shl((read 20u128), (read 3i32)) == 160u128) { panic("shl #2035") }
    if !(shr((read 20u128), (read 3i32)) == 2u128) { panic("shr #2036") }
    if !(shl_assign(20u128, (read 3i32)) == 160u128) { panic("shl_assign #2037") }
    if !(shr_assign(20u128, (read 3i32)) == 2u128) { panic("shr_assign #2038") }
    if !(shl(20u128, 3i64) == 160u128) { panic("shl #2039") }
    if !(shr(20u128, 3i64) == 2u128) { panic("shr #2040") }
    if !(shl((read 20u128), 3i64) == 160u128) { panic("shl #2041") }
    if !(shr((read 20u128), 3i64) == 2u128) { panic("shr #2042") }
    if !(shl_assign(20u128, 3i64) == 160u128) { panic("shl_assign #2043") }
    if !(shr_assign(20u128, 3i64) == 2u128) { panic("shr_assign #2044") }
    if !(shl(20u128, (read 3i64)) == 160u128) { panic("shl #2045") }
    if !(shr(20u128, (read 3i64)) == 2u128) { panic("shr #2046") }
    if !(shl((read 20u128), (read 3i64)) == 160u128) { panic("shl #2047") }
    if !(shr((read 20u128), (read 3i64)) == 2u128) { panic("shr #2048") }
    if !(shl_assign(20u128, (read 3i64)) == 160u128) { panic("shl_assign #2049") }
    if !(shr_assign(20u128, (read 3i64)) == 2u128) { panic("shr_assign #2050") }
    if !(shl(20u128, 3i128) == 160u128) { panic("shl #2051") }
    if !(shr(20u128, 3i128) == 2u128) { panic("shr #2052") }
    if !(shl((read 20u128), 3i128) == 160u128) { panic("shl #2053") }
    if !(shr((read 20u128), 3i128) == 2u128) { panic("shr #2054") }
    if !(shl_assign(20u128, 3i128) == 160u128) { panic("shl_assign #2055") }
    if !(shr_assign(20u128, 3i128) == 2u128) { panic("shr_assign #2056") }
    if !(shl(20u128, (read 3i128)) == 160u128) { panic("shl #2057") }
    if !(shr(20u128, (read 3i128)) == 2u128) { panic("shr #2058") }
    if !(shl((read 20u128), (read 3i128)) == 160u128) { panic("shl #2059") }
    if !(shr((read 20u128), (read 3i128)) == 2u128) { panic("shr #2060") }
    if !(shl_assign(20u128, (read 3i128)) == 160u128) { panic("shl_assign #2061") }
    if !(shr_assign(20u128, (read 3i128)) == 2u128) { panic("shr_assign #2062") }
    if !(shl(20u128, 3isize) == 160u128) { panic("shl #2063") }
    if !(shr(20u128, 3isize) == 2u128) { panic("shr #2064") }
    if !(shl((read 20u128), 3isize) == 160u128) { panic("shl #2065") }
    if !(shr((read 20u128), 3isize) == 2u128) { panic("shr #2066") }
    if !(shl_assign(20u128, 3isize) == 160u128) { panic("shl_assign #2067") }
    if !(shr_assign(20u128, 3isize) == 2u128) { panic("shr_assign #2068") }
    if !(shl(20u128, (read 3isize)) == 160u128) { panic("shl #2069") }
    if !(shr(20u128, (read 3isize)) == 2u128) { panic("shr #2070") }
    if !(shl((read 20u128), (read 3isize)) == 160u128) { panic("shl #2071") }
    if !(shr((read 20u128), (read 3isize)) == 2u128) { panic("shr #2072") }
    if !(shl_assign(20u128, (read 3isize)) == 160u128) { panic("shl_assign #2073") }
    if !(shr_assign(20u128, (read 3isize)) == 2u128) { panic("shr_assign #2074") }
    if !(shl(20u128, 3u8) == 160u128) { panic("shl #2075") }
    if !(shr(20u128, 3u8) == 2u128) { panic("shr #2076") }
    if !(shl((read 20u128), 3u8) == 160u128) { panic("shl #2077") }
    if !(shr((read 20u128), 3u8) == 2u128) { panic("shr #2078") }
    if !(shl_assign(20u128, 3u8) == 160u128) { panic("shl_assign #2079") }
    if !(shr_assign(20u128, 3u8) == 2u128) { panic("shr_assign #2080") }
    if !(shl(20u128, (read 3u8)) == 160u128) { panic("shl #2081") }
    if !(shr(20u128, (read 3u8)) == 2u128) { panic("shr #2082") }
    if !(shl((read 20u128), (read 3u8)) == 160u128) { panic("shl #2083") }
    if !(shr((read 20u128), (read 3u8)) == 2u128) { panic("shr #2084") }
    if !(shl_assign(20u128, (read 3u8)) == 160u128) { panic("shl_assign #2085") }
    if !(shr_assign(20u128, (read 3u8)) == 2u128) { panic("shr_assign #2086") }
    if !(shl(20u128, 3u16) == 160u128) { panic("shl #2087") }
    if !(shr(20u128, 3u16) == 2u128) { panic("shr #2088") }
    if !(shl((read 20u128), 3u16) == 160u128) { panic("shl #2089") }
    if !(shr((read 20u128), 3u16) == 2u128) { panic("shr #2090") }
    if !(shl_assign(20u128, 3u16) == 160u128) { panic("shl_assign #2091") }
    if !(shr_assign(20u128, 3u16) == 2u128) { panic("shr_assign #2092") }
    if !(shl(20u128, (read 3u16)) == 160u128) { panic("shl #2093") }
    if !(shr(20u128, (read 3u16)) == 2u128) { panic("shr #2094") }
    if !(shl((read 20u128), (read 3u16)) == 160u128) { panic("shl #2095") }
    if !(shr((read 20u128), (read 3u16)) == 2u128) { panic("shr #2096") }
    if !(shl_assign(20u128, (read 3u16)) == 160u128) { panic("shl_assign #2097") }
    if !(shr_assign(20u128, (read 3u16)) == 2u128) { panic("shr_assign #2098") }
    if !(shl(20u128, 3u32) == 160u128) { panic("shl #2099") }
    if !(shr(20u128, 3u32) == 2u128) { panic("shr #2100") }
}

fn group14() {
    if !(shl((read 20u128), 3u32) == 160u128) { panic("shl #2101") }
    if !(shr((read 20u128), 3u32) == 2u128) { panic("shr #2102") }
    if !(shl_assign(20u128, 3u32) == 160u128) { panic("shl_assign #2103") }
    if !(shr_assign(20u128, 3u32) == 2u128) { panic("shr_assign #2104") }
    if !(shl(20u128, (read 3u32)) == 160u128) { panic("shl #2105") }
    if !(shr(20u128, (read 3u32)) == 2u128) { panic("shr #2106") }
    if !(shl((read 20u128), (read 3u32)) == 160u128) { panic("shl #2107") }
    if !(shr((read 20u128), (read 3u32)) == 2u128) { panic("shr #2108") }
    if !(shl_assign(20u128, (read 3u32)) == 160u128) { panic("shl_assign #2109") }
    if !(shr_assign(20u128, (read 3u32)) == 2u128) { panic("shr_assign #2110") }
    if !(shl(20u128, 3u64) == 160u128) { panic("shl #2111") }
    if !(shr(20u128, 3u64) == 2u128) { panic("shr #2112") }
    if !(shl((read 20u128), 3u64) == 160u128) { panic("shl #2113") }
    if !(shr((read 20u128), 3u64) == 2u128) { panic("shr #2114") }
    if !(shl_assign(20u128, 3u64) == 160u128) { panic("shl_assign #2115") }
    if !(shr_assign(20u128, 3u64) == 2u128) { panic("shr_assign #2116") }
    if !(shl(20u128, (read 3u64)) == 160u128) { panic("shl #2117") }
    if !(shr(20u128, (read 3u64)) == 2u128) { panic("shr #2118") }
    if !(shl((read 20u128), (read 3u64)) == 160u128) { panic("shl #2119") }
    if !(shr((read 20u128), (read 3u64)) == 2u128) { panic("shr #2120") }
    if !(shl_assign(20u128, (read 3u64)) == 160u128) { panic("shl_assign #2121") }
    if !(shr_assign(20u128, (read 3u64)) == 2u128) { panic("shr_assign #2122") }
    if !(shl(20u128, 3u128) == 160u128) { panic("shl #2123") }
    if !(shr(20u128, 3u128) == 2u128) { panic("shr #2124") }
    if !(shl((read 20u128), 3u128) == 160u128) { panic("shl #2125") }
    if !(shr((read 20u128), 3u128) == 2u128) { panic("shr #2126") }
    if !(shl_assign(20u128, 3u128) == 160u128) { panic("shl_assign #2127") }
    if !(shr_assign(20u128, 3u128) == 2u128) { panic("shr_assign #2128") }
    if !(shl(20u128, (read 3u128)) == 160u128) { panic("shl #2129") }
    if !(shr(20u128, (read 3u128)) == 2u128) { panic("shr #2130") }
    if !(shl((read 20u128), (read 3u128)) == 160u128) { panic("shl #2131") }
    if !(shr((read 20u128), (read 3u128)) == 2u128) { panic("shr #2132") }
    if !(shl_assign(20u128, (read 3u128)) == 160u128) { panic("shl_assign #2133") }
    if !(shr_assign(20u128, (read 3u128)) == 2u128) { panic("shr_assign #2134") }
    if !(shl(20u128, 3usize) == 160u128) { panic("shl #2135") }
    if !(shr(20u128, 3usize) == 2u128) { panic("shr #2136") }
    if !(shl((read 20u128), 3usize) == 160u128) { panic("shl #2137") }
    if !(shr((read 20u128), 3usize) == 2u128) { panic("shr #2138") }
    if !(shl_assign(20u128, 3usize) == 160u128) { panic("shl_assign #2139") }
    if !(shr_assign(20u128, 3usize) == 2u128) { panic("shr_assign #2140") }
    if !(shl(20u128, (read 3usize)) == 160u128) { panic("shl #2141") }
    if !(shr(20u128, (read 3usize)) == 2u128) { panic("shr #2142") }
    if !(shl((read 20u128), (read 3usize)) == 160u128) { panic("shl #2143") }
    if !(shr((read 20u128), (read 3usize)) == 2u128) { panic("shr #2144") }
    if !(shl_assign(20u128, (read 3usize)) == 160u128) { panic("shl_assign #2145") }
    if !(shr_assign(20u128, (read 3usize)) == 2u128) { panic("shr_assign #2146") }
    if !(add(20usize, 7usize) == 27usize) { panic("add #2147") }
    if !(add((read 20usize), 7usize) == 27usize) { panic("add #2148") }
    if !(add(20usize, (read 7usize)) == 27usize) { panic("add #2149") }
    if !(add((read 20usize), (read 7usize)) == 27usize) { panic("add #2150") }
    if !(add_assign(20usize, 7usize) == 27usize) { panic("add_assign #2151") }
    if !(add_assign(20usize, (read 7usize)) == 27usize) { panic("add_assign #2152") }
    if !(sub(20usize, 7usize) == 13usize) { panic("sub #2153") }
    if !(sub((read 20usize), 7usize) == 13usize) { panic("sub #2154") }
    if !(sub(20usize, (read 7usize)) == 13usize) { panic("sub #2155") }
    if !(sub((read 20usize), (read 7usize)) == 13usize) { panic("sub #2156") }
    if !(sub_assign(20usize, 7usize) == 13usize) { panic("sub_assign #2157") }
    if !(sub_assign(20usize, (read 7usize)) == 13usize) { panic("sub_assign #2158") }
    if !(mul(20usize, 7usize) == 140usize) { panic("mul #2159") }
    if !(mul((read 20usize), 7usize) == 140usize) { panic("mul #2160") }
    if !(mul(20usize, (read 7usize)) == 140usize) { panic("mul #2161") }
    if !(mul((read 20usize), (read 7usize)) == 140usize) { panic("mul #2162") }
    if !(mul_assign(20usize, 7usize) == 140usize) { panic("mul_assign #2163") }
    if !(mul_assign(20usize, (read 7usize)) == 140usize) { panic("mul_assign #2164") }
    if !(div(20usize, 7usize) == 2usize) { panic("div #2165") }
    if !(div((read 20usize), 7usize) == 2usize) { panic("div #2166") }
    if !(div(20usize, (read 7usize)) == 2usize) { panic("div #2167") }
    if !(div((read 20usize), (read 7usize)) == 2usize) { panic("div #2168") }
    if !(div_assign(20usize, 7usize) == 2usize) { panic("div_assign #2169") }
    if !(div_assign(20usize, (read 7usize)) == 2usize) { panic("div_assign #2170") }
    if !(rem(20usize, 7usize) == 6usize) { panic("rem #2171") }
    if !(rem((read 20usize), 7usize) == 6usize) { panic("rem #2172") }
    if !(rem(20usize, (read 7usize)) == 6usize) { panic("rem #2173") }
    if !(rem((read 20usize), (read 7usize)) == 6usize) { panic("rem #2174") }
    if !(rem_assign(20usize, 7usize) == 6usize) { panic("rem_assign #2175") }
    if !(rem_assign(20usize, (read 7usize)) == 6usize) { panic("rem_assign #2176") }
    if !(and(20usize, 7usize) == 4usize) { panic("and #2177") }
    if !(and((read 20usize), 7usize) == 4usize) { panic("and #2178") }
    if !(and(20usize, (read 7usize)) == 4usize) { panic("and #2179") }
    if !(and((read 20usize), (read 7usize)) == 4usize) { panic("and #2180") }
    if !(and_assign(20usize, 7usize) == 4usize) { panic("and_assign #2181") }
    if !(and_assign(20usize, (read 7usize)) == 4usize) { panic("and_assign #2182") }
    if !(or(20usize, 7usize) == 23usize) { panic("or #2183") }
    if !(or((read 20usize), 7usize) == 23usize) { panic("or #2184") }
    if !(or(20usize, (read 7usize)) == 23usize) { panic("or #2185") }
    if !(or((read 20usize), (read 7usize)) == 23usize) { panic("or #2186") }
    if !(or_assign(20usize, 7usize) == 23usize) { panic("or_assign #2187") }
    if !(or_assign(20usize, (read 7usize)) == 23usize) { panic("or_assign #2188") }
    if !(xor(20usize, 7usize) == 19usize) { panic("xor #2189") }
    if !(xor((read 20usize), 7usize) == 19usize) { panic("xor #2190") }
    if !(xor(20usize, (read 7usize)) == 19usize) { panic("xor #2191") }
    if !(xor((read 20usize), (read 7usize)) == 19usize) { panic("xor #2192") }
    if !(xor_assign(20usize, 7usize) == 19usize) { panic("xor_assign #2193") }
    if !(xor_assign(20usize, (read 7usize)) == 19usize) { panic("xor_assign #2194") }
    if !(not(20usize) == 18446744073709551595usize) { panic("not #2195") }
    if !(not((read 20usize)) == 18446744073709551595usize) { panic("not #2196") }
    if !(shl(20usize, 3i8) == 160usize) { panic("shl #2197") }
    if !(shr(20usize, 3i8) == 2usize) { panic("shr #2198") }
    if !(shl((read 20usize), 3i8) == 160usize) { panic("shl #2199") }
    if !(shr((read 20usize), 3i8) == 2usize) { panic("shr #2200") }
    if !(shl_assign(20usize, 3i8) == 160usize) { panic("shl_assign #2201") }
    if !(shr_assign(20usize, 3i8) == 2usize) { panic("shr_assign #2202") }
    if !(shl(20usize, (read 3i8)) == 160usize) { panic("shl #2203") }
    if !(shr(20usize, (read 3i8)) == 2usize) { panic("shr #2204") }
    if !(shl((read 20usize), (read 3i8)) == 160usize) { panic("shl #2205") }
    if !(shr((read 20usize), (read 3i8)) == 2usize) { panic("shr #2206") }
    if !(shl_assign(20usize, (read 3i8)) == 160usize) { panic("shl_assign #2207") }
    if !(shr_assign(20usize, (read 3i8)) == 2usize) { panic("shr_assign #2208") }
    if !(shl(20usize, 3i16) == 160usize) { panic("shl #2209") }
    if !(shr(20usize, 3i16) == 2usize) { panic("shr #2210") }
    if !(shl((read 20usize), 3i16) == 160usize) { panic("shl #2211") }
    if !(shr((read 20usize), 3i16) == 2usize) { panic("shr #2212") }
    if !(shl_assign(20usize, 3i16) == 160usize) { panic("shl_assign #2213") }
    if !(shr_assign(20usize, 3i16) == 2usize) { panic("shr_assign #2214") }
    if !(shl(20usize, (read 3i16)) == 160usize) { panic("shl #2215") }
    if !(shr(20usize, (read 3i16)) == 2usize) { panic("shr #2216") }
    if !(shl((read 20usize), (read 3i16)) == 160usize) { panic("shl #2217") }
    if !(shr((read 20usize), (read 3i16)) == 2usize) { panic("shr #2218") }
    if !(shl_assign(20usize, (read 3i16)) == 160usize) { panic("shl_assign #2219") }
    if !(shr_assign(20usize, (read 3i16)) == 2usize) { panic("shr_assign #2220") }
    if !(shl(20usize, 3i32) == 160usize) { panic("shl #2221") }
    if !(shr(20usize, 3i32) == 2usize) { panic("shr #2222") }
    if !(shl((read 20usize), 3i32) == 160usize) { panic("shl #2223") }
    if !(shr((read 20usize), 3i32) == 2usize) { panic("shr #2224") }
    if !(shl_assign(20usize, 3i32) == 160usize) { panic("shl_assign #2225") }
    if !(shr_assign(20usize, 3i32) == 2usize) { panic("shr_assign #2226") }
    if !(shl(20usize, (read 3i32)) == 160usize) { panic("shl #2227") }
    if !(shr(20usize, (read 3i32)) == 2usize) { panic("shr #2228") }
    if !(shl((read 20usize), (read 3i32)) == 160usize) { panic("shl #2229") }
    if !(shr((read 20usize), (read 3i32)) == 2usize) { panic("shr #2230") }
    if !(shl_assign(20usize, (read 3i32)) == 160usize) { panic("shl_assign #2231") }
    if !(shr_assign(20usize, (read 3i32)) == 2usize) { panic("shr_assign #2232") }
    if !(shl(20usize, 3i64) == 160usize) { panic("shl #2233") }
    if !(shr(20usize, 3i64) == 2usize) { panic("shr #2234") }
    if !(shl((read 20usize), 3i64) == 160usize) { panic("shl #2235") }
    if !(shr((read 20usize), 3i64) == 2usize) { panic("shr #2236") }
    if !(shl_assign(20usize, 3i64) == 160usize) { panic("shl_assign #2237") }
    if !(shr_assign(20usize, 3i64) == 2usize) { panic("shr_assign #2238") }
    if !(shl(20usize, (read 3i64)) == 160usize) { panic("shl #2239") }
    if !(shr(20usize, (read 3i64)) == 2usize) { panic("shr #2240") }
    if !(shl((read 20usize), (read 3i64)) == 160usize) { panic("shl #2241") }
    if !(shr((read 20usize), (read 3i64)) == 2usize) { panic("shr #2242") }
    if !(shl_assign(20usize, (read 3i64)) == 160usize) { panic("shl_assign #2243") }
    if !(shr_assign(20usize, (read 3i64)) == 2usize) { panic("shr_assign #2244") }
    if !(shl(20usize, 3i128) == 160usize) { panic("shl #2245") }
    if !(shr(20usize, 3i128) == 2usize) { panic("shr #2246") }
    if !(shl((read 20usize), 3i128) == 160usize) { panic("shl #2247") }
    if !(shr((read 20usize), 3i128) == 2usize) { panic("shr #2248") }
    if !(shl_assign(20usize, 3i128) == 160usize) { panic("shl_assign #2249") }
    if !(shr_assign(20usize, 3i128) == 2usize) { panic("shr_assign #2250") }
}

fn group15() {
    if !(shl(20usize, (read 3i128)) == 160usize) { panic("shl #2251") }
    if !(shr(20usize, (read 3i128)) == 2usize) { panic("shr #2252") }
    if !(shl((read 20usize), (read 3i128)) == 160usize) { panic("shl #2253") }
    if !(shr((read 20usize), (read 3i128)) == 2usize) { panic("shr #2254") }
    if !(shl_assign(20usize, (read 3i128)) == 160usize) { panic("shl_assign #2255") }
    if !(shr_assign(20usize, (read 3i128)) == 2usize) { panic("shr_assign #2256") }
    if !(shl(20usize, 3isize) == 160usize) { panic("shl #2257") }
    if !(shr(20usize, 3isize) == 2usize) { panic("shr #2258") }
    if !(shl((read 20usize), 3isize) == 160usize) { panic("shl #2259") }
    if !(shr((read 20usize), 3isize) == 2usize) { panic("shr #2260") }
    if !(shl_assign(20usize, 3isize) == 160usize) { panic("shl_assign #2261") }
    if !(shr_assign(20usize, 3isize) == 2usize) { panic("shr_assign #2262") }
    if !(shl(20usize, (read 3isize)) == 160usize) { panic("shl #2263") }
    if !(shr(20usize, (read 3isize)) == 2usize) { panic("shr #2264") }
    if !(shl((read 20usize), (read 3isize)) == 160usize) { panic("shl #2265") }
    if !(shr((read 20usize), (read 3isize)) == 2usize) { panic("shr #2266") }
    if !(shl_assign(20usize, (read 3isize)) == 160usize) { panic("shl_assign #2267") }
    if !(shr_assign(20usize, (read 3isize)) == 2usize) { panic("shr_assign #2268") }
    if !(shl(20usize, 3u8) == 160usize) { panic("shl #2269") }
    if !(shr(20usize, 3u8) == 2usize) { panic("shr #2270") }
    if !(shl((read 20usize), 3u8) == 160usize) { panic("shl #2271") }
    if !(shr((read 20usize), 3u8) == 2usize) { panic("shr #2272") }
    if !(shl_assign(20usize, 3u8) == 160usize) { panic("shl_assign #2273") }
    if !(shr_assign(20usize, 3u8) == 2usize) { panic("shr_assign #2274") }
    if !(shl(20usize, (read 3u8)) == 160usize) { panic("shl #2275") }
    if !(shr(20usize, (read 3u8)) == 2usize) { panic("shr #2276") }
    if !(shl((read 20usize), (read 3u8)) == 160usize) { panic("shl #2277") }
    if !(shr((read 20usize), (read 3u8)) == 2usize) { panic("shr #2278") }
    if !(shl_assign(20usize, (read 3u8)) == 160usize) { panic("shl_assign #2279") }
    if !(shr_assign(20usize, (read 3u8)) == 2usize) { panic("shr_assign #2280") }
    if !(shl(20usize, 3u16) == 160usize) { panic("shl #2281") }
    if !(shr(20usize, 3u16) == 2usize) { panic("shr #2282") }
    if !(shl((read 20usize), 3u16) == 160usize) { panic("shl #2283") }
    if !(shr((read 20usize), 3u16) == 2usize) { panic("shr #2284") }
    if !(shl_assign(20usize, 3u16) == 160usize) { panic("shl_assign #2285") }
    if !(shr_assign(20usize, 3u16) == 2usize) { panic("shr_assign #2286") }
    if !(shl(20usize, (read 3u16)) == 160usize) { panic("shl #2287") }
    if !(shr(20usize, (read 3u16)) == 2usize) { panic("shr #2288") }
    if !(shl((read 20usize), (read 3u16)) == 160usize) { panic("shl #2289") }
    if !(shr((read 20usize), (read 3u16)) == 2usize) { panic("shr #2290") }
    if !(shl_assign(20usize, (read 3u16)) == 160usize) { panic("shl_assign #2291") }
    if !(shr_assign(20usize, (read 3u16)) == 2usize) { panic("shr_assign #2292") }
    if !(shl(20usize, 3u32) == 160usize) { panic("shl #2293") }
    if !(shr(20usize, 3u32) == 2usize) { panic("shr #2294") }
    if !(shl((read 20usize), 3u32) == 160usize) { panic("shl #2295") }
    if !(shr((read 20usize), 3u32) == 2usize) { panic("shr #2296") }
    if !(shl_assign(20usize, 3u32) == 160usize) { panic("shl_assign #2297") }
    if !(shr_assign(20usize, 3u32) == 2usize) { panic("shr_assign #2298") }
    if !(shl(20usize, (read 3u32)) == 160usize) { panic("shl #2299") }
    if !(shr(20usize, (read 3u32)) == 2usize) { panic("shr #2300") }
    if !(shl((read 20usize), (read 3u32)) == 160usize) { panic("shl #2301") }
    if !(shr((read 20usize), (read 3u32)) == 2usize) { panic("shr #2302") }
    if !(shl_assign(20usize, (read 3u32)) == 160usize) { panic("shl_assign #2303") }
    if !(shr_assign(20usize, (read 3u32)) == 2usize) { panic("shr_assign #2304") }
    if !(shl(20usize, 3u64) == 160usize) { panic("shl #2305") }
    if !(shr(20usize, 3u64) == 2usize) { panic("shr #2306") }
    if !(shl((read 20usize), 3u64) == 160usize) { panic("shl #2307") }
    if !(shr((read 20usize), 3u64) == 2usize) { panic("shr #2308") }
    if !(shl_assign(20usize, 3u64) == 160usize) { panic("shl_assign #2309") }
    if !(shr_assign(20usize, 3u64) == 2usize) { panic("shr_assign #2310") }
    if !(shl(20usize, (read 3u64)) == 160usize) { panic("shl #2311") }
    if !(shr(20usize, (read 3u64)) == 2usize) { panic("shr #2312") }
    if !(shl((read 20usize), (read 3u64)) == 160usize) { panic("shl #2313") }
    if !(shr((read 20usize), (read 3u64)) == 2usize) { panic("shr #2314") }
    if !(shl_assign(20usize, (read 3u64)) == 160usize) { panic("shl_assign #2315") }
    if !(shr_assign(20usize, (read 3u64)) == 2usize) { panic("shr_assign #2316") }
    if !(shl(20usize, 3u128) == 160usize) { panic("shl #2317") }
    if !(shr(20usize, 3u128) == 2usize) { panic("shr #2318") }
    if !(shl((read 20usize), 3u128) == 160usize) { panic("shl #2319") }
    if !(shr((read 20usize), 3u128) == 2usize) { panic("shr #2320") }
    if !(shl_assign(20usize, 3u128) == 160usize) { panic("shl_assign #2321") }
    if !(shr_assign(20usize, 3u128) == 2usize) { panic("shr_assign #2322") }
    if !(shl(20usize, (read 3u128)) == 160usize) { panic("shl #2323") }
    if !(shr(20usize, (read 3u128)) == 2usize) { panic("shr #2324") }
    if !(shl((read 20usize), (read 3u128)) == 160usize) { panic("shl #2325") }
    if !(shr((read 20usize), (read 3u128)) == 2usize) { panic("shr #2326") }
    if !(shl_assign(20usize, (read 3u128)) == 160usize) { panic("shl_assign #2327") }
    if !(shr_assign(20usize, (read 3u128)) == 2usize) { panic("shr_assign #2328") }
    if !(shl(20usize, 3usize) == 160usize) { panic("shl #2329") }
    if !(shr(20usize, 3usize) == 2usize) { panic("shr #2330") }
    if !(shl((read 20usize), 3usize) == 160usize) { panic("shl #2331") }
    if !(shr((read 20usize), 3usize) == 2usize) { panic("shr #2332") }
    if !(shl_assign(20usize, 3usize) == 160usize) { panic("shl_assign #2333") }
    if !(shr_assign(20usize, 3usize) == 2usize) { panic("shr_assign #2334") }
    if !(shl(20usize, (read 3usize)) == 160usize) { panic("shl #2335") }
    if !(shr(20usize, (read 3usize)) == 2usize) { panic("shr #2336") }
    if !(shl((read 20usize), (read 3usize)) == 160usize) { panic("shl #2337") }
    if !(shr((read 20usize), (read 3usize)) == 2usize) { panic("shr #2338") }
    if !(shl_assign(20usize, (read 3usize)) == 160usize) { panic("shl_assign #2339") }
    if !(shr_assign(20usize, (read 3usize)) == 2usize) { panic("shr_assign #2340") }
    if !(and(false, false) == false && and((read false), (read false)) == false) { panic("and #2341") }
    if !(and_assign(false, false) == false) { panic("and_assign #2342") }
    if !(and(false, true) == false && and((read false), (read true)) == false) { panic("and #2343") }
    if !(and_assign(false, true) == false) { panic("and_assign #2344") }
    if !(and(true, false) == false && and((read true), (read false)) == false) { panic("and #2345") }
    if !(and_assign(true, false) == false) { panic("and_assign #2346") }
    if !(and(true, true) == true && and((read true), (read true)) == true) { panic("and #2347") }
    if !(and_assign(true, true) == true) { panic("and_assign #2348") }
    if !(or(false, false) == false && or((read false), (read false)) == false) { panic("or #2349") }
    if !(or_assign(false, false) == false) { panic("or_assign #2350") }
    if !(or(false, true) == true && or((read false), (read true)) == true) { panic("or #2351") }
    if !(or_assign(false, true) == true) { panic("or_assign #2352") }
    if !(or(true, false) == true && or((read true), (read false)) == true) { panic("or #2353") }
    if !(or_assign(true, false) == true) { panic("or_assign #2354") }
    if !(or(true, true) == true && or((read true), (read true)) == true) { panic("or #2355") }
    if !(or_assign(true, true) == true) { panic("or_assign #2356") }
    if !(xor(false, false) == false && xor((read false), (read false)) == false) { panic("xor #2357") }
    if !(xor_assign(false, false) == false) { panic("xor_assign #2358") }
    if !(xor(false, true) == true && xor((read false), (read true)) == true) { panic("xor #2359") }
    if !(xor_assign(false, true) == true) { panic("xor_assign #2360") }
    if !(xor(true, false) == true && xor((read true), (read false)) == true) { panic("xor #2361") }
    if !(xor_assign(true, false) == true) { panic("xor_assign #2362") }
    if !(xor(true, true) == false && xor((read true), (read true)) == false) { panic("xor #2363") }
    if !(xor_assign(true, true) == false) { panic("xor_assign #2364") }
    if !(not(true) == false && not((read false)) == true) { panic("not #2365") }
    if !(widen<u8, u16>(255u8) == 255u16) { panic("From #2366") }
    if !(widen_into<u8, u16>(255u8) == 255u16) { panic("Into #2367") }
    if !(narrow<u8, u16>(255u8) == present(255u16)) { panic("TryFrom #2368") }
    if !(widen<bool, u16>(true) == 1u16) { panic("From #2369") }
    if !(widen<u8, u32>(255u8) == 255u32) { panic("From #2370") }
    if !(widen_into<u8, u32>(255u8) == 255u32) { panic("Into #2371") }
    if !(narrow<u8, u32>(255u8) == present(255u32)) { panic("TryFrom #2372") }
    if !(widen<u16, u32>(65535u16) == 65535u32) { panic("From #2373") }
    if !(widen_into<u16, u32>(65535u16) == 65535u32) { panic("Into #2374") }
    if !(narrow<u16, u32>(65535u16) == present(65535u32)) { panic("TryFrom #2375") }
    if !(widen<bool, u32>(true) == 1u32) { panic("From #2376") }
    if !(widen<u8, u64>(255u8) == 255u64) { panic("From #2377") }
    if !(widen_into<u8, u64>(255u8) == 255u64) { panic("Into #2378") }
    if !(narrow<u8, u64>(255u8) == present(255u64)) { panic("TryFrom #2379") }
    if !(widen<u16, u64>(65535u16) == 65535u64) { panic("From #2380") }
    if !(widen_into<u16, u64>(65535u16) == 65535u64) { panic("Into #2381") }
    if !(narrow<u16, u64>(65535u16) == present(65535u64)) { panic("TryFrom #2382") }
    if !(widen<u32, u64>(4294967295u32) == 4294967295u64) { panic("From #2383") }
    if !(widen_into<u32, u64>(4294967295u32) == 4294967295u64) { panic("Into #2384") }
    if !(narrow<u32, u64>(4294967295u32) == present(4294967295u64)) { panic("TryFrom #2385") }
    if !(widen<bool, u64>(true) == 1u64) { panic("From #2386") }
    if !(widen<u8, u128>(255u8) == 255u128) { panic("From #2387") }
    if !(widen_into<u8, u128>(255u8) == 255u128) { panic("Into #2388") }
    if !(narrow<u8, u128>(255u8) == present(255u128)) { panic("TryFrom #2389") }
    if !(widen<u16, u128>(65535u16) == 65535u128) { panic("From #2390") }
    if !(widen_into<u16, u128>(65535u16) == 65535u128) { panic("Into #2391") }
    if !(narrow<u16, u128>(65535u16) == present(65535u128)) { panic("TryFrom #2392") }
    if !(widen<u32, u128>(4294967295u32) == 4294967295u128) { panic("From #2393") }
    if !(widen_into<u32, u128>(4294967295u32) == 4294967295u128) { panic("Into #2394") }
    if !(narrow<u32, u128>(4294967295u32) == present(4294967295u128)) { panic("TryFrom #2395") }
    if !(widen<u64, u128>(18446744073709551615u64) == 18446744073709551615u128) { panic("From #2396") }
    if !(widen_into<u64, u128>(18446744073709551615u64) == 18446744073709551615u128) { panic("Into #2397") }
    if !(narrow<u64, u128>(18446744073709551615u64) == present(18446744073709551615u128)) { panic("TryFrom #2398") }
    if !(widen<bool, u128>(true) == 1u128) { panic("From #2399") }
    if !(widen<u8, usize>(255u8) == 255usize) { panic("From #2400") }
}

fn group16() {
    if !(widen_into<u8, usize>(255u8) == 255usize) { panic("Into #2401") }
    if !(narrow<u8, usize>(255u8) == present(255usize)) { panic("TryFrom #2402") }
    if !(widen<u16, usize>(65535u16) == 65535usize) { panic("From #2403") }
    if !(widen_into<u16, usize>(65535u16) == 65535usize) { panic("Into #2404") }
    if !(narrow<u16, usize>(65535u16) == present(65535usize)) { panic("TryFrom #2405") }
    if !(widen<bool, usize>(true) == 1usize) { panic("From #2406") }
    if !(widen<u8, i16>(255u8) == 255i16) { panic("From #2407") }
    if !(widen_into<u8, i16>(255u8) == 255i16) { panic("Into #2408") }
    if !(narrow<u8, i16>(255u8) == present(255i16)) { panic("TryFrom #2409") }
    if !(widen<i8, i16>(127i8) == 127i16) { panic("From #2410") }
    if !(widen_into<i8, i16>(127i8) == 127i16) { panic("Into #2411") }
    if !(narrow<i8, i16>(127i8) == present(127i16)) { panic("TryFrom #2412") }
    if !(widen<bool, i16>(true) == 1i16) { panic("From #2413") }
    if !(widen<u8, i32>(255u8) == 255i32) { panic("From #2414") }
    if !(widen_into<u8, i32>(255u8) == 255i32) { panic("Into #2415") }
    if !(narrow<u8, i32>(255u8) == present(255i32)) { panic("TryFrom #2416") }
    if !(widen<u16, i32>(65535u16) == 65535i32) { panic("From #2417") }
    if !(widen_into<u16, i32>(65535u16) == 65535i32) { panic("Into #2418") }
    if !(narrow<u16, i32>(65535u16) == present(65535i32)) { panic("TryFrom #2419") }
    if !(widen<i8, i32>(127i8) == 127i32) { panic("From #2420") }
    if !(widen_into<i8, i32>(127i8) == 127i32) { panic("Into #2421") }
    if !(narrow<i8, i32>(127i8) == present(127i32)) { panic("TryFrom #2422") }
    if !(widen<i16, i32>(32767i16) == 32767i32) { panic("From #2423") }
    if !(widen_into<i16, i32>(32767i16) == 32767i32) { panic("Into #2424") }
    if !(narrow<i16, i32>(32767i16) == present(32767i32)) { panic("TryFrom #2425") }
    if !(widen<bool, i32>(true) == 1i32) { panic("From #2426") }
    if !(widen<u8, i64>(255u8) == 255i64) { panic("From #2427") }
    if !(widen_into<u8, i64>(255u8) == 255i64) { panic("Into #2428") }
    if !(narrow<u8, i64>(255u8) == present(255i64)) { panic("TryFrom #2429") }
    if !(widen<u16, i64>(65535u16) == 65535i64) { panic("From #2430") }
    if !(widen_into<u16, i64>(65535u16) == 65535i64) { panic("Into #2431") }
    if !(narrow<u16, i64>(65535u16) == present(65535i64)) { panic("TryFrom #2432") }
    if !(widen<u32, i64>(4294967295u32) == 4294967295i64) { panic("From #2433") }
    if !(widen_into<u32, i64>(4294967295u32) == 4294967295i64) { panic("Into #2434") }
    if !(narrow<u32, i64>(4294967295u32) == present(4294967295i64)) { panic("TryFrom #2435") }
    if !(widen<i8, i64>(127i8) == 127i64) { panic("From #2436") }
    if !(widen_into<i8, i64>(127i8) == 127i64) { panic("Into #2437") }
    if !(narrow<i8, i64>(127i8) == present(127i64)) { panic("TryFrom #2438") }
    if !(widen<i16, i64>(32767i16) == 32767i64) { panic("From #2439") }
    if !(widen_into<i16, i64>(32767i16) == 32767i64) { panic("Into #2440") }
    if !(narrow<i16, i64>(32767i16) == present(32767i64)) { panic("TryFrom #2441") }
    if !(widen<i32, i64>(2147483647i32) == 2147483647i64) { panic("From #2442") }
    if !(widen_into<i32, i64>(2147483647i32) == 2147483647i64) { panic("Into #2443") }
    if !(narrow<i32, i64>(2147483647i32) == present(2147483647i64)) { panic("TryFrom #2444") }
    if !(widen<bool, i64>(true) == 1i64) { panic("From #2445") }
    if !(widen<u8, i128>(255u8) == 255i128) { panic("From #2446") }
    if !(widen_into<u8, i128>(255u8) == 255i128) { panic("Into #2447") }
    if !(narrow<u8, i128>(255u8) == present(255i128)) { panic("TryFrom #2448") }
    if !(widen<u16, i128>(65535u16) == 65535i128) { panic("From #2449") }
    if !(widen_into<u16, i128>(65535u16) == 65535i128) { panic("Into #2450") }
    if !(narrow<u16, i128>(65535u16) == present(65535i128)) { panic("TryFrom #2451") }
    if !(widen<u32, i128>(4294967295u32) == 4294967295i128) { panic("From #2452") }
    if !(widen_into<u32, i128>(4294967295u32) == 4294967295i128) { panic("Into #2453") }
    if !(narrow<u32, i128>(4294967295u32) == present(4294967295i128)) { panic("TryFrom #2454") }
    if !(widen<u64, i128>(18446744073709551615u64) == 18446744073709551615i128) { panic("From #2455") }
    if !(widen_into<u64, i128>(18446744073709551615u64) == 18446744073709551615i128) { panic("Into #2456") }
    if !(narrow<u64, i128>(18446744073709551615u64) == present(18446744073709551615i128)) { panic("TryFrom #2457") }
    if !(widen<i8, i128>(127i8) == 127i128) { panic("From #2458") }
    if !(widen_into<i8, i128>(127i8) == 127i128) { panic("Into #2459") }
    if !(narrow<i8, i128>(127i8) == present(127i128)) { panic("TryFrom #2460") }
    if !(widen<i16, i128>(32767i16) == 32767i128) { panic("From #2461") }
    if !(widen_into<i16, i128>(32767i16) == 32767i128) { panic("Into #2462") }
    if !(narrow<i16, i128>(32767i16) == present(32767i128)) { panic("TryFrom #2463") }
    if !(widen<i32, i128>(2147483647i32) == 2147483647i128) { panic("From #2464") }
    if !(widen_into<i32, i128>(2147483647i32) == 2147483647i128) { panic("Into #2465") }
    if !(narrow<i32, i128>(2147483647i32) == present(2147483647i128)) { panic("TryFrom #2466") }
    if !(widen<i64, i128>(9223372036854775807i64) == 9223372036854775807i128) { panic("From #2467") }
    if !(widen_into<i64, i128>(9223372036854775807i64) == 9223372036854775807i128) { panic("Into #2468") }
    if !(narrow<i64, i128>(9223372036854775807i64) == present(9223372036854775807i128)) { panic("TryFrom #2469") }
    if !(widen<bool, i128>(true) == 1i128) { panic("From #2470") }
    if !(widen<u8, isize>(255u8) == 255isize) { panic("From #2471") }
    if !(widen_into<u8, isize>(255u8) == 255isize) { panic("Into #2472") }
    if !(narrow<u8, isize>(255u8) == present(255isize)) { panic("TryFrom #2473") }
    if !(widen<i8, isize>(127i8) == 127isize) { panic("From #2474") }
    if !(widen_into<i8, isize>(127i8) == 127isize) { panic("Into #2475") }
    if !(narrow<i8, isize>(127i8) == present(127isize)) { panic("TryFrom #2476") }
    if !(widen<i16, isize>(32767i16) == 32767isize) { panic("From #2477") }
    if !(widen_into<i16, isize>(32767i16) == 32767isize) { panic("Into #2478") }
    if !(narrow<i16, isize>(32767i16) == present(32767isize)) { panic("TryFrom #2479") }
    if !(widen<bool, isize>(true) == 1isize) { panic("From #2480") }
    if !(missing(narrow<i16, i8>((-32768i16)))) { panic("TryFrom #2481") }
    if !(narrow<i16, i8>((-1i16)) == present((-1i8))) { panic("TryFrom #2482") }
    if !(narrow<i16, i8>(0i16) == present(0i8)) { panic("TryFrom #2483") }
    if !(narrow<i16, i8>(1i16) == present(1i8)) { panic("TryFrom #2484") }
    if !(missing(narrow<i16, i8>(32767i16))) { panic("TryFrom #2485") }
    if !(missing(narrow<i32, i8>((-2147483648i32)))) { panic("TryFrom #2486") }
    if !(narrow<i32, i8>((-1i32)) == present((-1i8))) { panic("TryFrom #2487") }
    if !(narrow<i32, i8>(0i32) == present(0i8)) { panic("TryFrom #2488") }
    if !(narrow<i32, i8>(1i32) == present(1i8)) { panic("TryFrom #2489") }
    if !(missing(narrow<i32, i8>(2147483647i32))) { panic("TryFrom #2490") }
    if !(missing(narrow<i64, i8>((-9223372036854775808i64)))) { panic("TryFrom #2491") }
    if !(narrow<i64, i8>((-1i64)) == present((-1i8))) { panic("TryFrom #2492") }
    if !(narrow<i64, i8>(0i64) == present(0i8)) { panic("TryFrom #2493") }
    if !(narrow<i64, i8>(1i64) == present(1i8)) { panic("TryFrom #2494") }
    if !(missing(narrow<i64, i8>(9223372036854775807i64))) { panic("TryFrom #2495") }
    if !(missing(narrow<i128, i8>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2496") }
    if !(narrow<i128, i8>((-1i128)) == present((-1i8))) { panic("TryFrom #2497") }
    if !(narrow<i128, i8>(0i128) == present(0i8)) { panic("TryFrom #2498") }
    if !(narrow<i128, i8>(1i128) == present(1i8)) { panic("TryFrom #2499") }
    if !(missing(narrow<i128, i8>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2500") }
    if !(missing(narrow<isize, i8>((-9223372036854775808isize)))) { panic("TryFrom #2501") }
    if !(narrow<isize, i8>((-1isize)) == present((-1i8))) { panic("TryFrom #2502") }
    if !(narrow<isize, i8>(0isize) == present(0i8)) { panic("TryFrom #2503") }
    if !(narrow<isize, i8>(1isize) == present(1i8)) { panic("TryFrom #2504") }
    if !(missing(narrow<isize, i8>(9223372036854775807isize))) { panic("TryFrom #2505") }
    if !(narrow<u8, i8>(0u8) == present(0i8)) { panic("TryFrom #2506") }
    if !(narrow<u8, i8>(1u8) == present(1i8)) { panic("TryFrom #2507") }
    if !(missing(narrow<u8, i8>(255u8))) { panic("TryFrom #2508") }
    if !(narrow<u16, i8>(0u16) == present(0i8)) { panic("TryFrom #2509") }
    if !(narrow<u16, i8>(1u16) == present(1i8)) { panic("TryFrom #2510") }
    if !(missing(narrow<u16, i8>(65535u16))) { panic("TryFrom #2511") }
    if !(narrow<u32, i8>(0u32) == present(0i8)) { panic("TryFrom #2512") }
    if !(narrow<u32, i8>(1u32) == present(1i8)) { panic("TryFrom #2513") }
    if !(missing(narrow<u32, i8>(4294967295u32))) { panic("TryFrom #2514") }
    if !(narrow<u64, i8>(0u64) == present(0i8)) { panic("TryFrom #2515") }
    if !(narrow<u64, i8>(1u64) == present(1i8)) { panic("TryFrom #2516") }
    if !(missing(narrow<u64, i8>(18446744073709551615u64))) { panic("TryFrom #2517") }
    if !(narrow<u128, i8>(0u128) == present(0i8)) { panic("TryFrom #2518") }
    if !(narrow<u128, i8>(1u128) == present(1i8)) { panic("TryFrom #2519") }
    if !(missing(narrow<u128, i8>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2520") }
    if !(narrow<usize, i8>(0usize) == present(0i8)) { panic("TryFrom #2521") }
    if !(narrow<usize, i8>(1usize) == present(1i8)) { panic("TryFrom #2522") }
    if !(missing(narrow<usize, i8>(18446744073709551615usize))) { panic("TryFrom #2523") }
    if !(missing(narrow<i32, i16>((-2147483648i32)))) { panic("TryFrom #2524") }
    if !(narrow<i32, i16>((-1i32)) == present((-1i16))) { panic("TryFrom #2525") }
    if !(narrow<i32, i16>(0i32) == present(0i16)) { panic("TryFrom #2526") }
    if !(narrow<i32, i16>(1i32) == present(1i16)) { panic("TryFrom #2527") }
    if !(missing(narrow<i32, i16>(2147483647i32))) { panic("TryFrom #2528") }
    if !(missing(narrow<i64, i16>((-9223372036854775808i64)))) { panic("TryFrom #2529") }
    if !(narrow<i64, i16>((-1i64)) == present((-1i16))) { panic("TryFrom #2530") }
    if !(narrow<i64, i16>(0i64) == present(0i16)) { panic("TryFrom #2531") }
    if !(narrow<i64, i16>(1i64) == present(1i16)) { panic("TryFrom #2532") }
    if !(missing(narrow<i64, i16>(9223372036854775807i64))) { panic("TryFrom #2533") }
    if !(missing(narrow<i128, i16>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2534") }
    if !(narrow<i128, i16>((-1i128)) == present((-1i16))) { panic("TryFrom #2535") }
    if !(narrow<i128, i16>(0i128) == present(0i16)) { panic("TryFrom #2536") }
    if !(narrow<i128, i16>(1i128) == present(1i16)) { panic("TryFrom #2537") }
    if !(missing(narrow<i128, i16>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2538") }
    if !(missing(narrow<isize, i16>((-9223372036854775808isize)))) { panic("TryFrom #2539") }
    if !(narrow<isize, i16>((-1isize)) == present((-1i16))) { panic("TryFrom #2540") }
    if !(narrow<isize, i16>(0isize) == present(0i16)) { panic("TryFrom #2541") }
    if !(narrow<isize, i16>(1isize) == present(1i16)) { panic("TryFrom #2542") }
    if !(missing(narrow<isize, i16>(9223372036854775807isize))) { panic("TryFrom #2543") }
    if !(narrow<u16, i16>(0u16) == present(0i16)) { panic("TryFrom #2544") }
    if !(narrow<u16, i16>(1u16) == present(1i16)) { panic("TryFrom #2545") }
    if !(missing(narrow<u16, i16>(65535u16))) { panic("TryFrom #2546") }
    if !(narrow<u32, i16>(0u32) == present(0i16)) { panic("TryFrom #2547") }
    if !(narrow<u32, i16>(1u32) == present(1i16)) { panic("TryFrom #2548") }
    if !(missing(narrow<u32, i16>(4294967295u32))) { panic("TryFrom #2549") }
    if !(narrow<u64, i16>(0u64) == present(0i16)) { panic("TryFrom #2550") }
}

fn group17() {
    if !(narrow<u64, i16>(1u64) == present(1i16)) { panic("TryFrom #2551") }
    if !(missing(narrow<u64, i16>(18446744073709551615u64))) { panic("TryFrom #2552") }
    if !(narrow<u128, i16>(0u128) == present(0i16)) { panic("TryFrom #2553") }
    if !(narrow<u128, i16>(1u128) == present(1i16)) { panic("TryFrom #2554") }
    if !(missing(narrow<u128, i16>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2555") }
    if !(narrow<usize, i16>(0usize) == present(0i16)) { panic("TryFrom #2556") }
    if !(narrow<usize, i16>(1usize) == present(1i16)) { panic("TryFrom #2557") }
    if !(missing(narrow<usize, i16>(18446744073709551615usize))) { panic("TryFrom #2558") }
    if !(missing(narrow<i64, i32>((-9223372036854775808i64)))) { panic("TryFrom #2559") }
    if !(narrow<i64, i32>((-1i64)) == present((-1i32))) { panic("TryFrom #2560") }
    if !(narrow<i64, i32>(0i64) == present(0i32)) { panic("TryFrom #2561") }
    if !(narrow<i64, i32>(1i64) == present(1i32)) { panic("TryFrom #2562") }
    if !(missing(narrow<i64, i32>(9223372036854775807i64))) { panic("TryFrom #2563") }
    if !(missing(narrow<i128, i32>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2564") }
    if !(narrow<i128, i32>((-1i128)) == present((-1i32))) { panic("TryFrom #2565") }
    if !(narrow<i128, i32>(0i128) == present(0i32)) { panic("TryFrom #2566") }
    if !(narrow<i128, i32>(1i128) == present(1i32)) { panic("TryFrom #2567") }
    if !(missing(narrow<i128, i32>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2568") }
    if !(missing(narrow<isize, i32>((-9223372036854775808isize)))) { panic("TryFrom #2569") }
    if !(narrow<isize, i32>((-1isize)) == present((-1i32))) { panic("TryFrom #2570") }
    if !(narrow<isize, i32>(0isize) == present(0i32)) { panic("TryFrom #2571") }
    if !(narrow<isize, i32>(1isize) == present(1i32)) { panic("TryFrom #2572") }
    if !(missing(narrow<isize, i32>(9223372036854775807isize))) { panic("TryFrom #2573") }
    if !(narrow<u32, i32>(0u32) == present(0i32)) { panic("TryFrom #2574") }
    if !(narrow<u32, i32>(1u32) == present(1i32)) { panic("TryFrom #2575") }
    if !(missing(narrow<u32, i32>(4294967295u32))) { panic("TryFrom #2576") }
    if !(narrow<u64, i32>(0u64) == present(0i32)) { panic("TryFrom #2577") }
    if !(narrow<u64, i32>(1u64) == present(1i32)) { panic("TryFrom #2578") }
    if !(missing(narrow<u64, i32>(18446744073709551615u64))) { panic("TryFrom #2579") }
    if !(narrow<u128, i32>(0u128) == present(0i32)) { panic("TryFrom #2580") }
    if !(narrow<u128, i32>(1u128) == present(1i32)) { panic("TryFrom #2581") }
    if !(missing(narrow<u128, i32>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2582") }
    if !(narrow<usize, i32>(0usize) == present(0i32)) { panic("TryFrom #2583") }
    if !(narrow<usize, i32>(1usize) == present(1i32)) { panic("TryFrom #2584") }
    if !(missing(narrow<usize, i32>(18446744073709551615usize))) { panic("TryFrom #2585") }
    if !(missing(narrow<i128, i64>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2586") }
    if !(narrow<i128, i64>((-1i128)) == present((-1i64))) { panic("TryFrom #2587") }
    if !(narrow<i128, i64>(0i128) == present(0i64)) { panic("TryFrom #2588") }
    if !(narrow<i128, i64>(1i128) == present(1i64)) { panic("TryFrom #2589") }
    if !(missing(narrow<i128, i64>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2590") }
    if !(narrow<isize, i64>((-9223372036854775808isize)) == present((-9223372036854775808i64))) { panic("TryFrom #2591") }
    if !(narrow<isize, i64>((-1isize)) == present((-1i64))) { panic("TryFrom #2592") }
    if !(narrow<isize, i64>(0isize) == present(0i64)) { panic("TryFrom #2593") }
    if !(narrow<isize, i64>(1isize) == present(1i64)) { panic("TryFrom #2594") }
    if !(narrow<isize, i64>(9223372036854775807isize) == present(9223372036854775807i64)) { panic("TryFrom #2595") }
    if !(narrow<u64, i64>(0u64) == present(0i64)) { panic("TryFrom #2596") }
    if !(narrow<u64, i64>(1u64) == present(1i64)) { panic("TryFrom #2597") }
    if !(missing(narrow<u64, i64>(18446744073709551615u64))) { panic("TryFrom #2598") }
    if !(narrow<u128, i64>(0u128) == present(0i64)) { panic("TryFrom #2599") }
    if !(narrow<u128, i64>(1u128) == present(1i64)) { panic("TryFrom #2600") }
    if !(missing(narrow<u128, i64>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2601") }
    if !(narrow<usize, i64>(0usize) == present(0i64)) { panic("TryFrom #2602") }
    if !(narrow<usize, i64>(1usize) == present(1i64)) { panic("TryFrom #2603") }
    if !(missing(narrow<usize, i64>(18446744073709551615usize))) { panic("TryFrom #2604") }
    if !(narrow<isize, i128>((-9223372036854775808isize)) == present((-9223372036854775808i128))) { panic("TryFrom #2605") }
    if !(narrow<isize, i128>((-1isize)) == present((-1i128))) { panic("TryFrom #2606") }
    if !(narrow<isize, i128>(0isize) == present(0i128)) { panic("TryFrom #2607") }
    if !(narrow<isize, i128>(1isize) == present(1i128)) { panic("TryFrom #2608") }
    if !(narrow<isize, i128>(9223372036854775807isize) == present(9223372036854775807i128)) { panic("TryFrom #2609") }
    if !(narrow<u128, i128>(0u128) == present(0i128)) { panic("TryFrom #2610") }
    if !(narrow<u128, i128>(1u128) == present(1i128)) { panic("TryFrom #2611") }
    if !(missing(narrow<u128, i128>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2612") }
    if !(narrow<usize, i128>(0usize) == present(0i128)) { panic("TryFrom #2613") }
    if !(narrow<usize, i128>(1usize) == present(1i128)) { panic("TryFrom #2614") }
    if !(narrow<usize, i128>(18446744073709551615usize) == present(18446744073709551615i128)) { panic("TryFrom #2615") }
    if !(narrow<i32, isize>((-2147483648i32)) == present((-2147483648isize))) { panic("TryFrom #2616") }
    if !(narrow<i32, isize>((-1i32)) == present((-1isize))) { panic("TryFrom #2617") }
    if !(narrow<i32, isize>(0i32) == present(0isize)) { panic("TryFrom #2618") }
    if !(narrow<i32, isize>(1i32) == present(1isize)) { panic("TryFrom #2619") }
    if !(narrow<i32, isize>(2147483647i32) == present(2147483647isize)) { panic("TryFrom #2620") }
    if !(narrow<i64, isize>((-9223372036854775808i64)) == present((-9223372036854775808isize))) { panic("TryFrom #2621") }
    if !(narrow<i64, isize>((-1i64)) == present((-1isize))) { panic("TryFrom #2622") }
    if !(narrow<i64, isize>(0i64) == present(0isize)) { panic("TryFrom #2623") }
    if !(narrow<i64, isize>(1i64) == present(1isize)) { panic("TryFrom #2624") }
    if !(narrow<i64, isize>(9223372036854775807i64) == present(9223372036854775807isize)) { panic("TryFrom #2625") }
    if !(missing(narrow<i128, isize>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2626") }
    if !(narrow<i128, isize>((-1i128)) == present((-1isize))) { panic("TryFrom #2627") }
    if !(narrow<i128, isize>(0i128) == present(0isize)) { panic("TryFrom #2628") }
    if !(narrow<i128, isize>(1i128) == present(1isize)) { panic("TryFrom #2629") }
    if !(missing(narrow<i128, isize>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2630") }
    if !(narrow<u16, isize>(0u16) == present(0isize)) { panic("TryFrom #2631") }
    if !(narrow<u16, isize>(1u16) == present(1isize)) { panic("TryFrom #2632") }
    if !(narrow<u16, isize>(65535u16) == present(65535isize)) { panic("TryFrom #2633") }
    if !(narrow<u32, isize>(0u32) == present(0isize)) { panic("TryFrom #2634") }
    if !(narrow<u32, isize>(1u32) == present(1isize)) { panic("TryFrom #2635") }
    if !(narrow<u32, isize>(4294967295u32) == present(4294967295isize)) { panic("TryFrom #2636") }
    if !(narrow<u64, isize>(0u64) == present(0isize)) { panic("TryFrom #2637") }
    if !(narrow<u64, isize>(1u64) == present(1isize)) { panic("TryFrom #2638") }
    if !(missing(narrow<u64, isize>(18446744073709551615u64))) { panic("TryFrom #2639") }
    if !(narrow<u128, isize>(0u128) == present(0isize)) { panic("TryFrom #2640") }
    if !(narrow<u128, isize>(1u128) == present(1isize)) { panic("TryFrom #2641") }
    if !(missing(narrow<u128, isize>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2642") }
    if !(narrow<usize, isize>(0usize) == present(0isize)) { panic("TryFrom #2643") }
    if !(narrow<usize, isize>(1usize) == present(1isize)) { panic("TryFrom #2644") }
    if !(missing(narrow<usize, isize>(18446744073709551615usize))) { panic("TryFrom #2645") }
    if !(missing(narrow<i8, u8>((-128i8)))) { panic("TryFrom #2646") }
    if !(missing(narrow<i8, u8>((-1i8)))) { panic("TryFrom #2647") }
    if !(narrow<i8, u8>(0i8) == present(0u8)) { panic("TryFrom #2648") }
    if !(narrow<i8, u8>(1i8) == present(1u8)) { panic("TryFrom #2649") }
    if !(narrow<i8, u8>(127i8) == present(127u8)) { panic("TryFrom #2650") }
    if !(missing(narrow<i16, u8>((-32768i16)))) { panic("TryFrom #2651") }
    if !(missing(narrow<i16, u8>((-1i16)))) { panic("TryFrom #2652") }
    if !(narrow<i16, u8>(0i16) == present(0u8)) { panic("TryFrom #2653") }
    if !(narrow<i16, u8>(1i16) == present(1u8)) { panic("TryFrom #2654") }
    if !(missing(narrow<i16, u8>(32767i16))) { panic("TryFrom #2655") }
    if !(missing(narrow<i32, u8>((-2147483648i32)))) { panic("TryFrom #2656") }
    if !(missing(narrow<i32, u8>((-1i32)))) { panic("TryFrom #2657") }
    if !(narrow<i32, u8>(0i32) == present(0u8)) { panic("TryFrom #2658") }
    if !(narrow<i32, u8>(1i32) == present(1u8)) { panic("TryFrom #2659") }
    if !(missing(narrow<i32, u8>(2147483647i32))) { panic("TryFrom #2660") }
    if !(missing(narrow<i64, u8>((-9223372036854775808i64)))) { panic("TryFrom #2661") }
    if !(missing(narrow<i64, u8>((-1i64)))) { panic("TryFrom #2662") }
    if !(narrow<i64, u8>(0i64) == present(0u8)) { panic("TryFrom #2663") }
    if !(narrow<i64, u8>(1i64) == present(1u8)) { panic("TryFrom #2664") }
    if !(missing(narrow<i64, u8>(9223372036854775807i64))) { panic("TryFrom #2665") }
    if !(missing(narrow<i128, u8>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2666") }
    if !(missing(narrow<i128, u8>((-1i128)))) { panic("TryFrom #2667") }
    if !(narrow<i128, u8>(0i128) == present(0u8)) { panic("TryFrom #2668") }
    if !(narrow<i128, u8>(1i128) == present(1u8)) { panic("TryFrom #2669") }
    if !(missing(narrow<i128, u8>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2670") }
    if !(missing(narrow<isize, u8>((-9223372036854775808isize)))) { panic("TryFrom #2671") }
    if !(missing(narrow<isize, u8>((-1isize)))) { panic("TryFrom #2672") }
    if !(narrow<isize, u8>(0isize) == present(0u8)) { panic("TryFrom #2673") }
    if !(narrow<isize, u8>(1isize) == present(1u8)) { panic("TryFrom #2674") }
    if !(missing(narrow<isize, u8>(9223372036854775807isize))) { panic("TryFrom #2675") }
    if !(narrow<u16, u8>(0u16) == present(0u8)) { panic("TryFrom #2676") }
    if !(narrow<u16, u8>(1u16) == present(1u8)) { panic("TryFrom #2677") }
    if !(missing(narrow<u16, u8>(65535u16))) { panic("TryFrom #2678") }
    if !(narrow<u32, u8>(0u32) == present(0u8)) { panic("TryFrom #2679") }
    if !(narrow<u32, u8>(1u32) == present(1u8)) { panic("TryFrom #2680") }
    if !(missing(narrow<u32, u8>(4294967295u32))) { panic("TryFrom #2681") }
    if !(narrow<u64, u8>(0u64) == present(0u8)) { panic("TryFrom #2682") }
    if !(narrow<u64, u8>(1u64) == present(1u8)) { panic("TryFrom #2683") }
    if !(missing(narrow<u64, u8>(18446744073709551615u64))) { panic("TryFrom #2684") }
    if !(narrow<u128, u8>(0u128) == present(0u8)) { panic("TryFrom #2685") }
    if !(narrow<u128, u8>(1u128) == present(1u8)) { panic("TryFrom #2686") }
    if !(missing(narrow<u128, u8>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2687") }
    if !(narrow<usize, u8>(0usize) == present(0u8)) { panic("TryFrom #2688") }
    if !(narrow<usize, u8>(1usize) == present(1u8)) { panic("TryFrom #2689") }
    if !(missing(narrow<usize, u8>(18446744073709551615usize))) { panic("TryFrom #2690") }
    if !(missing(narrow<i8, u16>((-128i8)))) { panic("TryFrom #2691") }
    if !(missing(narrow<i8, u16>((-1i8)))) { panic("TryFrom #2692") }
    if !(narrow<i8, u16>(0i8) == present(0u16)) { panic("TryFrom #2693") }
    if !(narrow<i8, u16>(1i8) == present(1u16)) { panic("TryFrom #2694") }
    if !(narrow<i8, u16>(127i8) == present(127u16)) { panic("TryFrom #2695") }
    if !(missing(narrow<i16, u16>((-32768i16)))) { panic("TryFrom #2696") }
    if !(missing(narrow<i16, u16>((-1i16)))) { panic("TryFrom #2697") }
    if !(narrow<i16, u16>(0i16) == present(0u16)) { panic("TryFrom #2698") }
    if !(narrow<i16, u16>(1i16) == present(1u16)) { panic("TryFrom #2699") }
    if !(narrow<i16, u16>(32767i16) == present(32767u16)) { panic("TryFrom #2700") }
}

fn group18() {
    if !(missing(narrow<i32, u16>((-2147483648i32)))) { panic("TryFrom #2701") }
    if !(missing(narrow<i32, u16>((-1i32)))) { panic("TryFrom #2702") }
    if !(narrow<i32, u16>(0i32) == present(0u16)) { panic("TryFrom #2703") }
    if !(narrow<i32, u16>(1i32) == present(1u16)) { panic("TryFrom #2704") }
    if !(missing(narrow<i32, u16>(2147483647i32))) { panic("TryFrom #2705") }
    if !(missing(narrow<i64, u16>((-9223372036854775808i64)))) { panic("TryFrom #2706") }
    if !(missing(narrow<i64, u16>((-1i64)))) { panic("TryFrom #2707") }
    if !(narrow<i64, u16>(0i64) == present(0u16)) { panic("TryFrom #2708") }
    if !(narrow<i64, u16>(1i64) == present(1u16)) { panic("TryFrom #2709") }
    if !(missing(narrow<i64, u16>(9223372036854775807i64))) { panic("TryFrom #2710") }
    if !(missing(narrow<i128, u16>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2711") }
    if !(missing(narrow<i128, u16>((-1i128)))) { panic("TryFrom #2712") }
    if !(narrow<i128, u16>(0i128) == present(0u16)) { panic("TryFrom #2713") }
    if !(narrow<i128, u16>(1i128) == present(1u16)) { panic("TryFrom #2714") }
    if !(missing(narrow<i128, u16>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2715") }
    if !(missing(narrow<isize, u16>((-9223372036854775808isize)))) { panic("TryFrom #2716") }
    if !(missing(narrow<isize, u16>((-1isize)))) { panic("TryFrom #2717") }
    if !(narrow<isize, u16>(0isize) == present(0u16)) { panic("TryFrom #2718") }
    if !(narrow<isize, u16>(1isize) == present(1u16)) { panic("TryFrom #2719") }
    if !(missing(narrow<isize, u16>(9223372036854775807isize))) { panic("TryFrom #2720") }
    if !(narrow<u32, u16>(0u32) == present(0u16)) { panic("TryFrom #2721") }
    if !(narrow<u32, u16>(1u32) == present(1u16)) { panic("TryFrom #2722") }
    if !(missing(narrow<u32, u16>(4294967295u32))) { panic("TryFrom #2723") }
    if !(narrow<u64, u16>(0u64) == present(0u16)) { panic("TryFrom #2724") }
    if !(narrow<u64, u16>(1u64) == present(1u16)) { panic("TryFrom #2725") }
    if !(missing(narrow<u64, u16>(18446744073709551615u64))) { panic("TryFrom #2726") }
    if !(narrow<u128, u16>(0u128) == present(0u16)) { panic("TryFrom #2727") }
    if !(narrow<u128, u16>(1u128) == present(1u16)) { panic("TryFrom #2728") }
    if !(missing(narrow<u128, u16>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2729") }
    if !(narrow<usize, u16>(0usize) == present(0u16)) { panic("TryFrom #2730") }
    if !(narrow<usize, u16>(1usize) == present(1u16)) { panic("TryFrom #2731") }
    if !(missing(narrow<usize, u16>(18446744073709551615usize))) { panic("TryFrom #2732") }
    if !(missing(narrow<i8, u32>((-128i8)))) { panic("TryFrom #2733") }
    if !(missing(narrow<i8, u32>((-1i8)))) { panic("TryFrom #2734") }
    if !(narrow<i8, u32>(0i8) == present(0u32)) { panic("TryFrom #2735") }
    if !(narrow<i8, u32>(1i8) == present(1u32)) { panic("TryFrom #2736") }
    if !(narrow<i8, u32>(127i8) == present(127u32)) { panic("TryFrom #2737") }
    if !(missing(narrow<i16, u32>((-32768i16)))) { panic("TryFrom #2738") }
    if !(missing(narrow<i16, u32>((-1i16)))) { panic("TryFrom #2739") }
    if !(narrow<i16, u32>(0i16) == present(0u32)) { panic("TryFrom #2740") }
    if !(narrow<i16, u32>(1i16) == present(1u32)) { panic("TryFrom #2741") }
    if !(narrow<i16, u32>(32767i16) == present(32767u32)) { panic("TryFrom #2742") }
    if !(missing(narrow<i32, u32>((-2147483648i32)))) { panic("TryFrom #2743") }
    if !(missing(narrow<i32, u32>((-1i32)))) { panic("TryFrom #2744") }
    if !(narrow<i32, u32>(0i32) == present(0u32)) { panic("TryFrom #2745") }
    if !(narrow<i32, u32>(1i32) == present(1u32)) { panic("TryFrom #2746") }
    if !(narrow<i32, u32>(2147483647i32) == present(2147483647u32)) { panic("TryFrom #2747") }
    if !(missing(narrow<i64, u32>((-9223372036854775808i64)))) { panic("TryFrom #2748") }
    if !(missing(narrow<i64, u32>((-1i64)))) { panic("TryFrom #2749") }
    if !(narrow<i64, u32>(0i64) == present(0u32)) { panic("TryFrom #2750") }
    if !(narrow<i64, u32>(1i64) == present(1u32)) { panic("TryFrom #2751") }
    if !(missing(narrow<i64, u32>(9223372036854775807i64))) { panic("TryFrom #2752") }
    if !(missing(narrow<i128, u32>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2753") }
    if !(missing(narrow<i128, u32>((-1i128)))) { panic("TryFrom #2754") }
    if !(narrow<i128, u32>(0i128) == present(0u32)) { panic("TryFrom #2755") }
    if !(narrow<i128, u32>(1i128) == present(1u32)) { panic("TryFrom #2756") }
    if !(missing(narrow<i128, u32>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2757") }
    if !(missing(narrow<isize, u32>((-9223372036854775808isize)))) { panic("TryFrom #2758") }
    if !(missing(narrow<isize, u32>((-1isize)))) { panic("TryFrom #2759") }
    if !(narrow<isize, u32>(0isize) == present(0u32)) { panic("TryFrom #2760") }
    if !(narrow<isize, u32>(1isize) == present(1u32)) { panic("TryFrom #2761") }
    if !(missing(narrow<isize, u32>(9223372036854775807isize))) { panic("TryFrom #2762") }
    if !(narrow<u64, u32>(0u64) == present(0u32)) { panic("TryFrom #2763") }
    if !(narrow<u64, u32>(1u64) == present(1u32)) { panic("TryFrom #2764") }
    if !(missing(narrow<u64, u32>(18446744073709551615u64))) { panic("TryFrom #2765") }
    if !(narrow<u128, u32>(0u128) == present(0u32)) { panic("TryFrom #2766") }
    if !(narrow<u128, u32>(1u128) == present(1u32)) { panic("TryFrom #2767") }
    if !(missing(narrow<u128, u32>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2768") }
    if !(narrow<usize, u32>(0usize) == present(0u32)) { panic("TryFrom #2769") }
    if !(narrow<usize, u32>(1usize) == present(1u32)) { panic("TryFrom #2770") }
    if !(missing(narrow<usize, u32>(18446744073709551615usize))) { panic("TryFrom #2771") }
    if !(missing(narrow<i8, u64>((-128i8)))) { panic("TryFrom #2772") }
    if !(missing(narrow<i8, u64>((-1i8)))) { panic("TryFrom #2773") }
    if !(narrow<i8, u64>(0i8) == present(0u64)) { panic("TryFrom #2774") }
    if !(narrow<i8, u64>(1i8) == present(1u64)) { panic("TryFrom #2775") }
    if !(narrow<i8, u64>(127i8) == present(127u64)) { panic("TryFrom #2776") }
    if !(missing(narrow<i16, u64>((-32768i16)))) { panic("TryFrom #2777") }
    if !(missing(narrow<i16, u64>((-1i16)))) { panic("TryFrom #2778") }
    if !(narrow<i16, u64>(0i16) == present(0u64)) { panic("TryFrom #2779") }
    if !(narrow<i16, u64>(1i16) == present(1u64)) { panic("TryFrom #2780") }
    if !(narrow<i16, u64>(32767i16) == present(32767u64)) { panic("TryFrom #2781") }
    if !(missing(narrow<i32, u64>((-2147483648i32)))) { panic("TryFrom #2782") }
    if !(missing(narrow<i32, u64>((-1i32)))) { panic("TryFrom #2783") }
    if !(narrow<i32, u64>(0i32) == present(0u64)) { panic("TryFrom #2784") }
    if !(narrow<i32, u64>(1i32) == present(1u64)) { panic("TryFrom #2785") }
    if !(narrow<i32, u64>(2147483647i32) == present(2147483647u64)) { panic("TryFrom #2786") }
    if !(missing(narrow<i64, u64>((-9223372036854775808i64)))) { panic("TryFrom #2787") }
    if !(missing(narrow<i64, u64>((-1i64)))) { panic("TryFrom #2788") }
    if !(narrow<i64, u64>(0i64) == present(0u64)) { panic("TryFrom #2789") }
    if !(narrow<i64, u64>(1i64) == present(1u64)) { panic("TryFrom #2790") }
    if !(narrow<i64, u64>(9223372036854775807i64) == present(9223372036854775807u64)) { panic("TryFrom #2791") }
    if !(missing(narrow<i128, u64>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2792") }
    if !(missing(narrow<i128, u64>((-1i128)))) { panic("TryFrom #2793") }
    if !(narrow<i128, u64>(0i128) == present(0u64)) { panic("TryFrom #2794") }
    if !(narrow<i128, u64>(1i128) == present(1u64)) { panic("TryFrom #2795") }
    if !(missing(narrow<i128, u64>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2796") }
    if !(missing(narrow<isize, u64>((-9223372036854775808isize)))) { panic("TryFrom #2797") }
    if !(missing(narrow<isize, u64>((-1isize)))) { panic("TryFrom #2798") }
    if !(narrow<isize, u64>(0isize) == present(0u64)) { panic("TryFrom #2799") }
    if !(narrow<isize, u64>(1isize) == present(1u64)) { panic("TryFrom #2800") }
    if !(narrow<isize, u64>(9223372036854775807isize) == present(9223372036854775807u64)) { panic("TryFrom #2801") }
    if !(narrow<u128, u64>(0u128) == present(0u64)) { panic("TryFrom #2802") }
    if !(narrow<u128, u64>(1u128) == present(1u64)) { panic("TryFrom #2803") }
    if !(missing(narrow<u128, u64>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2804") }
    if !(narrow<usize, u64>(0usize) == present(0u64)) { panic("TryFrom #2805") }
    if !(narrow<usize, u64>(1usize) == present(1u64)) { panic("TryFrom #2806") }
    if !(narrow<usize, u64>(18446744073709551615usize) == present(18446744073709551615u64)) { panic("TryFrom #2807") }
    if !(missing(narrow<i8, u128>((-128i8)))) { panic("TryFrom #2808") }
    if !(missing(narrow<i8, u128>((-1i8)))) { panic("TryFrom #2809") }
    if !(narrow<i8, u128>(0i8) == present(0u128)) { panic("TryFrom #2810") }
    if !(narrow<i8, u128>(1i8) == present(1u128)) { panic("TryFrom #2811") }
    if !(narrow<i8, u128>(127i8) == present(127u128)) { panic("TryFrom #2812") }
    if !(missing(narrow<i16, u128>((-32768i16)))) { panic("TryFrom #2813") }
    if !(missing(narrow<i16, u128>((-1i16)))) { panic("TryFrom #2814") }
    if !(narrow<i16, u128>(0i16) == present(0u128)) { panic("TryFrom #2815") }
    if !(narrow<i16, u128>(1i16) == present(1u128)) { panic("TryFrom #2816") }
    if !(narrow<i16, u128>(32767i16) == present(32767u128)) { panic("TryFrom #2817") }
    if !(missing(narrow<i32, u128>((-2147483648i32)))) { panic("TryFrom #2818") }
    if !(missing(narrow<i32, u128>((-1i32)))) { panic("TryFrom #2819") }
    if !(narrow<i32, u128>(0i32) == present(0u128)) { panic("TryFrom #2820") }
    if !(narrow<i32, u128>(1i32) == present(1u128)) { panic("TryFrom #2821") }
    if !(narrow<i32, u128>(2147483647i32) == present(2147483647u128)) { panic("TryFrom #2822") }
    if !(missing(narrow<i64, u128>((-9223372036854775808i64)))) { panic("TryFrom #2823") }
    if !(missing(narrow<i64, u128>((-1i64)))) { panic("TryFrom #2824") }
    if !(narrow<i64, u128>(0i64) == present(0u128)) { panic("TryFrom #2825") }
    if !(narrow<i64, u128>(1i64) == present(1u128)) { panic("TryFrom #2826") }
    if !(narrow<i64, u128>(9223372036854775807i64) == present(9223372036854775807u128)) { panic("TryFrom #2827") }
    if !(missing(narrow<i128, u128>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2828") }
    if !(missing(narrow<i128, u128>((-1i128)))) { panic("TryFrom #2829") }
    if !(narrow<i128, u128>(0i128) == present(0u128)) { panic("TryFrom #2830") }
    if !(narrow<i128, u128>(1i128) == present(1u128)) { panic("TryFrom #2831") }
    if !(narrow<i128, u128>(170141183460469231731687303715884105727i128) == present(170141183460469231731687303715884105727u128)) { panic("TryFrom #2832") }
    if !(missing(narrow<isize, u128>((-9223372036854775808isize)))) { panic("TryFrom #2833") }
    if !(missing(narrow<isize, u128>((-1isize)))) { panic("TryFrom #2834") }
    if !(narrow<isize, u128>(0isize) == present(0u128)) { panic("TryFrom #2835") }
    if !(narrow<isize, u128>(1isize) == present(1u128)) { panic("TryFrom #2836") }
    if !(narrow<isize, u128>(9223372036854775807isize) == present(9223372036854775807u128)) { panic("TryFrom #2837") }
    if !(narrow<usize, u128>(0usize) == present(0u128)) { panic("TryFrom #2838") }
    if !(narrow<usize, u128>(1usize) == present(1u128)) { panic("TryFrom #2839") }
    if !(narrow<usize, u128>(18446744073709551615usize) == present(18446744073709551615u128)) { panic("TryFrom #2840") }
    if !(missing(narrow<i8, usize>((-128i8)))) { panic("TryFrom #2841") }
    if !(missing(narrow<i8, usize>((-1i8)))) { panic("TryFrom #2842") }
    if !(narrow<i8, usize>(0i8) == present(0usize)) { panic("TryFrom #2843") }
    if !(narrow<i8, usize>(1i8) == present(1usize)) { panic("TryFrom #2844") }
    if !(narrow<i8, usize>(127i8) == present(127usize)) { panic("TryFrom #2845") }
    if !(missing(narrow<i16, usize>((-32768i16)))) { panic("TryFrom #2846") }
    if !(missing(narrow<i16, usize>((-1i16)))) { panic("TryFrom #2847") }
    if !(narrow<i16, usize>(0i16) == present(0usize)) { panic("TryFrom #2848") }
    if !(narrow<i16, usize>(1i16) == present(1usize)) { panic("TryFrom #2849") }
    if !(narrow<i16, usize>(32767i16) == present(32767usize)) { panic("TryFrom #2850") }
}

fn group19() {
    if !(missing(narrow<i32, usize>((-2147483648i32)))) { panic("TryFrom #2851") }
    if !(missing(narrow<i32, usize>((-1i32)))) { panic("TryFrom #2852") }
    if !(narrow<i32, usize>(0i32) == present(0usize)) { panic("TryFrom #2853") }
    if !(narrow<i32, usize>(1i32) == present(1usize)) { panic("TryFrom #2854") }
    if !(narrow<i32, usize>(2147483647i32) == present(2147483647usize)) { panic("TryFrom #2855") }
    if !(missing(narrow<i64, usize>((-9223372036854775808i64)))) { panic("TryFrom #2856") }
    if !(missing(narrow<i64, usize>((-1i64)))) { panic("TryFrom #2857") }
    if !(narrow<i64, usize>(0i64) == present(0usize)) { panic("TryFrom #2858") }
    if !(narrow<i64, usize>(1i64) == present(1usize)) { panic("TryFrom #2859") }
    if !(narrow<i64, usize>(9223372036854775807i64) == present(9223372036854775807usize)) { panic("TryFrom #2860") }
    if !(missing(narrow<i128, usize>((-170141183460469231731687303715884105728i128)))) { panic("TryFrom #2861") }
    if !(missing(narrow<i128, usize>((-1i128)))) { panic("TryFrom #2862") }
    if !(narrow<i128, usize>(0i128) == present(0usize)) { panic("TryFrom #2863") }
    if !(narrow<i128, usize>(1i128) == present(1usize)) { panic("TryFrom #2864") }
    if !(missing(narrow<i128, usize>(170141183460469231731687303715884105727i128))) { panic("TryFrom #2865") }
    if !(missing(narrow<isize, usize>((-9223372036854775808isize)))) { panic("TryFrom #2866") }
    if !(missing(narrow<isize, usize>((-1isize)))) { panic("TryFrom #2867") }
    if !(narrow<isize, usize>(0isize) == present(0usize)) { panic("TryFrom #2868") }
    if !(narrow<isize, usize>(1isize) == present(1usize)) { panic("TryFrom #2869") }
    if !(narrow<isize, usize>(9223372036854775807isize) == present(9223372036854775807usize)) { panic("TryFrom #2870") }
    if !(narrow<u32, usize>(0u32) == present(0usize)) { panic("TryFrom #2871") }
    if !(narrow<u32, usize>(1u32) == present(1usize)) { panic("TryFrom #2872") }
    if !(narrow<u32, usize>(4294967295u32) == present(4294967295usize)) { panic("TryFrom #2873") }
    if !(narrow<u64, usize>(0u64) == present(0usize)) { panic("TryFrom #2874") }
    if !(narrow<u64, usize>(1u64) == present(1usize)) { panic("TryFrom #2875") }
    if !(narrow<u64, usize>(18446744073709551615u64) == present(18446744073709551615usize)) { panic("TryFrom #2876") }
    if !(narrow<u128, usize>(0u128) == present(0usize)) { panic("TryFrom #2877") }
    if !(narrow<u128, usize>(1u128) == present(1usize)) { panic("TryFrom #2878") }
    if !(missing(narrow<u128, usize>(340282366920938463463374607431768211455u128))) { panic("TryFrom #2879") }
}

fn main(): i32 {
    group0()
    group1()
    group2()
    group3()
    group4()
    group5()
    group6()
    group7()
    group8()
    group9()
    group10()
    group11()
    group12()
    group13()
    group14()
    group15()
    group16()
    group17()
    group18()
    group19()
    0
}
