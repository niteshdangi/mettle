// profiles: debug release
// Every stable integer operation family at this width; expected values are
// computed independently. A failing check panics naming its operation.
import core.num
import core.num.{IntErrorKind, ParseIntError}
import core.panic.panic

fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(_) => false }
}

fn parsed<T: Copy>(result: (T throws ParseIntError)): T? {
    match result { success(value) => present(value), failure(_) => none }
}

fn kind<T: Copy>(result: (T throws ParseIntError)): IntErrorKind? {
    match result { success(_) => none, failure(error) => present(error.kind) }
}

fn group0() {
    if !(u32.BITS == 32u32) { panic("BITS #1") }
    if !(u32.MIN == 0u32) { panic("MIN #2") }
    if !(u32.MAX == 4294967295u32) { panic("MAX #3") }
    if !(missing(u32.MAX.checked_add(1u32))) { panic("checked_add #4") }
    if !(u32.MAX.wrapping_add(1u32) == 0u32) { panic("wrapping_add #5") }
    if !(u32.MAX.overflowing_add(1u32).0 == 0u32 && u32.MAX.overflowing_add(1u32).1 == true) { panic("overflowing_add #6") }
    if !(u32.MAX.saturating_add(1u32) == u32.MAX) { panic("saturating_add #7") }
    if !(u32.MAX.checked_sub(1u32) == present(4294967294u32)) { panic("checked_sub #8") }
    if !(u32.MAX.wrapping_sub(1u32) == 4294967294u32) { panic("wrapping_sub #9") }
    if !(u32.MAX.overflowing_sub(1u32).0 == 4294967294u32 && u32.MAX.overflowing_sub(1u32).1 == false) { panic("overflowing_sub #10") }
    if !(u32.MAX.saturating_sub(1u32) == 4294967294u32) { panic("saturating_sub #11") }
    if !(u32.MAX.strict_sub(1u32) == 4294967294u32) { panic("strict_sub #12") }
    if !(unsafe { u32.MAX.unchecked_sub(1u32) } == 4294967294u32) { panic("unchecked_sub #13") }
    if !(u32.MAX.checked_mul(1u32) == present(u32.MAX)) { panic("checked_mul #14") }
    if !(u32.MAX.wrapping_mul(1u32) == u32.MAX) { panic("wrapping_mul #15") }
    if !(u32.MAX.overflowing_mul(1u32).0 == u32.MAX && u32.MAX.overflowing_mul(1u32).1 == false) { panic("overflowing_mul #16") }
    if !(u32.MAX.saturating_mul(1u32) == u32.MAX) { panic("saturating_mul #17") }
    if !(u32.MAX.strict_mul(1u32) == u32.MAX) { panic("strict_mul #18") }
    if !(unsafe { u32.MAX.unchecked_mul(1u32) } == u32.MAX) { panic("unchecked_mul #19") }
    if !(u32.MAX.checked_div(1u32) == present(u32.MAX)) { panic("checked_div #20") }
    if !(u32.MAX.wrapping_div(1u32) == u32.MAX) { panic("wrapping_div #21") }
    if !(u32.MAX.overflowing_div(1u32).0 == u32.MAX && u32.MAX.overflowing_div(1u32).1 == false) { panic("overflowing_div #22") }
    if !(u32.MAX.strict_div(1u32) == u32.MAX) { panic("strict_div #23") }
    if !(u32.MAX.saturating_div(1u32) == u32.MAX) { panic("saturating_div #24") }
    if !(u32.MAX.checked_rem(1u32) == present(0u32)) { panic("checked_rem #25") }
    if !(u32.MAX.wrapping_rem(1u32) == 0u32) { panic("wrapping_rem #26") }
    if !(u32.MAX.overflowing_rem(1u32).0 == 0u32 && u32.MAX.overflowing_rem(1u32).1 == false) { panic("overflowing_rem #27") }
    if !(u32.MAX.strict_rem(1u32) == 0u32) { panic("strict_rem #28") }
    if !(u32.MAX.checked_div_euclid(1u32) == present(u32.MAX)) { panic("checked_div_euclid #29") }
    if !(u32.MAX.wrapping_div_euclid(1u32) == u32.MAX) { panic("wrapping_div_euclid #30") }
    if !(u32.MAX.overflowing_div_euclid(1u32).0 == u32.MAX && u32.MAX.overflowing_div_euclid(1u32).1 == false) { panic("overflowing_div_euclid #31") }
    if !(u32.MAX.strict_div_euclid(1u32) == u32.MAX) { panic("strict_div_euclid #32") }
    if !(u32.MAX.div_euclid(1u32) == u32.MAX) { panic("div_euclid #33") }
    if !(u32.MAX.checked_rem_euclid(1u32) == present(0u32)) { panic("checked_rem_euclid #34") }
    if !(u32.MAX.wrapping_rem_euclid(1u32) == 0u32) { panic("wrapping_rem_euclid #35") }
    if !(u32.MAX.overflowing_rem_euclid(1u32).0 == 0u32 && u32.MAX.overflowing_rem_euclid(1u32).1 == false) { panic("overflowing_rem_euclid #36") }
    if !(u32.MAX.strict_rem_euclid(1u32) == 0u32) { panic("strict_rem_euclid #37") }
    if !(u32.MAX.rem_euclid(1u32) == 0u32) { panic("rem_euclid #38") }
    if !(u32.MAX.abs_diff(1u32) == 4294967294u32) { panic("abs_diff #39") }
    if !(u32.MAX.midpoint(1u32) == 2147483648u32) { panic("midpoint #40") }
    if !(0u32.checked_add(1u32) == present(1u32)) { panic("checked_add #41") }
    if !(0u32.wrapping_add(1u32) == 1u32) { panic("wrapping_add #42") }
    if !(0u32.overflowing_add(1u32).0 == 1u32 && 0u32.overflowing_add(1u32).1 == false) { panic("overflowing_add #43") }
    if !(0u32.saturating_add(1u32) == 1u32) { panic("saturating_add #44") }
    if !(0u32.strict_add(1u32) == 1u32) { panic("strict_add #45") }
    if !(unsafe { 0u32.unchecked_add(1u32) } == 1u32) { panic("unchecked_add #46") }
    if !(missing(0u32.checked_sub(1u32))) { panic("checked_sub #47") }
    if !(0u32.wrapping_sub(1u32) == u32.MAX) { panic("wrapping_sub #48") }
    if !(0u32.overflowing_sub(1u32).0 == u32.MAX && 0u32.overflowing_sub(1u32).1 == true) { panic("overflowing_sub #49") }
    if !(0u32.saturating_sub(1u32) == 0u32) { panic("saturating_sub #50") }
    if !(0u32.checked_mul(1u32) == present(0u32)) { panic("checked_mul #51") }
    if !(0u32.wrapping_mul(1u32) == 0u32) { panic("wrapping_mul #52") }
    if !(0u32.overflowing_mul(1u32).0 == 0u32 && 0u32.overflowing_mul(1u32).1 == false) { panic("overflowing_mul #53") }
    if !(0u32.saturating_mul(1u32) == 0u32) { panic("saturating_mul #54") }
    if !(0u32.strict_mul(1u32) == 0u32) { panic("strict_mul #55") }
    if !(unsafe { 0u32.unchecked_mul(1u32) } == 0u32) { panic("unchecked_mul #56") }
    if !(0u32.checked_div(1u32) == present(0u32)) { panic("checked_div #57") }
    if !(0u32.wrapping_div(1u32) == 0u32) { panic("wrapping_div #58") }
    if !(0u32.overflowing_div(1u32).0 == 0u32 && 0u32.overflowing_div(1u32).1 == false) { panic("overflowing_div #59") }
    if !(0u32.strict_div(1u32) == 0u32) { panic("strict_div #60") }
    if !(0u32.saturating_div(1u32) == 0u32) { panic("saturating_div #61") }
    if !(0u32.checked_rem(1u32) == present(0u32)) { panic("checked_rem #62") }
    if !(0u32.wrapping_rem(1u32) == 0u32) { panic("wrapping_rem #63") }
    if !(0u32.overflowing_rem(1u32).0 == 0u32 && 0u32.overflowing_rem(1u32).1 == false) { panic("overflowing_rem #64") }
    if !(0u32.strict_rem(1u32) == 0u32) { panic("strict_rem #65") }
    if !(0u32.checked_div_euclid(1u32) == present(0u32)) { panic("checked_div_euclid #66") }
    if !(0u32.wrapping_div_euclid(1u32) == 0u32) { panic("wrapping_div_euclid #67") }
    if !(0u32.overflowing_div_euclid(1u32).0 == 0u32 && 0u32.overflowing_div_euclid(1u32).1 == false) { panic("overflowing_div_euclid #68") }
    if !(0u32.strict_div_euclid(1u32) == 0u32) { panic("strict_div_euclid #69") }
    if !(0u32.div_euclid(1u32) == 0u32) { panic("div_euclid #70") }
    if !(0u32.checked_rem_euclid(1u32) == present(0u32)) { panic("checked_rem_euclid #71") }
    if !(0u32.wrapping_rem_euclid(1u32) == 0u32) { panic("wrapping_rem_euclid #72") }
    if !(0u32.overflowing_rem_euclid(1u32).0 == 0u32 && 0u32.overflowing_rem_euclid(1u32).1 == false) { panic("overflowing_rem_euclid #73") }
    if !(0u32.strict_rem_euclid(1u32) == 0u32) { panic("strict_rem_euclid #74") }
    if !(0u32.rem_euclid(1u32) == 0u32) { panic("rem_euclid #75") }
    if !(0u32.abs_diff(1u32) == 1u32) { panic("abs_diff #76") }
    if !(0u32.midpoint(1u32) == 0u32) { panic("midpoint #77") }
    if !(1000u32.checked_add(7u32) == present(1007u32)) { panic("checked_add #78") }
    if !(1000u32.wrapping_add(7u32) == 1007u32) { panic("wrapping_add #79") }
    if !(1000u32.overflowing_add(7u32).0 == 1007u32 && 1000u32.overflowing_add(7u32).1 == false) { panic("overflowing_add #80") }
    if !(1000u32.saturating_add(7u32) == 1007u32) { panic("saturating_add #81") }
    if !(1000u32.strict_add(7u32) == 1007u32) { panic("strict_add #82") }
    if !(unsafe { 1000u32.unchecked_add(7u32) } == 1007u32) { panic("unchecked_add #83") }
    if !(1000u32.checked_sub(7u32) == present(993u32)) { panic("checked_sub #84") }
    if !(1000u32.wrapping_sub(7u32) == 993u32) { panic("wrapping_sub #85") }
    if !(1000u32.overflowing_sub(7u32).0 == 993u32 && 1000u32.overflowing_sub(7u32).1 == false) { panic("overflowing_sub #86") }
    if !(1000u32.saturating_sub(7u32) == 993u32) { panic("saturating_sub #87") }
    if !(1000u32.strict_sub(7u32) == 993u32) { panic("strict_sub #88") }
    if !(unsafe { 1000u32.unchecked_sub(7u32) } == 993u32) { panic("unchecked_sub #89") }
    if !(1000u32.checked_mul(7u32) == present(7000u32)) { panic("checked_mul #90") }
    if !(1000u32.wrapping_mul(7u32) == 7000u32) { panic("wrapping_mul #91") }
    if !(1000u32.overflowing_mul(7u32).0 == 7000u32 && 1000u32.overflowing_mul(7u32).1 == false) { panic("overflowing_mul #92") }
    if !(1000u32.saturating_mul(7u32) == 7000u32) { panic("saturating_mul #93") }
    if !(1000u32.strict_mul(7u32) == 7000u32) { panic("strict_mul #94") }
    if !(unsafe { 1000u32.unchecked_mul(7u32) } == 7000u32) { panic("unchecked_mul #95") }
    if !(1000u32.checked_div(7u32) == present(142u32)) { panic("checked_div #96") }
    if !(1000u32.wrapping_div(7u32) == 142u32) { panic("wrapping_div #97") }
    if !(1000u32.overflowing_div(7u32).0 == 142u32 && 1000u32.overflowing_div(7u32).1 == false) { panic("overflowing_div #98") }
    if !(1000u32.strict_div(7u32) == 142u32) { panic("strict_div #99") }
    if !(1000u32.saturating_div(7u32) == 142u32) { panic("saturating_div #100") }
    if !(1000u32.checked_rem(7u32) == present(6u32)) { panic("checked_rem #101") }
    if !(1000u32.wrapping_rem(7u32) == 6u32) { panic("wrapping_rem #102") }
    if !(1000u32.overflowing_rem(7u32).0 == 6u32 && 1000u32.overflowing_rem(7u32).1 == false) { panic("overflowing_rem #103") }
    if !(1000u32.strict_rem(7u32) == 6u32) { panic("strict_rem #104") }
    if !(1000u32.checked_div_euclid(7u32) == present(142u32)) { panic("checked_div_euclid #105") }
    if !(1000u32.wrapping_div_euclid(7u32) == 142u32) { panic("wrapping_div_euclid #106") }
    if !(1000u32.overflowing_div_euclid(7u32).0 == 142u32 && 1000u32.overflowing_div_euclid(7u32).1 == false) { panic("overflowing_div_euclid #107") }
    if !(1000u32.strict_div_euclid(7u32) == 142u32) { panic("strict_div_euclid #108") }
    if !(1000u32.div_euclid(7u32) == 142u32) { panic("div_euclid #109") }
    if !(1000u32.checked_rem_euclid(7u32) == present(6u32)) { panic("checked_rem_euclid #110") }
    if !(1000u32.wrapping_rem_euclid(7u32) == 6u32) { panic("wrapping_rem_euclid #111") }
    if !(1000u32.overflowing_rem_euclid(7u32).0 == 6u32 && 1000u32.overflowing_rem_euclid(7u32).1 == false) { panic("overflowing_rem_euclid #112") }
    if !(1000u32.strict_rem_euclid(7u32) == 6u32) { panic("strict_rem_euclid #113") }
    if !(1000u32.rem_euclid(7u32) == 6u32) { panic("rem_euclid #114") }
    if !(1000u32.abs_diff(7u32) == 993u32) { panic("abs_diff #115") }
    if !(1000u32.midpoint(7u32) == 503u32) { panic("midpoint #116") }
    if !(7u32.checked_add(1000u32) == present(1007u32)) { panic("checked_add #117") }
    if !(7u32.wrapping_add(1000u32) == 1007u32) { panic("wrapping_add #118") }
    if !(7u32.overflowing_add(1000u32).0 == 1007u32 && 7u32.overflowing_add(1000u32).1 == false) { panic("overflowing_add #119") }
    if !(7u32.saturating_add(1000u32) == 1007u32) { panic("saturating_add #120") }
}

fn group1() {
    if !(7u32.strict_add(1000u32) == 1007u32) { panic("strict_add #121") }
    if !(unsafe { 7u32.unchecked_add(1000u32) } == 1007u32) { panic("unchecked_add #122") }
    if !(missing(7u32.checked_sub(1000u32))) { panic("checked_sub #123") }
    if !(7u32.wrapping_sub(1000u32) == 4294966303u32) { panic("wrapping_sub #124") }
    if !(7u32.overflowing_sub(1000u32).0 == 4294966303u32 && 7u32.overflowing_sub(1000u32).1 == true) { panic("overflowing_sub #125") }
    if !(7u32.saturating_sub(1000u32) == 0u32) { panic("saturating_sub #126") }
    if !(7u32.checked_mul(1000u32) == present(7000u32)) { panic("checked_mul #127") }
    if !(7u32.wrapping_mul(1000u32) == 7000u32) { panic("wrapping_mul #128") }
    if !(7u32.overflowing_mul(1000u32).0 == 7000u32 && 7u32.overflowing_mul(1000u32).1 == false) { panic("overflowing_mul #129") }
    if !(7u32.saturating_mul(1000u32) == 7000u32) { panic("saturating_mul #130") }
    if !(7u32.strict_mul(1000u32) == 7000u32) { panic("strict_mul #131") }
    if !(unsafe { 7u32.unchecked_mul(1000u32) } == 7000u32) { panic("unchecked_mul #132") }
    if !(7u32.checked_div(1000u32) == present(0u32)) { panic("checked_div #133") }
    if !(7u32.wrapping_div(1000u32) == 0u32) { panic("wrapping_div #134") }
    if !(7u32.overflowing_div(1000u32).0 == 0u32 && 7u32.overflowing_div(1000u32).1 == false) { panic("overflowing_div #135") }
    if !(7u32.strict_div(1000u32) == 0u32) { panic("strict_div #136") }
    if !(7u32.saturating_div(1000u32) == 0u32) { panic("saturating_div #137") }
    if !(7u32.checked_rem(1000u32) == present(7u32)) { panic("checked_rem #138") }
    if !(7u32.wrapping_rem(1000u32) == 7u32) { panic("wrapping_rem #139") }
    if !(7u32.overflowing_rem(1000u32).0 == 7u32 && 7u32.overflowing_rem(1000u32).1 == false) { panic("overflowing_rem #140") }
    if !(7u32.strict_rem(1000u32) == 7u32) { panic("strict_rem #141") }
    if !(7u32.checked_div_euclid(1000u32) == present(0u32)) { panic("checked_div_euclid #142") }
    if !(7u32.wrapping_div_euclid(1000u32) == 0u32) { panic("wrapping_div_euclid #143") }
    if !(7u32.overflowing_div_euclid(1000u32).0 == 0u32 && 7u32.overflowing_div_euclid(1000u32).1 == false) { panic("overflowing_div_euclid #144") }
    if !(7u32.strict_div_euclid(1000u32) == 0u32) { panic("strict_div_euclid #145") }
    if !(7u32.div_euclid(1000u32) == 0u32) { panic("div_euclid #146") }
    if !(7u32.checked_rem_euclid(1000u32) == present(7u32)) { panic("checked_rem_euclid #147") }
    if !(7u32.wrapping_rem_euclid(1000u32) == 7u32) { panic("wrapping_rem_euclid #148") }
    if !(7u32.overflowing_rem_euclid(1000u32).0 == 7u32 && 7u32.overflowing_rem_euclid(1000u32).1 == false) { panic("overflowing_rem_euclid #149") }
    if !(7u32.strict_rem_euclid(1000u32) == 7u32) { panic("strict_rem_euclid #150") }
    if !(7u32.rem_euclid(1000u32) == 7u32) { panic("rem_euclid #151") }
    if !(7u32.abs_diff(1000u32) == 993u32) { panic("abs_diff #152") }
    if !(7u32.midpoint(1000u32) == 503u32) { panic("midpoint #153") }
    if !(missing(u32.MAX.checked_add(2u32))) { panic("checked_add #154") }
    if !(u32.MAX.wrapping_add(2u32) == 1u32) { panic("wrapping_add #155") }
    if !(u32.MAX.overflowing_add(2u32).0 == 1u32 && u32.MAX.overflowing_add(2u32).1 == true) { panic("overflowing_add #156") }
    if !(u32.MAX.saturating_add(2u32) == u32.MAX) { panic("saturating_add #157") }
    if !(u32.MAX.checked_sub(2u32) == present(4294967293u32)) { panic("checked_sub #158") }
    if !(u32.MAX.wrapping_sub(2u32) == 4294967293u32) { panic("wrapping_sub #159") }
    if !(u32.MAX.overflowing_sub(2u32).0 == 4294967293u32 && u32.MAX.overflowing_sub(2u32).1 == false) { panic("overflowing_sub #160") }
    if !(u32.MAX.saturating_sub(2u32) == 4294967293u32) { panic("saturating_sub #161") }
    if !(u32.MAX.strict_sub(2u32) == 4294967293u32) { panic("strict_sub #162") }
    if !(unsafe { u32.MAX.unchecked_sub(2u32) } == 4294967293u32) { panic("unchecked_sub #163") }
    if !(missing(u32.MAX.checked_mul(2u32))) { panic("checked_mul #164") }
    if !(u32.MAX.wrapping_mul(2u32) == 4294967294u32) { panic("wrapping_mul #165") }
    if !(u32.MAX.overflowing_mul(2u32).0 == 4294967294u32 && u32.MAX.overflowing_mul(2u32).1 == true) { panic("overflowing_mul #166") }
    if !(u32.MAX.saturating_mul(2u32) == u32.MAX) { panic("saturating_mul #167") }
    if !(u32.MAX.checked_div(2u32) == present(2147483647u32)) { panic("checked_div #168") }
    if !(u32.MAX.wrapping_div(2u32) == 2147483647u32) { panic("wrapping_div #169") }
    if !(u32.MAX.overflowing_div(2u32).0 == 2147483647u32 && u32.MAX.overflowing_div(2u32).1 == false) { panic("overflowing_div #170") }
    if !(u32.MAX.strict_div(2u32) == 2147483647u32) { panic("strict_div #171") }
    if !(u32.MAX.saturating_div(2u32) == 2147483647u32) { panic("saturating_div #172") }
    if !(u32.MAX.checked_rem(2u32) == present(1u32)) { panic("checked_rem #173") }
    if !(u32.MAX.wrapping_rem(2u32) == 1u32) { panic("wrapping_rem #174") }
    if !(u32.MAX.overflowing_rem(2u32).0 == 1u32 && u32.MAX.overflowing_rem(2u32).1 == false) { panic("overflowing_rem #175") }
    if !(u32.MAX.strict_rem(2u32) == 1u32) { panic("strict_rem #176") }
    if !(u32.MAX.checked_div_euclid(2u32) == present(2147483647u32)) { panic("checked_div_euclid #177") }
    if !(u32.MAX.wrapping_div_euclid(2u32) == 2147483647u32) { panic("wrapping_div_euclid #178") }
    if !(u32.MAX.overflowing_div_euclid(2u32).0 == 2147483647u32 && u32.MAX.overflowing_div_euclid(2u32).1 == false) { panic("overflowing_div_euclid #179") }
    if !(u32.MAX.strict_div_euclid(2u32) == 2147483647u32) { panic("strict_div_euclid #180") }
    if !(u32.MAX.div_euclid(2u32) == 2147483647u32) { panic("div_euclid #181") }
    if !(u32.MAX.checked_rem_euclid(2u32) == present(1u32)) { panic("checked_rem_euclid #182") }
    if !(u32.MAX.wrapping_rem_euclid(2u32) == 1u32) { panic("wrapping_rem_euclid #183") }
    if !(u32.MAX.overflowing_rem_euclid(2u32).0 == 1u32 && u32.MAX.overflowing_rem_euclid(2u32).1 == false) { panic("overflowing_rem_euclid #184") }
    if !(u32.MAX.strict_rem_euclid(2u32) == 1u32) { panic("strict_rem_euclid #185") }
    if !(u32.MAX.rem_euclid(2u32) == 1u32) { panic("rem_euclid #186") }
    if !(u32.MAX.abs_diff(2u32) == 4294967293u32) { panic("abs_diff #187") }
    if !(u32.MAX.midpoint(2u32) == 2147483648u32) { panic("midpoint #188") }
    if !(0u32.checked_add(0u32) == present(0u32)) { panic("checked_add #189") }
    if !(0u32.wrapping_add(0u32) == 0u32) { panic("wrapping_add #190") }
    if !(0u32.overflowing_add(0u32).0 == 0u32 && 0u32.overflowing_add(0u32).1 == false) { panic("overflowing_add #191") }
    if !(0u32.saturating_add(0u32) == 0u32) { panic("saturating_add #192") }
    if !(0u32.strict_add(0u32) == 0u32) { panic("strict_add #193") }
    if !(unsafe { 0u32.unchecked_add(0u32) } == 0u32) { panic("unchecked_add #194") }
    if !(0u32.checked_sub(0u32) == present(0u32)) { panic("checked_sub #195") }
    if !(0u32.wrapping_sub(0u32) == 0u32) { panic("wrapping_sub #196") }
    if !(0u32.overflowing_sub(0u32).0 == 0u32 && 0u32.overflowing_sub(0u32).1 == false) { panic("overflowing_sub #197") }
    if !(0u32.saturating_sub(0u32) == 0u32) { panic("saturating_sub #198") }
    if !(0u32.strict_sub(0u32) == 0u32) { panic("strict_sub #199") }
    if !(unsafe { 0u32.unchecked_sub(0u32) } == 0u32) { panic("unchecked_sub #200") }
    if !(0u32.checked_mul(0u32) == present(0u32)) { panic("checked_mul #201") }
    if !(0u32.wrapping_mul(0u32) == 0u32) { panic("wrapping_mul #202") }
    if !(0u32.overflowing_mul(0u32).0 == 0u32 && 0u32.overflowing_mul(0u32).1 == false) { panic("overflowing_mul #203") }
    if !(0u32.saturating_mul(0u32) == 0u32) { panic("saturating_mul #204") }
    if !(0u32.strict_mul(0u32) == 0u32) { panic("strict_mul #205") }
    if !(unsafe { 0u32.unchecked_mul(0u32) } == 0u32) { panic("unchecked_mul #206") }
    if !(missing(0u32.checked_div(0u32))) { panic("checked_div #207") }
    if !(missing(0u32.checked_rem(0u32))) { panic("checked_rem #208") }
    if !(missing(0u32.checked_div_euclid(0u32))) { panic("checked_div_euclid #209") }
    if !(missing(0u32.checked_rem_euclid(0u32))) { panic("checked_rem_euclid #210") }
    if !(0u32.abs_diff(0u32) == 0u32) { panic("abs_diff #211") }
    if !(0u32.midpoint(0u32) == 0u32) { panic("midpoint #212") }
    if !(missing(u32.MAX.checked_add(u32.MAX))) { panic("checked_add #213") }
    if !(u32.MAX.wrapping_add(u32.MAX) == 4294967294u32) { panic("wrapping_add #214") }
    if !(u32.MAX.overflowing_add(u32.MAX).0 == 4294967294u32 && u32.MAX.overflowing_add(u32.MAX).1 == true) { panic("overflowing_add #215") }
    if !(u32.MAX.saturating_add(u32.MAX) == u32.MAX) { panic("saturating_add #216") }
    if !(u32.MAX.checked_sub(u32.MAX) == present(0u32)) { panic("checked_sub #217") }
    if !(u32.MAX.wrapping_sub(u32.MAX) == 0u32) { panic("wrapping_sub #218") }
    if !(u32.MAX.overflowing_sub(u32.MAX).0 == 0u32 && u32.MAX.overflowing_sub(u32.MAX).1 == false) { panic("overflowing_sub #219") }
    if !(u32.MAX.saturating_sub(u32.MAX) == 0u32) { panic("saturating_sub #220") }
    if !(u32.MAX.strict_sub(u32.MAX) == 0u32) { panic("strict_sub #221") }
    if !(unsafe { u32.MAX.unchecked_sub(u32.MAX) } == 0u32) { panic("unchecked_sub #222") }
    if !(missing(u32.MAX.checked_mul(u32.MAX))) { panic("checked_mul #223") }
    if !(u32.MAX.wrapping_mul(u32.MAX) == 1u32) { panic("wrapping_mul #224") }
    if !(u32.MAX.overflowing_mul(u32.MAX).0 == 1u32 && u32.MAX.overflowing_mul(u32.MAX).1 == true) { panic("overflowing_mul #225") }
    if !(u32.MAX.saturating_mul(u32.MAX) == u32.MAX) { panic("saturating_mul #226") }
    if !(u32.MAX.checked_div(u32.MAX) == present(1u32)) { panic("checked_div #227") }
    if !(u32.MAX.wrapping_div(u32.MAX) == 1u32) { panic("wrapping_div #228") }
    if !(u32.MAX.overflowing_div(u32.MAX).0 == 1u32 && u32.MAX.overflowing_div(u32.MAX).1 == false) { panic("overflowing_div #229") }
    if !(u32.MAX.strict_div(u32.MAX) == 1u32) { panic("strict_div #230") }
    if !(u32.MAX.saturating_div(u32.MAX) == 1u32) { panic("saturating_div #231") }
    if !(u32.MAX.checked_rem(u32.MAX) == present(0u32)) { panic("checked_rem #232") }
    if !(u32.MAX.wrapping_rem(u32.MAX) == 0u32) { panic("wrapping_rem #233") }
    if !(u32.MAX.overflowing_rem(u32.MAX).0 == 0u32 && u32.MAX.overflowing_rem(u32.MAX).1 == false) { panic("overflowing_rem #234") }
    if !(u32.MAX.strict_rem(u32.MAX) == 0u32) { panic("strict_rem #235") }
    if !(u32.MAX.checked_div_euclid(u32.MAX) == present(1u32)) { panic("checked_div_euclid #236") }
    if !(u32.MAX.wrapping_div_euclid(u32.MAX) == 1u32) { panic("wrapping_div_euclid #237") }
    if !(u32.MAX.overflowing_div_euclid(u32.MAX).0 == 1u32 && u32.MAX.overflowing_div_euclid(u32.MAX).1 == false) { panic("overflowing_div_euclid #238") }
    if !(u32.MAX.strict_div_euclid(u32.MAX) == 1u32) { panic("strict_div_euclid #239") }
    if !(u32.MAX.div_euclid(u32.MAX) == 1u32) { panic("div_euclid #240") }
}

fn group2() {
    if !(u32.MAX.checked_rem_euclid(u32.MAX) == present(0u32)) { panic("checked_rem_euclid #241") }
    if !(u32.MAX.wrapping_rem_euclid(u32.MAX) == 0u32) { panic("wrapping_rem_euclid #242") }
    if !(u32.MAX.overflowing_rem_euclid(u32.MAX).0 == 0u32 && u32.MAX.overflowing_rem_euclid(u32.MAX).1 == false) { panic("overflowing_rem_euclid #243") }
    if !(u32.MAX.strict_rem_euclid(u32.MAX) == 0u32) { panic("strict_rem_euclid #244") }
    if !(u32.MAX.rem_euclid(u32.MAX) == 0u32) { panic("rem_euclid #245") }
    if !(u32.MAX.abs_diff(u32.MAX) == 0u32) { panic("abs_diff #246") }
    if !(u32.MAX.midpoint(u32.MAX) == u32.MAX) { panic("midpoint #247") }
    if !(missing(u32.MAX.checked_add(4294967294u32))) { panic("checked_add #248") }
    if !(u32.MAX.wrapping_add(4294967294u32) == 4294967293u32) { panic("wrapping_add #249") }
    if !(u32.MAX.overflowing_add(4294967294u32).0 == 4294967293u32 && u32.MAX.overflowing_add(4294967294u32).1 == true) { panic("overflowing_add #250") }
    if !(u32.MAX.saturating_add(4294967294u32) == u32.MAX) { panic("saturating_add #251") }
    if !(u32.MAX.checked_sub(4294967294u32) == present(1u32)) { panic("checked_sub #252") }
    if !(u32.MAX.wrapping_sub(4294967294u32) == 1u32) { panic("wrapping_sub #253") }
    if !(u32.MAX.overflowing_sub(4294967294u32).0 == 1u32 && u32.MAX.overflowing_sub(4294967294u32).1 == false) { panic("overflowing_sub #254") }
    if !(u32.MAX.saturating_sub(4294967294u32) == 1u32) { panic("saturating_sub #255") }
    if !(u32.MAX.strict_sub(4294967294u32) == 1u32) { panic("strict_sub #256") }
    if !(unsafe { u32.MAX.unchecked_sub(4294967294u32) } == 1u32) { panic("unchecked_sub #257") }
    if !(missing(u32.MAX.checked_mul(4294967294u32))) { panic("checked_mul #258") }
    if !(u32.MAX.wrapping_mul(4294967294u32) == 2u32) { panic("wrapping_mul #259") }
    if !(u32.MAX.overflowing_mul(4294967294u32).0 == 2u32 && u32.MAX.overflowing_mul(4294967294u32).1 == true) { panic("overflowing_mul #260") }
    if !(u32.MAX.saturating_mul(4294967294u32) == u32.MAX) { panic("saturating_mul #261") }
    if !(u32.MAX.checked_div(4294967294u32) == present(1u32)) { panic("checked_div #262") }
    if !(u32.MAX.wrapping_div(4294967294u32) == 1u32) { panic("wrapping_div #263") }
    if !(u32.MAX.overflowing_div(4294967294u32).0 == 1u32 && u32.MAX.overflowing_div(4294967294u32).1 == false) { panic("overflowing_div #264") }
    if !(u32.MAX.strict_div(4294967294u32) == 1u32) { panic("strict_div #265") }
    if !(u32.MAX.saturating_div(4294967294u32) == 1u32) { panic("saturating_div #266") }
    if !(u32.MAX.checked_rem(4294967294u32) == present(1u32)) { panic("checked_rem #267") }
    if !(u32.MAX.wrapping_rem(4294967294u32) == 1u32) { panic("wrapping_rem #268") }
    if !(u32.MAX.overflowing_rem(4294967294u32).0 == 1u32 && u32.MAX.overflowing_rem(4294967294u32).1 == false) { panic("overflowing_rem #269") }
    if !(u32.MAX.strict_rem(4294967294u32) == 1u32) { panic("strict_rem #270") }
    if !(u32.MAX.checked_div_euclid(4294967294u32) == present(1u32)) { panic("checked_div_euclid #271") }
    if !(u32.MAX.wrapping_div_euclid(4294967294u32) == 1u32) { panic("wrapping_div_euclid #272") }
    if !(u32.MAX.overflowing_div_euclid(4294967294u32).0 == 1u32 && u32.MAX.overflowing_div_euclid(4294967294u32).1 == false) { panic("overflowing_div_euclid #273") }
    if !(u32.MAX.strict_div_euclid(4294967294u32) == 1u32) { panic("strict_div_euclid #274") }
    if !(u32.MAX.div_euclid(4294967294u32) == 1u32) { panic("div_euclid #275") }
    if !(u32.MAX.checked_rem_euclid(4294967294u32) == present(1u32)) { panic("checked_rem_euclid #276") }
    if !(u32.MAX.wrapping_rem_euclid(4294967294u32) == 1u32) { panic("wrapping_rem_euclid #277") }
    if !(u32.MAX.overflowing_rem_euclid(4294967294u32).0 == 1u32 && u32.MAX.overflowing_rem_euclid(4294967294u32).1 == false) { panic("overflowing_rem_euclid #278") }
    if !(u32.MAX.strict_rem_euclid(4294967294u32) == 1u32) { panic("strict_rem_euclid #279") }
    if !(u32.MAX.rem_euclid(4294967294u32) == 1u32) { panic("rem_euclid #280") }
    if !(u32.MAX.abs_diff(4294967294u32) == 1u32) { panic("abs_diff #281") }
    if !(u32.MAX.midpoint(4294967294u32) == 4294967294u32) { panic("midpoint #282") }
    if !(missing(u32.MAX.checked_add_signed(1i32))) { panic("checked_add_signed #283") }
    if !(u32.MAX.wrapping_add_signed(1i32) == 0u32) { panic("wrapping_add_signed #284") }
    if !(u32.MAX.overflowing_add_signed(1i32).0 == 0u32 && u32.MAX.overflowing_add_signed(1i32).1 == true) { panic("overflowing_add_signed #285") }
    if !(u32.MAX.saturating_add_signed(1i32) == u32.MAX) { panic("saturating_add_signed #286") }
    if !(u32.MAX.checked_sub_signed(1i32) == present(4294967294u32)) { panic("checked_sub_signed #287") }
    if !(u32.MAX.wrapping_sub_signed(1i32) == 4294967294u32) { panic("wrapping_sub_signed #288") }
    if !(u32.MAX.overflowing_sub_signed(1i32).0 == 4294967294u32 && u32.MAX.overflowing_sub_signed(1i32).1 == false) { panic("overflowing_sub_signed #289") }
    if !(u32.MAX.saturating_sub_signed(1i32) == 4294967294u32) { panic("saturating_sub_signed #290") }
    if !(u32.MAX.strict_sub_signed(1i32) == 4294967294u32) { panic("strict_sub_signed #291") }
    if !(missing(0u32.checked_add_signed((-1i32)))) { panic("checked_add_signed #292") }
    if !(0u32.wrapping_add_signed((-1i32)) == u32.MAX) { panic("wrapping_add_signed #293") }
    if !(0u32.overflowing_add_signed((-1i32)).0 == u32.MAX && 0u32.overflowing_add_signed((-1i32)).1 == true) { panic("overflowing_add_signed #294") }
    if !(0u32.saturating_add_signed((-1i32)) == 0u32) { panic("saturating_add_signed #295") }
    if !(0u32.checked_sub_signed((-1i32)) == present(1u32)) { panic("checked_sub_signed #296") }
    if !(0u32.wrapping_sub_signed((-1i32)) == 1u32) { panic("wrapping_sub_signed #297") }
    if !(0u32.overflowing_sub_signed((-1i32)).0 == 1u32 && 0u32.overflowing_sub_signed((-1i32)).1 == false) { panic("overflowing_sub_signed #298") }
    if !(0u32.saturating_sub_signed((-1i32)) == 1u32) { panic("saturating_sub_signed #299") }
    if !(0u32.strict_sub_signed((-1i32)) == 1u32) { panic("strict_sub_signed #300") }
    if !(7u32.checked_add_signed((-3i32)) == present(4u32)) { panic("checked_add_signed #301") }
    if !(7u32.wrapping_add_signed((-3i32)) == 4u32) { panic("wrapping_add_signed #302") }
    if !(7u32.overflowing_add_signed((-3i32)).0 == 4u32 && 7u32.overflowing_add_signed((-3i32)).1 == false) { panic("overflowing_add_signed #303") }
    if !(7u32.saturating_add_signed((-3i32)) == 4u32) { panic("saturating_add_signed #304") }
    if !(7u32.strict_add_signed((-3i32)) == 4u32) { panic("strict_add_signed #305") }
    if !(7u32.checked_sub_signed((-3i32)) == present(10u32)) { panic("checked_sub_signed #306") }
    if !(7u32.wrapping_sub_signed((-3i32)) == 10u32) { panic("wrapping_sub_signed #307") }
    if !(7u32.overflowing_sub_signed((-3i32)).0 == 10u32 && 7u32.overflowing_sub_signed((-3i32)).1 == false) { panic("overflowing_sub_signed #308") }
    if !(7u32.saturating_sub_signed((-3i32)) == 10u32) { panic("saturating_sub_signed #309") }
    if !(7u32.strict_sub_signed((-3i32)) == 10u32) { panic("strict_sub_signed #310") }
    if !(u32.MAX.checked_add_signed(i32.MIN) == present(2147483647u32)) { panic("checked_add_signed #311") }
    if !(u32.MAX.wrapping_add_signed(i32.MIN) == 2147483647u32) { panic("wrapping_add_signed #312") }
    if !(u32.MAX.overflowing_add_signed(i32.MIN).0 == 2147483647u32 && u32.MAX.overflowing_add_signed(i32.MIN).1 == false) { panic("overflowing_add_signed #313") }
    if !(u32.MAX.saturating_add_signed(i32.MIN) == 2147483647u32) { panic("saturating_add_signed #314") }
    if !(u32.MAX.strict_add_signed(i32.MIN) == 2147483647u32) { panic("strict_add_signed #315") }
    if !(missing(u32.MAX.checked_sub_signed(i32.MIN))) { panic("checked_sub_signed #316") }
    if !(u32.MAX.wrapping_sub_signed(i32.MIN) == 2147483647u32) { panic("wrapping_sub_signed #317") }
    if !(u32.MAX.overflowing_sub_signed(i32.MIN).0 == 2147483647u32 && u32.MAX.overflowing_sub_signed(i32.MIN).1 == true) { panic("overflowing_sub_signed #318") }
    if !(u32.MAX.saturating_sub_signed(i32.MIN) == u32.MAX) { panic("saturating_sub_signed #319") }
    if !(0u32.checked_add_signed(i32.MAX) == present(2147483647u32)) { panic("checked_add_signed #320") }
    if !(0u32.wrapping_add_signed(i32.MAX) == 2147483647u32) { panic("wrapping_add_signed #321") }
    if !(0u32.overflowing_add_signed(i32.MAX).0 == 2147483647u32 && 0u32.overflowing_add_signed(i32.MAX).1 == false) { panic("overflowing_add_signed #322") }
    if !(0u32.saturating_add_signed(i32.MAX) == 2147483647u32) { panic("saturating_add_signed #323") }
    if !(0u32.strict_add_signed(i32.MAX) == 2147483647u32) { panic("strict_add_signed #324") }
    if !(missing(0u32.checked_sub_signed(i32.MAX))) { panic("checked_sub_signed #325") }
    if !(0u32.wrapping_sub_signed(i32.MAX) == 2147483649u32) { panic("wrapping_sub_signed #326") }
    if !(0u32.overflowing_sub_signed(i32.MAX).0 == 2147483649u32 && 0u32.overflowing_sub_signed(i32.MAX).1 == true) { panic("overflowing_sub_signed #327") }
    if !(0u32.saturating_sub_signed(i32.MAX) == 0u32) { panic("saturating_sub_signed #328") }
    if !(missing(u32.MAX.checked_neg())) { panic("checked_neg #329") }
    if !(u32.MAX.wrapping_neg() == 1u32) { panic("wrapping_neg #330") }
    if !(u32.MAX.overflowing_neg().0 == 1u32 && u32.MAX.overflowing_neg().1 == true) { panic("overflowing_neg #331") }
    if !(u32.MAX.cast_signed() == (-1i32)) { panic("cast_signed #332") }
    if !(u32.MAX.count_ones() == 32u32) { panic("count_ones #333") }
    if !(u32.MAX.count_zeros() == 0u32) { panic("count_zeros #334") }
    if !(u32.MAX.leading_zeros() == 0u32) { panic("leading_zeros #335") }
    if !(u32.MAX.trailing_zeros() == 0u32) { panic("trailing_zeros #336") }
    if !(u32.MAX.leading_ones() == 32u32) { panic("leading_ones #337") }
    if !(u32.MAX.trailing_ones() == 32u32) { panic("trailing_ones #338") }
    if !(u32.MAX.reverse_bits() == u32.MAX) { panic("reverse_bits #339") }
    if !(u32.MAX.swap_bytes() == u32.MAX) { panic("swap_bytes #340") }
    if !(u32.MAX.to_be() == u32.MAX) { panic("to_be #341") }
    if !(u32.MAX.to_le() == u32.MAX) { panic("to_le #342") }
    if !(u32.from_be(u32.MAX) == u32.MAX) { panic("from_be #343") }
    if !(u32.from_le(u32.MAX) == u32.MAX) { panic("from_le #344") }
    if !(u32.MAX.to_le_bytes() == [255u8, 255u8, 255u8, 255u8]) { panic("to_le_bytes #345") }
    if !(u32.MAX.to_be_bytes() == [255u8, 255u8, 255u8, 255u8]) { panic("to_be_bytes #346") }
    if !(u32.MAX.to_ne_bytes() == [255u8, 255u8, 255u8, 255u8]) { panic("to_ne_bytes #347") }
    if !(u32.from_le_bytes([255u8, 255u8, 255u8, 255u8]) == u32.MAX) { panic("from_le_bytes #348") }
    if !(u32.from_be_bytes([255u8, 255u8, 255u8, 255u8]) == u32.MAX) { panic("from_be_bytes #349") }
    if !(u32.from_ne_bytes([255u8, 255u8, 255u8, 255u8]) == u32.MAX) { panic("from_ne_bytes #350") }
    if !(u32.MAX.rotate_left(0u32) == u32.MAX) { panic("rotate_left #351") }
    if !(u32.MAX.rotate_right(0u32) == u32.MAX) { panic("rotate_right #352") }
    if !(u32.MAX.checked_shl(0u32) == present(u32.MAX)) { panic("checked_shl #353") }
    if !(u32.MAX.checked_shr(0u32) == present(u32.MAX)) { panic("checked_shr #354") }
    if !(u32.MAX.wrapping_shl(0u32) == u32.MAX) { panic("wrapping_shl #355") }
    if !(u32.MAX.wrapping_shr(0u32) == u32.MAX) { panic("wrapping_shr #356") }
    if !(u32.MAX.overflowing_shl(0u32).0 == u32.MAX && u32.MAX.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #357") }
    if !(u32.MAX.overflowing_shr(0u32).0 == u32.MAX && u32.MAX.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #358") }
    if !(u32.MAX.unbounded_shl(0u32) == u32.MAX) { panic("unbounded_shl #359") }
    if !(u32.MAX.unbounded_shr(0u32) == u32.MAX) { panic("unbounded_shr #360") }
}

fn group3() {
    if !(u32.MAX.strict_shl(0u32) == u32.MAX) { panic("strict_shl #361") }
    if !(u32.MAX.strict_shr(0u32) == u32.MAX) { panic("strict_shr #362") }
    if !(unsafe { u32.MAX.unchecked_shl(0u32) } == u32.MAX) { panic("unchecked_shl #363") }
    if !(unsafe { u32.MAX.unchecked_shr(0u32) } == u32.MAX) { panic("unchecked_shr #364") }
    if !(u32.MAX.rotate_left(1u32) == u32.MAX) { panic("rotate_left #365") }
    if !(u32.MAX.rotate_right(1u32) == u32.MAX) { panic("rotate_right #366") }
    if !(u32.MAX.checked_shl(1u32) == present(4294967294u32)) { panic("checked_shl #367") }
    if !(u32.MAX.checked_shr(1u32) == present(2147483647u32)) { panic("checked_shr #368") }
    if !(u32.MAX.wrapping_shl(1u32) == 4294967294u32) { panic("wrapping_shl #369") }
    if !(u32.MAX.wrapping_shr(1u32) == 2147483647u32) { panic("wrapping_shr #370") }
    if !(u32.MAX.overflowing_shl(1u32).0 == 4294967294u32 && u32.MAX.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #371") }
    if !(u32.MAX.overflowing_shr(1u32).0 == 2147483647u32 && u32.MAX.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #372") }
    if !(u32.MAX.unbounded_shl(1u32) == 4294967294u32) { panic("unbounded_shl #373") }
    if !(u32.MAX.unbounded_shr(1u32) == 2147483647u32) { panic("unbounded_shr #374") }
    if !(u32.MAX.strict_shl(1u32) == 4294967294u32) { panic("strict_shl #375") }
    if !(u32.MAX.strict_shr(1u32) == 2147483647u32) { panic("strict_shr #376") }
    if !(unsafe { u32.MAX.unchecked_shl(1u32) } == 4294967294u32) { panic("unchecked_shl #377") }
    if !(unsafe { u32.MAX.unchecked_shr(1u32) } == 2147483647u32) { panic("unchecked_shr #378") }
    if !(u32.MAX.rotate_left(3u32) == u32.MAX) { panic("rotate_left #379") }
    if !(u32.MAX.rotate_right(3u32) == u32.MAX) { panic("rotate_right #380") }
    if !(u32.MAX.checked_shl(3u32) == present(4294967288u32)) { panic("checked_shl #381") }
    if !(u32.MAX.checked_shr(3u32) == present(536870911u32)) { panic("checked_shr #382") }
    if !(u32.MAX.wrapping_shl(3u32) == 4294967288u32) { panic("wrapping_shl #383") }
    if !(u32.MAX.wrapping_shr(3u32) == 536870911u32) { panic("wrapping_shr #384") }
    if !(u32.MAX.overflowing_shl(3u32).0 == 4294967288u32 && u32.MAX.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #385") }
    if !(u32.MAX.overflowing_shr(3u32).0 == 536870911u32 && u32.MAX.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #386") }
    if !(u32.MAX.unbounded_shl(3u32) == 4294967288u32) { panic("unbounded_shl #387") }
    if !(u32.MAX.unbounded_shr(3u32) == 536870911u32) { panic("unbounded_shr #388") }
    if !(u32.MAX.strict_shl(3u32) == 4294967288u32) { panic("strict_shl #389") }
    if !(u32.MAX.strict_shr(3u32) == 536870911u32) { panic("strict_shr #390") }
    if !(unsafe { u32.MAX.unchecked_shl(3u32) } == 4294967288u32) { panic("unchecked_shl #391") }
    if !(unsafe { u32.MAX.unchecked_shr(3u32) } == 536870911u32) { panic("unchecked_shr #392") }
    if !(u32.MAX.rotate_left(31u32) == u32.MAX) { panic("rotate_left #393") }
    if !(u32.MAX.rotate_right(31u32) == u32.MAX) { panic("rotate_right #394") }
    if !(u32.MAX.checked_shl(31u32) == present(2147483648u32)) { panic("checked_shl #395") }
    if !(u32.MAX.checked_shr(31u32) == present(1u32)) { panic("checked_shr #396") }
    if !(u32.MAX.wrapping_shl(31u32) == 2147483648u32) { panic("wrapping_shl #397") }
    if !(u32.MAX.wrapping_shr(31u32) == 1u32) { panic("wrapping_shr #398") }
    if !(u32.MAX.overflowing_shl(31u32).0 == 2147483648u32 && u32.MAX.overflowing_shl(31u32).1 == false) { panic("overflowing_shl #399") }
    if !(u32.MAX.overflowing_shr(31u32).0 == 1u32 && u32.MAX.overflowing_shr(31u32).1 == false) { panic("overflowing_shr #400") }
    if !(u32.MAX.unbounded_shl(31u32) == 2147483648u32) { panic("unbounded_shl #401") }
    if !(u32.MAX.unbounded_shr(31u32) == 1u32) { panic("unbounded_shr #402") }
    if !(u32.MAX.strict_shl(31u32) == 2147483648u32) { panic("strict_shl #403") }
    if !(u32.MAX.strict_shr(31u32) == 1u32) { panic("strict_shr #404") }
    if !(unsafe { u32.MAX.unchecked_shl(31u32) } == 2147483648u32) { panic("unchecked_shl #405") }
    if !(unsafe { u32.MAX.unchecked_shr(31u32) } == 1u32) { panic("unchecked_shr #406") }
    if !(u32.MAX.rotate_left(32u32) == u32.MAX) { panic("rotate_left #407") }
    if !(u32.MAX.rotate_right(32u32) == u32.MAX) { panic("rotate_right #408") }
    if !(missing(u32.MAX.checked_shl(32u32))) { panic("checked_shl #409") }
    if !(missing(u32.MAX.checked_shr(32u32))) { panic("checked_shr #410") }
    if !(u32.MAX.wrapping_shl(32u32) == u32.MAX) { panic("wrapping_shl #411") }
    if !(u32.MAX.wrapping_shr(32u32) == u32.MAX) { panic("wrapping_shr #412") }
    if !(u32.MAX.overflowing_shl(32u32).0 == u32.MAX && u32.MAX.overflowing_shl(32u32).1 == true) { panic("overflowing_shl #413") }
    if !(u32.MAX.overflowing_shr(32u32).0 == u32.MAX && u32.MAX.overflowing_shr(32u32).1 == true) { panic("overflowing_shr #414") }
    if !(u32.MAX.unbounded_shl(32u32) == 0u32) { panic("unbounded_shl #415") }
    if !(u32.MAX.unbounded_shr(32u32) == 0u32) { panic("unbounded_shr #416") }
    if !(u32.MAX.rotate_left(37u32) == u32.MAX) { panic("rotate_left #417") }
    if !(u32.MAX.rotate_right(37u32) == u32.MAX) { panic("rotate_right #418") }
    if !(missing(u32.MAX.checked_shl(37u32))) { panic("checked_shl #419") }
    if !(missing(u32.MAX.checked_shr(37u32))) { panic("checked_shr #420") }
    if !(u32.MAX.wrapping_shl(37u32) == 4294967264u32) { panic("wrapping_shl #421") }
    if !(u32.MAX.wrapping_shr(37u32) == 134217727u32) { panic("wrapping_shr #422") }
    if !(u32.MAX.overflowing_shl(37u32).0 == 4294967264u32 && u32.MAX.overflowing_shl(37u32).1 == true) { panic("overflowing_shl #423") }
    if !(u32.MAX.overflowing_shr(37u32).0 == 134217727u32 && u32.MAX.overflowing_shr(37u32).1 == true) { panic("overflowing_shr #424") }
    if !(u32.MAX.unbounded_shl(37u32) == 0u32) { panic("unbounded_shl #425") }
    if !(u32.MAX.unbounded_shr(37u32) == 0u32) { panic("unbounded_shr #426") }
    if !(u32.MAX.checked_pow(0u32) == present(1u32)) { panic("checked_pow #427") }
    if !(u32.MAX.wrapping_pow(0u32) == 1u32) { panic("wrapping_pow #428") }
    if !(u32.MAX.overflowing_pow(0u32).0 == 1u32 && u32.MAX.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #429") }
    if !(u32.MAX.saturating_pow(0u32) == 1u32) { panic("saturating_pow #430") }
    if !(u32.MAX.pow(0u32) == 1u32) { panic("pow #431") }
    if !(u32.MAX.strict_pow(0u32) == 1u32) { panic("strict_pow #432") }
    if !(u32.MAX.checked_pow(1u32) == present(u32.MAX)) { panic("checked_pow #433") }
    if !(u32.MAX.wrapping_pow(1u32) == u32.MAX) { panic("wrapping_pow #434") }
    if !(u32.MAX.overflowing_pow(1u32).0 == u32.MAX && u32.MAX.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #435") }
    if !(u32.MAX.saturating_pow(1u32) == u32.MAX) { panic("saturating_pow #436") }
    if !(u32.MAX.pow(1u32) == u32.MAX) { panic("pow #437") }
    if !(u32.MAX.strict_pow(1u32) == u32.MAX) { panic("strict_pow #438") }
    if !(missing(u32.MAX.checked_pow(2u32))) { panic("checked_pow #439") }
    if !(u32.MAX.wrapping_pow(2u32) == 1u32) { panic("wrapping_pow #440") }
    if !(u32.MAX.overflowing_pow(2u32).0 == 1u32 && u32.MAX.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #441") }
    if !(u32.MAX.saturating_pow(2u32) == u32.MAX) { panic("saturating_pow #442") }
    if !(missing(u32.MAX.checked_pow(3u32))) { panic("checked_pow #443") }
    if !(u32.MAX.wrapping_pow(3u32) == u32.MAX) { panic("wrapping_pow #444") }
    if !(u32.MAX.overflowing_pow(3u32).0 == u32.MAX && u32.MAX.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #445") }
    if !(u32.MAX.saturating_pow(3u32) == u32.MAX) { panic("saturating_pow #446") }
    if !(missing(u32.MAX.checked_pow(31u32))) { panic("checked_pow #447") }
    if !(u32.MAX.wrapping_pow(31u32) == u32.MAX) { panic("wrapping_pow #448") }
    if !(u32.MAX.overflowing_pow(31u32).0 == u32.MAX && u32.MAX.overflowing_pow(31u32).1 == true) { panic("overflowing_pow #449") }
    if !(u32.MAX.saturating_pow(31u32) == u32.MAX) { panic("saturating_pow #450") }
    if !(missing(u32.MAX.checked_pow(32u32))) { panic("checked_pow #451") }
    if !(u32.MAX.wrapping_pow(32u32) == 1u32) { panic("wrapping_pow #452") }
    if !(u32.MAX.overflowing_pow(32u32).0 == 1u32 && u32.MAX.overflowing_pow(32u32).1 == true) { panic("overflowing_pow #453") }
    if !(u32.MAX.saturating_pow(32u32) == u32.MAX) { panic("saturating_pow #454") }
    if !(u32.MAX.ilog2() == 31u32) { panic("ilog2 #455") }
    if !(u32.MAX.ilog10() == 9u32) { panic("ilog10 #456") }
    if !(u32.MAX.checked_ilog2() == present(31u32)) { panic("checked_ilog2 #457") }
    if !(u32.MAX.checked_ilog10() == present(9u32)) { panic("checked_ilog10 #458") }
    if !(u32.MAX.ilog(2u32) == 31u32) { panic("ilog #459") }
    if !(u32.MAX.checked_ilog(2u32) == present(31u32)) { panic("checked_ilog #460") }
    if !(u32.MAX.ilog(3u32) == 20u32) { panic("ilog #461") }
    if !(u32.MAX.checked_ilog(3u32) == present(20u32)) { panic("checked_ilog #462") }
    if !(u32.MAX.ilog(7u32) == 11u32) { panic("ilog #463") }
    if !(u32.MAX.checked_ilog(7u32) == present(11u32)) { panic("checked_ilog #464") }
    if !(missing(u32.MAX.checked_ilog(1u32))) { panic("checked_ilog #465") }
    if !(u32.MAX.isqrt() == 65535u32) { panic("isqrt #466") }
    if !(u32.MAX.checked_isqrt() == present(65535u32)) { panic("checked_isqrt #467") }
    if !(u32.MAX.is_power_of_two() == false) { panic("is_power_of_two #468") }
    if !(missing(u32.MAX.checked_next_power_of_two())) { panic("checked_next_power_of_two #469") }
    if !(u32.MAX.div_ceil(1u32) == u32.MAX) { panic("div_ceil #470") }
    if !(u32.MAX.checked_next_multiple_of(1u32) == present(u32.MAX)) { panic("checked_next_multiple_of #471") }
    if !(u32.MAX.next_multiple_of(1u32) == u32.MAX) { panic("next_multiple_of #472") }
    if !(u32.MAX.is_multiple_of(1u32) == true) { panic("is_multiple_of #473") }
    if !(u32.MAX.div_ceil(3u32) == 1431655765u32) { panic("div_ceil #474") }
    if !(u32.MAX.checked_next_multiple_of(3u32) == present(u32.MAX)) { panic("checked_next_multiple_of #475") }
    if !(u32.MAX.next_multiple_of(3u32) == u32.MAX) { panic("next_multiple_of #476") }
    if !(u32.MAX.is_multiple_of(3u32) == true) { panic("is_multiple_of #477") }
    if !(u32.MAX.div_ceil(7u32) == 613566757u32) { panic("div_ceil #478") }
    if !(missing(u32.MAX.checked_next_multiple_of(7u32))) { panic("checked_next_multiple_of #479") }
    if !(u32.MAX.is_multiple_of(7u32) == false) { panic("is_multiple_of #480") }
}

fn group4() {
    if !(u32.MAX.is_multiple_of(0u32) == false) { panic("is_multiple_of #481") }
    if !(missing(u32.MAX.checked_next_multiple_of(0u32))) { panic("checked_next_multiple_of #482") }
    if !(u32.MAX.highest_one() == present(31u32)) { panic("highest_one #483") }
    if !(u32.MAX.lowest_one() == present(0u32)) { panic("lowest_one #484") }
    if !(u32.MAX.isolate_highest_one() == 2147483648u32) { panic("isolate_highest_one #485") }
    if !(u32.MAX.isolate_lowest_one() == 1u32) { panic("isolate_lowest_one #486") }
    if !(u32.MAX.bit_width() == 32u32) { panic("bit_width #487") }
    if !(0u32.checked_neg() == present(0u32)) { panic("checked_neg #488") }
    if !(0u32.wrapping_neg() == 0u32) { panic("wrapping_neg #489") }
    if !(0u32.overflowing_neg().0 == 0u32 && 0u32.overflowing_neg().1 == false) { panic("overflowing_neg #490") }
    if !(0u32.strict_neg() == 0u32) { panic("strict_neg #491") }
    if !(0u32.cast_signed() == 0i32) { panic("cast_signed #492") }
    if !(0u32.count_ones() == 0u32) { panic("count_ones #493") }
    if !(0u32.count_zeros() == 32u32) { panic("count_zeros #494") }
    if !(0u32.leading_zeros() == 32u32) { panic("leading_zeros #495") }
    if !(0u32.trailing_zeros() == 32u32) { panic("trailing_zeros #496") }
    if !(0u32.leading_ones() == 0u32) { panic("leading_ones #497") }
    if !(0u32.trailing_ones() == 0u32) { panic("trailing_ones #498") }
    if !(0u32.reverse_bits() == 0u32) { panic("reverse_bits #499") }
    if !(0u32.swap_bytes() == 0u32) { panic("swap_bytes #500") }
    if !(0u32.to_be() == 0u32) { panic("to_be #501") }
    if !(0u32.to_le() == 0u32) { panic("to_le #502") }
    if !(u32.from_be(0u32) == 0u32) { panic("from_be #503") }
    if !(u32.from_le(0u32) == 0u32) { panic("from_le #504") }
    if !(0u32.to_le_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #505") }
    if !(0u32.to_be_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #506") }
    if !(0u32.to_ne_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #507") }
    if !(u32.from_le_bytes([0u8, 0u8, 0u8, 0u8]) == 0u32) { panic("from_le_bytes #508") }
    if !(u32.from_be_bytes([0u8, 0u8, 0u8, 0u8]) == 0u32) { panic("from_be_bytes #509") }
    if !(u32.from_ne_bytes([0u8, 0u8, 0u8, 0u8]) == 0u32) { panic("from_ne_bytes #510") }
    if !(0u32.rotate_left(0u32) == 0u32) { panic("rotate_left #511") }
    if !(0u32.rotate_right(0u32) == 0u32) { panic("rotate_right #512") }
    if !(0u32.checked_shl(0u32) == present(0u32)) { panic("checked_shl #513") }
    if !(0u32.checked_shr(0u32) == present(0u32)) { panic("checked_shr #514") }
    if !(0u32.wrapping_shl(0u32) == 0u32) { panic("wrapping_shl #515") }
    if !(0u32.wrapping_shr(0u32) == 0u32) { panic("wrapping_shr #516") }
    if !(0u32.overflowing_shl(0u32).0 == 0u32 && 0u32.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #517") }
    if !(0u32.overflowing_shr(0u32).0 == 0u32 && 0u32.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #518") }
    if !(0u32.unbounded_shl(0u32) == 0u32) { panic("unbounded_shl #519") }
    if !(0u32.unbounded_shr(0u32) == 0u32) { panic("unbounded_shr #520") }
    if !(0u32.strict_shl(0u32) == 0u32) { panic("strict_shl #521") }
    if !(0u32.strict_shr(0u32) == 0u32) { panic("strict_shr #522") }
    if !(unsafe { 0u32.unchecked_shl(0u32) } == 0u32) { panic("unchecked_shl #523") }
    if !(unsafe { 0u32.unchecked_shr(0u32) } == 0u32) { panic("unchecked_shr #524") }
    if !(0u32.rotate_left(1u32) == 0u32) { panic("rotate_left #525") }
    if !(0u32.rotate_right(1u32) == 0u32) { panic("rotate_right #526") }
    if !(0u32.checked_shl(1u32) == present(0u32)) { panic("checked_shl #527") }
    if !(0u32.checked_shr(1u32) == present(0u32)) { panic("checked_shr #528") }
    if !(0u32.wrapping_shl(1u32) == 0u32) { panic("wrapping_shl #529") }
    if !(0u32.wrapping_shr(1u32) == 0u32) { panic("wrapping_shr #530") }
    if !(0u32.overflowing_shl(1u32).0 == 0u32 && 0u32.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #531") }
    if !(0u32.overflowing_shr(1u32).0 == 0u32 && 0u32.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #532") }
    if !(0u32.unbounded_shl(1u32) == 0u32) { panic("unbounded_shl #533") }
    if !(0u32.unbounded_shr(1u32) == 0u32) { panic("unbounded_shr #534") }
    if !(0u32.strict_shl(1u32) == 0u32) { panic("strict_shl #535") }
    if !(0u32.strict_shr(1u32) == 0u32) { panic("strict_shr #536") }
    if !(unsafe { 0u32.unchecked_shl(1u32) } == 0u32) { panic("unchecked_shl #537") }
    if !(unsafe { 0u32.unchecked_shr(1u32) } == 0u32) { panic("unchecked_shr #538") }
    if !(0u32.rotate_left(3u32) == 0u32) { panic("rotate_left #539") }
    if !(0u32.rotate_right(3u32) == 0u32) { panic("rotate_right #540") }
    if !(0u32.checked_shl(3u32) == present(0u32)) { panic("checked_shl #541") }
    if !(0u32.checked_shr(3u32) == present(0u32)) { panic("checked_shr #542") }
    if !(0u32.wrapping_shl(3u32) == 0u32) { panic("wrapping_shl #543") }
    if !(0u32.wrapping_shr(3u32) == 0u32) { panic("wrapping_shr #544") }
    if !(0u32.overflowing_shl(3u32).0 == 0u32 && 0u32.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #545") }
    if !(0u32.overflowing_shr(3u32).0 == 0u32 && 0u32.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #546") }
    if !(0u32.unbounded_shl(3u32) == 0u32) { panic("unbounded_shl #547") }
    if !(0u32.unbounded_shr(3u32) == 0u32) { panic("unbounded_shr #548") }
    if !(0u32.strict_shl(3u32) == 0u32) { panic("strict_shl #549") }
    if !(0u32.strict_shr(3u32) == 0u32) { panic("strict_shr #550") }
    if !(unsafe { 0u32.unchecked_shl(3u32) } == 0u32) { panic("unchecked_shl #551") }
    if !(unsafe { 0u32.unchecked_shr(3u32) } == 0u32) { panic("unchecked_shr #552") }
    if !(0u32.rotate_left(31u32) == 0u32) { panic("rotate_left #553") }
    if !(0u32.rotate_right(31u32) == 0u32) { panic("rotate_right #554") }
    if !(0u32.checked_shl(31u32) == present(0u32)) { panic("checked_shl #555") }
    if !(0u32.checked_shr(31u32) == present(0u32)) { panic("checked_shr #556") }
    if !(0u32.wrapping_shl(31u32) == 0u32) { panic("wrapping_shl #557") }
    if !(0u32.wrapping_shr(31u32) == 0u32) { panic("wrapping_shr #558") }
    if !(0u32.overflowing_shl(31u32).0 == 0u32 && 0u32.overflowing_shl(31u32).1 == false) { panic("overflowing_shl #559") }
    if !(0u32.overflowing_shr(31u32).0 == 0u32 && 0u32.overflowing_shr(31u32).1 == false) { panic("overflowing_shr #560") }
    if !(0u32.unbounded_shl(31u32) == 0u32) { panic("unbounded_shl #561") }
    if !(0u32.unbounded_shr(31u32) == 0u32) { panic("unbounded_shr #562") }
    if !(0u32.strict_shl(31u32) == 0u32) { panic("strict_shl #563") }
    if !(0u32.strict_shr(31u32) == 0u32) { panic("strict_shr #564") }
    if !(unsafe { 0u32.unchecked_shl(31u32) } == 0u32) { panic("unchecked_shl #565") }
    if !(unsafe { 0u32.unchecked_shr(31u32) } == 0u32) { panic("unchecked_shr #566") }
    if !(0u32.rotate_left(32u32) == 0u32) { panic("rotate_left #567") }
    if !(0u32.rotate_right(32u32) == 0u32) { panic("rotate_right #568") }
    if !(missing(0u32.checked_shl(32u32))) { panic("checked_shl #569") }
    if !(missing(0u32.checked_shr(32u32))) { panic("checked_shr #570") }
    if !(0u32.wrapping_shl(32u32) == 0u32) { panic("wrapping_shl #571") }
    if !(0u32.wrapping_shr(32u32) == 0u32) { panic("wrapping_shr #572") }
    if !(0u32.overflowing_shl(32u32).0 == 0u32 && 0u32.overflowing_shl(32u32).1 == true) { panic("overflowing_shl #573") }
    if !(0u32.overflowing_shr(32u32).0 == 0u32 && 0u32.overflowing_shr(32u32).1 == true) { panic("overflowing_shr #574") }
    if !(0u32.unbounded_shl(32u32) == 0u32) { panic("unbounded_shl #575") }
    if !(0u32.unbounded_shr(32u32) == 0u32) { panic("unbounded_shr #576") }
    if !(0u32.rotate_left(37u32) == 0u32) { panic("rotate_left #577") }
    if !(0u32.rotate_right(37u32) == 0u32) { panic("rotate_right #578") }
    if !(missing(0u32.checked_shl(37u32))) { panic("checked_shl #579") }
    if !(missing(0u32.checked_shr(37u32))) { panic("checked_shr #580") }
    if !(0u32.wrapping_shl(37u32) == 0u32) { panic("wrapping_shl #581") }
    if !(0u32.wrapping_shr(37u32) == 0u32) { panic("wrapping_shr #582") }
    if !(0u32.overflowing_shl(37u32).0 == 0u32 && 0u32.overflowing_shl(37u32).1 == true) { panic("overflowing_shl #583") }
    if !(0u32.overflowing_shr(37u32).0 == 0u32 && 0u32.overflowing_shr(37u32).1 == true) { panic("overflowing_shr #584") }
    if !(0u32.unbounded_shl(37u32) == 0u32) { panic("unbounded_shl #585") }
    if !(0u32.unbounded_shr(37u32) == 0u32) { panic("unbounded_shr #586") }
    if !(0u32.checked_pow(0u32) == present(1u32)) { panic("checked_pow #587") }
    if !(0u32.wrapping_pow(0u32) == 1u32) { panic("wrapping_pow #588") }
    if !(0u32.overflowing_pow(0u32).0 == 1u32 && 0u32.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #589") }
    if !(0u32.saturating_pow(0u32) == 1u32) { panic("saturating_pow #590") }
    if !(0u32.pow(0u32) == 1u32) { panic("pow #591") }
    if !(0u32.strict_pow(0u32) == 1u32) { panic("strict_pow #592") }
    if !(0u32.checked_pow(1u32) == present(0u32)) { panic("checked_pow #593") }
    if !(0u32.wrapping_pow(1u32) == 0u32) { panic("wrapping_pow #594") }
    if !(0u32.overflowing_pow(1u32).0 == 0u32 && 0u32.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #595") }
    if !(0u32.saturating_pow(1u32) == 0u32) { panic("saturating_pow #596") }
    if !(0u32.pow(1u32) == 0u32) { panic("pow #597") }
    if !(0u32.strict_pow(1u32) == 0u32) { panic("strict_pow #598") }
    if !(0u32.checked_pow(2u32) == present(0u32)) { panic("checked_pow #599") }
    if !(0u32.wrapping_pow(2u32) == 0u32) { panic("wrapping_pow #600") }
}

fn group5() {
    if !(0u32.overflowing_pow(2u32).0 == 0u32 && 0u32.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #601") }
    if !(0u32.saturating_pow(2u32) == 0u32) { panic("saturating_pow #602") }
    if !(0u32.pow(2u32) == 0u32) { panic("pow #603") }
    if !(0u32.strict_pow(2u32) == 0u32) { panic("strict_pow #604") }
    if !(0u32.checked_pow(3u32) == present(0u32)) { panic("checked_pow #605") }
    if !(0u32.wrapping_pow(3u32) == 0u32) { panic("wrapping_pow #606") }
    if !(0u32.overflowing_pow(3u32).0 == 0u32 && 0u32.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #607") }
    if !(0u32.saturating_pow(3u32) == 0u32) { panic("saturating_pow #608") }
    if !(0u32.pow(3u32) == 0u32) { panic("pow #609") }
    if !(0u32.strict_pow(3u32) == 0u32) { panic("strict_pow #610") }
    if !(0u32.checked_pow(31u32) == present(0u32)) { panic("checked_pow #611") }
    if !(0u32.wrapping_pow(31u32) == 0u32) { panic("wrapping_pow #612") }
    if !(0u32.overflowing_pow(31u32).0 == 0u32 && 0u32.overflowing_pow(31u32).1 == false) { panic("overflowing_pow #613") }
    if !(0u32.saturating_pow(31u32) == 0u32) { panic("saturating_pow #614") }
    if !(0u32.pow(31u32) == 0u32) { panic("pow #615") }
    if !(0u32.strict_pow(31u32) == 0u32) { panic("strict_pow #616") }
    if !(0u32.checked_pow(32u32) == present(0u32)) { panic("checked_pow #617") }
    if !(0u32.wrapping_pow(32u32) == 0u32) { panic("wrapping_pow #618") }
    if !(0u32.overflowing_pow(32u32).0 == 0u32 && 0u32.overflowing_pow(32u32).1 == false) { panic("overflowing_pow #619") }
    if !(0u32.saturating_pow(32u32) == 0u32) { panic("saturating_pow #620") }
    if !(0u32.pow(32u32) == 0u32) { panic("pow #621") }
    if !(0u32.strict_pow(32u32) == 0u32) { panic("strict_pow #622") }
    if !(missing(0u32.checked_ilog2())) { panic("checked_ilog2 #623") }
    if !(missing(0u32.checked_ilog10())) { panic("checked_ilog10 #624") }
    if !(missing(0u32.checked_ilog(2u32))) { panic("checked_ilog #625") }
    if !(0u32.isqrt() == 0u32) { panic("isqrt #626") }
    if !(0u32.checked_isqrt() == present(0u32)) { panic("checked_isqrt #627") }
    if !(0u32.is_power_of_two() == false) { panic("is_power_of_two #628") }
    if !(0u32.checked_next_power_of_two() == present(1u32)) { panic("checked_next_power_of_two #629") }
    if !(0u32.next_power_of_two() == 1u32) { panic("next_power_of_two #630") }
    if !(0u32.div_ceil(1u32) == 0u32) { panic("div_ceil #631") }
    if !(0u32.checked_next_multiple_of(1u32) == present(0u32)) { panic("checked_next_multiple_of #632") }
    if !(0u32.next_multiple_of(1u32) == 0u32) { panic("next_multiple_of #633") }
    if !(0u32.is_multiple_of(1u32) == true) { panic("is_multiple_of #634") }
    if !(0u32.div_ceil(3u32) == 0u32) { panic("div_ceil #635") }
    if !(0u32.checked_next_multiple_of(3u32) == present(0u32)) { panic("checked_next_multiple_of #636") }
    if !(0u32.next_multiple_of(3u32) == 0u32) { panic("next_multiple_of #637") }
    if !(0u32.is_multiple_of(3u32) == true) { panic("is_multiple_of #638") }
    if !(0u32.div_ceil(7u32) == 0u32) { panic("div_ceil #639") }
    if !(0u32.checked_next_multiple_of(7u32) == present(0u32)) { panic("checked_next_multiple_of #640") }
    if !(0u32.next_multiple_of(7u32) == 0u32) { panic("next_multiple_of #641") }
    if !(0u32.is_multiple_of(7u32) == true) { panic("is_multiple_of #642") }
    if !(0u32.is_multiple_of(0u32) == true) { panic("is_multiple_of #643") }
    if !(missing(0u32.checked_next_multiple_of(0u32))) { panic("checked_next_multiple_of #644") }
    if !(missing(0u32.highest_one())) { panic("highest_one #645") }
    if !(missing(0u32.lowest_one())) { panic("lowest_one #646") }
    if !(0u32.isolate_highest_one() == 0u32) { panic("isolate_highest_one #647") }
    if !(0u32.isolate_lowest_one() == 0u32) { panic("isolate_lowest_one #648") }
    if !(0u32.bit_width() == 0u32) { panic("bit_width #649") }
    if !(missing(1000u32.checked_neg())) { panic("checked_neg #650") }
    if !(1000u32.wrapping_neg() == 4294966296u32) { panic("wrapping_neg #651") }
    if !(1000u32.overflowing_neg().0 == 4294966296u32 && 1000u32.overflowing_neg().1 == true) { panic("overflowing_neg #652") }
    if !(1000u32.cast_signed() == 1000i32) { panic("cast_signed #653") }
    if !(1000u32.count_ones() == 6u32) { panic("count_ones #654") }
    if !(1000u32.count_zeros() == 26u32) { panic("count_zeros #655") }
    if !(1000u32.leading_zeros() == 22u32) { panic("leading_zeros #656") }
    if !(1000u32.trailing_zeros() == 3u32) { panic("trailing_zeros #657") }
    if !(1000u32.leading_ones() == 0u32) { panic("leading_ones #658") }
    if !(1000u32.trailing_ones() == 0u32) { panic("trailing_ones #659") }
    if !(1000u32.reverse_bits() == 398458880u32) { panic("reverse_bits #660") }
    if !(1000u32.swap_bytes() == 3892510720u32) { panic("swap_bytes #661") }
    if !(1000u32.to_be() == 3892510720u32) { panic("to_be #662") }
    if !(1000u32.to_le() == 1000u32) { panic("to_le #663") }
    if !(u32.from_be(1000u32) == 3892510720u32) { panic("from_be #664") }
    if !(u32.from_le(1000u32) == 1000u32) { panic("from_le #665") }
    if !(1000u32.to_le_bytes() == [232u8, 3u8, 0u8, 0u8]) { panic("to_le_bytes #666") }
    if !(1000u32.to_be_bytes() == [0u8, 0u8, 3u8, 232u8]) { panic("to_be_bytes #667") }
    if !(1000u32.to_ne_bytes() == [232u8, 3u8, 0u8, 0u8]) { panic("to_ne_bytes #668") }
    if !(u32.from_le_bytes([232u8, 3u8, 0u8, 0u8]) == 1000u32) { panic("from_le_bytes #669") }
    if !(u32.from_be_bytes([0u8, 0u8, 3u8, 232u8]) == 1000u32) { panic("from_be_bytes #670") }
    if !(u32.from_ne_bytes([232u8, 3u8, 0u8, 0u8]) == 1000u32) { panic("from_ne_bytes #671") }
    if !(1000u32.rotate_left(0u32) == 1000u32) { panic("rotate_left #672") }
    if !(1000u32.rotate_right(0u32) == 1000u32) { panic("rotate_right #673") }
    if !(1000u32.checked_shl(0u32) == present(1000u32)) { panic("checked_shl #674") }
    if !(1000u32.checked_shr(0u32) == present(1000u32)) { panic("checked_shr #675") }
    if !(1000u32.wrapping_shl(0u32) == 1000u32) { panic("wrapping_shl #676") }
    if !(1000u32.wrapping_shr(0u32) == 1000u32) { panic("wrapping_shr #677") }
    if !(1000u32.overflowing_shl(0u32).0 == 1000u32 && 1000u32.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #678") }
    if !(1000u32.overflowing_shr(0u32).0 == 1000u32 && 1000u32.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #679") }
    if !(1000u32.unbounded_shl(0u32) == 1000u32) { panic("unbounded_shl #680") }
    if !(1000u32.unbounded_shr(0u32) == 1000u32) { panic("unbounded_shr #681") }
    if !(1000u32.strict_shl(0u32) == 1000u32) { panic("strict_shl #682") }
    if !(1000u32.strict_shr(0u32) == 1000u32) { panic("strict_shr #683") }
    if !(unsafe { 1000u32.unchecked_shl(0u32) } == 1000u32) { panic("unchecked_shl #684") }
    if !(unsafe { 1000u32.unchecked_shr(0u32) } == 1000u32) { panic("unchecked_shr #685") }
    if !(1000u32.rotate_left(1u32) == 2000u32) { panic("rotate_left #686") }
    if !(1000u32.rotate_right(1u32) == 500u32) { panic("rotate_right #687") }
    if !(1000u32.checked_shl(1u32) == present(2000u32)) { panic("checked_shl #688") }
    if !(1000u32.checked_shr(1u32) == present(500u32)) { panic("checked_shr #689") }
    if !(1000u32.wrapping_shl(1u32) == 2000u32) { panic("wrapping_shl #690") }
    if !(1000u32.wrapping_shr(1u32) == 500u32) { panic("wrapping_shr #691") }
    if !(1000u32.overflowing_shl(1u32).0 == 2000u32 && 1000u32.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #692") }
    if !(1000u32.overflowing_shr(1u32).0 == 500u32 && 1000u32.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #693") }
    if !(1000u32.unbounded_shl(1u32) == 2000u32) { panic("unbounded_shl #694") }
    if !(1000u32.unbounded_shr(1u32) == 500u32) { panic("unbounded_shr #695") }
    if !(1000u32.strict_shl(1u32) == 2000u32) { panic("strict_shl #696") }
    if !(1000u32.strict_shr(1u32) == 500u32) { panic("strict_shr #697") }
    if !(unsafe { 1000u32.unchecked_shl(1u32) } == 2000u32) { panic("unchecked_shl #698") }
    if !(unsafe { 1000u32.unchecked_shr(1u32) } == 500u32) { panic("unchecked_shr #699") }
    if !(1000u32.rotate_left(3u32) == 8000u32) { panic("rotate_left #700") }
    if !(1000u32.rotate_right(3u32) == 125u32) { panic("rotate_right #701") }
    if !(1000u32.checked_shl(3u32) == present(8000u32)) { panic("checked_shl #702") }
    if !(1000u32.checked_shr(3u32) == present(125u32)) { panic("checked_shr #703") }
    if !(1000u32.wrapping_shl(3u32) == 8000u32) { panic("wrapping_shl #704") }
    if !(1000u32.wrapping_shr(3u32) == 125u32) { panic("wrapping_shr #705") }
    if !(1000u32.overflowing_shl(3u32).0 == 8000u32 && 1000u32.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #706") }
    if !(1000u32.overflowing_shr(3u32).0 == 125u32 && 1000u32.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #707") }
    if !(1000u32.unbounded_shl(3u32) == 8000u32) { panic("unbounded_shl #708") }
    if !(1000u32.unbounded_shr(3u32) == 125u32) { panic("unbounded_shr #709") }
    if !(1000u32.strict_shl(3u32) == 8000u32) { panic("strict_shl #710") }
    if !(1000u32.strict_shr(3u32) == 125u32) { panic("strict_shr #711") }
    if !(unsafe { 1000u32.unchecked_shl(3u32) } == 8000u32) { panic("unchecked_shl #712") }
    if !(unsafe { 1000u32.unchecked_shr(3u32) } == 125u32) { panic("unchecked_shr #713") }
    if !(1000u32.rotate_left(31u32) == 500u32) { panic("rotate_left #714") }
    if !(1000u32.rotate_right(31u32) == 2000u32) { panic("rotate_right #715") }
    if !(1000u32.checked_shl(31u32) == present(0u32)) { panic("checked_shl #716") }
    if !(1000u32.checked_shr(31u32) == present(0u32)) { panic("checked_shr #717") }
    if !(1000u32.wrapping_shl(31u32) == 0u32) { panic("wrapping_shl #718") }
    if !(1000u32.wrapping_shr(31u32) == 0u32) { panic("wrapping_shr #719") }
    if !(1000u32.overflowing_shl(31u32).0 == 0u32 && 1000u32.overflowing_shl(31u32).1 == false) { panic("overflowing_shl #720") }
}

fn group6() {
    if !(1000u32.overflowing_shr(31u32).0 == 0u32 && 1000u32.overflowing_shr(31u32).1 == false) { panic("overflowing_shr #721") }
    if !(1000u32.unbounded_shl(31u32) == 0u32) { panic("unbounded_shl #722") }
    if !(1000u32.unbounded_shr(31u32) == 0u32) { panic("unbounded_shr #723") }
    if !(1000u32.strict_shl(31u32) == 0u32) { panic("strict_shl #724") }
    if !(1000u32.strict_shr(31u32) == 0u32) { panic("strict_shr #725") }
    if !(unsafe { 1000u32.unchecked_shl(31u32) } == 0u32) { panic("unchecked_shl #726") }
    if !(unsafe { 1000u32.unchecked_shr(31u32) } == 0u32) { panic("unchecked_shr #727") }
    if !(1000u32.rotate_left(32u32) == 1000u32) { panic("rotate_left #728") }
    if !(1000u32.rotate_right(32u32) == 1000u32) { panic("rotate_right #729") }
    if !(missing(1000u32.checked_shl(32u32))) { panic("checked_shl #730") }
    if !(missing(1000u32.checked_shr(32u32))) { panic("checked_shr #731") }
    if !(1000u32.wrapping_shl(32u32) == 1000u32) { panic("wrapping_shl #732") }
    if !(1000u32.wrapping_shr(32u32) == 1000u32) { panic("wrapping_shr #733") }
    if !(1000u32.overflowing_shl(32u32).0 == 1000u32 && 1000u32.overflowing_shl(32u32).1 == true) { panic("overflowing_shl #734") }
    if !(1000u32.overflowing_shr(32u32).0 == 1000u32 && 1000u32.overflowing_shr(32u32).1 == true) { panic("overflowing_shr #735") }
    if !(1000u32.unbounded_shl(32u32) == 0u32) { panic("unbounded_shl #736") }
    if !(1000u32.unbounded_shr(32u32) == 0u32) { panic("unbounded_shr #737") }
    if !(1000u32.rotate_left(37u32) == 32000u32) { panic("rotate_left #738") }
    if !(1000u32.rotate_right(37u32) == 1073741855u32) { panic("rotate_right #739") }
    if !(missing(1000u32.checked_shl(37u32))) { panic("checked_shl #740") }
    if !(missing(1000u32.checked_shr(37u32))) { panic("checked_shr #741") }
    if !(1000u32.wrapping_shl(37u32) == 32000u32) { panic("wrapping_shl #742") }
    if !(1000u32.wrapping_shr(37u32) == 31u32) { panic("wrapping_shr #743") }
    if !(1000u32.overflowing_shl(37u32).0 == 32000u32 && 1000u32.overflowing_shl(37u32).1 == true) { panic("overflowing_shl #744") }
    if !(1000u32.overflowing_shr(37u32).0 == 31u32 && 1000u32.overflowing_shr(37u32).1 == true) { panic("overflowing_shr #745") }
    if !(1000u32.unbounded_shl(37u32) == 0u32) { panic("unbounded_shl #746") }
    if !(1000u32.unbounded_shr(37u32) == 0u32) { panic("unbounded_shr #747") }
    if !(1000u32.checked_pow(0u32) == present(1u32)) { panic("checked_pow #748") }
    if !(1000u32.wrapping_pow(0u32) == 1u32) { panic("wrapping_pow #749") }
    if !(1000u32.overflowing_pow(0u32).0 == 1u32 && 1000u32.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #750") }
    if !(1000u32.saturating_pow(0u32) == 1u32) { panic("saturating_pow #751") }
    if !(1000u32.pow(0u32) == 1u32) { panic("pow #752") }
    if !(1000u32.strict_pow(0u32) == 1u32) { panic("strict_pow #753") }
    if !(1000u32.checked_pow(1u32) == present(1000u32)) { panic("checked_pow #754") }
    if !(1000u32.wrapping_pow(1u32) == 1000u32) { panic("wrapping_pow #755") }
    if !(1000u32.overflowing_pow(1u32).0 == 1000u32 && 1000u32.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #756") }
    if !(1000u32.saturating_pow(1u32) == 1000u32) { panic("saturating_pow #757") }
    if !(1000u32.pow(1u32) == 1000u32) { panic("pow #758") }
    if !(1000u32.strict_pow(1u32) == 1000u32) { panic("strict_pow #759") }
    if !(1000u32.checked_pow(2u32) == present(1000000u32)) { panic("checked_pow #760") }
    if !(1000u32.wrapping_pow(2u32) == 1000000u32) { panic("wrapping_pow #761") }
    if !(1000u32.overflowing_pow(2u32).0 == 1000000u32 && 1000u32.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #762") }
    if !(1000u32.saturating_pow(2u32) == 1000000u32) { panic("saturating_pow #763") }
    if !(1000u32.pow(2u32) == 1000000u32) { panic("pow #764") }
    if !(1000u32.strict_pow(2u32) == 1000000u32) { panic("strict_pow #765") }
    if !(1000u32.checked_pow(3u32) == present(1000000000u32)) { panic("checked_pow #766") }
    if !(1000u32.wrapping_pow(3u32) == 1000000000u32) { panic("wrapping_pow #767") }
    if !(1000u32.overflowing_pow(3u32).0 == 1000000000u32 && 1000u32.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #768") }
    if !(1000u32.saturating_pow(3u32) == 1000000000u32) { panic("saturating_pow #769") }
    if !(1000u32.pow(3u32) == 1000000000u32) { panic("pow #770") }
    if !(1000u32.strict_pow(3u32) == 1000000000u32) { panic("strict_pow #771") }
    if !(missing(1000u32.checked_pow(31u32))) { panic("checked_pow #772") }
    if !(1000u32.wrapping_pow(31u32) == 0u32) { panic("wrapping_pow #773") }
    if !(1000u32.overflowing_pow(31u32).0 == 0u32 && 1000u32.overflowing_pow(31u32).1 == true) { panic("overflowing_pow #774") }
    if !(1000u32.saturating_pow(31u32) == u32.MAX) { panic("saturating_pow #775") }
    if !(missing(1000u32.checked_pow(32u32))) { panic("checked_pow #776") }
    if !(1000u32.wrapping_pow(32u32) == 0u32) { panic("wrapping_pow #777") }
    if !(1000u32.overflowing_pow(32u32).0 == 0u32 && 1000u32.overflowing_pow(32u32).1 == true) { panic("overflowing_pow #778") }
    if !(1000u32.saturating_pow(32u32) == u32.MAX) { panic("saturating_pow #779") }
    if !(1000u32.ilog2() == 9u32) { panic("ilog2 #780") }
    if !(1000u32.ilog10() == 3u32) { panic("ilog10 #781") }
    if !(1000u32.checked_ilog2() == present(9u32)) { panic("checked_ilog2 #782") }
    if !(1000u32.checked_ilog10() == present(3u32)) { panic("checked_ilog10 #783") }
    if !(1000u32.ilog(2u32) == 9u32) { panic("ilog #784") }
    if !(1000u32.checked_ilog(2u32) == present(9u32)) { panic("checked_ilog #785") }
    if !(1000u32.ilog(3u32) == 6u32) { panic("ilog #786") }
    if !(1000u32.checked_ilog(3u32) == present(6u32)) { panic("checked_ilog #787") }
    if !(1000u32.ilog(7u32) == 3u32) { panic("ilog #788") }
    if !(1000u32.checked_ilog(7u32) == present(3u32)) { panic("checked_ilog #789") }
    if !(missing(1000u32.checked_ilog(1u32))) { panic("checked_ilog #790") }
    if !(1000u32.isqrt() == 31u32) { panic("isqrt #791") }
    if !(1000u32.checked_isqrt() == present(31u32)) { panic("checked_isqrt #792") }
    if !(1000u32.is_power_of_two() == false) { panic("is_power_of_two #793") }
    if !(1000u32.checked_next_power_of_two() == present(1024u32)) { panic("checked_next_power_of_two #794") }
    if !(1000u32.next_power_of_two() == 1024u32) { panic("next_power_of_two #795") }
    if !(1000u32.div_ceil(1u32) == 1000u32) { panic("div_ceil #796") }
    if !(1000u32.checked_next_multiple_of(1u32) == present(1000u32)) { panic("checked_next_multiple_of #797") }
    if !(1000u32.next_multiple_of(1u32) == 1000u32) { panic("next_multiple_of #798") }
    if !(1000u32.is_multiple_of(1u32) == true) { panic("is_multiple_of #799") }
    if !(1000u32.div_ceil(3u32) == 334u32) { panic("div_ceil #800") }
    if !(1000u32.checked_next_multiple_of(3u32) == present(1002u32)) { panic("checked_next_multiple_of #801") }
    if !(1000u32.next_multiple_of(3u32) == 1002u32) { panic("next_multiple_of #802") }
    if !(1000u32.is_multiple_of(3u32) == false) { panic("is_multiple_of #803") }
    if !(1000u32.div_ceil(7u32) == 143u32) { panic("div_ceil #804") }
    if !(1000u32.checked_next_multiple_of(7u32) == present(1001u32)) { panic("checked_next_multiple_of #805") }
    if !(1000u32.next_multiple_of(7u32) == 1001u32) { panic("next_multiple_of #806") }
    if !(1000u32.is_multiple_of(7u32) == false) { panic("is_multiple_of #807") }
    if !(1000u32.is_multiple_of(0u32) == false) { panic("is_multiple_of #808") }
    if !(missing(1000u32.checked_next_multiple_of(0u32))) { panic("checked_next_multiple_of #809") }
    if !(1000u32.highest_one() == present(9u32)) { panic("highest_one #810") }
    if !(1000u32.lowest_one() == present(3u32)) { panic("lowest_one #811") }
    if !(1000u32.isolate_highest_one() == 512u32) { panic("isolate_highest_one #812") }
    if !(1000u32.isolate_lowest_one() == 8u32) { panic("isolate_lowest_one #813") }
    if !(1000u32.bit_width() == 10u32) { panic("bit_width #814") }
    if !(missing(7u32.checked_neg())) { panic("checked_neg #815") }
    if !(7u32.wrapping_neg() == 4294967289u32) { panic("wrapping_neg #816") }
    if !(7u32.overflowing_neg().0 == 4294967289u32 && 7u32.overflowing_neg().1 == true) { panic("overflowing_neg #817") }
    if !(7u32.cast_signed() == 7i32) { panic("cast_signed #818") }
    if !(7u32.count_ones() == 3u32) { panic("count_ones #819") }
    if !(7u32.count_zeros() == 29u32) { panic("count_zeros #820") }
    if !(7u32.leading_zeros() == 29u32) { panic("leading_zeros #821") }
    if !(7u32.trailing_zeros() == 0u32) { panic("trailing_zeros #822") }
    if !(7u32.leading_ones() == 0u32) { panic("leading_ones #823") }
    if !(7u32.trailing_ones() == 3u32) { panic("trailing_ones #824") }
    if !(7u32.reverse_bits() == 3758096384u32) { panic("reverse_bits #825") }
    if !(7u32.swap_bytes() == 117440512u32) { panic("swap_bytes #826") }
    if !(7u32.to_be() == 117440512u32) { panic("to_be #827") }
    if !(7u32.to_le() == 7u32) { panic("to_le #828") }
    if !(u32.from_be(7u32) == 117440512u32) { panic("from_be #829") }
    if !(u32.from_le(7u32) == 7u32) { panic("from_le #830") }
    if !(7u32.to_le_bytes() == [7u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #831") }
    if !(7u32.to_be_bytes() == [0u8, 0u8, 0u8, 7u8]) { panic("to_be_bytes #832") }
    if !(7u32.to_ne_bytes() == [7u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #833") }
    if !(u32.from_le_bytes([7u8, 0u8, 0u8, 0u8]) == 7u32) { panic("from_le_bytes #834") }
    if !(u32.from_be_bytes([0u8, 0u8, 0u8, 7u8]) == 7u32) { panic("from_be_bytes #835") }
    if !(u32.from_ne_bytes([7u8, 0u8, 0u8, 0u8]) == 7u32) { panic("from_ne_bytes #836") }
    if !(7u32.rotate_left(0u32) == 7u32) { panic("rotate_left #837") }
    if !(7u32.rotate_right(0u32) == 7u32) { panic("rotate_right #838") }
    if !(7u32.checked_shl(0u32) == present(7u32)) { panic("checked_shl #839") }
    if !(7u32.checked_shr(0u32) == present(7u32)) { panic("checked_shr #840") }
}

fn group7() {
    if !(7u32.wrapping_shl(0u32) == 7u32) { panic("wrapping_shl #841") }
    if !(7u32.wrapping_shr(0u32) == 7u32) { panic("wrapping_shr #842") }
    if !(7u32.overflowing_shl(0u32).0 == 7u32 && 7u32.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #843") }
    if !(7u32.overflowing_shr(0u32).0 == 7u32 && 7u32.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #844") }
    if !(7u32.unbounded_shl(0u32) == 7u32) { panic("unbounded_shl #845") }
    if !(7u32.unbounded_shr(0u32) == 7u32) { panic("unbounded_shr #846") }
    if !(7u32.strict_shl(0u32) == 7u32) { panic("strict_shl #847") }
    if !(7u32.strict_shr(0u32) == 7u32) { panic("strict_shr #848") }
    if !(unsafe { 7u32.unchecked_shl(0u32) } == 7u32) { panic("unchecked_shl #849") }
    if !(unsafe { 7u32.unchecked_shr(0u32) } == 7u32) { panic("unchecked_shr #850") }
    if !(7u32.rotate_left(1u32) == 14u32) { panic("rotate_left #851") }
    if !(7u32.rotate_right(1u32) == 2147483651u32) { panic("rotate_right #852") }
    if !(7u32.checked_shl(1u32) == present(14u32)) { panic("checked_shl #853") }
    if !(7u32.checked_shr(1u32) == present(3u32)) { panic("checked_shr #854") }
    if !(7u32.wrapping_shl(1u32) == 14u32) { panic("wrapping_shl #855") }
    if !(7u32.wrapping_shr(1u32) == 3u32) { panic("wrapping_shr #856") }
    if !(7u32.overflowing_shl(1u32).0 == 14u32 && 7u32.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #857") }
    if !(7u32.overflowing_shr(1u32).0 == 3u32 && 7u32.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #858") }
    if !(7u32.unbounded_shl(1u32) == 14u32) { panic("unbounded_shl #859") }
    if !(7u32.unbounded_shr(1u32) == 3u32) { panic("unbounded_shr #860") }
    if !(7u32.strict_shl(1u32) == 14u32) { panic("strict_shl #861") }
    if !(7u32.strict_shr(1u32) == 3u32) { panic("strict_shr #862") }
    if !(unsafe { 7u32.unchecked_shl(1u32) } == 14u32) { panic("unchecked_shl #863") }
    if !(unsafe { 7u32.unchecked_shr(1u32) } == 3u32) { panic("unchecked_shr #864") }
    if !(7u32.rotate_left(3u32) == 56u32) { panic("rotate_left #865") }
    if !(7u32.rotate_right(3u32) == 3758096384u32) { panic("rotate_right #866") }
    if !(7u32.checked_shl(3u32) == present(56u32)) { panic("checked_shl #867") }
    if !(7u32.checked_shr(3u32) == present(0u32)) { panic("checked_shr #868") }
    if !(7u32.wrapping_shl(3u32) == 56u32) { panic("wrapping_shl #869") }
    if !(7u32.wrapping_shr(3u32) == 0u32) { panic("wrapping_shr #870") }
    if !(7u32.overflowing_shl(3u32).0 == 56u32 && 7u32.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #871") }
    if !(7u32.overflowing_shr(3u32).0 == 0u32 && 7u32.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #872") }
    if !(7u32.unbounded_shl(3u32) == 56u32) { panic("unbounded_shl #873") }
    if !(7u32.unbounded_shr(3u32) == 0u32) { panic("unbounded_shr #874") }
    if !(7u32.strict_shl(3u32) == 56u32) { panic("strict_shl #875") }
    if !(7u32.strict_shr(3u32) == 0u32) { panic("strict_shr #876") }
    if !(unsafe { 7u32.unchecked_shl(3u32) } == 56u32) { panic("unchecked_shl #877") }
    if !(unsafe { 7u32.unchecked_shr(3u32) } == 0u32) { panic("unchecked_shr #878") }
    if !(7u32.rotate_left(31u32) == 2147483651u32) { panic("rotate_left #879") }
    if !(7u32.rotate_right(31u32) == 14u32) { panic("rotate_right #880") }
    if !(7u32.checked_shl(31u32) == present(2147483648u32)) { panic("checked_shl #881") }
    if !(7u32.checked_shr(31u32) == present(0u32)) { panic("checked_shr #882") }
    if !(7u32.wrapping_shl(31u32) == 2147483648u32) { panic("wrapping_shl #883") }
    if !(7u32.wrapping_shr(31u32) == 0u32) { panic("wrapping_shr #884") }
    if !(7u32.overflowing_shl(31u32).0 == 2147483648u32 && 7u32.overflowing_shl(31u32).1 == false) { panic("overflowing_shl #885") }
    if !(7u32.overflowing_shr(31u32).0 == 0u32 && 7u32.overflowing_shr(31u32).1 == false) { panic("overflowing_shr #886") }
    if !(7u32.unbounded_shl(31u32) == 2147483648u32) { panic("unbounded_shl #887") }
    if !(7u32.unbounded_shr(31u32) == 0u32) { panic("unbounded_shr #888") }
    if !(7u32.strict_shl(31u32) == 2147483648u32) { panic("strict_shl #889") }
    if !(7u32.strict_shr(31u32) == 0u32) { panic("strict_shr #890") }
    if !(unsafe { 7u32.unchecked_shl(31u32) } == 2147483648u32) { panic("unchecked_shl #891") }
    if !(unsafe { 7u32.unchecked_shr(31u32) } == 0u32) { panic("unchecked_shr #892") }
    if !(7u32.rotate_left(32u32) == 7u32) { panic("rotate_left #893") }
    if !(7u32.rotate_right(32u32) == 7u32) { panic("rotate_right #894") }
    if !(missing(7u32.checked_shl(32u32))) { panic("checked_shl #895") }
    if !(missing(7u32.checked_shr(32u32))) { panic("checked_shr #896") }
    if !(7u32.wrapping_shl(32u32) == 7u32) { panic("wrapping_shl #897") }
    if !(7u32.wrapping_shr(32u32) == 7u32) { panic("wrapping_shr #898") }
    if !(7u32.overflowing_shl(32u32).0 == 7u32 && 7u32.overflowing_shl(32u32).1 == true) { panic("overflowing_shl #899") }
    if !(7u32.overflowing_shr(32u32).0 == 7u32 && 7u32.overflowing_shr(32u32).1 == true) { panic("overflowing_shr #900") }
    if !(7u32.unbounded_shl(32u32) == 0u32) { panic("unbounded_shl #901") }
    if !(7u32.unbounded_shr(32u32) == 0u32) { panic("unbounded_shr #902") }
    if !(7u32.rotate_left(37u32) == 224u32) { panic("rotate_left #903") }
    if !(7u32.rotate_right(37u32) == 939524096u32) { panic("rotate_right #904") }
    if !(missing(7u32.checked_shl(37u32))) { panic("checked_shl #905") }
    if !(missing(7u32.checked_shr(37u32))) { panic("checked_shr #906") }
    if !(7u32.wrapping_shl(37u32) == 224u32) { panic("wrapping_shl #907") }
    if !(7u32.wrapping_shr(37u32) == 0u32) { panic("wrapping_shr #908") }
    if !(7u32.overflowing_shl(37u32).0 == 224u32 && 7u32.overflowing_shl(37u32).1 == true) { panic("overflowing_shl #909") }
    if !(7u32.overflowing_shr(37u32).0 == 0u32 && 7u32.overflowing_shr(37u32).1 == true) { panic("overflowing_shr #910") }
    if !(7u32.unbounded_shl(37u32) == 0u32) { panic("unbounded_shl #911") }
    if !(7u32.unbounded_shr(37u32) == 0u32) { panic("unbounded_shr #912") }
    if !(7u32.checked_pow(0u32) == present(1u32)) { panic("checked_pow #913") }
    if !(7u32.wrapping_pow(0u32) == 1u32) { panic("wrapping_pow #914") }
    if !(7u32.overflowing_pow(0u32).0 == 1u32 && 7u32.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #915") }
    if !(7u32.saturating_pow(0u32) == 1u32) { panic("saturating_pow #916") }
    if !(7u32.pow(0u32) == 1u32) { panic("pow #917") }
    if !(7u32.strict_pow(0u32) == 1u32) { panic("strict_pow #918") }
    if !(7u32.checked_pow(1u32) == present(7u32)) { panic("checked_pow #919") }
    if !(7u32.wrapping_pow(1u32) == 7u32) { panic("wrapping_pow #920") }
    if !(7u32.overflowing_pow(1u32).0 == 7u32 && 7u32.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #921") }
    if !(7u32.saturating_pow(1u32) == 7u32) { panic("saturating_pow #922") }
    if !(7u32.pow(1u32) == 7u32) { panic("pow #923") }
    if !(7u32.strict_pow(1u32) == 7u32) { panic("strict_pow #924") }
    if !(7u32.checked_pow(2u32) == present(49u32)) { panic("checked_pow #925") }
    if !(7u32.wrapping_pow(2u32) == 49u32) { panic("wrapping_pow #926") }
    if !(7u32.overflowing_pow(2u32).0 == 49u32 && 7u32.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #927") }
    if !(7u32.saturating_pow(2u32) == 49u32) { panic("saturating_pow #928") }
    if !(7u32.pow(2u32) == 49u32) { panic("pow #929") }
    if !(7u32.strict_pow(2u32) == 49u32) { panic("strict_pow #930") }
    if !(7u32.checked_pow(3u32) == present(343u32)) { panic("checked_pow #931") }
    if !(7u32.wrapping_pow(3u32) == 343u32) { panic("wrapping_pow #932") }
    if !(7u32.overflowing_pow(3u32).0 == 343u32 && 7u32.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #933") }
    if !(7u32.saturating_pow(3u32) == 343u32) { panic("saturating_pow #934") }
    if !(7u32.pow(3u32) == 343u32) { panic("pow #935") }
    if !(7u32.strict_pow(3u32) == 343u32) { panic("strict_pow #936") }
    if !(missing(7u32.checked_pow(31u32))) { panic("checked_pow #937") }
    if !(7u32.wrapping_pow(31u32) == 265001655u32) { panic("wrapping_pow #938") }
    if !(7u32.overflowing_pow(31u32).0 == 265001655u32 && 7u32.overflowing_pow(31u32).1 == true) { panic("overflowing_pow #939") }
    if !(7u32.saturating_pow(31u32) == u32.MAX) { panic("saturating_pow #940") }
    if !(missing(7u32.checked_pow(32u32))) { panic("checked_pow #941") }
    if !(7u32.wrapping_pow(32u32) == 1855011585u32) { panic("wrapping_pow #942") }
    if !(7u32.overflowing_pow(32u32).0 == 1855011585u32 && 7u32.overflowing_pow(32u32).1 == true) { panic("overflowing_pow #943") }
    if !(7u32.saturating_pow(32u32) == u32.MAX) { panic("saturating_pow #944") }
    if !(7u32.ilog2() == 2u32) { panic("ilog2 #945") }
    if !(7u32.ilog10() == 0u32) { panic("ilog10 #946") }
    if !(7u32.checked_ilog2() == present(2u32)) { panic("checked_ilog2 #947") }
    if !(7u32.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #948") }
    if !(7u32.ilog(2u32) == 2u32) { panic("ilog #949") }
    if !(7u32.checked_ilog(2u32) == present(2u32)) { panic("checked_ilog #950") }
    if !(7u32.ilog(3u32) == 1u32) { panic("ilog #951") }
    if !(7u32.checked_ilog(3u32) == present(1u32)) { panic("checked_ilog #952") }
    if !(7u32.ilog(7u32) == 1u32) { panic("ilog #953") }
    if !(7u32.checked_ilog(7u32) == present(1u32)) { panic("checked_ilog #954") }
    if !(missing(7u32.checked_ilog(1u32))) { panic("checked_ilog #955") }
    if !(7u32.isqrt() == 2u32) { panic("isqrt #956") }
    if !(7u32.checked_isqrt() == present(2u32)) { panic("checked_isqrt #957") }
    if !(7u32.is_power_of_two() == false) { panic("is_power_of_two #958") }
    if !(7u32.checked_next_power_of_two() == present(8u32)) { panic("checked_next_power_of_two #959") }
    if !(7u32.next_power_of_two() == 8u32) { panic("next_power_of_two #960") }
}

fn group8() {
    if !(7u32.div_ceil(1u32) == 7u32) { panic("div_ceil #961") }
    if !(7u32.checked_next_multiple_of(1u32) == present(7u32)) { panic("checked_next_multiple_of #962") }
    if !(7u32.next_multiple_of(1u32) == 7u32) { panic("next_multiple_of #963") }
    if !(7u32.is_multiple_of(1u32) == true) { panic("is_multiple_of #964") }
    if !(7u32.div_ceil(3u32) == 3u32) { panic("div_ceil #965") }
    if !(7u32.checked_next_multiple_of(3u32) == present(9u32)) { panic("checked_next_multiple_of #966") }
    if !(7u32.next_multiple_of(3u32) == 9u32) { panic("next_multiple_of #967") }
    if !(7u32.is_multiple_of(3u32) == false) { panic("is_multiple_of #968") }
    if !(7u32.div_ceil(7u32) == 1u32) { panic("div_ceil #969") }
    if !(7u32.checked_next_multiple_of(7u32) == present(7u32)) { panic("checked_next_multiple_of #970") }
    if !(7u32.next_multiple_of(7u32) == 7u32) { panic("next_multiple_of #971") }
    if !(7u32.is_multiple_of(7u32) == true) { panic("is_multiple_of #972") }
    if !(7u32.is_multiple_of(0u32) == false) { panic("is_multiple_of #973") }
    if !(missing(7u32.checked_next_multiple_of(0u32))) { panic("checked_next_multiple_of #974") }
    if !(7u32.highest_one() == present(2u32)) { panic("highest_one #975") }
    if !(7u32.lowest_one() == present(0u32)) { panic("lowest_one #976") }
    if !(7u32.isolate_highest_one() == 4u32) { panic("isolate_highest_one #977") }
    if !(7u32.isolate_lowest_one() == 1u32) { panic("isolate_lowest_one #978") }
    if !(7u32.bit_width() == 3u32) { panic("bit_width #979") }
    if !(0u32.checked_neg() == present(0u32)) { panic("checked_neg #980") }
    if !(0u32.wrapping_neg() == 0u32) { panic("wrapping_neg #981") }
    if !(0u32.overflowing_neg().0 == 0u32 && 0u32.overflowing_neg().1 == false) { panic("overflowing_neg #982") }
    if !(0u32.strict_neg() == 0u32) { panic("strict_neg #983") }
    if !(0u32.cast_signed() == 0i32) { panic("cast_signed #984") }
    if !(0u32.count_ones() == 0u32) { panic("count_ones #985") }
    if !(0u32.count_zeros() == 32u32) { panic("count_zeros #986") }
    if !(0u32.leading_zeros() == 32u32) { panic("leading_zeros #987") }
    if !(0u32.trailing_zeros() == 32u32) { panic("trailing_zeros #988") }
    if !(0u32.leading_ones() == 0u32) { panic("leading_ones #989") }
    if !(0u32.trailing_ones() == 0u32) { panic("trailing_ones #990") }
    if !(0u32.reverse_bits() == 0u32) { panic("reverse_bits #991") }
    if !(0u32.swap_bytes() == 0u32) { panic("swap_bytes #992") }
    if !(0u32.to_be() == 0u32) { panic("to_be #993") }
    if !(0u32.to_le() == 0u32) { panic("to_le #994") }
    if !(u32.from_be(0u32) == 0u32) { panic("from_be #995") }
    if !(u32.from_le(0u32) == 0u32) { panic("from_le #996") }
    if !(0u32.to_le_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #997") }
    if !(0u32.to_be_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #998") }
    if !(0u32.to_ne_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #999") }
    if !(u32.from_le_bytes([0u8, 0u8, 0u8, 0u8]) == 0u32) { panic("from_le_bytes #1000") }
    if !(u32.from_be_bytes([0u8, 0u8, 0u8, 0u8]) == 0u32) { panic("from_be_bytes #1001") }
    if !(u32.from_ne_bytes([0u8, 0u8, 0u8, 0u8]) == 0u32) { panic("from_ne_bytes #1002") }
    if !(0u32.rotate_left(0u32) == 0u32) { panic("rotate_left #1003") }
    if !(0u32.rotate_right(0u32) == 0u32) { panic("rotate_right #1004") }
    if !(0u32.checked_shl(0u32) == present(0u32)) { panic("checked_shl #1005") }
    if !(0u32.checked_shr(0u32) == present(0u32)) { panic("checked_shr #1006") }
    if !(0u32.wrapping_shl(0u32) == 0u32) { panic("wrapping_shl #1007") }
    if !(0u32.wrapping_shr(0u32) == 0u32) { panic("wrapping_shr #1008") }
    if !(0u32.overflowing_shl(0u32).0 == 0u32 && 0u32.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1009") }
    if !(0u32.overflowing_shr(0u32).0 == 0u32 && 0u32.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1010") }
    if !(0u32.unbounded_shl(0u32) == 0u32) { panic("unbounded_shl #1011") }
    if !(0u32.unbounded_shr(0u32) == 0u32) { panic("unbounded_shr #1012") }
    if !(0u32.strict_shl(0u32) == 0u32) { panic("strict_shl #1013") }
    if !(0u32.strict_shr(0u32) == 0u32) { panic("strict_shr #1014") }
    if !(unsafe { 0u32.unchecked_shl(0u32) } == 0u32) { panic("unchecked_shl #1015") }
    if !(unsafe { 0u32.unchecked_shr(0u32) } == 0u32) { panic("unchecked_shr #1016") }
    if !(0u32.rotate_left(1u32) == 0u32) { panic("rotate_left #1017") }
    if !(0u32.rotate_right(1u32) == 0u32) { panic("rotate_right #1018") }
    if !(0u32.checked_shl(1u32) == present(0u32)) { panic("checked_shl #1019") }
    if !(0u32.checked_shr(1u32) == present(0u32)) { panic("checked_shr #1020") }
    if !(0u32.wrapping_shl(1u32) == 0u32) { panic("wrapping_shl #1021") }
    if !(0u32.wrapping_shr(1u32) == 0u32) { panic("wrapping_shr #1022") }
    if !(0u32.overflowing_shl(1u32).0 == 0u32 && 0u32.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1023") }
    if !(0u32.overflowing_shr(1u32).0 == 0u32 && 0u32.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1024") }
    if !(0u32.unbounded_shl(1u32) == 0u32) { panic("unbounded_shl #1025") }
    if !(0u32.unbounded_shr(1u32) == 0u32) { panic("unbounded_shr #1026") }
    if !(0u32.strict_shl(1u32) == 0u32) { panic("strict_shl #1027") }
    if !(0u32.strict_shr(1u32) == 0u32) { panic("strict_shr #1028") }
    if !(unsafe { 0u32.unchecked_shl(1u32) } == 0u32) { panic("unchecked_shl #1029") }
    if !(unsafe { 0u32.unchecked_shr(1u32) } == 0u32) { panic("unchecked_shr #1030") }
    if !(0u32.rotate_left(3u32) == 0u32) { panic("rotate_left #1031") }
    if !(0u32.rotate_right(3u32) == 0u32) { panic("rotate_right #1032") }
    if !(0u32.checked_shl(3u32) == present(0u32)) { panic("checked_shl #1033") }
    if !(0u32.checked_shr(3u32) == present(0u32)) { panic("checked_shr #1034") }
    if !(0u32.wrapping_shl(3u32) == 0u32) { panic("wrapping_shl #1035") }
    if !(0u32.wrapping_shr(3u32) == 0u32) { panic("wrapping_shr #1036") }
    if !(0u32.overflowing_shl(3u32).0 == 0u32 && 0u32.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1037") }
    if !(0u32.overflowing_shr(3u32).0 == 0u32 && 0u32.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1038") }
    if !(0u32.unbounded_shl(3u32) == 0u32) { panic("unbounded_shl #1039") }
    if !(0u32.unbounded_shr(3u32) == 0u32) { panic("unbounded_shr #1040") }
    if !(0u32.strict_shl(3u32) == 0u32) { panic("strict_shl #1041") }
    if !(0u32.strict_shr(3u32) == 0u32) { panic("strict_shr #1042") }
    if !(unsafe { 0u32.unchecked_shl(3u32) } == 0u32) { panic("unchecked_shl #1043") }
    if !(unsafe { 0u32.unchecked_shr(3u32) } == 0u32) { panic("unchecked_shr #1044") }
    if !(0u32.rotate_left(31u32) == 0u32) { panic("rotate_left #1045") }
    if !(0u32.rotate_right(31u32) == 0u32) { panic("rotate_right #1046") }
    if !(0u32.checked_shl(31u32) == present(0u32)) { panic("checked_shl #1047") }
    if !(0u32.checked_shr(31u32) == present(0u32)) { panic("checked_shr #1048") }
    if !(0u32.wrapping_shl(31u32) == 0u32) { panic("wrapping_shl #1049") }
    if !(0u32.wrapping_shr(31u32) == 0u32) { panic("wrapping_shr #1050") }
    if !(0u32.overflowing_shl(31u32).0 == 0u32 && 0u32.overflowing_shl(31u32).1 == false) { panic("overflowing_shl #1051") }
    if !(0u32.overflowing_shr(31u32).0 == 0u32 && 0u32.overflowing_shr(31u32).1 == false) { panic("overflowing_shr #1052") }
    if !(0u32.unbounded_shl(31u32) == 0u32) { panic("unbounded_shl #1053") }
    if !(0u32.unbounded_shr(31u32) == 0u32) { panic("unbounded_shr #1054") }
    if !(0u32.strict_shl(31u32) == 0u32) { panic("strict_shl #1055") }
    if !(0u32.strict_shr(31u32) == 0u32) { panic("strict_shr #1056") }
    if !(unsafe { 0u32.unchecked_shl(31u32) } == 0u32) { panic("unchecked_shl #1057") }
    if !(unsafe { 0u32.unchecked_shr(31u32) } == 0u32) { panic("unchecked_shr #1058") }
    if !(0u32.rotate_left(32u32) == 0u32) { panic("rotate_left #1059") }
    if !(0u32.rotate_right(32u32) == 0u32) { panic("rotate_right #1060") }
    if !(missing(0u32.checked_shl(32u32))) { panic("checked_shl #1061") }
    if !(missing(0u32.checked_shr(32u32))) { panic("checked_shr #1062") }
    if !(0u32.wrapping_shl(32u32) == 0u32) { panic("wrapping_shl #1063") }
    if !(0u32.wrapping_shr(32u32) == 0u32) { panic("wrapping_shr #1064") }
    if !(0u32.overflowing_shl(32u32).0 == 0u32 && 0u32.overflowing_shl(32u32).1 == true) { panic("overflowing_shl #1065") }
    if !(0u32.overflowing_shr(32u32).0 == 0u32 && 0u32.overflowing_shr(32u32).1 == true) { panic("overflowing_shr #1066") }
    if !(0u32.unbounded_shl(32u32) == 0u32) { panic("unbounded_shl #1067") }
    if !(0u32.unbounded_shr(32u32) == 0u32) { panic("unbounded_shr #1068") }
    if !(0u32.rotate_left(37u32) == 0u32) { panic("rotate_left #1069") }
    if !(0u32.rotate_right(37u32) == 0u32) { panic("rotate_right #1070") }
    if !(missing(0u32.checked_shl(37u32))) { panic("checked_shl #1071") }
    if !(missing(0u32.checked_shr(37u32))) { panic("checked_shr #1072") }
    if !(0u32.wrapping_shl(37u32) == 0u32) { panic("wrapping_shl #1073") }
    if !(0u32.wrapping_shr(37u32) == 0u32) { panic("wrapping_shr #1074") }
    if !(0u32.overflowing_shl(37u32).0 == 0u32 && 0u32.overflowing_shl(37u32).1 == true) { panic("overflowing_shl #1075") }
    if !(0u32.overflowing_shr(37u32).0 == 0u32 && 0u32.overflowing_shr(37u32).1 == true) { panic("overflowing_shr #1076") }
    if !(0u32.unbounded_shl(37u32) == 0u32) { panic("unbounded_shl #1077") }
    if !(0u32.unbounded_shr(37u32) == 0u32) { panic("unbounded_shr #1078") }
    if !(0u32.checked_pow(0u32) == present(1u32)) { panic("checked_pow #1079") }
    if !(0u32.wrapping_pow(0u32) == 1u32) { panic("wrapping_pow #1080") }
}

fn group9() {
    if !(0u32.overflowing_pow(0u32).0 == 1u32 && 0u32.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1081") }
    if !(0u32.saturating_pow(0u32) == 1u32) { panic("saturating_pow #1082") }
    if !(0u32.pow(0u32) == 1u32) { panic("pow #1083") }
    if !(0u32.strict_pow(0u32) == 1u32) { panic("strict_pow #1084") }
    if !(0u32.checked_pow(1u32) == present(0u32)) { panic("checked_pow #1085") }
    if !(0u32.wrapping_pow(1u32) == 0u32) { panic("wrapping_pow #1086") }
    if !(0u32.overflowing_pow(1u32).0 == 0u32 && 0u32.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1087") }
    if !(0u32.saturating_pow(1u32) == 0u32) { panic("saturating_pow #1088") }
    if !(0u32.pow(1u32) == 0u32) { panic("pow #1089") }
    if !(0u32.strict_pow(1u32) == 0u32) { panic("strict_pow #1090") }
    if !(0u32.checked_pow(2u32) == present(0u32)) { panic("checked_pow #1091") }
    if !(0u32.wrapping_pow(2u32) == 0u32) { panic("wrapping_pow #1092") }
    if !(0u32.overflowing_pow(2u32).0 == 0u32 && 0u32.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1093") }
    if !(0u32.saturating_pow(2u32) == 0u32) { panic("saturating_pow #1094") }
    if !(0u32.pow(2u32) == 0u32) { panic("pow #1095") }
    if !(0u32.strict_pow(2u32) == 0u32) { panic("strict_pow #1096") }
    if !(0u32.checked_pow(3u32) == present(0u32)) { panic("checked_pow #1097") }
    if !(0u32.wrapping_pow(3u32) == 0u32) { panic("wrapping_pow #1098") }
    if !(0u32.overflowing_pow(3u32).0 == 0u32 && 0u32.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1099") }
    if !(0u32.saturating_pow(3u32) == 0u32) { panic("saturating_pow #1100") }
    if !(0u32.pow(3u32) == 0u32) { panic("pow #1101") }
    if !(0u32.strict_pow(3u32) == 0u32) { panic("strict_pow #1102") }
    if !(0u32.checked_pow(31u32) == present(0u32)) { panic("checked_pow #1103") }
    if !(0u32.wrapping_pow(31u32) == 0u32) { panic("wrapping_pow #1104") }
    if !(0u32.overflowing_pow(31u32).0 == 0u32 && 0u32.overflowing_pow(31u32).1 == false) { panic("overflowing_pow #1105") }
    if !(0u32.saturating_pow(31u32) == 0u32) { panic("saturating_pow #1106") }
    if !(0u32.pow(31u32) == 0u32) { panic("pow #1107") }
    if !(0u32.strict_pow(31u32) == 0u32) { panic("strict_pow #1108") }
    if !(0u32.checked_pow(32u32) == present(0u32)) { panic("checked_pow #1109") }
    if !(0u32.wrapping_pow(32u32) == 0u32) { panic("wrapping_pow #1110") }
    if !(0u32.overflowing_pow(32u32).0 == 0u32 && 0u32.overflowing_pow(32u32).1 == false) { panic("overflowing_pow #1111") }
    if !(0u32.saturating_pow(32u32) == 0u32) { panic("saturating_pow #1112") }
    if !(0u32.pow(32u32) == 0u32) { panic("pow #1113") }
    if !(0u32.strict_pow(32u32) == 0u32) { panic("strict_pow #1114") }
    if !(missing(0u32.checked_ilog2())) { panic("checked_ilog2 #1115") }
    if !(missing(0u32.checked_ilog10())) { panic("checked_ilog10 #1116") }
    if !(missing(0u32.checked_ilog(2u32))) { panic("checked_ilog #1117") }
    if !(0u32.isqrt() == 0u32) { panic("isqrt #1118") }
    if !(0u32.checked_isqrt() == present(0u32)) { panic("checked_isqrt #1119") }
    if !(0u32.is_power_of_two() == false) { panic("is_power_of_two #1120") }
    if !(0u32.checked_next_power_of_two() == present(1u32)) { panic("checked_next_power_of_two #1121") }
    if !(0u32.next_power_of_two() == 1u32) { panic("next_power_of_two #1122") }
    if !(0u32.div_ceil(1u32) == 0u32) { panic("div_ceil #1123") }
    if !(0u32.checked_next_multiple_of(1u32) == present(0u32)) { panic("checked_next_multiple_of #1124") }
    if !(0u32.next_multiple_of(1u32) == 0u32) { panic("next_multiple_of #1125") }
    if !(0u32.is_multiple_of(1u32) == true) { panic("is_multiple_of #1126") }
    if !(0u32.div_ceil(3u32) == 0u32) { panic("div_ceil #1127") }
    if !(0u32.checked_next_multiple_of(3u32) == present(0u32)) { panic("checked_next_multiple_of #1128") }
    if !(0u32.next_multiple_of(3u32) == 0u32) { panic("next_multiple_of #1129") }
    if !(0u32.is_multiple_of(3u32) == true) { panic("is_multiple_of #1130") }
    if !(0u32.div_ceil(7u32) == 0u32) { panic("div_ceil #1131") }
    if !(0u32.checked_next_multiple_of(7u32) == present(0u32)) { panic("checked_next_multiple_of #1132") }
    if !(0u32.next_multiple_of(7u32) == 0u32) { panic("next_multiple_of #1133") }
    if !(0u32.is_multiple_of(7u32) == true) { panic("is_multiple_of #1134") }
    if !(0u32.is_multiple_of(0u32) == true) { panic("is_multiple_of #1135") }
    if !(missing(0u32.checked_next_multiple_of(0u32))) { panic("checked_next_multiple_of #1136") }
    if !(missing(0u32.highest_one())) { panic("highest_one #1137") }
    if !(missing(0u32.lowest_one())) { panic("lowest_one #1138") }
    if !(0u32.isolate_highest_one() == 0u32) { panic("isolate_highest_one #1139") }
    if !(0u32.isolate_lowest_one() == 0u32) { panic("isolate_lowest_one #1140") }
    if !(0u32.bit_width() == 0u32) { panic("bit_width #1141") }
    if !(missing(1u32.checked_neg())) { panic("checked_neg #1142") }
    if !(1u32.wrapping_neg() == u32.MAX) { panic("wrapping_neg #1143") }
    if !(1u32.overflowing_neg().0 == u32.MAX && 1u32.overflowing_neg().1 == true) { panic("overflowing_neg #1144") }
    if !(1u32.cast_signed() == 1i32) { panic("cast_signed #1145") }
    if !(1u32.count_ones() == 1u32) { panic("count_ones #1146") }
    if !(1u32.count_zeros() == 31u32) { panic("count_zeros #1147") }
    if !(1u32.leading_zeros() == 31u32) { panic("leading_zeros #1148") }
    if !(1u32.trailing_zeros() == 0u32) { panic("trailing_zeros #1149") }
    if !(1u32.leading_ones() == 0u32) { panic("leading_ones #1150") }
    if !(1u32.trailing_ones() == 1u32) { panic("trailing_ones #1151") }
    if !(1u32.reverse_bits() == 2147483648u32) { panic("reverse_bits #1152") }
    if !(1u32.swap_bytes() == 16777216u32) { panic("swap_bytes #1153") }
    if !(1u32.to_be() == 16777216u32) { panic("to_be #1154") }
    if !(1u32.to_le() == 1u32) { panic("to_le #1155") }
    if !(u32.from_be(1u32) == 16777216u32) { panic("from_be #1156") }
    if !(u32.from_le(1u32) == 1u32) { panic("from_le #1157") }
    if !(1u32.to_le_bytes() == [1u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #1158") }
    if !(1u32.to_be_bytes() == [0u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #1159") }
    if !(1u32.to_ne_bytes() == [1u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #1160") }
    if !(u32.from_le_bytes([1u8, 0u8, 0u8, 0u8]) == 1u32) { panic("from_le_bytes #1161") }
    if !(u32.from_be_bytes([0u8, 0u8, 0u8, 1u8]) == 1u32) { panic("from_be_bytes #1162") }
    if !(u32.from_ne_bytes([1u8, 0u8, 0u8, 0u8]) == 1u32) { panic("from_ne_bytes #1163") }
    if !(1u32.rotate_left(0u32) == 1u32) { panic("rotate_left #1164") }
    if !(1u32.rotate_right(0u32) == 1u32) { panic("rotate_right #1165") }
    if !(1u32.checked_shl(0u32) == present(1u32)) { panic("checked_shl #1166") }
    if !(1u32.checked_shr(0u32) == present(1u32)) { panic("checked_shr #1167") }
    if !(1u32.wrapping_shl(0u32) == 1u32) { panic("wrapping_shl #1168") }
    if !(1u32.wrapping_shr(0u32) == 1u32) { panic("wrapping_shr #1169") }
    if !(1u32.overflowing_shl(0u32).0 == 1u32 && 1u32.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1170") }
    if !(1u32.overflowing_shr(0u32).0 == 1u32 && 1u32.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1171") }
    if !(1u32.unbounded_shl(0u32) == 1u32) { panic("unbounded_shl #1172") }
    if !(1u32.unbounded_shr(0u32) == 1u32) { panic("unbounded_shr #1173") }
    if !(1u32.strict_shl(0u32) == 1u32) { panic("strict_shl #1174") }
    if !(1u32.strict_shr(0u32) == 1u32) { panic("strict_shr #1175") }
    if !(unsafe { 1u32.unchecked_shl(0u32) } == 1u32) { panic("unchecked_shl #1176") }
    if !(unsafe { 1u32.unchecked_shr(0u32) } == 1u32) { panic("unchecked_shr #1177") }
    if !(1u32.rotate_left(1u32) == 2u32) { panic("rotate_left #1178") }
    if !(1u32.rotate_right(1u32) == 2147483648u32) { panic("rotate_right #1179") }
    if !(1u32.checked_shl(1u32) == present(2u32)) { panic("checked_shl #1180") }
    if !(1u32.checked_shr(1u32) == present(0u32)) { panic("checked_shr #1181") }
    if !(1u32.wrapping_shl(1u32) == 2u32) { panic("wrapping_shl #1182") }
    if !(1u32.wrapping_shr(1u32) == 0u32) { panic("wrapping_shr #1183") }
    if !(1u32.overflowing_shl(1u32).0 == 2u32 && 1u32.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1184") }
    if !(1u32.overflowing_shr(1u32).0 == 0u32 && 1u32.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1185") }
    if !(1u32.unbounded_shl(1u32) == 2u32) { panic("unbounded_shl #1186") }
    if !(1u32.unbounded_shr(1u32) == 0u32) { panic("unbounded_shr #1187") }
    if !(1u32.strict_shl(1u32) == 2u32) { panic("strict_shl #1188") }
    if !(1u32.strict_shr(1u32) == 0u32) { panic("strict_shr #1189") }
    if !(unsafe { 1u32.unchecked_shl(1u32) } == 2u32) { panic("unchecked_shl #1190") }
    if !(unsafe { 1u32.unchecked_shr(1u32) } == 0u32) { panic("unchecked_shr #1191") }
    if !(1u32.rotate_left(3u32) == 8u32) { panic("rotate_left #1192") }
    if !(1u32.rotate_right(3u32) == 536870912u32) { panic("rotate_right #1193") }
    if !(1u32.checked_shl(3u32) == present(8u32)) { panic("checked_shl #1194") }
    if !(1u32.checked_shr(3u32) == present(0u32)) { panic("checked_shr #1195") }
    if !(1u32.wrapping_shl(3u32) == 8u32) { panic("wrapping_shl #1196") }
    if !(1u32.wrapping_shr(3u32) == 0u32) { panic("wrapping_shr #1197") }
    if !(1u32.overflowing_shl(3u32).0 == 8u32 && 1u32.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1198") }
    if !(1u32.overflowing_shr(3u32).0 == 0u32 && 1u32.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1199") }
    if !(1u32.unbounded_shl(3u32) == 8u32) { panic("unbounded_shl #1200") }
}

fn group10() {
    if !(1u32.unbounded_shr(3u32) == 0u32) { panic("unbounded_shr #1201") }
    if !(1u32.strict_shl(3u32) == 8u32) { panic("strict_shl #1202") }
    if !(1u32.strict_shr(3u32) == 0u32) { panic("strict_shr #1203") }
    if !(unsafe { 1u32.unchecked_shl(3u32) } == 8u32) { panic("unchecked_shl #1204") }
    if !(unsafe { 1u32.unchecked_shr(3u32) } == 0u32) { panic("unchecked_shr #1205") }
    if !(1u32.rotate_left(31u32) == 2147483648u32) { panic("rotate_left #1206") }
    if !(1u32.rotate_right(31u32) == 2u32) { panic("rotate_right #1207") }
    if !(1u32.checked_shl(31u32) == present(2147483648u32)) { panic("checked_shl #1208") }
    if !(1u32.checked_shr(31u32) == present(0u32)) { panic("checked_shr #1209") }
    if !(1u32.wrapping_shl(31u32) == 2147483648u32) { panic("wrapping_shl #1210") }
    if !(1u32.wrapping_shr(31u32) == 0u32) { panic("wrapping_shr #1211") }
    if !(1u32.overflowing_shl(31u32).0 == 2147483648u32 && 1u32.overflowing_shl(31u32).1 == false) { panic("overflowing_shl #1212") }
    if !(1u32.overflowing_shr(31u32).0 == 0u32 && 1u32.overflowing_shr(31u32).1 == false) { panic("overflowing_shr #1213") }
    if !(1u32.unbounded_shl(31u32) == 2147483648u32) { panic("unbounded_shl #1214") }
    if !(1u32.unbounded_shr(31u32) == 0u32) { panic("unbounded_shr #1215") }
    if !(1u32.strict_shl(31u32) == 2147483648u32) { panic("strict_shl #1216") }
    if !(1u32.strict_shr(31u32) == 0u32) { panic("strict_shr #1217") }
    if !(unsafe { 1u32.unchecked_shl(31u32) } == 2147483648u32) { panic("unchecked_shl #1218") }
    if !(unsafe { 1u32.unchecked_shr(31u32) } == 0u32) { panic("unchecked_shr #1219") }
    if !(1u32.rotate_left(32u32) == 1u32) { panic("rotate_left #1220") }
    if !(1u32.rotate_right(32u32) == 1u32) { panic("rotate_right #1221") }
    if !(missing(1u32.checked_shl(32u32))) { panic("checked_shl #1222") }
    if !(missing(1u32.checked_shr(32u32))) { panic("checked_shr #1223") }
    if !(1u32.wrapping_shl(32u32) == 1u32) { panic("wrapping_shl #1224") }
    if !(1u32.wrapping_shr(32u32) == 1u32) { panic("wrapping_shr #1225") }
    if !(1u32.overflowing_shl(32u32).0 == 1u32 && 1u32.overflowing_shl(32u32).1 == true) { panic("overflowing_shl #1226") }
    if !(1u32.overflowing_shr(32u32).0 == 1u32 && 1u32.overflowing_shr(32u32).1 == true) { panic("overflowing_shr #1227") }
    if !(1u32.unbounded_shl(32u32) == 0u32) { panic("unbounded_shl #1228") }
    if !(1u32.unbounded_shr(32u32) == 0u32) { panic("unbounded_shr #1229") }
    if !(1u32.rotate_left(37u32) == 32u32) { panic("rotate_left #1230") }
    if !(1u32.rotate_right(37u32) == 134217728u32) { panic("rotate_right #1231") }
    if !(missing(1u32.checked_shl(37u32))) { panic("checked_shl #1232") }
    if !(missing(1u32.checked_shr(37u32))) { panic("checked_shr #1233") }
    if !(1u32.wrapping_shl(37u32) == 32u32) { panic("wrapping_shl #1234") }
    if !(1u32.wrapping_shr(37u32) == 0u32) { panic("wrapping_shr #1235") }
    if !(1u32.overflowing_shl(37u32).0 == 32u32 && 1u32.overflowing_shl(37u32).1 == true) { panic("overflowing_shl #1236") }
    if !(1u32.overflowing_shr(37u32).0 == 0u32 && 1u32.overflowing_shr(37u32).1 == true) { panic("overflowing_shr #1237") }
    if !(1u32.unbounded_shl(37u32) == 0u32) { panic("unbounded_shl #1238") }
    if !(1u32.unbounded_shr(37u32) == 0u32) { panic("unbounded_shr #1239") }
    if !(1u32.checked_pow(0u32) == present(1u32)) { panic("checked_pow #1240") }
    if !(1u32.wrapping_pow(0u32) == 1u32) { panic("wrapping_pow #1241") }
    if !(1u32.overflowing_pow(0u32).0 == 1u32 && 1u32.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1242") }
    if !(1u32.saturating_pow(0u32) == 1u32) { panic("saturating_pow #1243") }
    if !(1u32.pow(0u32) == 1u32) { panic("pow #1244") }
    if !(1u32.strict_pow(0u32) == 1u32) { panic("strict_pow #1245") }
    if !(1u32.checked_pow(1u32) == present(1u32)) { panic("checked_pow #1246") }
    if !(1u32.wrapping_pow(1u32) == 1u32) { panic("wrapping_pow #1247") }
    if !(1u32.overflowing_pow(1u32).0 == 1u32 && 1u32.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1248") }
    if !(1u32.saturating_pow(1u32) == 1u32) { panic("saturating_pow #1249") }
    if !(1u32.pow(1u32) == 1u32) { panic("pow #1250") }
    if !(1u32.strict_pow(1u32) == 1u32) { panic("strict_pow #1251") }
    if !(1u32.checked_pow(2u32) == present(1u32)) { panic("checked_pow #1252") }
    if !(1u32.wrapping_pow(2u32) == 1u32) { panic("wrapping_pow #1253") }
    if !(1u32.overflowing_pow(2u32).0 == 1u32 && 1u32.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1254") }
    if !(1u32.saturating_pow(2u32) == 1u32) { panic("saturating_pow #1255") }
    if !(1u32.pow(2u32) == 1u32) { panic("pow #1256") }
    if !(1u32.strict_pow(2u32) == 1u32) { panic("strict_pow #1257") }
    if !(1u32.checked_pow(3u32) == present(1u32)) { panic("checked_pow #1258") }
    if !(1u32.wrapping_pow(3u32) == 1u32) { panic("wrapping_pow #1259") }
    if !(1u32.overflowing_pow(3u32).0 == 1u32 && 1u32.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1260") }
    if !(1u32.saturating_pow(3u32) == 1u32) { panic("saturating_pow #1261") }
    if !(1u32.pow(3u32) == 1u32) { panic("pow #1262") }
    if !(1u32.strict_pow(3u32) == 1u32) { panic("strict_pow #1263") }
    if !(1u32.checked_pow(31u32) == present(1u32)) { panic("checked_pow #1264") }
    if !(1u32.wrapping_pow(31u32) == 1u32) { panic("wrapping_pow #1265") }
    if !(1u32.overflowing_pow(31u32).0 == 1u32 && 1u32.overflowing_pow(31u32).1 == false) { panic("overflowing_pow #1266") }
    if !(1u32.saturating_pow(31u32) == 1u32) { panic("saturating_pow #1267") }
    if !(1u32.pow(31u32) == 1u32) { panic("pow #1268") }
    if !(1u32.strict_pow(31u32) == 1u32) { panic("strict_pow #1269") }
    if !(1u32.checked_pow(32u32) == present(1u32)) { panic("checked_pow #1270") }
    if !(1u32.wrapping_pow(32u32) == 1u32) { panic("wrapping_pow #1271") }
    if !(1u32.overflowing_pow(32u32).0 == 1u32 && 1u32.overflowing_pow(32u32).1 == false) { panic("overflowing_pow #1272") }
    if !(1u32.saturating_pow(32u32) == 1u32) { panic("saturating_pow #1273") }
    if !(1u32.pow(32u32) == 1u32) { panic("pow #1274") }
    if !(1u32.strict_pow(32u32) == 1u32) { panic("strict_pow #1275") }
    if !(1u32.ilog2() == 0u32) { panic("ilog2 #1276") }
    if !(1u32.ilog10() == 0u32) { panic("ilog10 #1277") }
    if !(1u32.checked_ilog2() == present(0u32)) { panic("checked_ilog2 #1278") }
    if !(1u32.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1279") }
    if !(1u32.ilog(2u32) == 0u32) { panic("ilog #1280") }
    if !(1u32.checked_ilog(2u32) == present(0u32)) { panic("checked_ilog #1281") }
    if !(1u32.ilog(3u32) == 0u32) { panic("ilog #1282") }
    if !(1u32.checked_ilog(3u32) == present(0u32)) { panic("checked_ilog #1283") }
    if !(1u32.ilog(7u32) == 0u32) { panic("ilog #1284") }
    if !(1u32.checked_ilog(7u32) == present(0u32)) { panic("checked_ilog #1285") }
    if !(missing(1u32.checked_ilog(1u32))) { panic("checked_ilog #1286") }
    if !(1u32.isqrt() == 1u32) { panic("isqrt #1287") }
    if !(1u32.checked_isqrt() == present(1u32)) { panic("checked_isqrt #1288") }
    if !(1u32.is_power_of_two() == true) { panic("is_power_of_two #1289") }
    if !(1u32.checked_next_power_of_two() == present(1u32)) { panic("checked_next_power_of_two #1290") }
    if !(1u32.next_power_of_two() == 1u32) { panic("next_power_of_two #1291") }
    if !(1u32.div_ceil(1u32) == 1u32) { panic("div_ceil #1292") }
    if !(1u32.checked_next_multiple_of(1u32) == present(1u32)) { panic("checked_next_multiple_of #1293") }
    if !(1u32.next_multiple_of(1u32) == 1u32) { panic("next_multiple_of #1294") }
    if !(1u32.is_multiple_of(1u32) == true) { panic("is_multiple_of #1295") }
    if !(1u32.div_ceil(3u32) == 1u32) { panic("div_ceil #1296") }
    if !(1u32.checked_next_multiple_of(3u32) == present(3u32)) { panic("checked_next_multiple_of #1297") }
    if !(1u32.next_multiple_of(3u32) == 3u32) { panic("next_multiple_of #1298") }
    if !(1u32.is_multiple_of(3u32) == false) { panic("is_multiple_of #1299") }
    if !(1u32.div_ceil(7u32) == 1u32) { panic("div_ceil #1300") }
    if !(1u32.checked_next_multiple_of(7u32) == present(7u32)) { panic("checked_next_multiple_of #1301") }
    if !(1u32.next_multiple_of(7u32) == 7u32) { panic("next_multiple_of #1302") }
    if !(1u32.is_multiple_of(7u32) == false) { panic("is_multiple_of #1303") }
    if !(1u32.is_multiple_of(0u32) == false) { panic("is_multiple_of #1304") }
    if !(missing(1u32.checked_next_multiple_of(0u32))) { panic("checked_next_multiple_of #1305") }
    if !(1u32.highest_one() == present(0u32)) { panic("highest_one #1306") }
    if !(1u32.lowest_one() == present(0u32)) { panic("lowest_one #1307") }
    if !(1u32.isolate_highest_one() == 1u32) { panic("isolate_highest_one #1308") }
    if !(1u32.isolate_lowest_one() == 1u32) { panic("isolate_lowest_one #1309") }
    if !(1u32.bit_width() == 1u32) { panic("bit_width #1310") }
    if !(u32.MAX.carrying_add(1u32, false).0 == 0u32 && u32.MAX.carrying_add(1u32, false).1 == true) { panic("carrying_add #1311") }
    if !(u32.MAX.borrowing_sub(1u32, false).0 == 4294967294u32 && u32.MAX.borrowing_sub(1u32, false).1 == false) { panic("borrowing_sub #1312") }
    if !(u32.MAX.carrying_add(1u32, true).0 == 1u32 && u32.MAX.carrying_add(1u32, true).1 == true) { panic("carrying_add #1313") }
    if !(u32.MAX.borrowing_sub(1u32, true).0 == 4294967293u32 && u32.MAX.borrowing_sub(1u32, true).1 == false) { panic("borrowing_sub #1314") }
    if !(u32.MAX.carrying_mul(1u32, 0u32).0 == u32.MAX && u32.MAX.carrying_mul(1u32, 0u32).1 == 0u32) { panic("carrying_mul #1315") }
    if !(u32.MAX.carrying_mul_add(1u32, 0u32, 0u32).0 == u32.MAX && u32.MAX.carrying_mul_add(1u32, 0u32, 0u32).1 == 0u32) { panic("carrying_mul_add #1316") }
    if !(u32.MAX.carrying_mul(1u32, u32.MAX).0 == 4294967294u32 && u32.MAX.carrying_mul(1u32, u32.MAX).1 == 1u32) { panic("carrying_mul #1317") }
    if !(u32.MAX.carrying_mul_add(1u32, u32.MAX, 0u32).0 == 4294967294u32 && u32.MAX.carrying_mul_add(1u32, u32.MAX, 0u32).1 == 1u32) { panic("carrying_mul_add #1318") }
    if !(u32.MAX.carrying_mul(1u32, u32.MAX).0 == 4294967294u32 && u32.MAX.carrying_mul(1u32, u32.MAX).1 == 1u32) { panic("carrying_mul #1319") }
    if !(u32.MAX.carrying_mul_add(1u32, u32.MAX, u32.MAX).0 == 4294967293u32 && u32.MAX.carrying_mul_add(1u32, u32.MAX, u32.MAX).1 == 2u32) { panic("carrying_mul_add #1320") }
}

fn group11() {
    if !(u32.MAX.carrying_mul(1u32, 7u32).0 == 6u32 && u32.MAX.carrying_mul(1u32, 7u32).1 == 1u32) { panic("carrying_mul #1321") }
    if !(u32.MAX.carrying_mul_add(1u32, 7u32, 3u32).0 == 9u32 && u32.MAX.carrying_mul_add(1u32, 7u32, 3u32).1 == 1u32) { panic("carrying_mul_add #1322") }
    if !(missing(u32.MAX.checked_signed_diff(1u32))) { panic("checked_signed_diff #1323") }
    if !(0u32.carrying_add(1u32, false).0 == 1u32 && 0u32.carrying_add(1u32, false).1 == false) { panic("carrying_add #1324") }
    if !(0u32.borrowing_sub(1u32, false).0 == u32.MAX && 0u32.borrowing_sub(1u32, false).1 == true) { panic("borrowing_sub #1325") }
    if !(0u32.carrying_add(1u32, true).0 == 2u32 && 0u32.carrying_add(1u32, true).1 == false) { panic("carrying_add #1326") }
    if !(0u32.borrowing_sub(1u32, true).0 == 4294967294u32 && 0u32.borrowing_sub(1u32, true).1 == true) { panic("borrowing_sub #1327") }
    if !(0u32.carrying_mul(1u32, 0u32).0 == 0u32 && 0u32.carrying_mul(1u32, 0u32).1 == 0u32) { panic("carrying_mul #1328") }
    if !(0u32.carrying_mul_add(1u32, 0u32, 0u32).0 == 0u32 && 0u32.carrying_mul_add(1u32, 0u32, 0u32).1 == 0u32) { panic("carrying_mul_add #1329") }
    if !(0u32.carrying_mul(1u32, u32.MAX).0 == u32.MAX && 0u32.carrying_mul(1u32, u32.MAX).1 == 0u32) { panic("carrying_mul #1330") }
    if !(0u32.carrying_mul_add(1u32, u32.MAX, 0u32).0 == u32.MAX && 0u32.carrying_mul_add(1u32, u32.MAX, 0u32).1 == 0u32) { panic("carrying_mul_add #1331") }
    if !(0u32.carrying_mul(1u32, u32.MAX).0 == u32.MAX && 0u32.carrying_mul(1u32, u32.MAX).1 == 0u32) { panic("carrying_mul #1332") }
    if !(0u32.carrying_mul_add(1u32, u32.MAX, u32.MAX).0 == 4294967294u32 && 0u32.carrying_mul_add(1u32, u32.MAX, u32.MAX).1 == 1u32) { panic("carrying_mul_add #1333") }
    if !(0u32.carrying_mul(1u32, 7u32).0 == 7u32 && 0u32.carrying_mul(1u32, 7u32).1 == 0u32) { panic("carrying_mul #1334") }
    if !(0u32.carrying_mul_add(1u32, 7u32, 3u32).0 == 10u32 && 0u32.carrying_mul_add(1u32, 7u32, 3u32).1 == 0u32) { panic("carrying_mul_add #1335") }
    if !(0u32.checked_signed_diff(1u32) == present((-1i32))) { panic("checked_signed_diff #1336") }
    if !(1000u32.carrying_add(7u32, false).0 == 1007u32 && 1000u32.carrying_add(7u32, false).1 == false) { panic("carrying_add #1337") }
    if !(1000u32.borrowing_sub(7u32, false).0 == 993u32 && 1000u32.borrowing_sub(7u32, false).1 == false) { panic("borrowing_sub #1338") }
    if !(1000u32.carrying_add(7u32, true).0 == 1008u32 && 1000u32.carrying_add(7u32, true).1 == false) { panic("carrying_add #1339") }
    if !(1000u32.borrowing_sub(7u32, true).0 == 992u32 && 1000u32.borrowing_sub(7u32, true).1 == false) { panic("borrowing_sub #1340") }
    if !(1000u32.carrying_mul(7u32, 0u32).0 == 7000u32 && 1000u32.carrying_mul(7u32, 0u32).1 == 0u32) { panic("carrying_mul #1341") }
    if !(1000u32.carrying_mul_add(7u32, 0u32, 0u32).0 == 7000u32 && 1000u32.carrying_mul_add(7u32, 0u32, 0u32).1 == 0u32) { panic("carrying_mul_add #1342") }
    if !(1000u32.carrying_mul(7u32, u32.MAX).0 == 6999u32 && 1000u32.carrying_mul(7u32, u32.MAX).1 == 1u32) { panic("carrying_mul #1343") }
    if !(1000u32.carrying_mul_add(7u32, u32.MAX, 0u32).0 == 6999u32 && 1000u32.carrying_mul_add(7u32, u32.MAX, 0u32).1 == 1u32) { panic("carrying_mul_add #1344") }
    if !(1000u32.carrying_mul(7u32, u32.MAX).0 == 6999u32 && 1000u32.carrying_mul(7u32, u32.MAX).1 == 1u32) { panic("carrying_mul #1345") }
    if !(1000u32.carrying_mul_add(7u32, u32.MAX, u32.MAX).0 == 6998u32 && 1000u32.carrying_mul_add(7u32, u32.MAX, u32.MAX).1 == 2u32) { panic("carrying_mul_add #1346") }
    if !(1000u32.carrying_mul(7u32, 7u32).0 == 7007u32 && 1000u32.carrying_mul(7u32, 7u32).1 == 0u32) { panic("carrying_mul #1347") }
    if !(1000u32.carrying_mul_add(7u32, 7u32, 3u32).0 == 7010u32 && 1000u32.carrying_mul_add(7u32, 7u32, 3u32).1 == 0u32) { panic("carrying_mul_add #1348") }
    if !(1000u32.checked_signed_diff(7u32) == present(993i32)) { panic("checked_signed_diff #1349") }
    if !(7u32.carrying_add(1000u32, false).0 == 1007u32 && 7u32.carrying_add(1000u32, false).1 == false) { panic("carrying_add #1350") }
    if !(7u32.borrowing_sub(1000u32, false).0 == 4294966303u32 && 7u32.borrowing_sub(1000u32, false).1 == true) { panic("borrowing_sub #1351") }
    if !(7u32.carrying_add(1000u32, true).0 == 1008u32 && 7u32.carrying_add(1000u32, true).1 == false) { panic("carrying_add #1352") }
    if !(7u32.borrowing_sub(1000u32, true).0 == 4294966302u32 && 7u32.borrowing_sub(1000u32, true).1 == true) { panic("borrowing_sub #1353") }
    if !(7u32.carrying_mul(1000u32, 0u32).0 == 7000u32 && 7u32.carrying_mul(1000u32, 0u32).1 == 0u32) { panic("carrying_mul #1354") }
    if !(7u32.carrying_mul_add(1000u32, 0u32, 0u32).0 == 7000u32 && 7u32.carrying_mul_add(1000u32, 0u32, 0u32).1 == 0u32) { panic("carrying_mul_add #1355") }
    if !(7u32.carrying_mul(1000u32, u32.MAX).0 == 6999u32 && 7u32.carrying_mul(1000u32, u32.MAX).1 == 1u32) { panic("carrying_mul #1356") }
    if !(7u32.carrying_mul_add(1000u32, u32.MAX, 0u32).0 == 6999u32 && 7u32.carrying_mul_add(1000u32, u32.MAX, 0u32).1 == 1u32) { panic("carrying_mul_add #1357") }
    if !(7u32.carrying_mul(1000u32, u32.MAX).0 == 6999u32 && 7u32.carrying_mul(1000u32, u32.MAX).1 == 1u32) { panic("carrying_mul #1358") }
    if !(7u32.carrying_mul_add(1000u32, u32.MAX, u32.MAX).0 == 6998u32 && 7u32.carrying_mul_add(1000u32, u32.MAX, u32.MAX).1 == 2u32) { panic("carrying_mul_add #1359") }
    if !(7u32.carrying_mul(1000u32, 7u32).0 == 7007u32 && 7u32.carrying_mul(1000u32, 7u32).1 == 0u32) { panic("carrying_mul #1360") }
    if !(7u32.carrying_mul_add(1000u32, 7u32, 3u32).0 == 7010u32 && 7u32.carrying_mul_add(1000u32, 7u32, 3u32).1 == 0u32) { panic("carrying_mul_add #1361") }
    if !(7u32.checked_signed_diff(1000u32) == present((-993i32))) { panic("checked_signed_diff #1362") }
    if !(u32.MAX.carrying_add(2u32, false).0 == 1u32 && u32.MAX.carrying_add(2u32, false).1 == true) { panic("carrying_add #1363") }
    if !(u32.MAX.borrowing_sub(2u32, false).0 == 4294967293u32 && u32.MAX.borrowing_sub(2u32, false).1 == false) { panic("borrowing_sub #1364") }
    if !(u32.MAX.carrying_add(2u32, true).0 == 2u32 && u32.MAX.carrying_add(2u32, true).1 == true) { panic("carrying_add #1365") }
    if !(u32.MAX.borrowing_sub(2u32, true).0 == 4294967292u32 && u32.MAX.borrowing_sub(2u32, true).1 == false) { panic("borrowing_sub #1366") }
    if !(u32.MAX.carrying_mul(2u32, 0u32).0 == 4294967294u32 && u32.MAX.carrying_mul(2u32, 0u32).1 == 1u32) { panic("carrying_mul #1367") }
    if !(u32.MAX.carrying_mul_add(2u32, 0u32, 0u32).0 == 4294967294u32 && u32.MAX.carrying_mul_add(2u32, 0u32, 0u32).1 == 1u32) { panic("carrying_mul_add #1368") }
    if !(u32.MAX.carrying_mul(2u32, u32.MAX).0 == 4294967293u32 && u32.MAX.carrying_mul(2u32, u32.MAX).1 == 2u32) { panic("carrying_mul #1369") }
    if !(u32.MAX.carrying_mul_add(2u32, u32.MAX, 0u32).0 == 4294967293u32 && u32.MAX.carrying_mul_add(2u32, u32.MAX, 0u32).1 == 2u32) { panic("carrying_mul_add #1370") }
    if !(u32.MAX.carrying_mul(2u32, u32.MAX).0 == 4294967293u32 && u32.MAX.carrying_mul(2u32, u32.MAX).1 == 2u32) { panic("carrying_mul #1371") }
    if !(u32.MAX.carrying_mul_add(2u32, u32.MAX, u32.MAX).0 == 4294967292u32 && u32.MAX.carrying_mul_add(2u32, u32.MAX, u32.MAX).1 == 3u32) { panic("carrying_mul_add #1372") }
    if !(u32.MAX.carrying_mul(2u32, 7u32).0 == 5u32 && u32.MAX.carrying_mul(2u32, 7u32).1 == 2u32) { panic("carrying_mul #1373") }
    if !(u32.MAX.carrying_mul_add(2u32, 7u32, 3u32).0 == 8u32 && u32.MAX.carrying_mul_add(2u32, 7u32, 3u32).1 == 2u32) { panic("carrying_mul_add #1374") }
    if !(missing(u32.MAX.checked_signed_diff(2u32))) { panic("checked_signed_diff #1375") }
    if !(0u32.carrying_add(0u32, false).0 == 0u32 && 0u32.carrying_add(0u32, false).1 == false) { panic("carrying_add #1376") }
    if !(0u32.borrowing_sub(0u32, false).0 == 0u32 && 0u32.borrowing_sub(0u32, false).1 == false) { panic("borrowing_sub #1377") }
    if !(0u32.carrying_add(0u32, true).0 == 1u32 && 0u32.carrying_add(0u32, true).1 == false) { panic("carrying_add #1378") }
    if !(0u32.borrowing_sub(0u32, true).0 == u32.MAX && 0u32.borrowing_sub(0u32, true).1 == true) { panic("borrowing_sub #1379") }
    if !(0u32.carrying_mul(0u32, 0u32).0 == 0u32 && 0u32.carrying_mul(0u32, 0u32).1 == 0u32) { panic("carrying_mul #1380") }
    if !(0u32.carrying_mul_add(0u32, 0u32, 0u32).0 == 0u32 && 0u32.carrying_mul_add(0u32, 0u32, 0u32).1 == 0u32) { panic("carrying_mul_add #1381") }
    if !(0u32.carrying_mul(0u32, u32.MAX).0 == u32.MAX && 0u32.carrying_mul(0u32, u32.MAX).1 == 0u32) { panic("carrying_mul #1382") }
    if !(0u32.carrying_mul_add(0u32, u32.MAX, 0u32).0 == u32.MAX && 0u32.carrying_mul_add(0u32, u32.MAX, 0u32).1 == 0u32) { panic("carrying_mul_add #1383") }
    if !(0u32.carrying_mul(0u32, u32.MAX).0 == u32.MAX && 0u32.carrying_mul(0u32, u32.MAX).1 == 0u32) { panic("carrying_mul #1384") }
    if !(0u32.carrying_mul_add(0u32, u32.MAX, u32.MAX).0 == 4294967294u32 && 0u32.carrying_mul_add(0u32, u32.MAX, u32.MAX).1 == 1u32) { panic("carrying_mul_add #1385") }
    if !(0u32.carrying_mul(0u32, 7u32).0 == 7u32 && 0u32.carrying_mul(0u32, 7u32).1 == 0u32) { panic("carrying_mul #1386") }
    if !(0u32.carrying_mul_add(0u32, 7u32, 3u32).0 == 10u32 && 0u32.carrying_mul_add(0u32, 7u32, 3u32).1 == 0u32) { panic("carrying_mul_add #1387") }
    if !(0u32.checked_signed_diff(0u32) == present(0i32)) { panic("checked_signed_diff #1388") }
    if !(u32.MAX.carrying_add(u32.MAX, false).0 == 4294967294u32 && u32.MAX.carrying_add(u32.MAX, false).1 == true) { panic("carrying_add #1389") }
    if !(u32.MAX.borrowing_sub(u32.MAX, false).0 == 0u32 && u32.MAX.borrowing_sub(u32.MAX, false).1 == false) { panic("borrowing_sub #1390") }
    if !(u32.MAX.carrying_add(u32.MAX, true).0 == u32.MAX && u32.MAX.carrying_add(u32.MAX, true).1 == true) { panic("carrying_add #1391") }
    if !(u32.MAX.borrowing_sub(u32.MAX, true).0 == u32.MAX && u32.MAX.borrowing_sub(u32.MAX, true).1 == true) { panic("borrowing_sub #1392") }
    if !(u32.MAX.carrying_mul(u32.MAX, 0u32).0 == 1u32 && u32.MAX.carrying_mul(u32.MAX, 0u32).1 == 4294967294u32) { panic("carrying_mul #1393") }
    if !(u32.MAX.carrying_mul_add(u32.MAX, 0u32, 0u32).0 == 1u32 && u32.MAX.carrying_mul_add(u32.MAX, 0u32, 0u32).1 == 4294967294u32) { panic("carrying_mul_add #1394") }
    if !(u32.MAX.carrying_mul(u32.MAX, u32.MAX).0 == 0u32 && u32.MAX.carrying_mul(u32.MAX, u32.MAX).1 == u32.MAX) { panic("carrying_mul #1395") }
    if !(u32.MAX.carrying_mul_add(u32.MAX, u32.MAX, 0u32).0 == 0u32 && u32.MAX.carrying_mul_add(u32.MAX, u32.MAX, 0u32).1 == u32.MAX) { panic("carrying_mul_add #1396") }
    if !(u32.MAX.carrying_mul(u32.MAX, u32.MAX).0 == 0u32 && u32.MAX.carrying_mul(u32.MAX, u32.MAX).1 == u32.MAX) { panic("carrying_mul #1397") }
    if !(u32.MAX.carrying_mul_add(u32.MAX, u32.MAX, u32.MAX).0 == u32.MAX && u32.MAX.carrying_mul_add(u32.MAX, u32.MAX, u32.MAX).1 == u32.MAX) { panic("carrying_mul_add #1398") }
    if !(u32.MAX.carrying_mul(u32.MAX, 7u32).0 == 8u32 && u32.MAX.carrying_mul(u32.MAX, 7u32).1 == 4294967294u32) { panic("carrying_mul #1399") }
    if !(u32.MAX.carrying_mul_add(u32.MAX, 7u32, 3u32).0 == 11u32 && u32.MAX.carrying_mul_add(u32.MAX, 7u32, 3u32).1 == 4294967294u32) { panic("carrying_mul_add #1400") }
    if !(u32.MAX.checked_signed_diff(u32.MAX) == present(0i32)) { panic("checked_signed_diff #1401") }
    if !(u32.MAX.carrying_add(4294967294u32, false).0 == 4294967293u32 && u32.MAX.carrying_add(4294967294u32, false).1 == true) { panic("carrying_add #1402") }
    if !(u32.MAX.borrowing_sub(4294967294u32, false).0 == 1u32 && u32.MAX.borrowing_sub(4294967294u32, false).1 == false) { panic("borrowing_sub #1403") }
    if !(u32.MAX.carrying_add(4294967294u32, true).0 == 4294967294u32 && u32.MAX.carrying_add(4294967294u32, true).1 == true) { panic("carrying_add #1404") }
    if !(u32.MAX.borrowing_sub(4294967294u32, true).0 == 0u32 && u32.MAX.borrowing_sub(4294967294u32, true).1 == false) { panic("borrowing_sub #1405") }
    if !(u32.MAX.carrying_mul(4294967294u32, 0u32).0 == 2u32 && u32.MAX.carrying_mul(4294967294u32, 0u32).1 == 4294967293u32) { panic("carrying_mul #1406") }
    if !(u32.MAX.carrying_mul_add(4294967294u32, 0u32, 0u32).0 == 2u32 && u32.MAX.carrying_mul_add(4294967294u32, 0u32, 0u32).1 == 4294967293u32) { panic("carrying_mul_add #1407") }
    if !(u32.MAX.carrying_mul(4294967294u32, u32.MAX).0 == 1u32 && u32.MAX.carrying_mul(4294967294u32, u32.MAX).1 == 4294967294u32) { panic("carrying_mul #1408") }
    if !(u32.MAX.carrying_mul_add(4294967294u32, u32.MAX, 0u32).0 == 1u32 && u32.MAX.carrying_mul_add(4294967294u32, u32.MAX, 0u32).1 == 4294967294u32) { panic("carrying_mul_add #1409") }
    if !(u32.MAX.carrying_mul(4294967294u32, u32.MAX).0 == 1u32 && u32.MAX.carrying_mul(4294967294u32, u32.MAX).1 == 4294967294u32) { panic("carrying_mul #1410") }
    if !(u32.MAX.carrying_mul_add(4294967294u32, u32.MAX, u32.MAX).0 == 0u32 && u32.MAX.carrying_mul_add(4294967294u32, u32.MAX, u32.MAX).1 == u32.MAX) { panic("carrying_mul_add #1411") }
    if !(u32.MAX.carrying_mul(4294967294u32, 7u32).0 == 9u32 && u32.MAX.carrying_mul(4294967294u32, 7u32).1 == 4294967293u32) { panic("carrying_mul #1412") }
    if !(u32.MAX.carrying_mul_add(4294967294u32, 7u32, 3u32).0 == 12u32 && u32.MAX.carrying_mul_add(4294967294u32, 7u32, 3u32).1 == 4294967293u32) { panic("carrying_mul_add #1413") }
    if !(u32.MAX.checked_signed_diff(4294967294u32) == present(1i32)) { panic("checked_signed_diff #1414") }
    if !(parsed(capture num.from_str_radix<u32>("4294967295", 10u32)) == present(u32.MAX)) { panic("from_str_radix #1415") }
    if !(parsed(capture num.from_str_radix<u32>("ffffffff", 16u32)) == present(u32.MAX)) { panic("from_str_radix #1416") }
    if !(parsed(capture num.from_str_radix<u32>("11111111111111111111111111111111", 2u32)) == present(u32.MAX)) { panic("from_str_radix #1417") }
    if !(parsed(capture num.from_str_radix<u32>("1z141z3", 36u32)) == present(u32.MAX)) { panic("from_str_radix #1418") }
    if !(parsed(capture num.from_str_radix<u32>("FFFFFFFF", 16u32)) == present(u32.MAX)) { panic("from_str_radix #1419") }
    if !(parsed(capture num.from_str_radix<u32>("0", 10u32)) == present(0u32)) { panic("from_str_radix #1420") }
    if !(parsed(capture num.from_str_radix<u32>("0", 16u32)) == present(0u32)) { panic("from_str_radix #1421") }
    if !(parsed(capture num.from_str_radix<u32>("0", 2u32)) == present(0u32)) { panic("from_str_radix #1422") }
    if !(parsed(capture num.from_str_radix<u32>("0", 36u32)) == present(0u32)) { panic("from_str_radix #1423") }
    if !(parsed(capture num.from_str_radix<u32>("0", 16u32)) == present(0u32)) { panic("from_str_radix #1424") }
    if !(parsed(capture num.from_str_radix<u32>("7", 10u32)) == present(7u32)) { panic("from_str_radix #1425") }
    if !(parsed(capture num.from_str_radix<u32>("7", 16u32)) == present(7u32)) { panic("from_str_radix #1426") }
    if !(parsed(capture num.from_str_radix<u32>("111", 2u32)) == present(7u32)) { panic("from_str_radix #1427") }
    if !(parsed(capture num.from_str_radix<u32>("7", 36u32)) == present(7u32)) { panic("from_str_radix #1428") }
    if !(parsed(capture num.from_str_radix<u32>("7", 16u32)) == present(7u32)) { panic("from_str_radix #1429") }
    if !(parsed(capture num.from_str_radix<u32>("0", 10u32)) == present(0u32)) { panic("from_str_radix #1430") }
    if !(parsed(capture num.from_str_radix<u32>("0", 16u32)) == present(0u32)) { panic("from_str_radix #1431") }
    if !(parsed(capture num.from_str_radix<u32>("0", 2u32)) == present(0u32)) { panic("from_str_radix #1432") }
    if !(parsed(capture num.from_str_radix<u32>("0", 36u32)) == present(0u32)) { panic("from_str_radix #1433") }
    if !(parsed(capture num.from_str_radix<u32>("0", 16u32)) == present(0u32)) { panic("from_str_radix #1434") }
    if !(parsed(capture num.from_str_radix<u32>("+7", 10u32)) == present(7u32)) { panic("from_str_radix #1435") }
    if !(kind(capture num.from_str_radix<u32>("", 10u32)) == present(IntErrorKind.Empty)) { panic("from_str_radix #1436") }
    if !(kind(capture num.from_str_radix<u32>("-", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1437") }
    if !(kind(capture num.from_str_radix<u32>("+", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1438") }
    if !(kind(capture num.from_str_radix<u32>("1_0", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1439") }
    if !(kind(capture num.from_str_radix<u32>("12", 2u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1440") }
}

fn group12() {
    if !(kind(capture num.from_str_radix<u32>(" 1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1441") }
    if !(kind(capture num.from_str_radix<u32>("4294967296", 10u32)) == present(IntErrorKind.PosOverflow)) { panic("from_str_radix #1442") }
    if !(kind(capture num.from_str_radix<u32>("1", 37u32)) == present(IntErrorKind.InvalidRadix)) { panic("from_str_radix #1443") }
    if !(kind(capture num.from_str_radix<u32>("1", 1u32)) == present(IntErrorKind.InvalidRadix)) { panic("from_str_radix #1444") }
    if !(kind(capture num.from_str_radix<u32>("-1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1445") }
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
    0
}
