// profiles: debug release
// Every Wrapping operator in its value and reference operand forms, the
// compound assignments from Wrapping, &Wrapping, T and &T, shifts by usize and
// &usize, and Not/Neg on references, at every integer width. Results wrap.
import core.num
import core.num.Wrapping
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

fn group0() {
    if !(add(Wrapping(125i8), Wrapping(7i8)).value == (-124i8)) { panic("add #1") }
    if !(add((read Wrapping(125i8)), Wrapping(7i8)).value == (-124i8)) { panic("add #2") }
    if !(add(Wrapping(125i8), (read Wrapping(7i8))).value == (-124i8)) { panic("add #3") }
    if !(add((read Wrapping(125i8)), (read Wrapping(7i8))).value == (-124i8)) { panic("add #4") }
    if !(add_assign(Wrapping(125i8), Wrapping(7i8)).value == (-124i8)) { panic("add_assign #5") }
    if !(add_assign(Wrapping(125i8), (read Wrapping(7i8))).value == (-124i8)) { panic("add_assign #6") }
    if !(add_assign(Wrapping(125i8), 7i8).value == (-124i8)) { panic("add_assign #7") }
    if !(add_assign(Wrapping(125i8), (read 7i8)).value == (-124i8)) { panic("add_assign #8") }
    if !(sub(Wrapping(125i8), Wrapping(7i8)).value == 118i8) { panic("sub #9") }
    if !(sub((read Wrapping(125i8)), Wrapping(7i8)).value == 118i8) { panic("sub #10") }
    if !(sub(Wrapping(125i8), (read Wrapping(7i8))).value == 118i8) { panic("sub #11") }
    if !(sub((read Wrapping(125i8)), (read Wrapping(7i8))).value == 118i8) { panic("sub #12") }
    if !(sub_assign(Wrapping(125i8), Wrapping(7i8)).value == 118i8) { panic("sub_assign #13") }
    if !(sub_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 118i8) { panic("sub_assign #14") }
    if !(sub_assign(Wrapping(125i8), 7i8).value == 118i8) { panic("sub_assign #15") }
    if !(sub_assign(Wrapping(125i8), (read 7i8)).value == 118i8) { panic("sub_assign #16") }
    if !(mul(Wrapping(125i8), Wrapping(7i8)).value == 107i8) { panic("mul #17") }
    if !(mul((read Wrapping(125i8)), Wrapping(7i8)).value == 107i8) { panic("mul #18") }
    if !(mul(Wrapping(125i8), (read Wrapping(7i8))).value == 107i8) { panic("mul #19") }
    if !(mul((read Wrapping(125i8)), (read Wrapping(7i8))).value == 107i8) { panic("mul #20") }
    if !(mul_assign(Wrapping(125i8), Wrapping(7i8)).value == 107i8) { panic("mul_assign #21") }
    if !(mul_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 107i8) { panic("mul_assign #22") }
    if !(mul_assign(Wrapping(125i8), 7i8).value == 107i8) { panic("mul_assign #23") }
    if !(mul_assign(Wrapping(125i8), (read 7i8)).value == 107i8) { panic("mul_assign #24") }
    if !(div(Wrapping(125i8), Wrapping(7i8)).value == 17i8) { panic("div #25") }
    if !(div((read Wrapping(125i8)), Wrapping(7i8)).value == 17i8) { panic("div #26") }
    if !(div(Wrapping(125i8), (read Wrapping(7i8))).value == 17i8) { panic("div #27") }
    if !(div((read Wrapping(125i8)), (read Wrapping(7i8))).value == 17i8) { panic("div #28") }
    if !(div_assign(Wrapping(125i8), Wrapping(7i8)).value == 17i8) { panic("div_assign #29") }
    if !(div_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 17i8) { panic("div_assign #30") }
    if !(div_assign(Wrapping(125i8), 7i8).value == 17i8) { panic("div_assign #31") }
    if !(div_assign(Wrapping(125i8), (read 7i8)).value == 17i8) { panic("div_assign #32") }
    if !(rem(Wrapping(125i8), Wrapping(7i8)).value == 6i8) { panic("rem #33") }
    if !(rem((read Wrapping(125i8)), Wrapping(7i8)).value == 6i8) { panic("rem #34") }
    if !(rem(Wrapping(125i8), (read Wrapping(7i8))).value == 6i8) { panic("rem #35") }
    if !(rem((read Wrapping(125i8)), (read Wrapping(7i8))).value == 6i8) { panic("rem #36") }
    if !(rem_assign(Wrapping(125i8), Wrapping(7i8)).value == 6i8) { panic("rem_assign #37") }
    if !(rem_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 6i8) { panic("rem_assign #38") }
    if !(rem_assign(Wrapping(125i8), 7i8).value == 6i8) { panic("rem_assign #39") }
    if !(rem_assign(Wrapping(125i8), (read 7i8)).value == 6i8) { panic("rem_assign #40") }
    if !(and(Wrapping(125i8), Wrapping(7i8)).value == 5i8) { panic("and #41") }
    if !(and((read Wrapping(125i8)), Wrapping(7i8)).value == 5i8) { panic("and #42") }
    if !(and(Wrapping(125i8), (read Wrapping(7i8))).value == 5i8) { panic("and #43") }
    if !(and((read Wrapping(125i8)), (read Wrapping(7i8))).value == 5i8) { panic("and #44") }
    if !(and_assign(Wrapping(125i8), Wrapping(7i8)).value == 5i8) { panic("and_assign #45") }
    if !(and_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 5i8) { panic("and_assign #46") }
    if !(and_assign(Wrapping(125i8), 7i8).value == 5i8) { panic("and_assign #47") }
    if !(and_assign(Wrapping(125i8), (read 7i8)).value == 5i8) { panic("and_assign #48") }
    if !(or(Wrapping(125i8), Wrapping(7i8)).value == 127i8) { panic("or #49") }
    if !(or((read Wrapping(125i8)), Wrapping(7i8)).value == 127i8) { panic("or #50") }
    if !(or(Wrapping(125i8), (read Wrapping(7i8))).value == 127i8) { panic("or #51") }
    if !(or((read Wrapping(125i8)), (read Wrapping(7i8))).value == 127i8) { panic("or #52") }
    if !(or_assign(Wrapping(125i8), Wrapping(7i8)).value == 127i8) { panic("or_assign #53") }
    if !(or_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 127i8) { panic("or_assign #54") }
    if !(or_assign(Wrapping(125i8), 7i8).value == 127i8) { panic("or_assign #55") }
    if !(or_assign(Wrapping(125i8), (read 7i8)).value == 127i8) { panic("or_assign #56") }
    if !(xor(Wrapping(125i8), Wrapping(7i8)).value == 122i8) { panic("xor #57") }
    if !(xor((read Wrapping(125i8)), Wrapping(7i8)).value == 122i8) { panic("xor #58") }
    if !(xor(Wrapping(125i8), (read Wrapping(7i8))).value == 122i8) { panic("xor #59") }
    if !(xor((read Wrapping(125i8)), (read Wrapping(7i8))).value == 122i8) { panic("xor #60") }
    if !(xor_assign(Wrapping(125i8), Wrapping(7i8)).value == 122i8) { panic("xor_assign #61") }
    if !(xor_assign(Wrapping(125i8), (read Wrapping(7i8))).value == 122i8) { panic("xor_assign #62") }
    if !(xor_assign(Wrapping(125i8), 7i8).value == 122i8) { panic("xor_assign #63") }
    if !(xor_assign(Wrapping(125i8), (read 7i8)).value == 122i8) { panic("xor_assign #64") }
    if !(shl(Wrapping(125i8), 3usize).value == (-24i8)) { panic("shl #65") }
    if !(shr(Wrapping(125i8), 3usize).value == 15i8) { panic("shr #66") }
    if !(shl((read Wrapping(125i8)), 3usize).value == (-24i8)) { panic("shl #67") }
    if !(shr((read Wrapping(125i8)), 3usize).value == 15i8) { panic("shr #68") }
    if !(shl(Wrapping(125i8), (read 3usize)).value == (-24i8)) { panic("shl #69") }
    if !(shr(Wrapping(125i8), (read 3usize)).value == 15i8) { panic("shr #70") }
    if !(shl((read Wrapping(125i8)), (read 3usize)).value == (-24i8)) { panic("shl #71") }
    if !(shr((read Wrapping(125i8)), (read 3usize)).value == 15i8) { panic("shr #72") }
    if !(shl_assign(Wrapping(125i8), 3usize).value == (-24i8)) { panic("shl_assign #73") }
    if !(shr_assign(Wrapping(125i8), 3usize).value == 15i8) { panic("shr_assign #74") }
    if !(shl_assign(Wrapping(125i8), (read 3usize)).value == (-24i8)) { panic("shl_assign #75") }
    if !(shr_assign(Wrapping(125i8), (read 3usize)).value == 15i8) { panic("shr_assign #76") }
    if !(shl(Wrapping(125i8), 11usize).value == (-24i8)) { panic("shl #77") }
    if !(shr(Wrapping(125i8), 11usize).value == 15i8) { panic("shr #78") }
    if !(shl((read Wrapping(125i8)), 11usize).value == (-24i8)) { panic("shl #79") }
    if !(shr((read Wrapping(125i8)), 11usize).value == 15i8) { panic("shr #80") }
    if !(shl(Wrapping(125i8), (read 11usize)).value == (-24i8)) { panic("shl #81") }
    if !(shr(Wrapping(125i8), (read 11usize)).value == 15i8) { panic("shr #82") }
    if !(shl((read Wrapping(125i8)), (read 11usize)).value == (-24i8)) { panic("shl #83") }
    if !(shr((read Wrapping(125i8)), (read 11usize)).value == 15i8) { panic("shr #84") }
    if !(shl_assign(Wrapping(125i8), 11usize).value == (-24i8)) { panic("shl_assign #85") }
    if !(shr_assign(Wrapping(125i8), 11usize).value == 15i8) { panic("shr_assign #86") }
    if !(shl_assign(Wrapping(125i8), (read 11usize)).value == (-24i8)) { panic("shl_assign #87") }
    if !(shr_assign(Wrapping(125i8), (read 11usize)).value == 15i8) { panic("shr_assign #88") }
    if !(not((read Wrapping(125i8))).value == (-126i8) && not(Wrapping(125i8)).value == (-126i8)) { panic("not #89") }
    if !(neg((read Wrapping(125i8))).value == (-125i8) && neg(Wrapping(125i8)).value == (-125i8)) { panic("neg #90") }
    if !(neg((read Wrapping(i8.MIN))).value == i8.MIN) { panic("neg #91") }
    if !(add(Wrapping(32765i16), Wrapping(7i16)).value == (-32764i16)) { panic("add #92") }
    if !(add((read Wrapping(32765i16)), Wrapping(7i16)).value == (-32764i16)) { panic("add #93") }
    if !(add(Wrapping(32765i16), (read Wrapping(7i16))).value == (-32764i16)) { panic("add #94") }
    if !(add((read Wrapping(32765i16)), (read Wrapping(7i16))).value == (-32764i16)) { panic("add #95") }
    if !(add_assign(Wrapping(32765i16), Wrapping(7i16)).value == (-32764i16)) { panic("add_assign #96") }
    if !(add_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == (-32764i16)) { panic("add_assign #97") }
    if !(add_assign(Wrapping(32765i16), 7i16).value == (-32764i16)) { panic("add_assign #98") }
    if !(add_assign(Wrapping(32765i16), (read 7i16)).value == (-32764i16)) { panic("add_assign #99") }
    if !(sub(Wrapping(32765i16), Wrapping(7i16)).value == 32758i16) { panic("sub #100") }
    if !(sub((read Wrapping(32765i16)), Wrapping(7i16)).value == 32758i16) { panic("sub #101") }
    if !(sub(Wrapping(32765i16), (read Wrapping(7i16))).value == 32758i16) { panic("sub #102") }
    if !(sub((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 32758i16) { panic("sub #103") }
    if !(sub_assign(Wrapping(32765i16), Wrapping(7i16)).value == 32758i16) { panic("sub_assign #104") }
    if !(sub_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 32758i16) { panic("sub_assign #105") }
    if !(sub_assign(Wrapping(32765i16), 7i16).value == 32758i16) { panic("sub_assign #106") }
    if !(sub_assign(Wrapping(32765i16), (read 7i16)).value == 32758i16) { panic("sub_assign #107") }
    if !(mul(Wrapping(32765i16), Wrapping(7i16)).value == 32747i16) { panic("mul #108") }
    if !(mul((read Wrapping(32765i16)), Wrapping(7i16)).value == 32747i16) { panic("mul #109") }
    if !(mul(Wrapping(32765i16), (read Wrapping(7i16))).value == 32747i16) { panic("mul #110") }
    if !(mul((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 32747i16) { panic("mul #111") }
    if !(mul_assign(Wrapping(32765i16), Wrapping(7i16)).value == 32747i16) { panic("mul_assign #112") }
    if !(mul_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 32747i16) { panic("mul_assign #113") }
    if !(mul_assign(Wrapping(32765i16), 7i16).value == 32747i16) { panic("mul_assign #114") }
    if !(mul_assign(Wrapping(32765i16), (read 7i16)).value == 32747i16) { panic("mul_assign #115") }
    if !(div(Wrapping(32765i16), Wrapping(7i16)).value == 4680i16) { panic("div #116") }
    if !(div((read Wrapping(32765i16)), Wrapping(7i16)).value == 4680i16) { panic("div #117") }
    if !(div(Wrapping(32765i16), (read Wrapping(7i16))).value == 4680i16) { panic("div #118") }
    if !(div((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 4680i16) { panic("div #119") }
    if !(div_assign(Wrapping(32765i16), Wrapping(7i16)).value == 4680i16) { panic("div_assign #120") }
    if !(div_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 4680i16) { panic("div_assign #121") }
    if !(div_assign(Wrapping(32765i16), 7i16).value == 4680i16) { panic("div_assign #122") }
    if !(div_assign(Wrapping(32765i16), (read 7i16)).value == 4680i16) { panic("div_assign #123") }
    if !(rem(Wrapping(32765i16), Wrapping(7i16)).value == 5i16) { panic("rem #124") }
    if !(rem((read Wrapping(32765i16)), Wrapping(7i16)).value == 5i16) { panic("rem #125") }
    if !(rem(Wrapping(32765i16), (read Wrapping(7i16))).value == 5i16) { panic("rem #126") }
    if !(rem((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 5i16) { panic("rem #127") }
    if !(rem_assign(Wrapping(32765i16), Wrapping(7i16)).value == 5i16) { panic("rem_assign #128") }
    if !(rem_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 5i16) { panic("rem_assign #129") }
    if !(rem_assign(Wrapping(32765i16), 7i16).value == 5i16) { panic("rem_assign #130") }
    if !(rem_assign(Wrapping(32765i16), (read 7i16)).value == 5i16) { panic("rem_assign #131") }
    if !(and(Wrapping(32765i16), Wrapping(7i16)).value == 5i16) { panic("and #132") }
    if !(and((read Wrapping(32765i16)), Wrapping(7i16)).value == 5i16) { panic("and #133") }
    if !(and(Wrapping(32765i16), (read Wrapping(7i16))).value == 5i16) { panic("and #134") }
    if !(and((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 5i16) { panic("and #135") }
    if !(and_assign(Wrapping(32765i16), Wrapping(7i16)).value == 5i16) { panic("and_assign #136") }
    if !(and_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 5i16) { panic("and_assign #137") }
    if !(and_assign(Wrapping(32765i16), 7i16).value == 5i16) { panic("and_assign #138") }
    if !(and_assign(Wrapping(32765i16), (read 7i16)).value == 5i16) { panic("and_assign #139") }
    if !(or(Wrapping(32765i16), Wrapping(7i16)).value == 32767i16) { panic("or #140") }
    if !(or((read Wrapping(32765i16)), Wrapping(7i16)).value == 32767i16) { panic("or #141") }
    if !(or(Wrapping(32765i16), (read Wrapping(7i16))).value == 32767i16) { panic("or #142") }
    if !(or((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 32767i16) { panic("or #143") }
    if !(or_assign(Wrapping(32765i16), Wrapping(7i16)).value == 32767i16) { panic("or_assign #144") }
    if !(or_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 32767i16) { panic("or_assign #145") }
    if !(or_assign(Wrapping(32765i16), 7i16).value == 32767i16) { panic("or_assign #146") }
    if !(or_assign(Wrapping(32765i16), (read 7i16)).value == 32767i16) { panic("or_assign #147") }
    if !(xor(Wrapping(32765i16), Wrapping(7i16)).value == 32762i16) { panic("xor #148") }
    if !(xor((read Wrapping(32765i16)), Wrapping(7i16)).value == 32762i16) { panic("xor #149") }
    if !(xor(Wrapping(32765i16), (read Wrapping(7i16))).value == 32762i16) { panic("xor #150") }
}

fn group1() {
    if !(xor((read Wrapping(32765i16)), (read Wrapping(7i16))).value == 32762i16) { panic("xor #151") }
    if !(xor_assign(Wrapping(32765i16), Wrapping(7i16)).value == 32762i16) { panic("xor_assign #152") }
    if !(xor_assign(Wrapping(32765i16), (read Wrapping(7i16))).value == 32762i16) { panic("xor_assign #153") }
    if !(xor_assign(Wrapping(32765i16), 7i16).value == 32762i16) { panic("xor_assign #154") }
    if !(xor_assign(Wrapping(32765i16), (read 7i16)).value == 32762i16) { panic("xor_assign #155") }
    if !(shl(Wrapping(32765i16), 3usize).value == (-24i16)) { panic("shl #156") }
    if !(shr(Wrapping(32765i16), 3usize).value == 4095i16) { panic("shr #157") }
    if !(shl((read Wrapping(32765i16)), 3usize).value == (-24i16)) { panic("shl #158") }
    if !(shr((read Wrapping(32765i16)), 3usize).value == 4095i16) { panic("shr #159") }
    if !(shl(Wrapping(32765i16), (read 3usize)).value == (-24i16)) { panic("shl #160") }
    if !(shr(Wrapping(32765i16), (read 3usize)).value == 4095i16) { panic("shr #161") }
    if !(shl((read Wrapping(32765i16)), (read 3usize)).value == (-24i16)) { panic("shl #162") }
    if !(shr((read Wrapping(32765i16)), (read 3usize)).value == 4095i16) { panic("shr #163") }
    if !(shl_assign(Wrapping(32765i16), 3usize).value == (-24i16)) { panic("shl_assign #164") }
    if !(shr_assign(Wrapping(32765i16), 3usize).value == 4095i16) { panic("shr_assign #165") }
    if !(shl_assign(Wrapping(32765i16), (read 3usize)).value == (-24i16)) { panic("shl_assign #166") }
    if !(shr_assign(Wrapping(32765i16), (read 3usize)).value == 4095i16) { panic("shr_assign #167") }
    if !(shl(Wrapping(32765i16), 19usize).value == (-24i16)) { panic("shl #168") }
    if !(shr(Wrapping(32765i16), 19usize).value == 4095i16) { panic("shr #169") }
    if !(shl((read Wrapping(32765i16)), 19usize).value == (-24i16)) { panic("shl #170") }
    if !(shr((read Wrapping(32765i16)), 19usize).value == 4095i16) { panic("shr #171") }
    if !(shl(Wrapping(32765i16), (read 19usize)).value == (-24i16)) { panic("shl #172") }
    if !(shr(Wrapping(32765i16), (read 19usize)).value == 4095i16) { panic("shr #173") }
    if !(shl((read Wrapping(32765i16)), (read 19usize)).value == (-24i16)) { panic("shl #174") }
    if !(shr((read Wrapping(32765i16)), (read 19usize)).value == 4095i16) { panic("shr #175") }
    if !(shl_assign(Wrapping(32765i16), 19usize).value == (-24i16)) { panic("shl_assign #176") }
    if !(shr_assign(Wrapping(32765i16), 19usize).value == 4095i16) { panic("shr_assign #177") }
    if !(shl_assign(Wrapping(32765i16), (read 19usize)).value == (-24i16)) { panic("shl_assign #178") }
    if !(shr_assign(Wrapping(32765i16), (read 19usize)).value == 4095i16) { panic("shr_assign #179") }
    if !(not((read Wrapping(32765i16))).value == (-32766i16) && not(Wrapping(32765i16)).value == (-32766i16)) { panic("not #180") }
    if !(neg((read Wrapping(32765i16))).value == (-32765i16) && neg(Wrapping(32765i16)).value == (-32765i16)) { panic("neg #181") }
    if !(neg((read Wrapping(i16.MIN))).value == i16.MIN) { panic("neg #182") }
    if !(add(Wrapping(2147483645i32), Wrapping(7i32)).value == (-2147483644i32)) { panic("add #183") }
    if !(add((read Wrapping(2147483645i32)), Wrapping(7i32)).value == (-2147483644i32)) { panic("add #184") }
    if !(add(Wrapping(2147483645i32), (read Wrapping(7i32))).value == (-2147483644i32)) { panic("add #185") }
    if !(add((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == (-2147483644i32)) { panic("add #186") }
    if !(add_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == (-2147483644i32)) { panic("add_assign #187") }
    if !(add_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == (-2147483644i32)) { panic("add_assign #188") }
    if !(add_assign(Wrapping(2147483645i32), 7i32).value == (-2147483644i32)) { panic("add_assign #189") }
    if !(add_assign(Wrapping(2147483645i32), (read 7i32)).value == (-2147483644i32)) { panic("add_assign #190") }
    if !(sub(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483638i32) { panic("sub #191") }
    if !(sub((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 2147483638i32) { panic("sub #192") }
    if !(sub(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483638i32) { panic("sub #193") }
    if !(sub((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 2147483638i32) { panic("sub #194") }
    if !(sub_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483638i32) { panic("sub_assign #195") }
    if !(sub_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483638i32) { panic("sub_assign #196") }
    if !(sub_assign(Wrapping(2147483645i32), 7i32).value == 2147483638i32) { panic("sub_assign #197") }
    if !(sub_assign(Wrapping(2147483645i32), (read 7i32)).value == 2147483638i32) { panic("sub_assign #198") }
    if !(mul(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483627i32) { panic("mul #199") }
    if !(mul((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 2147483627i32) { panic("mul #200") }
    if !(mul(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483627i32) { panic("mul #201") }
    if !(mul((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 2147483627i32) { panic("mul #202") }
    if !(mul_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483627i32) { panic("mul_assign #203") }
    if !(mul_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483627i32) { panic("mul_assign #204") }
    if !(mul_assign(Wrapping(2147483645i32), 7i32).value == 2147483627i32) { panic("mul_assign #205") }
    if !(mul_assign(Wrapping(2147483645i32), (read 7i32)).value == 2147483627i32) { panic("mul_assign #206") }
    if !(div(Wrapping(2147483645i32), Wrapping(7i32)).value == 306783377i32) { panic("div #207") }
    if !(div((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 306783377i32) { panic("div #208") }
    if !(div(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 306783377i32) { panic("div #209") }
    if !(div((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 306783377i32) { panic("div #210") }
    if !(div_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 306783377i32) { panic("div_assign #211") }
    if !(div_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 306783377i32) { panic("div_assign #212") }
    if !(div_assign(Wrapping(2147483645i32), 7i32).value == 306783377i32) { panic("div_assign #213") }
    if !(div_assign(Wrapping(2147483645i32), (read 7i32)).value == 306783377i32) { panic("div_assign #214") }
    if !(rem(Wrapping(2147483645i32), Wrapping(7i32)).value == 6i32) { panic("rem #215") }
    if !(rem((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 6i32) { panic("rem #216") }
    if !(rem(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 6i32) { panic("rem #217") }
    if !(rem((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 6i32) { panic("rem #218") }
    if !(rem_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 6i32) { panic("rem_assign #219") }
    if !(rem_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 6i32) { panic("rem_assign #220") }
    if !(rem_assign(Wrapping(2147483645i32), 7i32).value == 6i32) { panic("rem_assign #221") }
    if !(rem_assign(Wrapping(2147483645i32), (read 7i32)).value == 6i32) { panic("rem_assign #222") }
    if !(and(Wrapping(2147483645i32), Wrapping(7i32)).value == 5i32) { panic("and #223") }
    if !(and((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 5i32) { panic("and #224") }
    if !(and(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 5i32) { panic("and #225") }
    if !(and((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 5i32) { panic("and #226") }
    if !(and_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 5i32) { panic("and_assign #227") }
    if !(and_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 5i32) { panic("and_assign #228") }
    if !(and_assign(Wrapping(2147483645i32), 7i32).value == 5i32) { panic("and_assign #229") }
    if !(and_assign(Wrapping(2147483645i32), (read 7i32)).value == 5i32) { panic("and_assign #230") }
    if !(or(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483647i32) { panic("or #231") }
    if !(or((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 2147483647i32) { panic("or #232") }
    if !(or(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483647i32) { panic("or #233") }
    if !(or((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 2147483647i32) { panic("or #234") }
    if !(or_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483647i32) { panic("or_assign #235") }
    if !(or_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483647i32) { panic("or_assign #236") }
    if !(or_assign(Wrapping(2147483645i32), 7i32).value == 2147483647i32) { panic("or_assign #237") }
    if !(or_assign(Wrapping(2147483645i32), (read 7i32)).value == 2147483647i32) { panic("or_assign #238") }
    if !(xor(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483642i32) { panic("xor #239") }
    if !(xor((read Wrapping(2147483645i32)), Wrapping(7i32)).value == 2147483642i32) { panic("xor #240") }
    if !(xor(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483642i32) { panic("xor #241") }
    if !(xor((read Wrapping(2147483645i32)), (read Wrapping(7i32))).value == 2147483642i32) { panic("xor #242") }
    if !(xor_assign(Wrapping(2147483645i32), Wrapping(7i32)).value == 2147483642i32) { panic("xor_assign #243") }
    if !(xor_assign(Wrapping(2147483645i32), (read Wrapping(7i32))).value == 2147483642i32) { panic("xor_assign #244") }
    if !(xor_assign(Wrapping(2147483645i32), 7i32).value == 2147483642i32) { panic("xor_assign #245") }
    if !(xor_assign(Wrapping(2147483645i32), (read 7i32)).value == 2147483642i32) { panic("xor_assign #246") }
    if !(shl(Wrapping(2147483645i32), 3usize).value == (-24i32)) { panic("shl #247") }
    if !(shr(Wrapping(2147483645i32), 3usize).value == 268435455i32) { panic("shr #248") }
    if !(shl((read Wrapping(2147483645i32)), 3usize).value == (-24i32)) { panic("shl #249") }
    if !(shr((read Wrapping(2147483645i32)), 3usize).value == 268435455i32) { panic("shr #250") }
    if !(shl(Wrapping(2147483645i32), (read 3usize)).value == (-24i32)) { panic("shl #251") }
    if !(shr(Wrapping(2147483645i32), (read 3usize)).value == 268435455i32) { panic("shr #252") }
    if !(shl((read Wrapping(2147483645i32)), (read 3usize)).value == (-24i32)) { panic("shl #253") }
    if !(shr((read Wrapping(2147483645i32)), (read 3usize)).value == 268435455i32) { panic("shr #254") }
    if !(shl_assign(Wrapping(2147483645i32), 3usize).value == (-24i32)) { panic("shl_assign #255") }
    if !(shr_assign(Wrapping(2147483645i32), 3usize).value == 268435455i32) { panic("shr_assign #256") }
    if !(shl_assign(Wrapping(2147483645i32), (read 3usize)).value == (-24i32)) { panic("shl_assign #257") }
    if !(shr_assign(Wrapping(2147483645i32), (read 3usize)).value == 268435455i32) { panic("shr_assign #258") }
    if !(shl(Wrapping(2147483645i32), 35usize).value == (-24i32)) { panic("shl #259") }
    if !(shr(Wrapping(2147483645i32), 35usize).value == 268435455i32) { panic("shr #260") }
    if !(shl((read Wrapping(2147483645i32)), 35usize).value == (-24i32)) { panic("shl #261") }
    if !(shr((read Wrapping(2147483645i32)), 35usize).value == 268435455i32) { panic("shr #262") }
    if !(shl(Wrapping(2147483645i32), (read 35usize)).value == (-24i32)) { panic("shl #263") }
    if !(shr(Wrapping(2147483645i32), (read 35usize)).value == 268435455i32) { panic("shr #264") }
    if !(shl((read Wrapping(2147483645i32)), (read 35usize)).value == (-24i32)) { panic("shl #265") }
    if !(shr((read Wrapping(2147483645i32)), (read 35usize)).value == 268435455i32) { panic("shr #266") }
    if !(shl_assign(Wrapping(2147483645i32), 35usize).value == (-24i32)) { panic("shl_assign #267") }
    if !(shr_assign(Wrapping(2147483645i32), 35usize).value == 268435455i32) { panic("shr_assign #268") }
    if !(shl_assign(Wrapping(2147483645i32), (read 35usize)).value == (-24i32)) { panic("shl_assign #269") }
    if !(shr_assign(Wrapping(2147483645i32), (read 35usize)).value == 268435455i32) { panic("shr_assign #270") }
    if !(not((read Wrapping(2147483645i32))).value == (-2147483646i32) && not(Wrapping(2147483645i32)).value == (-2147483646i32)) { panic("not #271") }
    if !(neg((read Wrapping(2147483645i32))).value == (-2147483645i32) && neg(Wrapping(2147483645i32)).value == (-2147483645i32)) { panic("neg #272") }
    if !(neg((read Wrapping(i32.MIN))).value == i32.MIN) { panic("neg #273") }
    if !(add(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == (-9223372036854775804i64)) { panic("add #274") }
    if !(add((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == (-9223372036854775804i64)) { panic("add #275") }
    if !(add(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == (-9223372036854775804i64)) { panic("add #276") }
    if !(add((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == (-9223372036854775804i64)) { panic("add #277") }
    if !(add_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == (-9223372036854775804i64)) { panic("add_assign #278") }
    if !(add_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == (-9223372036854775804i64)) { panic("add_assign #279") }
    if !(add_assign(Wrapping(9223372036854775805i64), 7i64).value == (-9223372036854775804i64)) { panic("add_assign #280") }
    if !(add_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == (-9223372036854775804i64)) { panic("add_assign #281") }
    if !(sub(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775798i64) { panic("sub #282") }
    if !(sub((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 9223372036854775798i64) { panic("sub #283") }
    if !(sub(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775798i64) { panic("sub #284") }
    if !(sub((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 9223372036854775798i64) { panic("sub #285") }
    if !(sub_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775798i64) { panic("sub_assign #286") }
    if !(sub_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775798i64) { panic("sub_assign #287") }
    if !(sub_assign(Wrapping(9223372036854775805i64), 7i64).value == 9223372036854775798i64) { panic("sub_assign #288") }
    if !(sub_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 9223372036854775798i64) { panic("sub_assign #289") }
    if !(mul(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775787i64) { panic("mul #290") }
    if !(mul((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 9223372036854775787i64) { panic("mul #291") }
    if !(mul(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775787i64) { panic("mul #292") }
    if !(mul((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 9223372036854775787i64) { panic("mul #293") }
    if !(mul_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775787i64) { panic("mul_assign #294") }
    if !(mul_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775787i64) { panic("mul_assign #295") }
    if !(mul_assign(Wrapping(9223372036854775805i64), 7i64).value == 9223372036854775787i64) { panic("mul_assign #296") }
    if !(mul_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 9223372036854775787i64) { panic("mul_assign #297") }
    if !(div(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 1317624576693539400i64) { panic("div #298") }
    if !(div((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 1317624576693539400i64) { panic("div #299") }
    if !(div(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 1317624576693539400i64) { panic("div #300") }
}

fn group2() {
    if !(div((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 1317624576693539400i64) { panic("div #301") }
    if !(div_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 1317624576693539400i64) { panic("div_assign #302") }
    if !(div_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 1317624576693539400i64) { panic("div_assign #303") }
    if !(div_assign(Wrapping(9223372036854775805i64), 7i64).value == 1317624576693539400i64) { panic("div_assign #304") }
    if !(div_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 1317624576693539400i64) { panic("div_assign #305") }
    if !(rem(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 5i64) { panic("rem #306") }
    if !(rem((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 5i64) { panic("rem #307") }
    if !(rem(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 5i64) { panic("rem #308") }
    if !(rem((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 5i64) { panic("rem #309") }
    if !(rem_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 5i64) { panic("rem_assign #310") }
    if !(rem_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 5i64) { panic("rem_assign #311") }
    if !(rem_assign(Wrapping(9223372036854775805i64), 7i64).value == 5i64) { panic("rem_assign #312") }
    if !(rem_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 5i64) { panic("rem_assign #313") }
    if !(and(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 5i64) { panic("and #314") }
    if !(and((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 5i64) { panic("and #315") }
    if !(and(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 5i64) { panic("and #316") }
    if !(and((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 5i64) { panic("and #317") }
    if !(and_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 5i64) { panic("and_assign #318") }
    if !(and_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 5i64) { panic("and_assign #319") }
    if !(and_assign(Wrapping(9223372036854775805i64), 7i64).value == 5i64) { panic("and_assign #320") }
    if !(and_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 5i64) { panic("and_assign #321") }
    if !(or(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775807i64) { panic("or #322") }
    if !(or((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 9223372036854775807i64) { panic("or #323") }
    if !(or(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775807i64) { panic("or #324") }
    if !(or((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 9223372036854775807i64) { panic("or #325") }
    if !(or_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775807i64) { panic("or_assign #326") }
    if !(or_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775807i64) { panic("or_assign #327") }
    if !(or_assign(Wrapping(9223372036854775805i64), 7i64).value == 9223372036854775807i64) { panic("or_assign #328") }
    if !(or_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 9223372036854775807i64) { panic("or_assign #329") }
    if !(xor(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775802i64) { panic("xor #330") }
    if !(xor((read Wrapping(9223372036854775805i64)), Wrapping(7i64)).value == 9223372036854775802i64) { panic("xor #331") }
    if !(xor(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775802i64) { panic("xor #332") }
    if !(xor((read Wrapping(9223372036854775805i64)), (read Wrapping(7i64))).value == 9223372036854775802i64) { panic("xor #333") }
    if !(xor_assign(Wrapping(9223372036854775805i64), Wrapping(7i64)).value == 9223372036854775802i64) { panic("xor_assign #334") }
    if !(xor_assign(Wrapping(9223372036854775805i64), (read Wrapping(7i64))).value == 9223372036854775802i64) { panic("xor_assign #335") }
    if !(xor_assign(Wrapping(9223372036854775805i64), 7i64).value == 9223372036854775802i64) { panic("xor_assign #336") }
    if !(xor_assign(Wrapping(9223372036854775805i64), (read 7i64)).value == 9223372036854775802i64) { panic("xor_assign #337") }
    if !(shl(Wrapping(9223372036854775805i64), 3usize).value == (-24i64)) { panic("shl #338") }
    if !(shr(Wrapping(9223372036854775805i64), 3usize).value == 1152921504606846975i64) { panic("shr #339") }
    if !(shl((read Wrapping(9223372036854775805i64)), 3usize).value == (-24i64)) { panic("shl #340") }
    if !(shr((read Wrapping(9223372036854775805i64)), 3usize).value == 1152921504606846975i64) { panic("shr #341") }
    if !(shl(Wrapping(9223372036854775805i64), (read 3usize)).value == (-24i64)) { panic("shl #342") }
    if !(shr(Wrapping(9223372036854775805i64), (read 3usize)).value == 1152921504606846975i64) { panic("shr #343") }
    if !(shl((read Wrapping(9223372036854775805i64)), (read 3usize)).value == (-24i64)) { panic("shl #344") }
    if !(shr((read Wrapping(9223372036854775805i64)), (read 3usize)).value == 1152921504606846975i64) { panic("shr #345") }
    if !(shl_assign(Wrapping(9223372036854775805i64), 3usize).value == (-24i64)) { panic("shl_assign #346") }
    if !(shr_assign(Wrapping(9223372036854775805i64), 3usize).value == 1152921504606846975i64) { panic("shr_assign #347") }
    if !(shl_assign(Wrapping(9223372036854775805i64), (read 3usize)).value == (-24i64)) { panic("shl_assign #348") }
    if !(shr_assign(Wrapping(9223372036854775805i64), (read 3usize)).value == 1152921504606846975i64) { panic("shr_assign #349") }
    if !(shl(Wrapping(9223372036854775805i64), 67usize).value == (-24i64)) { panic("shl #350") }
    if !(shr(Wrapping(9223372036854775805i64), 67usize).value == 1152921504606846975i64) { panic("shr #351") }
    if !(shl((read Wrapping(9223372036854775805i64)), 67usize).value == (-24i64)) { panic("shl #352") }
    if !(shr((read Wrapping(9223372036854775805i64)), 67usize).value == 1152921504606846975i64) { panic("shr #353") }
    if !(shl(Wrapping(9223372036854775805i64), (read 67usize)).value == (-24i64)) { panic("shl #354") }
    if !(shr(Wrapping(9223372036854775805i64), (read 67usize)).value == 1152921504606846975i64) { panic("shr #355") }
    if !(shl((read Wrapping(9223372036854775805i64)), (read 67usize)).value == (-24i64)) { panic("shl #356") }
    if !(shr((read Wrapping(9223372036854775805i64)), (read 67usize)).value == 1152921504606846975i64) { panic("shr #357") }
    if !(shl_assign(Wrapping(9223372036854775805i64), 67usize).value == (-24i64)) { panic("shl_assign #358") }
    if !(shr_assign(Wrapping(9223372036854775805i64), 67usize).value == 1152921504606846975i64) { panic("shr_assign #359") }
    if !(shl_assign(Wrapping(9223372036854775805i64), (read 67usize)).value == (-24i64)) { panic("shl_assign #360") }
    if !(shr_assign(Wrapping(9223372036854775805i64), (read 67usize)).value == 1152921504606846975i64) { panic("shr_assign #361") }
    if !(not((read Wrapping(9223372036854775805i64))).value == (-9223372036854775806i64) && not(Wrapping(9223372036854775805i64)).value == (-9223372036854775806i64)) { panic("not #362") }
    if !(neg((read Wrapping(9223372036854775805i64))).value == (-9223372036854775805i64) && neg(Wrapping(9223372036854775805i64)).value == (-9223372036854775805i64)) { panic("neg #363") }
    if !(neg((read Wrapping(i64.MIN))).value == i64.MIN) { panic("neg #364") }
    if !(add(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == (-170141183460469231731687303715884105724i128)) { panic("add #365") }
    if !(add((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == (-170141183460469231731687303715884105724i128)) { panic("add #366") }
    if !(add(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == (-170141183460469231731687303715884105724i128)) { panic("add #367") }
    if !(add((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == (-170141183460469231731687303715884105724i128)) { panic("add #368") }
    if !(add_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == (-170141183460469231731687303715884105724i128)) { panic("add_assign #369") }
    if !(add_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == (-170141183460469231731687303715884105724i128)) { panic("add_assign #370") }
    if !(add_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == (-170141183460469231731687303715884105724i128)) { panic("add_assign #371") }
    if !(add_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == (-170141183460469231731687303715884105724i128)) { panic("add_assign #372") }
    if !(sub(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105718i128) { panic("sub #373") }
    if !(sub((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 170141183460469231731687303715884105718i128) { panic("sub #374") }
    if !(sub(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105718i128) { panic("sub #375") }
    if !(sub((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 170141183460469231731687303715884105718i128) { panic("sub #376") }
    if !(sub_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105718i128) { panic("sub_assign #377") }
    if !(sub_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105718i128) { panic("sub_assign #378") }
    if !(sub_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 170141183460469231731687303715884105718i128) { panic("sub_assign #379") }
    if !(sub_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 170141183460469231731687303715884105718i128) { panic("sub_assign #380") }
    if !(mul(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105707i128) { panic("mul #381") }
    if !(mul((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 170141183460469231731687303715884105707i128) { panic("mul #382") }
    if !(mul(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105707i128) { panic("mul #383") }
    if !(mul((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 170141183460469231731687303715884105707i128) { panic("mul #384") }
    if !(mul_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105707i128) { panic("mul_assign #385") }
    if !(mul_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105707i128) { panic("mul_assign #386") }
    if !(mul_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 170141183460469231731687303715884105707i128) { panic("mul_assign #387") }
    if !(mul_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 170141183460469231731687303715884105707i128) { panic("mul_assign #388") }
    if !(div(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 24305883351495604533098186245126300817i128) { panic("div #389") }
    if !(div((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 24305883351495604533098186245126300817i128) { panic("div #390") }
    if !(div(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 24305883351495604533098186245126300817i128) { panic("div #391") }
    if !(div((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 24305883351495604533098186245126300817i128) { panic("div #392") }
    if !(div_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 24305883351495604533098186245126300817i128) { panic("div_assign #393") }
    if !(div_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 24305883351495604533098186245126300817i128) { panic("div_assign #394") }
    if !(div_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 24305883351495604533098186245126300817i128) { panic("div_assign #395") }
    if !(div_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 24305883351495604533098186245126300817i128) { panic("div_assign #396") }
    if !(rem(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 6i128) { panic("rem #397") }
    if !(rem((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 6i128) { panic("rem #398") }
    if !(rem(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 6i128) { panic("rem #399") }
    if !(rem((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 6i128) { panic("rem #400") }
    if !(rem_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 6i128) { panic("rem_assign #401") }
    if !(rem_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 6i128) { panic("rem_assign #402") }
    if !(rem_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 6i128) { panic("rem_assign #403") }
    if !(rem_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 6i128) { panic("rem_assign #404") }
    if !(and(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 5i128) { panic("and #405") }
    if !(and((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 5i128) { panic("and #406") }
    if !(and(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 5i128) { panic("and #407") }
    if !(and((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 5i128) { panic("and #408") }
    if !(and_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 5i128) { panic("and_assign #409") }
    if !(and_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 5i128) { panic("and_assign #410") }
    if !(and_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 5i128) { panic("and_assign #411") }
    if !(and_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 5i128) { panic("and_assign #412") }
    if !(or(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105727i128) { panic("or #413") }
    if !(or((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 170141183460469231731687303715884105727i128) { panic("or #414") }
    if !(or(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105727i128) { panic("or #415") }
    if !(or((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 170141183460469231731687303715884105727i128) { panic("or #416") }
    if !(or_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105727i128) { panic("or_assign #417") }
    if !(or_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105727i128) { panic("or_assign #418") }
    if !(or_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 170141183460469231731687303715884105727i128) { panic("or_assign #419") }
    if !(or_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 170141183460469231731687303715884105727i128) { panic("or_assign #420") }
    if !(xor(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105722i128) { panic("xor #421") }
    if !(xor((read Wrapping(170141183460469231731687303715884105725i128)), Wrapping(7i128)).value == 170141183460469231731687303715884105722i128) { panic("xor #422") }
    if !(xor(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105722i128) { panic("xor #423") }
    if !(xor((read Wrapping(170141183460469231731687303715884105725i128)), (read Wrapping(7i128))).value == 170141183460469231731687303715884105722i128) { panic("xor #424") }
    if !(xor_assign(Wrapping(170141183460469231731687303715884105725i128), Wrapping(7i128)).value == 170141183460469231731687303715884105722i128) { panic("xor_assign #425") }
    if !(xor_assign(Wrapping(170141183460469231731687303715884105725i128), (read Wrapping(7i128))).value == 170141183460469231731687303715884105722i128) { panic("xor_assign #426") }
    if !(xor_assign(Wrapping(170141183460469231731687303715884105725i128), 7i128).value == 170141183460469231731687303715884105722i128) { panic("xor_assign #427") }
    if !(xor_assign(Wrapping(170141183460469231731687303715884105725i128), (read 7i128)).value == 170141183460469231731687303715884105722i128) { panic("xor_assign #428") }
    if !(shl(Wrapping(170141183460469231731687303715884105725i128), 3usize).value == (-24i128)) { panic("shl #429") }
    if !(shr(Wrapping(170141183460469231731687303715884105725i128), 3usize).value == 21267647932558653966460912964485513215i128) { panic("shr #430") }
    if !(shl((read Wrapping(170141183460469231731687303715884105725i128)), 3usize).value == (-24i128)) { panic("shl #431") }
    if !(shr((read Wrapping(170141183460469231731687303715884105725i128)), 3usize).value == 21267647932558653966460912964485513215i128) { panic("shr #432") }
    if !(shl(Wrapping(170141183460469231731687303715884105725i128), (read 3usize)).value == (-24i128)) { panic("shl #433") }
    if !(shr(Wrapping(170141183460469231731687303715884105725i128), (read 3usize)).value == 21267647932558653966460912964485513215i128) { panic("shr #434") }
    if !(shl((read Wrapping(170141183460469231731687303715884105725i128)), (read 3usize)).value == (-24i128)) { panic("shl #435") }
    if !(shr((read Wrapping(170141183460469231731687303715884105725i128)), (read 3usize)).value == 21267647932558653966460912964485513215i128) { panic("shr #436") }
    if !(shl_assign(Wrapping(170141183460469231731687303715884105725i128), 3usize).value == (-24i128)) { panic("shl_assign #437") }
    if !(shr_assign(Wrapping(170141183460469231731687303715884105725i128), 3usize).value == 21267647932558653966460912964485513215i128) { panic("shr_assign #438") }
    if !(shl_assign(Wrapping(170141183460469231731687303715884105725i128), (read 3usize)).value == (-24i128)) { panic("shl_assign #439") }
    if !(shr_assign(Wrapping(170141183460469231731687303715884105725i128), (read 3usize)).value == 21267647932558653966460912964485513215i128) { panic("shr_assign #440") }
    if !(shl(Wrapping(170141183460469231731687303715884105725i128), 131usize).value == (-24i128)) { panic("shl #441") }
    if !(shr(Wrapping(170141183460469231731687303715884105725i128), 131usize).value == 21267647932558653966460912964485513215i128) { panic("shr #442") }
    if !(shl((read Wrapping(170141183460469231731687303715884105725i128)), 131usize).value == (-24i128)) { panic("shl #443") }
    if !(shr((read Wrapping(170141183460469231731687303715884105725i128)), 131usize).value == 21267647932558653966460912964485513215i128) { panic("shr #444") }
    if !(shl(Wrapping(170141183460469231731687303715884105725i128), (read 131usize)).value == (-24i128)) { panic("shl #445") }
    if !(shr(Wrapping(170141183460469231731687303715884105725i128), (read 131usize)).value == 21267647932558653966460912964485513215i128) { panic("shr #446") }
    if !(shl((read Wrapping(170141183460469231731687303715884105725i128)), (read 131usize)).value == (-24i128)) { panic("shl #447") }
    if !(shr((read Wrapping(170141183460469231731687303715884105725i128)), (read 131usize)).value == 21267647932558653966460912964485513215i128) { panic("shr #448") }
    if !(shl_assign(Wrapping(170141183460469231731687303715884105725i128), 131usize).value == (-24i128)) { panic("shl_assign #449") }
    if !(shr_assign(Wrapping(170141183460469231731687303715884105725i128), 131usize).value == 21267647932558653966460912964485513215i128) { panic("shr_assign #450") }
}

fn group3() {
    if !(shl_assign(Wrapping(170141183460469231731687303715884105725i128), (read 131usize)).value == (-24i128)) { panic("shl_assign #451") }
    if !(shr_assign(Wrapping(170141183460469231731687303715884105725i128), (read 131usize)).value == 21267647932558653966460912964485513215i128) { panic("shr_assign #452") }
    if !(not((read Wrapping(170141183460469231731687303715884105725i128))).value == (-170141183460469231731687303715884105726i128) && not(Wrapping(170141183460469231731687303715884105725i128)).value == (-170141183460469231731687303715884105726i128)) { panic("not #453") }
    if !(neg((read Wrapping(170141183460469231731687303715884105725i128))).value == (-170141183460469231731687303715884105725i128) && neg(Wrapping(170141183460469231731687303715884105725i128)).value == (-170141183460469231731687303715884105725i128)) { panic("neg #454") }
    if !(neg((read Wrapping(i128.MIN))).value == i128.MIN) { panic("neg #455") }
    if !(add(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == (-9223372036854775804isize)) { panic("add #456") }
    if !(add((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == (-9223372036854775804isize)) { panic("add #457") }
    if !(add(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == (-9223372036854775804isize)) { panic("add #458") }
    if !(add((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == (-9223372036854775804isize)) { panic("add #459") }
    if !(add_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == (-9223372036854775804isize)) { panic("add_assign #460") }
    if !(add_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == (-9223372036854775804isize)) { panic("add_assign #461") }
    if !(add_assign(Wrapping(9223372036854775805isize), 7isize).value == (-9223372036854775804isize)) { panic("add_assign #462") }
    if !(add_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == (-9223372036854775804isize)) { panic("add_assign #463") }
    if !(sub(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775798isize) { panic("sub #464") }
    if !(sub((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 9223372036854775798isize) { panic("sub #465") }
    if !(sub(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775798isize) { panic("sub #466") }
    if !(sub((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 9223372036854775798isize) { panic("sub #467") }
    if !(sub_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775798isize) { panic("sub_assign #468") }
    if !(sub_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775798isize) { panic("sub_assign #469") }
    if !(sub_assign(Wrapping(9223372036854775805isize), 7isize).value == 9223372036854775798isize) { panic("sub_assign #470") }
    if !(sub_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 9223372036854775798isize) { panic("sub_assign #471") }
    if !(mul(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775787isize) { panic("mul #472") }
    if !(mul((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 9223372036854775787isize) { panic("mul #473") }
    if !(mul(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775787isize) { panic("mul #474") }
    if !(mul((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 9223372036854775787isize) { panic("mul #475") }
    if !(mul_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775787isize) { panic("mul_assign #476") }
    if !(mul_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775787isize) { panic("mul_assign #477") }
    if !(mul_assign(Wrapping(9223372036854775805isize), 7isize).value == 9223372036854775787isize) { panic("mul_assign #478") }
    if !(mul_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 9223372036854775787isize) { panic("mul_assign #479") }
    if !(div(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 1317624576693539400isize) { panic("div #480") }
    if !(div((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 1317624576693539400isize) { panic("div #481") }
    if !(div(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 1317624576693539400isize) { panic("div #482") }
    if !(div((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 1317624576693539400isize) { panic("div #483") }
    if !(div_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 1317624576693539400isize) { panic("div_assign #484") }
    if !(div_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 1317624576693539400isize) { panic("div_assign #485") }
    if !(div_assign(Wrapping(9223372036854775805isize), 7isize).value == 1317624576693539400isize) { panic("div_assign #486") }
    if !(div_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 1317624576693539400isize) { panic("div_assign #487") }
    if !(rem(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 5isize) { panic("rem #488") }
    if !(rem((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 5isize) { panic("rem #489") }
    if !(rem(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 5isize) { panic("rem #490") }
    if !(rem((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 5isize) { panic("rem #491") }
    if !(rem_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 5isize) { panic("rem_assign #492") }
    if !(rem_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 5isize) { panic("rem_assign #493") }
    if !(rem_assign(Wrapping(9223372036854775805isize), 7isize).value == 5isize) { panic("rem_assign #494") }
    if !(rem_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 5isize) { panic("rem_assign #495") }
    if !(and(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 5isize) { panic("and #496") }
    if !(and((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 5isize) { panic("and #497") }
    if !(and(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 5isize) { panic("and #498") }
    if !(and((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 5isize) { panic("and #499") }
    if !(and_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 5isize) { panic("and_assign #500") }
    if !(and_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 5isize) { panic("and_assign #501") }
    if !(and_assign(Wrapping(9223372036854775805isize), 7isize).value == 5isize) { panic("and_assign #502") }
    if !(and_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 5isize) { panic("and_assign #503") }
    if !(or(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775807isize) { panic("or #504") }
    if !(or((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 9223372036854775807isize) { panic("or #505") }
    if !(or(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775807isize) { panic("or #506") }
    if !(or((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 9223372036854775807isize) { panic("or #507") }
    if !(or_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775807isize) { panic("or_assign #508") }
    if !(or_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775807isize) { panic("or_assign #509") }
    if !(or_assign(Wrapping(9223372036854775805isize), 7isize).value == 9223372036854775807isize) { panic("or_assign #510") }
    if !(or_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 9223372036854775807isize) { panic("or_assign #511") }
    if !(xor(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775802isize) { panic("xor #512") }
    if !(xor((read Wrapping(9223372036854775805isize)), Wrapping(7isize)).value == 9223372036854775802isize) { panic("xor #513") }
    if !(xor(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775802isize) { panic("xor #514") }
    if !(xor((read Wrapping(9223372036854775805isize)), (read Wrapping(7isize))).value == 9223372036854775802isize) { panic("xor #515") }
    if !(xor_assign(Wrapping(9223372036854775805isize), Wrapping(7isize)).value == 9223372036854775802isize) { panic("xor_assign #516") }
    if !(xor_assign(Wrapping(9223372036854775805isize), (read Wrapping(7isize))).value == 9223372036854775802isize) { panic("xor_assign #517") }
    if !(xor_assign(Wrapping(9223372036854775805isize), 7isize).value == 9223372036854775802isize) { panic("xor_assign #518") }
    if !(xor_assign(Wrapping(9223372036854775805isize), (read 7isize)).value == 9223372036854775802isize) { panic("xor_assign #519") }
    if !(shl(Wrapping(9223372036854775805isize), 3usize).value == (-24isize)) { panic("shl #520") }
    if !(shr(Wrapping(9223372036854775805isize), 3usize).value == 1152921504606846975isize) { panic("shr #521") }
    if !(shl((read Wrapping(9223372036854775805isize)), 3usize).value == (-24isize)) { panic("shl #522") }
    if !(shr((read Wrapping(9223372036854775805isize)), 3usize).value == 1152921504606846975isize) { panic("shr #523") }
    if !(shl(Wrapping(9223372036854775805isize), (read 3usize)).value == (-24isize)) { panic("shl #524") }
    if !(shr(Wrapping(9223372036854775805isize), (read 3usize)).value == 1152921504606846975isize) { panic("shr #525") }
    if !(shl((read Wrapping(9223372036854775805isize)), (read 3usize)).value == (-24isize)) { panic("shl #526") }
    if !(shr((read Wrapping(9223372036854775805isize)), (read 3usize)).value == 1152921504606846975isize) { panic("shr #527") }
    if !(shl_assign(Wrapping(9223372036854775805isize), 3usize).value == (-24isize)) { panic("shl_assign #528") }
    if !(shr_assign(Wrapping(9223372036854775805isize), 3usize).value == 1152921504606846975isize) { panic("shr_assign #529") }
    if !(shl_assign(Wrapping(9223372036854775805isize), (read 3usize)).value == (-24isize)) { panic("shl_assign #530") }
    if !(shr_assign(Wrapping(9223372036854775805isize), (read 3usize)).value == 1152921504606846975isize) { panic("shr_assign #531") }
    if !(shl(Wrapping(9223372036854775805isize), 67usize).value == (-24isize)) { panic("shl #532") }
    if !(shr(Wrapping(9223372036854775805isize), 67usize).value == 1152921504606846975isize) { panic("shr #533") }
    if !(shl((read Wrapping(9223372036854775805isize)), 67usize).value == (-24isize)) { panic("shl #534") }
    if !(shr((read Wrapping(9223372036854775805isize)), 67usize).value == 1152921504606846975isize) { panic("shr #535") }
    if !(shl(Wrapping(9223372036854775805isize), (read 67usize)).value == (-24isize)) { panic("shl #536") }
    if !(shr(Wrapping(9223372036854775805isize), (read 67usize)).value == 1152921504606846975isize) { panic("shr #537") }
    if !(shl((read Wrapping(9223372036854775805isize)), (read 67usize)).value == (-24isize)) { panic("shl #538") }
    if !(shr((read Wrapping(9223372036854775805isize)), (read 67usize)).value == 1152921504606846975isize) { panic("shr #539") }
    if !(shl_assign(Wrapping(9223372036854775805isize), 67usize).value == (-24isize)) { panic("shl_assign #540") }
    if !(shr_assign(Wrapping(9223372036854775805isize), 67usize).value == 1152921504606846975isize) { panic("shr_assign #541") }
    if !(shl_assign(Wrapping(9223372036854775805isize), (read 67usize)).value == (-24isize)) { panic("shl_assign #542") }
    if !(shr_assign(Wrapping(9223372036854775805isize), (read 67usize)).value == 1152921504606846975isize) { panic("shr_assign #543") }
    if !(not((read Wrapping(9223372036854775805isize))).value == (-9223372036854775806isize) && not(Wrapping(9223372036854775805isize)).value == (-9223372036854775806isize)) { panic("not #544") }
    if !(neg((read Wrapping(9223372036854775805isize))).value == (-9223372036854775805isize) && neg(Wrapping(9223372036854775805isize)).value == (-9223372036854775805isize)) { panic("neg #545") }
    if !(neg((read Wrapping(isize.MIN))).value == isize.MIN) { panic("neg #546") }
}

fn main(): i32 {
    group0()
    group1()
    group2()
    group3()
    0
}
