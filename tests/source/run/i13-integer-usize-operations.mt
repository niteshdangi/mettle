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
    match result { success(_) => none, failure(error) => present(*error.kind()) }
}

fn group0() {
    if !(usize.BITS == 64u32) { panic("BITS #1") }
    if !(usize.MIN == 0usize) { panic("MIN #2") }
    if !(usize.MAX == 18446744073709551615usize) { panic("MAX #3") }
    if !(missing(usize.MAX.checked_add(1usize))) { panic("checked_add #4") }
    if !(usize.MAX.wrapping_add(1usize) == 0usize) { panic("wrapping_add #5") }
    if !(usize.MAX.overflowing_add(1usize).0 == 0usize && usize.MAX.overflowing_add(1usize).1 == true) { panic("overflowing_add #6") }
    if !(usize.MAX.saturating_add(1usize) == usize.MAX) { panic("saturating_add #7") }
    if !(usize.MAX.checked_sub(1usize) == present(18446744073709551614usize)) { panic("checked_sub #8") }
    if !(usize.MAX.wrapping_sub(1usize) == 18446744073709551614usize) { panic("wrapping_sub #9") }
    if !(usize.MAX.overflowing_sub(1usize).0 == 18446744073709551614usize && usize.MAX.overflowing_sub(1usize).1 == false) { panic("overflowing_sub #10") }
    if !(usize.MAX.saturating_sub(1usize) == 18446744073709551614usize) { panic("saturating_sub #11") }
    if !(usize.MAX.strict_sub(1usize) == 18446744073709551614usize) { panic("strict_sub #12") }
    if !(unsafe { usize.MAX.unchecked_sub(1usize) } == 18446744073709551614usize) { panic("unchecked_sub #13") }
    if !(usize.MAX.checked_mul(1usize) == present(usize.MAX)) { panic("checked_mul #14") }
    if !(usize.MAX.wrapping_mul(1usize) == usize.MAX) { panic("wrapping_mul #15") }
    if !(usize.MAX.overflowing_mul(1usize).0 == usize.MAX && usize.MAX.overflowing_mul(1usize).1 == false) { panic("overflowing_mul #16") }
    if !(usize.MAX.saturating_mul(1usize) == usize.MAX) { panic("saturating_mul #17") }
    if !(usize.MAX.strict_mul(1usize) == usize.MAX) { panic("strict_mul #18") }
    if !(unsafe { usize.MAX.unchecked_mul(1usize) } == usize.MAX) { panic("unchecked_mul #19") }
    if !(usize.MAX.checked_div(1usize) == present(usize.MAX)) { panic("checked_div #20") }
    if !(usize.MAX.wrapping_div(1usize) == usize.MAX) { panic("wrapping_div #21") }
    if !(usize.MAX.overflowing_div(1usize).0 == usize.MAX && usize.MAX.overflowing_div(1usize).1 == false) { panic("overflowing_div #22") }
    if !(usize.MAX.strict_div(1usize) == usize.MAX) { panic("strict_div #23") }
    if !(usize.MAX.saturating_div(1usize) == usize.MAX) { panic("saturating_div #24") }
    if !(usize.MAX.checked_rem(1usize) == present(0usize)) { panic("checked_rem #25") }
    if !(usize.MAX.wrapping_rem(1usize) == 0usize) { panic("wrapping_rem #26") }
    if !(usize.MAX.overflowing_rem(1usize).0 == 0usize && usize.MAX.overflowing_rem(1usize).1 == false) { panic("overflowing_rem #27") }
    if !(usize.MAX.strict_rem(1usize) == 0usize) { panic("strict_rem #28") }
    if !(usize.MAX.checked_div_euclid(1usize) == present(usize.MAX)) { panic("checked_div_euclid #29") }
    if !(usize.MAX.wrapping_div_euclid(1usize) == usize.MAX) { panic("wrapping_div_euclid #30") }
    if !(usize.MAX.overflowing_div_euclid(1usize).0 == usize.MAX && usize.MAX.overflowing_div_euclid(1usize).1 == false) { panic("overflowing_div_euclid #31") }
    if !(usize.MAX.strict_div_euclid(1usize) == usize.MAX) { panic("strict_div_euclid #32") }
    if !(usize.MAX.div_euclid(1usize) == usize.MAX) { panic("div_euclid #33") }
    if !(usize.MAX.checked_rem_euclid(1usize) == present(0usize)) { panic("checked_rem_euclid #34") }
    if !(usize.MAX.wrapping_rem_euclid(1usize) == 0usize) { panic("wrapping_rem_euclid #35") }
    if !(usize.MAX.overflowing_rem_euclid(1usize).0 == 0usize && usize.MAX.overflowing_rem_euclid(1usize).1 == false) { panic("overflowing_rem_euclid #36") }
    if !(usize.MAX.strict_rem_euclid(1usize) == 0usize) { panic("strict_rem_euclid #37") }
    if !(usize.MAX.rem_euclid(1usize) == 0usize) { panic("rem_euclid #38") }
    if !(usize.MAX.abs_diff(1usize) == 18446744073709551614usize) { panic("abs_diff #39") }
    if !(usize.MAX.midpoint(1usize) == 9223372036854775808usize) { panic("midpoint #40") }
    if !(0usize.checked_add(1usize) == present(1usize)) { panic("checked_add #41") }
    if !(0usize.wrapping_add(1usize) == 1usize) { panic("wrapping_add #42") }
    if !(0usize.overflowing_add(1usize).0 == 1usize && 0usize.overflowing_add(1usize).1 == false) { panic("overflowing_add #43") }
    if !(0usize.saturating_add(1usize) == 1usize) { panic("saturating_add #44") }
    if !(0usize.strict_add(1usize) == 1usize) { panic("strict_add #45") }
    if !(unsafe { 0usize.unchecked_add(1usize) } == 1usize) { panic("unchecked_add #46") }
    if !(missing(0usize.checked_sub(1usize))) { panic("checked_sub #47") }
    if !(0usize.wrapping_sub(1usize) == usize.MAX) { panic("wrapping_sub #48") }
    if !(0usize.overflowing_sub(1usize).0 == usize.MAX && 0usize.overflowing_sub(1usize).1 == true) { panic("overflowing_sub #49") }
    if !(0usize.saturating_sub(1usize) == 0usize) { panic("saturating_sub #50") }
    if !(0usize.checked_mul(1usize) == present(0usize)) { panic("checked_mul #51") }
    if !(0usize.wrapping_mul(1usize) == 0usize) { panic("wrapping_mul #52") }
    if !(0usize.overflowing_mul(1usize).0 == 0usize && 0usize.overflowing_mul(1usize).1 == false) { panic("overflowing_mul #53") }
    if !(0usize.saturating_mul(1usize) == 0usize) { panic("saturating_mul #54") }
    if !(0usize.strict_mul(1usize) == 0usize) { panic("strict_mul #55") }
    if !(unsafe { 0usize.unchecked_mul(1usize) } == 0usize) { panic("unchecked_mul #56") }
    if !(0usize.checked_div(1usize) == present(0usize)) { panic("checked_div #57") }
    if !(0usize.wrapping_div(1usize) == 0usize) { panic("wrapping_div #58") }
    if !(0usize.overflowing_div(1usize).0 == 0usize && 0usize.overflowing_div(1usize).1 == false) { panic("overflowing_div #59") }
    if !(0usize.strict_div(1usize) == 0usize) { panic("strict_div #60") }
    if !(0usize.saturating_div(1usize) == 0usize) { panic("saturating_div #61") }
    if !(0usize.checked_rem(1usize) == present(0usize)) { panic("checked_rem #62") }
    if !(0usize.wrapping_rem(1usize) == 0usize) { panic("wrapping_rem #63") }
    if !(0usize.overflowing_rem(1usize).0 == 0usize && 0usize.overflowing_rem(1usize).1 == false) { panic("overflowing_rem #64") }
    if !(0usize.strict_rem(1usize) == 0usize) { panic("strict_rem #65") }
    if !(0usize.checked_div_euclid(1usize) == present(0usize)) { panic("checked_div_euclid #66") }
    if !(0usize.wrapping_div_euclid(1usize) == 0usize) { panic("wrapping_div_euclid #67") }
    if !(0usize.overflowing_div_euclid(1usize).0 == 0usize && 0usize.overflowing_div_euclid(1usize).1 == false) { panic("overflowing_div_euclid #68") }
    if !(0usize.strict_div_euclid(1usize) == 0usize) { panic("strict_div_euclid #69") }
    if !(0usize.div_euclid(1usize) == 0usize) { panic("div_euclid #70") }
    if !(0usize.checked_rem_euclid(1usize) == present(0usize)) { panic("checked_rem_euclid #71") }
    if !(0usize.wrapping_rem_euclid(1usize) == 0usize) { panic("wrapping_rem_euclid #72") }
    if !(0usize.overflowing_rem_euclid(1usize).0 == 0usize && 0usize.overflowing_rem_euclid(1usize).1 == false) { panic("overflowing_rem_euclid #73") }
    if !(0usize.strict_rem_euclid(1usize) == 0usize) { panic("strict_rem_euclid #74") }
    if !(0usize.rem_euclid(1usize) == 0usize) { panic("rem_euclid #75") }
    if !(0usize.abs_diff(1usize) == 1usize) { panic("abs_diff #76") }
    if !(0usize.midpoint(1usize) == 0usize) { panic("midpoint #77") }
    if !(1000usize.checked_add(7usize) == present(1007usize)) { panic("checked_add #78") }
    if !(1000usize.wrapping_add(7usize) == 1007usize) { panic("wrapping_add #79") }
    if !(1000usize.overflowing_add(7usize).0 == 1007usize && 1000usize.overflowing_add(7usize).1 == false) { panic("overflowing_add #80") }
    if !(1000usize.saturating_add(7usize) == 1007usize) { panic("saturating_add #81") }
    if !(1000usize.strict_add(7usize) == 1007usize) { panic("strict_add #82") }
    if !(unsafe { 1000usize.unchecked_add(7usize) } == 1007usize) { panic("unchecked_add #83") }
    if !(1000usize.checked_sub(7usize) == present(993usize)) { panic("checked_sub #84") }
    if !(1000usize.wrapping_sub(7usize) == 993usize) { panic("wrapping_sub #85") }
    if !(1000usize.overflowing_sub(7usize).0 == 993usize && 1000usize.overflowing_sub(7usize).1 == false) { panic("overflowing_sub #86") }
    if !(1000usize.saturating_sub(7usize) == 993usize) { panic("saturating_sub #87") }
    if !(1000usize.strict_sub(7usize) == 993usize) { panic("strict_sub #88") }
    if !(unsafe { 1000usize.unchecked_sub(7usize) } == 993usize) { panic("unchecked_sub #89") }
    if !(1000usize.checked_mul(7usize) == present(7000usize)) { panic("checked_mul #90") }
    if !(1000usize.wrapping_mul(7usize) == 7000usize) { panic("wrapping_mul #91") }
    if !(1000usize.overflowing_mul(7usize).0 == 7000usize && 1000usize.overflowing_mul(7usize).1 == false) { panic("overflowing_mul #92") }
    if !(1000usize.saturating_mul(7usize) == 7000usize) { panic("saturating_mul #93") }
    if !(1000usize.strict_mul(7usize) == 7000usize) { panic("strict_mul #94") }
    if !(unsafe { 1000usize.unchecked_mul(7usize) } == 7000usize) { panic("unchecked_mul #95") }
    if !(1000usize.checked_div(7usize) == present(142usize)) { panic("checked_div #96") }
    if !(1000usize.wrapping_div(7usize) == 142usize) { panic("wrapping_div #97") }
    if !(1000usize.overflowing_div(7usize).0 == 142usize && 1000usize.overflowing_div(7usize).1 == false) { panic("overflowing_div #98") }
    if !(1000usize.strict_div(7usize) == 142usize) { panic("strict_div #99") }
    if !(1000usize.saturating_div(7usize) == 142usize) { panic("saturating_div #100") }
    if !(1000usize.checked_rem(7usize) == present(6usize)) { panic("checked_rem #101") }
    if !(1000usize.wrapping_rem(7usize) == 6usize) { panic("wrapping_rem #102") }
    if !(1000usize.overflowing_rem(7usize).0 == 6usize && 1000usize.overflowing_rem(7usize).1 == false) { panic("overflowing_rem #103") }
    if !(1000usize.strict_rem(7usize) == 6usize) { panic("strict_rem #104") }
    if !(1000usize.checked_div_euclid(7usize) == present(142usize)) { panic("checked_div_euclid #105") }
    if !(1000usize.wrapping_div_euclid(7usize) == 142usize) { panic("wrapping_div_euclid #106") }
    if !(1000usize.overflowing_div_euclid(7usize).0 == 142usize && 1000usize.overflowing_div_euclid(7usize).1 == false) { panic("overflowing_div_euclid #107") }
    if !(1000usize.strict_div_euclid(7usize) == 142usize) { panic("strict_div_euclid #108") }
    if !(1000usize.div_euclid(7usize) == 142usize) { panic("div_euclid #109") }
    if !(1000usize.checked_rem_euclid(7usize) == present(6usize)) { panic("checked_rem_euclid #110") }
    if !(1000usize.wrapping_rem_euclid(7usize) == 6usize) { panic("wrapping_rem_euclid #111") }
    if !(1000usize.overflowing_rem_euclid(7usize).0 == 6usize && 1000usize.overflowing_rem_euclid(7usize).1 == false) { panic("overflowing_rem_euclid #112") }
    if !(1000usize.strict_rem_euclid(7usize) == 6usize) { panic("strict_rem_euclid #113") }
    if !(1000usize.rem_euclid(7usize) == 6usize) { panic("rem_euclid #114") }
    if !(1000usize.abs_diff(7usize) == 993usize) { panic("abs_diff #115") }
    if !(1000usize.midpoint(7usize) == 503usize) { panic("midpoint #116") }
    if !(7usize.checked_add(1000usize) == present(1007usize)) { panic("checked_add #117") }
    if !(7usize.wrapping_add(1000usize) == 1007usize) { panic("wrapping_add #118") }
    if !(7usize.overflowing_add(1000usize).0 == 1007usize && 7usize.overflowing_add(1000usize).1 == false) { panic("overflowing_add #119") }
    if !(7usize.saturating_add(1000usize) == 1007usize) { panic("saturating_add #120") }
}

fn group1() {
    if !(7usize.strict_add(1000usize) == 1007usize) { panic("strict_add #121") }
    if !(unsafe { 7usize.unchecked_add(1000usize) } == 1007usize) { panic("unchecked_add #122") }
    if !(missing(7usize.checked_sub(1000usize))) { panic("checked_sub #123") }
    if !(7usize.wrapping_sub(1000usize) == 18446744073709550623usize) { panic("wrapping_sub #124") }
    if !(7usize.overflowing_sub(1000usize).0 == 18446744073709550623usize && 7usize.overflowing_sub(1000usize).1 == true) { panic("overflowing_sub #125") }
    if !(7usize.saturating_sub(1000usize) == 0usize) { panic("saturating_sub #126") }
    if !(7usize.checked_mul(1000usize) == present(7000usize)) { panic("checked_mul #127") }
    if !(7usize.wrapping_mul(1000usize) == 7000usize) { panic("wrapping_mul #128") }
    if !(7usize.overflowing_mul(1000usize).0 == 7000usize && 7usize.overflowing_mul(1000usize).1 == false) { panic("overflowing_mul #129") }
    if !(7usize.saturating_mul(1000usize) == 7000usize) { panic("saturating_mul #130") }
    if !(7usize.strict_mul(1000usize) == 7000usize) { panic("strict_mul #131") }
    if !(unsafe { 7usize.unchecked_mul(1000usize) } == 7000usize) { panic("unchecked_mul #132") }
    if !(7usize.checked_div(1000usize) == present(0usize)) { panic("checked_div #133") }
    if !(7usize.wrapping_div(1000usize) == 0usize) { panic("wrapping_div #134") }
    if !(7usize.overflowing_div(1000usize).0 == 0usize && 7usize.overflowing_div(1000usize).1 == false) { panic("overflowing_div #135") }
    if !(7usize.strict_div(1000usize) == 0usize) { panic("strict_div #136") }
    if !(7usize.saturating_div(1000usize) == 0usize) { panic("saturating_div #137") }
    if !(7usize.checked_rem(1000usize) == present(7usize)) { panic("checked_rem #138") }
    if !(7usize.wrapping_rem(1000usize) == 7usize) { panic("wrapping_rem #139") }
    if !(7usize.overflowing_rem(1000usize).0 == 7usize && 7usize.overflowing_rem(1000usize).1 == false) { panic("overflowing_rem #140") }
    if !(7usize.strict_rem(1000usize) == 7usize) { panic("strict_rem #141") }
    if !(7usize.checked_div_euclid(1000usize) == present(0usize)) { panic("checked_div_euclid #142") }
    if !(7usize.wrapping_div_euclid(1000usize) == 0usize) { panic("wrapping_div_euclid #143") }
    if !(7usize.overflowing_div_euclid(1000usize).0 == 0usize && 7usize.overflowing_div_euclid(1000usize).1 == false) { panic("overflowing_div_euclid #144") }
    if !(7usize.strict_div_euclid(1000usize) == 0usize) { panic("strict_div_euclid #145") }
    if !(7usize.div_euclid(1000usize) == 0usize) { panic("div_euclid #146") }
    if !(7usize.checked_rem_euclid(1000usize) == present(7usize)) { panic("checked_rem_euclid #147") }
    if !(7usize.wrapping_rem_euclid(1000usize) == 7usize) { panic("wrapping_rem_euclid #148") }
    if !(7usize.overflowing_rem_euclid(1000usize).0 == 7usize && 7usize.overflowing_rem_euclid(1000usize).1 == false) { panic("overflowing_rem_euclid #149") }
    if !(7usize.strict_rem_euclid(1000usize) == 7usize) { panic("strict_rem_euclid #150") }
    if !(7usize.rem_euclid(1000usize) == 7usize) { panic("rem_euclid #151") }
    if !(7usize.abs_diff(1000usize) == 993usize) { panic("abs_diff #152") }
    if !(7usize.midpoint(1000usize) == 503usize) { panic("midpoint #153") }
    if !(missing(usize.MAX.checked_add(2usize))) { panic("checked_add #154") }
    if !(usize.MAX.wrapping_add(2usize) == 1usize) { panic("wrapping_add #155") }
    if !(usize.MAX.overflowing_add(2usize).0 == 1usize && usize.MAX.overflowing_add(2usize).1 == true) { panic("overflowing_add #156") }
    if !(usize.MAX.saturating_add(2usize) == usize.MAX) { panic("saturating_add #157") }
    if !(usize.MAX.checked_sub(2usize) == present(18446744073709551613usize)) { panic("checked_sub #158") }
    if !(usize.MAX.wrapping_sub(2usize) == 18446744073709551613usize) { panic("wrapping_sub #159") }
    if !(usize.MAX.overflowing_sub(2usize).0 == 18446744073709551613usize && usize.MAX.overflowing_sub(2usize).1 == false) { panic("overflowing_sub #160") }
    if !(usize.MAX.saturating_sub(2usize) == 18446744073709551613usize) { panic("saturating_sub #161") }
    if !(usize.MAX.strict_sub(2usize) == 18446744073709551613usize) { panic("strict_sub #162") }
    if !(unsafe { usize.MAX.unchecked_sub(2usize) } == 18446744073709551613usize) { panic("unchecked_sub #163") }
    if !(missing(usize.MAX.checked_mul(2usize))) { panic("checked_mul #164") }
    if !(usize.MAX.wrapping_mul(2usize) == 18446744073709551614usize) { panic("wrapping_mul #165") }
    if !(usize.MAX.overflowing_mul(2usize).0 == 18446744073709551614usize && usize.MAX.overflowing_mul(2usize).1 == true) { panic("overflowing_mul #166") }
    if !(usize.MAX.saturating_mul(2usize) == usize.MAX) { panic("saturating_mul #167") }
    if !(usize.MAX.checked_div(2usize) == present(9223372036854775807usize)) { panic("checked_div #168") }
    if !(usize.MAX.wrapping_div(2usize) == 9223372036854775807usize) { panic("wrapping_div #169") }
    if !(usize.MAX.overflowing_div(2usize).0 == 9223372036854775807usize && usize.MAX.overflowing_div(2usize).1 == false) { panic("overflowing_div #170") }
    if !(usize.MAX.strict_div(2usize) == 9223372036854775807usize) { panic("strict_div #171") }
    if !(usize.MAX.saturating_div(2usize) == 9223372036854775807usize) { panic("saturating_div #172") }
    if !(usize.MAX.checked_rem(2usize) == present(1usize)) { panic("checked_rem #173") }
    if !(usize.MAX.wrapping_rem(2usize) == 1usize) { panic("wrapping_rem #174") }
    if !(usize.MAX.overflowing_rem(2usize).0 == 1usize && usize.MAX.overflowing_rem(2usize).1 == false) { panic("overflowing_rem #175") }
    if !(usize.MAX.strict_rem(2usize) == 1usize) { panic("strict_rem #176") }
    if !(usize.MAX.checked_div_euclid(2usize) == present(9223372036854775807usize)) { panic("checked_div_euclid #177") }
    if !(usize.MAX.wrapping_div_euclid(2usize) == 9223372036854775807usize) { panic("wrapping_div_euclid #178") }
    if !(usize.MAX.overflowing_div_euclid(2usize).0 == 9223372036854775807usize && usize.MAX.overflowing_div_euclid(2usize).1 == false) { panic("overflowing_div_euclid #179") }
    if !(usize.MAX.strict_div_euclid(2usize) == 9223372036854775807usize) { panic("strict_div_euclid #180") }
    if !(usize.MAX.div_euclid(2usize) == 9223372036854775807usize) { panic("div_euclid #181") }
    if !(usize.MAX.checked_rem_euclid(2usize) == present(1usize)) { panic("checked_rem_euclid #182") }
    if !(usize.MAX.wrapping_rem_euclid(2usize) == 1usize) { panic("wrapping_rem_euclid #183") }
    if !(usize.MAX.overflowing_rem_euclid(2usize).0 == 1usize && usize.MAX.overflowing_rem_euclid(2usize).1 == false) { panic("overflowing_rem_euclid #184") }
    if !(usize.MAX.strict_rem_euclid(2usize) == 1usize) { panic("strict_rem_euclid #185") }
    if !(usize.MAX.rem_euclid(2usize) == 1usize) { panic("rem_euclid #186") }
    if !(usize.MAX.abs_diff(2usize) == 18446744073709551613usize) { panic("abs_diff #187") }
    if !(usize.MAX.midpoint(2usize) == 9223372036854775808usize) { panic("midpoint #188") }
    if !(0usize.checked_add(0usize) == present(0usize)) { panic("checked_add #189") }
    if !(0usize.wrapping_add(0usize) == 0usize) { panic("wrapping_add #190") }
    if !(0usize.overflowing_add(0usize).0 == 0usize && 0usize.overflowing_add(0usize).1 == false) { panic("overflowing_add #191") }
    if !(0usize.saturating_add(0usize) == 0usize) { panic("saturating_add #192") }
    if !(0usize.strict_add(0usize) == 0usize) { panic("strict_add #193") }
    if !(unsafe { 0usize.unchecked_add(0usize) } == 0usize) { panic("unchecked_add #194") }
    if !(0usize.checked_sub(0usize) == present(0usize)) { panic("checked_sub #195") }
    if !(0usize.wrapping_sub(0usize) == 0usize) { panic("wrapping_sub #196") }
    if !(0usize.overflowing_sub(0usize).0 == 0usize && 0usize.overflowing_sub(0usize).1 == false) { panic("overflowing_sub #197") }
    if !(0usize.saturating_sub(0usize) == 0usize) { panic("saturating_sub #198") }
    if !(0usize.strict_sub(0usize) == 0usize) { panic("strict_sub #199") }
    if !(unsafe { 0usize.unchecked_sub(0usize) } == 0usize) { panic("unchecked_sub #200") }
    if !(0usize.checked_mul(0usize) == present(0usize)) { panic("checked_mul #201") }
    if !(0usize.wrapping_mul(0usize) == 0usize) { panic("wrapping_mul #202") }
    if !(0usize.overflowing_mul(0usize).0 == 0usize && 0usize.overflowing_mul(0usize).1 == false) { panic("overflowing_mul #203") }
    if !(0usize.saturating_mul(0usize) == 0usize) { panic("saturating_mul #204") }
    if !(0usize.strict_mul(0usize) == 0usize) { panic("strict_mul #205") }
    if !(unsafe { 0usize.unchecked_mul(0usize) } == 0usize) { panic("unchecked_mul #206") }
    if !(missing(0usize.checked_div(0usize))) { panic("checked_div #207") }
    if !(missing(0usize.checked_rem(0usize))) { panic("checked_rem #208") }
    if !(missing(0usize.checked_div_euclid(0usize))) { panic("checked_div_euclid #209") }
    if !(missing(0usize.checked_rem_euclid(0usize))) { panic("checked_rem_euclid #210") }
    if !(0usize.abs_diff(0usize) == 0usize) { panic("abs_diff #211") }
    if !(0usize.midpoint(0usize) == 0usize) { panic("midpoint #212") }
    if !(missing(usize.MAX.checked_add(usize.MAX))) { panic("checked_add #213") }
    if !(usize.MAX.wrapping_add(usize.MAX) == 18446744073709551614usize) { panic("wrapping_add #214") }
    if !(usize.MAX.overflowing_add(usize.MAX).0 == 18446744073709551614usize && usize.MAX.overflowing_add(usize.MAX).1 == true) { panic("overflowing_add #215") }
    if !(usize.MAX.saturating_add(usize.MAX) == usize.MAX) { panic("saturating_add #216") }
    if !(usize.MAX.checked_sub(usize.MAX) == present(0usize)) { panic("checked_sub #217") }
    if !(usize.MAX.wrapping_sub(usize.MAX) == 0usize) { panic("wrapping_sub #218") }
    if !(usize.MAX.overflowing_sub(usize.MAX).0 == 0usize && usize.MAX.overflowing_sub(usize.MAX).1 == false) { panic("overflowing_sub #219") }
    if !(usize.MAX.saturating_sub(usize.MAX) == 0usize) { panic("saturating_sub #220") }
    if !(usize.MAX.strict_sub(usize.MAX) == 0usize) { panic("strict_sub #221") }
    if !(unsafe { usize.MAX.unchecked_sub(usize.MAX) } == 0usize) { panic("unchecked_sub #222") }
    if !(missing(usize.MAX.checked_mul(usize.MAX))) { panic("checked_mul #223") }
    if !(usize.MAX.wrapping_mul(usize.MAX) == 1usize) { panic("wrapping_mul #224") }
    if !(usize.MAX.overflowing_mul(usize.MAX).0 == 1usize && usize.MAX.overflowing_mul(usize.MAX).1 == true) { panic("overflowing_mul #225") }
    if !(usize.MAX.saturating_mul(usize.MAX) == usize.MAX) { panic("saturating_mul #226") }
    if !(usize.MAX.checked_div(usize.MAX) == present(1usize)) { panic("checked_div #227") }
    if !(usize.MAX.wrapping_div(usize.MAX) == 1usize) { panic("wrapping_div #228") }
    if !(usize.MAX.overflowing_div(usize.MAX).0 == 1usize && usize.MAX.overflowing_div(usize.MAX).1 == false) { panic("overflowing_div #229") }
    if !(usize.MAX.strict_div(usize.MAX) == 1usize) { panic("strict_div #230") }
    if !(usize.MAX.saturating_div(usize.MAX) == 1usize) { panic("saturating_div #231") }
    if !(usize.MAX.checked_rem(usize.MAX) == present(0usize)) { panic("checked_rem #232") }
    if !(usize.MAX.wrapping_rem(usize.MAX) == 0usize) { panic("wrapping_rem #233") }
    if !(usize.MAX.overflowing_rem(usize.MAX).0 == 0usize && usize.MAX.overflowing_rem(usize.MAX).1 == false) { panic("overflowing_rem #234") }
    if !(usize.MAX.strict_rem(usize.MAX) == 0usize) { panic("strict_rem #235") }
    if !(usize.MAX.checked_div_euclid(usize.MAX) == present(1usize)) { panic("checked_div_euclid #236") }
    if !(usize.MAX.wrapping_div_euclid(usize.MAX) == 1usize) { panic("wrapping_div_euclid #237") }
    if !(usize.MAX.overflowing_div_euclid(usize.MAX).0 == 1usize && usize.MAX.overflowing_div_euclid(usize.MAX).1 == false) { panic("overflowing_div_euclid #238") }
    if !(usize.MAX.strict_div_euclid(usize.MAX) == 1usize) { panic("strict_div_euclid #239") }
    if !(usize.MAX.div_euclid(usize.MAX) == 1usize) { panic("div_euclid #240") }
}

fn group2() {
    if !(usize.MAX.checked_rem_euclid(usize.MAX) == present(0usize)) { panic("checked_rem_euclid #241") }
    if !(usize.MAX.wrapping_rem_euclid(usize.MAX) == 0usize) { panic("wrapping_rem_euclid #242") }
    if !(usize.MAX.overflowing_rem_euclid(usize.MAX).0 == 0usize && usize.MAX.overflowing_rem_euclid(usize.MAX).1 == false) { panic("overflowing_rem_euclid #243") }
    if !(usize.MAX.strict_rem_euclid(usize.MAX) == 0usize) { panic("strict_rem_euclid #244") }
    if !(usize.MAX.rem_euclid(usize.MAX) == 0usize) { panic("rem_euclid #245") }
    if !(usize.MAX.abs_diff(usize.MAX) == 0usize) { panic("abs_diff #246") }
    if !(usize.MAX.midpoint(usize.MAX) == usize.MAX) { panic("midpoint #247") }
    if !(missing(usize.MAX.checked_add(18446744073709551614usize))) { panic("checked_add #248") }
    if !(usize.MAX.wrapping_add(18446744073709551614usize) == 18446744073709551613usize) { panic("wrapping_add #249") }
    if !(usize.MAX.overflowing_add(18446744073709551614usize).0 == 18446744073709551613usize && usize.MAX.overflowing_add(18446744073709551614usize).1 == true) { panic("overflowing_add #250") }
    if !(usize.MAX.saturating_add(18446744073709551614usize) == usize.MAX) { panic("saturating_add #251") }
    if !(usize.MAX.checked_sub(18446744073709551614usize) == present(1usize)) { panic("checked_sub #252") }
    if !(usize.MAX.wrapping_sub(18446744073709551614usize) == 1usize) { panic("wrapping_sub #253") }
    if !(usize.MAX.overflowing_sub(18446744073709551614usize).0 == 1usize && usize.MAX.overflowing_sub(18446744073709551614usize).1 == false) { panic("overflowing_sub #254") }
    if !(usize.MAX.saturating_sub(18446744073709551614usize) == 1usize) { panic("saturating_sub #255") }
    if !(usize.MAX.strict_sub(18446744073709551614usize) == 1usize) { panic("strict_sub #256") }
    if !(unsafe { usize.MAX.unchecked_sub(18446744073709551614usize) } == 1usize) { panic("unchecked_sub #257") }
    if !(missing(usize.MAX.checked_mul(18446744073709551614usize))) { panic("checked_mul #258") }
    if !(usize.MAX.wrapping_mul(18446744073709551614usize) == 2usize) { panic("wrapping_mul #259") }
    if !(usize.MAX.overflowing_mul(18446744073709551614usize).0 == 2usize && usize.MAX.overflowing_mul(18446744073709551614usize).1 == true) { panic("overflowing_mul #260") }
    if !(usize.MAX.saturating_mul(18446744073709551614usize) == usize.MAX) { panic("saturating_mul #261") }
    if !(usize.MAX.checked_div(18446744073709551614usize) == present(1usize)) { panic("checked_div #262") }
    if !(usize.MAX.wrapping_div(18446744073709551614usize) == 1usize) { panic("wrapping_div #263") }
    if !(usize.MAX.overflowing_div(18446744073709551614usize).0 == 1usize && usize.MAX.overflowing_div(18446744073709551614usize).1 == false) { panic("overflowing_div #264") }
    if !(usize.MAX.strict_div(18446744073709551614usize) == 1usize) { panic("strict_div #265") }
    if !(usize.MAX.saturating_div(18446744073709551614usize) == 1usize) { panic("saturating_div #266") }
    if !(usize.MAX.checked_rem(18446744073709551614usize) == present(1usize)) { panic("checked_rem #267") }
    if !(usize.MAX.wrapping_rem(18446744073709551614usize) == 1usize) { panic("wrapping_rem #268") }
    if !(usize.MAX.overflowing_rem(18446744073709551614usize).0 == 1usize && usize.MAX.overflowing_rem(18446744073709551614usize).1 == false) { panic("overflowing_rem #269") }
    if !(usize.MAX.strict_rem(18446744073709551614usize) == 1usize) { panic("strict_rem #270") }
    if !(usize.MAX.checked_div_euclid(18446744073709551614usize) == present(1usize)) { panic("checked_div_euclid #271") }
    if !(usize.MAX.wrapping_div_euclid(18446744073709551614usize) == 1usize) { panic("wrapping_div_euclid #272") }
    if !(usize.MAX.overflowing_div_euclid(18446744073709551614usize).0 == 1usize && usize.MAX.overflowing_div_euclid(18446744073709551614usize).1 == false) { panic("overflowing_div_euclid #273") }
    if !(usize.MAX.strict_div_euclid(18446744073709551614usize) == 1usize) { panic("strict_div_euclid #274") }
    if !(usize.MAX.div_euclid(18446744073709551614usize) == 1usize) { panic("div_euclid #275") }
    if !(usize.MAX.checked_rem_euclid(18446744073709551614usize) == present(1usize)) { panic("checked_rem_euclid #276") }
    if !(usize.MAX.wrapping_rem_euclid(18446744073709551614usize) == 1usize) { panic("wrapping_rem_euclid #277") }
    if !(usize.MAX.overflowing_rem_euclid(18446744073709551614usize).0 == 1usize && usize.MAX.overflowing_rem_euclid(18446744073709551614usize).1 == false) { panic("overflowing_rem_euclid #278") }
    if !(usize.MAX.strict_rem_euclid(18446744073709551614usize) == 1usize) { panic("strict_rem_euclid #279") }
    if !(usize.MAX.rem_euclid(18446744073709551614usize) == 1usize) { panic("rem_euclid #280") }
    if !(usize.MAX.abs_diff(18446744073709551614usize) == 1usize) { panic("abs_diff #281") }
    if !(usize.MAX.midpoint(18446744073709551614usize) == 18446744073709551614usize) { panic("midpoint #282") }
    if !(missing(usize.MAX.checked_add_signed(1isize))) { panic("checked_add_signed #283") }
    if !(usize.MAX.wrapping_add_signed(1isize) == 0usize) { panic("wrapping_add_signed #284") }
    if !(usize.MAX.overflowing_add_signed(1isize).0 == 0usize && usize.MAX.overflowing_add_signed(1isize).1 == true) { panic("overflowing_add_signed #285") }
    if !(usize.MAX.saturating_add_signed(1isize) == usize.MAX) { panic("saturating_add_signed #286") }
    if !(usize.MAX.checked_sub_signed(1isize) == present(18446744073709551614usize)) { panic("checked_sub_signed #287") }
    if !(usize.MAX.wrapping_sub_signed(1isize) == 18446744073709551614usize) { panic("wrapping_sub_signed #288") }
    if !(usize.MAX.overflowing_sub_signed(1isize).0 == 18446744073709551614usize && usize.MAX.overflowing_sub_signed(1isize).1 == false) { panic("overflowing_sub_signed #289") }
    if !(usize.MAX.saturating_sub_signed(1isize) == 18446744073709551614usize) { panic("saturating_sub_signed #290") }
    if !(usize.MAX.strict_sub_signed(1isize) == 18446744073709551614usize) { panic("strict_sub_signed #291") }
    if !(missing(0usize.checked_add_signed((-1isize)))) { panic("checked_add_signed #292") }
    if !(0usize.wrapping_add_signed((-1isize)) == usize.MAX) { panic("wrapping_add_signed #293") }
    if !(0usize.overflowing_add_signed((-1isize)).0 == usize.MAX && 0usize.overflowing_add_signed((-1isize)).1 == true) { panic("overflowing_add_signed #294") }
    if !(0usize.saturating_add_signed((-1isize)) == 0usize) { panic("saturating_add_signed #295") }
    if !(0usize.checked_sub_signed((-1isize)) == present(1usize)) { panic("checked_sub_signed #296") }
    if !(0usize.wrapping_sub_signed((-1isize)) == 1usize) { panic("wrapping_sub_signed #297") }
    if !(0usize.overflowing_sub_signed((-1isize)).0 == 1usize && 0usize.overflowing_sub_signed((-1isize)).1 == false) { panic("overflowing_sub_signed #298") }
    if !(0usize.saturating_sub_signed((-1isize)) == 1usize) { panic("saturating_sub_signed #299") }
    if !(0usize.strict_sub_signed((-1isize)) == 1usize) { panic("strict_sub_signed #300") }
    if !(7usize.checked_add_signed((-3isize)) == present(4usize)) { panic("checked_add_signed #301") }
    if !(7usize.wrapping_add_signed((-3isize)) == 4usize) { panic("wrapping_add_signed #302") }
    if !(7usize.overflowing_add_signed((-3isize)).0 == 4usize && 7usize.overflowing_add_signed((-3isize)).1 == false) { panic("overflowing_add_signed #303") }
    if !(7usize.saturating_add_signed((-3isize)) == 4usize) { panic("saturating_add_signed #304") }
    if !(7usize.strict_add_signed((-3isize)) == 4usize) { panic("strict_add_signed #305") }
    if !(7usize.checked_sub_signed((-3isize)) == present(10usize)) { panic("checked_sub_signed #306") }
    if !(7usize.wrapping_sub_signed((-3isize)) == 10usize) { panic("wrapping_sub_signed #307") }
    if !(7usize.overflowing_sub_signed((-3isize)).0 == 10usize && 7usize.overflowing_sub_signed((-3isize)).1 == false) { panic("overflowing_sub_signed #308") }
    if !(7usize.saturating_sub_signed((-3isize)) == 10usize) { panic("saturating_sub_signed #309") }
    if !(7usize.strict_sub_signed((-3isize)) == 10usize) { panic("strict_sub_signed #310") }
    if !(usize.MAX.checked_add_signed(isize.MIN) == present(9223372036854775807usize)) { panic("checked_add_signed #311") }
    if !(usize.MAX.wrapping_add_signed(isize.MIN) == 9223372036854775807usize) { panic("wrapping_add_signed #312") }
    if !(usize.MAX.overflowing_add_signed(isize.MIN).0 == 9223372036854775807usize && usize.MAX.overflowing_add_signed(isize.MIN).1 == false) { panic("overflowing_add_signed #313") }
    if !(usize.MAX.saturating_add_signed(isize.MIN) == 9223372036854775807usize) { panic("saturating_add_signed #314") }
    if !(usize.MAX.strict_add_signed(isize.MIN) == 9223372036854775807usize) { panic("strict_add_signed #315") }
    if !(missing(usize.MAX.checked_sub_signed(isize.MIN))) { panic("checked_sub_signed #316") }
    if !(usize.MAX.wrapping_sub_signed(isize.MIN) == 9223372036854775807usize) { panic("wrapping_sub_signed #317") }
    if !(usize.MAX.overflowing_sub_signed(isize.MIN).0 == 9223372036854775807usize && usize.MAX.overflowing_sub_signed(isize.MIN).1 == true) { panic("overflowing_sub_signed #318") }
    if !(usize.MAX.saturating_sub_signed(isize.MIN) == usize.MAX) { panic("saturating_sub_signed #319") }
    if !(0usize.checked_add_signed(isize.MAX) == present(9223372036854775807usize)) { panic("checked_add_signed #320") }
    if !(0usize.wrapping_add_signed(isize.MAX) == 9223372036854775807usize) { panic("wrapping_add_signed #321") }
    if !(0usize.overflowing_add_signed(isize.MAX).0 == 9223372036854775807usize && 0usize.overflowing_add_signed(isize.MAX).1 == false) { panic("overflowing_add_signed #322") }
    if !(0usize.saturating_add_signed(isize.MAX) == 9223372036854775807usize) { panic("saturating_add_signed #323") }
    if !(0usize.strict_add_signed(isize.MAX) == 9223372036854775807usize) { panic("strict_add_signed #324") }
    if !(missing(0usize.checked_sub_signed(isize.MAX))) { panic("checked_sub_signed #325") }
    if !(0usize.wrapping_sub_signed(isize.MAX) == 9223372036854775809usize) { panic("wrapping_sub_signed #326") }
    if !(0usize.overflowing_sub_signed(isize.MAX).0 == 9223372036854775809usize && 0usize.overflowing_sub_signed(isize.MAX).1 == true) { panic("overflowing_sub_signed #327") }
    if !(0usize.saturating_sub_signed(isize.MAX) == 0usize) { panic("saturating_sub_signed #328") }
    if !(missing(usize.MAX.checked_neg())) { panic("checked_neg #329") }
    if !(usize.MAX.wrapping_neg() == 1usize) { panic("wrapping_neg #330") }
    if !(usize.MAX.overflowing_neg().0 == 1usize && usize.MAX.overflowing_neg().1 == true) { panic("overflowing_neg #331") }
    if !(usize.MAX.cast_signed() == (-1isize)) { panic("cast_signed #332") }
    if !(usize.MAX.count_ones() == 64u32) { panic("count_ones #333") }
    if !(usize.MAX.count_zeros() == 0u32) { panic("count_zeros #334") }
    if !(usize.MAX.leading_zeros() == 0u32) { panic("leading_zeros #335") }
    if !(usize.MAX.trailing_zeros() == 0u32) { panic("trailing_zeros #336") }
    if !(usize.MAX.leading_ones() == 64u32) { panic("leading_ones #337") }
    if !(usize.MAX.trailing_ones() == 64u32) { panic("trailing_ones #338") }
    if !(usize.MAX.reverse_bits() == usize.MAX) { panic("reverse_bits #339") }
    if !(usize.MAX.swap_bytes() == usize.MAX) { panic("swap_bytes #340") }
    if !(usize.MAX.to_be() == usize.MAX) { panic("to_be #341") }
    if !(usize.MAX.to_le() == usize.MAX) { panic("to_le #342") }
    if !(usize.from_be(usize.MAX) == usize.MAX) { panic("from_be #343") }
    if !(usize.from_le(usize.MAX) == usize.MAX) { panic("from_le #344") }
    if !(usize.MAX.to_le_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_le_bytes #345") }
    if !(usize.MAX.to_be_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_be_bytes #346") }
    if !(usize.MAX.to_ne_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_ne_bytes #347") }
    if !(usize.from_le_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == usize.MAX) { panic("from_le_bytes #348") }
    if !(usize.from_be_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == usize.MAX) { panic("from_be_bytes #349") }
    if !(usize.from_ne_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == usize.MAX) { panic("from_ne_bytes #350") }
    if !(usize.MAX.rotate_left(0u32) == usize.MAX) { panic("rotate_left #351") }
    if !(usize.MAX.rotate_right(0u32) == usize.MAX) { panic("rotate_right #352") }
    if !(usize.MAX.checked_shl(0u32) == present(usize.MAX)) { panic("checked_shl #353") }
    if !(usize.MAX.checked_shr(0u32) == present(usize.MAX)) { panic("checked_shr #354") }
    if !(usize.MAX.wrapping_shl(0u32) == usize.MAX) { panic("wrapping_shl #355") }
    if !(usize.MAX.wrapping_shr(0u32) == usize.MAX) { panic("wrapping_shr #356") }
    if !(usize.MAX.overflowing_shl(0u32).0 == usize.MAX && usize.MAX.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #357") }
    if !(usize.MAX.overflowing_shr(0u32).0 == usize.MAX && usize.MAX.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #358") }
    if !(usize.MAX.unbounded_shl(0u32) == usize.MAX) { panic("unbounded_shl #359") }
    if !(usize.MAX.unbounded_shr(0u32) == usize.MAX) { panic("unbounded_shr #360") }
}

fn group3() {
    if !(usize.MAX.strict_shl(0u32) == usize.MAX) { panic("strict_shl #361") }
    if !(usize.MAX.strict_shr(0u32) == usize.MAX) { panic("strict_shr #362") }
    if !(unsafe { usize.MAX.unchecked_shl(0u32) } == usize.MAX) { panic("unchecked_shl #363") }
    if !(unsafe { usize.MAX.unchecked_shr(0u32) } == usize.MAX) { panic("unchecked_shr #364") }
    if !(usize.MAX.rotate_left(1u32) == usize.MAX) { panic("rotate_left #365") }
    if !(usize.MAX.rotate_right(1u32) == usize.MAX) { panic("rotate_right #366") }
    if !(usize.MAX.checked_shl(1u32) == present(18446744073709551614usize)) { panic("checked_shl #367") }
    if !(usize.MAX.checked_shr(1u32) == present(9223372036854775807usize)) { panic("checked_shr #368") }
    if !(usize.MAX.wrapping_shl(1u32) == 18446744073709551614usize) { panic("wrapping_shl #369") }
    if !(usize.MAX.wrapping_shr(1u32) == 9223372036854775807usize) { panic("wrapping_shr #370") }
    if !(usize.MAX.overflowing_shl(1u32).0 == 18446744073709551614usize && usize.MAX.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #371") }
    if !(usize.MAX.overflowing_shr(1u32).0 == 9223372036854775807usize && usize.MAX.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #372") }
    if !(usize.MAX.unbounded_shl(1u32) == 18446744073709551614usize) { panic("unbounded_shl #373") }
    if !(usize.MAX.unbounded_shr(1u32) == 9223372036854775807usize) { panic("unbounded_shr #374") }
    if !(usize.MAX.strict_shl(1u32) == 18446744073709551614usize) { panic("strict_shl #375") }
    if !(usize.MAX.strict_shr(1u32) == 9223372036854775807usize) { panic("strict_shr #376") }
    if !(unsafe { usize.MAX.unchecked_shl(1u32) } == 18446744073709551614usize) { panic("unchecked_shl #377") }
    if !(unsafe { usize.MAX.unchecked_shr(1u32) } == 9223372036854775807usize) { panic("unchecked_shr #378") }
    if !(usize.MAX.rotate_left(3u32) == usize.MAX) { panic("rotate_left #379") }
    if !(usize.MAX.rotate_right(3u32) == usize.MAX) { panic("rotate_right #380") }
    if !(usize.MAX.checked_shl(3u32) == present(18446744073709551608usize)) { panic("checked_shl #381") }
    if !(usize.MAX.checked_shr(3u32) == present(2305843009213693951usize)) { panic("checked_shr #382") }
    if !(usize.MAX.wrapping_shl(3u32) == 18446744073709551608usize) { panic("wrapping_shl #383") }
    if !(usize.MAX.wrapping_shr(3u32) == 2305843009213693951usize) { panic("wrapping_shr #384") }
    if !(usize.MAX.overflowing_shl(3u32).0 == 18446744073709551608usize && usize.MAX.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #385") }
    if !(usize.MAX.overflowing_shr(3u32).0 == 2305843009213693951usize && usize.MAX.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #386") }
    if !(usize.MAX.unbounded_shl(3u32) == 18446744073709551608usize) { panic("unbounded_shl #387") }
    if !(usize.MAX.unbounded_shr(3u32) == 2305843009213693951usize) { panic("unbounded_shr #388") }
    if !(usize.MAX.strict_shl(3u32) == 18446744073709551608usize) { panic("strict_shl #389") }
    if !(usize.MAX.strict_shr(3u32) == 2305843009213693951usize) { panic("strict_shr #390") }
    if !(unsafe { usize.MAX.unchecked_shl(3u32) } == 18446744073709551608usize) { panic("unchecked_shl #391") }
    if !(unsafe { usize.MAX.unchecked_shr(3u32) } == 2305843009213693951usize) { panic("unchecked_shr #392") }
    if !(usize.MAX.rotate_left(63u32) == usize.MAX) { panic("rotate_left #393") }
    if !(usize.MAX.rotate_right(63u32) == usize.MAX) { panic("rotate_right #394") }
    if !(usize.MAX.checked_shl(63u32) == present(9223372036854775808usize)) { panic("checked_shl #395") }
    if !(usize.MAX.checked_shr(63u32) == present(1usize)) { panic("checked_shr #396") }
    if !(usize.MAX.wrapping_shl(63u32) == 9223372036854775808usize) { panic("wrapping_shl #397") }
    if !(usize.MAX.wrapping_shr(63u32) == 1usize) { panic("wrapping_shr #398") }
    if !(usize.MAX.overflowing_shl(63u32).0 == 9223372036854775808usize && usize.MAX.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #399") }
    if !(usize.MAX.overflowing_shr(63u32).0 == 1usize && usize.MAX.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #400") }
    if !(usize.MAX.unbounded_shl(63u32) == 9223372036854775808usize) { panic("unbounded_shl #401") }
    if !(usize.MAX.unbounded_shr(63u32) == 1usize) { panic("unbounded_shr #402") }
    if !(usize.MAX.strict_shl(63u32) == 9223372036854775808usize) { panic("strict_shl #403") }
    if !(usize.MAX.strict_shr(63u32) == 1usize) { panic("strict_shr #404") }
    if !(unsafe { usize.MAX.unchecked_shl(63u32) } == 9223372036854775808usize) { panic("unchecked_shl #405") }
    if !(unsafe { usize.MAX.unchecked_shr(63u32) } == 1usize) { panic("unchecked_shr #406") }
    if !(usize.MAX.rotate_left(64u32) == usize.MAX) { panic("rotate_left #407") }
    if !(usize.MAX.rotate_right(64u32) == usize.MAX) { panic("rotate_right #408") }
    if !(missing(usize.MAX.checked_shl(64u32))) { panic("checked_shl #409") }
    if !(missing(usize.MAX.checked_shr(64u32))) { panic("checked_shr #410") }
    if !(usize.MAX.wrapping_shl(64u32) == usize.MAX) { panic("wrapping_shl #411") }
    if !(usize.MAX.wrapping_shr(64u32) == usize.MAX) { panic("wrapping_shr #412") }
    if !(usize.MAX.overflowing_shl(64u32).0 == usize.MAX && usize.MAX.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #413") }
    if !(usize.MAX.overflowing_shr(64u32).0 == usize.MAX && usize.MAX.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #414") }
    if !(usize.MAX.unbounded_shl(64u32) == 0usize) { panic("unbounded_shl #415") }
    if !(usize.MAX.unbounded_shr(64u32) == 0usize) { panic("unbounded_shr #416") }
    if !(usize.MAX.rotate_left(69u32) == usize.MAX) { panic("rotate_left #417") }
    if !(usize.MAX.rotate_right(69u32) == usize.MAX) { panic("rotate_right #418") }
    if !(missing(usize.MAX.checked_shl(69u32))) { panic("checked_shl #419") }
    if !(missing(usize.MAX.checked_shr(69u32))) { panic("checked_shr #420") }
    if !(usize.MAX.wrapping_shl(69u32) == 18446744073709551584usize) { panic("wrapping_shl #421") }
    if !(usize.MAX.wrapping_shr(69u32) == 576460752303423487usize) { panic("wrapping_shr #422") }
    if !(usize.MAX.overflowing_shl(69u32).0 == 18446744073709551584usize && usize.MAX.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #423") }
    if !(usize.MAX.overflowing_shr(69u32).0 == 576460752303423487usize && usize.MAX.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #424") }
    if !(usize.MAX.unbounded_shl(69u32) == 0usize) { panic("unbounded_shl #425") }
    if !(usize.MAX.unbounded_shr(69u32) == 0usize) { panic("unbounded_shr #426") }
    if !(usize.MAX.checked_pow(0u32) == present(1usize)) { panic("checked_pow #427") }
    if !(usize.MAX.wrapping_pow(0u32) == 1usize) { panic("wrapping_pow #428") }
    if !(usize.MAX.overflowing_pow(0u32).0 == 1usize && usize.MAX.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #429") }
    if !(usize.MAX.saturating_pow(0u32) == 1usize) { panic("saturating_pow #430") }
    if !(usize.MAX.pow(0u32) == 1usize) { panic("pow #431") }
    if !(usize.MAX.strict_pow(0u32) == 1usize) { panic("strict_pow #432") }
    if !(usize.MAX.checked_pow(1u32) == present(usize.MAX)) { panic("checked_pow #433") }
    if !(usize.MAX.wrapping_pow(1u32) == usize.MAX) { panic("wrapping_pow #434") }
    if !(usize.MAX.overflowing_pow(1u32).0 == usize.MAX && usize.MAX.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #435") }
    if !(usize.MAX.saturating_pow(1u32) == usize.MAX) { panic("saturating_pow #436") }
    if !(usize.MAX.pow(1u32) == usize.MAX) { panic("pow #437") }
    if !(usize.MAX.strict_pow(1u32) == usize.MAX) { panic("strict_pow #438") }
    if !(missing(usize.MAX.checked_pow(2u32))) { panic("checked_pow #439") }
    if !(usize.MAX.wrapping_pow(2u32) == 1usize) { panic("wrapping_pow #440") }
    if !(usize.MAX.overflowing_pow(2u32).0 == 1usize && usize.MAX.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #441") }
    if !(usize.MAX.saturating_pow(2u32) == usize.MAX) { panic("saturating_pow #442") }
    if !(missing(usize.MAX.checked_pow(3u32))) { panic("checked_pow #443") }
    if !(usize.MAX.wrapping_pow(3u32) == usize.MAX) { panic("wrapping_pow #444") }
    if !(usize.MAX.overflowing_pow(3u32).0 == usize.MAX && usize.MAX.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #445") }
    if !(usize.MAX.saturating_pow(3u32) == usize.MAX) { panic("saturating_pow #446") }
    if !(missing(usize.MAX.checked_pow(63u32))) { panic("checked_pow #447") }
    if !(usize.MAX.wrapping_pow(63u32) == usize.MAX) { panic("wrapping_pow #448") }
    if !(usize.MAX.overflowing_pow(63u32).0 == usize.MAX && usize.MAX.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #449") }
    if !(usize.MAX.saturating_pow(63u32) == usize.MAX) { panic("saturating_pow #450") }
    if !(missing(usize.MAX.checked_pow(64u32))) { panic("checked_pow #451") }
    if !(usize.MAX.wrapping_pow(64u32) == 1usize) { panic("wrapping_pow #452") }
    if !(usize.MAX.overflowing_pow(64u32).0 == 1usize && usize.MAX.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #453") }
    if !(usize.MAX.saturating_pow(64u32) == usize.MAX) { panic("saturating_pow #454") }
    if !(usize.MAX.ilog2() == 63u32) { panic("ilog2 #455") }
    if !(usize.MAX.ilog10() == 19u32) { panic("ilog10 #456") }
    if !(usize.MAX.checked_ilog2() == present(63u32)) { panic("checked_ilog2 #457") }
    if !(usize.MAX.checked_ilog10() == present(19u32)) { panic("checked_ilog10 #458") }
    if !(usize.MAX.ilog(2usize) == 63u32) { panic("ilog #459") }
    if !(usize.MAX.checked_ilog(2usize) == present(63u32)) { panic("checked_ilog #460") }
    if !(usize.MAX.ilog(3usize) == 40u32) { panic("ilog #461") }
    if !(usize.MAX.checked_ilog(3usize) == present(40u32)) { panic("checked_ilog #462") }
    if !(usize.MAX.ilog(7usize) == 22u32) { panic("ilog #463") }
    if !(usize.MAX.checked_ilog(7usize) == present(22u32)) { panic("checked_ilog #464") }
    if !(missing(usize.MAX.checked_ilog(1usize))) { panic("checked_ilog #465") }
    if !(usize.MAX.isqrt() == 4294967295usize) { panic("isqrt #466") }
    if !(usize.MAX.checked_isqrt() == present(4294967295usize)) { panic("checked_isqrt #467") }
    if !(usize.MAX.is_power_of_two() == false) { panic("is_power_of_two #468") }
    if !(missing(usize.MAX.checked_next_power_of_two())) { panic("checked_next_power_of_two #469") }
    if !(usize.MAX.div_ceil(1usize) == usize.MAX) { panic("div_ceil #470") }
    if !(usize.MAX.checked_next_multiple_of(1usize) == present(usize.MAX)) { panic("checked_next_multiple_of #471") }
    if !(usize.MAX.next_multiple_of(1usize) == usize.MAX) { panic("next_multiple_of #472") }
    if !(usize.MAX.is_multiple_of(1usize) == true) { panic("is_multiple_of #473") }
    if !(usize.MAX.div_ceil(3usize) == 6148914691236517205usize) { panic("div_ceil #474") }
    if !(usize.MAX.checked_next_multiple_of(3usize) == present(usize.MAX)) { panic("checked_next_multiple_of #475") }
    if !(usize.MAX.next_multiple_of(3usize) == usize.MAX) { panic("next_multiple_of #476") }
    if !(usize.MAX.is_multiple_of(3usize) == true) { panic("is_multiple_of #477") }
    if !(usize.MAX.div_ceil(7usize) == 2635249153387078803usize) { panic("div_ceil #478") }
    if !(missing(usize.MAX.checked_next_multiple_of(7usize))) { panic("checked_next_multiple_of #479") }
    if !(usize.MAX.is_multiple_of(7usize) == false) { panic("is_multiple_of #480") }
}

fn group4() {
    if !(usize.MAX.is_multiple_of(0usize) == false) { panic("is_multiple_of #481") }
    if !(missing(usize.MAX.checked_next_multiple_of(0usize))) { panic("checked_next_multiple_of #482") }
    if !(usize.MAX.highest_one() == present(63u32)) { panic("highest_one #483") }
    if !(usize.MAX.lowest_one() == present(0u32)) { panic("lowest_one #484") }
    if !(usize.MAX.isolate_highest_one() == 9223372036854775808usize) { panic("isolate_highest_one #485") }
    if !(usize.MAX.isolate_lowest_one() == 1usize) { panic("isolate_lowest_one #486") }
    if !(usize.MAX.bit_width() == 64u32) { panic("bit_width #487") }
    if !(0usize.checked_neg() == present(0usize)) { panic("checked_neg #488") }
    if !(0usize.wrapping_neg() == 0usize) { panic("wrapping_neg #489") }
    if !(0usize.overflowing_neg().0 == 0usize && 0usize.overflowing_neg().1 == false) { panic("overflowing_neg #490") }
    if !(0usize.strict_neg() == 0usize) { panic("strict_neg #491") }
    if !(0usize.cast_signed() == 0isize) { panic("cast_signed #492") }
    if !(0usize.count_ones() == 0u32) { panic("count_ones #493") }
    if !(0usize.count_zeros() == 64u32) { panic("count_zeros #494") }
    if !(0usize.leading_zeros() == 64u32) { panic("leading_zeros #495") }
    if !(0usize.trailing_zeros() == 64u32) { panic("trailing_zeros #496") }
    if !(0usize.leading_ones() == 0u32) { panic("leading_ones #497") }
    if !(0usize.trailing_ones() == 0u32) { panic("trailing_ones #498") }
    if !(0usize.reverse_bits() == 0usize) { panic("reverse_bits #499") }
    if !(0usize.swap_bytes() == 0usize) { panic("swap_bytes #500") }
    if !(0usize.to_be() == 0usize) { panic("to_be #501") }
    if !(0usize.to_le() == 0usize) { panic("to_le #502") }
    if !(usize.from_be(0usize) == 0usize) { panic("from_be #503") }
    if !(usize.from_le(0usize) == 0usize) { panic("from_le #504") }
    if !(0usize.to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #505") }
    if !(0usize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #506") }
    if !(0usize.to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #507") }
    if !(usize.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 0usize) { panic("from_le_bytes #508") }
    if !(usize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 0usize) { panic("from_be_bytes #509") }
    if !(usize.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 0usize) { panic("from_ne_bytes #510") }
    if !(0usize.rotate_left(0u32) == 0usize) { panic("rotate_left #511") }
    if !(0usize.rotate_right(0u32) == 0usize) { panic("rotate_right #512") }
    if !(0usize.checked_shl(0u32) == present(0usize)) { panic("checked_shl #513") }
    if !(0usize.checked_shr(0u32) == present(0usize)) { panic("checked_shr #514") }
    if !(0usize.wrapping_shl(0u32) == 0usize) { panic("wrapping_shl #515") }
    if !(0usize.wrapping_shr(0u32) == 0usize) { panic("wrapping_shr #516") }
    if !(0usize.overflowing_shl(0u32).0 == 0usize && 0usize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #517") }
    if !(0usize.overflowing_shr(0u32).0 == 0usize && 0usize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #518") }
    if !(0usize.unbounded_shl(0u32) == 0usize) { panic("unbounded_shl #519") }
    if !(0usize.unbounded_shr(0u32) == 0usize) { panic("unbounded_shr #520") }
    if !(0usize.strict_shl(0u32) == 0usize) { panic("strict_shl #521") }
    if !(0usize.strict_shr(0u32) == 0usize) { panic("strict_shr #522") }
    if !(unsafe { 0usize.unchecked_shl(0u32) } == 0usize) { panic("unchecked_shl #523") }
    if !(unsafe { 0usize.unchecked_shr(0u32) } == 0usize) { panic("unchecked_shr #524") }
    if !(0usize.rotate_left(1u32) == 0usize) { panic("rotate_left #525") }
    if !(0usize.rotate_right(1u32) == 0usize) { panic("rotate_right #526") }
    if !(0usize.checked_shl(1u32) == present(0usize)) { panic("checked_shl #527") }
    if !(0usize.checked_shr(1u32) == present(0usize)) { panic("checked_shr #528") }
    if !(0usize.wrapping_shl(1u32) == 0usize) { panic("wrapping_shl #529") }
    if !(0usize.wrapping_shr(1u32) == 0usize) { panic("wrapping_shr #530") }
    if !(0usize.overflowing_shl(1u32).0 == 0usize && 0usize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #531") }
    if !(0usize.overflowing_shr(1u32).0 == 0usize && 0usize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #532") }
    if !(0usize.unbounded_shl(1u32) == 0usize) { panic("unbounded_shl #533") }
    if !(0usize.unbounded_shr(1u32) == 0usize) { panic("unbounded_shr #534") }
    if !(0usize.strict_shl(1u32) == 0usize) { panic("strict_shl #535") }
    if !(0usize.strict_shr(1u32) == 0usize) { panic("strict_shr #536") }
    if !(unsafe { 0usize.unchecked_shl(1u32) } == 0usize) { panic("unchecked_shl #537") }
    if !(unsafe { 0usize.unchecked_shr(1u32) } == 0usize) { panic("unchecked_shr #538") }
    if !(0usize.rotate_left(3u32) == 0usize) { panic("rotate_left #539") }
    if !(0usize.rotate_right(3u32) == 0usize) { panic("rotate_right #540") }
    if !(0usize.checked_shl(3u32) == present(0usize)) { panic("checked_shl #541") }
    if !(0usize.checked_shr(3u32) == present(0usize)) { panic("checked_shr #542") }
    if !(0usize.wrapping_shl(3u32) == 0usize) { panic("wrapping_shl #543") }
    if !(0usize.wrapping_shr(3u32) == 0usize) { panic("wrapping_shr #544") }
    if !(0usize.overflowing_shl(3u32).0 == 0usize && 0usize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #545") }
    if !(0usize.overflowing_shr(3u32).0 == 0usize && 0usize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #546") }
    if !(0usize.unbounded_shl(3u32) == 0usize) { panic("unbounded_shl #547") }
    if !(0usize.unbounded_shr(3u32) == 0usize) { panic("unbounded_shr #548") }
    if !(0usize.strict_shl(3u32) == 0usize) { panic("strict_shl #549") }
    if !(0usize.strict_shr(3u32) == 0usize) { panic("strict_shr #550") }
    if !(unsafe { 0usize.unchecked_shl(3u32) } == 0usize) { panic("unchecked_shl #551") }
    if !(unsafe { 0usize.unchecked_shr(3u32) } == 0usize) { panic("unchecked_shr #552") }
    if !(0usize.rotate_left(63u32) == 0usize) { panic("rotate_left #553") }
    if !(0usize.rotate_right(63u32) == 0usize) { panic("rotate_right #554") }
    if !(0usize.checked_shl(63u32) == present(0usize)) { panic("checked_shl #555") }
    if !(0usize.checked_shr(63u32) == present(0usize)) { panic("checked_shr #556") }
    if !(0usize.wrapping_shl(63u32) == 0usize) { panic("wrapping_shl #557") }
    if !(0usize.wrapping_shr(63u32) == 0usize) { panic("wrapping_shr #558") }
    if !(0usize.overflowing_shl(63u32).0 == 0usize && 0usize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #559") }
    if !(0usize.overflowing_shr(63u32).0 == 0usize && 0usize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #560") }
    if !(0usize.unbounded_shl(63u32) == 0usize) { panic("unbounded_shl #561") }
    if !(0usize.unbounded_shr(63u32) == 0usize) { panic("unbounded_shr #562") }
    if !(0usize.strict_shl(63u32) == 0usize) { panic("strict_shl #563") }
    if !(0usize.strict_shr(63u32) == 0usize) { panic("strict_shr #564") }
    if !(unsafe { 0usize.unchecked_shl(63u32) } == 0usize) { panic("unchecked_shl #565") }
    if !(unsafe { 0usize.unchecked_shr(63u32) } == 0usize) { panic("unchecked_shr #566") }
    if !(0usize.rotate_left(64u32) == 0usize) { panic("rotate_left #567") }
    if !(0usize.rotate_right(64u32) == 0usize) { panic("rotate_right #568") }
    if !(missing(0usize.checked_shl(64u32))) { panic("checked_shl #569") }
    if !(missing(0usize.checked_shr(64u32))) { panic("checked_shr #570") }
    if !(0usize.wrapping_shl(64u32) == 0usize) { panic("wrapping_shl #571") }
    if !(0usize.wrapping_shr(64u32) == 0usize) { panic("wrapping_shr #572") }
    if !(0usize.overflowing_shl(64u32).0 == 0usize && 0usize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #573") }
    if !(0usize.overflowing_shr(64u32).0 == 0usize && 0usize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #574") }
    if !(0usize.unbounded_shl(64u32) == 0usize) { panic("unbounded_shl #575") }
    if !(0usize.unbounded_shr(64u32) == 0usize) { panic("unbounded_shr #576") }
    if !(0usize.rotate_left(69u32) == 0usize) { panic("rotate_left #577") }
    if !(0usize.rotate_right(69u32) == 0usize) { panic("rotate_right #578") }
    if !(missing(0usize.checked_shl(69u32))) { panic("checked_shl #579") }
    if !(missing(0usize.checked_shr(69u32))) { panic("checked_shr #580") }
    if !(0usize.wrapping_shl(69u32) == 0usize) { panic("wrapping_shl #581") }
    if !(0usize.wrapping_shr(69u32) == 0usize) { panic("wrapping_shr #582") }
    if !(0usize.overflowing_shl(69u32).0 == 0usize && 0usize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #583") }
    if !(0usize.overflowing_shr(69u32).0 == 0usize && 0usize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #584") }
    if !(0usize.unbounded_shl(69u32) == 0usize) { panic("unbounded_shl #585") }
    if !(0usize.unbounded_shr(69u32) == 0usize) { panic("unbounded_shr #586") }
    if !(0usize.checked_pow(0u32) == present(1usize)) { panic("checked_pow #587") }
    if !(0usize.wrapping_pow(0u32) == 1usize) { panic("wrapping_pow #588") }
    if !(0usize.overflowing_pow(0u32).0 == 1usize && 0usize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #589") }
    if !(0usize.saturating_pow(0u32) == 1usize) { panic("saturating_pow #590") }
    if !(0usize.pow(0u32) == 1usize) { panic("pow #591") }
    if !(0usize.strict_pow(0u32) == 1usize) { panic("strict_pow #592") }
    if !(0usize.checked_pow(1u32) == present(0usize)) { panic("checked_pow #593") }
    if !(0usize.wrapping_pow(1u32) == 0usize) { panic("wrapping_pow #594") }
    if !(0usize.overflowing_pow(1u32).0 == 0usize && 0usize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #595") }
    if !(0usize.saturating_pow(1u32) == 0usize) { panic("saturating_pow #596") }
    if !(0usize.pow(1u32) == 0usize) { panic("pow #597") }
    if !(0usize.strict_pow(1u32) == 0usize) { panic("strict_pow #598") }
    if !(0usize.checked_pow(2u32) == present(0usize)) { panic("checked_pow #599") }
    if !(0usize.wrapping_pow(2u32) == 0usize) { panic("wrapping_pow #600") }
}

fn group5() {
    if !(0usize.overflowing_pow(2u32).0 == 0usize && 0usize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #601") }
    if !(0usize.saturating_pow(2u32) == 0usize) { panic("saturating_pow #602") }
    if !(0usize.pow(2u32) == 0usize) { panic("pow #603") }
    if !(0usize.strict_pow(2u32) == 0usize) { panic("strict_pow #604") }
    if !(0usize.checked_pow(3u32) == present(0usize)) { panic("checked_pow #605") }
    if !(0usize.wrapping_pow(3u32) == 0usize) { panic("wrapping_pow #606") }
    if !(0usize.overflowing_pow(3u32).0 == 0usize && 0usize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #607") }
    if !(0usize.saturating_pow(3u32) == 0usize) { panic("saturating_pow #608") }
    if !(0usize.pow(3u32) == 0usize) { panic("pow #609") }
    if !(0usize.strict_pow(3u32) == 0usize) { panic("strict_pow #610") }
    if !(0usize.checked_pow(63u32) == present(0usize)) { panic("checked_pow #611") }
    if !(0usize.wrapping_pow(63u32) == 0usize) { panic("wrapping_pow #612") }
    if !(0usize.overflowing_pow(63u32).0 == 0usize && 0usize.overflowing_pow(63u32).1 == false) { panic("overflowing_pow #613") }
    if !(0usize.saturating_pow(63u32) == 0usize) { panic("saturating_pow #614") }
    if !(0usize.pow(63u32) == 0usize) { panic("pow #615") }
    if !(0usize.strict_pow(63u32) == 0usize) { panic("strict_pow #616") }
    if !(0usize.checked_pow(64u32) == present(0usize)) { panic("checked_pow #617") }
    if !(0usize.wrapping_pow(64u32) == 0usize) { panic("wrapping_pow #618") }
    if !(0usize.overflowing_pow(64u32).0 == 0usize && 0usize.overflowing_pow(64u32).1 == false) { panic("overflowing_pow #619") }
    if !(0usize.saturating_pow(64u32) == 0usize) { panic("saturating_pow #620") }
    if !(0usize.pow(64u32) == 0usize) { panic("pow #621") }
    if !(0usize.strict_pow(64u32) == 0usize) { panic("strict_pow #622") }
    if !(missing(0usize.checked_ilog2())) { panic("checked_ilog2 #623") }
    if !(missing(0usize.checked_ilog10())) { panic("checked_ilog10 #624") }
    if !(missing(0usize.checked_ilog(2usize))) { panic("checked_ilog #625") }
    if !(0usize.isqrt() == 0usize) { panic("isqrt #626") }
    if !(0usize.checked_isqrt() == present(0usize)) { panic("checked_isqrt #627") }
    if !(0usize.is_power_of_two() == false) { panic("is_power_of_two #628") }
    if !(0usize.checked_next_power_of_two() == present(1usize)) { panic("checked_next_power_of_two #629") }
    if !(0usize.next_power_of_two() == 1usize) { panic("next_power_of_two #630") }
    if !(0usize.div_ceil(1usize) == 0usize) { panic("div_ceil #631") }
    if !(0usize.checked_next_multiple_of(1usize) == present(0usize)) { panic("checked_next_multiple_of #632") }
    if !(0usize.next_multiple_of(1usize) == 0usize) { panic("next_multiple_of #633") }
    if !(0usize.is_multiple_of(1usize) == true) { panic("is_multiple_of #634") }
    if !(0usize.div_ceil(3usize) == 0usize) { panic("div_ceil #635") }
    if !(0usize.checked_next_multiple_of(3usize) == present(0usize)) { panic("checked_next_multiple_of #636") }
    if !(0usize.next_multiple_of(3usize) == 0usize) { panic("next_multiple_of #637") }
    if !(0usize.is_multiple_of(3usize) == true) { panic("is_multiple_of #638") }
    if !(0usize.div_ceil(7usize) == 0usize) { panic("div_ceil #639") }
    if !(0usize.checked_next_multiple_of(7usize) == present(0usize)) { panic("checked_next_multiple_of #640") }
    if !(0usize.next_multiple_of(7usize) == 0usize) { panic("next_multiple_of #641") }
    if !(0usize.is_multiple_of(7usize) == true) { panic("is_multiple_of #642") }
    if !(0usize.is_multiple_of(0usize) == true) { panic("is_multiple_of #643") }
    if !(missing(0usize.checked_next_multiple_of(0usize))) { panic("checked_next_multiple_of #644") }
    if !(missing(0usize.highest_one())) { panic("highest_one #645") }
    if !(missing(0usize.lowest_one())) { panic("lowest_one #646") }
    if !(0usize.isolate_highest_one() == 0usize) { panic("isolate_highest_one #647") }
    if !(0usize.isolate_lowest_one() == 0usize) { panic("isolate_lowest_one #648") }
    if !(0usize.bit_width() == 0u32) { panic("bit_width #649") }
    if !(missing(1000usize.checked_neg())) { panic("checked_neg #650") }
    if !(1000usize.wrapping_neg() == 18446744073709550616usize) { panic("wrapping_neg #651") }
    if !(1000usize.overflowing_neg().0 == 18446744073709550616usize && 1000usize.overflowing_neg().1 == true) { panic("overflowing_neg #652") }
    if !(1000usize.cast_signed() == 1000isize) { panic("cast_signed #653") }
    if !(1000usize.count_ones() == 6u32) { panic("count_ones #654") }
    if !(1000usize.count_zeros() == 58u32) { panic("count_zeros #655") }
    if !(1000usize.leading_zeros() == 54u32) { panic("leading_zeros #656") }
    if !(1000usize.trailing_zeros() == 3u32) { panic("trailing_zeros #657") }
    if !(1000usize.leading_ones() == 0u32) { panic("leading_ones #658") }
    if !(1000usize.trailing_ones() == 0u32) { panic("trailing_ones #659") }
    if !(1000usize.reverse_bits() == 1711367858400788480usize) { panic("reverse_bits #660") }
    if !(1000usize.swap_bytes() == 16718206241729413120usize) { panic("swap_bytes #661") }
    if !(1000usize.to_be() == 16718206241729413120usize) { panic("to_be #662") }
    if !(1000usize.to_le() == 1000usize) { panic("to_le #663") }
    if !(usize.from_be(1000usize) == 16718206241729413120usize) { panic("from_be #664") }
    if !(usize.from_le(1000usize) == 1000usize) { panic("from_le #665") }
    if !(1000usize.to_le_bytes() == [232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #666") }
    if !(1000usize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 3u8, 232u8]) { panic("to_be_bytes #667") }
    if !(1000usize.to_ne_bytes() == [232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #668") }
    if !(usize.from_le_bytes([232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1000usize) { panic("from_le_bytes #669") }
    if !(usize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 3u8, 232u8]) == 1000usize) { panic("from_be_bytes #670") }
    if !(usize.from_ne_bytes([232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1000usize) { panic("from_ne_bytes #671") }
    if !(1000usize.rotate_left(0u32) == 1000usize) { panic("rotate_left #672") }
    if !(1000usize.rotate_right(0u32) == 1000usize) { panic("rotate_right #673") }
    if !(1000usize.checked_shl(0u32) == present(1000usize)) { panic("checked_shl #674") }
    if !(1000usize.checked_shr(0u32) == present(1000usize)) { panic("checked_shr #675") }
    if !(1000usize.wrapping_shl(0u32) == 1000usize) { panic("wrapping_shl #676") }
    if !(1000usize.wrapping_shr(0u32) == 1000usize) { panic("wrapping_shr #677") }
    if !(1000usize.overflowing_shl(0u32).0 == 1000usize && 1000usize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #678") }
    if !(1000usize.overflowing_shr(0u32).0 == 1000usize && 1000usize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #679") }
    if !(1000usize.unbounded_shl(0u32) == 1000usize) { panic("unbounded_shl #680") }
    if !(1000usize.unbounded_shr(0u32) == 1000usize) { panic("unbounded_shr #681") }
    if !(1000usize.strict_shl(0u32) == 1000usize) { panic("strict_shl #682") }
    if !(1000usize.strict_shr(0u32) == 1000usize) { panic("strict_shr #683") }
    if !(unsafe { 1000usize.unchecked_shl(0u32) } == 1000usize) { panic("unchecked_shl #684") }
    if !(unsafe { 1000usize.unchecked_shr(0u32) } == 1000usize) { panic("unchecked_shr #685") }
    if !(1000usize.rotate_left(1u32) == 2000usize) { panic("rotate_left #686") }
    if !(1000usize.rotate_right(1u32) == 500usize) { panic("rotate_right #687") }
    if !(1000usize.checked_shl(1u32) == present(2000usize)) { panic("checked_shl #688") }
    if !(1000usize.checked_shr(1u32) == present(500usize)) { panic("checked_shr #689") }
    if !(1000usize.wrapping_shl(1u32) == 2000usize) { panic("wrapping_shl #690") }
    if !(1000usize.wrapping_shr(1u32) == 500usize) { panic("wrapping_shr #691") }
    if !(1000usize.overflowing_shl(1u32).0 == 2000usize && 1000usize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #692") }
    if !(1000usize.overflowing_shr(1u32).0 == 500usize && 1000usize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #693") }
    if !(1000usize.unbounded_shl(1u32) == 2000usize) { panic("unbounded_shl #694") }
    if !(1000usize.unbounded_shr(1u32) == 500usize) { panic("unbounded_shr #695") }
    if !(1000usize.strict_shl(1u32) == 2000usize) { panic("strict_shl #696") }
    if !(1000usize.strict_shr(1u32) == 500usize) { panic("strict_shr #697") }
    if !(unsafe { 1000usize.unchecked_shl(1u32) } == 2000usize) { panic("unchecked_shl #698") }
    if !(unsafe { 1000usize.unchecked_shr(1u32) } == 500usize) { panic("unchecked_shr #699") }
    if !(1000usize.rotate_left(3u32) == 8000usize) { panic("rotate_left #700") }
    if !(1000usize.rotate_right(3u32) == 125usize) { panic("rotate_right #701") }
    if !(1000usize.checked_shl(3u32) == present(8000usize)) { panic("checked_shl #702") }
    if !(1000usize.checked_shr(3u32) == present(125usize)) { panic("checked_shr #703") }
    if !(1000usize.wrapping_shl(3u32) == 8000usize) { panic("wrapping_shl #704") }
    if !(1000usize.wrapping_shr(3u32) == 125usize) { panic("wrapping_shr #705") }
    if !(1000usize.overflowing_shl(3u32).0 == 8000usize && 1000usize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #706") }
    if !(1000usize.overflowing_shr(3u32).0 == 125usize && 1000usize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #707") }
    if !(1000usize.unbounded_shl(3u32) == 8000usize) { panic("unbounded_shl #708") }
    if !(1000usize.unbounded_shr(3u32) == 125usize) { panic("unbounded_shr #709") }
    if !(1000usize.strict_shl(3u32) == 8000usize) { panic("strict_shl #710") }
    if !(1000usize.strict_shr(3u32) == 125usize) { panic("strict_shr #711") }
    if !(unsafe { 1000usize.unchecked_shl(3u32) } == 8000usize) { panic("unchecked_shl #712") }
    if !(unsafe { 1000usize.unchecked_shr(3u32) } == 125usize) { panic("unchecked_shr #713") }
    if !(1000usize.rotate_left(63u32) == 500usize) { panic("rotate_left #714") }
    if !(1000usize.rotate_right(63u32) == 2000usize) { panic("rotate_right #715") }
    if !(1000usize.checked_shl(63u32) == present(0usize)) { panic("checked_shl #716") }
    if !(1000usize.checked_shr(63u32) == present(0usize)) { panic("checked_shr #717") }
    if !(1000usize.wrapping_shl(63u32) == 0usize) { panic("wrapping_shl #718") }
    if !(1000usize.wrapping_shr(63u32) == 0usize) { panic("wrapping_shr #719") }
    if !(1000usize.overflowing_shl(63u32).0 == 0usize && 1000usize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #720") }
}

fn group6() {
    if !(1000usize.overflowing_shr(63u32).0 == 0usize && 1000usize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #721") }
    if !(1000usize.unbounded_shl(63u32) == 0usize) { panic("unbounded_shl #722") }
    if !(1000usize.unbounded_shr(63u32) == 0usize) { panic("unbounded_shr #723") }
    if !(1000usize.strict_shl(63u32) == 0usize) { panic("strict_shl #724") }
    if !(1000usize.strict_shr(63u32) == 0usize) { panic("strict_shr #725") }
    if !(unsafe { 1000usize.unchecked_shl(63u32) } == 0usize) { panic("unchecked_shl #726") }
    if !(unsafe { 1000usize.unchecked_shr(63u32) } == 0usize) { panic("unchecked_shr #727") }
    if !(1000usize.rotate_left(64u32) == 1000usize) { panic("rotate_left #728") }
    if !(1000usize.rotate_right(64u32) == 1000usize) { panic("rotate_right #729") }
    if !(missing(1000usize.checked_shl(64u32))) { panic("checked_shl #730") }
    if !(missing(1000usize.checked_shr(64u32))) { panic("checked_shr #731") }
    if !(1000usize.wrapping_shl(64u32) == 1000usize) { panic("wrapping_shl #732") }
    if !(1000usize.wrapping_shr(64u32) == 1000usize) { panic("wrapping_shr #733") }
    if !(1000usize.overflowing_shl(64u32).0 == 1000usize && 1000usize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #734") }
    if !(1000usize.overflowing_shr(64u32).0 == 1000usize && 1000usize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #735") }
    if !(1000usize.unbounded_shl(64u32) == 0usize) { panic("unbounded_shl #736") }
    if !(1000usize.unbounded_shr(64u32) == 0usize) { panic("unbounded_shr #737") }
    if !(1000usize.rotate_left(69u32) == 32000usize) { panic("rotate_left #738") }
    if !(1000usize.rotate_right(69u32) == 4611686018427387935usize) { panic("rotate_right #739") }
    if !(missing(1000usize.checked_shl(69u32))) { panic("checked_shl #740") }
    if !(missing(1000usize.checked_shr(69u32))) { panic("checked_shr #741") }
    if !(1000usize.wrapping_shl(69u32) == 32000usize) { panic("wrapping_shl #742") }
    if !(1000usize.wrapping_shr(69u32) == 31usize) { panic("wrapping_shr #743") }
    if !(1000usize.overflowing_shl(69u32).0 == 32000usize && 1000usize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #744") }
    if !(1000usize.overflowing_shr(69u32).0 == 31usize && 1000usize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #745") }
    if !(1000usize.unbounded_shl(69u32) == 0usize) { panic("unbounded_shl #746") }
    if !(1000usize.unbounded_shr(69u32) == 0usize) { panic("unbounded_shr #747") }
    if !(1000usize.checked_pow(0u32) == present(1usize)) { panic("checked_pow #748") }
    if !(1000usize.wrapping_pow(0u32) == 1usize) { panic("wrapping_pow #749") }
    if !(1000usize.overflowing_pow(0u32).0 == 1usize && 1000usize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #750") }
    if !(1000usize.saturating_pow(0u32) == 1usize) { panic("saturating_pow #751") }
    if !(1000usize.pow(0u32) == 1usize) { panic("pow #752") }
    if !(1000usize.strict_pow(0u32) == 1usize) { panic("strict_pow #753") }
    if !(1000usize.checked_pow(1u32) == present(1000usize)) { panic("checked_pow #754") }
    if !(1000usize.wrapping_pow(1u32) == 1000usize) { panic("wrapping_pow #755") }
    if !(1000usize.overflowing_pow(1u32).0 == 1000usize && 1000usize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #756") }
    if !(1000usize.saturating_pow(1u32) == 1000usize) { panic("saturating_pow #757") }
    if !(1000usize.pow(1u32) == 1000usize) { panic("pow #758") }
    if !(1000usize.strict_pow(1u32) == 1000usize) { panic("strict_pow #759") }
    if !(1000usize.checked_pow(2u32) == present(1000000usize)) { panic("checked_pow #760") }
    if !(1000usize.wrapping_pow(2u32) == 1000000usize) { panic("wrapping_pow #761") }
    if !(1000usize.overflowing_pow(2u32).0 == 1000000usize && 1000usize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #762") }
    if !(1000usize.saturating_pow(2u32) == 1000000usize) { panic("saturating_pow #763") }
    if !(1000usize.pow(2u32) == 1000000usize) { panic("pow #764") }
    if !(1000usize.strict_pow(2u32) == 1000000usize) { panic("strict_pow #765") }
    if !(1000usize.checked_pow(3u32) == present(1000000000usize)) { panic("checked_pow #766") }
    if !(1000usize.wrapping_pow(3u32) == 1000000000usize) { panic("wrapping_pow #767") }
    if !(1000usize.overflowing_pow(3u32).0 == 1000000000usize && 1000usize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #768") }
    if !(1000usize.saturating_pow(3u32) == 1000000000usize) { panic("saturating_pow #769") }
    if !(1000usize.pow(3u32) == 1000000000usize) { panic("pow #770") }
    if !(1000usize.strict_pow(3u32) == 1000000000usize) { panic("strict_pow #771") }
    if !(missing(1000usize.checked_pow(63u32))) { panic("checked_pow #772") }
    if !(1000usize.wrapping_pow(63u32) == 0usize) { panic("wrapping_pow #773") }
    if !(1000usize.overflowing_pow(63u32).0 == 0usize && 1000usize.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #774") }
    if !(1000usize.saturating_pow(63u32) == usize.MAX) { panic("saturating_pow #775") }
    if !(missing(1000usize.checked_pow(64u32))) { panic("checked_pow #776") }
    if !(1000usize.wrapping_pow(64u32) == 0usize) { panic("wrapping_pow #777") }
    if !(1000usize.overflowing_pow(64u32).0 == 0usize && 1000usize.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #778") }
    if !(1000usize.saturating_pow(64u32) == usize.MAX) { panic("saturating_pow #779") }
    if !(1000usize.ilog2() == 9u32) { panic("ilog2 #780") }
    if !(1000usize.ilog10() == 3u32) { panic("ilog10 #781") }
    if !(1000usize.checked_ilog2() == present(9u32)) { panic("checked_ilog2 #782") }
    if !(1000usize.checked_ilog10() == present(3u32)) { panic("checked_ilog10 #783") }
    if !(1000usize.ilog(2usize) == 9u32) { panic("ilog #784") }
    if !(1000usize.checked_ilog(2usize) == present(9u32)) { panic("checked_ilog #785") }
    if !(1000usize.ilog(3usize) == 6u32) { panic("ilog #786") }
    if !(1000usize.checked_ilog(3usize) == present(6u32)) { panic("checked_ilog #787") }
    if !(1000usize.ilog(7usize) == 3u32) { panic("ilog #788") }
    if !(1000usize.checked_ilog(7usize) == present(3u32)) { panic("checked_ilog #789") }
    if !(missing(1000usize.checked_ilog(1usize))) { panic("checked_ilog #790") }
    if !(1000usize.isqrt() == 31usize) { panic("isqrt #791") }
    if !(1000usize.checked_isqrt() == present(31usize)) { panic("checked_isqrt #792") }
    if !(1000usize.is_power_of_two() == false) { panic("is_power_of_two #793") }
    if !(1000usize.checked_next_power_of_two() == present(1024usize)) { panic("checked_next_power_of_two #794") }
    if !(1000usize.next_power_of_two() == 1024usize) { panic("next_power_of_two #795") }
    if !(1000usize.div_ceil(1usize) == 1000usize) { panic("div_ceil #796") }
    if !(1000usize.checked_next_multiple_of(1usize) == present(1000usize)) { panic("checked_next_multiple_of #797") }
    if !(1000usize.next_multiple_of(1usize) == 1000usize) { panic("next_multiple_of #798") }
    if !(1000usize.is_multiple_of(1usize) == true) { panic("is_multiple_of #799") }
    if !(1000usize.div_ceil(3usize) == 334usize) { panic("div_ceil #800") }
    if !(1000usize.checked_next_multiple_of(3usize) == present(1002usize)) { panic("checked_next_multiple_of #801") }
    if !(1000usize.next_multiple_of(3usize) == 1002usize) { panic("next_multiple_of #802") }
    if !(1000usize.is_multiple_of(3usize) == false) { panic("is_multiple_of #803") }
    if !(1000usize.div_ceil(7usize) == 143usize) { panic("div_ceil #804") }
    if !(1000usize.checked_next_multiple_of(7usize) == present(1001usize)) { panic("checked_next_multiple_of #805") }
    if !(1000usize.next_multiple_of(7usize) == 1001usize) { panic("next_multiple_of #806") }
    if !(1000usize.is_multiple_of(7usize) == false) { panic("is_multiple_of #807") }
    if !(1000usize.is_multiple_of(0usize) == false) { panic("is_multiple_of #808") }
    if !(missing(1000usize.checked_next_multiple_of(0usize))) { panic("checked_next_multiple_of #809") }
    if !(1000usize.highest_one() == present(9u32)) { panic("highest_one #810") }
    if !(1000usize.lowest_one() == present(3u32)) { panic("lowest_one #811") }
    if !(1000usize.isolate_highest_one() == 512usize) { panic("isolate_highest_one #812") }
    if !(1000usize.isolate_lowest_one() == 8usize) { panic("isolate_lowest_one #813") }
    if !(1000usize.bit_width() == 10u32) { panic("bit_width #814") }
    if !(missing(7usize.checked_neg())) { panic("checked_neg #815") }
    if !(7usize.wrapping_neg() == 18446744073709551609usize) { panic("wrapping_neg #816") }
    if !(7usize.overflowing_neg().0 == 18446744073709551609usize && 7usize.overflowing_neg().1 == true) { panic("overflowing_neg #817") }
    if !(7usize.cast_signed() == 7isize) { panic("cast_signed #818") }
    if !(7usize.count_ones() == 3u32) { panic("count_ones #819") }
    if !(7usize.count_zeros() == 61u32) { panic("count_zeros #820") }
    if !(7usize.leading_zeros() == 61u32) { panic("leading_zeros #821") }
    if !(7usize.trailing_zeros() == 0u32) { panic("trailing_zeros #822") }
    if !(7usize.leading_ones() == 0u32) { panic("leading_ones #823") }
    if !(7usize.trailing_ones() == 3u32) { panic("trailing_ones #824") }
    if !(7usize.reverse_bits() == 16140901064495857664usize) { panic("reverse_bits #825") }
    if !(7usize.swap_bytes() == 504403158265495552usize) { panic("swap_bytes #826") }
    if !(7usize.to_be() == 504403158265495552usize) { panic("to_be #827") }
    if !(7usize.to_le() == 7usize) { panic("to_le #828") }
    if !(usize.from_be(7usize) == 504403158265495552usize) { panic("from_be #829") }
    if !(usize.from_le(7usize) == 7usize) { panic("from_le #830") }
    if !(7usize.to_le_bytes() == [7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #831") }
    if !(7usize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 7u8]) { panic("to_be_bytes #832") }
    if !(7usize.to_ne_bytes() == [7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #833") }
    if !(usize.from_le_bytes([7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 7usize) { panic("from_le_bytes #834") }
    if !(usize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 7u8]) == 7usize) { panic("from_be_bytes #835") }
    if !(usize.from_ne_bytes([7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 7usize) { panic("from_ne_bytes #836") }
    if !(7usize.rotate_left(0u32) == 7usize) { panic("rotate_left #837") }
    if !(7usize.rotate_right(0u32) == 7usize) { panic("rotate_right #838") }
    if !(7usize.checked_shl(0u32) == present(7usize)) { panic("checked_shl #839") }
    if !(7usize.checked_shr(0u32) == present(7usize)) { panic("checked_shr #840") }
}

fn group7() {
    if !(7usize.wrapping_shl(0u32) == 7usize) { panic("wrapping_shl #841") }
    if !(7usize.wrapping_shr(0u32) == 7usize) { panic("wrapping_shr #842") }
    if !(7usize.overflowing_shl(0u32).0 == 7usize && 7usize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #843") }
    if !(7usize.overflowing_shr(0u32).0 == 7usize && 7usize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #844") }
    if !(7usize.unbounded_shl(0u32) == 7usize) { panic("unbounded_shl #845") }
    if !(7usize.unbounded_shr(0u32) == 7usize) { panic("unbounded_shr #846") }
    if !(7usize.strict_shl(0u32) == 7usize) { panic("strict_shl #847") }
    if !(7usize.strict_shr(0u32) == 7usize) { panic("strict_shr #848") }
    if !(unsafe { 7usize.unchecked_shl(0u32) } == 7usize) { panic("unchecked_shl #849") }
    if !(unsafe { 7usize.unchecked_shr(0u32) } == 7usize) { panic("unchecked_shr #850") }
    if !(7usize.rotate_left(1u32) == 14usize) { panic("rotate_left #851") }
    if !(7usize.rotate_right(1u32) == 9223372036854775811usize) { panic("rotate_right #852") }
    if !(7usize.checked_shl(1u32) == present(14usize)) { panic("checked_shl #853") }
    if !(7usize.checked_shr(1u32) == present(3usize)) { panic("checked_shr #854") }
    if !(7usize.wrapping_shl(1u32) == 14usize) { panic("wrapping_shl #855") }
    if !(7usize.wrapping_shr(1u32) == 3usize) { panic("wrapping_shr #856") }
    if !(7usize.overflowing_shl(1u32).0 == 14usize && 7usize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #857") }
    if !(7usize.overflowing_shr(1u32).0 == 3usize && 7usize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #858") }
    if !(7usize.unbounded_shl(1u32) == 14usize) { panic("unbounded_shl #859") }
    if !(7usize.unbounded_shr(1u32) == 3usize) { panic("unbounded_shr #860") }
    if !(7usize.strict_shl(1u32) == 14usize) { panic("strict_shl #861") }
    if !(7usize.strict_shr(1u32) == 3usize) { panic("strict_shr #862") }
    if !(unsafe { 7usize.unchecked_shl(1u32) } == 14usize) { panic("unchecked_shl #863") }
    if !(unsafe { 7usize.unchecked_shr(1u32) } == 3usize) { panic("unchecked_shr #864") }
    if !(7usize.rotate_left(3u32) == 56usize) { panic("rotate_left #865") }
    if !(7usize.rotate_right(3u32) == 16140901064495857664usize) { panic("rotate_right #866") }
    if !(7usize.checked_shl(3u32) == present(56usize)) { panic("checked_shl #867") }
    if !(7usize.checked_shr(3u32) == present(0usize)) { panic("checked_shr #868") }
    if !(7usize.wrapping_shl(3u32) == 56usize) { panic("wrapping_shl #869") }
    if !(7usize.wrapping_shr(3u32) == 0usize) { panic("wrapping_shr #870") }
    if !(7usize.overflowing_shl(3u32).0 == 56usize && 7usize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #871") }
    if !(7usize.overflowing_shr(3u32).0 == 0usize && 7usize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #872") }
    if !(7usize.unbounded_shl(3u32) == 56usize) { panic("unbounded_shl #873") }
    if !(7usize.unbounded_shr(3u32) == 0usize) { panic("unbounded_shr #874") }
    if !(7usize.strict_shl(3u32) == 56usize) { panic("strict_shl #875") }
    if !(7usize.strict_shr(3u32) == 0usize) { panic("strict_shr #876") }
    if !(unsafe { 7usize.unchecked_shl(3u32) } == 56usize) { panic("unchecked_shl #877") }
    if !(unsafe { 7usize.unchecked_shr(3u32) } == 0usize) { panic("unchecked_shr #878") }
    if !(7usize.rotate_left(63u32) == 9223372036854775811usize) { panic("rotate_left #879") }
    if !(7usize.rotate_right(63u32) == 14usize) { panic("rotate_right #880") }
    if !(7usize.checked_shl(63u32) == present(9223372036854775808usize)) { panic("checked_shl #881") }
    if !(7usize.checked_shr(63u32) == present(0usize)) { panic("checked_shr #882") }
    if !(7usize.wrapping_shl(63u32) == 9223372036854775808usize) { panic("wrapping_shl #883") }
    if !(7usize.wrapping_shr(63u32) == 0usize) { panic("wrapping_shr #884") }
    if !(7usize.overflowing_shl(63u32).0 == 9223372036854775808usize && 7usize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #885") }
    if !(7usize.overflowing_shr(63u32).0 == 0usize && 7usize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #886") }
    if !(7usize.unbounded_shl(63u32) == 9223372036854775808usize) { panic("unbounded_shl #887") }
    if !(7usize.unbounded_shr(63u32) == 0usize) { panic("unbounded_shr #888") }
    if !(7usize.strict_shl(63u32) == 9223372036854775808usize) { panic("strict_shl #889") }
    if !(7usize.strict_shr(63u32) == 0usize) { panic("strict_shr #890") }
    if !(unsafe { 7usize.unchecked_shl(63u32) } == 9223372036854775808usize) { panic("unchecked_shl #891") }
    if !(unsafe { 7usize.unchecked_shr(63u32) } == 0usize) { panic("unchecked_shr #892") }
    if !(7usize.rotate_left(64u32) == 7usize) { panic("rotate_left #893") }
    if !(7usize.rotate_right(64u32) == 7usize) { panic("rotate_right #894") }
    if !(missing(7usize.checked_shl(64u32))) { panic("checked_shl #895") }
    if !(missing(7usize.checked_shr(64u32))) { panic("checked_shr #896") }
    if !(7usize.wrapping_shl(64u32) == 7usize) { panic("wrapping_shl #897") }
    if !(7usize.wrapping_shr(64u32) == 7usize) { panic("wrapping_shr #898") }
    if !(7usize.overflowing_shl(64u32).0 == 7usize && 7usize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #899") }
    if !(7usize.overflowing_shr(64u32).0 == 7usize && 7usize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #900") }
    if !(7usize.unbounded_shl(64u32) == 0usize) { panic("unbounded_shl #901") }
    if !(7usize.unbounded_shr(64u32) == 0usize) { panic("unbounded_shr #902") }
    if !(7usize.rotate_left(69u32) == 224usize) { panic("rotate_left #903") }
    if !(7usize.rotate_right(69u32) == 4035225266123964416usize) { panic("rotate_right #904") }
    if !(missing(7usize.checked_shl(69u32))) { panic("checked_shl #905") }
    if !(missing(7usize.checked_shr(69u32))) { panic("checked_shr #906") }
    if !(7usize.wrapping_shl(69u32) == 224usize) { panic("wrapping_shl #907") }
    if !(7usize.wrapping_shr(69u32) == 0usize) { panic("wrapping_shr #908") }
    if !(7usize.overflowing_shl(69u32).0 == 224usize && 7usize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #909") }
    if !(7usize.overflowing_shr(69u32).0 == 0usize && 7usize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #910") }
    if !(7usize.unbounded_shl(69u32) == 0usize) { panic("unbounded_shl #911") }
    if !(7usize.unbounded_shr(69u32) == 0usize) { panic("unbounded_shr #912") }
    if !(7usize.checked_pow(0u32) == present(1usize)) { panic("checked_pow #913") }
    if !(7usize.wrapping_pow(0u32) == 1usize) { panic("wrapping_pow #914") }
    if !(7usize.overflowing_pow(0u32).0 == 1usize && 7usize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #915") }
    if !(7usize.saturating_pow(0u32) == 1usize) { panic("saturating_pow #916") }
    if !(7usize.pow(0u32) == 1usize) { panic("pow #917") }
    if !(7usize.strict_pow(0u32) == 1usize) { panic("strict_pow #918") }
    if !(7usize.checked_pow(1u32) == present(7usize)) { panic("checked_pow #919") }
    if !(7usize.wrapping_pow(1u32) == 7usize) { panic("wrapping_pow #920") }
    if !(7usize.overflowing_pow(1u32).0 == 7usize && 7usize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #921") }
    if !(7usize.saturating_pow(1u32) == 7usize) { panic("saturating_pow #922") }
    if !(7usize.pow(1u32) == 7usize) { panic("pow #923") }
    if !(7usize.strict_pow(1u32) == 7usize) { panic("strict_pow #924") }
    if !(7usize.checked_pow(2u32) == present(49usize)) { panic("checked_pow #925") }
    if !(7usize.wrapping_pow(2u32) == 49usize) { panic("wrapping_pow #926") }
    if !(7usize.overflowing_pow(2u32).0 == 49usize && 7usize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #927") }
    if !(7usize.saturating_pow(2u32) == 49usize) { panic("saturating_pow #928") }
    if !(7usize.pow(2u32) == 49usize) { panic("pow #929") }
    if !(7usize.strict_pow(2u32) == 49usize) { panic("strict_pow #930") }
    if !(7usize.checked_pow(3u32) == present(343usize)) { panic("checked_pow #931") }
    if !(7usize.wrapping_pow(3u32) == 343usize) { panic("wrapping_pow #932") }
    if !(7usize.overflowing_pow(3u32).0 == 343usize && 7usize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #933") }
    if !(7usize.saturating_pow(3u32) == 343usize) { panic("saturating_pow #934") }
    if !(7usize.pow(3u32) == 343usize) { panic("pow #935") }
    if !(7usize.strict_pow(3u32) == 343usize) { panic("strict_pow #936") }
    if !(missing(7usize.checked_pow(63u32))) { panic("checked_pow #937") }
    if !(7usize.wrapping_pow(63u32) == 2898552624600762295usize) { panic("wrapping_pow #938") }
    if !(7usize.overflowing_pow(63u32).0 == 2898552624600762295usize && 7usize.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #939") }
    if !(7usize.saturating_pow(63u32) == usize.MAX) { panic("saturating_pow #940") }
    if !(missing(7usize.checked_pow(64u32))) { panic("checked_pow #941") }
    if !(7usize.wrapping_pow(64u32) == 1843124298495784449usize) { panic("wrapping_pow #942") }
    if !(7usize.overflowing_pow(64u32).0 == 1843124298495784449usize && 7usize.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #943") }
    if !(7usize.saturating_pow(64u32) == usize.MAX) { panic("saturating_pow #944") }
    if !(7usize.ilog2() == 2u32) { panic("ilog2 #945") }
    if !(7usize.ilog10() == 0u32) { panic("ilog10 #946") }
    if !(7usize.checked_ilog2() == present(2u32)) { panic("checked_ilog2 #947") }
    if !(7usize.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #948") }
    if !(7usize.ilog(2usize) == 2u32) { panic("ilog #949") }
    if !(7usize.checked_ilog(2usize) == present(2u32)) { panic("checked_ilog #950") }
    if !(7usize.ilog(3usize) == 1u32) { panic("ilog #951") }
    if !(7usize.checked_ilog(3usize) == present(1u32)) { panic("checked_ilog #952") }
    if !(7usize.ilog(7usize) == 1u32) { panic("ilog #953") }
    if !(7usize.checked_ilog(7usize) == present(1u32)) { panic("checked_ilog #954") }
    if !(missing(7usize.checked_ilog(1usize))) { panic("checked_ilog #955") }
    if !(7usize.isqrt() == 2usize) { panic("isqrt #956") }
    if !(7usize.checked_isqrt() == present(2usize)) { panic("checked_isqrt #957") }
    if !(7usize.is_power_of_two() == false) { panic("is_power_of_two #958") }
    if !(7usize.checked_next_power_of_two() == present(8usize)) { panic("checked_next_power_of_two #959") }
    if !(7usize.next_power_of_two() == 8usize) { panic("next_power_of_two #960") }
}

fn group8() {
    if !(7usize.div_ceil(1usize) == 7usize) { panic("div_ceil #961") }
    if !(7usize.checked_next_multiple_of(1usize) == present(7usize)) { panic("checked_next_multiple_of #962") }
    if !(7usize.next_multiple_of(1usize) == 7usize) { panic("next_multiple_of #963") }
    if !(7usize.is_multiple_of(1usize) == true) { panic("is_multiple_of #964") }
    if !(7usize.div_ceil(3usize) == 3usize) { panic("div_ceil #965") }
    if !(7usize.checked_next_multiple_of(3usize) == present(9usize)) { panic("checked_next_multiple_of #966") }
    if !(7usize.next_multiple_of(3usize) == 9usize) { panic("next_multiple_of #967") }
    if !(7usize.is_multiple_of(3usize) == false) { panic("is_multiple_of #968") }
    if !(7usize.div_ceil(7usize) == 1usize) { panic("div_ceil #969") }
    if !(7usize.checked_next_multiple_of(7usize) == present(7usize)) { panic("checked_next_multiple_of #970") }
    if !(7usize.next_multiple_of(7usize) == 7usize) { panic("next_multiple_of #971") }
    if !(7usize.is_multiple_of(7usize) == true) { panic("is_multiple_of #972") }
    if !(7usize.is_multiple_of(0usize) == false) { panic("is_multiple_of #973") }
    if !(missing(7usize.checked_next_multiple_of(0usize))) { panic("checked_next_multiple_of #974") }
    if !(7usize.highest_one() == present(2u32)) { panic("highest_one #975") }
    if !(7usize.lowest_one() == present(0u32)) { panic("lowest_one #976") }
    if !(7usize.isolate_highest_one() == 4usize) { panic("isolate_highest_one #977") }
    if !(7usize.isolate_lowest_one() == 1usize) { panic("isolate_lowest_one #978") }
    if !(7usize.bit_width() == 3u32) { panic("bit_width #979") }
}

fn group9() {
    if !(missing(1usize.checked_neg())) { panic("checked_neg #1142") }
    if !(1usize.wrapping_neg() == usize.MAX) { panic("wrapping_neg #1143") }
    if !(1usize.overflowing_neg().0 == usize.MAX && 1usize.overflowing_neg().1 == true) { panic("overflowing_neg #1144") }
    if !(1usize.cast_signed() == 1isize) { panic("cast_signed #1145") }
    if !(1usize.count_ones() == 1u32) { panic("count_ones #1146") }
    if !(1usize.count_zeros() == 63u32) { panic("count_zeros #1147") }
    if !(1usize.leading_zeros() == 63u32) { panic("leading_zeros #1148") }
    if !(1usize.trailing_zeros() == 0u32) { panic("trailing_zeros #1149") }
    if !(1usize.leading_ones() == 0u32) { panic("leading_ones #1150") }
    if !(1usize.trailing_ones() == 1u32) { panic("trailing_ones #1151") }
    if !(1usize.reverse_bits() == 9223372036854775808usize) { panic("reverse_bits #1152") }
    if !(1usize.swap_bytes() == 72057594037927936usize) { panic("swap_bytes #1153") }
    if !(1usize.to_be() == 72057594037927936usize) { panic("to_be #1154") }
    if !(1usize.to_le() == 1usize) { panic("to_le #1155") }
    if !(usize.from_be(1usize) == 72057594037927936usize) { panic("from_be #1156") }
    if !(usize.from_le(1usize) == 1usize) { panic("from_le #1157") }
    if !(1usize.to_le_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #1158") }
    if !(1usize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #1159") }
    if !(1usize.to_ne_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #1160") }
    if !(usize.from_le_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1usize) { panic("from_le_bytes #1161") }
    if !(usize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]) == 1usize) { panic("from_be_bytes #1162") }
    if !(usize.from_ne_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1usize) { panic("from_ne_bytes #1163") }
    if !(1usize.rotate_left(0u32) == 1usize) { panic("rotate_left #1164") }
    if !(1usize.rotate_right(0u32) == 1usize) { panic("rotate_right #1165") }
    if !(1usize.checked_shl(0u32) == present(1usize)) { panic("checked_shl #1166") }
    if !(1usize.checked_shr(0u32) == present(1usize)) { panic("checked_shr #1167") }
    if !(1usize.wrapping_shl(0u32) == 1usize) { panic("wrapping_shl #1168") }
    if !(1usize.wrapping_shr(0u32) == 1usize) { panic("wrapping_shr #1169") }
    if !(1usize.overflowing_shl(0u32).0 == 1usize && 1usize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1170") }
    if !(1usize.overflowing_shr(0u32).0 == 1usize && 1usize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1171") }
    if !(1usize.unbounded_shl(0u32) == 1usize) { panic("unbounded_shl #1172") }
    if !(1usize.unbounded_shr(0u32) == 1usize) { panic("unbounded_shr #1173") }
    if !(1usize.strict_shl(0u32) == 1usize) { panic("strict_shl #1174") }
    if !(1usize.strict_shr(0u32) == 1usize) { panic("strict_shr #1175") }
    if !(unsafe { 1usize.unchecked_shl(0u32) } == 1usize) { panic("unchecked_shl #1176") }
    if !(unsafe { 1usize.unchecked_shr(0u32) } == 1usize) { panic("unchecked_shr #1177") }
    if !(1usize.rotate_left(1u32) == 2usize) { panic("rotate_left #1178") }
    if !(1usize.rotate_right(1u32) == 9223372036854775808usize) { panic("rotate_right #1179") }
    if !(1usize.checked_shl(1u32) == present(2usize)) { panic("checked_shl #1180") }
    if !(1usize.checked_shr(1u32) == present(0usize)) { panic("checked_shr #1181") }
    if !(1usize.wrapping_shl(1u32) == 2usize) { panic("wrapping_shl #1182") }
    if !(1usize.wrapping_shr(1u32) == 0usize) { panic("wrapping_shr #1183") }
    if !(1usize.overflowing_shl(1u32).0 == 2usize && 1usize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1184") }
    if !(1usize.overflowing_shr(1u32).0 == 0usize && 1usize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1185") }
    if !(1usize.unbounded_shl(1u32) == 2usize) { panic("unbounded_shl #1186") }
    if !(1usize.unbounded_shr(1u32) == 0usize) { panic("unbounded_shr #1187") }
    if !(1usize.strict_shl(1u32) == 2usize) { panic("strict_shl #1188") }
    if !(1usize.strict_shr(1u32) == 0usize) { panic("strict_shr #1189") }
    if !(unsafe { 1usize.unchecked_shl(1u32) } == 2usize) { panic("unchecked_shl #1190") }
    if !(unsafe { 1usize.unchecked_shr(1u32) } == 0usize) { panic("unchecked_shr #1191") }
    if !(1usize.rotate_left(3u32) == 8usize) { panic("rotate_left #1192") }
    if !(1usize.rotate_right(3u32) == 2305843009213693952usize) { panic("rotate_right #1193") }
    if !(1usize.checked_shl(3u32) == present(8usize)) { panic("checked_shl #1194") }
    if !(1usize.checked_shr(3u32) == present(0usize)) { panic("checked_shr #1195") }
    if !(1usize.wrapping_shl(3u32) == 8usize) { panic("wrapping_shl #1196") }
    if !(1usize.wrapping_shr(3u32) == 0usize) { panic("wrapping_shr #1197") }
    if !(1usize.overflowing_shl(3u32).0 == 8usize && 1usize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1198") }
    if !(1usize.overflowing_shr(3u32).0 == 0usize && 1usize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1199") }
    if !(1usize.unbounded_shl(3u32) == 8usize) { panic("unbounded_shl #1200") }
}

fn group10() {
    if !(1usize.unbounded_shr(3u32) == 0usize) { panic("unbounded_shr #1201") }
    if !(1usize.strict_shl(3u32) == 8usize) { panic("strict_shl #1202") }
    if !(1usize.strict_shr(3u32) == 0usize) { panic("strict_shr #1203") }
    if !(unsafe { 1usize.unchecked_shl(3u32) } == 8usize) { panic("unchecked_shl #1204") }
    if !(unsafe { 1usize.unchecked_shr(3u32) } == 0usize) { panic("unchecked_shr #1205") }
    if !(1usize.rotate_left(63u32) == 9223372036854775808usize) { panic("rotate_left #1206") }
    if !(1usize.rotate_right(63u32) == 2usize) { panic("rotate_right #1207") }
    if !(1usize.checked_shl(63u32) == present(9223372036854775808usize)) { panic("checked_shl #1208") }
    if !(1usize.checked_shr(63u32) == present(0usize)) { panic("checked_shr #1209") }
    if !(1usize.wrapping_shl(63u32) == 9223372036854775808usize) { panic("wrapping_shl #1210") }
    if !(1usize.wrapping_shr(63u32) == 0usize) { panic("wrapping_shr #1211") }
    if !(1usize.overflowing_shl(63u32).0 == 9223372036854775808usize && 1usize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #1212") }
    if !(1usize.overflowing_shr(63u32).0 == 0usize && 1usize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #1213") }
    if !(1usize.unbounded_shl(63u32) == 9223372036854775808usize) { panic("unbounded_shl #1214") }
    if !(1usize.unbounded_shr(63u32) == 0usize) { panic("unbounded_shr #1215") }
    if !(1usize.strict_shl(63u32) == 9223372036854775808usize) { panic("strict_shl #1216") }
    if !(1usize.strict_shr(63u32) == 0usize) { panic("strict_shr #1217") }
    if !(unsafe { 1usize.unchecked_shl(63u32) } == 9223372036854775808usize) { panic("unchecked_shl #1218") }
    if !(unsafe { 1usize.unchecked_shr(63u32) } == 0usize) { panic("unchecked_shr #1219") }
    if !(1usize.rotate_left(64u32) == 1usize) { panic("rotate_left #1220") }
    if !(1usize.rotate_right(64u32) == 1usize) { panic("rotate_right #1221") }
    if !(missing(1usize.checked_shl(64u32))) { panic("checked_shl #1222") }
    if !(missing(1usize.checked_shr(64u32))) { panic("checked_shr #1223") }
    if !(1usize.wrapping_shl(64u32) == 1usize) { panic("wrapping_shl #1224") }
    if !(1usize.wrapping_shr(64u32) == 1usize) { panic("wrapping_shr #1225") }
    if !(1usize.overflowing_shl(64u32).0 == 1usize && 1usize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #1226") }
    if !(1usize.overflowing_shr(64u32).0 == 1usize && 1usize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #1227") }
    if !(1usize.unbounded_shl(64u32) == 0usize) { panic("unbounded_shl #1228") }
    if !(1usize.unbounded_shr(64u32) == 0usize) { panic("unbounded_shr #1229") }
    if !(1usize.rotate_left(69u32) == 32usize) { panic("rotate_left #1230") }
    if !(1usize.rotate_right(69u32) == 576460752303423488usize) { panic("rotate_right #1231") }
    if !(missing(1usize.checked_shl(69u32))) { panic("checked_shl #1232") }
    if !(missing(1usize.checked_shr(69u32))) { panic("checked_shr #1233") }
    if !(1usize.wrapping_shl(69u32) == 32usize) { panic("wrapping_shl #1234") }
    if !(1usize.wrapping_shr(69u32) == 0usize) { panic("wrapping_shr #1235") }
    if !(1usize.overflowing_shl(69u32).0 == 32usize && 1usize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #1236") }
    if !(1usize.overflowing_shr(69u32).0 == 0usize && 1usize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #1237") }
    if !(1usize.unbounded_shl(69u32) == 0usize) { panic("unbounded_shl #1238") }
    if !(1usize.unbounded_shr(69u32) == 0usize) { panic("unbounded_shr #1239") }
    if !(1usize.checked_pow(0u32) == present(1usize)) { panic("checked_pow #1240") }
    if !(1usize.wrapping_pow(0u32) == 1usize) { panic("wrapping_pow #1241") }
    if !(1usize.overflowing_pow(0u32).0 == 1usize && 1usize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1242") }
    if !(1usize.saturating_pow(0u32) == 1usize) { panic("saturating_pow #1243") }
    if !(1usize.pow(0u32) == 1usize) { panic("pow #1244") }
    if !(1usize.strict_pow(0u32) == 1usize) { panic("strict_pow #1245") }
    if !(1usize.checked_pow(1u32) == present(1usize)) { panic("checked_pow #1246") }
    if !(1usize.wrapping_pow(1u32) == 1usize) { panic("wrapping_pow #1247") }
    if !(1usize.overflowing_pow(1u32).0 == 1usize && 1usize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1248") }
    if !(1usize.saturating_pow(1u32) == 1usize) { panic("saturating_pow #1249") }
    if !(1usize.pow(1u32) == 1usize) { panic("pow #1250") }
    if !(1usize.strict_pow(1u32) == 1usize) { panic("strict_pow #1251") }
    if !(1usize.checked_pow(2u32) == present(1usize)) { panic("checked_pow #1252") }
    if !(1usize.wrapping_pow(2u32) == 1usize) { panic("wrapping_pow #1253") }
    if !(1usize.overflowing_pow(2u32).0 == 1usize && 1usize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1254") }
    if !(1usize.saturating_pow(2u32) == 1usize) { panic("saturating_pow #1255") }
    if !(1usize.pow(2u32) == 1usize) { panic("pow #1256") }
    if !(1usize.strict_pow(2u32) == 1usize) { panic("strict_pow #1257") }
    if !(1usize.checked_pow(3u32) == present(1usize)) { panic("checked_pow #1258") }
    if !(1usize.wrapping_pow(3u32) == 1usize) { panic("wrapping_pow #1259") }
    if !(1usize.overflowing_pow(3u32).0 == 1usize && 1usize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1260") }
    if !(1usize.saturating_pow(3u32) == 1usize) { panic("saturating_pow #1261") }
    if !(1usize.pow(3u32) == 1usize) { panic("pow #1262") }
    if !(1usize.strict_pow(3u32) == 1usize) { panic("strict_pow #1263") }
    if !(1usize.checked_pow(63u32) == present(1usize)) { panic("checked_pow #1264") }
    if !(1usize.wrapping_pow(63u32) == 1usize) { panic("wrapping_pow #1265") }
    if !(1usize.overflowing_pow(63u32).0 == 1usize && 1usize.overflowing_pow(63u32).1 == false) { panic("overflowing_pow #1266") }
    if !(1usize.saturating_pow(63u32) == 1usize) { panic("saturating_pow #1267") }
    if !(1usize.pow(63u32) == 1usize) { panic("pow #1268") }
    if !(1usize.strict_pow(63u32) == 1usize) { panic("strict_pow #1269") }
    if !(1usize.checked_pow(64u32) == present(1usize)) { panic("checked_pow #1270") }
    if !(1usize.wrapping_pow(64u32) == 1usize) { panic("wrapping_pow #1271") }
    if !(1usize.overflowing_pow(64u32).0 == 1usize && 1usize.overflowing_pow(64u32).1 == false) { panic("overflowing_pow #1272") }
    if !(1usize.saturating_pow(64u32) == 1usize) { panic("saturating_pow #1273") }
    if !(1usize.pow(64u32) == 1usize) { panic("pow #1274") }
    if !(1usize.strict_pow(64u32) == 1usize) { panic("strict_pow #1275") }
    if !(1usize.ilog2() == 0u32) { panic("ilog2 #1276") }
    if !(1usize.ilog10() == 0u32) { panic("ilog10 #1277") }
    if !(1usize.checked_ilog2() == present(0u32)) { panic("checked_ilog2 #1278") }
    if !(1usize.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1279") }
    if !(1usize.ilog(2usize) == 0u32) { panic("ilog #1280") }
    if !(1usize.checked_ilog(2usize) == present(0u32)) { panic("checked_ilog #1281") }
    if !(1usize.ilog(3usize) == 0u32) { panic("ilog #1282") }
    if !(1usize.checked_ilog(3usize) == present(0u32)) { panic("checked_ilog #1283") }
    if !(1usize.ilog(7usize) == 0u32) { panic("ilog #1284") }
    if !(1usize.checked_ilog(7usize) == present(0u32)) { panic("checked_ilog #1285") }
    if !(missing(1usize.checked_ilog(1usize))) { panic("checked_ilog #1286") }
    if !(1usize.isqrt() == 1usize) { panic("isqrt #1287") }
    if !(1usize.checked_isqrt() == present(1usize)) { panic("checked_isqrt #1288") }
    if !(1usize.is_power_of_two() == true) { panic("is_power_of_two #1289") }
    if !(1usize.checked_next_power_of_two() == present(1usize)) { panic("checked_next_power_of_two #1290") }
    if !(1usize.next_power_of_two() == 1usize) { panic("next_power_of_two #1291") }
    if !(1usize.div_ceil(1usize) == 1usize) { panic("div_ceil #1292") }
    if !(1usize.checked_next_multiple_of(1usize) == present(1usize)) { panic("checked_next_multiple_of #1293") }
    if !(1usize.next_multiple_of(1usize) == 1usize) { panic("next_multiple_of #1294") }
    if !(1usize.is_multiple_of(1usize) == true) { panic("is_multiple_of #1295") }
    if !(1usize.div_ceil(3usize) == 1usize) { panic("div_ceil #1296") }
    if !(1usize.checked_next_multiple_of(3usize) == present(3usize)) { panic("checked_next_multiple_of #1297") }
    if !(1usize.next_multiple_of(3usize) == 3usize) { panic("next_multiple_of #1298") }
    if !(1usize.is_multiple_of(3usize) == false) { panic("is_multiple_of #1299") }
    if !(1usize.div_ceil(7usize) == 1usize) { panic("div_ceil #1300") }
    if !(1usize.checked_next_multiple_of(7usize) == present(7usize)) { panic("checked_next_multiple_of #1301") }
    if !(1usize.next_multiple_of(7usize) == 7usize) { panic("next_multiple_of #1302") }
    if !(1usize.is_multiple_of(7usize) == false) { panic("is_multiple_of #1303") }
    if !(1usize.is_multiple_of(0usize) == false) { panic("is_multiple_of #1304") }
    if !(missing(1usize.checked_next_multiple_of(0usize))) { panic("checked_next_multiple_of #1305") }
    if !(1usize.highest_one() == present(0u32)) { panic("highest_one #1306") }
    if !(1usize.lowest_one() == present(0u32)) { panic("lowest_one #1307") }
    if !(1usize.isolate_highest_one() == 1usize) { panic("isolate_highest_one #1308") }
    if !(1usize.isolate_lowest_one() == 1usize) { panic("isolate_lowest_one #1309") }
    if !(1usize.bit_width() == 1u32) { panic("bit_width #1310") }
    if !(usize.MAX.carrying_add(1usize, false).0 == 0usize && usize.MAX.carrying_add(1usize, false).1 == true) { panic("carrying_add #1311") }
    if !(usize.MAX.borrowing_sub(1usize, false).0 == 18446744073709551614usize && usize.MAX.borrowing_sub(1usize, false).1 == false) { panic("borrowing_sub #1312") }
    if !(usize.MAX.carrying_add(1usize, true).0 == 1usize && usize.MAX.carrying_add(1usize, true).1 == true) { panic("carrying_add #1313") }
    if !(usize.MAX.borrowing_sub(1usize, true).0 == 18446744073709551613usize && usize.MAX.borrowing_sub(1usize, true).1 == false) { panic("borrowing_sub #1314") }
    if !(usize.MAX.carrying_mul(1usize, 0usize).0 == usize.MAX && usize.MAX.carrying_mul(1usize, 0usize).1 == 0usize) { panic("carrying_mul #1315") }
    if !(usize.MAX.carrying_mul_add(1usize, 0usize, 0usize).0 == usize.MAX && usize.MAX.carrying_mul_add(1usize, 0usize, 0usize).1 == 0usize) { panic("carrying_mul_add #1316") }
    if !(usize.MAX.carrying_mul(1usize, usize.MAX).0 == 18446744073709551614usize && usize.MAX.carrying_mul(1usize, usize.MAX).1 == 1usize) { panic("carrying_mul #1317") }
    if !(usize.MAX.carrying_mul_add(1usize, usize.MAX, 0usize).0 == 18446744073709551614usize && usize.MAX.carrying_mul_add(1usize, usize.MAX, 0usize).1 == 1usize) { panic("carrying_mul_add #1318") }
    if !(usize.MAX.carrying_mul_add(1usize, usize.MAX, usize.MAX).0 == 18446744073709551613usize && usize.MAX.carrying_mul_add(1usize, usize.MAX, usize.MAX).1 == 2usize) { panic("carrying_mul_add #1320") }
}

fn group11() {
    if !(usize.MAX.carrying_mul(1usize, 7usize).0 == 6usize && usize.MAX.carrying_mul(1usize, 7usize).1 == 1usize) { panic("carrying_mul #1321") }
    if !(usize.MAX.carrying_mul_add(1usize, 7usize, 3usize).0 == 9usize && usize.MAX.carrying_mul_add(1usize, 7usize, 3usize).1 == 1usize) { panic("carrying_mul_add #1322") }
    if !(missing(usize.MAX.checked_signed_diff(1usize))) { panic("checked_signed_diff #1323") }
    if !(0usize.carrying_add(1usize, false).0 == 1usize && 0usize.carrying_add(1usize, false).1 == false) { panic("carrying_add #1324") }
    if !(0usize.borrowing_sub(1usize, false).0 == usize.MAX && 0usize.borrowing_sub(1usize, false).1 == true) { panic("borrowing_sub #1325") }
    if !(0usize.carrying_add(1usize, true).0 == 2usize && 0usize.carrying_add(1usize, true).1 == false) { panic("carrying_add #1326") }
    if !(0usize.borrowing_sub(1usize, true).0 == 18446744073709551614usize && 0usize.borrowing_sub(1usize, true).1 == true) { panic("borrowing_sub #1327") }
    if !(0usize.carrying_mul(1usize, 0usize).0 == 0usize && 0usize.carrying_mul(1usize, 0usize).1 == 0usize) { panic("carrying_mul #1328") }
    if !(0usize.carrying_mul_add(1usize, 0usize, 0usize).0 == 0usize && 0usize.carrying_mul_add(1usize, 0usize, 0usize).1 == 0usize) { panic("carrying_mul_add #1329") }
    if !(0usize.carrying_mul(1usize, usize.MAX).0 == usize.MAX && 0usize.carrying_mul(1usize, usize.MAX).1 == 0usize) { panic("carrying_mul #1330") }
    if !(0usize.carrying_mul_add(1usize, usize.MAX, 0usize).0 == usize.MAX && 0usize.carrying_mul_add(1usize, usize.MAX, 0usize).1 == 0usize) { panic("carrying_mul_add #1331") }
    if !(0usize.carrying_mul_add(1usize, usize.MAX, usize.MAX).0 == 18446744073709551614usize && 0usize.carrying_mul_add(1usize, usize.MAX, usize.MAX).1 == 1usize) { panic("carrying_mul_add #1333") }
    if !(0usize.carrying_mul(1usize, 7usize).0 == 7usize && 0usize.carrying_mul(1usize, 7usize).1 == 0usize) { panic("carrying_mul #1334") }
    if !(0usize.carrying_mul_add(1usize, 7usize, 3usize).0 == 10usize && 0usize.carrying_mul_add(1usize, 7usize, 3usize).1 == 0usize) { panic("carrying_mul_add #1335") }
    if !(0usize.checked_signed_diff(1usize) == present((-1isize))) { panic("checked_signed_diff #1336") }
    if !(1000usize.carrying_add(7usize, false).0 == 1007usize && 1000usize.carrying_add(7usize, false).1 == false) { panic("carrying_add #1337") }
    if !(1000usize.borrowing_sub(7usize, false).0 == 993usize && 1000usize.borrowing_sub(7usize, false).1 == false) { panic("borrowing_sub #1338") }
    if !(1000usize.carrying_add(7usize, true).0 == 1008usize && 1000usize.carrying_add(7usize, true).1 == false) { panic("carrying_add #1339") }
    if !(1000usize.borrowing_sub(7usize, true).0 == 992usize && 1000usize.borrowing_sub(7usize, true).1 == false) { panic("borrowing_sub #1340") }
    if !(1000usize.carrying_mul(7usize, 0usize).0 == 7000usize && 1000usize.carrying_mul(7usize, 0usize).1 == 0usize) { panic("carrying_mul #1341") }
    if !(1000usize.carrying_mul_add(7usize, 0usize, 0usize).0 == 7000usize && 1000usize.carrying_mul_add(7usize, 0usize, 0usize).1 == 0usize) { panic("carrying_mul_add #1342") }
    if !(1000usize.carrying_mul(7usize, usize.MAX).0 == 6999usize && 1000usize.carrying_mul(7usize, usize.MAX).1 == 1usize) { panic("carrying_mul #1343") }
    if !(1000usize.carrying_mul_add(7usize, usize.MAX, 0usize).0 == 6999usize && 1000usize.carrying_mul_add(7usize, usize.MAX, 0usize).1 == 1usize) { panic("carrying_mul_add #1344") }
    if !(1000usize.carrying_mul_add(7usize, usize.MAX, usize.MAX).0 == 6998usize && 1000usize.carrying_mul_add(7usize, usize.MAX, usize.MAX).1 == 2usize) { panic("carrying_mul_add #1346") }
    if !(1000usize.carrying_mul(7usize, 7usize).0 == 7007usize && 1000usize.carrying_mul(7usize, 7usize).1 == 0usize) { panic("carrying_mul #1347") }
    if !(1000usize.carrying_mul_add(7usize, 7usize, 3usize).0 == 7010usize && 1000usize.carrying_mul_add(7usize, 7usize, 3usize).1 == 0usize) { panic("carrying_mul_add #1348") }
    if !(1000usize.checked_signed_diff(7usize) == present(993isize)) { panic("checked_signed_diff #1349") }
    if !(7usize.carrying_add(1000usize, false).0 == 1007usize && 7usize.carrying_add(1000usize, false).1 == false) { panic("carrying_add #1350") }
    if !(7usize.borrowing_sub(1000usize, false).0 == 18446744073709550623usize && 7usize.borrowing_sub(1000usize, false).1 == true) { panic("borrowing_sub #1351") }
    if !(7usize.carrying_add(1000usize, true).0 == 1008usize && 7usize.carrying_add(1000usize, true).1 == false) { panic("carrying_add #1352") }
    if !(7usize.borrowing_sub(1000usize, true).0 == 18446744073709550622usize && 7usize.borrowing_sub(1000usize, true).1 == true) { panic("borrowing_sub #1353") }
    if !(7usize.carrying_mul(1000usize, 0usize).0 == 7000usize && 7usize.carrying_mul(1000usize, 0usize).1 == 0usize) { panic("carrying_mul #1354") }
    if !(7usize.carrying_mul_add(1000usize, 0usize, 0usize).0 == 7000usize && 7usize.carrying_mul_add(1000usize, 0usize, 0usize).1 == 0usize) { panic("carrying_mul_add #1355") }
    if !(7usize.carrying_mul(1000usize, usize.MAX).0 == 6999usize && 7usize.carrying_mul(1000usize, usize.MAX).1 == 1usize) { panic("carrying_mul #1356") }
    if !(7usize.carrying_mul_add(1000usize, usize.MAX, 0usize).0 == 6999usize && 7usize.carrying_mul_add(1000usize, usize.MAX, 0usize).1 == 1usize) { panic("carrying_mul_add #1357") }
    if !(7usize.carrying_mul_add(1000usize, usize.MAX, usize.MAX).0 == 6998usize && 7usize.carrying_mul_add(1000usize, usize.MAX, usize.MAX).1 == 2usize) { panic("carrying_mul_add #1359") }
    if !(7usize.carrying_mul(1000usize, 7usize).0 == 7007usize && 7usize.carrying_mul(1000usize, 7usize).1 == 0usize) { panic("carrying_mul #1360") }
    if !(7usize.carrying_mul_add(1000usize, 7usize, 3usize).0 == 7010usize && 7usize.carrying_mul_add(1000usize, 7usize, 3usize).1 == 0usize) { panic("carrying_mul_add #1361") }
    if !(7usize.checked_signed_diff(1000usize) == present((-993isize))) { panic("checked_signed_diff #1362") }
    if !(usize.MAX.carrying_add(2usize, false).0 == 1usize && usize.MAX.carrying_add(2usize, false).1 == true) { panic("carrying_add #1363") }
    if !(usize.MAX.borrowing_sub(2usize, false).0 == 18446744073709551613usize && usize.MAX.borrowing_sub(2usize, false).1 == false) { panic("borrowing_sub #1364") }
    if !(usize.MAX.carrying_add(2usize, true).0 == 2usize && usize.MAX.carrying_add(2usize, true).1 == true) { panic("carrying_add #1365") }
    if !(usize.MAX.borrowing_sub(2usize, true).0 == 18446744073709551612usize && usize.MAX.borrowing_sub(2usize, true).1 == false) { panic("borrowing_sub #1366") }
    if !(usize.MAX.carrying_mul(2usize, 0usize).0 == 18446744073709551614usize && usize.MAX.carrying_mul(2usize, 0usize).1 == 1usize) { panic("carrying_mul #1367") }
    if !(usize.MAX.carrying_mul_add(2usize, 0usize, 0usize).0 == 18446744073709551614usize && usize.MAX.carrying_mul_add(2usize, 0usize, 0usize).1 == 1usize) { panic("carrying_mul_add #1368") }
    if !(usize.MAX.carrying_mul(2usize, usize.MAX).0 == 18446744073709551613usize && usize.MAX.carrying_mul(2usize, usize.MAX).1 == 2usize) { panic("carrying_mul #1369") }
    if !(usize.MAX.carrying_mul_add(2usize, usize.MAX, 0usize).0 == 18446744073709551613usize && usize.MAX.carrying_mul_add(2usize, usize.MAX, 0usize).1 == 2usize) { panic("carrying_mul_add #1370") }
    if !(usize.MAX.carrying_mul_add(2usize, usize.MAX, usize.MAX).0 == 18446744073709551612usize && usize.MAX.carrying_mul_add(2usize, usize.MAX, usize.MAX).1 == 3usize) { panic("carrying_mul_add #1372") }
    if !(usize.MAX.carrying_mul(2usize, 7usize).0 == 5usize && usize.MAX.carrying_mul(2usize, 7usize).1 == 2usize) { panic("carrying_mul #1373") }
    if !(usize.MAX.carrying_mul_add(2usize, 7usize, 3usize).0 == 8usize && usize.MAX.carrying_mul_add(2usize, 7usize, 3usize).1 == 2usize) { panic("carrying_mul_add #1374") }
    if !(missing(usize.MAX.checked_signed_diff(2usize))) { panic("checked_signed_diff #1375") }
    if !(0usize.carrying_add(0usize, false).0 == 0usize && 0usize.carrying_add(0usize, false).1 == false) { panic("carrying_add #1376") }
    if !(0usize.borrowing_sub(0usize, false).0 == 0usize && 0usize.borrowing_sub(0usize, false).1 == false) { panic("borrowing_sub #1377") }
    if !(0usize.carrying_add(0usize, true).0 == 1usize && 0usize.carrying_add(0usize, true).1 == false) { panic("carrying_add #1378") }
    if !(0usize.borrowing_sub(0usize, true).0 == usize.MAX && 0usize.borrowing_sub(0usize, true).1 == true) { panic("borrowing_sub #1379") }
    if !(0usize.carrying_mul(0usize, 0usize).0 == 0usize && 0usize.carrying_mul(0usize, 0usize).1 == 0usize) { panic("carrying_mul #1380") }
    if !(0usize.carrying_mul_add(0usize, 0usize, 0usize).0 == 0usize && 0usize.carrying_mul_add(0usize, 0usize, 0usize).1 == 0usize) { panic("carrying_mul_add #1381") }
    if !(0usize.carrying_mul(0usize, usize.MAX).0 == usize.MAX && 0usize.carrying_mul(0usize, usize.MAX).1 == 0usize) { panic("carrying_mul #1382") }
    if !(0usize.carrying_mul_add(0usize, usize.MAX, 0usize).0 == usize.MAX && 0usize.carrying_mul_add(0usize, usize.MAX, 0usize).1 == 0usize) { panic("carrying_mul_add #1383") }
    if !(0usize.carrying_mul_add(0usize, usize.MAX, usize.MAX).0 == 18446744073709551614usize && 0usize.carrying_mul_add(0usize, usize.MAX, usize.MAX).1 == 1usize) { panic("carrying_mul_add #1385") }
    if !(0usize.carrying_mul(0usize, 7usize).0 == 7usize && 0usize.carrying_mul(0usize, 7usize).1 == 0usize) { panic("carrying_mul #1386") }
    if !(0usize.carrying_mul_add(0usize, 7usize, 3usize).0 == 10usize && 0usize.carrying_mul_add(0usize, 7usize, 3usize).1 == 0usize) { panic("carrying_mul_add #1387") }
    if !(0usize.checked_signed_diff(0usize) == present(0isize)) { panic("checked_signed_diff #1388") }
    if !(usize.MAX.carrying_add(usize.MAX, false).0 == 18446744073709551614usize && usize.MAX.carrying_add(usize.MAX, false).1 == true) { panic("carrying_add #1389") }
    if !(usize.MAX.borrowing_sub(usize.MAX, false).0 == 0usize && usize.MAX.borrowing_sub(usize.MAX, false).1 == false) { panic("borrowing_sub #1390") }
    if !(usize.MAX.carrying_add(usize.MAX, true).0 == usize.MAX && usize.MAX.carrying_add(usize.MAX, true).1 == true) { panic("carrying_add #1391") }
    if !(usize.MAX.borrowing_sub(usize.MAX, true).0 == usize.MAX && usize.MAX.borrowing_sub(usize.MAX, true).1 == true) { panic("borrowing_sub #1392") }
    if !(usize.MAX.carrying_mul(usize.MAX, 0usize).0 == 1usize && usize.MAX.carrying_mul(usize.MAX, 0usize).1 == 18446744073709551614usize) { panic("carrying_mul #1393") }
    if !(usize.MAX.carrying_mul_add(usize.MAX, 0usize, 0usize).0 == 1usize && usize.MAX.carrying_mul_add(usize.MAX, 0usize, 0usize).1 == 18446744073709551614usize) { panic("carrying_mul_add #1394") }
    if !(usize.MAX.carrying_mul(usize.MAX, usize.MAX).0 == 0usize && usize.MAX.carrying_mul(usize.MAX, usize.MAX).1 == usize.MAX) { panic("carrying_mul #1395") }
    if !(usize.MAX.carrying_mul_add(usize.MAX, usize.MAX, 0usize).0 == 0usize && usize.MAX.carrying_mul_add(usize.MAX, usize.MAX, 0usize).1 == usize.MAX) { panic("carrying_mul_add #1396") }
    if !(usize.MAX.carrying_mul_add(usize.MAX, usize.MAX, usize.MAX).0 == usize.MAX && usize.MAX.carrying_mul_add(usize.MAX, usize.MAX, usize.MAX).1 == usize.MAX) { panic("carrying_mul_add #1398") }
    if !(usize.MAX.carrying_mul(usize.MAX, 7usize).0 == 8usize && usize.MAX.carrying_mul(usize.MAX, 7usize).1 == 18446744073709551614usize) { panic("carrying_mul #1399") }
    if !(usize.MAX.carrying_mul_add(usize.MAX, 7usize, 3usize).0 == 11usize && usize.MAX.carrying_mul_add(usize.MAX, 7usize, 3usize).1 == 18446744073709551614usize) { panic("carrying_mul_add #1400") }
    if !(usize.MAX.checked_signed_diff(usize.MAX) == present(0isize)) { panic("checked_signed_diff #1401") }
    if !(usize.MAX.carrying_add(18446744073709551614usize, false).0 == 18446744073709551613usize && usize.MAX.carrying_add(18446744073709551614usize, false).1 == true) { panic("carrying_add #1402") }
    if !(usize.MAX.borrowing_sub(18446744073709551614usize, false).0 == 1usize && usize.MAX.borrowing_sub(18446744073709551614usize, false).1 == false) { panic("borrowing_sub #1403") }
    if !(usize.MAX.carrying_add(18446744073709551614usize, true).0 == 18446744073709551614usize && usize.MAX.carrying_add(18446744073709551614usize, true).1 == true) { panic("carrying_add #1404") }
    if !(usize.MAX.borrowing_sub(18446744073709551614usize, true).0 == 0usize && usize.MAX.borrowing_sub(18446744073709551614usize, true).1 == false) { panic("borrowing_sub #1405") }
    if !(usize.MAX.carrying_mul(18446744073709551614usize, 0usize).0 == 2usize && usize.MAX.carrying_mul(18446744073709551614usize, 0usize).1 == 18446744073709551613usize) { panic("carrying_mul #1406") }
    if !(usize.MAX.carrying_mul_add(18446744073709551614usize, 0usize, 0usize).0 == 2usize && usize.MAX.carrying_mul_add(18446744073709551614usize, 0usize, 0usize).1 == 18446744073709551613usize) { panic("carrying_mul_add #1407") }
    if !(usize.MAX.carrying_mul(18446744073709551614usize, usize.MAX).0 == 1usize && usize.MAX.carrying_mul(18446744073709551614usize, usize.MAX).1 == 18446744073709551614usize) { panic("carrying_mul #1408") }
    if !(usize.MAX.carrying_mul_add(18446744073709551614usize, usize.MAX, 0usize).0 == 1usize && usize.MAX.carrying_mul_add(18446744073709551614usize, usize.MAX, 0usize).1 == 18446744073709551614usize) { panic("carrying_mul_add #1409") }
    if !(usize.MAX.carrying_mul_add(18446744073709551614usize, usize.MAX, usize.MAX).0 == 0usize && usize.MAX.carrying_mul_add(18446744073709551614usize, usize.MAX, usize.MAX).1 == usize.MAX) { panic("carrying_mul_add #1411") }
    if !(usize.MAX.carrying_mul(18446744073709551614usize, 7usize).0 == 9usize && usize.MAX.carrying_mul(18446744073709551614usize, 7usize).1 == 18446744073709551613usize) { panic("carrying_mul #1412") }
    if !(usize.MAX.carrying_mul_add(18446744073709551614usize, 7usize, 3usize).0 == 12usize && usize.MAX.carrying_mul_add(18446744073709551614usize, 7usize, 3usize).1 == 18446744073709551613usize) { panic("carrying_mul_add #1413") }
    if !(usize.MAX.checked_signed_diff(18446744073709551614usize) == present(1isize)) { panic("checked_signed_diff #1414") }
    if !(parsed(capture num.parse_radix<usize>("18446744073709551615", 10u32)) == present(usize.MAX)) { panic("parse_radix #1415") }
    if !(parsed(capture num.parse_radix<usize>("ffffffffffffffff", 16u32)) == present(usize.MAX)) { panic("parse_radix #1416") }
    if !(parsed(capture num.parse_radix<usize>("1111111111111111111111111111111111111111111111111111111111111111", 2u32)) == present(usize.MAX)) { panic("parse_radix #1417") }
    if !(parsed(capture num.parse_radix<usize>("3w5e11264sgsf", 36u32)) == present(usize.MAX)) { panic("parse_radix #1418") }
    if !(parsed(capture num.parse_radix<usize>("FFFFFFFFFFFFFFFF", 16u32)) == present(usize.MAX)) { panic("parse_radix #1419") }
    if !(parsed(capture num.parse_radix<usize>("0", 10u32)) == present(0usize)) { panic("parse_radix #1420") }
    if !(parsed(capture num.parse_radix<usize>("0", 16u32)) == present(0usize)) { panic("parse_radix #1421") }
    if !(parsed(capture num.parse_radix<usize>("0", 2u32)) == present(0usize)) { panic("parse_radix #1422") }
    if !(parsed(capture num.parse_radix<usize>("0", 36u32)) == present(0usize)) { panic("parse_radix #1423") }
    if !(parsed(capture num.parse_radix<usize>("7", 10u32)) == present(7usize)) { panic("parse_radix #1425") }
    if !(parsed(capture num.parse_radix<usize>("7", 16u32)) == present(7usize)) { panic("parse_radix #1426") }
    if !(parsed(capture num.parse_radix<usize>("111", 2u32)) == present(7usize)) { panic("parse_radix #1427") }
    if !(parsed(capture num.parse_radix<usize>("7", 36u32)) == present(7usize)) { panic("parse_radix #1428") }
    if !(parsed(capture num.parse_radix<usize>("+7", 10u32)) == present(7usize)) { panic("parse_radix #1435") }
    if !(kind(capture num.parse_radix<usize>("", 10u32)) == present(IntErrorKind.Empty)) { panic("parse_radix #1436") }
    if !(kind(capture num.parse_radix<usize>("-", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1437") }
    if !(kind(capture num.parse_radix<usize>("+", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1438") }
    if !(kind(capture num.parse_radix<usize>("1_0", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1439") }
    if !(kind(capture num.parse_radix<usize>("12", 2u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1440") }
}

fn group12() {
    if !(kind(capture num.parse_radix<usize>(" 1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1441") }
    if !(kind(capture num.parse_radix<usize>("18446744073709551616", 10u32)) == present(IntErrorKind.PosOverflow)) { panic("parse_radix #1442") }
    if !(kind(capture num.parse_radix<usize>("-1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("parse_radix #1445") }
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
