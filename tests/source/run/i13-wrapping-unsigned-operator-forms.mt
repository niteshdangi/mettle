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
fn add_assign<A: AddAssign<B>, B>(take a: A, b: B): A { var x = a; x.add_assign(b); x }
fn sub_assign<A: SubAssign<B>, B>(take a: A, b: B): A { var x = a; x.sub_assign(b); x }
fn mul_assign<A: MulAssign<B>, B>(take a: A, b: B): A { var x = a; x.mul_assign(b); x }
fn div_assign<A: DivAssign<B>, B>(take a: A, b: B): A { var x = a; x.div_assign(b); x }
fn rem_assign<A: RemAssign<B>, B>(take a: A, b: B): A { var x = a; x.rem_assign(b); x }
fn and_assign<A: BitAndAssign<B>, B>(take a: A, b: B): A { var x = a; x.bitand_assign(b); x }
fn or_assign<A: BitOrAssign<B>, B>(take a: A, b: B): A { var x = a; x.bitor_assign(b); x }
fn xor_assign<A: BitXorAssign<B>, B>(take a: A, b: B): A { var x = a; x.bitxor_assign(b); x }
fn shl_assign<A: ShlAssign<B>, B>(take a: A, b: B): A { var x = a; x.shl_assign(b); x }
fn shr_assign<A: ShrAssign<B>, B>(take a: A, b: B): A { var x = a; x.shr_assign(b); x }

fn group0() {
    if !(add(Wrapping(253u8), Wrapping(7u8)).value == 4u8) { panic("add #1") }
    if !(add((read Wrapping(253u8)), Wrapping(7u8)).value == 4u8) { panic("add #2") }
    if !(add(Wrapping(253u8), (read Wrapping(7u8))).value == 4u8) { panic("add #3") }
    if !(add((read Wrapping(253u8)), (read Wrapping(7u8))).value == 4u8) { panic("add #4") }
    if !(add_assign(Wrapping(253u8), Wrapping(7u8)).value == 4u8) { panic("add_assign #5") }
    if !(add_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 4u8) { panic("add_assign #6") }
    if !(add_assign(Wrapping(253u8), 7u8).value == 4u8) { panic("add_assign #7") }
    if !(add_assign(Wrapping(253u8), (read 7u8)).value == 4u8) { panic("add_assign #8") }
    if !(sub(Wrapping(253u8), Wrapping(7u8)).value == 246u8) { panic("sub #9") }
    if !(sub((read Wrapping(253u8)), Wrapping(7u8)).value == 246u8) { panic("sub #10") }
    if !(sub(Wrapping(253u8), (read Wrapping(7u8))).value == 246u8) { panic("sub #11") }
    if !(sub((read Wrapping(253u8)), (read Wrapping(7u8))).value == 246u8) { panic("sub #12") }
    if !(sub_assign(Wrapping(253u8), Wrapping(7u8)).value == 246u8) { panic("sub_assign #13") }
    if !(sub_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 246u8) { panic("sub_assign #14") }
    if !(sub_assign(Wrapping(253u8), 7u8).value == 246u8) { panic("sub_assign #15") }
    if !(sub_assign(Wrapping(253u8), (read 7u8)).value == 246u8) { panic("sub_assign #16") }
    if !(mul(Wrapping(253u8), Wrapping(7u8)).value == 235u8) { panic("mul #17") }
    if !(mul((read Wrapping(253u8)), Wrapping(7u8)).value == 235u8) { panic("mul #18") }
    if !(mul(Wrapping(253u8), (read Wrapping(7u8))).value == 235u8) { panic("mul #19") }
    if !(mul((read Wrapping(253u8)), (read Wrapping(7u8))).value == 235u8) { panic("mul #20") }
    if !(mul_assign(Wrapping(253u8), Wrapping(7u8)).value == 235u8) { panic("mul_assign #21") }
    if !(mul_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 235u8) { panic("mul_assign #22") }
    if !(mul_assign(Wrapping(253u8), 7u8).value == 235u8) { panic("mul_assign #23") }
    if !(mul_assign(Wrapping(253u8), (read 7u8)).value == 235u8) { panic("mul_assign #24") }
    if !(div(Wrapping(253u8), Wrapping(7u8)).value == 36u8) { panic("div #25") }
    if !(div((read Wrapping(253u8)), Wrapping(7u8)).value == 36u8) { panic("div #26") }
    if !(div(Wrapping(253u8), (read Wrapping(7u8))).value == 36u8) { panic("div #27") }
    if !(div((read Wrapping(253u8)), (read Wrapping(7u8))).value == 36u8) { panic("div #28") }
    if !(div_assign(Wrapping(253u8), Wrapping(7u8)).value == 36u8) { panic("div_assign #29") }
    if !(div_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 36u8) { panic("div_assign #30") }
    if !(div_assign(Wrapping(253u8), 7u8).value == 36u8) { panic("div_assign #31") }
    if !(div_assign(Wrapping(253u8), (read 7u8)).value == 36u8) { panic("div_assign #32") }
    if !(rem(Wrapping(253u8), Wrapping(7u8)).value == 1u8) { panic("rem #33") }
    if !(rem((read Wrapping(253u8)), Wrapping(7u8)).value == 1u8) { panic("rem #34") }
    if !(rem(Wrapping(253u8), (read Wrapping(7u8))).value == 1u8) { panic("rem #35") }
    if !(rem((read Wrapping(253u8)), (read Wrapping(7u8))).value == 1u8) { panic("rem #36") }
    if !(rem_assign(Wrapping(253u8), Wrapping(7u8)).value == 1u8) { panic("rem_assign #37") }
    if !(rem_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 1u8) { panic("rem_assign #38") }
    if !(rem_assign(Wrapping(253u8), 7u8).value == 1u8) { panic("rem_assign #39") }
    if !(rem_assign(Wrapping(253u8), (read 7u8)).value == 1u8) { panic("rem_assign #40") }
    if !(and(Wrapping(253u8), Wrapping(7u8)).value == 5u8) { panic("and #41") }
    if !(and((read Wrapping(253u8)), Wrapping(7u8)).value == 5u8) { panic("and #42") }
    if !(and(Wrapping(253u8), (read Wrapping(7u8))).value == 5u8) { panic("and #43") }
    if !(and((read Wrapping(253u8)), (read Wrapping(7u8))).value == 5u8) { panic("and #44") }
    if !(and_assign(Wrapping(253u8), Wrapping(7u8)).value == 5u8) { panic("and_assign #45") }
    if !(and_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 5u8) { panic("and_assign #46") }
    if !(and_assign(Wrapping(253u8), 7u8).value == 5u8) { panic("and_assign #47") }
    if !(and_assign(Wrapping(253u8), (read 7u8)).value == 5u8) { panic("and_assign #48") }
    if !(or(Wrapping(253u8), Wrapping(7u8)).value == 255u8) { panic("or #49") }
    if !(or((read Wrapping(253u8)), Wrapping(7u8)).value == 255u8) { panic("or #50") }
    if !(or(Wrapping(253u8), (read Wrapping(7u8))).value == 255u8) { panic("or #51") }
    if !(or((read Wrapping(253u8)), (read Wrapping(7u8))).value == 255u8) { panic("or #52") }
    if !(or_assign(Wrapping(253u8), Wrapping(7u8)).value == 255u8) { panic("or_assign #53") }
    if !(or_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 255u8) { panic("or_assign #54") }
    if !(or_assign(Wrapping(253u8), 7u8).value == 255u8) { panic("or_assign #55") }
    if !(or_assign(Wrapping(253u8), (read 7u8)).value == 255u8) { panic("or_assign #56") }
    if !(xor(Wrapping(253u8), Wrapping(7u8)).value == 250u8) { panic("xor #57") }
    if !(xor((read Wrapping(253u8)), Wrapping(7u8)).value == 250u8) { panic("xor #58") }
    if !(xor(Wrapping(253u8), (read Wrapping(7u8))).value == 250u8) { panic("xor #59") }
    if !(xor((read Wrapping(253u8)), (read Wrapping(7u8))).value == 250u8) { panic("xor #60") }
    if !(xor_assign(Wrapping(253u8), Wrapping(7u8)).value == 250u8) { panic("xor_assign #61") }
    if !(xor_assign(Wrapping(253u8), (read Wrapping(7u8))).value == 250u8) { panic("xor_assign #62") }
    if !(xor_assign(Wrapping(253u8), 7u8).value == 250u8) { panic("xor_assign #63") }
    if !(xor_assign(Wrapping(253u8), (read 7u8)).value == 250u8) { panic("xor_assign #64") }
    if !(shl(Wrapping(253u8), 3usize).value == 232u8) { panic("shl #65") }
    if !(shr(Wrapping(253u8), 3usize).value == 31u8) { panic("shr #66") }
    if !(shl((read Wrapping(253u8)), 3usize).value == 232u8) { panic("shl #67") }
    if !(shr((read Wrapping(253u8)), 3usize).value == 31u8) { panic("shr #68") }
    if !(shl(Wrapping(253u8), (read 3usize)).value == 232u8) { panic("shl #69") }
    if !(shr(Wrapping(253u8), (read 3usize)).value == 31u8) { panic("shr #70") }
    if !(shl((read Wrapping(253u8)), (read 3usize)).value == 232u8) { panic("shl #71") }
    if !(shr((read Wrapping(253u8)), (read 3usize)).value == 31u8) { panic("shr #72") }
    if !(shl_assign(Wrapping(253u8), 3usize).value == 232u8) { panic("shl_assign #73") }
    if !(shr_assign(Wrapping(253u8), 3usize).value == 31u8) { panic("shr_assign #74") }
    if !(shl_assign(Wrapping(253u8), (read 3usize)).value == 232u8) { panic("shl_assign #75") }
    if !(shr_assign(Wrapping(253u8), (read 3usize)).value == 31u8) { panic("shr_assign #76") }
    if !(shl(Wrapping(253u8), 11usize).value == 232u8) { panic("shl #77") }
    if !(shr(Wrapping(253u8), 11usize).value == 31u8) { panic("shr #78") }
    if !(shl((read Wrapping(253u8)), 11usize).value == 232u8) { panic("shl #79") }
    if !(shr((read Wrapping(253u8)), 11usize).value == 31u8) { panic("shr #80") }
    if !(shl(Wrapping(253u8), (read 11usize)).value == 232u8) { panic("shl #81") }
    if !(shr(Wrapping(253u8), (read 11usize)).value == 31u8) { panic("shr #82") }
    if !(shl((read Wrapping(253u8)), (read 11usize)).value == 232u8) { panic("shl #83") }
    if !(shr((read Wrapping(253u8)), (read 11usize)).value == 31u8) { panic("shr #84") }
    if !(shl_assign(Wrapping(253u8), 11usize).value == 232u8) { panic("shl_assign #85") }
    if !(shr_assign(Wrapping(253u8), 11usize).value == 31u8) { panic("shr_assign #86") }
    if !(shl_assign(Wrapping(253u8), (read 11usize)).value == 232u8) { panic("shl_assign #87") }
    if !(shr_assign(Wrapping(253u8), (read 11usize)).value == 31u8) { panic("shr_assign #88") }
    if !(not((read Wrapping(253u8))).value == 2u8 && not(Wrapping(253u8)).value == 2u8) { panic("not #89") }
    if !(neg((read Wrapping(253u8))).value == 3u8 && neg(Wrapping(253u8)).value == 3u8) { panic("neg #90") }
    if !(add(Wrapping(65533u16), Wrapping(7u16)).value == 4u16) { panic("add #91") }
    if !(add((read Wrapping(65533u16)), Wrapping(7u16)).value == 4u16) { panic("add #92") }
    if !(add(Wrapping(65533u16), (read Wrapping(7u16))).value == 4u16) { panic("add #93") }
    if !(add((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 4u16) { panic("add #94") }
    if !(add_assign(Wrapping(65533u16), Wrapping(7u16)).value == 4u16) { panic("add_assign #95") }
    if !(add_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 4u16) { panic("add_assign #96") }
    if !(add_assign(Wrapping(65533u16), 7u16).value == 4u16) { panic("add_assign #97") }
    if !(add_assign(Wrapping(65533u16), (read 7u16)).value == 4u16) { panic("add_assign #98") }
    if !(sub(Wrapping(65533u16), Wrapping(7u16)).value == 65526u16) { panic("sub #99") }
    if !(sub((read Wrapping(65533u16)), Wrapping(7u16)).value == 65526u16) { panic("sub #100") }
    if !(sub(Wrapping(65533u16), (read Wrapping(7u16))).value == 65526u16) { panic("sub #101") }
    if !(sub((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 65526u16) { panic("sub #102") }
    if !(sub_assign(Wrapping(65533u16), Wrapping(7u16)).value == 65526u16) { panic("sub_assign #103") }
    if !(sub_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 65526u16) { panic("sub_assign #104") }
    if !(sub_assign(Wrapping(65533u16), 7u16).value == 65526u16) { panic("sub_assign #105") }
    if !(sub_assign(Wrapping(65533u16), (read 7u16)).value == 65526u16) { panic("sub_assign #106") }
    if !(mul(Wrapping(65533u16), Wrapping(7u16)).value == 65515u16) { panic("mul #107") }
    if !(mul((read Wrapping(65533u16)), Wrapping(7u16)).value == 65515u16) { panic("mul #108") }
    if !(mul(Wrapping(65533u16), (read Wrapping(7u16))).value == 65515u16) { panic("mul #109") }
    if !(mul((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 65515u16) { panic("mul #110") }
    if !(mul_assign(Wrapping(65533u16), Wrapping(7u16)).value == 65515u16) { panic("mul_assign #111") }
    if !(mul_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 65515u16) { panic("mul_assign #112") }
    if !(mul_assign(Wrapping(65533u16), 7u16).value == 65515u16) { panic("mul_assign #113") }
    if !(mul_assign(Wrapping(65533u16), (read 7u16)).value == 65515u16) { panic("mul_assign #114") }
    if !(div(Wrapping(65533u16), Wrapping(7u16)).value == 9361u16) { panic("div #115") }
    if !(div((read Wrapping(65533u16)), Wrapping(7u16)).value == 9361u16) { panic("div #116") }
    if !(div(Wrapping(65533u16), (read Wrapping(7u16))).value == 9361u16) { panic("div #117") }
    if !(div((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 9361u16) { panic("div #118") }
    if !(div_assign(Wrapping(65533u16), Wrapping(7u16)).value == 9361u16) { panic("div_assign #119") }
    if !(div_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 9361u16) { panic("div_assign #120") }
    if !(div_assign(Wrapping(65533u16), 7u16).value == 9361u16) { panic("div_assign #121") }
    if !(div_assign(Wrapping(65533u16), (read 7u16)).value == 9361u16) { panic("div_assign #122") }
    if !(rem(Wrapping(65533u16), Wrapping(7u16)).value == 6u16) { panic("rem #123") }
    if !(rem((read Wrapping(65533u16)), Wrapping(7u16)).value == 6u16) { panic("rem #124") }
    if !(rem(Wrapping(65533u16), (read Wrapping(7u16))).value == 6u16) { panic("rem #125") }
    if !(rem((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 6u16) { panic("rem #126") }
    if !(rem_assign(Wrapping(65533u16), Wrapping(7u16)).value == 6u16) { panic("rem_assign #127") }
    if !(rem_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 6u16) { panic("rem_assign #128") }
    if !(rem_assign(Wrapping(65533u16), 7u16).value == 6u16) { panic("rem_assign #129") }
    if !(rem_assign(Wrapping(65533u16), (read 7u16)).value == 6u16) { panic("rem_assign #130") }
    if !(and(Wrapping(65533u16), Wrapping(7u16)).value == 5u16) { panic("and #131") }
    if !(and((read Wrapping(65533u16)), Wrapping(7u16)).value == 5u16) { panic("and #132") }
    if !(and(Wrapping(65533u16), (read Wrapping(7u16))).value == 5u16) { panic("and #133") }
    if !(and((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 5u16) { panic("and #134") }
    if !(and_assign(Wrapping(65533u16), Wrapping(7u16)).value == 5u16) { panic("and_assign #135") }
    if !(and_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 5u16) { panic("and_assign #136") }
    if !(and_assign(Wrapping(65533u16), 7u16).value == 5u16) { panic("and_assign #137") }
    if !(and_assign(Wrapping(65533u16), (read 7u16)).value == 5u16) { panic("and_assign #138") }
    if !(or(Wrapping(65533u16), Wrapping(7u16)).value == 65535u16) { panic("or #139") }
    if !(or((read Wrapping(65533u16)), Wrapping(7u16)).value == 65535u16) { panic("or #140") }
    if !(or(Wrapping(65533u16), (read Wrapping(7u16))).value == 65535u16) { panic("or #141") }
    if !(or((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 65535u16) { panic("or #142") }
    if !(or_assign(Wrapping(65533u16), Wrapping(7u16)).value == 65535u16) { panic("or_assign #143") }
    if !(or_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 65535u16) { panic("or_assign #144") }
    if !(or_assign(Wrapping(65533u16), 7u16).value == 65535u16) { panic("or_assign #145") }
    if !(or_assign(Wrapping(65533u16), (read 7u16)).value == 65535u16) { panic("or_assign #146") }
    if !(xor(Wrapping(65533u16), Wrapping(7u16)).value == 65530u16) { panic("xor #147") }
    if !(xor((read Wrapping(65533u16)), Wrapping(7u16)).value == 65530u16) { panic("xor #148") }
    if !(xor(Wrapping(65533u16), (read Wrapping(7u16))).value == 65530u16) { panic("xor #149") }
    if !(xor((read Wrapping(65533u16)), (read Wrapping(7u16))).value == 65530u16) { panic("xor #150") }
}

fn group1() {
    if !(xor_assign(Wrapping(65533u16), Wrapping(7u16)).value == 65530u16) { panic("xor_assign #151") }
    if !(xor_assign(Wrapping(65533u16), (read Wrapping(7u16))).value == 65530u16) { panic("xor_assign #152") }
    if !(xor_assign(Wrapping(65533u16), 7u16).value == 65530u16) { panic("xor_assign #153") }
    if !(xor_assign(Wrapping(65533u16), (read 7u16)).value == 65530u16) { panic("xor_assign #154") }
    if !(shl(Wrapping(65533u16), 3usize).value == 65512u16) { panic("shl #155") }
    if !(shr(Wrapping(65533u16), 3usize).value == 8191u16) { panic("shr #156") }
    if !(shl((read Wrapping(65533u16)), 3usize).value == 65512u16) { panic("shl #157") }
    if !(shr((read Wrapping(65533u16)), 3usize).value == 8191u16) { panic("shr #158") }
    if !(shl(Wrapping(65533u16), (read 3usize)).value == 65512u16) { panic("shl #159") }
    if !(shr(Wrapping(65533u16), (read 3usize)).value == 8191u16) { panic("shr #160") }
    if !(shl((read Wrapping(65533u16)), (read 3usize)).value == 65512u16) { panic("shl #161") }
    if !(shr((read Wrapping(65533u16)), (read 3usize)).value == 8191u16) { panic("shr #162") }
    if !(shl_assign(Wrapping(65533u16), 3usize).value == 65512u16) { panic("shl_assign #163") }
    if !(shr_assign(Wrapping(65533u16), 3usize).value == 8191u16) { panic("shr_assign #164") }
    if !(shl_assign(Wrapping(65533u16), (read 3usize)).value == 65512u16) { panic("shl_assign #165") }
    if !(shr_assign(Wrapping(65533u16), (read 3usize)).value == 8191u16) { panic("shr_assign #166") }
    if !(shl(Wrapping(65533u16), 19usize).value == 65512u16) { panic("shl #167") }
    if !(shr(Wrapping(65533u16), 19usize).value == 8191u16) { panic("shr #168") }
    if !(shl((read Wrapping(65533u16)), 19usize).value == 65512u16) { panic("shl #169") }
    if !(shr((read Wrapping(65533u16)), 19usize).value == 8191u16) { panic("shr #170") }
    if !(shl(Wrapping(65533u16), (read 19usize)).value == 65512u16) { panic("shl #171") }
    if !(shr(Wrapping(65533u16), (read 19usize)).value == 8191u16) { panic("shr #172") }
    if !(shl((read Wrapping(65533u16)), (read 19usize)).value == 65512u16) { panic("shl #173") }
    if !(shr((read Wrapping(65533u16)), (read 19usize)).value == 8191u16) { panic("shr #174") }
    if !(shl_assign(Wrapping(65533u16), 19usize).value == 65512u16) { panic("shl_assign #175") }
    if !(shr_assign(Wrapping(65533u16), 19usize).value == 8191u16) { panic("shr_assign #176") }
    if !(shl_assign(Wrapping(65533u16), (read 19usize)).value == 65512u16) { panic("shl_assign #177") }
    if !(shr_assign(Wrapping(65533u16), (read 19usize)).value == 8191u16) { panic("shr_assign #178") }
    if !(not((read Wrapping(65533u16))).value == 2u16 && not(Wrapping(65533u16)).value == 2u16) { panic("not #179") }
    if !(neg((read Wrapping(65533u16))).value == 3u16 && neg(Wrapping(65533u16)).value == 3u16) { panic("neg #180") }
    if !(add(Wrapping(4294967293u32), Wrapping(7u32)).value == 4u32) { panic("add #181") }
    if !(add((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 4u32) { panic("add #182") }
    if !(add(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4u32) { panic("add #183") }
    if !(add((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 4u32) { panic("add #184") }
    if !(add_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 4u32) { panic("add_assign #185") }
    if !(add_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4u32) { panic("add_assign #186") }
    if !(add_assign(Wrapping(4294967293u32), 7u32).value == 4u32) { panic("add_assign #187") }
    if !(add_assign(Wrapping(4294967293u32), (read 7u32)).value == 4u32) { panic("add_assign #188") }
    if !(sub(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967286u32) { panic("sub #189") }
    if !(sub((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 4294967286u32) { panic("sub #190") }
    if !(sub(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967286u32) { panic("sub #191") }
    if !(sub((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 4294967286u32) { panic("sub #192") }
    if !(sub_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967286u32) { panic("sub_assign #193") }
    if !(sub_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967286u32) { panic("sub_assign #194") }
    if !(sub_assign(Wrapping(4294967293u32), 7u32).value == 4294967286u32) { panic("sub_assign #195") }
    if !(sub_assign(Wrapping(4294967293u32), (read 7u32)).value == 4294967286u32) { panic("sub_assign #196") }
    if !(mul(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967275u32) { panic("mul #197") }
    if !(mul((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 4294967275u32) { panic("mul #198") }
    if !(mul(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967275u32) { panic("mul #199") }
    if !(mul((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 4294967275u32) { panic("mul #200") }
    if !(mul_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967275u32) { panic("mul_assign #201") }
    if !(mul_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967275u32) { panic("mul_assign #202") }
    if !(mul_assign(Wrapping(4294967293u32), 7u32).value == 4294967275u32) { panic("mul_assign #203") }
    if !(mul_assign(Wrapping(4294967293u32), (read 7u32)).value == 4294967275u32) { panic("mul_assign #204") }
    if !(div(Wrapping(4294967293u32), Wrapping(7u32)).value == 613566756u32) { panic("div #205") }
    if !(div((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 613566756u32) { panic("div #206") }
    if !(div(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 613566756u32) { panic("div #207") }
    if !(div((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 613566756u32) { panic("div #208") }
    if !(div_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 613566756u32) { panic("div_assign #209") }
    if !(div_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 613566756u32) { panic("div_assign #210") }
    if !(div_assign(Wrapping(4294967293u32), 7u32).value == 613566756u32) { panic("div_assign #211") }
    if !(div_assign(Wrapping(4294967293u32), (read 7u32)).value == 613566756u32) { panic("div_assign #212") }
    if !(rem(Wrapping(4294967293u32), Wrapping(7u32)).value == 1u32) { panic("rem #213") }
    if !(rem((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 1u32) { panic("rem #214") }
    if !(rem(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 1u32) { panic("rem #215") }
    if !(rem((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 1u32) { panic("rem #216") }
    if !(rem_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 1u32) { panic("rem_assign #217") }
    if !(rem_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 1u32) { panic("rem_assign #218") }
    if !(rem_assign(Wrapping(4294967293u32), 7u32).value == 1u32) { panic("rem_assign #219") }
    if !(rem_assign(Wrapping(4294967293u32), (read 7u32)).value == 1u32) { panic("rem_assign #220") }
    if !(and(Wrapping(4294967293u32), Wrapping(7u32)).value == 5u32) { panic("and #221") }
    if !(and((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 5u32) { panic("and #222") }
    if !(and(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 5u32) { panic("and #223") }
    if !(and((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 5u32) { panic("and #224") }
    if !(and_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 5u32) { panic("and_assign #225") }
    if !(and_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 5u32) { panic("and_assign #226") }
    if !(and_assign(Wrapping(4294967293u32), 7u32).value == 5u32) { panic("and_assign #227") }
    if !(and_assign(Wrapping(4294967293u32), (read 7u32)).value == 5u32) { panic("and_assign #228") }
    if !(or(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967295u32) { panic("or #229") }
    if !(or((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 4294967295u32) { panic("or #230") }
    if !(or(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967295u32) { panic("or #231") }
    if !(or((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 4294967295u32) { panic("or #232") }
    if !(or_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967295u32) { panic("or_assign #233") }
    if !(or_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967295u32) { panic("or_assign #234") }
    if !(or_assign(Wrapping(4294967293u32), 7u32).value == 4294967295u32) { panic("or_assign #235") }
    if !(or_assign(Wrapping(4294967293u32), (read 7u32)).value == 4294967295u32) { panic("or_assign #236") }
    if !(xor(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967290u32) { panic("xor #237") }
    if !(xor((read Wrapping(4294967293u32)), Wrapping(7u32)).value == 4294967290u32) { panic("xor #238") }
    if !(xor(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967290u32) { panic("xor #239") }
    if !(xor((read Wrapping(4294967293u32)), (read Wrapping(7u32))).value == 4294967290u32) { panic("xor #240") }
    if !(xor_assign(Wrapping(4294967293u32), Wrapping(7u32)).value == 4294967290u32) { panic("xor_assign #241") }
    if !(xor_assign(Wrapping(4294967293u32), (read Wrapping(7u32))).value == 4294967290u32) { panic("xor_assign #242") }
    if !(xor_assign(Wrapping(4294967293u32), 7u32).value == 4294967290u32) { panic("xor_assign #243") }
    if !(xor_assign(Wrapping(4294967293u32), (read 7u32)).value == 4294967290u32) { panic("xor_assign #244") }
    if !(shl(Wrapping(4294967293u32), 3usize).value == 4294967272u32) { panic("shl #245") }
    if !(shr(Wrapping(4294967293u32), 3usize).value == 536870911u32) { panic("shr #246") }
    if !(shl((read Wrapping(4294967293u32)), 3usize).value == 4294967272u32) { panic("shl #247") }
    if !(shr((read Wrapping(4294967293u32)), 3usize).value == 536870911u32) { panic("shr #248") }
    if !(shl(Wrapping(4294967293u32), (read 3usize)).value == 4294967272u32) { panic("shl #249") }
    if !(shr(Wrapping(4294967293u32), (read 3usize)).value == 536870911u32) { panic("shr #250") }
    if !(shl((read Wrapping(4294967293u32)), (read 3usize)).value == 4294967272u32) { panic("shl #251") }
    if !(shr((read Wrapping(4294967293u32)), (read 3usize)).value == 536870911u32) { panic("shr #252") }
    if !(shl_assign(Wrapping(4294967293u32), 3usize).value == 4294967272u32) { panic("shl_assign #253") }
    if !(shr_assign(Wrapping(4294967293u32), 3usize).value == 536870911u32) { panic("shr_assign #254") }
    if !(shl_assign(Wrapping(4294967293u32), (read 3usize)).value == 4294967272u32) { panic("shl_assign #255") }
    if !(shr_assign(Wrapping(4294967293u32), (read 3usize)).value == 536870911u32) { panic("shr_assign #256") }
    if !(shl(Wrapping(4294967293u32), 35usize).value == 4294967272u32) { panic("shl #257") }
    if !(shr(Wrapping(4294967293u32), 35usize).value == 536870911u32) { panic("shr #258") }
    if !(shl((read Wrapping(4294967293u32)), 35usize).value == 4294967272u32) { panic("shl #259") }
    if !(shr((read Wrapping(4294967293u32)), 35usize).value == 536870911u32) { panic("shr #260") }
    if !(shl(Wrapping(4294967293u32), (read 35usize)).value == 4294967272u32) { panic("shl #261") }
    if !(shr(Wrapping(4294967293u32), (read 35usize)).value == 536870911u32) { panic("shr #262") }
    if !(shl((read Wrapping(4294967293u32)), (read 35usize)).value == 4294967272u32) { panic("shl #263") }
    if !(shr((read Wrapping(4294967293u32)), (read 35usize)).value == 536870911u32) { panic("shr #264") }
    if !(shl_assign(Wrapping(4294967293u32), 35usize).value == 4294967272u32) { panic("shl_assign #265") }
    if !(shr_assign(Wrapping(4294967293u32), 35usize).value == 536870911u32) { panic("shr_assign #266") }
    if !(shl_assign(Wrapping(4294967293u32), (read 35usize)).value == 4294967272u32) { panic("shl_assign #267") }
    if !(shr_assign(Wrapping(4294967293u32), (read 35usize)).value == 536870911u32) { panic("shr_assign #268") }
    if !(not((read Wrapping(4294967293u32))).value == 2u32 && not(Wrapping(4294967293u32)).value == 2u32) { panic("not #269") }
    if !(neg((read Wrapping(4294967293u32))).value == 3u32 && neg(Wrapping(4294967293u32)).value == 3u32) { panic("neg #270") }
    if !(add(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 4u64) { panic("add #271") }
    if !(add((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 4u64) { panic("add #272") }
    if !(add(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 4u64) { panic("add #273") }
    if !(add((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 4u64) { panic("add #274") }
    if !(add_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 4u64) { panic("add_assign #275") }
    if !(add_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 4u64) { panic("add_assign #276") }
    if !(add_assign(Wrapping(18446744073709551613u64), 7u64).value == 4u64) { panic("add_assign #277") }
    if !(add_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 4u64) { panic("add_assign #278") }
    if !(sub(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551606u64) { panic("sub #279") }
    if !(sub((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 18446744073709551606u64) { panic("sub #280") }
    if !(sub(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551606u64) { panic("sub #281") }
    if !(sub((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 18446744073709551606u64) { panic("sub #282") }
    if !(sub_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551606u64) { panic("sub_assign #283") }
    if !(sub_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551606u64) { panic("sub_assign #284") }
    if !(sub_assign(Wrapping(18446744073709551613u64), 7u64).value == 18446744073709551606u64) { panic("sub_assign #285") }
    if !(sub_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 18446744073709551606u64) { panic("sub_assign #286") }
    if !(mul(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551595u64) { panic("mul #287") }
    if !(mul((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 18446744073709551595u64) { panic("mul #288") }
    if !(mul(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551595u64) { panic("mul #289") }
    if !(mul((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 18446744073709551595u64) { panic("mul #290") }
    if !(mul_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551595u64) { panic("mul_assign #291") }
    if !(mul_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551595u64) { panic("mul_assign #292") }
    if !(mul_assign(Wrapping(18446744073709551613u64), 7u64).value == 18446744073709551595u64) { panic("mul_assign #293") }
    if !(mul_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 18446744073709551595u64) { panic("mul_assign #294") }
    if !(div(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 2635249153387078801u64) { panic("div #295") }
    if !(div((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 2635249153387078801u64) { panic("div #296") }
    if !(div(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 2635249153387078801u64) { panic("div #297") }
    if !(div((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 2635249153387078801u64) { panic("div #298") }
    if !(div_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 2635249153387078801u64) { panic("div_assign #299") }
    if !(div_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 2635249153387078801u64) { panic("div_assign #300") }
}

fn group2() {
    if !(div_assign(Wrapping(18446744073709551613u64), 7u64).value == 2635249153387078801u64) { panic("div_assign #301") }
    if !(div_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 2635249153387078801u64) { panic("div_assign #302") }
    if !(rem(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 6u64) { panic("rem #303") }
    if !(rem((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 6u64) { panic("rem #304") }
    if !(rem(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 6u64) { panic("rem #305") }
    if !(rem((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 6u64) { panic("rem #306") }
    if !(rem_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 6u64) { panic("rem_assign #307") }
    if !(rem_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 6u64) { panic("rem_assign #308") }
    if !(rem_assign(Wrapping(18446744073709551613u64), 7u64).value == 6u64) { panic("rem_assign #309") }
    if !(rem_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 6u64) { panic("rem_assign #310") }
    if !(and(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 5u64) { panic("and #311") }
    if !(and((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 5u64) { panic("and #312") }
    if !(and(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 5u64) { panic("and #313") }
    if !(and((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 5u64) { panic("and #314") }
    if !(and_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 5u64) { panic("and_assign #315") }
    if !(and_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 5u64) { panic("and_assign #316") }
    if !(and_assign(Wrapping(18446744073709551613u64), 7u64).value == 5u64) { panic("and_assign #317") }
    if !(and_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 5u64) { panic("and_assign #318") }
    if !(or(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551615u64) { panic("or #319") }
    if !(or((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 18446744073709551615u64) { panic("or #320") }
    if !(or(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551615u64) { panic("or #321") }
    if !(or((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 18446744073709551615u64) { panic("or #322") }
    if !(or_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551615u64) { panic("or_assign #323") }
    if !(or_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551615u64) { panic("or_assign #324") }
    if !(or_assign(Wrapping(18446744073709551613u64), 7u64).value == 18446744073709551615u64) { panic("or_assign #325") }
    if !(or_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 18446744073709551615u64) { panic("or_assign #326") }
    if !(xor(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551610u64) { panic("xor #327") }
    if !(xor((read Wrapping(18446744073709551613u64)), Wrapping(7u64)).value == 18446744073709551610u64) { panic("xor #328") }
    if !(xor(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551610u64) { panic("xor #329") }
    if !(xor((read Wrapping(18446744073709551613u64)), (read Wrapping(7u64))).value == 18446744073709551610u64) { panic("xor #330") }
    if !(xor_assign(Wrapping(18446744073709551613u64), Wrapping(7u64)).value == 18446744073709551610u64) { panic("xor_assign #331") }
    if !(xor_assign(Wrapping(18446744073709551613u64), (read Wrapping(7u64))).value == 18446744073709551610u64) { panic("xor_assign #332") }
    if !(xor_assign(Wrapping(18446744073709551613u64), 7u64).value == 18446744073709551610u64) { panic("xor_assign #333") }
    if !(xor_assign(Wrapping(18446744073709551613u64), (read 7u64)).value == 18446744073709551610u64) { panic("xor_assign #334") }
    if !(shl(Wrapping(18446744073709551613u64), 3usize).value == 18446744073709551592u64) { panic("shl #335") }
    if !(shr(Wrapping(18446744073709551613u64), 3usize).value == 2305843009213693951u64) { panic("shr #336") }
    if !(shl((read Wrapping(18446744073709551613u64)), 3usize).value == 18446744073709551592u64) { panic("shl #337") }
    if !(shr((read Wrapping(18446744073709551613u64)), 3usize).value == 2305843009213693951u64) { panic("shr #338") }
    if !(shl(Wrapping(18446744073709551613u64), (read 3usize)).value == 18446744073709551592u64) { panic("shl #339") }
    if !(shr(Wrapping(18446744073709551613u64), (read 3usize)).value == 2305843009213693951u64) { panic("shr #340") }
    if !(shl((read Wrapping(18446744073709551613u64)), (read 3usize)).value == 18446744073709551592u64) { panic("shl #341") }
    if !(shr((read Wrapping(18446744073709551613u64)), (read 3usize)).value == 2305843009213693951u64) { panic("shr #342") }
    if !(shl_assign(Wrapping(18446744073709551613u64), 3usize).value == 18446744073709551592u64) { panic("shl_assign #343") }
    if !(shr_assign(Wrapping(18446744073709551613u64), 3usize).value == 2305843009213693951u64) { panic("shr_assign #344") }
    if !(shl_assign(Wrapping(18446744073709551613u64), (read 3usize)).value == 18446744073709551592u64) { panic("shl_assign #345") }
    if !(shr_assign(Wrapping(18446744073709551613u64), (read 3usize)).value == 2305843009213693951u64) { panic("shr_assign #346") }
    if !(shl(Wrapping(18446744073709551613u64), 67usize).value == 18446744073709551592u64) { panic("shl #347") }
    if !(shr(Wrapping(18446744073709551613u64), 67usize).value == 2305843009213693951u64) { panic("shr #348") }
    if !(shl((read Wrapping(18446744073709551613u64)), 67usize).value == 18446744073709551592u64) { panic("shl #349") }
    if !(shr((read Wrapping(18446744073709551613u64)), 67usize).value == 2305843009213693951u64) { panic("shr #350") }
    if !(shl(Wrapping(18446744073709551613u64), (read 67usize)).value == 18446744073709551592u64) { panic("shl #351") }
    if !(shr(Wrapping(18446744073709551613u64), (read 67usize)).value == 2305843009213693951u64) { panic("shr #352") }
    if !(shl((read Wrapping(18446744073709551613u64)), (read 67usize)).value == 18446744073709551592u64) { panic("shl #353") }
    if !(shr((read Wrapping(18446744073709551613u64)), (read 67usize)).value == 2305843009213693951u64) { panic("shr #354") }
    if !(shl_assign(Wrapping(18446744073709551613u64), 67usize).value == 18446744073709551592u64) { panic("shl_assign #355") }
    if !(shr_assign(Wrapping(18446744073709551613u64), 67usize).value == 2305843009213693951u64) { panic("shr_assign #356") }
    if !(shl_assign(Wrapping(18446744073709551613u64), (read 67usize)).value == 18446744073709551592u64) { panic("shl_assign #357") }
    if !(shr_assign(Wrapping(18446744073709551613u64), (read 67usize)).value == 2305843009213693951u64) { panic("shr_assign #358") }
    if !(not((read Wrapping(18446744073709551613u64))).value == 2u64 && not(Wrapping(18446744073709551613u64)).value == 2u64) { panic("not #359") }
    if !(neg((read Wrapping(18446744073709551613u64))).value == 3u64 && neg(Wrapping(18446744073709551613u64)).value == 3u64) { panic("neg #360") }
    if !(add(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 4u128) { panic("add #361") }
    if !(add((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 4u128) { panic("add #362") }
    if !(add(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 4u128) { panic("add #363") }
    if !(add((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 4u128) { panic("add #364") }
    if !(add_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 4u128) { panic("add_assign #365") }
    if !(add_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 4u128) { panic("add_assign #366") }
    if !(add_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 4u128) { panic("add_assign #367") }
    if !(add_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 4u128) { panic("add_assign #368") }
    if !(sub(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211446u128) { panic("sub #369") }
    if !(sub((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 340282366920938463463374607431768211446u128) { panic("sub #370") }
    if !(sub(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211446u128) { panic("sub #371") }
    if !(sub((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 340282366920938463463374607431768211446u128) { panic("sub #372") }
    if !(sub_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211446u128) { panic("sub_assign #373") }
    if !(sub_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211446u128) { panic("sub_assign #374") }
    if !(sub_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 340282366920938463463374607431768211446u128) { panic("sub_assign #375") }
    if !(sub_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 340282366920938463463374607431768211446u128) { panic("sub_assign #376") }
    if !(mul(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211435u128) { panic("mul #377") }
    if !(mul((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 340282366920938463463374607431768211435u128) { panic("mul #378") }
    if !(mul(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211435u128) { panic("mul #379") }
    if !(mul((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 340282366920938463463374607431768211435u128) { panic("mul #380") }
    if !(mul_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211435u128) { panic("mul_assign #381") }
    if !(mul_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211435u128) { panic("mul_assign #382") }
    if !(mul_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 340282366920938463463374607431768211435u128) { panic("mul_assign #383") }
    if !(mul_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 340282366920938463463374607431768211435u128) { panic("mul_assign #384") }
    if !(div(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 48611766702991209066196372490252601636u128) { panic("div #385") }
    if !(div((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 48611766702991209066196372490252601636u128) { panic("div #386") }
    if !(div(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 48611766702991209066196372490252601636u128) { panic("div #387") }
    if !(div((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 48611766702991209066196372490252601636u128) { panic("div #388") }
    if !(div_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 48611766702991209066196372490252601636u128) { panic("div_assign #389") }
    if !(div_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 48611766702991209066196372490252601636u128) { panic("div_assign #390") }
    if !(div_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 48611766702991209066196372490252601636u128) { panic("div_assign #391") }
    if !(div_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 48611766702991209066196372490252601636u128) { panic("div_assign #392") }
    if !(rem(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 1u128) { panic("rem #393") }
    if !(rem((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 1u128) { panic("rem #394") }
    if !(rem(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 1u128) { panic("rem #395") }
    if !(rem((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 1u128) { panic("rem #396") }
    if !(rem_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 1u128) { panic("rem_assign #397") }
    if !(rem_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 1u128) { panic("rem_assign #398") }
    if !(rem_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 1u128) { panic("rem_assign #399") }
    if !(rem_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 1u128) { panic("rem_assign #400") }
    if !(and(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 5u128) { panic("and #401") }
    if !(and((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 5u128) { panic("and #402") }
    if !(and(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 5u128) { panic("and #403") }
    if !(and((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 5u128) { panic("and #404") }
    if !(and_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 5u128) { panic("and_assign #405") }
    if !(and_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 5u128) { panic("and_assign #406") }
    if !(and_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 5u128) { panic("and_assign #407") }
    if !(and_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 5u128) { panic("and_assign #408") }
    if !(or(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211455u128) { panic("or #409") }
    if !(or((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 340282366920938463463374607431768211455u128) { panic("or #410") }
    if !(or(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211455u128) { panic("or #411") }
    if !(or((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 340282366920938463463374607431768211455u128) { panic("or #412") }
    if !(or_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211455u128) { panic("or_assign #413") }
    if !(or_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211455u128) { panic("or_assign #414") }
    if !(or_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 340282366920938463463374607431768211455u128) { panic("or_assign #415") }
    if !(or_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 340282366920938463463374607431768211455u128) { panic("or_assign #416") }
    if !(xor(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211450u128) { panic("xor #417") }
    if !(xor((read Wrapping(340282366920938463463374607431768211453u128)), Wrapping(7u128)).value == 340282366920938463463374607431768211450u128) { panic("xor #418") }
    if !(xor(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211450u128) { panic("xor #419") }
    if !(xor((read Wrapping(340282366920938463463374607431768211453u128)), (read Wrapping(7u128))).value == 340282366920938463463374607431768211450u128) { panic("xor #420") }
    if !(xor_assign(Wrapping(340282366920938463463374607431768211453u128), Wrapping(7u128)).value == 340282366920938463463374607431768211450u128) { panic("xor_assign #421") }
    if !(xor_assign(Wrapping(340282366920938463463374607431768211453u128), (read Wrapping(7u128))).value == 340282366920938463463374607431768211450u128) { panic("xor_assign #422") }
    if !(xor_assign(Wrapping(340282366920938463463374607431768211453u128), 7u128).value == 340282366920938463463374607431768211450u128) { panic("xor_assign #423") }
    if !(xor_assign(Wrapping(340282366920938463463374607431768211453u128), (read 7u128)).value == 340282366920938463463374607431768211450u128) { panic("xor_assign #424") }
    if !(shl(Wrapping(340282366920938463463374607431768211453u128), 3usize).value == 340282366920938463463374607431768211432u128) { panic("shl #425") }
    if !(shr(Wrapping(340282366920938463463374607431768211453u128), 3usize).value == 42535295865117307932921825928971026431u128) { panic("shr #426") }
    if !(shl((read Wrapping(340282366920938463463374607431768211453u128)), 3usize).value == 340282366920938463463374607431768211432u128) { panic("shl #427") }
    if !(shr((read Wrapping(340282366920938463463374607431768211453u128)), 3usize).value == 42535295865117307932921825928971026431u128) { panic("shr #428") }
    if !(shl(Wrapping(340282366920938463463374607431768211453u128), (read 3usize)).value == 340282366920938463463374607431768211432u128) { panic("shl #429") }
    if !(shr(Wrapping(340282366920938463463374607431768211453u128), (read 3usize)).value == 42535295865117307932921825928971026431u128) { panic("shr #430") }
    if !(shl((read Wrapping(340282366920938463463374607431768211453u128)), (read 3usize)).value == 340282366920938463463374607431768211432u128) { panic("shl #431") }
    if !(shr((read Wrapping(340282366920938463463374607431768211453u128)), (read 3usize)).value == 42535295865117307932921825928971026431u128) { panic("shr #432") }
    if !(shl_assign(Wrapping(340282366920938463463374607431768211453u128), 3usize).value == 340282366920938463463374607431768211432u128) { panic("shl_assign #433") }
    if !(shr_assign(Wrapping(340282366920938463463374607431768211453u128), 3usize).value == 42535295865117307932921825928971026431u128) { panic("shr_assign #434") }
    if !(shl_assign(Wrapping(340282366920938463463374607431768211453u128), (read 3usize)).value == 340282366920938463463374607431768211432u128) { panic("shl_assign #435") }
    if !(shr_assign(Wrapping(340282366920938463463374607431768211453u128), (read 3usize)).value == 42535295865117307932921825928971026431u128) { panic("shr_assign #436") }
    if !(shl(Wrapping(340282366920938463463374607431768211453u128), 131usize).value == 340282366920938463463374607431768211432u128) { panic("shl #437") }
    if !(shr(Wrapping(340282366920938463463374607431768211453u128), 131usize).value == 42535295865117307932921825928971026431u128) { panic("shr #438") }
    if !(shl((read Wrapping(340282366920938463463374607431768211453u128)), 131usize).value == 340282366920938463463374607431768211432u128) { panic("shl #439") }
    if !(shr((read Wrapping(340282366920938463463374607431768211453u128)), 131usize).value == 42535295865117307932921825928971026431u128) { panic("shr #440") }
    if !(shl(Wrapping(340282366920938463463374607431768211453u128), (read 131usize)).value == 340282366920938463463374607431768211432u128) { panic("shl #441") }
    if !(shr(Wrapping(340282366920938463463374607431768211453u128), (read 131usize)).value == 42535295865117307932921825928971026431u128) { panic("shr #442") }
    if !(shl((read Wrapping(340282366920938463463374607431768211453u128)), (read 131usize)).value == 340282366920938463463374607431768211432u128) { panic("shl #443") }
    if !(shr((read Wrapping(340282366920938463463374607431768211453u128)), (read 131usize)).value == 42535295865117307932921825928971026431u128) { panic("shr #444") }
    if !(shl_assign(Wrapping(340282366920938463463374607431768211453u128), 131usize).value == 340282366920938463463374607431768211432u128) { panic("shl_assign #445") }
    if !(shr_assign(Wrapping(340282366920938463463374607431768211453u128), 131usize).value == 42535295865117307932921825928971026431u128) { panic("shr_assign #446") }
    if !(shl_assign(Wrapping(340282366920938463463374607431768211453u128), (read 131usize)).value == 340282366920938463463374607431768211432u128) { panic("shl_assign #447") }
    if !(shr_assign(Wrapping(340282366920938463463374607431768211453u128), (read 131usize)).value == 42535295865117307932921825928971026431u128) { panic("shr_assign #448") }
    if !(not((read Wrapping(340282366920938463463374607431768211453u128))).value == 2u128 && not(Wrapping(340282366920938463463374607431768211453u128)).value == 2u128) { panic("not #449") }
    if !(neg((read Wrapping(340282366920938463463374607431768211453u128))).value == 3u128 && neg(Wrapping(340282366920938463463374607431768211453u128)).value == 3u128) { panic("neg #450") }
}

fn group3() {
    if !(add(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 4usize) { panic("add #451") }
    if !(add((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 4usize) { panic("add #452") }
    if !(add(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 4usize) { panic("add #453") }
    if !(add((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 4usize) { panic("add #454") }
    if !(add_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 4usize) { panic("add_assign #455") }
    if !(add_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 4usize) { panic("add_assign #456") }
    if !(add_assign(Wrapping(18446744073709551613usize), 7usize).value == 4usize) { panic("add_assign #457") }
    if !(add_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 4usize) { panic("add_assign #458") }
    if !(sub(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551606usize) { panic("sub #459") }
    if !(sub((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 18446744073709551606usize) { panic("sub #460") }
    if !(sub(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551606usize) { panic("sub #461") }
    if !(sub((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 18446744073709551606usize) { panic("sub #462") }
    if !(sub_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551606usize) { panic("sub_assign #463") }
    if !(sub_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551606usize) { panic("sub_assign #464") }
    if !(sub_assign(Wrapping(18446744073709551613usize), 7usize).value == 18446744073709551606usize) { panic("sub_assign #465") }
    if !(sub_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 18446744073709551606usize) { panic("sub_assign #466") }
    if !(mul(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551595usize) { panic("mul #467") }
    if !(mul((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 18446744073709551595usize) { panic("mul #468") }
    if !(mul(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551595usize) { panic("mul #469") }
    if !(mul((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 18446744073709551595usize) { panic("mul #470") }
    if !(mul_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551595usize) { panic("mul_assign #471") }
    if !(mul_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551595usize) { panic("mul_assign #472") }
    if !(mul_assign(Wrapping(18446744073709551613usize), 7usize).value == 18446744073709551595usize) { panic("mul_assign #473") }
    if !(mul_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 18446744073709551595usize) { panic("mul_assign #474") }
    if !(div(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 2635249153387078801usize) { panic("div #475") }
    if !(div((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 2635249153387078801usize) { panic("div #476") }
    if !(div(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 2635249153387078801usize) { panic("div #477") }
    if !(div((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 2635249153387078801usize) { panic("div #478") }
    if !(div_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 2635249153387078801usize) { panic("div_assign #479") }
    if !(div_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 2635249153387078801usize) { panic("div_assign #480") }
    if !(div_assign(Wrapping(18446744073709551613usize), 7usize).value == 2635249153387078801usize) { panic("div_assign #481") }
    if !(div_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 2635249153387078801usize) { panic("div_assign #482") }
    if !(rem(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 6usize) { panic("rem #483") }
    if !(rem((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 6usize) { panic("rem #484") }
    if !(rem(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 6usize) { panic("rem #485") }
    if !(rem((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 6usize) { panic("rem #486") }
    if !(rem_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 6usize) { panic("rem_assign #487") }
    if !(rem_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 6usize) { panic("rem_assign #488") }
    if !(rem_assign(Wrapping(18446744073709551613usize), 7usize).value == 6usize) { panic("rem_assign #489") }
    if !(rem_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 6usize) { panic("rem_assign #490") }
    if !(and(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 5usize) { panic("and #491") }
    if !(and((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 5usize) { panic("and #492") }
    if !(and(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 5usize) { panic("and #493") }
    if !(and((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 5usize) { panic("and #494") }
    if !(and_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 5usize) { panic("and_assign #495") }
    if !(and_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 5usize) { panic("and_assign #496") }
    if !(and_assign(Wrapping(18446744073709551613usize), 7usize).value == 5usize) { panic("and_assign #497") }
    if !(and_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 5usize) { panic("and_assign #498") }
    if !(or(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551615usize) { panic("or #499") }
    if !(or((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 18446744073709551615usize) { panic("or #500") }
    if !(or(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551615usize) { panic("or #501") }
    if !(or((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 18446744073709551615usize) { panic("or #502") }
    if !(or_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551615usize) { panic("or_assign #503") }
    if !(or_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551615usize) { panic("or_assign #504") }
    if !(or_assign(Wrapping(18446744073709551613usize), 7usize).value == 18446744073709551615usize) { panic("or_assign #505") }
    if !(or_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 18446744073709551615usize) { panic("or_assign #506") }
    if !(xor(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551610usize) { panic("xor #507") }
    if !(xor((read Wrapping(18446744073709551613usize)), Wrapping(7usize)).value == 18446744073709551610usize) { panic("xor #508") }
    if !(xor(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551610usize) { panic("xor #509") }
    if !(xor((read Wrapping(18446744073709551613usize)), (read Wrapping(7usize))).value == 18446744073709551610usize) { panic("xor #510") }
    if !(xor_assign(Wrapping(18446744073709551613usize), Wrapping(7usize)).value == 18446744073709551610usize) { panic("xor_assign #511") }
    if !(xor_assign(Wrapping(18446744073709551613usize), (read Wrapping(7usize))).value == 18446744073709551610usize) { panic("xor_assign #512") }
    if !(xor_assign(Wrapping(18446744073709551613usize), 7usize).value == 18446744073709551610usize) { panic("xor_assign #513") }
    if !(xor_assign(Wrapping(18446744073709551613usize), (read 7usize)).value == 18446744073709551610usize) { panic("xor_assign #514") }
    if !(shl(Wrapping(18446744073709551613usize), 3usize).value == 18446744073709551592usize) { panic("shl #515") }
    if !(shr(Wrapping(18446744073709551613usize), 3usize).value == 2305843009213693951usize) { panic("shr #516") }
    if !(shl((read Wrapping(18446744073709551613usize)), 3usize).value == 18446744073709551592usize) { panic("shl #517") }
    if !(shr((read Wrapping(18446744073709551613usize)), 3usize).value == 2305843009213693951usize) { panic("shr #518") }
    if !(shl(Wrapping(18446744073709551613usize), (read 3usize)).value == 18446744073709551592usize) { panic("shl #519") }
    if !(shr(Wrapping(18446744073709551613usize), (read 3usize)).value == 2305843009213693951usize) { panic("shr #520") }
    if !(shl((read Wrapping(18446744073709551613usize)), (read 3usize)).value == 18446744073709551592usize) { panic("shl #521") }
    if !(shr((read Wrapping(18446744073709551613usize)), (read 3usize)).value == 2305843009213693951usize) { panic("shr #522") }
    if !(shl_assign(Wrapping(18446744073709551613usize), 3usize).value == 18446744073709551592usize) { panic("shl_assign #523") }
    if !(shr_assign(Wrapping(18446744073709551613usize), 3usize).value == 2305843009213693951usize) { panic("shr_assign #524") }
    if !(shl_assign(Wrapping(18446744073709551613usize), (read 3usize)).value == 18446744073709551592usize) { panic("shl_assign #525") }
    if !(shr_assign(Wrapping(18446744073709551613usize), (read 3usize)).value == 2305843009213693951usize) { panic("shr_assign #526") }
    if !(shl(Wrapping(18446744073709551613usize), 67usize).value == 18446744073709551592usize) { panic("shl #527") }
    if !(shr(Wrapping(18446744073709551613usize), 67usize).value == 2305843009213693951usize) { panic("shr #528") }
    if !(shl((read Wrapping(18446744073709551613usize)), 67usize).value == 18446744073709551592usize) { panic("shl #529") }
    if !(shr((read Wrapping(18446744073709551613usize)), 67usize).value == 2305843009213693951usize) { panic("shr #530") }
    if !(shl(Wrapping(18446744073709551613usize), (read 67usize)).value == 18446744073709551592usize) { panic("shl #531") }
    if !(shr(Wrapping(18446744073709551613usize), (read 67usize)).value == 2305843009213693951usize) { panic("shr #532") }
    if !(shl((read Wrapping(18446744073709551613usize)), (read 67usize)).value == 18446744073709551592usize) { panic("shl #533") }
    if !(shr((read Wrapping(18446744073709551613usize)), (read 67usize)).value == 2305843009213693951usize) { panic("shr #534") }
    if !(shl_assign(Wrapping(18446744073709551613usize), 67usize).value == 18446744073709551592usize) { panic("shl_assign #535") }
    if !(shr_assign(Wrapping(18446744073709551613usize), 67usize).value == 2305843009213693951usize) { panic("shr_assign #536") }
    if !(shl_assign(Wrapping(18446744073709551613usize), (read 67usize)).value == 18446744073709551592usize) { panic("shl_assign #537") }
    if !(shr_assign(Wrapping(18446744073709551613usize), (read 67usize)).value == 2305843009213693951usize) { panic("shr_assign #538") }
    if !(not((read Wrapping(18446744073709551613usize))).value == 2usize && not(Wrapping(18446744073709551613usize)).value == 2usize) { panic("not #539") }
    if !(neg((read Wrapping(18446744073709551613usize))).value == 3usize && neg(Wrapping(18446744073709551613usize)).value == 3usize) { panic("neg #540") }
}

fn main(): i32 {
    group0()
    group1()
    group2()
    group3()
    0
}
