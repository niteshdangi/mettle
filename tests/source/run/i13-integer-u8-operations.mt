// profiles: debug release
// Every stable integer operation family at this width; expected values are
// computed independently. A failing check panics naming its operation.
import core.num
import core.num.{IntErrorKind, ParseIntError}
import core.panic.panic

fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(_) => false }
}

fn parsed<T: Copy>(result: (Outcome<T, ParseIntError>)): T? {
    match result { success(value) => present(value), failure(_) => none }
}

fn kind<T: Copy>(result: (Outcome<T, ParseIntError>)): IntErrorKind? {
    match result { success(_) => none, failure(error) => present(error.kind) }
}

fn ascii_lower(value: u8): u8 {
    var byte = value
    byte.make_ascii_lowercase()
    byte
}

fn ascii_upper(value: u8): u8 {
    var byte = value
    byte.make_ascii_uppercase()
    byte
}

fn group0() {
    if !(u8.BITS == 8u32) { panic("BITS #1") }
    if !(u8.MIN == 0u8) { panic("MIN #2") }
    if !(u8.MAX == 255u8) { panic("MAX #3") }
    if !(missing(u8.MAX.checked_add(1u8))) { panic("checked_add #4") }
    if !(u8.MAX.wrapping_add(1u8) == 0u8) { panic("wrapping_add #5") }
    if !(u8.MAX.overflowing_add(1u8).0 == 0u8 && u8.MAX.overflowing_add(1u8).1 == true) { panic("overflowing_add #6") }
    if !(u8.MAX.saturating_add(1u8) == u8.MAX) { panic("saturating_add #7") }
    if !(u8.MAX.checked_sub(1u8) == present(254u8)) { panic("checked_sub #8") }
    if !(u8.MAX.wrapping_sub(1u8) == 254u8) { panic("wrapping_sub #9") }
    if !(u8.MAX.overflowing_sub(1u8).0 == 254u8 && u8.MAX.overflowing_sub(1u8).1 == false) { panic("overflowing_sub #10") }
    if !(u8.MAX.saturating_sub(1u8) == 254u8) { panic("saturating_sub #11") }
    if !(u8.MAX.strict_sub(1u8) == 254u8) { panic("strict_sub #12") }
    if !(unsafe { u8.MAX.unchecked_sub(1u8) } == 254u8) { panic("unchecked_sub #13") }
    if !(u8.MAX.checked_mul(1u8) == present(u8.MAX)) { panic("checked_mul #14") }
    if !(u8.MAX.wrapping_mul(1u8) == u8.MAX) { panic("wrapping_mul #15") }
    if !(u8.MAX.overflowing_mul(1u8).0 == u8.MAX && u8.MAX.overflowing_mul(1u8).1 == false) { panic("overflowing_mul #16") }
    if !(u8.MAX.saturating_mul(1u8) == u8.MAX) { panic("saturating_mul #17") }
    if !(u8.MAX.strict_mul(1u8) == u8.MAX) { panic("strict_mul #18") }
    if !(unsafe { u8.MAX.unchecked_mul(1u8) } == u8.MAX) { panic("unchecked_mul #19") }
    if !(u8.MAX.checked_div(1u8) == present(u8.MAX)) { panic("checked_div #20") }
    if !(u8.MAX.wrapping_div(1u8) == u8.MAX) { panic("wrapping_div #21") }
    if !(u8.MAX.overflowing_div(1u8).0 == u8.MAX && u8.MAX.overflowing_div(1u8).1 == false) { panic("overflowing_div #22") }
    if !(u8.MAX.strict_div(1u8) == u8.MAX) { panic("strict_div #23") }
    if !(u8.MAX.saturating_div(1u8) == u8.MAX) { panic("saturating_div #24") }
    if !(u8.MAX.checked_rem(1u8) == present(0u8)) { panic("checked_rem #25") }
    if !(u8.MAX.wrapping_rem(1u8) == 0u8) { panic("wrapping_rem #26") }
    if !(u8.MAX.overflowing_rem(1u8).0 == 0u8 && u8.MAX.overflowing_rem(1u8).1 == false) { panic("overflowing_rem #27") }
    if !(u8.MAX.strict_rem(1u8) == 0u8) { panic("strict_rem #28") }
    if !(u8.MAX.checked_div_euclid(1u8) == present(u8.MAX)) { panic("checked_div_euclid #29") }
    if !(u8.MAX.wrapping_div_euclid(1u8) == u8.MAX) { panic("wrapping_div_euclid #30") }
    if !(u8.MAX.overflowing_div_euclid(1u8).0 == u8.MAX && u8.MAX.overflowing_div_euclid(1u8).1 == false) { panic("overflowing_div_euclid #31") }
    if !(u8.MAX.strict_div_euclid(1u8) == u8.MAX) { panic("strict_div_euclid #32") }
    if !(u8.MAX.div_euclid(1u8) == u8.MAX) { panic("div_euclid #33") }
    if !(u8.MAX.checked_rem_euclid(1u8) == present(0u8)) { panic("checked_rem_euclid #34") }
    if !(u8.MAX.wrapping_rem_euclid(1u8) == 0u8) { panic("wrapping_rem_euclid #35") }
    if !(u8.MAX.overflowing_rem_euclid(1u8).0 == 0u8 && u8.MAX.overflowing_rem_euclid(1u8).1 == false) { panic("overflowing_rem_euclid #36") }
    if !(u8.MAX.strict_rem_euclid(1u8) == 0u8) { panic("strict_rem_euclid #37") }
    if !(u8.MAX.rem_euclid(1u8) == 0u8) { panic("rem_euclid #38") }
    if !(u8.MAX.abs_diff(1u8) == 254u8) { panic("abs_diff #39") }
    if !(u8.MAX.midpoint(1u8) == 128u8) { panic("midpoint #40") }
    if !(0u8.checked_add(1u8) == present(1u8)) { panic("checked_add #41") }
    if !(0u8.wrapping_add(1u8) == 1u8) { panic("wrapping_add #42") }
    if !(0u8.overflowing_add(1u8).0 == 1u8 && 0u8.overflowing_add(1u8).1 == false) { panic("overflowing_add #43") }
    if !(0u8.saturating_add(1u8) == 1u8) { panic("saturating_add #44") }
    if !(0u8.strict_add(1u8) == 1u8) { panic("strict_add #45") }
    if !(unsafe { 0u8.unchecked_add(1u8) } == 1u8) { panic("unchecked_add #46") }
    if !(missing(0u8.checked_sub(1u8))) { panic("checked_sub #47") }
    if !(0u8.wrapping_sub(1u8) == u8.MAX) { panic("wrapping_sub #48") }
    if !(0u8.overflowing_sub(1u8).0 == u8.MAX && 0u8.overflowing_sub(1u8).1 == true) { panic("overflowing_sub #49") }
    if !(0u8.saturating_sub(1u8) == 0u8) { panic("saturating_sub #50") }
    if !(0u8.checked_mul(1u8) == present(0u8)) { panic("checked_mul #51") }
    if !(0u8.wrapping_mul(1u8) == 0u8) { panic("wrapping_mul #52") }
    if !(0u8.overflowing_mul(1u8).0 == 0u8 && 0u8.overflowing_mul(1u8).1 == false) { panic("overflowing_mul #53") }
    if !(0u8.saturating_mul(1u8) == 0u8) { panic("saturating_mul #54") }
    if !(0u8.strict_mul(1u8) == 0u8) { panic("strict_mul #55") }
    if !(unsafe { 0u8.unchecked_mul(1u8) } == 0u8) { panic("unchecked_mul #56") }
    if !(0u8.checked_div(1u8) == present(0u8)) { panic("checked_div #57") }
    if !(0u8.wrapping_div(1u8) == 0u8) { panic("wrapping_div #58") }
    if !(0u8.overflowing_div(1u8).0 == 0u8 && 0u8.overflowing_div(1u8).1 == false) { panic("overflowing_div #59") }
    if !(0u8.strict_div(1u8) == 0u8) { panic("strict_div #60") }
    if !(0u8.saturating_div(1u8) == 0u8) { panic("saturating_div #61") }
    if !(0u8.checked_rem(1u8) == present(0u8)) { panic("checked_rem #62") }
    if !(0u8.wrapping_rem(1u8) == 0u8) { panic("wrapping_rem #63") }
    if !(0u8.overflowing_rem(1u8).0 == 0u8 && 0u8.overflowing_rem(1u8).1 == false) { panic("overflowing_rem #64") }
    if !(0u8.strict_rem(1u8) == 0u8) { panic("strict_rem #65") }
    if !(0u8.checked_div_euclid(1u8) == present(0u8)) { panic("checked_div_euclid #66") }
    if !(0u8.wrapping_div_euclid(1u8) == 0u8) { panic("wrapping_div_euclid #67") }
    if !(0u8.overflowing_div_euclid(1u8).0 == 0u8 && 0u8.overflowing_div_euclid(1u8).1 == false) { panic("overflowing_div_euclid #68") }
    if !(0u8.strict_div_euclid(1u8) == 0u8) { panic("strict_div_euclid #69") }
    if !(0u8.div_euclid(1u8) == 0u8) { panic("div_euclid #70") }
    if !(0u8.checked_rem_euclid(1u8) == present(0u8)) { panic("checked_rem_euclid #71") }
    if !(0u8.wrapping_rem_euclid(1u8) == 0u8) { panic("wrapping_rem_euclid #72") }
    if !(0u8.overflowing_rem_euclid(1u8).0 == 0u8 && 0u8.overflowing_rem_euclid(1u8).1 == false) { panic("overflowing_rem_euclid #73") }
    if !(0u8.strict_rem_euclid(1u8) == 0u8) { panic("strict_rem_euclid #74") }
    if !(0u8.rem_euclid(1u8) == 0u8) { panic("rem_euclid #75") }
    if !(0u8.abs_diff(1u8) == 1u8) { panic("abs_diff #76") }
    if !(0u8.midpoint(1u8) == 0u8) { panic("midpoint #77") }
    if !(3u8.checked_add(7u8) == present(10u8)) { panic("checked_add #78") }
    if !(3u8.wrapping_add(7u8) == 10u8) { panic("wrapping_add #79") }
    if !(3u8.overflowing_add(7u8).0 == 10u8 && 3u8.overflowing_add(7u8).1 == false) { panic("overflowing_add #80") }
    if !(3u8.saturating_add(7u8) == 10u8) { panic("saturating_add #81") }
    if !(3u8.strict_add(7u8) == 10u8) { panic("strict_add #82") }
    if !(unsafe { 3u8.unchecked_add(7u8) } == 10u8) { panic("unchecked_add #83") }
    if !(missing(3u8.checked_sub(7u8))) { panic("checked_sub #84") }
    if !(3u8.wrapping_sub(7u8) == 252u8) { panic("wrapping_sub #85") }
    if !(3u8.overflowing_sub(7u8).0 == 252u8 && 3u8.overflowing_sub(7u8).1 == true) { panic("overflowing_sub #86") }
    if !(3u8.saturating_sub(7u8) == 0u8) { panic("saturating_sub #87") }
    if !(3u8.checked_mul(7u8) == present(21u8)) { panic("checked_mul #88") }
    if !(3u8.wrapping_mul(7u8) == 21u8) { panic("wrapping_mul #89") }
    if !(3u8.overflowing_mul(7u8).0 == 21u8 && 3u8.overflowing_mul(7u8).1 == false) { panic("overflowing_mul #90") }
    if !(3u8.saturating_mul(7u8) == 21u8) { panic("saturating_mul #91") }
    if !(3u8.strict_mul(7u8) == 21u8) { panic("strict_mul #92") }
    if !(unsafe { 3u8.unchecked_mul(7u8) } == 21u8) { panic("unchecked_mul #93") }
    if !(3u8.checked_div(7u8) == present(0u8)) { panic("checked_div #94") }
    if !(3u8.wrapping_div(7u8) == 0u8) { panic("wrapping_div #95") }
    if !(3u8.overflowing_div(7u8).0 == 0u8 && 3u8.overflowing_div(7u8).1 == false) { panic("overflowing_div #96") }
    if !(3u8.strict_div(7u8) == 0u8) { panic("strict_div #97") }
    if !(3u8.saturating_div(7u8) == 0u8) { panic("saturating_div #98") }
    if !(3u8.checked_rem(7u8) == present(3u8)) { panic("checked_rem #99") }
    if !(3u8.wrapping_rem(7u8) == 3u8) { panic("wrapping_rem #100") }
    if !(3u8.overflowing_rem(7u8).0 == 3u8 && 3u8.overflowing_rem(7u8).1 == false) { panic("overflowing_rem #101") }
    if !(3u8.strict_rem(7u8) == 3u8) { panic("strict_rem #102") }
    if !(3u8.checked_div_euclid(7u8) == present(0u8)) { panic("checked_div_euclid #103") }
    if !(3u8.wrapping_div_euclid(7u8) == 0u8) { panic("wrapping_div_euclid #104") }
    if !(3u8.overflowing_div_euclid(7u8).0 == 0u8 && 3u8.overflowing_div_euclid(7u8).1 == false) { panic("overflowing_div_euclid #105") }
    if !(3u8.strict_div_euclid(7u8) == 0u8) { panic("strict_div_euclid #106") }
    if !(3u8.div_euclid(7u8) == 0u8) { panic("div_euclid #107") }
    if !(3u8.checked_rem_euclid(7u8) == present(3u8)) { panic("checked_rem_euclid #108") }
    if !(3u8.wrapping_rem_euclid(7u8) == 3u8) { panic("wrapping_rem_euclid #109") }
    if !(3u8.overflowing_rem_euclid(7u8).0 == 3u8 && 3u8.overflowing_rem_euclid(7u8).1 == false) { panic("overflowing_rem_euclid #110") }
    if !(3u8.strict_rem_euclid(7u8) == 3u8) { panic("strict_rem_euclid #111") }
    if !(3u8.rem_euclid(7u8) == 3u8) { panic("rem_euclid #112") }
    if !(3u8.abs_diff(7u8) == 4u8) { panic("abs_diff #113") }
    if !(3u8.midpoint(7u8) == 5u8) { panic("midpoint #114") }
    if !(7u8.checked_add(3u8) == present(10u8)) { panic("checked_add #115") }
    if !(7u8.wrapping_add(3u8) == 10u8) { panic("wrapping_add #116") }
    if !(7u8.overflowing_add(3u8).0 == 10u8 && 7u8.overflowing_add(3u8).1 == false) { panic("overflowing_add #117") }
    if !(7u8.saturating_add(3u8) == 10u8) { panic("saturating_add #118") }
    if !(7u8.strict_add(3u8) == 10u8) { panic("strict_add #119") }
    if !(unsafe { 7u8.unchecked_add(3u8) } == 10u8) { panic("unchecked_add #120") }
}

fn group1() {
    if !(7u8.checked_sub(3u8) == present(4u8)) { panic("checked_sub #121") }
    if !(7u8.wrapping_sub(3u8) == 4u8) { panic("wrapping_sub #122") }
    if !(7u8.overflowing_sub(3u8).0 == 4u8 && 7u8.overflowing_sub(3u8).1 == false) { panic("overflowing_sub #123") }
    if !(7u8.saturating_sub(3u8) == 4u8) { panic("saturating_sub #124") }
    if !(7u8.strict_sub(3u8) == 4u8) { panic("strict_sub #125") }
    if !(unsafe { 7u8.unchecked_sub(3u8) } == 4u8) { panic("unchecked_sub #126") }
    if !(7u8.checked_mul(3u8) == present(21u8)) { panic("checked_mul #127") }
    if !(7u8.wrapping_mul(3u8) == 21u8) { panic("wrapping_mul #128") }
    if !(7u8.overflowing_mul(3u8).0 == 21u8 && 7u8.overflowing_mul(3u8).1 == false) { panic("overflowing_mul #129") }
    if !(7u8.saturating_mul(3u8) == 21u8) { panic("saturating_mul #130") }
    if !(7u8.strict_mul(3u8) == 21u8) { panic("strict_mul #131") }
    if !(unsafe { 7u8.unchecked_mul(3u8) } == 21u8) { panic("unchecked_mul #132") }
    if !(7u8.checked_div(3u8) == present(2u8)) { panic("checked_div #133") }
    if !(7u8.wrapping_div(3u8) == 2u8) { panic("wrapping_div #134") }
    if !(7u8.overflowing_div(3u8).0 == 2u8 && 7u8.overflowing_div(3u8).1 == false) { panic("overflowing_div #135") }
    if !(7u8.strict_div(3u8) == 2u8) { panic("strict_div #136") }
    if !(7u8.saturating_div(3u8) == 2u8) { panic("saturating_div #137") }
    if !(7u8.checked_rem(3u8) == present(1u8)) { panic("checked_rem #138") }
    if !(7u8.wrapping_rem(3u8) == 1u8) { panic("wrapping_rem #139") }
    if !(7u8.overflowing_rem(3u8).0 == 1u8 && 7u8.overflowing_rem(3u8).1 == false) { panic("overflowing_rem #140") }
    if !(7u8.strict_rem(3u8) == 1u8) { panic("strict_rem #141") }
    if !(7u8.checked_div_euclid(3u8) == present(2u8)) { panic("checked_div_euclid #142") }
    if !(7u8.wrapping_div_euclid(3u8) == 2u8) { panic("wrapping_div_euclid #143") }
    if !(7u8.overflowing_div_euclid(3u8).0 == 2u8 && 7u8.overflowing_div_euclid(3u8).1 == false) { panic("overflowing_div_euclid #144") }
    if !(7u8.strict_div_euclid(3u8) == 2u8) { panic("strict_div_euclid #145") }
    if !(7u8.div_euclid(3u8) == 2u8) { panic("div_euclid #146") }
    if !(7u8.checked_rem_euclid(3u8) == present(1u8)) { panic("checked_rem_euclid #147") }
    if !(7u8.wrapping_rem_euclid(3u8) == 1u8) { panic("wrapping_rem_euclid #148") }
    if !(7u8.overflowing_rem_euclid(3u8).0 == 1u8 && 7u8.overflowing_rem_euclid(3u8).1 == false) { panic("overflowing_rem_euclid #149") }
    if !(7u8.strict_rem_euclid(3u8) == 1u8) { panic("strict_rem_euclid #150") }
    if !(7u8.rem_euclid(3u8) == 1u8) { panic("rem_euclid #151") }
    if !(7u8.abs_diff(3u8) == 4u8) { panic("abs_diff #152") }
    if !(7u8.midpoint(3u8) == 5u8) { panic("midpoint #153") }
    if !(missing(u8.MAX.checked_add(2u8))) { panic("checked_add #154") }
    if !(u8.MAX.wrapping_add(2u8) == 1u8) { panic("wrapping_add #155") }
    if !(u8.MAX.overflowing_add(2u8).0 == 1u8 && u8.MAX.overflowing_add(2u8).1 == true) { panic("overflowing_add #156") }
    if !(u8.MAX.saturating_add(2u8) == u8.MAX) { panic("saturating_add #157") }
    if !(u8.MAX.checked_sub(2u8) == present(253u8)) { panic("checked_sub #158") }
    if !(u8.MAX.wrapping_sub(2u8) == 253u8) { panic("wrapping_sub #159") }
    if !(u8.MAX.overflowing_sub(2u8).0 == 253u8 && u8.MAX.overflowing_sub(2u8).1 == false) { panic("overflowing_sub #160") }
    if !(u8.MAX.saturating_sub(2u8) == 253u8) { panic("saturating_sub #161") }
    if !(u8.MAX.strict_sub(2u8) == 253u8) { panic("strict_sub #162") }
    if !(unsafe { u8.MAX.unchecked_sub(2u8) } == 253u8) { panic("unchecked_sub #163") }
    if !(missing(u8.MAX.checked_mul(2u8))) { panic("checked_mul #164") }
    if !(u8.MAX.wrapping_mul(2u8) == 254u8) { panic("wrapping_mul #165") }
    if !(u8.MAX.overflowing_mul(2u8).0 == 254u8 && u8.MAX.overflowing_mul(2u8).1 == true) { panic("overflowing_mul #166") }
    if !(u8.MAX.saturating_mul(2u8) == u8.MAX) { panic("saturating_mul #167") }
    if !(u8.MAX.checked_div(2u8) == present(127u8)) { panic("checked_div #168") }
    if !(u8.MAX.wrapping_div(2u8) == 127u8) { panic("wrapping_div #169") }
    if !(u8.MAX.overflowing_div(2u8).0 == 127u8 && u8.MAX.overflowing_div(2u8).1 == false) { panic("overflowing_div #170") }
    if !(u8.MAX.strict_div(2u8) == 127u8) { panic("strict_div #171") }
    if !(u8.MAX.saturating_div(2u8) == 127u8) { panic("saturating_div #172") }
    if !(u8.MAX.checked_rem(2u8) == present(1u8)) { panic("checked_rem #173") }
    if !(u8.MAX.wrapping_rem(2u8) == 1u8) { panic("wrapping_rem #174") }
    if !(u8.MAX.overflowing_rem(2u8).0 == 1u8 && u8.MAX.overflowing_rem(2u8).1 == false) { panic("overflowing_rem #175") }
    if !(u8.MAX.strict_rem(2u8) == 1u8) { panic("strict_rem #176") }
    if !(u8.MAX.checked_div_euclid(2u8) == present(127u8)) { panic("checked_div_euclid #177") }
    if !(u8.MAX.wrapping_div_euclid(2u8) == 127u8) { panic("wrapping_div_euclid #178") }
    if !(u8.MAX.overflowing_div_euclid(2u8).0 == 127u8 && u8.MAX.overflowing_div_euclid(2u8).1 == false) { panic("overflowing_div_euclid #179") }
    if !(u8.MAX.strict_div_euclid(2u8) == 127u8) { panic("strict_div_euclid #180") }
    if !(u8.MAX.div_euclid(2u8) == 127u8) { panic("div_euclid #181") }
    if !(u8.MAX.checked_rem_euclid(2u8) == present(1u8)) { panic("checked_rem_euclid #182") }
    if !(u8.MAX.wrapping_rem_euclid(2u8) == 1u8) { panic("wrapping_rem_euclid #183") }
    if !(u8.MAX.overflowing_rem_euclid(2u8).0 == 1u8 && u8.MAX.overflowing_rem_euclid(2u8).1 == false) { panic("overflowing_rem_euclid #184") }
    if !(u8.MAX.strict_rem_euclid(2u8) == 1u8) { panic("strict_rem_euclid #185") }
    if !(u8.MAX.rem_euclid(2u8) == 1u8) { panic("rem_euclid #186") }
    if !(u8.MAX.abs_diff(2u8) == 253u8) { panic("abs_diff #187") }
    if !(u8.MAX.midpoint(2u8) == 128u8) { panic("midpoint #188") }
    if !(0u8.checked_add(0u8) == present(0u8)) { panic("checked_add #189") }
    if !(0u8.wrapping_add(0u8) == 0u8) { panic("wrapping_add #190") }
    if !(0u8.overflowing_add(0u8).0 == 0u8 && 0u8.overflowing_add(0u8).1 == false) { panic("overflowing_add #191") }
    if !(0u8.saturating_add(0u8) == 0u8) { panic("saturating_add #192") }
    if !(0u8.strict_add(0u8) == 0u8) { panic("strict_add #193") }
    if !(unsafe { 0u8.unchecked_add(0u8) } == 0u8) { panic("unchecked_add #194") }
    if !(0u8.checked_sub(0u8) == present(0u8)) { panic("checked_sub #195") }
    if !(0u8.wrapping_sub(0u8) == 0u8) { panic("wrapping_sub #196") }
    if !(0u8.overflowing_sub(0u8).0 == 0u8 && 0u8.overflowing_sub(0u8).1 == false) { panic("overflowing_sub #197") }
    if !(0u8.saturating_sub(0u8) == 0u8) { panic("saturating_sub #198") }
    if !(0u8.strict_sub(0u8) == 0u8) { panic("strict_sub #199") }
    if !(unsafe { 0u8.unchecked_sub(0u8) } == 0u8) { panic("unchecked_sub #200") }
    if !(0u8.checked_mul(0u8) == present(0u8)) { panic("checked_mul #201") }
    if !(0u8.wrapping_mul(0u8) == 0u8) { panic("wrapping_mul #202") }
    if !(0u8.overflowing_mul(0u8).0 == 0u8 && 0u8.overflowing_mul(0u8).1 == false) { panic("overflowing_mul #203") }
    if !(0u8.saturating_mul(0u8) == 0u8) { panic("saturating_mul #204") }
    if !(0u8.strict_mul(0u8) == 0u8) { panic("strict_mul #205") }
    if !(unsafe { 0u8.unchecked_mul(0u8) } == 0u8) { panic("unchecked_mul #206") }
    if !(missing(0u8.checked_div(0u8))) { panic("checked_div #207") }
    if !(missing(0u8.checked_rem(0u8))) { panic("checked_rem #208") }
    if !(missing(0u8.checked_div_euclid(0u8))) { panic("checked_div_euclid #209") }
    if !(missing(0u8.checked_rem_euclid(0u8))) { panic("checked_rem_euclid #210") }
    if !(0u8.abs_diff(0u8) == 0u8) { panic("abs_diff #211") }
    if !(0u8.midpoint(0u8) == 0u8) { panic("midpoint #212") }
    if !(missing(u8.MAX.checked_add(u8.MAX))) { panic("checked_add #213") }
    if !(u8.MAX.wrapping_add(u8.MAX) == 254u8) { panic("wrapping_add #214") }
    if !(u8.MAX.overflowing_add(u8.MAX).0 == 254u8 && u8.MAX.overflowing_add(u8.MAX).1 == true) { panic("overflowing_add #215") }
    if !(u8.MAX.saturating_add(u8.MAX) == u8.MAX) { panic("saturating_add #216") }
    if !(u8.MAX.checked_sub(u8.MAX) == present(0u8)) { panic("checked_sub #217") }
    if !(u8.MAX.wrapping_sub(u8.MAX) == 0u8) { panic("wrapping_sub #218") }
    if !(u8.MAX.overflowing_sub(u8.MAX).0 == 0u8 && u8.MAX.overflowing_sub(u8.MAX).1 == false) { panic("overflowing_sub #219") }
    if !(u8.MAX.saturating_sub(u8.MAX) == 0u8) { panic("saturating_sub #220") }
    if !(u8.MAX.strict_sub(u8.MAX) == 0u8) { panic("strict_sub #221") }
    if !(unsafe { u8.MAX.unchecked_sub(u8.MAX) } == 0u8) { panic("unchecked_sub #222") }
    if !(missing(u8.MAX.checked_mul(u8.MAX))) { panic("checked_mul #223") }
    if !(u8.MAX.wrapping_mul(u8.MAX) == 1u8) { panic("wrapping_mul #224") }
    if !(u8.MAX.overflowing_mul(u8.MAX).0 == 1u8 && u8.MAX.overflowing_mul(u8.MAX).1 == true) { panic("overflowing_mul #225") }
    if !(u8.MAX.saturating_mul(u8.MAX) == u8.MAX) { panic("saturating_mul #226") }
    if !(u8.MAX.checked_div(u8.MAX) == present(1u8)) { panic("checked_div #227") }
    if !(u8.MAX.wrapping_div(u8.MAX) == 1u8) { panic("wrapping_div #228") }
    if !(u8.MAX.overflowing_div(u8.MAX).0 == 1u8 && u8.MAX.overflowing_div(u8.MAX).1 == false) { panic("overflowing_div #229") }
    if !(u8.MAX.strict_div(u8.MAX) == 1u8) { panic("strict_div #230") }
    if !(u8.MAX.saturating_div(u8.MAX) == 1u8) { panic("saturating_div #231") }
    if !(u8.MAX.checked_rem(u8.MAX) == present(0u8)) { panic("checked_rem #232") }
    if !(u8.MAX.wrapping_rem(u8.MAX) == 0u8) { panic("wrapping_rem #233") }
    if !(u8.MAX.overflowing_rem(u8.MAX).0 == 0u8 && u8.MAX.overflowing_rem(u8.MAX).1 == false) { panic("overflowing_rem #234") }
    if !(u8.MAX.strict_rem(u8.MAX) == 0u8) { panic("strict_rem #235") }
    if !(u8.MAX.checked_div_euclid(u8.MAX) == present(1u8)) { panic("checked_div_euclid #236") }
    if !(u8.MAX.wrapping_div_euclid(u8.MAX) == 1u8) { panic("wrapping_div_euclid #237") }
    if !(u8.MAX.overflowing_div_euclid(u8.MAX).0 == 1u8 && u8.MAX.overflowing_div_euclid(u8.MAX).1 == false) { panic("overflowing_div_euclid #238") }
    if !(u8.MAX.strict_div_euclid(u8.MAX) == 1u8) { panic("strict_div_euclid #239") }
    if !(u8.MAX.div_euclid(u8.MAX) == 1u8) { panic("div_euclid #240") }
}

fn group2() {
    if !(u8.MAX.checked_rem_euclid(u8.MAX) == present(0u8)) { panic("checked_rem_euclid #241") }
    if !(u8.MAX.wrapping_rem_euclid(u8.MAX) == 0u8) { panic("wrapping_rem_euclid #242") }
    if !(u8.MAX.overflowing_rem_euclid(u8.MAX).0 == 0u8 && u8.MAX.overflowing_rem_euclid(u8.MAX).1 == false) { panic("overflowing_rem_euclid #243") }
    if !(u8.MAX.strict_rem_euclid(u8.MAX) == 0u8) { panic("strict_rem_euclid #244") }
    if !(u8.MAX.rem_euclid(u8.MAX) == 0u8) { panic("rem_euclid #245") }
    if !(u8.MAX.abs_diff(u8.MAX) == 0u8) { panic("abs_diff #246") }
    if !(u8.MAX.midpoint(u8.MAX) == u8.MAX) { panic("midpoint #247") }
    if !(missing(u8.MAX.checked_add(254u8))) { panic("checked_add #248") }
    if !(u8.MAX.wrapping_add(254u8) == 253u8) { panic("wrapping_add #249") }
    if !(u8.MAX.overflowing_add(254u8).0 == 253u8 && u8.MAX.overflowing_add(254u8).1 == true) { panic("overflowing_add #250") }
    if !(u8.MAX.saturating_add(254u8) == u8.MAX) { panic("saturating_add #251") }
    if !(u8.MAX.checked_sub(254u8) == present(1u8)) { panic("checked_sub #252") }
    if !(u8.MAX.wrapping_sub(254u8) == 1u8) { panic("wrapping_sub #253") }
    if !(u8.MAX.overflowing_sub(254u8).0 == 1u8 && u8.MAX.overflowing_sub(254u8).1 == false) { panic("overflowing_sub #254") }
    if !(u8.MAX.saturating_sub(254u8) == 1u8) { panic("saturating_sub #255") }
    if !(u8.MAX.strict_sub(254u8) == 1u8) { panic("strict_sub #256") }
    if !(unsafe { u8.MAX.unchecked_sub(254u8) } == 1u8) { panic("unchecked_sub #257") }
    if !(missing(u8.MAX.checked_mul(254u8))) { panic("checked_mul #258") }
    if !(u8.MAX.wrapping_mul(254u8) == 2u8) { panic("wrapping_mul #259") }
    if !(u8.MAX.overflowing_mul(254u8).0 == 2u8 && u8.MAX.overflowing_mul(254u8).1 == true) { panic("overflowing_mul #260") }
    if !(u8.MAX.saturating_mul(254u8) == u8.MAX) { panic("saturating_mul #261") }
    if !(u8.MAX.checked_div(254u8) == present(1u8)) { panic("checked_div #262") }
    if !(u8.MAX.wrapping_div(254u8) == 1u8) { panic("wrapping_div #263") }
    if !(u8.MAX.overflowing_div(254u8).0 == 1u8 && u8.MAX.overflowing_div(254u8).1 == false) { panic("overflowing_div #264") }
    if !(u8.MAX.strict_div(254u8) == 1u8) { panic("strict_div #265") }
    if !(u8.MAX.saturating_div(254u8) == 1u8) { panic("saturating_div #266") }
    if !(u8.MAX.checked_rem(254u8) == present(1u8)) { panic("checked_rem #267") }
    if !(u8.MAX.wrapping_rem(254u8) == 1u8) { panic("wrapping_rem #268") }
    if !(u8.MAX.overflowing_rem(254u8).0 == 1u8 && u8.MAX.overflowing_rem(254u8).1 == false) { panic("overflowing_rem #269") }
    if !(u8.MAX.strict_rem(254u8) == 1u8) { panic("strict_rem #270") }
    if !(u8.MAX.checked_div_euclid(254u8) == present(1u8)) { panic("checked_div_euclid #271") }
    if !(u8.MAX.wrapping_div_euclid(254u8) == 1u8) { panic("wrapping_div_euclid #272") }
    if !(u8.MAX.overflowing_div_euclid(254u8).0 == 1u8 && u8.MAX.overflowing_div_euclid(254u8).1 == false) { panic("overflowing_div_euclid #273") }
    if !(u8.MAX.strict_div_euclid(254u8) == 1u8) { panic("strict_div_euclid #274") }
    if !(u8.MAX.div_euclid(254u8) == 1u8) { panic("div_euclid #275") }
    if !(u8.MAX.checked_rem_euclid(254u8) == present(1u8)) { panic("checked_rem_euclid #276") }
    if !(u8.MAX.wrapping_rem_euclid(254u8) == 1u8) { panic("wrapping_rem_euclid #277") }
    if !(u8.MAX.overflowing_rem_euclid(254u8).0 == 1u8 && u8.MAX.overflowing_rem_euclid(254u8).1 == false) { panic("overflowing_rem_euclid #278") }
    if !(u8.MAX.strict_rem_euclid(254u8) == 1u8) { panic("strict_rem_euclid #279") }
    if !(u8.MAX.rem_euclid(254u8) == 1u8) { panic("rem_euclid #280") }
    if !(u8.MAX.abs_diff(254u8) == 1u8) { panic("abs_diff #281") }
    if !(u8.MAX.midpoint(254u8) == 254u8) { panic("midpoint #282") }
    if !(missing(u8.MAX.checked_add_signed(1i8))) { panic("checked_add_signed #283") }
    if !(u8.MAX.wrapping_add_signed(1i8) == 0u8) { panic("wrapping_add_signed #284") }
    if !(u8.MAX.overflowing_add_signed(1i8).0 == 0u8 && u8.MAX.overflowing_add_signed(1i8).1 == true) { panic("overflowing_add_signed #285") }
    if !(u8.MAX.saturating_add_signed(1i8) == u8.MAX) { panic("saturating_add_signed #286") }
    if !(u8.MAX.checked_sub_signed(1i8) == present(254u8)) { panic("checked_sub_signed #287") }
    if !(u8.MAX.wrapping_sub_signed(1i8) == 254u8) { panic("wrapping_sub_signed #288") }
    if !(u8.MAX.overflowing_sub_signed(1i8).0 == 254u8 && u8.MAX.overflowing_sub_signed(1i8).1 == false) { panic("overflowing_sub_signed #289") }
    if !(u8.MAX.saturating_sub_signed(1i8) == 254u8) { panic("saturating_sub_signed #290") }
    if !(u8.MAX.strict_sub_signed(1i8) == 254u8) { panic("strict_sub_signed #291") }
    if !(missing(0u8.checked_add_signed((-1i8)))) { panic("checked_add_signed #292") }
    if !(0u8.wrapping_add_signed((-1i8)) == u8.MAX) { panic("wrapping_add_signed #293") }
    if !(0u8.overflowing_add_signed((-1i8)).0 == u8.MAX && 0u8.overflowing_add_signed((-1i8)).1 == true) { panic("overflowing_add_signed #294") }
    if !(0u8.saturating_add_signed((-1i8)) == 0u8) { panic("saturating_add_signed #295") }
    if !(0u8.checked_sub_signed((-1i8)) == present(1u8)) { panic("checked_sub_signed #296") }
    if !(0u8.wrapping_sub_signed((-1i8)) == 1u8) { panic("wrapping_sub_signed #297") }
    if !(0u8.overflowing_sub_signed((-1i8)).0 == 1u8 && 0u8.overflowing_sub_signed((-1i8)).1 == false) { panic("overflowing_sub_signed #298") }
    if !(0u8.saturating_sub_signed((-1i8)) == 1u8) { panic("saturating_sub_signed #299") }
    if !(0u8.strict_sub_signed((-1i8)) == 1u8) { panic("strict_sub_signed #300") }
    if !(7u8.checked_add_signed((-3i8)) == present(4u8)) { panic("checked_add_signed #301") }
    if !(7u8.wrapping_add_signed((-3i8)) == 4u8) { panic("wrapping_add_signed #302") }
    if !(7u8.overflowing_add_signed((-3i8)).0 == 4u8 && 7u8.overflowing_add_signed((-3i8)).1 == false) { panic("overflowing_add_signed #303") }
    if !(7u8.saturating_add_signed((-3i8)) == 4u8) { panic("saturating_add_signed #304") }
    if !(7u8.strict_add_signed((-3i8)) == 4u8) { panic("strict_add_signed #305") }
    if !(7u8.checked_sub_signed((-3i8)) == present(10u8)) { panic("checked_sub_signed #306") }
    if !(7u8.wrapping_sub_signed((-3i8)) == 10u8) { panic("wrapping_sub_signed #307") }
    if !(7u8.overflowing_sub_signed((-3i8)).0 == 10u8 && 7u8.overflowing_sub_signed((-3i8)).1 == false) { panic("overflowing_sub_signed #308") }
    if !(7u8.saturating_sub_signed((-3i8)) == 10u8) { panic("saturating_sub_signed #309") }
    if !(7u8.strict_sub_signed((-3i8)) == 10u8) { panic("strict_sub_signed #310") }
    if !(u8.MAX.checked_add_signed(i8.MIN) == present(127u8)) { panic("checked_add_signed #311") }
    if !(u8.MAX.wrapping_add_signed(i8.MIN) == 127u8) { panic("wrapping_add_signed #312") }
    if !(u8.MAX.overflowing_add_signed(i8.MIN).0 == 127u8 && u8.MAX.overflowing_add_signed(i8.MIN).1 == false) { panic("overflowing_add_signed #313") }
    if !(u8.MAX.saturating_add_signed(i8.MIN) == 127u8) { panic("saturating_add_signed #314") }
    if !(u8.MAX.strict_add_signed(i8.MIN) == 127u8) { panic("strict_add_signed #315") }
    if !(missing(u8.MAX.checked_sub_signed(i8.MIN))) { panic("checked_sub_signed #316") }
    if !(u8.MAX.wrapping_sub_signed(i8.MIN) == 127u8) { panic("wrapping_sub_signed #317") }
    if !(u8.MAX.overflowing_sub_signed(i8.MIN).0 == 127u8 && u8.MAX.overflowing_sub_signed(i8.MIN).1 == true) { panic("overflowing_sub_signed #318") }
    if !(u8.MAX.saturating_sub_signed(i8.MIN) == u8.MAX) { panic("saturating_sub_signed #319") }
    if !(0u8.checked_add_signed(i8.MAX) == present(127u8)) { panic("checked_add_signed #320") }
    if !(0u8.wrapping_add_signed(i8.MAX) == 127u8) { panic("wrapping_add_signed #321") }
    if !(0u8.overflowing_add_signed(i8.MAX).0 == 127u8 && 0u8.overflowing_add_signed(i8.MAX).1 == false) { panic("overflowing_add_signed #322") }
    if !(0u8.saturating_add_signed(i8.MAX) == 127u8) { panic("saturating_add_signed #323") }
    if !(0u8.strict_add_signed(i8.MAX) == 127u8) { panic("strict_add_signed #324") }
    if !(missing(0u8.checked_sub_signed(i8.MAX))) { panic("checked_sub_signed #325") }
    if !(0u8.wrapping_sub_signed(i8.MAX) == 129u8) { panic("wrapping_sub_signed #326") }
    if !(0u8.overflowing_sub_signed(i8.MAX).0 == 129u8 && 0u8.overflowing_sub_signed(i8.MAX).1 == true) { panic("overflowing_sub_signed #327") }
    if !(0u8.saturating_sub_signed(i8.MAX) == 0u8) { panic("saturating_sub_signed #328") }
    if !(missing(u8.MAX.checked_neg())) { panic("checked_neg #329") }
    if !(u8.MAX.wrapping_neg() == 1u8) { panic("wrapping_neg #330") }
    if !(u8.MAX.overflowing_neg().0 == 1u8 && u8.MAX.overflowing_neg().1 == true) { panic("overflowing_neg #331") }
    if !(u8.MAX.cast_signed() == (-1i8)) { panic("cast_signed #332") }
    if !(u8.MAX.count_ones() == 8u32) { panic("count_ones #333") }
    if !(u8.MAX.count_zeros() == 0u32) { panic("count_zeros #334") }
    if !(u8.MAX.leading_zeros() == 0u32) { panic("leading_zeros #335") }
    if !(u8.MAX.trailing_zeros() == 0u32) { panic("trailing_zeros #336") }
    if !(u8.MAX.leading_ones() == 8u32) { panic("leading_ones #337") }
    if !(u8.MAX.trailing_ones() == 8u32) { panic("trailing_ones #338") }
    if !(u8.MAX.reverse_bits() == u8.MAX) { panic("reverse_bits #339") }
    if !(u8.MAX.swap_bytes() == u8.MAX) { panic("swap_bytes #340") }
    if !(u8.MAX.to_be() == u8.MAX) { panic("to_be #341") }
    if !(u8.MAX.to_le() == u8.MAX) { panic("to_le #342") }
    if !(u8.from_be(u8.MAX) == u8.MAX) { panic("from_be #343") }
    if !(u8.from_le(u8.MAX) == u8.MAX) { panic("from_le #344") }
    if !(u8.MAX.to_le_bytes() == [255u8]) { panic("to_le_bytes #345") }
    if !(u8.MAX.to_be_bytes() == [255u8]) { panic("to_be_bytes #346") }
    if !(u8.MAX.to_ne_bytes() == [255u8]) { panic("to_ne_bytes #347") }
    if !(u8.from_le_bytes([255u8]) == u8.MAX) { panic("from_le_bytes #348") }
    if !(u8.from_be_bytes([255u8]) == u8.MAX) { panic("from_be_bytes #349") }
    if !(u8.from_ne_bytes([255u8]) == u8.MAX) { panic("from_ne_bytes #350") }
    if !(u8.MAX.rotate_left(0u32) == u8.MAX) { panic("rotate_left #351") }
    if !(u8.MAX.rotate_right(0u32) == u8.MAX) { panic("rotate_right #352") }
    if !(u8.MAX.checked_shl(0u32) == present(u8.MAX)) { panic("checked_shl #353") }
    if !(u8.MAX.checked_shr(0u32) == present(u8.MAX)) { panic("checked_shr #354") }
    if !(u8.MAX.wrapping_shl(0u32) == u8.MAX) { panic("wrapping_shl #355") }
    if !(u8.MAX.wrapping_shr(0u32) == u8.MAX) { panic("wrapping_shr #356") }
    if !(u8.MAX.overflowing_shl(0u32).0 == u8.MAX && u8.MAX.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #357") }
    if !(u8.MAX.overflowing_shr(0u32).0 == u8.MAX && u8.MAX.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #358") }
    if !(u8.MAX.unbounded_shl(0u32) == u8.MAX) { panic("unbounded_shl #359") }
    if !(u8.MAX.unbounded_shr(0u32) == u8.MAX) { panic("unbounded_shr #360") }
}

fn group3() {
    if !(u8.MAX.strict_shl(0u32) == u8.MAX) { panic("strict_shl #361") }
    if !(u8.MAX.strict_shr(0u32) == u8.MAX) { panic("strict_shr #362") }
    if !(unsafe { u8.MAX.unchecked_shl(0u32) } == u8.MAX) { panic("unchecked_shl #363") }
    if !(unsafe { u8.MAX.unchecked_shr(0u32) } == u8.MAX) { panic("unchecked_shr #364") }
    if !(u8.MAX.rotate_left(1u32) == u8.MAX) { panic("rotate_left #365") }
    if !(u8.MAX.rotate_right(1u32) == u8.MAX) { panic("rotate_right #366") }
    if !(u8.MAX.checked_shl(1u32) == present(254u8)) { panic("checked_shl #367") }
    if !(u8.MAX.checked_shr(1u32) == present(127u8)) { panic("checked_shr #368") }
    if !(u8.MAX.wrapping_shl(1u32) == 254u8) { panic("wrapping_shl #369") }
    if !(u8.MAX.wrapping_shr(1u32) == 127u8) { panic("wrapping_shr #370") }
    if !(u8.MAX.overflowing_shl(1u32).0 == 254u8 && u8.MAX.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #371") }
    if !(u8.MAX.overflowing_shr(1u32).0 == 127u8 && u8.MAX.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #372") }
    if !(u8.MAX.unbounded_shl(1u32) == 254u8) { panic("unbounded_shl #373") }
    if !(u8.MAX.unbounded_shr(1u32) == 127u8) { panic("unbounded_shr #374") }
    if !(u8.MAX.strict_shl(1u32) == 254u8) { panic("strict_shl #375") }
    if !(u8.MAX.strict_shr(1u32) == 127u8) { panic("strict_shr #376") }
    if !(unsafe { u8.MAX.unchecked_shl(1u32) } == 254u8) { panic("unchecked_shl #377") }
    if !(unsafe { u8.MAX.unchecked_shr(1u32) } == 127u8) { panic("unchecked_shr #378") }
    if !(u8.MAX.rotate_left(3u32) == u8.MAX) { panic("rotate_left #379") }
    if !(u8.MAX.rotate_right(3u32) == u8.MAX) { panic("rotate_right #380") }
    if !(u8.MAX.checked_shl(3u32) == present(248u8)) { panic("checked_shl #381") }
    if !(u8.MAX.checked_shr(3u32) == present(31u8)) { panic("checked_shr #382") }
    if !(u8.MAX.wrapping_shl(3u32) == 248u8) { panic("wrapping_shl #383") }
    if !(u8.MAX.wrapping_shr(3u32) == 31u8) { panic("wrapping_shr #384") }
    if !(u8.MAX.overflowing_shl(3u32).0 == 248u8 && u8.MAX.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #385") }
    if !(u8.MAX.overflowing_shr(3u32).0 == 31u8 && u8.MAX.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #386") }
    if !(u8.MAX.unbounded_shl(3u32) == 248u8) { panic("unbounded_shl #387") }
    if !(u8.MAX.unbounded_shr(3u32) == 31u8) { panic("unbounded_shr #388") }
    if !(u8.MAX.strict_shl(3u32) == 248u8) { panic("strict_shl #389") }
    if !(u8.MAX.strict_shr(3u32) == 31u8) { panic("strict_shr #390") }
    if !(unsafe { u8.MAX.unchecked_shl(3u32) } == 248u8) { panic("unchecked_shl #391") }
    if !(unsafe { u8.MAX.unchecked_shr(3u32) } == 31u8) { panic("unchecked_shr #392") }
    if !(u8.MAX.rotate_left(7u32) == u8.MAX) { panic("rotate_left #393") }
    if !(u8.MAX.rotate_right(7u32) == u8.MAX) { panic("rotate_right #394") }
    if !(u8.MAX.checked_shl(7u32) == present(128u8)) { panic("checked_shl #395") }
    if !(u8.MAX.checked_shr(7u32) == present(1u8)) { panic("checked_shr #396") }
    if !(u8.MAX.wrapping_shl(7u32) == 128u8) { panic("wrapping_shl #397") }
    if !(u8.MAX.wrapping_shr(7u32) == 1u8) { panic("wrapping_shr #398") }
    if !(u8.MAX.overflowing_shl(7u32).0 == 128u8 && u8.MAX.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #399") }
    if !(u8.MAX.overflowing_shr(7u32).0 == 1u8 && u8.MAX.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #400") }
    if !(u8.MAX.unbounded_shl(7u32) == 128u8) { panic("unbounded_shl #401") }
    if !(u8.MAX.unbounded_shr(7u32) == 1u8) { panic("unbounded_shr #402") }
    if !(u8.MAX.strict_shl(7u32) == 128u8) { panic("strict_shl #403") }
    if !(u8.MAX.strict_shr(7u32) == 1u8) { panic("strict_shr #404") }
    if !(unsafe { u8.MAX.unchecked_shl(7u32) } == 128u8) { panic("unchecked_shl #405") }
    if !(unsafe { u8.MAX.unchecked_shr(7u32) } == 1u8) { panic("unchecked_shr #406") }
    if !(u8.MAX.rotate_left(8u32) == u8.MAX) { panic("rotate_left #407") }
    if !(u8.MAX.rotate_right(8u32) == u8.MAX) { panic("rotate_right #408") }
    if !(missing(u8.MAX.checked_shl(8u32))) { panic("checked_shl #409") }
    if !(missing(u8.MAX.checked_shr(8u32))) { panic("checked_shr #410") }
    if !(u8.MAX.wrapping_shl(8u32) == u8.MAX) { panic("wrapping_shl #411") }
    if !(u8.MAX.wrapping_shr(8u32) == u8.MAX) { panic("wrapping_shr #412") }
    if !(u8.MAX.overflowing_shl(8u32).0 == u8.MAX && u8.MAX.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #413") }
    if !(u8.MAX.overflowing_shr(8u32).0 == u8.MAX && u8.MAX.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #414") }
    if !(u8.MAX.unbounded_shl(8u32) == 0u8) { panic("unbounded_shl #415") }
    if !(u8.MAX.unbounded_shr(8u32) == 0u8) { panic("unbounded_shr #416") }
    if !(u8.MAX.rotate_left(13u32) == u8.MAX) { panic("rotate_left #417") }
    if !(u8.MAX.rotate_right(13u32) == u8.MAX) { panic("rotate_right #418") }
    if !(missing(u8.MAX.checked_shl(13u32))) { panic("checked_shl #419") }
    if !(missing(u8.MAX.checked_shr(13u32))) { panic("checked_shr #420") }
    if !(u8.MAX.wrapping_shl(13u32) == 224u8) { panic("wrapping_shl #421") }
    if !(u8.MAX.wrapping_shr(13u32) == 7u8) { panic("wrapping_shr #422") }
    if !(u8.MAX.overflowing_shl(13u32).0 == 224u8 && u8.MAX.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #423") }
    if !(u8.MAX.overflowing_shr(13u32).0 == 7u8 && u8.MAX.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #424") }
    if !(u8.MAX.unbounded_shl(13u32) == 0u8) { panic("unbounded_shl #425") }
    if !(u8.MAX.unbounded_shr(13u32) == 0u8) { panic("unbounded_shr #426") }
    if !(u8.MAX.checked_pow(0u32) == present(1u8)) { panic("checked_pow #427") }
    if !(u8.MAX.wrapping_pow(0u32) == 1u8) { panic("wrapping_pow #428") }
    if !(u8.MAX.overflowing_pow(0u32).0 == 1u8 && u8.MAX.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #429") }
    if !(u8.MAX.saturating_pow(0u32) == 1u8) { panic("saturating_pow #430") }
    if !(u8.MAX.pow(0u32) == 1u8) { panic("pow #431") }
    if !(u8.MAX.strict_pow(0u32) == 1u8) { panic("strict_pow #432") }
    if !(u8.MAX.checked_pow(1u32) == present(u8.MAX)) { panic("checked_pow #433") }
    if !(u8.MAX.wrapping_pow(1u32) == u8.MAX) { panic("wrapping_pow #434") }
    if !(u8.MAX.overflowing_pow(1u32).0 == u8.MAX && u8.MAX.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #435") }
    if !(u8.MAX.saturating_pow(1u32) == u8.MAX) { panic("saturating_pow #436") }
    if !(u8.MAX.pow(1u32) == u8.MAX) { panic("pow #437") }
    if !(u8.MAX.strict_pow(1u32) == u8.MAX) { panic("strict_pow #438") }
    if !(missing(u8.MAX.checked_pow(2u32))) { panic("checked_pow #439") }
    if !(u8.MAX.wrapping_pow(2u32) == 1u8) { panic("wrapping_pow #440") }
    if !(u8.MAX.overflowing_pow(2u32).0 == 1u8 && u8.MAX.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #441") }
    if !(u8.MAX.saturating_pow(2u32) == u8.MAX) { panic("saturating_pow #442") }
    if !(missing(u8.MAX.checked_pow(3u32))) { panic("checked_pow #443") }
    if !(u8.MAX.wrapping_pow(3u32) == u8.MAX) { panic("wrapping_pow #444") }
    if !(u8.MAX.overflowing_pow(3u32).0 == u8.MAX && u8.MAX.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #445") }
    if !(u8.MAX.saturating_pow(3u32) == u8.MAX) { panic("saturating_pow #446") }
    if !(missing(u8.MAX.checked_pow(7u32))) { panic("checked_pow #447") }
    if !(u8.MAX.wrapping_pow(7u32) == u8.MAX) { panic("wrapping_pow #448") }
    if !(u8.MAX.overflowing_pow(7u32).0 == u8.MAX && u8.MAX.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #449") }
    if !(u8.MAX.saturating_pow(7u32) == u8.MAX) { panic("saturating_pow #450") }
    if !(missing(u8.MAX.checked_pow(8u32))) { panic("checked_pow #451") }
    if !(u8.MAX.wrapping_pow(8u32) == 1u8) { panic("wrapping_pow #452") }
    if !(u8.MAX.overflowing_pow(8u32).0 == 1u8 && u8.MAX.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #453") }
    if !(u8.MAX.saturating_pow(8u32) == u8.MAX) { panic("saturating_pow #454") }
    if !(u8.MAX.ilog2() == 7u32) { panic("ilog2 #455") }
    if !(u8.MAX.ilog10() == 2u32) { panic("ilog10 #456") }
    if !(u8.MAX.checked_ilog2() == present(7u32)) { panic("checked_ilog2 #457") }
    if !(u8.MAX.checked_ilog10() == present(2u32)) { panic("checked_ilog10 #458") }
    if !(u8.MAX.ilog(2u8) == 7u32) { panic("ilog #459") }
    if !(u8.MAX.checked_ilog(2u8) == present(7u32)) { panic("checked_ilog #460") }
    if !(u8.MAX.ilog(3u8) == 5u32) { panic("ilog #461") }
    if !(u8.MAX.checked_ilog(3u8) == present(5u32)) { panic("checked_ilog #462") }
    if !(u8.MAX.ilog(7u8) == 2u32) { panic("ilog #463") }
    if !(u8.MAX.checked_ilog(7u8) == present(2u32)) { panic("checked_ilog #464") }
    if !(missing(u8.MAX.checked_ilog(1u8))) { panic("checked_ilog #465") }
    if !(u8.MAX.isqrt() == 15u8) { panic("isqrt #466") }
    if !(u8.MAX.checked_isqrt() == present(15u8)) { panic("checked_isqrt #467") }
    if !(u8.MAX.is_power_of_two() == false) { panic("is_power_of_two #468") }
    if !(missing(u8.MAX.checked_next_power_of_two())) { panic("checked_next_power_of_two #469") }
    if !(u8.MAX.div_ceil(1u8) == u8.MAX) { panic("div_ceil #470") }
    if !(u8.MAX.checked_next_multiple_of(1u8) == present(u8.MAX)) { panic("checked_next_multiple_of #471") }
    if !(u8.MAX.next_multiple_of(1u8) == u8.MAX) { panic("next_multiple_of #472") }
    if !(u8.MAX.is_multiple_of(1u8) == true) { panic("is_multiple_of #473") }
    if !(u8.MAX.div_ceil(3u8) == 85u8) { panic("div_ceil #474") }
    if !(u8.MAX.checked_next_multiple_of(3u8) == present(u8.MAX)) { panic("checked_next_multiple_of #475") }
    if !(u8.MAX.next_multiple_of(3u8) == u8.MAX) { panic("next_multiple_of #476") }
    if !(u8.MAX.is_multiple_of(3u8) == true) { panic("is_multiple_of #477") }
    if !(u8.MAX.div_ceil(7u8) == 37u8) { panic("div_ceil #478") }
    if !(missing(u8.MAX.checked_next_multiple_of(7u8))) { panic("checked_next_multiple_of #479") }
    if !(u8.MAX.is_multiple_of(7u8) == false) { panic("is_multiple_of #480") }
}

fn group4() {
    if !(u8.MAX.is_multiple_of(0u8) == false) { panic("is_multiple_of #481") }
    if !(missing(u8.MAX.checked_next_multiple_of(0u8))) { panic("checked_next_multiple_of #482") }
    if !(u8.MAX.highest_one() == present(7u32)) { panic("highest_one #483") }
    if !(u8.MAX.lowest_one() == present(0u32)) { panic("lowest_one #484") }
    if !(u8.MAX.isolate_highest_one() == 128u8) { panic("isolate_highest_one #485") }
    if !(u8.MAX.isolate_lowest_one() == 1u8) { panic("isolate_lowest_one #486") }
    if !(u8.MAX.bit_width() == 8u32) { panic("bit_width #487") }
    if !(0u8.checked_neg() == present(0u8)) { panic("checked_neg #488") }
    if !(0u8.wrapping_neg() == 0u8) { panic("wrapping_neg #489") }
    if !(0u8.overflowing_neg().0 == 0u8 && 0u8.overflowing_neg().1 == false) { panic("overflowing_neg #490") }
    if !(0u8.strict_neg() == 0u8) { panic("strict_neg #491") }
    if !(0u8.cast_signed() == 0i8) { panic("cast_signed #492") }
    if !(0u8.count_ones() == 0u32) { panic("count_ones #493") }
    if !(0u8.count_zeros() == 8u32) { panic("count_zeros #494") }
    if !(0u8.leading_zeros() == 8u32) { panic("leading_zeros #495") }
    if !(0u8.trailing_zeros() == 8u32) { panic("trailing_zeros #496") }
    if !(0u8.leading_ones() == 0u32) { panic("leading_ones #497") }
    if !(0u8.trailing_ones() == 0u32) { panic("trailing_ones #498") }
    if !(0u8.reverse_bits() == 0u8) { panic("reverse_bits #499") }
    if !(0u8.swap_bytes() == 0u8) { panic("swap_bytes #500") }
    if !(0u8.to_be() == 0u8) { panic("to_be #501") }
    if !(0u8.to_le() == 0u8) { panic("to_le #502") }
    if !(u8.from_be(0u8) == 0u8) { panic("from_be #503") }
    if !(u8.from_le(0u8) == 0u8) { panic("from_le #504") }
    if !(0u8.to_le_bytes() == [0u8]) { panic("to_le_bytes #505") }
    if !(0u8.to_be_bytes() == [0u8]) { panic("to_be_bytes #506") }
    if !(0u8.to_ne_bytes() == [0u8]) { panic("to_ne_bytes #507") }
    if !(u8.from_le_bytes([0u8]) == 0u8) { panic("from_le_bytes #508") }
    if !(u8.from_be_bytes([0u8]) == 0u8) { panic("from_be_bytes #509") }
    if !(u8.from_ne_bytes([0u8]) == 0u8) { panic("from_ne_bytes #510") }
    if !(0u8.rotate_left(0u32) == 0u8) { panic("rotate_left #511") }
    if !(0u8.rotate_right(0u32) == 0u8) { panic("rotate_right #512") }
    if !(0u8.checked_shl(0u32) == present(0u8)) { panic("checked_shl #513") }
    if !(0u8.checked_shr(0u32) == present(0u8)) { panic("checked_shr #514") }
    if !(0u8.wrapping_shl(0u32) == 0u8) { panic("wrapping_shl #515") }
    if !(0u8.wrapping_shr(0u32) == 0u8) { panic("wrapping_shr #516") }
    if !(0u8.overflowing_shl(0u32).0 == 0u8 && 0u8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #517") }
    if !(0u8.overflowing_shr(0u32).0 == 0u8 && 0u8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #518") }
    if !(0u8.unbounded_shl(0u32) == 0u8) { panic("unbounded_shl #519") }
    if !(0u8.unbounded_shr(0u32) == 0u8) { panic("unbounded_shr #520") }
    if !(0u8.strict_shl(0u32) == 0u8) { panic("strict_shl #521") }
    if !(0u8.strict_shr(0u32) == 0u8) { panic("strict_shr #522") }
    if !(unsafe { 0u8.unchecked_shl(0u32) } == 0u8) { panic("unchecked_shl #523") }
    if !(unsafe { 0u8.unchecked_shr(0u32) } == 0u8) { panic("unchecked_shr #524") }
    if !(0u8.rotate_left(1u32) == 0u8) { panic("rotate_left #525") }
    if !(0u8.rotate_right(1u32) == 0u8) { panic("rotate_right #526") }
    if !(0u8.checked_shl(1u32) == present(0u8)) { panic("checked_shl #527") }
    if !(0u8.checked_shr(1u32) == present(0u8)) { panic("checked_shr #528") }
    if !(0u8.wrapping_shl(1u32) == 0u8) { panic("wrapping_shl #529") }
    if !(0u8.wrapping_shr(1u32) == 0u8) { panic("wrapping_shr #530") }
    if !(0u8.overflowing_shl(1u32).0 == 0u8 && 0u8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #531") }
    if !(0u8.overflowing_shr(1u32).0 == 0u8 && 0u8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #532") }
    if !(0u8.unbounded_shl(1u32) == 0u8) { panic("unbounded_shl #533") }
    if !(0u8.unbounded_shr(1u32) == 0u8) { panic("unbounded_shr #534") }
    if !(0u8.strict_shl(1u32) == 0u8) { panic("strict_shl #535") }
    if !(0u8.strict_shr(1u32) == 0u8) { panic("strict_shr #536") }
    if !(unsafe { 0u8.unchecked_shl(1u32) } == 0u8) { panic("unchecked_shl #537") }
    if !(unsafe { 0u8.unchecked_shr(1u32) } == 0u8) { panic("unchecked_shr #538") }
    if !(0u8.rotate_left(3u32) == 0u8) { panic("rotate_left #539") }
    if !(0u8.rotate_right(3u32) == 0u8) { panic("rotate_right #540") }
    if !(0u8.checked_shl(3u32) == present(0u8)) { panic("checked_shl #541") }
    if !(0u8.checked_shr(3u32) == present(0u8)) { panic("checked_shr #542") }
    if !(0u8.wrapping_shl(3u32) == 0u8) { panic("wrapping_shl #543") }
    if !(0u8.wrapping_shr(3u32) == 0u8) { panic("wrapping_shr #544") }
    if !(0u8.overflowing_shl(3u32).0 == 0u8 && 0u8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #545") }
    if !(0u8.overflowing_shr(3u32).0 == 0u8 && 0u8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #546") }
    if !(0u8.unbounded_shl(3u32) == 0u8) { panic("unbounded_shl #547") }
    if !(0u8.unbounded_shr(3u32) == 0u8) { panic("unbounded_shr #548") }
    if !(0u8.strict_shl(3u32) == 0u8) { panic("strict_shl #549") }
    if !(0u8.strict_shr(3u32) == 0u8) { panic("strict_shr #550") }
    if !(unsafe { 0u8.unchecked_shl(3u32) } == 0u8) { panic("unchecked_shl #551") }
    if !(unsafe { 0u8.unchecked_shr(3u32) } == 0u8) { panic("unchecked_shr #552") }
    if !(0u8.rotate_left(7u32) == 0u8) { panic("rotate_left #553") }
    if !(0u8.rotate_right(7u32) == 0u8) { panic("rotate_right #554") }
    if !(0u8.checked_shl(7u32) == present(0u8)) { panic("checked_shl #555") }
    if !(0u8.checked_shr(7u32) == present(0u8)) { panic("checked_shr #556") }
    if !(0u8.wrapping_shl(7u32) == 0u8) { panic("wrapping_shl #557") }
    if !(0u8.wrapping_shr(7u32) == 0u8) { panic("wrapping_shr #558") }
    if !(0u8.overflowing_shl(7u32).0 == 0u8 && 0u8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #559") }
    if !(0u8.overflowing_shr(7u32).0 == 0u8 && 0u8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #560") }
    if !(0u8.unbounded_shl(7u32) == 0u8) { panic("unbounded_shl #561") }
    if !(0u8.unbounded_shr(7u32) == 0u8) { panic("unbounded_shr #562") }
    if !(0u8.strict_shl(7u32) == 0u8) { panic("strict_shl #563") }
    if !(0u8.strict_shr(7u32) == 0u8) { panic("strict_shr #564") }
    if !(unsafe { 0u8.unchecked_shl(7u32) } == 0u8) { panic("unchecked_shl #565") }
    if !(unsafe { 0u8.unchecked_shr(7u32) } == 0u8) { panic("unchecked_shr #566") }
    if !(0u8.rotate_left(8u32) == 0u8) { panic("rotate_left #567") }
    if !(0u8.rotate_right(8u32) == 0u8) { panic("rotate_right #568") }
    if !(missing(0u8.checked_shl(8u32))) { panic("checked_shl #569") }
    if !(missing(0u8.checked_shr(8u32))) { panic("checked_shr #570") }
    if !(0u8.wrapping_shl(8u32) == 0u8) { panic("wrapping_shl #571") }
    if !(0u8.wrapping_shr(8u32) == 0u8) { panic("wrapping_shr #572") }
    if !(0u8.overflowing_shl(8u32).0 == 0u8 && 0u8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #573") }
    if !(0u8.overflowing_shr(8u32).0 == 0u8 && 0u8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #574") }
    if !(0u8.unbounded_shl(8u32) == 0u8) { panic("unbounded_shl #575") }
    if !(0u8.unbounded_shr(8u32) == 0u8) { panic("unbounded_shr #576") }
    if !(0u8.rotate_left(13u32) == 0u8) { panic("rotate_left #577") }
    if !(0u8.rotate_right(13u32) == 0u8) { panic("rotate_right #578") }
    if !(missing(0u8.checked_shl(13u32))) { panic("checked_shl #579") }
    if !(missing(0u8.checked_shr(13u32))) { panic("checked_shr #580") }
    if !(0u8.wrapping_shl(13u32) == 0u8) { panic("wrapping_shl #581") }
    if !(0u8.wrapping_shr(13u32) == 0u8) { panic("wrapping_shr #582") }
    if !(0u8.overflowing_shl(13u32).0 == 0u8 && 0u8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #583") }
    if !(0u8.overflowing_shr(13u32).0 == 0u8 && 0u8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #584") }
    if !(0u8.unbounded_shl(13u32) == 0u8) { panic("unbounded_shl #585") }
    if !(0u8.unbounded_shr(13u32) == 0u8) { panic("unbounded_shr #586") }
    if !(0u8.checked_pow(0u32) == present(1u8)) { panic("checked_pow #587") }
    if !(0u8.wrapping_pow(0u32) == 1u8) { panic("wrapping_pow #588") }
    if !(0u8.overflowing_pow(0u32).0 == 1u8 && 0u8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #589") }
    if !(0u8.saturating_pow(0u32) == 1u8) { panic("saturating_pow #590") }
    if !(0u8.pow(0u32) == 1u8) { panic("pow #591") }
    if !(0u8.strict_pow(0u32) == 1u8) { panic("strict_pow #592") }
    if !(0u8.checked_pow(1u32) == present(0u8)) { panic("checked_pow #593") }
    if !(0u8.wrapping_pow(1u32) == 0u8) { panic("wrapping_pow #594") }
    if !(0u8.overflowing_pow(1u32).0 == 0u8 && 0u8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #595") }
    if !(0u8.saturating_pow(1u32) == 0u8) { panic("saturating_pow #596") }
    if !(0u8.pow(1u32) == 0u8) { panic("pow #597") }
    if !(0u8.strict_pow(1u32) == 0u8) { panic("strict_pow #598") }
    if !(0u8.checked_pow(2u32) == present(0u8)) { panic("checked_pow #599") }
    if !(0u8.wrapping_pow(2u32) == 0u8) { panic("wrapping_pow #600") }
}

fn group5() {
    if !(0u8.overflowing_pow(2u32).0 == 0u8 && 0u8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #601") }
    if !(0u8.saturating_pow(2u32) == 0u8) { panic("saturating_pow #602") }
    if !(0u8.pow(2u32) == 0u8) { panic("pow #603") }
    if !(0u8.strict_pow(2u32) == 0u8) { panic("strict_pow #604") }
    if !(0u8.checked_pow(3u32) == present(0u8)) { panic("checked_pow #605") }
    if !(0u8.wrapping_pow(3u32) == 0u8) { panic("wrapping_pow #606") }
    if !(0u8.overflowing_pow(3u32).0 == 0u8 && 0u8.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #607") }
    if !(0u8.saturating_pow(3u32) == 0u8) { panic("saturating_pow #608") }
    if !(0u8.pow(3u32) == 0u8) { panic("pow #609") }
    if !(0u8.strict_pow(3u32) == 0u8) { panic("strict_pow #610") }
    if !(0u8.checked_pow(7u32) == present(0u8)) { panic("checked_pow #611") }
    if !(0u8.wrapping_pow(7u32) == 0u8) { panic("wrapping_pow #612") }
    if !(0u8.overflowing_pow(7u32).0 == 0u8 && 0u8.overflowing_pow(7u32).1 == false) { panic("overflowing_pow #613") }
    if !(0u8.saturating_pow(7u32) == 0u8) { panic("saturating_pow #614") }
    if !(0u8.pow(7u32) == 0u8) { panic("pow #615") }
    if !(0u8.strict_pow(7u32) == 0u8) { panic("strict_pow #616") }
    if !(0u8.checked_pow(8u32) == present(0u8)) { panic("checked_pow #617") }
    if !(0u8.wrapping_pow(8u32) == 0u8) { panic("wrapping_pow #618") }
    if !(0u8.overflowing_pow(8u32).0 == 0u8 && 0u8.overflowing_pow(8u32).1 == false) { panic("overflowing_pow #619") }
    if !(0u8.saturating_pow(8u32) == 0u8) { panic("saturating_pow #620") }
    if !(0u8.pow(8u32) == 0u8) { panic("pow #621") }
    if !(0u8.strict_pow(8u32) == 0u8) { panic("strict_pow #622") }
    if !(missing(0u8.checked_ilog2())) { panic("checked_ilog2 #623") }
    if !(missing(0u8.checked_ilog10())) { panic("checked_ilog10 #624") }
    if !(missing(0u8.checked_ilog(2u8))) { panic("checked_ilog #625") }
    if !(0u8.isqrt() == 0u8) { panic("isqrt #626") }
    if !(0u8.checked_isqrt() == present(0u8)) { panic("checked_isqrt #627") }
    if !(0u8.is_power_of_two() == false) { panic("is_power_of_two #628") }
    if !(0u8.checked_next_power_of_two() == present(1u8)) { panic("checked_next_power_of_two #629") }
    if !(0u8.next_power_of_two() == 1u8) { panic("next_power_of_two #630") }
    if !(0u8.div_ceil(1u8) == 0u8) { panic("div_ceil #631") }
    if !(0u8.checked_next_multiple_of(1u8) == present(0u8)) { panic("checked_next_multiple_of #632") }
    if !(0u8.next_multiple_of(1u8) == 0u8) { panic("next_multiple_of #633") }
    if !(0u8.is_multiple_of(1u8) == true) { panic("is_multiple_of #634") }
    if !(0u8.div_ceil(3u8) == 0u8) { panic("div_ceil #635") }
    if !(0u8.checked_next_multiple_of(3u8) == present(0u8)) { panic("checked_next_multiple_of #636") }
    if !(0u8.next_multiple_of(3u8) == 0u8) { panic("next_multiple_of #637") }
    if !(0u8.is_multiple_of(3u8) == true) { panic("is_multiple_of #638") }
    if !(0u8.div_ceil(7u8) == 0u8) { panic("div_ceil #639") }
    if !(0u8.checked_next_multiple_of(7u8) == present(0u8)) { panic("checked_next_multiple_of #640") }
    if !(0u8.next_multiple_of(7u8) == 0u8) { panic("next_multiple_of #641") }
    if !(0u8.is_multiple_of(7u8) == true) { panic("is_multiple_of #642") }
    if !(0u8.is_multiple_of(0u8) == true) { panic("is_multiple_of #643") }
    if !(missing(0u8.checked_next_multiple_of(0u8))) { panic("checked_next_multiple_of #644") }
    if !(missing(0u8.highest_one())) { panic("highest_one #645") }
    if !(missing(0u8.lowest_one())) { panic("lowest_one #646") }
    if !(0u8.isolate_highest_one() == 0u8) { panic("isolate_highest_one #647") }
    if !(0u8.isolate_lowest_one() == 0u8) { panic("isolate_lowest_one #648") }
    if !(0u8.bit_width() == 0u32) { panic("bit_width #649") }
    if !(missing(3u8.checked_neg())) { panic("checked_neg #650") }
    if !(3u8.wrapping_neg() == 253u8) { panic("wrapping_neg #651") }
    if !(3u8.overflowing_neg().0 == 253u8 && 3u8.overflowing_neg().1 == true) { panic("overflowing_neg #652") }
    if !(3u8.cast_signed() == 3i8) { panic("cast_signed #653") }
    if !(3u8.count_ones() == 2u32) { panic("count_ones #654") }
    if !(3u8.count_zeros() == 6u32) { panic("count_zeros #655") }
    if !(3u8.leading_zeros() == 6u32) { panic("leading_zeros #656") }
    if !(3u8.trailing_zeros() == 0u32) { panic("trailing_zeros #657") }
    if !(3u8.leading_ones() == 0u32) { panic("leading_ones #658") }
    if !(3u8.trailing_ones() == 2u32) { panic("trailing_ones #659") }
    if !(3u8.reverse_bits() == 192u8) { panic("reverse_bits #660") }
    if !(3u8.swap_bytes() == 3u8) { panic("swap_bytes #661") }
    if !(3u8.to_be() == 3u8) { panic("to_be #662") }
    if !(3u8.to_le() == 3u8) { panic("to_le #663") }
    if !(u8.from_be(3u8) == 3u8) { panic("from_be #664") }
    if !(u8.from_le(3u8) == 3u8) { panic("from_le #665") }
    if !(3u8.to_le_bytes() == [3u8]) { panic("to_le_bytes #666") }
    if !(3u8.to_be_bytes() == [3u8]) { panic("to_be_bytes #667") }
    if !(3u8.to_ne_bytes() == [3u8]) { panic("to_ne_bytes #668") }
    if !(u8.from_le_bytes([3u8]) == 3u8) { panic("from_le_bytes #669") }
    if !(u8.from_be_bytes([3u8]) == 3u8) { panic("from_be_bytes #670") }
    if !(u8.from_ne_bytes([3u8]) == 3u8) { panic("from_ne_bytes #671") }
    if !(3u8.rotate_left(0u32) == 3u8) { panic("rotate_left #672") }
    if !(3u8.rotate_right(0u32) == 3u8) { panic("rotate_right #673") }
    if !(3u8.checked_shl(0u32) == present(3u8)) { panic("checked_shl #674") }
    if !(3u8.checked_shr(0u32) == present(3u8)) { panic("checked_shr #675") }
    if !(3u8.wrapping_shl(0u32) == 3u8) { panic("wrapping_shl #676") }
    if !(3u8.wrapping_shr(0u32) == 3u8) { panic("wrapping_shr #677") }
    if !(3u8.overflowing_shl(0u32).0 == 3u8 && 3u8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #678") }
    if !(3u8.overflowing_shr(0u32).0 == 3u8 && 3u8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #679") }
    if !(3u8.unbounded_shl(0u32) == 3u8) { panic("unbounded_shl #680") }
    if !(3u8.unbounded_shr(0u32) == 3u8) { panic("unbounded_shr #681") }
    if !(3u8.strict_shl(0u32) == 3u8) { panic("strict_shl #682") }
    if !(3u8.strict_shr(0u32) == 3u8) { panic("strict_shr #683") }
    if !(unsafe { 3u8.unchecked_shl(0u32) } == 3u8) { panic("unchecked_shl #684") }
    if !(unsafe { 3u8.unchecked_shr(0u32) } == 3u8) { panic("unchecked_shr #685") }
    if !(3u8.rotate_left(1u32) == 6u8) { panic("rotate_left #686") }
    if !(3u8.rotate_right(1u32) == 129u8) { panic("rotate_right #687") }
    if !(3u8.checked_shl(1u32) == present(6u8)) { panic("checked_shl #688") }
    if !(3u8.checked_shr(1u32) == present(1u8)) { panic("checked_shr #689") }
    if !(3u8.wrapping_shl(1u32) == 6u8) { panic("wrapping_shl #690") }
    if !(3u8.wrapping_shr(1u32) == 1u8) { panic("wrapping_shr #691") }
    if !(3u8.overflowing_shl(1u32).0 == 6u8 && 3u8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #692") }
    if !(3u8.overflowing_shr(1u32).0 == 1u8 && 3u8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #693") }
    if !(3u8.unbounded_shl(1u32) == 6u8) { panic("unbounded_shl #694") }
    if !(3u8.unbounded_shr(1u32) == 1u8) { panic("unbounded_shr #695") }
    if !(3u8.strict_shl(1u32) == 6u8) { panic("strict_shl #696") }
    if !(3u8.strict_shr(1u32) == 1u8) { panic("strict_shr #697") }
    if !(unsafe { 3u8.unchecked_shl(1u32) } == 6u8) { panic("unchecked_shl #698") }
    if !(unsafe { 3u8.unchecked_shr(1u32) } == 1u8) { panic("unchecked_shr #699") }
    if !(3u8.rotate_left(3u32) == 24u8) { panic("rotate_left #700") }
    if !(3u8.rotate_right(3u32) == 96u8) { panic("rotate_right #701") }
    if !(3u8.checked_shl(3u32) == present(24u8)) { panic("checked_shl #702") }
    if !(3u8.checked_shr(3u32) == present(0u8)) { panic("checked_shr #703") }
    if !(3u8.wrapping_shl(3u32) == 24u8) { panic("wrapping_shl #704") }
    if !(3u8.wrapping_shr(3u32) == 0u8) { panic("wrapping_shr #705") }
    if !(3u8.overflowing_shl(3u32).0 == 24u8 && 3u8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #706") }
    if !(3u8.overflowing_shr(3u32).0 == 0u8 && 3u8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #707") }
    if !(3u8.unbounded_shl(3u32) == 24u8) { panic("unbounded_shl #708") }
    if !(3u8.unbounded_shr(3u32) == 0u8) { panic("unbounded_shr #709") }
    if !(3u8.strict_shl(3u32) == 24u8) { panic("strict_shl #710") }
    if !(3u8.strict_shr(3u32) == 0u8) { panic("strict_shr #711") }
    if !(unsafe { 3u8.unchecked_shl(3u32) } == 24u8) { panic("unchecked_shl #712") }
    if !(unsafe { 3u8.unchecked_shr(3u32) } == 0u8) { panic("unchecked_shr #713") }
    if !(3u8.rotate_left(7u32) == 129u8) { panic("rotate_left #714") }
    if !(3u8.rotate_right(7u32) == 6u8) { panic("rotate_right #715") }
    if !(3u8.checked_shl(7u32) == present(128u8)) { panic("checked_shl #716") }
    if !(3u8.checked_shr(7u32) == present(0u8)) { panic("checked_shr #717") }
    if !(3u8.wrapping_shl(7u32) == 128u8) { panic("wrapping_shl #718") }
    if !(3u8.wrapping_shr(7u32) == 0u8) { panic("wrapping_shr #719") }
    if !(3u8.overflowing_shl(7u32).0 == 128u8 && 3u8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #720") }
}

fn group6() {
    if !(3u8.overflowing_shr(7u32).0 == 0u8 && 3u8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #721") }
    if !(3u8.unbounded_shl(7u32) == 128u8) { panic("unbounded_shl #722") }
    if !(3u8.unbounded_shr(7u32) == 0u8) { panic("unbounded_shr #723") }
    if !(3u8.strict_shl(7u32) == 128u8) { panic("strict_shl #724") }
    if !(3u8.strict_shr(7u32) == 0u8) { panic("strict_shr #725") }
    if !(unsafe { 3u8.unchecked_shl(7u32) } == 128u8) { panic("unchecked_shl #726") }
    if !(unsafe { 3u8.unchecked_shr(7u32) } == 0u8) { panic("unchecked_shr #727") }
    if !(3u8.rotate_left(8u32) == 3u8) { panic("rotate_left #728") }
    if !(3u8.rotate_right(8u32) == 3u8) { panic("rotate_right #729") }
    if !(missing(3u8.checked_shl(8u32))) { panic("checked_shl #730") }
    if !(missing(3u8.checked_shr(8u32))) { panic("checked_shr #731") }
    if !(3u8.wrapping_shl(8u32) == 3u8) { panic("wrapping_shl #732") }
    if !(3u8.wrapping_shr(8u32) == 3u8) { panic("wrapping_shr #733") }
    if !(3u8.overflowing_shl(8u32).0 == 3u8 && 3u8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #734") }
    if !(3u8.overflowing_shr(8u32).0 == 3u8 && 3u8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #735") }
    if !(3u8.unbounded_shl(8u32) == 0u8) { panic("unbounded_shl #736") }
    if !(3u8.unbounded_shr(8u32) == 0u8) { panic("unbounded_shr #737") }
    if !(3u8.rotate_left(13u32) == 96u8) { panic("rotate_left #738") }
    if !(3u8.rotate_right(13u32) == 24u8) { panic("rotate_right #739") }
    if !(missing(3u8.checked_shl(13u32))) { panic("checked_shl #740") }
    if !(missing(3u8.checked_shr(13u32))) { panic("checked_shr #741") }
    if !(3u8.wrapping_shl(13u32) == 96u8) { panic("wrapping_shl #742") }
    if !(3u8.wrapping_shr(13u32) == 0u8) { panic("wrapping_shr #743") }
    if !(3u8.overflowing_shl(13u32).0 == 96u8 && 3u8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #744") }
    if !(3u8.overflowing_shr(13u32).0 == 0u8 && 3u8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #745") }
    if !(3u8.unbounded_shl(13u32) == 0u8) { panic("unbounded_shl #746") }
    if !(3u8.unbounded_shr(13u32) == 0u8) { panic("unbounded_shr #747") }
    if !(3u8.checked_pow(0u32) == present(1u8)) { panic("checked_pow #748") }
    if !(3u8.wrapping_pow(0u32) == 1u8) { panic("wrapping_pow #749") }
    if !(3u8.overflowing_pow(0u32).0 == 1u8 && 3u8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #750") }
    if !(3u8.saturating_pow(0u32) == 1u8) { panic("saturating_pow #751") }
    if !(3u8.pow(0u32) == 1u8) { panic("pow #752") }
    if !(3u8.strict_pow(0u32) == 1u8) { panic("strict_pow #753") }
    if !(3u8.checked_pow(1u32) == present(3u8)) { panic("checked_pow #754") }
    if !(3u8.wrapping_pow(1u32) == 3u8) { panic("wrapping_pow #755") }
    if !(3u8.overflowing_pow(1u32).0 == 3u8 && 3u8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #756") }
    if !(3u8.saturating_pow(1u32) == 3u8) { panic("saturating_pow #757") }
    if !(3u8.pow(1u32) == 3u8) { panic("pow #758") }
    if !(3u8.strict_pow(1u32) == 3u8) { panic("strict_pow #759") }
    if !(3u8.checked_pow(2u32) == present(9u8)) { panic("checked_pow #760") }
    if !(3u8.wrapping_pow(2u32) == 9u8) { panic("wrapping_pow #761") }
    if !(3u8.overflowing_pow(2u32).0 == 9u8 && 3u8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #762") }
    if !(3u8.saturating_pow(2u32) == 9u8) { panic("saturating_pow #763") }
    if !(3u8.pow(2u32) == 9u8) { panic("pow #764") }
    if !(3u8.strict_pow(2u32) == 9u8) { panic("strict_pow #765") }
    if !(3u8.checked_pow(3u32) == present(27u8)) { panic("checked_pow #766") }
    if !(3u8.wrapping_pow(3u32) == 27u8) { panic("wrapping_pow #767") }
    if !(3u8.overflowing_pow(3u32).0 == 27u8 && 3u8.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #768") }
    if !(3u8.saturating_pow(3u32) == 27u8) { panic("saturating_pow #769") }
    if !(3u8.pow(3u32) == 27u8) { panic("pow #770") }
    if !(3u8.strict_pow(3u32) == 27u8) { panic("strict_pow #771") }
    if !(missing(3u8.checked_pow(7u32))) { panic("checked_pow #772") }
    if !(3u8.wrapping_pow(7u32) == 139u8) { panic("wrapping_pow #773") }
    if !(3u8.overflowing_pow(7u32).0 == 139u8 && 3u8.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #774") }
    if !(3u8.saturating_pow(7u32) == u8.MAX) { panic("saturating_pow #775") }
    if !(missing(3u8.checked_pow(8u32))) { panic("checked_pow #776") }
    if !(3u8.wrapping_pow(8u32) == 161u8) { panic("wrapping_pow #777") }
    if !(3u8.overflowing_pow(8u32).0 == 161u8 && 3u8.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #778") }
    if !(3u8.saturating_pow(8u32) == u8.MAX) { panic("saturating_pow #779") }
    if !(3u8.ilog2() == 1u32) { panic("ilog2 #780") }
    if !(3u8.ilog10() == 0u32) { panic("ilog10 #781") }
    if !(3u8.checked_ilog2() == present(1u32)) { panic("checked_ilog2 #782") }
    if !(3u8.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #783") }
    if !(3u8.ilog(2u8) == 1u32) { panic("ilog #784") }
    if !(3u8.checked_ilog(2u8) == present(1u32)) { panic("checked_ilog #785") }
    if !(3u8.ilog(3u8) == 1u32) { panic("ilog #786") }
    if !(3u8.checked_ilog(3u8) == present(1u32)) { panic("checked_ilog #787") }
    if !(3u8.ilog(7u8) == 0u32) { panic("ilog #788") }
    if !(3u8.checked_ilog(7u8) == present(0u32)) { panic("checked_ilog #789") }
    if !(missing(3u8.checked_ilog(1u8))) { panic("checked_ilog #790") }
    if !(3u8.isqrt() == 1u8) { panic("isqrt #791") }
    if !(3u8.checked_isqrt() == present(1u8)) { panic("checked_isqrt #792") }
    if !(3u8.is_power_of_two() == false) { panic("is_power_of_two #793") }
    if !(3u8.checked_next_power_of_two() == present(4u8)) { panic("checked_next_power_of_two #794") }
    if !(3u8.next_power_of_two() == 4u8) { panic("next_power_of_two #795") }
    if !(3u8.div_ceil(1u8) == 3u8) { panic("div_ceil #796") }
    if !(3u8.checked_next_multiple_of(1u8) == present(3u8)) { panic("checked_next_multiple_of #797") }
    if !(3u8.next_multiple_of(1u8) == 3u8) { panic("next_multiple_of #798") }
    if !(3u8.is_multiple_of(1u8) == true) { panic("is_multiple_of #799") }
    if !(3u8.div_ceil(3u8) == 1u8) { panic("div_ceil #800") }
    if !(3u8.checked_next_multiple_of(3u8) == present(3u8)) { panic("checked_next_multiple_of #801") }
    if !(3u8.next_multiple_of(3u8) == 3u8) { panic("next_multiple_of #802") }
    if !(3u8.is_multiple_of(3u8) == true) { panic("is_multiple_of #803") }
    if !(3u8.div_ceil(7u8) == 1u8) { panic("div_ceil #804") }
    if !(3u8.checked_next_multiple_of(7u8) == present(7u8)) { panic("checked_next_multiple_of #805") }
    if !(3u8.next_multiple_of(7u8) == 7u8) { panic("next_multiple_of #806") }
    if !(3u8.is_multiple_of(7u8) == false) { panic("is_multiple_of #807") }
    if !(3u8.is_multiple_of(0u8) == false) { panic("is_multiple_of #808") }
    if !(missing(3u8.checked_next_multiple_of(0u8))) { panic("checked_next_multiple_of #809") }
    if !(3u8.highest_one() == present(1u32)) { panic("highest_one #810") }
    if !(3u8.lowest_one() == present(0u32)) { panic("lowest_one #811") }
    if !(3u8.isolate_highest_one() == 2u8) { panic("isolate_highest_one #812") }
    if !(3u8.isolate_lowest_one() == 1u8) { panic("isolate_lowest_one #813") }
    if !(3u8.bit_width() == 2u32) { panic("bit_width #814") }
    if !(missing(7u8.checked_neg())) { panic("checked_neg #815") }
    if !(7u8.wrapping_neg() == 249u8) { panic("wrapping_neg #816") }
    if !(7u8.overflowing_neg().0 == 249u8 && 7u8.overflowing_neg().1 == true) { panic("overflowing_neg #817") }
    if !(7u8.cast_signed() == 7i8) { panic("cast_signed #818") }
    if !(7u8.count_ones() == 3u32) { panic("count_ones #819") }
    if !(7u8.count_zeros() == 5u32) { panic("count_zeros #820") }
    if !(7u8.leading_zeros() == 5u32) { panic("leading_zeros #821") }
    if !(7u8.trailing_zeros() == 0u32) { panic("trailing_zeros #822") }
    if !(7u8.leading_ones() == 0u32) { panic("leading_ones #823") }
    if !(7u8.trailing_ones() == 3u32) { panic("trailing_ones #824") }
    if !(7u8.reverse_bits() == 224u8) { panic("reverse_bits #825") }
    if !(7u8.swap_bytes() == 7u8) { panic("swap_bytes #826") }
    if !(7u8.to_be() == 7u8) { panic("to_be #827") }
    if !(7u8.to_le() == 7u8) { panic("to_le #828") }
    if !(u8.from_be(7u8) == 7u8) { panic("from_be #829") }
    if !(u8.from_le(7u8) == 7u8) { panic("from_le #830") }
    if !(7u8.to_le_bytes() == [7u8]) { panic("to_le_bytes #831") }
    if !(7u8.to_be_bytes() == [7u8]) { panic("to_be_bytes #832") }
    if !(7u8.to_ne_bytes() == [7u8]) { panic("to_ne_bytes #833") }
    if !(u8.from_le_bytes([7u8]) == 7u8) { panic("from_le_bytes #834") }
    if !(u8.from_be_bytes([7u8]) == 7u8) { panic("from_be_bytes #835") }
    if !(u8.from_ne_bytes([7u8]) == 7u8) { panic("from_ne_bytes #836") }
    if !(7u8.rotate_left(0u32) == 7u8) { panic("rotate_left #837") }
    if !(7u8.rotate_right(0u32) == 7u8) { panic("rotate_right #838") }
    if !(7u8.checked_shl(0u32) == present(7u8)) { panic("checked_shl #839") }
    if !(7u8.checked_shr(0u32) == present(7u8)) { panic("checked_shr #840") }
}

fn group7() {
    if !(7u8.wrapping_shl(0u32) == 7u8) { panic("wrapping_shl #841") }
    if !(7u8.wrapping_shr(0u32) == 7u8) { panic("wrapping_shr #842") }
    if !(7u8.overflowing_shl(0u32).0 == 7u8 && 7u8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #843") }
    if !(7u8.overflowing_shr(0u32).0 == 7u8 && 7u8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #844") }
    if !(7u8.unbounded_shl(0u32) == 7u8) { panic("unbounded_shl #845") }
    if !(7u8.unbounded_shr(0u32) == 7u8) { panic("unbounded_shr #846") }
    if !(7u8.strict_shl(0u32) == 7u8) { panic("strict_shl #847") }
    if !(7u8.strict_shr(0u32) == 7u8) { panic("strict_shr #848") }
    if !(unsafe { 7u8.unchecked_shl(0u32) } == 7u8) { panic("unchecked_shl #849") }
    if !(unsafe { 7u8.unchecked_shr(0u32) } == 7u8) { panic("unchecked_shr #850") }
    if !(7u8.rotate_left(1u32) == 14u8) { panic("rotate_left #851") }
    if !(7u8.rotate_right(1u32) == 131u8) { panic("rotate_right #852") }
    if !(7u8.checked_shl(1u32) == present(14u8)) { panic("checked_shl #853") }
    if !(7u8.checked_shr(1u32) == present(3u8)) { panic("checked_shr #854") }
    if !(7u8.wrapping_shl(1u32) == 14u8) { panic("wrapping_shl #855") }
    if !(7u8.wrapping_shr(1u32) == 3u8) { panic("wrapping_shr #856") }
    if !(7u8.overflowing_shl(1u32).0 == 14u8 && 7u8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #857") }
    if !(7u8.overflowing_shr(1u32).0 == 3u8 && 7u8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #858") }
    if !(7u8.unbounded_shl(1u32) == 14u8) { panic("unbounded_shl #859") }
    if !(7u8.unbounded_shr(1u32) == 3u8) { panic("unbounded_shr #860") }
    if !(7u8.strict_shl(1u32) == 14u8) { panic("strict_shl #861") }
    if !(7u8.strict_shr(1u32) == 3u8) { panic("strict_shr #862") }
    if !(unsafe { 7u8.unchecked_shl(1u32) } == 14u8) { panic("unchecked_shl #863") }
    if !(unsafe { 7u8.unchecked_shr(1u32) } == 3u8) { panic("unchecked_shr #864") }
    if !(7u8.rotate_left(3u32) == 56u8) { panic("rotate_left #865") }
    if !(7u8.rotate_right(3u32) == 224u8) { panic("rotate_right #866") }
    if !(7u8.checked_shl(3u32) == present(56u8)) { panic("checked_shl #867") }
    if !(7u8.checked_shr(3u32) == present(0u8)) { panic("checked_shr #868") }
    if !(7u8.wrapping_shl(3u32) == 56u8) { panic("wrapping_shl #869") }
    if !(7u8.wrapping_shr(3u32) == 0u8) { panic("wrapping_shr #870") }
    if !(7u8.overflowing_shl(3u32).0 == 56u8 && 7u8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #871") }
    if !(7u8.overflowing_shr(3u32).0 == 0u8 && 7u8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #872") }
    if !(7u8.unbounded_shl(3u32) == 56u8) { panic("unbounded_shl #873") }
    if !(7u8.unbounded_shr(3u32) == 0u8) { panic("unbounded_shr #874") }
    if !(7u8.strict_shl(3u32) == 56u8) { panic("strict_shl #875") }
    if !(7u8.strict_shr(3u32) == 0u8) { panic("strict_shr #876") }
    if !(unsafe { 7u8.unchecked_shl(3u32) } == 56u8) { panic("unchecked_shl #877") }
    if !(unsafe { 7u8.unchecked_shr(3u32) } == 0u8) { panic("unchecked_shr #878") }
    if !(7u8.rotate_left(7u32) == 131u8) { panic("rotate_left #879") }
    if !(7u8.rotate_right(7u32) == 14u8) { panic("rotate_right #880") }
    if !(7u8.checked_shl(7u32) == present(128u8)) { panic("checked_shl #881") }
    if !(7u8.checked_shr(7u32) == present(0u8)) { panic("checked_shr #882") }
    if !(7u8.wrapping_shl(7u32) == 128u8) { panic("wrapping_shl #883") }
    if !(7u8.wrapping_shr(7u32) == 0u8) { panic("wrapping_shr #884") }
    if !(7u8.overflowing_shl(7u32).0 == 128u8 && 7u8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #885") }
    if !(7u8.overflowing_shr(7u32).0 == 0u8 && 7u8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #886") }
    if !(7u8.unbounded_shl(7u32) == 128u8) { panic("unbounded_shl #887") }
    if !(7u8.unbounded_shr(7u32) == 0u8) { panic("unbounded_shr #888") }
    if !(7u8.strict_shl(7u32) == 128u8) { panic("strict_shl #889") }
    if !(7u8.strict_shr(7u32) == 0u8) { panic("strict_shr #890") }
    if !(unsafe { 7u8.unchecked_shl(7u32) } == 128u8) { panic("unchecked_shl #891") }
    if !(unsafe { 7u8.unchecked_shr(7u32) } == 0u8) { panic("unchecked_shr #892") }
    if !(7u8.rotate_left(8u32) == 7u8) { panic("rotate_left #893") }
    if !(7u8.rotate_right(8u32) == 7u8) { panic("rotate_right #894") }
    if !(missing(7u8.checked_shl(8u32))) { panic("checked_shl #895") }
    if !(missing(7u8.checked_shr(8u32))) { panic("checked_shr #896") }
    if !(7u8.wrapping_shl(8u32) == 7u8) { panic("wrapping_shl #897") }
    if !(7u8.wrapping_shr(8u32) == 7u8) { panic("wrapping_shr #898") }
    if !(7u8.overflowing_shl(8u32).0 == 7u8 && 7u8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #899") }
    if !(7u8.overflowing_shr(8u32).0 == 7u8 && 7u8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #900") }
    if !(7u8.unbounded_shl(8u32) == 0u8) { panic("unbounded_shl #901") }
    if !(7u8.unbounded_shr(8u32) == 0u8) { panic("unbounded_shr #902") }
    if !(7u8.rotate_left(13u32) == 224u8) { panic("rotate_left #903") }
    if !(7u8.rotate_right(13u32) == 56u8) { panic("rotate_right #904") }
    if !(missing(7u8.checked_shl(13u32))) { panic("checked_shl #905") }
    if !(missing(7u8.checked_shr(13u32))) { panic("checked_shr #906") }
    if !(7u8.wrapping_shl(13u32) == 224u8) { panic("wrapping_shl #907") }
    if !(7u8.wrapping_shr(13u32) == 0u8) { panic("wrapping_shr #908") }
    if !(7u8.overflowing_shl(13u32).0 == 224u8 && 7u8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #909") }
    if !(7u8.overflowing_shr(13u32).0 == 0u8 && 7u8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #910") }
    if !(7u8.unbounded_shl(13u32) == 0u8) { panic("unbounded_shl #911") }
    if !(7u8.unbounded_shr(13u32) == 0u8) { panic("unbounded_shr #912") }
    if !(7u8.checked_pow(0u32) == present(1u8)) { panic("checked_pow #913") }
    if !(7u8.wrapping_pow(0u32) == 1u8) { panic("wrapping_pow #914") }
    if !(7u8.overflowing_pow(0u32).0 == 1u8 && 7u8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #915") }
    if !(7u8.saturating_pow(0u32) == 1u8) { panic("saturating_pow #916") }
    if !(7u8.pow(0u32) == 1u8) { panic("pow #917") }
    if !(7u8.strict_pow(0u32) == 1u8) { panic("strict_pow #918") }
    if !(7u8.checked_pow(1u32) == present(7u8)) { panic("checked_pow #919") }
    if !(7u8.wrapping_pow(1u32) == 7u8) { panic("wrapping_pow #920") }
    if !(7u8.overflowing_pow(1u32).0 == 7u8 && 7u8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #921") }
    if !(7u8.saturating_pow(1u32) == 7u8) { panic("saturating_pow #922") }
    if !(7u8.pow(1u32) == 7u8) { panic("pow #923") }
    if !(7u8.strict_pow(1u32) == 7u8) { panic("strict_pow #924") }
    if !(7u8.checked_pow(2u32) == present(49u8)) { panic("checked_pow #925") }
    if !(7u8.wrapping_pow(2u32) == 49u8) { panic("wrapping_pow #926") }
    if !(7u8.overflowing_pow(2u32).0 == 49u8 && 7u8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #927") }
    if !(7u8.saturating_pow(2u32) == 49u8) { panic("saturating_pow #928") }
    if !(7u8.pow(2u32) == 49u8) { panic("pow #929") }
    if !(7u8.strict_pow(2u32) == 49u8) { panic("strict_pow #930") }
    if !(missing(7u8.checked_pow(3u32))) { panic("checked_pow #931") }
    if !(7u8.wrapping_pow(3u32) == 87u8) { panic("wrapping_pow #932") }
    if !(7u8.overflowing_pow(3u32).0 == 87u8 && 7u8.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #933") }
    if !(7u8.saturating_pow(3u32) == u8.MAX) { panic("saturating_pow #934") }
    if !(missing(7u8.checked_pow(7u32))) { panic("checked_pow #935") }
    if !(7u8.wrapping_pow(7u32) == 247u8) { panic("wrapping_pow #936") }
    if !(7u8.overflowing_pow(7u32).0 == 247u8 && 7u8.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #937") }
    if !(7u8.saturating_pow(7u32) == u8.MAX) { panic("saturating_pow #938") }
    if !(missing(7u8.checked_pow(8u32))) { panic("checked_pow #939") }
    if !(7u8.wrapping_pow(8u32) == 193u8) { panic("wrapping_pow #940") }
    if !(7u8.overflowing_pow(8u32).0 == 193u8 && 7u8.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #941") }
    if !(7u8.saturating_pow(8u32) == u8.MAX) { panic("saturating_pow #942") }
    if !(7u8.ilog2() == 2u32) { panic("ilog2 #943") }
    if !(7u8.ilog10() == 0u32) { panic("ilog10 #944") }
    if !(7u8.checked_ilog2() == present(2u32)) { panic("checked_ilog2 #945") }
    if !(7u8.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #946") }
    if !(7u8.ilog(2u8) == 2u32) { panic("ilog #947") }
    if !(7u8.checked_ilog(2u8) == present(2u32)) { panic("checked_ilog #948") }
    if !(7u8.ilog(3u8) == 1u32) { panic("ilog #949") }
    if !(7u8.checked_ilog(3u8) == present(1u32)) { panic("checked_ilog #950") }
    if !(7u8.ilog(7u8) == 1u32) { panic("ilog #951") }
    if !(7u8.checked_ilog(7u8) == present(1u32)) { panic("checked_ilog #952") }
    if !(missing(7u8.checked_ilog(1u8))) { panic("checked_ilog #953") }
    if !(7u8.isqrt() == 2u8) { panic("isqrt #954") }
    if !(7u8.checked_isqrt() == present(2u8)) { panic("checked_isqrt #955") }
    if !(7u8.is_power_of_two() == false) { panic("is_power_of_two #956") }
    if !(7u8.checked_next_power_of_two() == present(8u8)) { panic("checked_next_power_of_two #957") }
    if !(7u8.next_power_of_two() == 8u8) { panic("next_power_of_two #958") }
    if !(7u8.div_ceil(1u8) == 7u8) { panic("div_ceil #959") }
    if !(7u8.checked_next_multiple_of(1u8) == present(7u8)) { panic("checked_next_multiple_of #960") }
}

fn group8() {
    if !(7u8.next_multiple_of(1u8) == 7u8) { panic("next_multiple_of #961") }
    if !(7u8.is_multiple_of(1u8) == true) { panic("is_multiple_of #962") }
    if !(7u8.div_ceil(3u8) == 3u8) { panic("div_ceil #963") }
    if !(7u8.checked_next_multiple_of(3u8) == present(9u8)) { panic("checked_next_multiple_of #964") }
    if !(7u8.next_multiple_of(3u8) == 9u8) { panic("next_multiple_of #965") }
    if !(7u8.is_multiple_of(3u8) == false) { panic("is_multiple_of #966") }
    if !(7u8.div_ceil(7u8) == 1u8) { panic("div_ceil #967") }
    if !(7u8.checked_next_multiple_of(7u8) == present(7u8)) { panic("checked_next_multiple_of #968") }
    if !(7u8.next_multiple_of(7u8) == 7u8) { panic("next_multiple_of #969") }
    if !(7u8.is_multiple_of(7u8) == true) { panic("is_multiple_of #970") }
    if !(7u8.is_multiple_of(0u8) == false) { panic("is_multiple_of #971") }
    if !(missing(7u8.checked_next_multiple_of(0u8))) { panic("checked_next_multiple_of #972") }
    if !(7u8.highest_one() == present(2u32)) { panic("highest_one #973") }
    if !(7u8.lowest_one() == present(0u32)) { panic("lowest_one #974") }
    if !(7u8.isolate_highest_one() == 4u8) { panic("isolate_highest_one #975") }
    if !(7u8.isolate_lowest_one() == 1u8) { panic("isolate_lowest_one #976") }
    if !(7u8.bit_width() == 3u32) { panic("bit_width #977") }
}

fn group9() {
    if !(missing(1u8.checked_neg())) { panic("checked_neg #1140") }
    if !(1u8.wrapping_neg() == u8.MAX) { panic("wrapping_neg #1141") }
    if !(1u8.overflowing_neg().0 == u8.MAX && 1u8.overflowing_neg().1 == true) { panic("overflowing_neg #1142") }
    if !(1u8.cast_signed() == 1i8) { panic("cast_signed #1143") }
    if !(1u8.count_ones() == 1u32) { panic("count_ones #1144") }
    if !(1u8.count_zeros() == 7u32) { panic("count_zeros #1145") }
    if !(1u8.leading_zeros() == 7u32) { panic("leading_zeros #1146") }
    if !(1u8.trailing_zeros() == 0u32) { panic("trailing_zeros #1147") }
    if !(1u8.leading_ones() == 0u32) { panic("leading_ones #1148") }
    if !(1u8.trailing_ones() == 1u32) { panic("trailing_ones #1149") }
    if !(1u8.reverse_bits() == 128u8) { panic("reverse_bits #1150") }
    if !(1u8.swap_bytes() == 1u8) { panic("swap_bytes #1151") }
    if !(1u8.to_be() == 1u8) { panic("to_be #1152") }
    if !(1u8.to_le() == 1u8) { panic("to_le #1153") }
    if !(u8.from_be(1u8) == 1u8) { panic("from_be #1154") }
    if !(u8.from_le(1u8) == 1u8) { panic("from_le #1155") }
    if !(1u8.to_le_bytes() == [1u8]) { panic("to_le_bytes #1156") }
    if !(1u8.to_be_bytes() == [1u8]) { panic("to_be_bytes #1157") }
    if !(1u8.to_ne_bytes() == [1u8]) { panic("to_ne_bytes #1158") }
    if !(u8.from_le_bytes([1u8]) == 1u8) { panic("from_le_bytes #1159") }
    if !(u8.from_be_bytes([1u8]) == 1u8) { panic("from_be_bytes #1160") }
    if !(u8.from_ne_bytes([1u8]) == 1u8) { panic("from_ne_bytes #1161") }
    if !(1u8.rotate_left(0u32) == 1u8) { panic("rotate_left #1162") }
    if !(1u8.rotate_right(0u32) == 1u8) { panic("rotate_right #1163") }
    if !(1u8.checked_shl(0u32) == present(1u8)) { panic("checked_shl #1164") }
    if !(1u8.checked_shr(0u32) == present(1u8)) { panic("checked_shr #1165") }
    if !(1u8.wrapping_shl(0u32) == 1u8) { panic("wrapping_shl #1166") }
    if !(1u8.wrapping_shr(0u32) == 1u8) { panic("wrapping_shr #1167") }
    if !(1u8.overflowing_shl(0u32).0 == 1u8 && 1u8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1168") }
    if !(1u8.overflowing_shr(0u32).0 == 1u8 && 1u8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1169") }
    if !(1u8.unbounded_shl(0u32) == 1u8) { panic("unbounded_shl #1170") }
    if !(1u8.unbounded_shr(0u32) == 1u8) { panic("unbounded_shr #1171") }
    if !(1u8.strict_shl(0u32) == 1u8) { panic("strict_shl #1172") }
    if !(1u8.strict_shr(0u32) == 1u8) { panic("strict_shr #1173") }
    if !(unsafe { 1u8.unchecked_shl(0u32) } == 1u8) { panic("unchecked_shl #1174") }
    if !(unsafe { 1u8.unchecked_shr(0u32) } == 1u8) { panic("unchecked_shr #1175") }
    if !(1u8.rotate_left(1u32) == 2u8) { panic("rotate_left #1176") }
    if !(1u8.rotate_right(1u32) == 128u8) { panic("rotate_right #1177") }
    if !(1u8.checked_shl(1u32) == present(2u8)) { panic("checked_shl #1178") }
    if !(1u8.checked_shr(1u32) == present(0u8)) { panic("checked_shr #1179") }
    if !(1u8.wrapping_shl(1u32) == 2u8) { panic("wrapping_shl #1180") }
    if !(1u8.wrapping_shr(1u32) == 0u8) { panic("wrapping_shr #1181") }
    if !(1u8.overflowing_shl(1u32).0 == 2u8 && 1u8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1182") }
    if !(1u8.overflowing_shr(1u32).0 == 0u8 && 1u8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1183") }
    if !(1u8.unbounded_shl(1u32) == 2u8) { panic("unbounded_shl #1184") }
    if !(1u8.unbounded_shr(1u32) == 0u8) { panic("unbounded_shr #1185") }
    if !(1u8.strict_shl(1u32) == 2u8) { panic("strict_shl #1186") }
    if !(1u8.strict_shr(1u32) == 0u8) { panic("strict_shr #1187") }
    if !(unsafe { 1u8.unchecked_shl(1u32) } == 2u8) { panic("unchecked_shl #1188") }
    if !(unsafe { 1u8.unchecked_shr(1u32) } == 0u8) { panic("unchecked_shr #1189") }
    if !(1u8.rotate_left(3u32) == 8u8) { panic("rotate_left #1190") }
    if !(1u8.rotate_right(3u32) == 32u8) { panic("rotate_right #1191") }
    if !(1u8.checked_shl(3u32) == present(8u8)) { panic("checked_shl #1192") }
    if !(1u8.checked_shr(3u32) == present(0u8)) { panic("checked_shr #1193") }
    if !(1u8.wrapping_shl(3u32) == 8u8) { panic("wrapping_shl #1194") }
    if !(1u8.wrapping_shr(3u32) == 0u8) { panic("wrapping_shr #1195") }
    if !(1u8.overflowing_shl(3u32).0 == 8u8 && 1u8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1196") }
    if !(1u8.overflowing_shr(3u32).0 == 0u8 && 1u8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1197") }
    if !(1u8.unbounded_shl(3u32) == 8u8) { panic("unbounded_shl #1198") }
    if !(1u8.unbounded_shr(3u32) == 0u8) { panic("unbounded_shr #1199") }
    if !(1u8.strict_shl(3u32) == 8u8) { panic("strict_shl #1200") }
}

fn group10() {
    if !(1u8.strict_shr(3u32) == 0u8) { panic("strict_shr #1201") }
    if !(unsafe { 1u8.unchecked_shl(3u32) } == 8u8) { panic("unchecked_shl #1202") }
    if !(unsafe { 1u8.unchecked_shr(3u32) } == 0u8) { panic("unchecked_shr #1203") }
    if !(1u8.rotate_left(7u32) == 128u8) { panic("rotate_left #1204") }
    if !(1u8.rotate_right(7u32) == 2u8) { panic("rotate_right #1205") }
    if !(1u8.checked_shl(7u32) == present(128u8)) { panic("checked_shl #1206") }
    if !(1u8.checked_shr(7u32) == present(0u8)) { panic("checked_shr #1207") }
    if !(1u8.wrapping_shl(7u32) == 128u8) { panic("wrapping_shl #1208") }
    if !(1u8.wrapping_shr(7u32) == 0u8) { panic("wrapping_shr #1209") }
    if !(1u8.overflowing_shl(7u32).0 == 128u8 && 1u8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #1210") }
    if !(1u8.overflowing_shr(7u32).0 == 0u8 && 1u8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #1211") }
    if !(1u8.unbounded_shl(7u32) == 128u8) { panic("unbounded_shl #1212") }
    if !(1u8.unbounded_shr(7u32) == 0u8) { panic("unbounded_shr #1213") }
    if !(1u8.strict_shl(7u32) == 128u8) { panic("strict_shl #1214") }
    if !(1u8.strict_shr(7u32) == 0u8) { panic("strict_shr #1215") }
    if !(unsafe { 1u8.unchecked_shl(7u32) } == 128u8) { panic("unchecked_shl #1216") }
    if !(unsafe { 1u8.unchecked_shr(7u32) } == 0u8) { panic("unchecked_shr #1217") }
    if !(1u8.rotate_left(8u32) == 1u8) { panic("rotate_left #1218") }
    if !(1u8.rotate_right(8u32) == 1u8) { panic("rotate_right #1219") }
    if !(missing(1u8.checked_shl(8u32))) { panic("checked_shl #1220") }
    if !(missing(1u8.checked_shr(8u32))) { panic("checked_shr #1221") }
    if !(1u8.wrapping_shl(8u32) == 1u8) { panic("wrapping_shl #1222") }
    if !(1u8.wrapping_shr(8u32) == 1u8) { panic("wrapping_shr #1223") }
    if !(1u8.overflowing_shl(8u32).0 == 1u8 && 1u8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #1224") }
    if !(1u8.overflowing_shr(8u32).0 == 1u8 && 1u8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #1225") }
    if !(1u8.unbounded_shl(8u32) == 0u8) { panic("unbounded_shl #1226") }
    if !(1u8.unbounded_shr(8u32) == 0u8) { panic("unbounded_shr #1227") }
    if !(1u8.rotate_left(13u32) == 32u8) { panic("rotate_left #1228") }
    if !(1u8.rotate_right(13u32) == 8u8) { panic("rotate_right #1229") }
    if !(missing(1u8.checked_shl(13u32))) { panic("checked_shl #1230") }
    if !(missing(1u8.checked_shr(13u32))) { panic("checked_shr #1231") }
    if !(1u8.wrapping_shl(13u32) == 32u8) { panic("wrapping_shl #1232") }
    if !(1u8.wrapping_shr(13u32) == 0u8) { panic("wrapping_shr #1233") }
    if !(1u8.overflowing_shl(13u32).0 == 32u8 && 1u8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #1234") }
    if !(1u8.overflowing_shr(13u32).0 == 0u8 && 1u8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #1235") }
    if !(1u8.unbounded_shl(13u32) == 0u8) { panic("unbounded_shl #1236") }
    if !(1u8.unbounded_shr(13u32) == 0u8) { panic("unbounded_shr #1237") }
    if !(1u8.checked_pow(0u32) == present(1u8)) { panic("checked_pow #1238") }
    if !(1u8.wrapping_pow(0u32) == 1u8) { panic("wrapping_pow #1239") }
    if !(1u8.overflowing_pow(0u32).0 == 1u8 && 1u8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1240") }
    if !(1u8.saturating_pow(0u32) == 1u8) { panic("saturating_pow #1241") }
    if !(1u8.pow(0u32) == 1u8) { panic("pow #1242") }
    if !(1u8.strict_pow(0u32) == 1u8) { panic("strict_pow #1243") }
    if !(1u8.checked_pow(1u32) == present(1u8)) { panic("checked_pow #1244") }
    if !(1u8.wrapping_pow(1u32) == 1u8) { panic("wrapping_pow #1245") }
    if !(1u8.overflowing_pow(1u32).0 == 1u8 && 1u8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1246") }
    if !(1u8.saturating_pow(1u32) == 1u8) { panic("saturating_pow #1247") }
    if !(1u8.pow(1u32) == 1u8) { panic("pow #1248") }
    if !(1u8.strict_pow(1u32) == 1u8) { panic("strict_pow #1249") }
    if !(1u8.checked_pow(2u32) == present(1u8)) { panic("checked_pow #1250") }
    if !(1u8.wrapping_pow(2u32) == 1u8) { panic("wrapping_pow #1251") }
    if !(1u8.overflowing_pow(2u32).0 == 1u8 && 1u8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1252") }
    if !(1u8.saturating_pow(2u32) == 1u8) { panic("saturating_pow #1253") }
    if !(1u8.pow(2u32) == 1u8) { panic("pow #1254") }
    if !(1u8.strict_pow(2u32) == 1u8) { panic("strict_pow #1255") }
    if !(1u8.checked_pow(3u32) == present(1u8)) { panic("checked_pow #1256") }
    if !(1u8.wrapping_pow(3u32) == 1u8) { panic("wrapping_pow #1257") }
    if !(1u8.overflowing_pow(3u32).0 == 1u8 && 1u8.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1258") }
    if !(1u8.saturating_pow(3u32) == 1u8) { panic("saturating_pow #1259") }
    if !(1u8.pow(3u32) == 1u8) { panic("pow #1260") }
    if !(1u8.strict_pow(3u32) == 1u8) { panic("strict_pow #1261") }
    if !(1u8.checked_pow(7u32) == present(1u8)) { panic("checked_pow #1262") }
    if !(1u8.wrapping_pow(7u32) == 1u8) { panic("wrapping_pow #1263") }
    if !(1u8.overflowing_pow(7u32).0 == 1u8 && 1u8.overflowing_pow(7u32).1 == false) { panic("overflowing_pow #1264") }
    if !(1u8.saturating_pow(7u32) == 1u8) { panic("saturating_pow #1265") }
    if !(1u8.pow(7u32) == 1u8) { panic("pow #1266") }
    if !(1u8.strict_pow(7u32) == 1u8) { panic("strict_pow #1267") }
    if !(1u8.checked_pow(8u32) == present(1u8)) { panic("checked_pow #1268") }
    if !(1u8.wrapping_pow(8u32) == 1u8) { panic("wrapping_pow #1269") }
    if !(1u8.overflowing_pow(8u32).0 == 1u8 && 1u8.overflowing_pow(8u32).1 == false) { panic("overflowing_pow #1270") }
    if !(1u8.saturating_pow(8u32) == 1u8) { panic("saturating_pow #1271") }
    if !(1u8.pow(8u32) == 1u8) { panic("pow #1272") }
    if !(1u8.strict_pow(8u32) == 1u8) { panic("strict_pow #1273") }
    if !(1u8.ilog2() == 0u32) { panic("ilog2 #1274") }
    if !(1u8.ilog10() == 0u32) { panic("ilog10 #1275") }
    if !(1u8.checked_ilog2() == present(0u32)) { panic("checked_ilog2 #1276") }
    if !(1u8.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1277") }
    if !(1u8.ilog(2u8) == 0u32) { panic("ilog #1278") }
    if !(1u8.checked_ilog(2u8) == present(0u32)) { panic("checked_ilog #1279") }
    if !(1u8.ilog(3u8) == 0u32) { panic("ilog #1280") }
    if !(1u8.checked_ilog(3u8) == present(0u32)) { panic("checked_ilog #1281") }
    if !(1u8.ilog(7u8) == 0u32) { panic("ilog #1282") }
    if !(1u8.checked_ilog(7u8) == present(0u32)) { panic("checked_ilog #1283") }
    if !(missing(1u8.checked_ilog(1u8))) { panic("checked_ilog #1284") }
    if !(1u8.isqrt() == 1u8) { panic("isqrt #1285") }
    if !(1u8.checked_isqrt() == present(1u8)) { panic("checked_isqrt #1286") }
    if !(1u8.is_power_of_two() == true) { panic("is_power_of_two #1287") }
    if !(1u8.checked_next_power_of_two() == present(1u8)) { panic("checked_next_power_of_two #1288") }
    if !(1u8.next_power_of_two() == 1u8) { panic("next_power_of_two #1289") }
    if !(1u8.div_ceil(1u8) == 1u8) { panic("div_ceil #1290") }
    if !(1u8.checked_next_multiple_of(1u8) == present(1u8)) { panic("checked_next_multiple_of #1291") }
    if !(1u8.next_multiple_of(1u8) == 1u8) { panic("next_multiple_of #1292") }
    if !(1u8.is_multiple_of(1u8) == true) { panic("is_multiple_of #1293") }
    if !(1u8.div_ceil(3u8) == 1u8) { panic("div_ceil #1294") }
    if !(1u8.checked_next_multiple_of(3u8) == present(3u8)) { panic("checked_next_multiple_of #1295") }
    if !(1u8.next_multiple_of(3u8) == 3u8) { panic("next_multiple_of #1296") }
    if !(1u8.is_multiple_of(3u8) == false) { panic("is_multiple_of #1297") }
    if !(1u8.div_ceil(7u8) == 1u8) { panic("div_ceil #1298") }
    if !(1u8.checked_next_multiple_of(7u8) == present(7u8)) { panic("checked_next_multiple_of #1299") }
    if !(1u8.next_multiple_of(7u8) == 7u8) { panic("next_multiple_of #1300") }
    if !(1u8.is_multiple_of(7u8) == false) { panic("is_multiple_of #1301") }
    if !(1u8.is_multiple_of(0u8) == false) { panic("is_multiple_of #1302") }
    if !(missing(1u8.checked_next_multiple_of(0u8))) { panic("checked_next_multiple_of #1303") }
    if !(1u8.highest_one() == present(0u32)) { panic("highest_one #1304") }
    if !(1u8.lowest_one() == present(0u32)) { panic("lowest_one #1305") }
    if !(1u8.isolate_highest_one() == 1u8) { panic("isolate_highest_one #1306") }
    if !(1u8.isolate_lowest_one() == 1u8) { panic("isolate_lowest_one #1307") }
    if !(1u8.bit_width() == 1u32) { panic("bit_width #1308") }
    if !(u8.MAX.carrying_add(1u8, false).0 == 0u8 && u8.MAX.carrying_add(1u8, false).1 == true) { panic("carrying_add #1309") }
    if !(u8.MAX.borrowing_sub(1u8, false).0 == 254u8 && u8.MAX.borrowing_sub(1u8, false).1 == false) { panic("borrowing_sub #1310") }
    if !(u8.MAX.carrying_add(1u8, true).0 == 1u8 && u8.MAX.carrying_add(1u8, true).1 == true) { panic("carrying_add #1311") }
    if !(u8.MAX.borrowing_sub(1u8, true).0 == 253u8 && u8.MAX.borrowing_sub(1u8, true).1 == false) { panic("borrowing_sub #1312") }
    if !(u8.MAX.carrying_mul(1u8, 0u8).0 == u8.MAX && u8.MAX.carrying_mul(1u8, 0u8).1 == 0u8) { panic("carrying_mul #1313") }
    if !(u8.MAX.carrying_mul_add(1u8, 0u8, 0u8).0 == u8.MAX && u8.MAX.carrying_mul_add(1u8, 0u8, 0u8).1 == 0u8) { panic("carrying_mul_add #1314") }
    if !(u8.MAX.carrying_mul(1u8, u8.MAX).0 == 254u8 && u8.MAX.carrying_mul(1u8, u8.MAX).1 == 1u8) { panic("carrying_mul #1315") }
    if !(u8.MAX.carrying_mul_add(1u8, u8.MAX, 0u8).0 == 254u8 && u8.MAX.carrying_mul_add(1u8, u8.MAX, 0u8).1 == 1u8) { panic("carrying_mul_add #1316") }
    if !(u8.MAX.carrying_mul_add(1u8, u8.MAX, u8.MAX).0 == 253u8 && u8.MAX.carrying_mul_add(1u8, u8.MAX, u8.MAX).1 == 2u8) { panic("carrying_mul_add #1318") }
    if !(u8.MAX.carrying_mul(1u8, 7u8).0 == 6u8 && u8.MAX.carrying_mul(1u8, 7u8).1 == 1u8) { panic("carrying_mul #1319") }
    if !(u8.MAX.carrying_mul_add(1u8, 7u8, 3u8).0 == 9u8 && u8.MAX.carrying_mul_add(1u8, 7u8, 3u8).1 == 1u8) { panic("carrying_mul_add #1320") }
}

fn group11() {
    if !(missing(u8.MAX.checked_signed_diff(1u8))) { panic("checked_signed_diff #1321") }
    if !(0u8.carrying_add(1u8, false).0 == 1u8 && 0u8.carrying_add(1u8, false).1 == false) { panic("carrying_add #1322") }
    if !(0u8.borrowing_sub(1u8, false).0 == u8.MAX && 0u8.borrowing_sub(1u8, false).1 == true) { panic("borrowing_sub #1323") }
    if !(0u8.carrying_add(1u8, true).0 == 2u8 && 0u8.carrying_add(1u8, true).1 == false) { panic("carrying_add #1324") }
    if !(0u8.borrowing_sub(1u8, true).0 == 254u8 && 0u8.borrowing_sub(1u8, true).1 == true) { panic("borrowing_sub #1325") }
    if !(0u8.carrying_mul(1u8, 0u8).0 == 0u8 && 0u8.carrying_mul(1u8, 0u8).1 == 0u8) { panic("carrying_mul #1326") }
    if !(0u8.carrying_mul_add(1u8, 0u8, 0u8).0 == 0u8 && 0u8.carrying_mul_add(1u8, 0u8, 0u8).1 == 0u8) { panic("carrying_mul_add #1327") }
    if !(0u8.carrying_mul(1u8, u8.MAX).0 == u8.MAX && 0u8.carrying_mul(1u8, u8.MAX).1 == 0u8) { panic("carrying_mul #1328") }
    if !(0u8.carrying_mul_add(1u8, u8.MAX, 0u8).0 == u8.MAX && 0u8.carrying_mul_add(1u8, u8.MAX, 0u8).1 == 0u8) { panic("carrying_mul_add #1329") }
    if !(0u8.carrying_mul_add(1u8, u8.MAX, u8.MAX).0 == 254u8 && 0u8.carrying_mul_add(1u8, u8.MAX, u8.MAX).1 == 1u8) { panic("carrying_mul_add #1331") }
    if !(0u8.carrying_mul(1u8, 7u8).0 == 7u8 && 0u8.carrying_mul(1u8, 7u8).1 == 0u8) { panic("carrying_mul #1332") }
    if !(0u8.carrying_mul_add(1u8, 7u8, 3u8).0 == 10u8 && 0u8.carrying_mul_add(1u8, 7u8, 3u8).1 == 0u8) { panic("carrying_mul_add #1333") }
    if !(0u8.checked_signed_diff(1u8) == present((-1i8))) { panic("checked_signed_diff #1334") }
    if !(3u8.carrying_add(7u8, false).0 == 10u8 && 3u8.carrying_add(7u8, false).1 == false) { panic("carrying_add #1335") }
    if !(3u8.borrowing_sub(7u8, false).0 == 252u8 && 3u8.borrowing_sub(7u8, false).1 == true) { panic("borrowing_sub #1336") }
    if !(3u8.carrying_add(7u8, true).0 == 11u8 && 3u8.carrying_add(7u8, true).1 == false) { panic("carrying_add #1337") }
    if !(3u8.borrowing_sub(7u8, true).0 == 251u8 && 3u8.borrowing_sub(7u8, true).1 == true) { panic("borrowing_sub #1338") }
    if !(3u8.carrying_mul(7u8, 0u8).0 == 21u8 && 3u8.carrying_mul(7u8, 0u8).1 == 0u8) { panic("carrying_mul #1339") }
    if !(3u8.carrying_mul_add(7u8, 0u8, 0u8).0 == 21u8 && 3u8.carrying_mul_add(7u8, 0u8, 0u8).1 == 0u8) { panic("carrying_mul_add #1340") }
    if !(3u8.carrying_mul(7u8, u8.MAX).0 == 20u8 && 3u8.carrying_mul(7u8, u8.MAX).1 == 1u8) { panic("carrying_mul #1341") }
    if !(3u8.carrying_mul_add(7u8, u8.MAX, 0u8).0 == 20u8 && 3u8.carrying_mul_add(7u8, u8.MAX, 0u8).1 == 1u8) { panic("carrying_mul_add #1342") }
    if !(3u8.carrying_mul_add(7u8, u8.MAX, u8.MAX).0 == 19u8 && 3u8.carrying_mul_add(7u8, u8.MAX, u8.MAX).1 == 2u8) { panic("carrying_mul_add #1344") }
    if !(3u8.carrying_mul(7u8, 7u8).0 == 28u8 && 3u8.carrying_mul(7u8, 7u8).1 == 0u8) { panic("carrying_mul #1345") }
    if !(3u8.carrying_mul_add(7u8, 7u8, 3u8).0 == 31u8 && 3u8.carrying_mul_add(7u8, 7u8, 3u8).1 == 0u8) { panic("carrying_mul_add #1346") }
    if !(3u8.checked_signed_diff(7u8) == present((-4i8))) { panic("checked_signed_diff #1347") }
    if !(7u8.carrying_add(3u8, false).0 == 10u8 && 7u8.carrying_add(3u8, false).1 == false) { panic("carrying_add #1348") }
    if !(7u8.borrowing_sub(3u8, false).0 == 4u8 && 7u8.borrowing_sub(3u8, false).1 == false) { panic("borrowing_sub #1349") }
    if !(7u8.carrying_add(3u8, true).0 == 11u8 && 7u8.carrying_add(3u8, true).1 == false) { panic("carrying_add #1350") }
    if !(7u8.borrowing_sub(3u8, true).0 == 3u8 && 7u8.borrowing_sub(3u8, true).1 == false) { panic("borrowing_sub #1351") }
    if !(7u8.carrying_mul(3u8, 0u8).0 == 21u8 && 7u8.carrying_mul(3u8, 0u8).1 == 0u8) { panic("carrying_mul #1352") }
    if !(7u8.carrying_mul_add(3u8, 0u8, 0u8).0 == 21u8 && 7u8.carrying_mul_add(3u8, 0u8, 0u8).1 == 0u8) { panic("carrying_mul_add #1353") }
    if !(7u8.carrying_mul(3u8, u8.MAX).0 == 20u8 && 7u8.carrying_mul(3u8, u8.MAX).1 == 1u8) { panic("carrying_mul #1354") }
    if !(7u8.carrying_mul_add(3u8, u8.MAX, 0u8).0 == 20u8 && 7u8.carrying_mul_add(3u8, u8.MAX, 0u8).1 == 1u8) { panic("carrying_mul_add #1355") }
    if !(7u8.carrying_mul_add(3u8, u8.MAX, u8.MAX).0 == 19u8 && 7u8.carrying_mul_add(3u8, u8.MAX, u8.MAX).1 == 2u8) { panic("carrying_mul_add #1357") }
    if !(7u8.carrying_mul(3u8, 7u8).0 == 28u8 && 7u8.carrying_mul(3u8, 7u8).1 == 0u8) { panic("carrying_mul #1358") }
    if !(7u8.carrying_mul_add(3u8, 7u8, 3u8).0 == 31u8 && 7u8.carrying_mul_add(3u8, 7u8, 3u8).1 == 0u8) { panic("carrying_mul_add #1359") }
    if !(7u8.checked_signed_diff(3u8) == present(4i8)) { panic("checked_signed_diff #1360") }
    if !(u8.MAX.carrying_add(2u8, false).0 == 1u8 && u8.MAX.carrying_add(2u8, false).1 == true) { panic("carrying_add #1361") }
    if !(u8.MAX.borrowing_sub(2u8, false).0 == 253u8 && u8.MAX.borrowing_sub(2u8, false).1 == false) { panic("borrowing_sub #1362") }
    if !(u8.MAX.carrying_add(2u8, true).0 == 2u8 && u8.MAX.carrying_add(2u8, true).1 == true) { panic("carrying_add #1363") }
    if !(u8.MAX.borrowing_sub(2u8, true).0 == 252u8 && u8.MAX.borrowing_sub(2u8, true).1 == false) { panic("borrowing_sub #1364") }
    if !(u8.MAX.carrying_mul(2u8, 0u8).0 == 254u8 && u8.MAX.carrying_mul(2u8, 0u8).1 == 1u8) { panic("carrying_mul #1365") }
    if !(u8.MAX.carrying_mul_add(2u8, 0u8, 0u8).0 == 254u8 && u8.MAX.carrying_mul_add(2u8, 0u8, 0u8).1 == 1u8) { panic("carrying_mul_add #1366") }
    if !(u8.MAX.carrying_mul(2u8, u8.MAX).0 == 253u8 && u8.MAX.carrying_mul(2u8, u8.MAX).1 == 2u8) { panic("carrying_mul #1367") }
    if !(u8.MAX.carrying_mul_add(2u8, u8.MAX, 0u8).0 == 253u8 && u8.MAX.carrying_mul_add(2u8, u8.MAX, 0u8).1 == 2u8) { panic("carrying_mul_add #1368") }
    if !(u8.MAX.carrying_mul_add(2u8, u8.MAX, u8.MAX).0 == 252u8 && u8.MAX.carrying_mul_add(2u8, u8.MAX, u8.MAX).1 == 3u8) { panic("carrying_mul_add #1370") }
    if !(u8.MAX.carrying_mul(2u8, 7u8).0 == 5u8 && u8.MAX.carrying_mul(2u8, 7u8).1 == 2u8) { panic("carrying_mul #1371") }
    if !(u8.MAX.carrying_mul_add(2u8, 7u8, 3u8).0 == 8u8 && u8.MAX.carrying_mul_add(2u8, 7u8, 3u8).1 == 2u8) { panic("carrying_mul_add #1372") }
    if !(missing(u8.MAX.checked_signed_diff(2u8))) { panic("checked_signed_diff #1373") }
    if !(0u8.carrying_add(0u8, false).0 == 0u8 && 0u8.carrying_add(0u8, false).1 == false) { panic("carrying_add #1374") }
    if !(0u8.borrowing_sub(0u8, false).0 == 0u8 && 0u8.borrowing_sub(0u8, false).1 == false) { panic("borrowing_sub #1375") }
    if !(0u8.carrying_add(0u8, true).0 == 1u8 && 0u8.carrying_add(0u8, true).1 == false) { panic("carrying_add #1376") }
    if !(0u8.borrowing_sub(0u8, true).0 == u8.MAX && 0u8.borrowing_sub(0u8, true).1 == true) { panic("borrowing_sub #1377") }
    if !(0u8.carrying_mul(0u8, 0u8).0 == 0u8 && 0u8.carrying_mul(0u8, 0u8).1 == 0u8) { panic("carrying_mul #1378") }
    if !(0u8.carrying_mul_add(0u8, 0u8, 0u8).0 == 0u8 && 0u8.carrying_mul_add(0u8, 0u8, 0u8).1 == 0u8) { panic("carrying_mul_add #1379") }
    if !(0u8.carrying_mul(0u8, u8.MAX).0 == u8.MAX && 0u8.carrying_mul(0u8, u8.MAX).1 == 0u8) { panic("carrying_mul #1380") }
    if !(0u8.carrying_mul_add(0u8, u8.MAX, 0u8).0 == u8.MAX && 0u8.carrying_mul_add(0u8, u8.MAX, 0u8).1 == 0u8) { panic("carrying_mul_add #1381") }
    if !(0u8.carrying_mul_add(0u8, u8.MAX, u8.MAX).0 == 254u8 && 0u8.carrying_mul_add(0u8, u8.MAX, u8.MAX).1 == 1u8) { panic("carrying_mul_add #1383") }
    if !(0u8.carrying_mul(0u8, 7u8).0 == 7u8 && 0u8.carrying_mul(0u8, 7u8).1 == 0u8) { panic("carrying_mul #1384") }
    if !(0u8.carrying_mul_add(0u8, 7u8, 3u8).0 == 10u8 && 0u8.carrying_mul_add(0u8, 7u8, 3u8).1 == 0u8) { panic("carrying_mul_add #1385") }
    if !(0u8.checked_signed_diff(0u8) == present(0i8)) { panic("checked_signed_diff #1386") }
    if !(u8.MAX.carrying_add(u8.MAX, false).0 == 254u8 && u8.MAX.carrying_add(u8.MAX, false).1 == true) { panic("carrying_add #1387") }
    if !(u8.MAX.borrowing_sub(u8.MAX, false).0 == 0u8 && u8.MAX.borrowing_sub(u8.MAX, false).1 == false) { panic("borrowing_sub #1388") }
    if !(u8.MAX.carrying_add(u8.MAX, true).0 == u8.MAX && u8.MAX.carrying_add(u8.MAX, true).1 == true) { panic("carrying_add #1389") }
    if !(u8.MAX.borrowing_sub(u8.MAX, true).0 == u8.MAX && u8.MAX.borrowing_sub(u8.MAX, true).1 == true) { panic("borrowing_sub #1390") }
    if !(u8.MAX.carrying_mul(u8.MAX, 0u8).0 == 1u8 && u8.MAX.carrying_mul(u8.MAX, 0u8).1 == 254u8) { panic("carrying_mul #1391") }
    if !(u8.MAX.carrying_mul_add(u8.MAX, 0u8, 0u8).0 == 1u8 && u8.MAX.carrying_mul_add(u8.MAX, 0u8, 0u8).1 == 254u8) { panic("carrying_mul_add #1392") }
    if !(u8.MAX.carrying_mul(u8.MAX, u8.MAX).0 == 0u8 && u8.MAX.carrying_mul(u8.MAX, u8.MAX).1 == u8.MAX) { panic("carrying_mul #1393") }
    if !(u8.MAX.carrying_mul_add(u8.MAX, u8.MAX, 0u8).0 == 0u8 && u8.MAX.carrying_mul_add(u8.MAX, u8.MAX, 0u8).1 == u8.MAX) { panic("carrying_mul_add #1394") }
    if !(u8.MAX.carrying_mul_add(u8.MAX, u8.MAX, u8.MAX).0 == u8.MAX && u8.MAX.carrying_mul_add(u8.MAX, u8.MAX, u8.MAX).1 == u8.MAX) { panic("carrying_mul_add #1396") }
    if !(u8.MAX.carrying_mul(u8.MAX, 7u8).0 == 8u8 && u8.MAX.carrying_mul(u8.MAX, 7u8).1 == 254u8) { panic("carrying_mul #1397") }
    if !(u8.MAX.carrying_mul_add(u8.MAX, 7u8, 3u8).0 == 11u8 && u8.MAX.carrying_mul_add(u8.MAX, 7u8, 3u8).1 == 254u8) { panic("carrying_mul_add #1398") }
    if !(u8.MAX.checked_signed_diff(u8.MAX) == present(0i8)) { panic("checked_signed_diff #1399") }
    if !(u8.MAX.carrying_add(254u8, false).0 == 253u8 && u8.MAX.carrying_add(254u8, false).1 == true) { panic("carrying_add #1400") }
    if !(u8.MAX.borrowing_sub(254u8, false).0 == 1u8 && u8.MAX.borrowing_sub(254u8, false).1 == false) { panic("borrowing_sub #1401") }
    if !(u8.MAX.carrying_add(254u8, true).0 == 254u8 && u8.MAX.carrying_add(254u8, true).1 == true) { panic("carrying_add #1402") }
    if !(u8.MAX.borrowing_sub(254u8, true).0 == 0u8 && u8.MAX.borrowing_sub(254u8, true).1 == false) { panic("borrowing_sub #1403") }
    if !(u8.MAX.carrying_mul(254u8, 0u8).0 == 2u8 && u8.MAX.carrying_mul(254u8, 0u8).1 == 253u8) { panic("carrying_mul #1404") }
    if !(u8.MAX.carrying_mul_add(254u8, 0u8, 0u8).0 == 2u8 && u8.MAX.carrying_mul_add(254u8, 0u8, 0u8).1 == 253u8) { panic("carrying_mul_add #1405") }
    if !(u8.MAX.carrying_mul(254u8, u8.MAX).0 == 1u8 && u8.MAX.carrying_mul(254u8, u8.MAX).1 == 254u8) { panic("carrying_mul #1406") }
    if !(u8.MAX.carrying_mul_add(254u8, u8.MAX, 0u8).0 == 1u8 && u8.MAX.carrying_mul_add(254u8, u8.MAX, 0u8).1 == 254u8) { panic("carrying_mul_add #1407") }
    if !(u8.MAX.carrying_mul_add(254u8, u8.MAX, u8.MAX).0 == 0u8 && u8.MAX.carrying_mul_add(254u8, u8.MAX, u8.MAX).1 == u8.MAX) { panic("carrying_mul_add #1409") }
    if !(u8.MAX.carrying_mul(254u8, 7u8).0 == 9u8 && u8.MAX.carrying_mul(254u8, 7u8).1 == 253u8) { panic("carrying_mul #1410") }
    if !(u8.MAX.carrying_mul_add(254u8, 7u8, 3u8).0 == 12u8 && u8.MAX.carrying_mul_add(254u8, 7u8, 3u8).1 == 253u8) { panic("carrying_mul_add #1411") }
    if !(u8.MAX.checked_signed_diff(254u8) == present(1i8)) { panic("checked_signed_diff #1412") }
    if !(parsed(capture num.parse_radix<u8>("255", 10u32)) == present(u8.MAX)) { panic("parse_radix #1413") }
    if !(parsed(capture num.parse_radix<u8>("ff", 16u32)) == present(u8.MAX)) { panic("parse_radix #1414") }
    if !(parsed(capture num.parse_radix<u8>("11111111", 2u32)) == present(u8.MAX)) { panic("parse_radix #1415") }
    if !(parsed(capture num.parse_radix<u8>("73", 36u32)) == present(u8.MAX)) { panic("parse_radix #1416") }
    if !(parsed(capture num.parse_radix<u8>("FF", 16u32)) == present(u8.MAX)) { panic("parse_radix #1417") }
    if !(parsed(capture num.parse_radix<u8>("0", 10u32)) == present(0u8)) { panic("parse_radix #1418") }
    if !(parsed(capture num.parse_radix<u8>("0", 16u32)) == present(0u8)) { panic("parse_radix #1419") }
    if !(parsed(capture num.parse_radix<u8>("0", 2u32)) == present(0u8)) { panic("parse_radix #1420") }
    if !(parsed(capture num.parse_radix<u8>("0", 36u32)) == present(0u8)) { panic("parse_radix #1421") }
    if !(parsed(capture num.parse_radix<u8>("7", 10u32)) == present(7u8)) { panic("parse_radix #1423") }
    if !(parsed(capture num.parse_radix<u8>("7", 16u32)) == present(7u8)) { panic("parse_radix #1424") }
    if !(parsed(capture num.parse_radix<u8>("111", 2u32)) == present(7u8)) { panic("parse_radix #1425") }
    if !(parsed(capture num.parse_radix<u8>("7", 36u32)) == present(7u8)) { panic("parse_radix #1426") }
    if !(parsed(capture num.parse_radix<u8>("+7", 10u32)) == present(7u8)) { panic("parse_radix #1433") }
    if !(kind(capture num.parse_radix<u8>("", 10u32)) == present(IntErrorKind.Empty)) { panic("parse_radix #1434") }
    if !(kind(capture num.parse_radix<u8>("-", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1435") }
    if !(kind(capture num.parse_radix<u8>("+", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1436") }
    if !(kind(capture num.parse_radix<u8>("1_0", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1437") }
    if !(kind(capture num.parse_radix<u8>("12", 2u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1438") }
    if !(kind(capture num.parse_radix<u8>(" 1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1439") }
    if !(kind(capture num.parse_radix<u8>("256", 10u32)) == present(IntErrorKind.PosOverflow)) { panic("parse_radix #1440") }
}

fn group12() {
    if !(kind(capture num.parse_radix<u8>("-1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1443") }
    if !(0u8.is_ascii() == true) { panic("is_ascii #1444") }
    if !(0u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1445") }
    if !(0u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1446") }
    if !(0u8.is_ascii_control() == true) { panic("is_ascii_control #1447") }
    if !(0u8.is_ascii_digit() == false) { panic("is_ascii_digit #1448") }
    if !(0u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1449") }
    if !(0u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1450") }
    if !(0u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1451") }
    if !(0u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1452") }
    if !(0u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1453") }
    if !(0u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1454") }
    if !(0u8.to_ascii_lowercase() == 0u8) { panic("to_ascii_lowercase #1455") }
    if !(0u8.to_ascii_uppercase() == 0u8) { panic("to_ascii_uppercase #1456") }
    if !(ascii_lower(0u8) == 0u8) { panic("make_ascii_lowercase #1457") }
    if !(ascii_upper(0u8) == 0u8) { panic("make_ascii_uppercase #1458") }
    if !(0u8.eq_ignore_ascii_case(0u8) == true) { panic("eq_ignore_ascii_case #1459") }
    if !(0u8.eq_ignore_ascii_case(1u8) == false) { panic("eq_ignore_ascii_case #1462") }
    if !(9u8.is_ascii() == true) { panic("is_ascii #1463") }
    if !(9u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1464") }
    if !(9u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1465") }
    if !(9u8.is_ascii_control() == true) { panic("is_ascii_control #1466") }
    if !(9u8.is_ascii_digit() == false) { panic("is_ascii_digit #1467") }
    if !(9u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1468") }
    if !(9u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1469") }
    if !(9u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1470") }
    if !(9u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1471") }
    if !(9u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1472") }
    if !(9u8.is_ascii_whitespace() == true) { panic("is_ascii_whitespace #1473") }
    if !(9u8.to_ascii_lowercase() == 9u8) { panic("to_ascii_lowercase #1474") }
    if !(9u8.to_ascii_uppercase() == 9u8) { panic("to_ascii_uppercase #1475") }
    if !(ascii_lower(9u8) == 9u8) { panic("make_ascii_lowercase #1476") }
    if !(ascii_upper(9u8) == 9u8) { panic("make_ascii_uppercase #1477") }
    if !(9u8.eq_ignore_ascii_case(9u8) == true) { panic("eq_ignore_ascii_case #1478") }
    if !(9u8.eq_ignore_ascii_case(10u8) == false) { panic("eq_ignore_ascii_case #1481") }
    if !(10u8.is_ascii() == true) { panic("is_ascii #1482") }
    if !(10u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1483") }
    if !(10u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1484") }
    if !(10u8.is_ascii_control() == true) { panic("is_ascii_control #1485") }
    if !(10u8.is_ascii_digit() == false) { panic("is_ascii_digit #1486") }
    if !(10u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1487") }
    if !(10u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1488") }
    if !(10u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1489") }
    if !(10u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1490") }
    if !(10u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1491") }
    if !(10u8.is_ascii_whitespace() == true) { panic("is_ascii_whitespace #1492") }
    if !(10u8.to_ascii_lowercase() == 10u8) { panic("to_ascii_lowercase #1493") }
    if !(10u8.to_ascii_uppercase() == 10u8) { panic("to_ascii_uppercase #1494") }
    if !(ascii_lower(10u8) == 10u8) { panic("make_ascii_lowercase #1495") }
    if !(ascii_upper(10u8) == 10u8) { panic("make_ascii_uppercase #1496") }
    if !(10u8.eq_ignore_ascii_case(10u8) == true) { panic("eq_ignore_ascii_case #1497") }
    if !(10u8.eq_ignore_ascii_case(11u8) == false) { panic("eq_ignore_ascii_case #1500") }
    if !(11u8.is_ascii() == true) { panic("is_ascii #1501") }
    if !(11u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1502") }
    if !(11u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1503") }
    if !(11u8.is_ascii_control() == true) { panic("is_ascii_control #1504") }
    if !(11u8.is_ascii_digit() == false) { panic("is_ascii_digit #1505") }
    if !(11u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1506") }
    if !(11u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1507") }
    if !(11u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1508") }
    if !(11u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1509") }
    if !(11u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1510") }
    if !(11u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1511") }
    if !(11u8.to_ascii_lowercase() == 11u8) { panic("to_ascii_lowercase #1512") }
    if !(11u8.to_ascii_uppercase() == 11u8) { panic("to_ascii_uppercase #1513") }
    if !(ascii_lower(11u8) == 11u8) { panic("make_ascii_lowercase #1514") }
    if !(ascii_upper(11u8) == 11u8) { panic("make_ascii_uppercase #1515") }
    if !(11u8.eq_ignore_ascii_case(11u8) == true) { panic("eq_ignore_ascii_case #1516") }
    if !(11u8.eq_ignore_ascii_case(12u8) == false) { panic("eq_ignore_ascii_case #1519") }
    if !(12u8.is_ascii() == true) { panic("is_ascii #1520") }
    if !(12u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1521") }
    if !(12u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1522") }
    if !(12u8.is_ascii_control() == true) { panic("is_ascii_control #1523") }
    if !(12u8.is_ascii_digit() == false) { panic("is_ascii_digit #1524") }
    if !(12u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1525") }
    if !(12u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1526") }
    if !(12u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1527") }
    if !(12u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1528") }
    if !(12u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1529") }
    if !(12u8.is_ascii_whitespace() == true) { panic("is_ascii_whitespace #1530") }
    if !(12u8.to_ascii_lowercase() == 12u8) { panic("to_ascii_lowercase #1531") }
    if !(12u8.to_ascii_uppercase() == 12u8) { panic("to_ascii_uppercase #1532") }
    if !(ascii_lower(12u8) == 12u8) { panic("make_ascii_lowercase #1533") }
    if !(ascii_upper(12u8) == 12u8) { panic("make_ascii_uppercase #1534") }
    if !(12u8.eq_ignore_ascii_case(12u8) == true) { panic("eq_ignore_ascii_case #1535") }
    if !(12u8.eq_ignore_ascii_case(13u8) == false) { panic("eq_ignore_ascii_case #1538") }
    if !(13u8.is_ascii() == true) { panic("is_ascii #1539") }
    if !(13u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1540") }
    if !(13u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1541") }
    if !(13u8.is_ascii_control() == true) { panic("is_ascii_control #1542") }
    if !(13u8.is_ascii_digit() == false) { panic("is_ascii_digit #1543") }
    if !(13u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1544") }
    if !(13u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1545") }
    if !(13u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1546") }
    if !(13u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1547") }
    if !(13u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1548") }
    if !(13u8.is_ascii_whitespace() == true) { panic("is_ascii_whitespace #1549") }
    if !(13u8.to_ascii_lowercase() == 13u8) { panic("to_ascii_lowercase #1550") }
    if !(13u8.to_ascii_uppercase() == 13u8) { panic("to_ascii_uppercase #1551") }
    if !(ascii_lower(13u8) == 13u8) { panic("make_ascii_lowercase #1552") }
    if !(ascii_upper(13u8) == 13u8) { panic("make_ascii_uppercase #1553") }
    if !(13u8.eq_ignore_ascii_case(13u8) == true) { panic("eq_ignore_ascii_case #1554") }
    if !(13u8.eq_ignore_ascii_case(14u8) == false) { panic("eq_ignore_ascii_case #1557") }
    if !(31u8.is_ascii() == true) { panic("is_ascii #1558") }
    if !(31u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1559") }
    if !(31u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1560") }
}

fn group13() {
    if !(31u8.is_ascii_control() == true) { panic("is_ascii_control #1561") }
    if !(31u8.is_ascii_digit() == false) { panic("is_ascii_digit #1562") }
    if !(31u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1563") }
    if !(31u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1564") }
    if !(31u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1565") }
    if !(31u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1566") }
    if !(31u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1567") }
    if !(31u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1568") }
    if !(31u8.to_ascii_lowercase() == 31u8) { panic("to_ascii_lowercase #1569") }
    if !(31u8.to_ascii_uppercase() == 31u8) { panic("to_ascii_uppercase #1570") }
    if !(ascii_lower(31u8) == 31u8) { panic("make_ascii_lowercase #1571") }
    if !(ascii_upper(31u8) == 31u8) { panic("make_ascii_uppercase #1572") }
    if !(31u8.eq_ignore_ascii_case(31u8) == true) { panic("eq_ignore_ascii_case #1573") }
    if !(31u8.eq_ignore_ascii_case(32u8) == false) { panic("eq_ignore_ascii_case #1576") }
    if !(32u8.is_ascii() == true) { panic("is_ascii #1577") }
    if !(32u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1578") }
    if !(32u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1579") }
    if !(32u8.is_ascii_control() == false) { panic("is_ascii_control #1580") }
    if !(32u8.is_ascii_digit() == false) { panic("is_ascii_digit #1581") }
    if !(32u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1582") }
    if !(32u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1583") }
    if !(32u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1584") }
    if !(32u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1585") }
    if !(32u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1586") }
    if !(32u8.is_ascii_whitespace() == true) { panic("is_ascii_whitespace #1587") }
    if !(32u8.to_ascii_lowercase() == 32u8) { panic("to_ascii_lowercase #1588") }
    if !(32u8.to_ascii_uppercase() == 32u8) { panic("to_ascii_uppercase #1589") }
    if !(ascii_lower(32u8) == 32u8) { panic("make_ascii_lowercase #1590") }
    if !(ascii_upper(32u8) == 32u8) { panic("make_ascii_uppercase #1591") }
    if !(32u8.eq_ignore_ascii_case(32u8) == true) { panic("eq_ignore_ascii_case #1592") }
    if !(32u8.eq_ignore_ascii_case(33u8) == false) { panic("eq_ignore_ascii_case #1595") }
    if !(33u8.is_ascii() == true) { panic("is_ascii #1596") }
    if !(33u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1597") }
    if !(33u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1598") }
    if !(33u8.is_ascii_control() == false) { panic("is_ascii_control #1599") }
    if !(33u8.is_ascii_digit() == false) { panic("is_ascii_digit #1600") }
    if !(33u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1601") }
    if !(33u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1602") }
    if !(33u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1603") }
    if !(33u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1604") }
    if !(33u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1605") }
    if !(33u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1606") }
    if !(33u8.to_ascii_lowercase() == 33u8) { panic("to_ascii_lowercase #1607") }
    if !(33u8.to_ascii_uppercase() == 33u8) { panic("to_ascii_uppercase #1608") }
    if !(ascii_lower(33u8) == 33u8) { panic("make_ascii_lowercase #1609") }
    if !(ascii_upper(33u8) == 33u8) { panic("make_ascii_uppercase #1610") }
    if !(33u8.eq_ignore_ascii_case(33u8) == true) { panic("eq_ignore_ascii_case #1611") }
    if !(33u8.eq_ignore_ascii_case(34u8) == false) { panic("eq_ignore_ascii_case #1614") }
    if !(47u8.is_ascii() == true) { panic("is_ascii #1615") }
    if !(47u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1616") }
    if !(47u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1617") }
    if !(47u8.is_ascii_control() == false) { panic("is_ascii_control #1618") }
    if !(47u8.is_ascii_digit() == false) { panic("is_ascii_digit #1619") }
    if !(47u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1620") }
    if !(47u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1621") }
    if !(47u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1622") }
    if !(47u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1623") }
    if !(47u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1624") }
    if !(47u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1625") }
    if !(47u8.to_ascii_lowercase() == 47u8) { panic("to_ascii_lowercase #1626") }
    if !(47u8.to_ascii_uppercase() == 47u8) { panic("to_ascii_uppercase #1627") }
    if !(ascii_lower(47u8) == 47u8) { panic("make_ascii_lowercase #1628") }
    if !(ascii_upper(47u8) == 47u8) { panic("make_ascii_uppercase #1629") }
    if !(47u8.eq_ignore_ascii_case(47u8) == true) { panic("eq_ignore_ascii_case #1630") }
    if !(47u8.eq_ignore_ascii_case(48u8) == false) { panic("eq_ignore_ascii_case #1633") }
    if !(48u8.is_ascii() == true) { panic("is_ascii #1634") }
    if !(48u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1635") }
    if !(48u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1636") }
    if !(48u8.is_ascii_control() == false) { panic("is_ascii_control #1637") }
    if !(48u8.is_ascii_digit() == true) { panic("is_ascii_digit #1638") }
    if !(48u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1639") }
    if !(48u8.is_ascii_hexdigit() == true) { panic("is_ascii_hexdigit #1640") }
    if !(48u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1641") }
    if !(48u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1642") }
    if !(48u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1643") }
    if !(48u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1644") }
    if !(48u8.to_ascii_lowercase() == 48u8) { panic("to_ascii_lowercase #1645") }
    if !(48u8.to_ascii_uppercase() == 48u8) { panic("to_ascii_uppercase #1646") }
    if !(ascii_lower(48u8) == 48u8) { panic("make_ascii_lowercase #1647") }
    if !(ascii_upper(48u8) == 48u8) { panic("make_ascii_uppercase #1648") }
    if !(48u8.eq_ignore_ascii_case(48u8) == true) { panic("eq_ignore_ascii_case #1649") }
    if !(48u8.eq_ignore_ascii_case(49u8) == false) { panic("eq_ignore_ascii_case #1652") }
    if !(57u8.is_ascii() == true) { panic("is_ascii #1653") }
    if !(57u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1654") }
    if !(57u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1655") }
    if !(57u8.is_ascii_control() == false) { panic("is_ascii_control #1656") }
    if !(57u8.is_ascii_digit() == true) { panic("is_ascii_digit #1657") }
    if !(57u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1658") }
    if !(57u8.is_ascii_hexdigit() == true) { panic("is_ascii_hexdigit #1659") }
    if !(57u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1660") }
    if !(57u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1661") }
    if !(57u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1662") }
    if !(57u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1663") }
    if !(57u8.to_ascii_lowercase() == 57u8) { panic("to_ascii_lowercase #1664") }
    if !(57u8.to_ascii_uppercase() == 57u8) { panic("to_ascii_uppercase #1665") }
    if !(ascii_lower(57u8) == 57u8) { panic("make_ascii_lowercase #1666") }
    if !(ascii_upper(57u8) == 57u8) { panic("make_ascii_uppercase #1667") }
    if !(57u8.eq_ignore_ascii_case(57u8) == true) { panic("eq_ignore_ascii_case #1668") }
    if !(57u8.eq_ignore_ascii_case(58u8) == false) { panic("eq_ignore_ascii_case #1671") }
    if !(58u8.is_ascii() == true) { panic("is_ascii #1672") }
    if !(58u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1673") }
    if !(58u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1674") }
    if !(58u8.is_ascii_control() == false) { panic("is_ascii_control #1675") }
    if !(58u8.is_ascii_digit() == false) { panic("is_ascii_digit #1676") }
    if !(58u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1677") }
    if !(58u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1678") }
    if !(58u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1679") }
    if !(58u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1680") }
}

fn group14() {
    if !(58u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1681") }
    if !(58u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1682") }
    if !(58u8.to_ascii_lowercase() == 58u8) { panic("to_ascii_lowercase #1683") }
    if !(58u8.to_ascii_uppercase() == 58u8) { panic("to_ascii_uppercase #1684") }
    if !(ascii_lower(58u8) == 58u8) { panic("make_ascii_lowercase #1685") }
    if !(ascii_upper(58u8) == 58u8) { panic("make_ascii_uppercase #1686") }
    if !(58u8.eq_ignore_ascii_case(58u8) == true) { panic("eq_ignore_ascii_case #1687") }
    if !(58u8.eq_ignore_ascii_case(59u8) == false) { panic("eq_ignore_ascii_case #1690") }
    if !(64u8.is_ascii() == true) { panic("is_ascii #1691") }
    if !(64u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1692") }
    if !(64u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1693") }
    if !(64u8.is_ascii_control() == false) { panic("is_ascii_control #1694") }
    if !(64u8.is_ascii_digit() == false) { panic("is_ascii_digit #1695") }
    if !(64u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1696") }
    if !(64u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1697") }
    if !(64u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1698") }
    if !(64u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1699") }
    if !(64u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1700") }
    if !(64u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1701") }
    if !(64u8.to_ascii_lowercase() == 64u8) { panic("to_ascii_lowercase #1702") }
    if !(64u8.to_ascii_uppercase() == 64u8) { panic("to_ascii_uppercase #1703") }
    if !(ascii_lower(64u8) == 64u8) { panic("make_ascii_lowercase #1704") }
    if !(ascii_upper(64u8) == 64u8) { panic("make_ascii_uppercase #1705") }
    if !(64u8.eq_ignore_ascii_case(64u8) == true) { panic("eq_ignore_ascii_case #1706") }
    if !(64u8.eq_ignore_ascii_case(65u8) == false) { panic("eq_ignore_ascii_case #1709") }
    if !(65u8.is_ascii() == true) { panic("is_ascii #1710") }
    if !(65u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1711") }
    if !(65u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1712") }
    if !(65u8.is_ascii_control() == false) { panic("is_ascii_control #1713") }
    if !(65u8.is_ascii_digit() == false) { panic("is_ascii_digit #1714") }
    if !(65u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1715") }
    if !(65u8.is_ascii_hexdigit() == true) { panic("is_ascii_hexdigit #1716") }
    if !(65u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1717") }
    if !(65u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1718") }
    if !(65u8.is_ascii_uppercase() == true) { panic("is_ascii_uppercase #1719") }
    if !(65u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1720") }
    if !(65u8.to_ascii_lowercase() == 97u8) { panic("to_ascii_lowercase #1721") }
    if !(65u8.to_ascii_uppercase() == 65u8) { panic("to_ascii_uppercase #1722") }
    if !(ascii_lower(65u8) == 97u8) { panic("make_ascii_lowercase #1723") }
    if !(ascii_upper(65u8) == 65u8) { panic("make_ascii_uppercase #1724") }
    if !(65u8.eq_ignore_ascii_case(65u8) == true) { panic("eq_ignore_ascii_case #1725") }
    if !(65u8.eq_ignore_ascii_case(97u8) == true) { panic("eq_ignore_ascii_case #1726") }
    if !(65u8.eq_ignore_ascii_case(66u8) == false) { panic("eq_ignore_ascii_case #1728") }
    if !(70u8.is_ascii() == true) { panic("is_ascii #1729") }
    if !(70u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1730") }
    if !(70u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1731") }
    if !(70u8.is_ascii_control() == false) { panic("is_ascii_control #1732") }
    if !(70u8.is_ascii_digit() == false) { panic("is_ascii_digit #1733") }
    if !(70u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1734") }
    if !(70u8.is_ascii_hexdigit() == true) { panic("is_ascii_hexdigit #1735") }
    if !(70u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1736") }
    if !(70u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1737") }
    if !(70u8.is_ascii_uppercase() == true) { panic("is_ascii_uppercase #1738") }
    if !(70u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1739") }
    if !(70u8.to_ascii_lowercase() == 102u8) { panic("to_ascii_lowercase #1740") }
    if !(70u8.to_ascii_uppercase() == 70u8) { panic("to_ascii_uppercase #1741") }
    if !(ascii_lower(70u8) == 102u8) { panic("make_ascii_lowercase #1742") }
    if !(ascii_upper(70u8) == 70u8) { panic("make_ascii_uppercase #1743") }
    if !(70u8.eq_ignore_ascii_case(70u8) == true) { panic("eq_ignore_ascii_case #1744") }
    if !(70u8.eq_ignore_ascii_case(102u8) == true) { panic("eq_ignore_ascii_case #1745") }
    if !(70u8.eq_ignore_ascii_case(71u8) == false) { panic("eq_ignore_ascii_case #1747") }
    if !(71u8.is_ascii() == true) { panic("is_ascii #1748") }
    if !(71u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1749") }
    if !(71u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1750") }
    if !(71u8.is_ascii_control() == false) { panic("is_ascii_control #1751") }
    if !(71u8.is_ascii_digit() == false) { panic("is_ascii_digit #1752") }
    if !(71u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1753") }
    if !(71u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1754") }
    if !(71u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1755") }
    if !(71u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1756") }
    if !(71u8.is_ascii_uppercase() == true) { panic("is_ascii_uppercase #1757") }
    if !(71u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1758") }
    if !(71u8.to_ascii_lowercase() == 103u8) { panic("to_ascii_lowercase #1759") }
    if !(71u8.to_ascii_uppercase() == 71u8) { panic("to_ascii_uppercase #1760") }
    if !(ascii_lower(71u8) == 103u8) { panic("make_ascii_lowercase #1761") }
    if !(ascii_upper(71u8) == 71u8) { panic("make_ascii_uppercase #1762") }
    if !(71u8.eq_ignore_ascii_case(71u8) == true) { panic("eq_ignore_ascii_case #1763") }
    if !(71u8.eq_ignore_ascii_case(103u8) == true) { panic("eq_ignore_ascii_case #1764") }
    if !(71u8.eq_ignore_ascii_case(72u8) == false) { panic("eq_ignore_ascii_case #1766") }
    if !(90u8.is_ascii() == true) { panic("is_ascii #1767") }
    if !(90u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1768") }
    if !(90u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1769") }
    if !(90u8.is_ascii_control() == false) { panic("is_ascii_control #1770") }
    if !(90u8.is_ascii_digit() == false) { panic("is_ascii_digit #1771") }
    if !(90u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1772") }
    if !(90u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1773") }
    if !(90u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1774") }
    if !(90u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1775") }
    if !(90u8.is_ascii_uppercase() == true) { panic("is_ascii_uppercase #1776") }
    if !(90u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1777") }
    if !(90u8.to_ascii_lowercase() == 122u8) { panic("to_ascii_lowercase #1778") }
    if !(90u8.to_ascii_uppercase() == 90u8) { panic("to_ascii_uppercase #1779") }
    if !(ascii_lower(90u8) == 122u8) { panic("make_ascii_lowercase #1780") }
    if !(ascii_upper(90u8) == 90u8) { panic("make_ascii_uppercase #1781") }
    if !(90u8.eq_ignore_ascii_case(90u8) == true) { panic("eq_ignore_ascii_case #1782") }
    if !(90u8.eq_ignore_ascii_case(122u8) == true) { panic("eq_ignore_ascii_case #1783") }
    if !(90u8.eq_ignore_ascii_case(91u8) == false) { panic("eq_ignore_ascii_case #1785") }
    if !(91u8.is_ascii() == true) { panic("is_ascii #1786") }
    if !(91u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1787") }
    if !(91u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1788") }
    if !(91u8.is_ascii_control() == false) { panic("is_ascii_control #1789") }
    if !(91u8.is_ascii_digit() == false) { panic("is_ascii_digit #1790") }
    if !(91u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1791") }
    if !(91u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1792") }
    if !(91u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1793") }
    if !(91u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1794") }
    if !(91u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1795") }
    if !(91u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1796") }
    if !(91u8.to_ascii_lowercase() == 91u8) { panic("to_ascii_lowercase #1797") }
    if !(91u8.to_ascii_uppercase() == 91u8) { panic("to_ascii_uppercase #1798") }
    if !(ascii_lower(91u8) == 91u8) { panic("make_ascii_lowercase #1799") }
    if !(ascii_upper(91u8) == 91u8) { panic("make_ascii_uppercase #1800") }
}

fn group15() {
    if !(91u8.eq_ignore_ascii_case(91u8) == true) { panic("eq_ignore_ascii_case #1801") }
    if !(91u8.eq_ignore_ascii_case(92u8) == false) { panic("eq_ignore_ascii_case #1804") }
    if !(96u8.is_ascii() == true) { panic("is_ascii #1805") }
    if !(96u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1806") }
    if !(96u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1807") }
    if !(96u8.is_ascii_control() == false) { panic("is_ascii_control #1808") }
    if !(96u8.is_ascii_digit() == false) { panic("is_ascii_digit #1809") }
    if !(96u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1810") }
    if !(96u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1811") }
    if !(96u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1812") }
    if !(96u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1813") }
    if !(96u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1814") }
    if !(96u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1815") }
    if !(96u8.to_ascii_lowercase() == 96u8) { panic("to_ascii_lowercase #1816") }
    if !(96u8.to_ascii_uppercase() == 96u8) { panic("to_ascii_uppercase #1817") }
    if !(ascii_lower(96u8) == 96u8) { panic("make_ascii_lowercase #1818") }
    if !(ascii_upper(96u8) == 96u8) { panic("make_ascii_uppercase #1819") }
    if !(96u8.eq_ignore_ascii_case(96u8) == true) { panic("eq_ignore_ascii_case #1820") }
    if !(96u8.eq_ignore_ascii_case(97u8) == false) { panic("eq_ignore_ascii_case #1823") }
    if !(97u8.is_ascii() == true) { panic("is_ascii #1824") }
    if !(97u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1825") }
    if !(97u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1826") }
    if !(97u8.is_ascii_control() == false) { panic("is_ascii_control #1827") }
    if !(97u8.is_ascii_digit() == false) { panic("is_ascii_digit #1828") }
    if !(97u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1829") }
    if !(97u8.is_ascii_hexdigit() == true) { panic("is_ascii_hexdigit #1830") }
    if !(97u8.is_ascii_lowercase() == true) { panic("is_ascii_lowercase #1831") }
    if !(97u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1832") }
    if !(97u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1833") }
    if !(97u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1834") }
    if !(97u8.to_ascii_lowercase() == 97u8) { panic("to_ascii_lowercase #1835") }
    if !(97u8.to_ascii_uppercase() == 65u8) { panic("to_ascii_uppercase #1836") }
    if !(ascii_lower(97u8) == 97u8) { panic("make_ascii_lowercase #1837") }
    if !(ascii_upper(97u8) == 65u8) { panic("make_ascii_uppercase #1838") }
    if !(97u8.eq_ignore_ascii_case(97u8) == true) { panic("eq_ignore_ascii_case #1839") }
    if !(97u8.eq_ignore_ascii_case(65u8) == true) { panic("eq_ignore_ascii_case #1841") }
    if !(97u8.eq_ignore_ascii_case(98u8) == false) { panic("eq_ignore_ascii_case #1842") }
    if !(102u8.is_ascii() == true) { panic("is_ascii #1843") }
    if !(102u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1844") }
    if !(102u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1845") }
    if !(102u8.is_ascii_control() == false) { panic("is_ascii_control #1846") }
    if !(102u8.is_ascii_digit() == false) { panic("is_ascii_digit #1847") }
    if !(102u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1848") }
    if !(102u8.is_ascii_hexdigit() == true) { panic("is_ascii_hexdigit #1849") }
    if !(102u8.is_ascii_lowercase() == true) { panic("is_ascii_lowercase #1850") }
    if !(102u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1851") }
    if !(102u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1852") }
    if !(102u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1853") }
    if !(102u8.to_ascii_lowercase() == 102u8) { panic("to_ascii_lowercase #1854") }
    if !(102u8.to_ascii_uppercase() == 70u8) { panic("to_ascii_uppercase #1855") }
    if !(ascii_lower(102u8) == 102u8) { panic("make_ascii_lowercase #1856") }
    if !(ascii_upper(102u8) == 70u8) { panic("make_ascii_uppercase #1857") }
    if !(102u8.eq_ignore_ascii_case(102u8) == true) { panic("eq_ignore_ascii_case #1858") }
    if !(102u8.eq_ignore_ascii_case(70u8) == true) { panic("eq_ignore_ascii_case #1860") }
    if !(102u8.eq_ignore_ascii_case(103u8) == false) { panic("eq_ignore_ascii_case #1861") }
    if !(103u8.is_ascii() == true) { panic("is_ascii #1862") }
    if !(103u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1863") }
    if !(103u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1864") }
    if !(103u8.is_ascii_control() == false) { panic("is_ascii_control #1865") }
    if !(103u8.is_ascii_digit() == false) { panic("is_ascii_digit #1866") }
    if !(103u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1867") }
    if !(103u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1868") }
    if !(103u8.is_ascii_lowercase() == true) { panic("is_ascii_lowercase #1869") }
    if !(103u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1870") }
    if !(103u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1871") }
    if !(103u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1872") }
    if !(103u8.to_ascii_lowercase() == 103u8) { panic("to_ascii_lowercase #1873") }
    if !(103u8.to_ascii_uppercase() == 71u8) { panic("to_ascii_uppercase #1874") }
    if !(ascii_lower(103u8) == 103u8) { panic("make_ascii_lowercase #1875") }
    if !(ascii_upper(103u8) == 71u8) { panic("make_ascii_uppercase #1876") }
    if !(103u8.eq_ignore_ascii_case(103u8) == true) { panic("eq_ignore_ascii_case #1877") }
    if !(103u8.eq_ignore_ascii_case(71u8) == true) { panic("eq_ignore_ascii_case #1879") }
    if !(103u8.eq_ignore_ascii_case(104u8) == false) { panic("eq_ignore_ascii_case #1880") }
    if !(122u8.is_ascii() == true) { panic("is_ascii #1881") }
    if !(122u8.is_ascii_alphabetic() == true) { panic("is_ascii_alphabetic #1882") }
    if !(122u8.is_ascii_alphanumeric() == true) { panic("is_ascii_alphanumeric #1883") }
    if !(122u8.is_ascii_control() == false) { panic("is_ascii_control #1884") }
    if !(122u8.is_ascii_digit() == false) { panic("is_ascii_digit #1885") }
    if !(122u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1886") }
    if !(122u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1887") }
    if !(122u8.is_ascii_lowercase() == true) { panic("is_ascii_lowercase #1888") }
    if !(122u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1889") }
    if !(122u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1890") }
    if !(122u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1891") }
    if !(122u8.to_ascii_lowercase() == 122u8) { panic("to_ascii_lowercase #1892") }
    if !(122u8.to_ascii_uppercase() == 90u8) { panic("to_ascii_uppercase #1893") }
    if !(ascii_lower(122u8) == 122u8) { panic("make_ascii_lowercase #1894") }
    if !(ascii_upper(122u8) == 90u8) { panic("make_ascii_uppercase #1895") }
    if !(122u8.eq_ignore_ascii_case(122u8) == true) { panic("eq_ignore_ascii_case #1896") }
    if !(122u8.eq_ignore_ascii_case(90u8) == true) { panic("eq_ignore_ascii_case #1898") }
    if !(122u8.eq_ignore_ascii_case(123u8) == false) { panic("eq_ignore_ascii_case #1899") }
    if !(123u8.is_ascii() == true) { panic("is_ascii #1900") }
    if !(123u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1901") }
    if !(123u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1902") }
    if !(123u8.is_ascii_control() == false) { panic("is_ascii_control #1903") }
    if !(123u8.is_ascii_digit() == false) { panic("is_ascii_digit #1904") }
    if !(123u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1905") }
    if !(123u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1906") }
    if !(123u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1907") }
    if !(123u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1908") }
    if !(123u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1909") }
    if !(123u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1910") }
    if !(123u8.to_ascii_lowercase() == 123u8) { panic("to_ascii_lowercase #1911") }
    if !(123u8.to_ascii_uppercase() == 123u8) { panic("to_ascii_uppercase #1912") }
    if !(ascii_lower(123u8) == 123u8) { panic("make_ascii_lowercase #1913") }
    if !(ascii_upper(123u8) == 123u8) { panic("make_ascii_uppercase #1914") }
    if !(123u8.eq_ignore_ascii_case(123u8) == true) { panic("eq_ignore_ascii_case #1915") }
    if !(123u8.eq_ignore_ascii_case(124u8) == false) { panic("eq_ignore_ascii_case #1918") }
    if !(126u8.is_ascii() == true) { panic("is_ascii #1919") }
    if !(126u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1920") }
}

fn group16() {
    if !(126u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1921") }
    if !(126u8.is_ascii_control() == false) { panic("is_ascii_control #1922") }
    if !(126u8.is_ascii_digit() == false) { panic("is_ascii_digit #1923") }
    if !(126u8.is_ascii_graphic() == true) { panic("is_ascii_graphic #1924") }
    if !(126u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1925") }
    if !(126u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1926") }
    if !(126u8.is_ascii_punctuation() == true) { panic("is_ascii_punctuation #1927") }
    if !(126u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1928") }
    if !(126u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1929") }
    if !(126u8.to_ascii_lowercase() == 126u8) { panic("to_ascii_lowercase #1930") }
    if !(126u8.to_ascii_uppercase() == 126u8) { panic("to_ascii_uppercase #1931") }
    if !(ascii_lower(126u8) == 126u8) { panic("make_ascii_lowercase #1932") }
    if !(ascii_upper(126u8) == 126u8) { panic("make_ascii_uppercase #1933") }
    if !(126u8.eq_ignore_ascii_case(126u8) == true) { panic("eq_ignore_ascii_case #1934") }
    if !(126u8.eq_ignore_ascii_case(127u8) == false) { panic("eq_ignore_ascii_case #1937") }
    if !(127u8.is_ascii() == true) { panic("is_ascii #1938") }
    if !(127u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1939") }
    if !(127u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1940") }
    if !(127u8.is_ascii_control() == true) { panic("is_ascii_control #1941") }
    if !(127u8.is_ascii_digit() == false) { panic("is_ascii_digit #1942") }
    if !(127u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1943") }
    if !(127u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1944") }
    if !(127u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1945") }
    if !(127u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1946") }
    if !(127u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1947") }
    if !(127u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1948") }
    if !(127u8.to_ascii_lowercase() == 127u8) { panic("to_ascii_lowercase #1949") }
    if !(127u8.to_ascii_uppercase() == 127u8) { panic("to_ascii_uppercase #1950") }
    if !(ascii_lower(127u8) == 127u8) { panic("make_ascii_lowercase #1951") }
    if !(ascii_upper(127u8) == 127u8) { panic("make_ascii_uppercase #1952") }
    if !(127u8.eq_ignore_ascii_case(127u8) == true) { panic("eq_ignore_ascii_case #1953") }
    if !(127u8.eq_ignore_ascii_case(128u8) == false) { panic("eq_ignore_ascii_case #1956") }
    if !(128u8.is_ascii() == false) { panic("is_ascii #1957") }
    if !(128u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1958") }
    if !(128u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1959") }
    if !(128u8.is_ascii_control() == false) { panic("is_ascii_control #1960") }
    if !(128u8.is_ascii_digit() == false) { panic("is_ascii_digit #1961") }
    if !(128u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1962") }
    if !(128u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1963") }
    if !(128u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1964") }
    if !(128u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1965") }
    if !(128u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1966") }
    if !(128u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1967") }
    if !(128u8.to_ascii_lowercase() == 128u8) { panic("to_ascii_lowercase #1968") }
    if !(128u8.to_ascii_uppercase() == 128u8) { panic("to_ascii_uppercase #1969") }
    if !(ascii_lower(128u8) == 128u8) { panic("make_ascii_lowercase #1970") }
    if !(ascii_upper(128u8) == 128u8) { panic("make_ascii_uppercase #1971") }
    if !(128u8.eq_ignore_ascii_case(128u8) == true) { panic("eq_ignore_ascii_case #1972") }
    if !(128u8.eq_ignore_ascii_case(129u8) == false) { panic("eq_ignore_ascii_case #1975") }
    if !(200u8.is_ascii() == false) { panic("is_ascii #1976") }
    if !(200u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1977") }
    if !(200u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1978") }
    if !(200u8.is_ascii_control() == false) { panic("is_ascii_control #1979") }
    if !(200u8.is_ascii_digit() == false) { panic("is_ascii_digit #1980") }
    if !(200u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #1981") }
    if !(200u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #1982") }
    if !(200u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #1983") }
    if !(200u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #1984") }
    if !(200u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #1985") }
    if !(200u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #1986") }
    if !(200u8.to_ascii_lowercase() == 200u8) { panic("to_ascii_lowercase #1987") }
    if !(200u8.to_ascii_uppercase() == 200u8) { panic("to_ascii_uppercase #1988") }
    if !(ascii_lower(200u8) == 200u8) { panic("make_ascii_lowercase #1989") }
    if !(ascii_upper(200u8) == 200u8) { panic("make_ascii_uppercase #1990") }
    if !(200u8.eq_ignore_ascii_case(200u8) == true) { panic("eq_ignore_ascii_case #1991") }
    if !(200u8.eq_ignore_ascii_case(201u8) == false) { panic("eq_ignore_ascii_case #1994") }
    if !(255u8.is_ascii() == false) { panic("is_ascii #1995") }
    if !(255u8.is_ascii_alphabetic() == false) { panic("is_ascii_alphabetic #1996") }
    if !(255u8.is_ascii_alphanumeric() == false) { panic("is_ascii_alphanumeric #1997") }
    if !(255u8.is_ascii_control() == false) { panic("is_ascii_control #1998") }
    if !(255u8.is_ascii_digit() == false) { panic("is_ascii_digit #1999") }
    if !(255u8.is_ascii_graphic() == false) { panic("is_ascii_graphic #2000") }
    if !(255u8.is_ascii_hexdigit() == false) { panic("is_ascii_hexdigit #2001") }
    if !(255u8.is_ascii_lowercase() == false) { panic("is_ascii_lowercase #2002") }
    if !(255u8.is_ascii_punctuation() == false) { panic("is_ascii_punctuation #2003") }
    if !(255u8.is_ascii_uppercase() == false) { panic("is_ascii_uppercase #2004") }
    if !(255u8.is_ascii_whitespace() == false) { panic("is_ascii_whitespace #2005") }
    if !(255u8.to_ascii_lowercase() == 255u8) { panic("to_ascii_lowercase #2006") }
    if !(255u8.to_ascii_uppercase() == 255u8) { panic("to_ascii_uppercase #2007") }
    if !(ascii_lower(255u8) == 255u8) { panic("make_ascii_lowercase #2008") }
    if !(ascii_upper(255u8) == 255u8) { panic("make_ascii_uppercase #2009") }
    if !(255u8.eq_ignore_ascii_case(255u8) == true) { panic("eq_ignore_ascii_case #2010") }
    if !(255u8.eq_ignore_ascii_case(0u8) == false) { panic("eq_ignore_ascii_case #2013") }
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
    0
}
