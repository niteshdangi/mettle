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

fn group0() {
    if !(i8.BITS == 8u32) { panic("BITS #1") }
    if !(i8.MIN == -128i8) { panic("MIN #2") }
    if !(i8.MAX == 127i8) { panic("MAX #3") }
    if !(missing(i8.MAX.checked_add(1i8))) { panic("checked_add #4") }
    if !(i8.MAX.wrapping_add(1i8) == i8.MIN) { panic("wrapping_add #5") }
    if !(i8.MAX.overflowing_add(1i8).0 == i8.MIN && i8.MAX.overflowing_add(1i8).1 == true) { panic("overflowing_add #6") }
    if !(i8.MAX.saturating_add(1i8) == i8.MAX) { panic("saturating_add #7") }
    if !(i8.MAX.checked_sub(1i8) == present(126i8)) { panic("checked_sub #8") }
    if !(i8.MAX.wrapping_sub(1i8) == 126i8) { panic("wrapping_sub #9") }
    if !(i8.MAX.overflowing_sub(1i8).0 == 126i8 && i8.MAX.overflowing_sub(1i8).1 == false) { panic("overflowing_sub #10") }
    if !(i8.MAX.saturating_sub(1i8) == 126i8) { panic("saturating_sub #11") }
    if !(i8.MAX.strict_sub(1i8) == 126i8) { panic("strict_sub #12") }
    if !(unsafe { i8.MAX.unchecked_sub(1i8) } == 126i8) { panic("unchecked_sub #13") }
    if !(i8.MAX.checked_mul(1i8) == present(i8.MAX)) { panic("checked_mul #14") }
    if !(i8.MAX.wrapping_mul(1i8) == i8.MAX) { panic("wrapping_mul #15") }
    if !(i8.MAX.overflowing_mul(1i8).0 == i8.MAX && i8.MAX.overflowing_mul(1i8).1 == false) { panic("overflowing_mul #16") }
    if !(i8.MAX.saturating_mul(1i8) == i8.MAX) { panic("saturating_mul #17") }
    if !(i8.MAX.strict_mul(1i8) == i8.MAX) { panic("strict_mul #18") }
    if !(unsafe { i8.MAX.unchecked_mul(1i8) } == i8.MAX) { panic("unchecked_mul #19") }
    if !(i8.MAX.checked_div(1i8) == present(i8.MAX)) { panic("checked_div #20") }
    if !(i8.MAX.wrapping_div(1i8) == i8.MAX) { panic("wrapping_div #21") }
    if !(i8.MAX.overflowing_div(1i8).0 == i8.MAX && i8.MAX.overflowing_div(1i8).1 == false) { panic("overflowing_div #22") }
    if !(i8.MAX.strict_div(1i8) == i8.MAX) { panic("strict_div #23") }
    if !(i8.MAX.saturating_div(1i8) == i8.MAX) { panic("saturating_div #24") }
    if !(i8.MAX.checked_rem(1i8) == present(0i8)) { panic("checked_rem #25") }
    if !(i8.MAX.wrapping_rem(1i8) == 0i8) { panic("wrapping_rem #26") }
    if !(i8.MAX.overflowing_rem(1i8).0 == 0i8 && i8.MAX.overflowing_rem(1i8).1 == false) { panic("overflowing_rem #27") }
    if !(i8.MAX.strict_rem(1i8) == 0i8) { panic("strict_rem #28") }
    if !(i8.MAX.checked_div_euclid(1i8) == present(i8.MAX)) { panic("checked_div_euclid #29") }
    if !(i8.MAX.wrapping_div_euclid(1i8) == i8.MAX) { panic("wrapping_div_euclid #30") }
    if !(i8.MAX.overflowing_div_euclid(1i8).0 == i8.MAX && i8.MAX.overflowing_div_euclid(1i8).1 == false) { panic("overflowing_div_euclid #31") }
    if !(i8.MAX.strict_div_euclid(1i8) == i8.MAX) { panic("strict_div_euclid #32") }
    if !(i8.MAX.div_euclid(1i8) == i8.MAX) { panic("div_euclid #33") }
    if !(i8.MAX.checked_rem_euclid(1i8) == present(0i8)) { panic("checked_rem_euclid #34") }
    if !(i8.MAX.wrapping_rem_euclid(1i8) == 0i8) { panic("wrapping_rem_euclid #35") }
    if !(i8.MAX.overflowing_rem_euclid(1i8).0 == 0i8 && i8.MAX.overflowing_rem_euclid(1i8).1 == false) { panic("overflowing_rem_euclid #36") }
    if !(i8.MAX.strict_rem_euclid(1i8) == 0i8) { panic("strict_rem_euclid #37") }
    if !(i8.MAX.rem_euclid(1i8) == 0i8) { panic("rem_euclid #38") }
    if !(i8.MAX.abs_diff(1i8) == 126u8) { panic("abs_diff #39") }
    if !(i8.MAX.midpoint(1i8) == 64i8) { panic("midpoint #40") }
    if !(i8.MIN.checked_add(1i8) == present((-127i8))) { panic("checked_add #41") }
    if !(i8.MIN.wrapping_add(1i8) == (-127i8)) { panic("wrapping_add #42") }
    if !(i8.MIN.overflowing_add(1i8).0 == (-127i8) && i8.MIN.overflowing_add(1i8).1 == false) { panic("overflowing_add #43") }
    if !(i8.MIN.saturating_add(1i8) == (-127i8)) { panic("saturating_add #44") }
    if !(i8.MIN.strict_add(1i8) == (-127i8)) { panic("strict_add #45") }
    if !(unsafe { i8.MIN.unchecked_add(1i8) } == (-127i8)) { panic("unchecked_add #46") }
    if !(missing(i8.MIN.checked_sub(1i8))) { panic("checked_sub #47") }
    if !(i8.MIN.wrapping_sub(1i8) == i8.MAX) { panic("wrapping_sub #48") }
    if !(i8.MIN.overflowing_sub(1i8).0 == i8.MAX && i8.MIN.overflowing_sub(1i8).1 == true) { panic("overflowing_sub #49") }
    if !(i8.MIN.saturating_sub(1i8) == i8.MIN) { panic("saturating_sub #50") }
    if !(i8.MIN.checked_mul(1i8) == present(i8.MIN)) { panic("checked_mul #51") }
    if !(i8.MIN.wrapping_mul(1i8) == i8.MIN) { panic("wrapping_mul #52") }
    if !(i8.MIN.overflowing_mul(1i8).0 == i8.MIN && i8.MIN.overflowing_mul(1i8).1 == false) { panic("overflowing_mul #53") }
    if !(i8.MIN.saturating_mul(1i8) == i8.MIN) { panic("saturating_mul #54") }
    if !(i8.MIN.strict_mul(1i8) == i8.MIN) { panic("strict_mul #55") }
    if !(unsafe { i8.MIN.unchecked_mul(1i8) } == i8.MIN) { panic("unchecked_mul #56") }
    if !(i8.MIN.checked_div(1i8) == present(i8.MIN)) { panic("checked_div #57") }
    if !(i8.MIN.wrapping_div(1i8) == i8.MIN) { panic("wrapping_div #58") }
    if !(i8.MIN.overflowing_div(1i8).0 == i8.MIN && i8.MIN.overflowing_div(1i8).1 == false) { panic("overflowing_div #59") }
    if !(i8.MIN.strict_div(1i8) == i8.MIN) { panic("strict_div #60") }
    if !(i8.MIN.saturating_div(1i8) == i8.MIN) { panic("saturating_div #61") }
    if !(i8.MIN.checked_rem(1i8) == present(0i8)) { panic("checked_rem #62") }
    if !(i8.MIN.wrapping_rem(1i8) == 0i8) { panic("wrapping_rem #63") }
    if !(i8.MIN.overflowing_rem(1i8).0 == 0i8 && i8.MIN.overflowing_rem(1i8).1 == false) { panic("overflowing_rem #64") }
    if !(i8.MIN.strict_rem(1i8) == 0i8) { panic("strict_rem #65") }
    if !(i8.MIN.checked_div_euclid(1i8) == present(i8.MIN)) { panic("checked_div_euclid #66") }
    if !(i8.MIN.wrapping_div_euclid(1i8) == i8.MIN) { panic("wrapping_div_euclid #67") }
    if !(i8.MIN.overflowing_div_euclid(1i8).0 == i8.MIN && i8.MIN.overflowing_div_euclid(1i8).1 == false) { panic("overflowing_div_euclid #68") }
    if !(i8.MIN.strict_div_euclid(1i8) == i8.MIN) { panic("strict_div_euclid #69") }
    if !(i8.MIN.div_euclid(1i8) == i8.MIN) { panic("div_euclid #70") }
    if !(i8.MIN.checked_rem_euclid(1i8) == present(0i8)) { panic("checked_rem_euclid #71") }
    if !(i8.MIN.wrapping_rem_euclid(1i8) == 0i8) { panic("wrapping_rem_euclid #72") }
    if !(i8.MIN.overflowing_rem_euclid(1i8).0 == 0i8 && i8.MIN.overflowing_rem_euclid(1i8).1 == false) { panic("overflowing_rem_euclid #73") }
    if !(i8.MIN.strict_rem_euclid(1i8) == 0i8) { panic("strict_rem_euclid #74") }
    if !(i8.MIN.rem_euclid(1i8) == 0i8) { panic("rem_euclid #75") }
    if !(i8.MIN.abs_diff(1i8) == 129u8) { panic("abs_diff #76") }
    if !(i8.MIN.midpoint(1i8) == (-63i8)) { panic("midpoint #77") }
    if !(3i8.checked_add(7i8) == present(10i8)) { panic("checked_add #78") }
    if !(3i8.wrapping_add(7i8) == 10i8) { panic("wrapping_add #79") }
    if !(3i8.overflowing_add(7i8).0 == 10i8 && 3i8.overflowing_add(7i8).1 == false) { panic("overflowing_add #80") }
    if !(3i8.saturating_add(7i8) == 10i8) { panic("saturating_add #81") }
    if !(3i8.strict_add(7i8) == 10i8) { panic("strict_add #82") }
    if !(unsafe { 3i8.unchecked_add(7i8) } == 10i8) { panic("unchecked_add #83") }
    if !(3i8.checked_sub(7i8) == present((-4i8))) { panic("checked_sub #84") }
    if !(3i8.wrapping_sub(7i8) == (-4i8)) { panic("wrapping_sub #85") }
    if !(3i8.overflowing_sub(7i8).0 == (-4i8) && 3i8.overflowing_sub(7i8).1 == false) { panic("overflowing_sub #86") }
    if !(3i8.saturating_sub(7i8) == (-4i8)) { panic("saturating_sub #87") }
    if !(3i8.strict_sub(7i8) == (-4i8)) { panic("strict_sub #88") }
    if !(unsafe { 3i8.unchecked_sub(7i8) } == (-4i8)) { panic("unchecked_sub #89") }
    if !(3i8.checked_mul(7i8) == present(21i8)) { panic("checked_mul #90") }
    if !(3i8.wrapping_mul(7i8) == 21i8) { panic("wrapping_mul #91") }
    if !(3i8.overflowing_mul(7i8).0 == 21i8 && 3i8.overflowing_mul(7i8).1 == false) { panic("overflowing_mul #92") }
    if !(3i8.saturating_mul(7i8) == 21i8) { panic("saturating_mul #93") }
    if !(3i8.strict_mul(7i8) == 21i8) { panic("strict_mul #94") }
    if !(unsafe { 3i8.unchecked_mul(7i8) } == 21i8) { panic("unchecked_mul #95") }
    if !(3i8.checked_div(7i8) == present(0i8)) { panic("checked_div #96") }
    if !(3i8.wrapping_div(7i8) == 0i8) { panic("wrapping_div #97") }
    if !(3i8.overflowing_div(7i8).0 == 0i8 && 3i8.overflowing_div(7i8).1 == false) { panic("overflowing_div #98") }
    if !(3i8.strict_div(7i8) == 0i8) { panic("strict_div #99") }
    if !(3i8.saturating_div(7i8) == 0i8) { panic("saturating_div #100") }
    if !(3i8.checked_rem(7i8) == present(3i8)) { panic("checked_rem #101") }
    if !(3i8.wrapping_rem(7i8) == 3i8) { panic("wrapping_rem #102") }
    if !(3i8.overflowing_rem(7i8).0 == 3i8 && 3i8.overflowing_rem(7i8).1 == false) { panic("overflowing_rem #103") }
    if !(3i8.strict_rem(7i8) == 3i8) { panic("strict_rem #104") }
    if !(3i8.checked_div_euclid(7i8) == present(0i8)) { panic("checked_div_euclid #105") }
    if !(3i8.wrapping_div_euclid(7i8) == 0i8) { panic("wrapping_div_euclid #106") }
    if !(3i8.overflowing_div_euclid(7i8).0 == 0i8 && 3i8.overflowing_div_euclid(7i8).1 == false) { panic("overflowing_div_euclid #107") }
    if !(3i8.strict_div_euclid(7i8) == 0i8) { panic("strict_div_euclid #108") }
    if !(3i8.div_euclid(7i8) == 0i8) { panic("div_euclid #109") }
    if !(3i8.checked_rem_euclid(7i8) == present(3i8)) { panic("checked_rem_euclid #110") }
    if !(3i8.wrapping_rem_euclid(7i8) == 3i8) { panic("wrapping_rem_euclid #111") }
    if !(3i8.overflowing_rem_euclid(7i8).0 == 3i8 && 3i8.overflowing_rem_euclid(7i8).1 == false) { panic("overflowing_rem_euclid #112") }
    if !(3i8.strict_rem_euclid(7i8) == 3i8) { panic("strict_rem_euclid #113") }
    if !(3i8.rem_euclid(7i8) == 3i8) { panic("rem_euclid #114") }
    if !(3i8.abs_diff(7i8) == 4u8) { panic("abs_diff #115") }
    if !(3i8.midpoint(7i8) == 5i8) { panic("midpoint #116") }
    if !(7i8.checked_add(3i8) == present(10i8)) { panic("checked_add #117") }
    if !(7i8.wrapping_add(3i8) == 10i8) { panic("wrapping_add #118") }
    if !(7i8.overflowing_add(3i8).0 == 10i8 && 7i8.overflowing_add(3i8).1 == false) { panic("overflowing_add #119") }
    if !(7i8.saturating_add(3i8) == 10i8) { panic("saturating_add #120") }
}

fn group1() {
    if !(7i8.strict_add(3i8) == 10i8) { panic("strict_add #121") }
    if !(unsafe { 7i8.unchecked_add(3i8) } == 10i8) { panic("unchecked_add #122") }
    if !(7i8.checked_sub(3i8) == present(4i8)) { panic("checked_sub #123") }
    if !(7i8.wrapping_sub(3i8) == 4i8) { panic("wrapping_sub #124") }
    if !(7i8.overflowing_sub(3i8).0 == 4i8 && 7i8.overflowing_sub(3i8).1 == false) { panic("overflowing_sub #125") }
    if !(7i8.saturating_sub(3i8) == 4i8) { panic("saturating_sub #126") }
    if !(7i8.strict_sub(3i8) == 4i8) { panic("strict_sub #127") }
    if !(unsafe { 7i8.unchecked_sub(3i8) } == 4i8) { panic("unchecked_sub #128") }
    if !(7i8.checked_mul(3i8) == present(21i8)) { panic("checked_mul #129") }
    if !(7i8.wrapping_mul(3i8) == 21i8) { panic("wrapping_mul #130") }
    if !(7i8.overflowing_mul(3i8).0 == 21i8 && 7i8.overflowing_mul(3i8).1 == false) { panic("overflowing_mul #131") }
    if !(7i8.saturating_mul(3i8) == 21i8) { panic("saturating_mul #132") }
    if !(7i8.strict_mul(3i8) == 21i8) { panic("strict_mul #133") }
    if !(unsafe { 7i8.unchecked_mul(3i8) } == 21i8) { panic("unchecked_mul #134") }
    if !(7i8.checked_div(3i8) == present(2i8)) { panic("checked_div #135") }
    if !(7i8.wrapping_div(3i8) == 2i8) { panic("wrapping_div #136") }
    if !(7i8.overflowing_div(3i8).0 == 2i8 && 7i8.overflowing_div(3i8).1 == false) { panic("overflowing_div #137") }
    if !(7i8.strict_div(3i8) == 2i8) { panic("strict_div #138") }
    if !(7i8.saturating_div(3i8) == 2i8) { panic("saturating_div #139") }
    if !(7i8.checked_rem(3i8) == present(1i8)) { panic("checked_rem #140") }
    if !(7i8.wrapping_rem(3i8) == 1i8) { panic("wrapping_rem #141") }
    if !(7i8.overflowing_rem(3i8).0 == 1i8 && 7i8.overflowing_rem(3i8).1 == false) { panic("overflowing_rem #142") }
    if !(7i8.strict_rem(3i8) == 1i8) { panic("strict_rem #143") }
    if !(7i8.checked_div_euclid(3i8) == present(2i8)) { panic("checked_div_euclid #144") }
    if !(7i8.wrapping_div_euclid(3i8) == 2i8) { panic("wrapping_div_euclid #145") }
    if !(7i8.overflowing_div_euclid(3i8).0 == 2i8 && 7i8.overflowing_div_euclid(3i8).1 == false) { panic("overflowing_div_euclid #146") }
    if !(7i8.strict_div_euclid(3i8) == 2i8) { panic("strict_div_euclid #147") }
    if !(7i8.div_euclid(3i8) == 2i8) { panic("div_euclid #148") }
    if !(7i8.checked_rem_euclid(3i8) == present(1i8)) { panic("checked_rem_euclid #149") }
    if !(7i8.wrapping_rem_euclid(3i8) == 1i8) { panic("wrapping_rem_euclid #150") }
    if !(7i8.overflowing_rem_euclid(3i8).0 == 1i8 && 7i8.overflowing_rem_euclid(3i8).1 == false) { panic("overflowing_rem_euclid #151") }
    if !(7i8.strict_rem_euclid(3i8) == 1i8) { panic("strict_rem_euclid #152") }
    if !(7i8.rem_euclid(3i8) == 1i8) { panic("rem_euclid #153") }
    if !(7i8.abs_diff(3i8) == 4u8) { panic("abs_diff #154") }
    if !(7i8.midpoint(3i8) == 5i8) { panic("midpoint #155") }
    if !(missing(i8.MAX.checked_add(2i8))) { panic("checked_add #156") }
    if !(i8.MAX.wrapping_add(2i8) == (-127i8)) { panic("wrapping_add #157") }
    if !(i8.MAX.overflowing_add(2i8).0 == (-127i8) && i8.MAX.overflowing_add(2i8).1 == true) { panic("overflowing_add #158") }
    if !(i8.MAX.saturating_add(2i8) == i8.MAX) { panic("saturating_add #159") }
    if !(i8.MAX.checked_sub(2i8) == present(125i8)) { panic("checked_sub #160") }
    if !(i8.MAX.wrapping_sub(2i8) == 125i8) { panic("wrapping_sub #161") }
    if !(i8.MAX.overflowing_sub(2i8).0 == 125i8 && i8.MAX.overflowing_sub(2i8).1 == false) { panic("overflowing_sub #162") }
    if !(i8.MAX.saturating_sub(2i8) == 125i8) { panic("saturating_sub #163") }
    if !(i8.MAX.strict_sub(2i8) == 125i8) { panic("strict_sub #164") }
    if !(unsafe { i8.MAX.unchecked_sub(2i8) } == 125i8) { panic("unchecked_sub #165") }
    if !(missing(i8.MAX.checked_mul(2i8))) { panic("checked_mul #166") }
    if !(i8.MAX.wrapping_mul(2i8) == (-2i8)) { panic("wrapping_mul #167") }
    if !(i8.MAX.overflowing_mul(2i8).0 == (-2i8) && i8.MAX.overflowing_mul(2i8).1 == true) { panic("overflowing_mul #168") }
    if !(i8.MAX.saturating_mul(2i8) == i8.MAX) { panic("saturating_mul #169") }
    if !(i8.MAX.checked_div(2i8) == present(63i8)) { panic("checked_div #170") }
    if !(i8.MAX.wrapping_div(2i8) == 63i8) { panic("wrapping_div #171") }
    if !(i8.MAX.overflowing_div(2i8).0 == 63i8 && i8.MAX.overflowing_div(2i8).1 == false) { panic("overflowing_div #172") }
    if !(i8.MAX.strict_div(2i8) == 63i8) { panic("strict_div #173") }
    if !(i8.MAX.saturating_div(2i8) == 63i8) { panic("saturating_div #174") }
    if !(i8.MAX.checked_rem(2i8) == present(1i8)) { panic("checked_rem #175") }
    if !(i8.MAX.wrapping_rem(2i8) == 1i8) { panic("wrapping_rem #176") }
    if !(i8.MAX.overflowing_rem(2i8).0 == 1i8 && i8.MAX.overflowing_rem(2i8).1 == false) { panic("overflowing_rem #177") }
    if !(i8.MAX.strict_rem(2i8) == 1i8) { panic("strict_rem #178") }
    if !(i8.MAX.checked_div_euclid(2i8) == present(63i8)) { panic("checked_div_euclid #179") }
    if !(i8.MAX.wrapping_div_euclid(2i8) == 63i8) { panic("wrapping_div_euclid #180") }
    if !(i8.MAX.overflowing_div_euclid(2i8).0 == 63i8 && i8.MAX.overflowing_div_euclid(2i8).1 == false) { panic("overflowing_div_euclid #181") }
    if !(i8.MAX.strict_div_euclid(2i8) == 63i8) { panic("strict_div_euclid #182") }
    if !(i8.MAX.div_euclid(2i8) == 63i8) { panic("div_euclid #183") }
    if !(i8.MAX.checked_rem_euclid(2i8) == present(1i8)) { panic("checked_rem_euclid #184") }
    if !(i8.MAX.wrapping_rem_euclid(2i8) == 1i8) { panic("wrapping_rem_euclid #185") }
    if !(i8.MAX.overflowing_rem_euclid(2i8).0 == 1i8 && i8.MAX.overflowing_rem_euclid(2i8).1 == false) { panic("overflowing_rem_euclid #186") }
    if !(i8.MAX.strict_rem_euclid(2i8) == 1i8) { panic("strict_rem_euclid #187") }
    if !(i8.MAX.rem_euclid(2i8) == 1i8) { panic("rem_euclid #188") }
    if !(i8.MAX.abs_diff(2i8) == 125u8) { panic("abs_diff #189") }
    if !(i8.MAX.midpoint(2i8) == 64i8) { panic("midpoint #190") }
    if !(0i8.checked_add(0i8) == present(0i8)) { panic("checked_add #191") }
    if !(0i8.wrapping_add(0i8) == 0i8) { panic("wrapping_add #192") }
    if !(0i8.overflowing_add(0i8).0 == 0i8 && 0i8.overflowing_add(0i8).1 == false) { panic("overflowing_add #193") }
    if !(0i8.saturating_add(0i8) == 0i8) { panic("saturating_add #194") }
    if !(0i8.strict_add(0i8) == 0i8) { panic("strict_add #195") }
    if !(unsafe { 0i8.unchecked_add(0i8) } == 0i8) { panic("unchecked_add #196") }
    if !(0i8.checked_sub(0i8) == present(0i8)) { panic("checked_sub #197") }
    if !(0i8.wrapping_sub(0i8) == 0i8) { panic("wrapping_sub #198") }
    if !(0i8.overflowing_sub(0i8).0 == 0i8 && 0i8.overflowing_sub(0i8).1 == false) { panic("overflowing_sub #199") }
    if !(0i8.saturating_sub(0i8) == 0i8) { panic("saturating_sub #200") }
    if !(0i8.strict_sub(0i8) == 0i8) { panic("strict_sub #201") }
    if !(unsafe { 0i8.unchecked_sub(0i8) } == 0i8) { panic("unchecked_sub #202") }
    if !(0i8.checked_mul(0i8) == present(0i8)) { panic("checked_mul #203") }
    if !(0i8.wrapping_mul(0i8) == 0i8) { panic("wrapping_mul #204") }
    if !(0i8.overflowing_mul(0i8).0 == 0i8 && 0i8.overflowing_mul(0i8).1 == false) { panic("overflowing_mul #205") }
    if !(0i8.saturating_mul(0i8) == 0i8) { panic("saturating_mul #206") }
    if !(0i8.strict_mul(0i8) == 0i8) { panic("strict_mul #207") }
    if !(unsafe { 0i8.unchecked_mul(0i8) } == 0i8) { panic("unchecked_mul #208") }
    if !(missing(0i8.checked_div(0i8))) { panic("checked_div #209") }
    if !(missing(0i8.checked_rem(0i8))) { panic("checked_rem #210") }
    if !(missing(0i8.checked_div_euclid(0i8))) { panic("checked_div_euclid #211") }
    if !(missing(0i8.checked_rem_euclid(0i8))) { panic("checked_rem_euclid #212") }
    if !(0i8.abs_diff(0i8) == 0u8) { panic("abs_diff #213") }
    if !(0i8.midpoint(0i8) == 0i8) { panic("midpoint #214") }
    if !(missing(i8.MAX.checked_add(i8.MAX))) { panic("checked_add #215") }
    if !(i8.MAX.wrapping_add(i8.MAX) == (-2i8)) { panic("wrapping_add #216") }
    if !(i8.MAX.overflowing_add(i8.MAX).0 == (-2i8) && i8.MAX.overflowing_add(i8.MAX).1 == true) { panic("overflowing_add #217") }
    if !(i8.MAX.saturating_add(i8.MAX) == i8.MAX) { panic("saturating_add #218") }
    if !(i8.MAX.checked_sub(i8.MAX) == present(0i8)) { panic("checked_sub #219") }
    if !(i8.MAX.wrapping_sub(i8.MAX) == 0i8) { panic("wrapping_sub #220") }
    if !(i8.MAX.overflowing_sub(i8.MAX).0 == 0i8 && i8.MAX.overflowing_sub(i8.MAX).1 == false) { panic("overflowing_sub #221") }
    if !(i8.MAX.saturating_sub(i8.MAX) == 0i8) { panic("saturating_sub #222") }
    if !(i8.MAX.strict_sub(i8.MAX) == 0i8) { panic("strict_sub #223") }
    if !(unsafe { i8.MAX.unchecked_sub(i8.MAX) } == 0i8) { panic("unchecked_sub #224") }
    if !(missing(i8.MAX.checked_mul(i8.MAX))) { panic("checked_mul #225") }
    if !(i8.MAX.wrapping_mul(i8.MAX) == 1i8) { panic("wrapping_mul #226") }
    if !(i8.MAX.overflowing_mul(i8.MAX).0 == 1i8 && i8.MAX.overflowing_mul(i8.MAX).1 == true) { panic("overflowing_mul #227") }
    if !(i8.MAX.saturating_mul(i8.MAX) == i8.MAX) { panic("saturating_mul #228") }
    if !(i8.MAX.checked_div(i8.MAX) == present(1i8)) { panic("checked_div #229") }
    if !(i8.MAX.wrapping_div(i8.MAX) == 1i8) { panic("wrapping_div #230") }
    if !(i8.MAX.overflowing_div(i8.MAX).0 == 1i8 && i8.MAX.overflowing_div(i8.MAX).1 == false) { panic("overflowing_div #231") }
    if !(i8.MAX.strict_div(i8.MAX) == 1i8) { panic("strict_div #232") }
    if !(i8.MAX.saturating_div(i8.MAX) == 1i8) { panic("saturating_div #233") }
    if !(i8.MAX.checked_rem(i8.MAX) == present(0i8)) { panic("checked_rem #234") }
    if !(i8.MAX.wrapping_rem(i8.MAX) == 0i8) { panic("wrapping_rem #235") }
    if !(i8.MAX.overflowing_rem(i8.MAX).0 == 0i8 && i8.MAX.overflowing_rem(i8.MAX).1 == false) { panic("overflowing_rem #236") }
    if !(i8.MAX.strict_rem(i8.MAX) == 0i8) { panic("strict_rem #237") }
    if !(i8.MAX.checked_div_euclid(i8.MAX) == present(1i8)) { panic("checked_div_euclid #238") }
    if !(i8.MAX.wrapping_div_euclid(i8.MAX) == 1i8) { panic("wrapping_div_euclid #239") }
    if !(i8.MAX.overflowing_div_euclid(i8.MAX).0 == 1i8 && i8.MAX.overflowing_div_euclid(i8.MAX).1 == false) { panic("overflowing_div_euclid #240") }
}

fn group2() {
    if !(i8.MAX.strict_div_euclid(i8.MAX) == 1i8) { panic("strict_div_euclid #241") }
    if !(i8.MAX.div_euclid(i8.MAX) == 1i8) { panic("div_euclid #242") }
    if !(i8.MAX.checked_rem_euclid(i8.MAX) == present(0i8)) { panic("checked_rem_euclid #243") }
    if !(i8.MAX.wrapping_rem_euclid(i8.MAX) == 0i8) { panic("wrapping_rem_euclid #244") }
    if !(i8.MAX.overflowing_rem_euclid(i8.MAX).0 == 0i8 && i8.MAX.overflowing_rem_euclid(i8.MAX).1 == false) { panic("overflowing_rem_euclid #245") }
    if !(i8.MAX.strict_rem_euclid(i8.MAX) == 0i8) { panic("strict_rem_euclid #246") }
    if !(i8.MAX.rem_euclid(i8.MAX) == 0i8) { panic("rem_euclid #247") }
    if !(i8.MAX.abs_diff(i8.MAX) == 0u8) { panic("abs_diff #248") }
    if !(i8.MAX.midpoint(i8.MAX) == i8.MAX) { panic("midpoint #249") }
    if !(missing(i8.MIN.checked_add((-1i8)))) { panic("checked_add #250") }
    if !(i8.MIN.wrapping_add((-1i8)) == i8.MAX) { panic("wrapping_add #251") }
    if !(i8.MIN.overflowing_add((-1i8)).0 == i8.MAX && i8.MIN.overflowing_add((-1i8)).1 == true) { panic("overflowing_add #252") }
    if !(i8.MIN.saturating_add((-1i8)) == i8.MIN) { panic("saturating_add #253") }
    if !(i8.MIN.checked_sub((-1i8)) == present((-127i8))) { panic("checked_sub #254") }
    if !(i8.MIN.wrapping_sub((-1i8)) == (-127i8)) { panic("wrapping_sub #255") }
    if !(i8.MIN.overflowing_sub((-1i8)).0 == (-127i8) && i8.MIN.overflowing_sub((-1i8)).1 == false) { panic("overflowing_sub #256") }
    if !(i8.MIN.saturating_sub((-1i8)) == (-127i8)) { panic("saturating_sub #257") }
    if !(i8.MIN.strict_sub((-1i8)) == (-127i8)) { panic("strict_sub #258") }
    if !(unsafe { i8.MIN.unchecked_sub((-1i8)) } == (-127i8)) { panic("unchecked_sub #259") }
    if !(missing(i8.MIN.checked_mul((-1i8)))) { panic("checked_mul #260") }
    if !(i8.MIN.wrapping_mul((-1i8)) == i8.MIN) { panic("wrapping_mul #261") }
    if !(i8.MIN.overflowing_mul((-1i8)).0 == i8.MIN && i8.MIN.overflowing_mul((-1i8)).1 == true) { panic("overflowing_mul #262") }
    if !(i8.MIN.saturating_mul((-1i8)) == i8.MAX) { panic("saturating_mul #263") }
    if !(missing(i8.MIN.checked_div((-1i8)))) { panic("checked_div #264") }
    if !(i8.MIN.wrapping_div((-1i8)) == i8.MIN) { panic("wrapping_div #265") }
    if !(i8.MIN.overflowing_div((-1i8)).0 == i8.MIN && i8.MIN.overflowing_div((-1i8)).1 == true) { panic("overflowing_div #266") }
    if !(i8.MIN.saturating_div((-1i8)) == i8.MAX) { panic("saturating_div #267") }
    if !(missing(i8.MIN.checked_rem((-1i8)))) { panic("checked_rem #268") }
    if !(i8.MIN.wrapping_rem((-1i8)) == 0i8) { panic("wrapping_rem #269") }
    if !(i8.MIN.overflowing_rem((-1i8)).0 == 0i8 && i8.MIN.overflowing_rem((-1i8)).1 == true) { panic("overflowing_rem #270") }
    if !(missing(i8.MIN.checked_div_euclid((-1i8)))) { panic("checked_div_euclid #271") }
    if !(i8.MIN.wrapping_div_euclid((-1i8)) == i8.MIN) { panic("wrapping_div_euclid #272") }
    if !(i8.MIN.overflowing_div_euclid((-1i8)).0 == i8.MIN && i8.MIN.overflowing_div_euclid((-1i8)).1 == true) { panic("overflowing_div_euclid #273") }
    if !(missing(i8.MIN.checked_rem_euclid((-1i8)))) { panic("checked_rem_euclid #274") }
    if !(i8.MIN.wrapping_rem_euclid((-1i8)) == 0i8) { panic("wrapping_rem_euclid #275") }
    if !(i8.MIN.overflowing_rem_euclid((-1i8)).0 == 0i8 && i8.MIN.overflowing_rem_euclid((-1i8)).1 == true) { panic("overflowing_rem_euclid #276") }
    if !(i8.MIN.abs_diff((-1i8)) == 127u8) { panic("abs_diff #277") }
    if !(i8.MIN.midpoint((-1i8)) == (-64i8)) { panic("midpoint #278") }
    if !((-7i8).checked_add(3i8) == present((-4i8))) { panic("checked_add #279") }
    if !((-7i8).wrapping_add(3i8) == (-4i8)) { panic("wrapping_add #280") }
    if !((-7i8).overflowing_add(3i8).0 == (-4i8) && (-7i8).overflowing_add(3i8).1 == false) { panic("overflowing_add #281") }
    if !((-7i8).saturating_add(3i8) == (-4i8)) { panic("saturating_add #282") }
    if !((-7i8).strict_add(3i8) == (-4i8)) { panic("strict_add #283") }
    if !(unsafe { (-7i8).unchecked_add(3i8) } == (-4i8)) { panic("unchecked_add #284") }
    if !((-7i8).checked_sub(3i8) == present((-10i8))) { panic("checked_sub #285") }
    if !((-7i8).wrapping_sub(3i8) == (-10i8)) { panic("wrapping_sub #286") }
    if !((-7i8).overflowing_sub(3i8).0 == (-10i8) && (-7i8).overflowing_sub(3i8).1 == false) { panic("overflowing_sub #287") }
    if !((-7i8).saturating_sub(3i8) == (-10i8)) { panic("saturating_sub #288") }
    if !((-7i8).strict_sub(3i8) == (-10i8)) { panic("strict_sub #289") }
    if !(unsafe { (-7i8).unchecked_sub(3i8) } == (-10i8)) { panic("unchecked_sub #290") }
    if !((-7i8).checked_mul(3i8) == present((-21i8))) { panic("checked_mul #291") }
    if !((-7i8).wrapping_mul(3i8) == (-21i8)) { panic("wrapping_mul #292") }
    if !((-7i8).overflowing_mul(3i8).0 == (-21i8) && (-7i8).overflowing_mul(3i8).1 == false) { panic("overflowing_mul #293") }
    if !((-7i8).saturating_mul(3i8) == (-21i8)) { panic("saturating_mul #294") }
    if !((-7i8).strict_mul(3i8) == (-21i8)) { panic("strict_mul #295") }
    if !(unsafe { (-7i8).unchecked_mul(3i8) } == (-21i8)) { panic("unchecked_mul #296") }
    if !((-7i8).checked_div(3i8) == present((-2i8))) { panic("checked_div #297") }
    if !((-7i8).wrapping_div(3i8) == (-2i8)) { panic("wrapping_div #298") }
    if !((-7i8).overflowing_div(3i8).0 == (-2i8) && (-7i8).overflowing_div(3i8).1 == false) { panic("overflowing_div #299") }
    if !((-7i8).strict_div(3i8) == (-2i8)) { panic("strict_div #300") }
    if !((-7i8).saturating_div(3i8) == (-2i8)) { panic("saturating_div #301") }
    if !((-7i8).checked_rem(3i8) == present((-1i8))) { panic("checked_rem #302") }
    if !((-7i8).wrapping_rem(3i8) == (-1i8)) { panic("wrapping_rem #303") }
    if !((-7i8).overflowing_rem(3i8).0 == (-1i8) && (-7i8).overflowing_rem(3i8).1 == false) { panic("overflowing_rem #304") }
    if !((-7i8).strict_rem(3i8) == (-1i8)) { panic("strict_rem #305") }
    if !((-7i8).checked_div_euclid(3i8) == present((-3i8))) { panic("checked_div_euclid #306") }
    if !((-7i8).wrapping_div_euclid(3i8) == (-3i8)) { panic("wrapping_div_euclid #307") }
    if !((-7i8).overflowing_div_euclid(3i8).0 == (-3i8) && (-7i8).overflowing_div_euclid(3i8).1 == false) { panic("overflowing_div_euclid #308") }
    if !((-7i8).strict_div_euclid(3i8) == (-3i8)) { panic("strict_div_euclid #309") }
    if !((-7i8).div_euclid(3i8) == (-3i8)) { panic("div_euclid #310") }
    if !((-7i8).checked_rem_euclid(3i8) == present(2i8)) { panic("checked_rem_euclid #311") }
    if !((-7i8).wrapping_rem_euclid(3i8) == 2i8) { panic("wrapping_rem_euclid #312") }
    if !((-7i8).overflowing_rem_euclid(3i8).0 == 2i8 && (-7i8).overflowing_rem_euclid(3i8).1 == false) { panic("overflowing_rem_euclid #313") }
    if !((-7i8).strict_rem_euclid(3i8) == 2i8) { panic("strict_rem_euclid #314") }
    if !((-7i8).rem_euclid(3i8) == 2i8) { panic("rem_euclid #315") }
    if !((-7i8).abs_diff(3i8) == 10u8) { panic("abs_diff #316") }
    if !((-7i8).midpoint(3i8) == (-2i8)) { panic("midpoint #317") }
    if !(7i8.checked_add((-3i8)) == present(4i8)) { panic("checked_add #318") }
    if !(7i8.wrapping_add((-3i8)) == 4i8) { panic("wrapping_add #319") }
    if !(7i8.overflowing_add((-3i8)).0 == 4i8 && 7i8.overflowing_add((-3i8)).1 == false) { panic("overflowing_add #320") }
    if !(7i8.saturating_add((-3i8)) == 4i8) { panic("saturating_add #321") }
    if !(7i8.strict_add((-3i8)) == 4i8) { panic("strict_add #322") }
    if !(unsafe { 7i8.unchecked_add((-3i8)) } == 4i8) { panic("unchecked_add #323") }
    if !(7i8.checked_sub((-3i8)) == present(10i8)) { panic("checked_sub #324") }
    if !(7i8.wrapping_sub((-3i8)) == 10i8) { panic("wrapping_sub #325") }
    if !(7i8.overflowing_sub((-3i8)).0 == 10i8 && 7i8.overflowing_sub((-3i8)).1 == false) { panic("overflowing_sub #326") }
    if !(7i8.saturating_sub((-3i8)) == 10i8) { panic("saturating_sub #327") }
    if !(7i8.strict_sub((-3i8)) == 10i8) { panic("strict_sub #328") }
    if !(unsafe { 7i8.unchecked_sub((-3i8)) } == 10i8) { panic("unchecked_sub #329") }
    if !(7i8.checked_mul((-3i8)) == present((-21i8))) { panic("checked_mul #330") }
    if !(7i8.wrapping_mul((-3i8)) == (-21i8)) { panic("wrapping_mul #331") }
    if !(7i8.overflowing_mul((-3i8)).0 == (-21i8) && 7i8.overflowing_mul((-3i8)).1 == false) { panic("overflowing_mul #332") }
    if !(7i8.saturating_mul((-3i8)) == (-21i8)) { panic("saturating_mul #333") }
    if !(7i8.strict_mul((-3i8)) == (-21i8)) { panic("strict_mul #334") }
    if !(unsafe { 7i8.unchecked_mul((-3i8)) } == (-21i8)) { panic("unchecked_mul #335") }
    if !(7i8.checked_div((-3i8)) == present((-2i8))) { panic("checked_div #336") }
    if !(7i8.wrapping_div((-3i8)) == (-2i8)) { panic("wrapping_div #337") }
    if !(7i8.overflowing_div((-3i8)).0 == (-2i8) && 7i8.overflowing_div((-3i8)).1 == false) { panic("overflowing_div #338") }
    if !(7i8.strict_div((-3i8)) == (-2i8)) { panic("strict_div #339") }
    if !(7i8.saturating_div((-3i8)) == (-2i8)) { panic("saturating_div #340") }
    if !(7i8.checked_rem((-3i8)) == present(1i8)) { panic("checked_rem #341") }
    if !(7i8.wrapping_rem((-3i8)) == 1i8) { panic("wrapping_rem #342") }
    if !(7i8.overflowing_rem((-3i8)).0 == 1i8 && 7i8.overflowing_rem((-3i8)).1 == false) { panic("overflowing_rem #343") }
    if !(7i8.strict_rem((-3i8)) == 1i8) { panic("strict_rem #344") }
    if !(7i8.checked_div_euclid((-3i8)) == present((-2i8))) { panic("checked_div_euclid #345") }
    if !(7i8.wrapping_div_euclid((-3i8)) == (-2i8)) { panic("wrapping_div_euclid #346") }
    if !(7i8.overflowing_div_euclid((-3i8)).0 == (-2i8) && 7i8.overflowing_div_euclid((-3i8)).1 == false) { panic("overflowing_div_euclid #347") }
    if !(7i8.strict_div_euclid((-3i8)) == (-2i8)) { panic("strict_div_euclid #348") }
    if !(7i8.div_euclid((-3i8)) == (-2i8)) { panic("div_euclid #349") }
    if !(7i8.checked_rem_euclid((-3i8)) == present(1i8)) { panic("checked_rem_euclid #350") }
    if !(7i8.wrapping_rem_euclid((-3i8)) == 1i8) { panic("wrapping_rem_euclid #351") }
    if !(7i8.overflowing_rem_euclid((-3i8)).0 == 1i8 && 7i8.overflowing_rem_euclid((-3i8)).1 == false) { panic("overflowing_rem_euclid #352") }
    if !(7i8.strict_rem_euclid((-3i8)) == 1i8) { panic("strict_rem_euclid #353") }
    if !(7i8.rem_euclid((-3i8)) == 1i8) { panic("rem_euclid #354") }
    if !(7i8.abs_diff((-3i8)) == 10u8) { panic("abs_diff #355") }
    if !(7i8.midpoint((-3i8)) == 2i8) { panic("midpoint #356") }
    if !((-7i8).checked_add((-3i8)) == present((-10i8))) { panic("checked_add #357") }
    if !((-7i8).wrapping_add((-3i8)) == (-10i8)) { panic("wrapping_add #358") }
    if !((-7i8).overflowing_add((-3i8)).0 == (-10i8) && (-7i8).overflowing_add((-3i8)).1 == false) { panic("overflowing_add #359") }
    if !((-7i8).saturating_add((-3i8)) == (-10i8)) { panic("saturating_add #360") }
}

fn group3() {
    if !((-7i8).strict_add((-3i8)) == (-10i8)) { panic("strict_add #361") }
    if !(unsafe { (-7i8).unchecked_add((-3i8)) } == (-10i8)) { panic("unchecked_add #362") }
    if !((-7i8).checked_sub((-3i8)) == present((-4i8))) { panic("checked_sub #363") }
    if !((-7i8).wrapping_sub((-3i8)) == (-4i8)) { panic("wrapping_sub #364") }
    if !((-7i8).overflowing_sub((-3i8)).0 == (-4i8) && (-7i8).overflowing_sub((-3i8)).1 == false) { panic("overflowing_sub #365") }
    if !((-7i8).saturating_sub((-3i8)) == (-4i8)) { panic("saturating_sub #366") }
    if !((-7i8).strict_sub((-3i8)) == (-4i8)) { panic("strict_sub #367") }
    if !(unsafe { (-7i8).unchecked_sub((-3i8)) } == (-4i8)) { panic("unchecked_sub #368") }
    if !((-7i8).checked_mul((-3i8)) == present(21i8)) { panic("checked_mul #369") }
    if !((-7i8).wrapping_mul((-3i8)) == 21i8) { panic("wrapping_mul #370") }
    if !((-7i8).overflowing_mul((-3i8)).0 == 21i8 && (-7i8).overflowing_mul((-3i8)).1 == false) { panic("overflowing_mul #371") }
    if !((-7i8).saturating_mul((-3i8)) == 21i8) { panic("saturating_mul #372") }
    if !((-7i8).strict_mul((-3i8)) == 21i8) { panic("strict_mul #373") }
    if !(unsafe { (-7i8).unchecked_mul((-3i8)) } == 21i8) { panic("unchecked_mul #374") }
    if !((-7i8).checked_div((-3i8)) == present(2i8)) { panic("checked_div #375") }
    if !((-7i8).wrapping_div((-3i8)) == 2i8) { panic("wrapping_div #376") }
    if !((-7i8).overflowing_div((-3i8)).0 == 2i8 && (-7i8).overflowing_div((-3i8)).1 == false) { panic("overflowing_div #377") }
    if !((-7i8).strict_div((-3i8)) == 2i8) { panic("strict_div #378") }
    if !((-7i8).saturating_div((-3i8)) == 2i8) { panic("saturating_div #379") }
    if !((-7i8).checked_rem((-3i8)) == present((-1i8))) { panic("checked_rem #380") }
    if !((-7i8).wrapping_rem((-3i8)) == (-1i8)) { panic("wrapping_rem #381") }
    if !((-7i8).overflowing_rem((-3i8)).0 == (-1i8) && (-7i8).overflowing_rem((-3i8)).1 == false) { panic("overflowing_rem #382") }
    if !((-7i8).strict_rem((-3i8)) == (-1i8)) { panic("strict_rem #383") }
    if !((-7i8).checked_div_euclid((-3i8)) == present(3i8)) { panic("checked_div_euclid #384") }
    if !((-7i8).wrapping_div_euclid((-3i8)) == 3i8) { panic("wrapping_div_euclid #385") }
    if !((-7i8).overflowing_div_euclid((-3i8)).0 == 3i8 && (-7i8).overflowing_div_euclid((-3i8)).1 == false) { panic("overflowing_div_euclid #386") }
    if !((-7i8).strict_div_euclid((-3i8)) == 3i8) { panic("strict_div_euclid #387") }
    if !((-7i8).div_euclid((-3i8)) == 3i8) { panic("div_euclid #388") }
    if !((-7i8).checked_rem_euclid((-3i8)) == present(2i8)) { panic("checked_rem_euclid #389") }
    if !((-7i8).wrapping_rem_euclid((-3i8)) == 2i8) { panic("wrapping_rem_euclid #390") }
    if !((-7i8).overflowing_rem_euclid((-3i8)).0 == 2i8 && (-7i8).overflowing_rem_euclid((-3i8)).1 == false) { panic("overflowing_rem_euclid #391") }
    if !((-7i8).strict_rem_euclid((-3i8)) == 2i8) { panic("strict_rem_euclid #392") }
    if !((-7i8).rem_euclid((-3i8)) == 2i8) { panic("rem_euclid #393") }
    if !((-7i8).abs_diff((-3i8)) == 4u8) { panic("abs_diff #394") }
    if !((-7i8).midpoint((-3i8)) == (-5i8)) { panic("midpoint #395") }
    if !(missing(i8.MIN.checked_add(i8.MIN))) { panic("checked_add #396") }
    if !(i8.MIN.wrapping_add(i8.MIN) == 0i8) { panic("wrapping_add #397") }
    if !(i8.MIN.overflowing_add(i8.MIN).0 == 0i8 && i8.MIN.overflowing_add(i8.MIN).1 == true) { panic("overflowing_add #398") }
    if !(i8.MIN.saturating_add(i8.MIN) == i8.MIN) { panic("saturating_add #399") }
    if !(i8.MIN.checked_sub(i8.MIN) == present(0i8)) { panic("checked_sub #400") }
    if !(i8.MIN.wrapping_sub(i8.MIN) == 0i8) { panic("wrapping_sub #401") }
    if !(i8.MIN.overflowing_sub(i8.MIN).0 == 0i8 && i8.MIN.overflowing_sub(i8.MIN).1 == false) { panic("overflowing_sub #402") }
    if !(i8.MIN.saturating_sub(i8.MIN) == 0i8) { panic("saturating_sub #403") }
    if !(i8.MIN.strict_sub(i8.MIN) == 0i8) { panic("strict_sub #404") }
    if !(unsafe { i8.MIN.unchecked_sub(i8.MIN) } == 0i8) { panic("unchecked_sub #405") }
    if !(missing(i8.MIN.checked_mul(i8.MIN))) { panic("checked_mul #406") }
    if !(i8.MIN.wrapping_mul(i8.MIN) == 0i8) { panic("wrapping_mul #407") }
    if !(i8.MIN.overflowing_mul(i8.MIN).0 == 0i8 && i8.MIN.overflowing_mul(i8.MIN).1 == true) { panic("overflowing_mul #408") }
    if !(i8.MIN.saturating_mul(i8.MIN) == i8.MAX) { panic("saturating_mul #409") }
    if !(i8.MIN.checked_div(i8.MIN) == present(1i8)) { panic("checked_div #410") }
    if !(i8.MIN.wrapping_div(i8.MIN) == 1i8) { panic("wrapping_div #411") }
    if !(i8.MIN.overflowing_div(i8.MIN).0 == 1i8 && i8.MIN.overflowing_div(i8.MIN).1 == false) { panic("overflowing_div #412") }
    if !(i8.MIN.strict_div(i8.MIN) == 1i8) { panic("strict_div #413") }
    if !(i8.MIN.saturating_div(i8.MIN) == 1i8) { panic("saturating_div #414") }
    if !(i8.MIN.checked_rem(i8.MIN) == present(0i8)) { panic("checked_rem #415") }
    if !(i8.MIN.wrapping_rem(i8.MIN) == 0i8) { panic("wrapping_rem #416") }
    if !(i8.MIN.overflowing_rem(i8.MIN).0 == 0i8 && i8.MIN.overflowing_rem(i8.MIN).1 == false) { panic("overflowing_rem #417") }
    if !(i8.MIN.strict_rem(i8.MIN) == 0i8) { panic("strict_rem #418") }
    if !(i8.MIN.checked_div_euclid(i8.MIN) == present(1i8)) { panic("checked_div_euclid #419") }
    if !(i8.MIN.wrapping_div_euclid(i8.MIN) == 1i8) { panic("wrapping_div_euclid #420") }
    if !(i8.MIN.overflowing_div_euclid(i8.MIN).0 == 1i8 && i8.MIN.overflowing_div_euclid(i8.MIN).1 == false) { panic("overflowing_div_euclid #421") }
    if !(i8.MIN.strict_div_euclid(i8.MIN) == 1i8) { panic("strict_div_euclid #422") }
    if !(i8.MIN.div_euclid(i8.MIN) == 1i8) { panic("div_euclid #423") }
    if !(i8.MIN.checked_rem_euclid(i8.MIN) == present(0i8)) { panic("checked_rem_euclid #424") }
    if !(i8.MIN.wrapping_rem_euclid(i8.MIN) == 0i8) { panic("wrapping_rem_euclid #425") }
    if !(i8.MIN.overflowing_rem_euclid(i8.MIN).0 == 0i8 && i8.MIN.overflowing_rem_euclid(i8.MIN).1 == false) { panic("overflowing_rem_euclid #426") }
    if !(i8.MIN.strict_rem_euclid(i8.MIN) == 0i8) { panic("strict_rem_euclid #427") }
    if !(i8.MIN.rem_euclid(i8.MIN) == 0i8) { panic("rem_euclid #428") }
    if !(i8.MIN.abs_diff(i8.MIN) == 0u8) { panic("abs_diff #429") }
    if !(i8.MIN.midpoint(i8.MIN) == i8.MIN) { panic("midpoint #430") }
    if !(missing(i8.MAX.checked_add_unsigned(1u8))) { panic("checked_add_unsigned #431") }
    if !(i8.MAX.wrapping_add_unsigned(1u8) == i8.MIN) { panic("wrapping_add_unsigned #432") }
    if !(i8.MAX.overflowing_add_unsigned(1u8).0 == i8.MIN && i8.MAX.overflowing_add_unsigned(1u8).1 == true) { panic("overflowing_add_unsigned #433") }
    if !(i8.MAX.saturating_add_unsigned(1u8) == i8.MAX) { panic("saturating_add_unsigned #434") }
    if !(i8.MAX.checked_sub_unsigned(1u8) == present(126i8)) { panic("checked_sub_unsigned #435") }
    if !(i8.MAX.wrapping_sub_unsigned(1u8) == 126i8) { panic("wrapping_sub_unsigned #436") }
    if !(i8.MAX.overflowing_sub_unsigned(1u8).0 == 126i8 && i8.MAX.overflowing_sub_unsigned(1u8).1 == false) { panic("overflowing_sub_unsigned #437") }
    if !(i8.MAX.saturating_sub_unsigned(1u8) == 126i8) { panic("saturating_sub_unsigned #438") }
    if !(i8.MAX.strict_sub_unsigned(1u8) == 126i8) { panic("strict_sub_unsigned #439") }
    if !(i8.MIN.checked_add_unsigned(u8.MAX) == present(i8.MAX)) { panic("checked_add_unsigned #440") }
    if !(i8.MIN.wrapping_add_unsigned(u8.MAX) == i8.MAX) { panic("wrapping_add_unsigned #441") }
    if !(i8.MIN.overflowing_add_unsigned(u8.MAX).0 == i8.MAX && i8.MIN.overflowing_add_unsigned(u8.MAX).1 == false) { panic("overflowing_add_unsigned #442") }
    if !(i8.MIN.saturating_add_unsigned(u8.MAX) == i8.MAX) { panic("saturating_add_unsigned #443") }
    if !(i8.MIN.strict_add_unsigned(u8.MAX) == i8.MAX) { panic("strict_add_unsigned #444") }
    if !(missing(i8.MIN.checked_sub_unsigned(u8.MAX))) { panic("checked_sub_unsigned #445") }
    if !(i8.MIN.wrapping_sub_unsigned(u8.MAX) == (-127i8)) { panic("wrapping_sub_unsigned #446") }
    if !(i8.MIN.overflowing_sub_unsigned(u8.MAX).0 == (-127i8) && i8.MIN.overflowing_sub_unsigned(u8.MAX).1 == true) { panic("overflowing_sub_unsigned #447") }
    if !(i8.MIN.saturating_sub_unsigned(u8.MAX) == i8.MIN) { panic("saturating_sub_unsigned #448") }
    if !((-7i8).checked_add_unsigned(3u8) == present((-4i8))) { panic("checked_add_unsigned #449") }
    if !((-7i8).wrapping_add_unsigned(3u8) == (-4i8)) { panic("wrapping_add_unsigned #450") }
    if !((-7i8).overflowing_add_unsigned(3u8).0 == (-4i8) && (-7i8).overflowing_add_unsigned(3u8).1 == false) { panic("overflowing_add_unsigned #451") }
    if !((-7i8).saturating_add_unsigned(3u8) == (-4i8)) { panic("saturating_add_unsigned #452") }
    if !((-7i8).strict_add_unsigned(3u8) == (-4i8)) { panic("strict_add_unsigned #453") }
    if !((-7i8).checked_sub_unsigned(3u8) == present((-10i8))) { panic("checked_sub_unsigned #454") }
    if !((-7i8).wrapping_sub_unsigned(3u8) == (-10i8)) { panic("wrapping_sub_unsigned #455") }
    if !((-7i8).overflowing_sub_unsigned(3u8).0 == (-10i8) && (-7i8).overflowing_sub_unsigned(3u8).1 == false) { panic("overflowing_sub_unsigned #456") }
    if !((-7i8).saturating_sub_unsigned(3u8) == (-10i8)) { panic("saturating_sub_unsigned #457") }
    if !((-7i8).strict_sub_unsigned(3u8) == (-10i8)) { panic("strict_sub_unsigned #458") }
    if !(i8.MIN.checked_add_unsigned(0u8) == present(i8.MIN)) { panic("checked_add_unsigned #459") }
    if !(i8.MIN.wrapping_add_unsigned(0u8) == i8.MIN) { panic("wrapping_add_unsigned #460") }
    if !(i8.MIN.overflowing_add_unsigned(0u8).0 == i8.MIN && i8.MIN.overflowing_add_unsigned(0u8).1 == false) { panic("overflowing_add_unsigned #461") }
    if !(i8.MIN.saturating_add_unsigned(0u8) == i8.MIN) { panic("saturating_add_unsigned #462") }
    if !(i8.MIN.strict_add_unsigned(0u8) == i8.MIN) { panic("strict_add_unsigned #463") }
    if !(i8.MIN.checked_sub_unsigned(0u8) == present(i8.MIN)) { panic("checked_sub_unsigned #464") }
    if !(i8.MIN.wrapping_sub_unsigned(0u8) == i8.MIN) { panic("wrapping_sub_unsigned #465") }
    if !(i8.MIN.overflowing_sub_unsigned(0u8).0 == i8.MIN && i8.MIN.overflowing_sub_unsigned(0u8).1 == false) { panic("overflowing_sub_unsigned #466") }
    if !(i8.MIN.saturating_sub_unsigned(0u8) == i8.MIN) { panic("saturating_sub_unsigned #467") }
    if !(i8.MIN.strict_sub_unsigned(0u8) == i8.MIN) { panic("strict_sub_unsigned #468") }
    if !(missing((-1i8).checked_add_unsigned(u8.MAX))) { panic("checked_add_unsigned #469") }
    if !((-1i8).wrapping_add_unsigned(u8.MAX) == (-2i8)) { panic("wrapping_add_unsigned #470") }
    if !((-1i8).overflowing_add_unsigned(u8.MAX).0 == (-2i8) && (-1i8).overflowing_add_unsigned(u8.MAX).1 == true) { panic("overflowing_add_unsigned #471") }
    if !((-1i8).saturating_add_unsigned(u8.MAX) == i8.MAX) { panic("saturating_add_unsigned #472") }
    if !(missing((-1i8).checked_sub_unsigned(u8.MAX))) { panic("checked_sub_unsigned #473") }
    if !((-1i8).wrapping_sub_unsigned(u8.MAX) == 0i8) { panic("wrapping_sub_unsigned #474") }
    if !((-1i8).overflowing_sub_unsigned(u8.MAX).0 == 0i8 && (-1i8).overflowing_sub_unsigned(u8.MAX).1 == true) { panic("overflowing_sub_unsigned #475") }
    if !((-1i8).saturating_sub_unsigned(u8.MAX) == i8.MIN) { panic("saturating_sub_unsigned #476") }
    if !(i8.MAX.checked_neg() == present((-127i8))) { panic("checked_neg #477") }
    if !(i8.MAX.wrapping_neg() == (-127i8)) { panic("wrapping_neg #478") }
    if !(i8.MAX.overflowing_neg().0 == (-127i8) && i8.MAX.overflowing_neg().1 == false) { panic("overflowing_neg #479") }
    if !(i8.MAX.strict_neg() == (-127i8)) { panic("strict_neg #480") }
}

fn group4() {
    if !(unsafe { i8.MAX.unchecked_neg() } == (-127i8)) { panic("unchecked_neg #481") }
    if !(i8.MAX.saturating_neg() == (-127i8)) { panic("saturating_neg #482") }
    if !(i8.MAX.checked_abs() == present(i8.MAX)) { panic("checked_abs #483") }
    if !(i8.MAX.wrapping_abs() == i8.MAX) { panic("wrapping_abs #484") }
    if !(i8.MAX.overflowing_abs().0 == i8.MAX && i8.MAX.overflowing_abs().1 == false) { panic("overflowing_abs #485") }
    if !(i8.MAX.saturating_abs() == i8.MAX) { panic("saturating_abs #486") }
    if !(i8.MAX.strict_abs() == i8.MAX) { panic("strict_abs #487") }
    if !(i8.MAX.abs() == i8.MAX) { panic("abs #488") }
    if !(i8.MAX.unsigned_abs() == 127u8) { panic("unsigned_abs #489") }
    if !(i8.MAX.signum() == 1i8) { panic("signum #490") }
    if !(i8.MAX.is_positive() == true) { panic("is_positive #491") }
    if !(i8.MAX.is_negative() == false) { panic("is_negative #492") }
    if !(i8.MAX.cast_unsigned() == 127u8) { panic("cast_unsigned #493") }
    if !(i8.MAX.count_ones() == 7u32) { panic("count_ones #494") }
    if !(i8.MAX.count_zeros() == 1u32) { panic("count_zeros #495") }
    if !(i8.MAX.leading_zeros() == 1u32) { panic("leading_zeros #496") }
    if !(i8.MAX.trailing_zeros() == 0u32) { panic("trailing_zeros #497") }
    if !(i8.MAX.leading_ones() == 0u32) { panic("leading_ones #498") }
    if !(i8.MAX.trailing_ones() == 7u32) { panic("trailing_ones #499") }
    if !(i8.MAX.reverse_bits() == (-2i8)) { panic("reverse_bits #500") }
    if !(i8.MAX.swap_bytes() == i8.MAX) { panic("swap_bytes #501") }
    if !(i8.MAX.to_be() == i8.MAX) { panic("to_be #502") }
    if !(i8.MAX.to_le() == i8.MAX) { panic("to_le #503") }
    if !(i8.from_be(i8.MAX) == i8.MAX) { panic("from_be #504") }
    if !(i8.from_le(i8.MAX) == i8.MAX) { panic("from_le #505") }
    if !(i8.MAX.to_le_bytes() == [127u8]) { panic("to_le_bytes #506") }
    if !(i8.MAX.to_be_bytes() == [127u8]) { panic("to_be_bytes #507") }
    if !(i8.MAX.to_ne_bytes() == [127u8]) { panic("to_ne_bytes #508") }
    if !(i8.from_le_bytes([127u8]) == i8.MAX) { panic("from_le_bytes #509") }
    if !(i8.from_be_bytes([127u8]) == i8.MAX) { panic("from_be_bytes #510") }
    if !(i8.from_ne_bytes([127u8]) == i8.MAX) { panic("from_ne_bytes #511") }
    if !(i8.MAX.rotate_left(0u32) == i8.MAX) { panic("rotate_left #512") }
    if !(i8.MAX.rotate_right(0u32) == i8.MAX) { panic("rotate_right #513") }
    if !(i8.MAX.checked_shl(0u32) == present(i8.MAX)) { panic("checked_shl #514") }
    if !(i8.MAX.checked_shr(0u32) == present(i8.MAX)) { panic("checked_shr #515") }
    if !(i8.MAX.wrapping_shl(0u32) == i8.MAX) { panic("wrapping_shl #516") }
    if !(i8.MAX.wrapping_shr(0u32) == i8.MAX) { panic("wrapping_shr #517") }
    if !(i8.MAX.overflowing_shl(0u32).0 == i8.MAX && i8.MAX.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #518") }
    if !(i8.MAX.overflowing_shr(0u32).0 == i8.MAX && i8.MAX.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #519") }
    if !(i8.MAX.unbounded_shl(0u32) == i8.MAX) { panic("unbounded_shl #520") }
    if !(i8.MAX.unbounded_shr(0u32) == i8.MAX) { panic("unbounded_shr #521") }
    if !(i8.MAX.strict_shl(0u32) == i8.MAX) { panic("strict_shl #522") }
    if !(i8.MAX.strict_shr(0u32) == i8.MAX) { panic("strict_shr #523") }
    if !(unsafe { i8.MAX.unchecked_shl(0u32) } == i8.MAX) { panic("unchecked_shl #524") }
    if !(unsafe { i8.MAX.unchecked_shr(0u32) } == i8.MAX) { panic("unchecked_shr #525") }
    if !(i8.MAX.rotate_left(1u32) == (-2i8)) { panic("rotate_left #526") }
    if !(i8.MAX.rotate_right(1u32) == (-65i8)) { panic("rotate_right #527") }
    if !(i8.MAX.checked_shl(1u32) == present((-2i8))) { panic("checked_shl #528") }
    if !(i8.MAX.checked_shr(1u32) == present(63i8)) { panic("checked_shr #529") }
    if !(i8.MAX.wrapping_shl(1u32) == (-2i8)) { panic("wrapping_shl #530") }
    if !(i8.MAX.wrapping_shr(1u32) == 63i8) { panic("wrapping_shr #531") }
    if !(i8.MAX.overflowing_shl(1u32).0 == (-2i8) && i8.MAX.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #532") }
    if !(i8.MAX.overflowing_shr(1u32).0 == 63i8 && i8.MAX.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #533") }
    if !(i8.MAX.unbounded_shl(1u32) == (-2i8)) { panic("unbounded_shl #534") }
    if !(i8.MAX.unbounded_shr(1u32) == 63i8) { panic("unbounded_shr #535") }
    if !(i8.MAX.strict_shl(1u32) == (-2i8)) { panic("strict_shl #536") }
    if !(i8.MAX.strict_shr(1u32) == 63i8) { panic("strict_shr #537") }
    if !(unsafe { i8.MAX.unchecked_shl(1u32) } == (-2i8)) { panic("unchecked_shl #538") }
    if !(unsafe { i8.MAX.unchecked_shr(1u32) } == 63i8) { panic("unchecked_shr #539") }
    if !(i8.MAX.rotate_left(3u32) == (-5i8)) { panic("rotate_left #540") }
    if !(i8.MAX.rotate_right(3u32) == (-17i8)) { panic("rotate_right #541") }
    if !(i8.MAX.checked_shl(3u32) == present((-8i8))) { panic("checked_shl #542") }
    if !(i8.MAX.checked_shr(3u32) == present(15i8)) { panic("checked_shr #543") }
    if !(i8.MAX.wrapping_shl(3u32) == (-8i8)) { panic("wrapping_shl #544") }
    if !(i8.MAX.wrapping_shr(3u32) == 15i8) { panic("wrapping_shr #545") }
    if !(i8.MAX.overflowing_shl(3u32).0 == (-8i8) && i8.MAX.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #546") }
    if !(i8.MAX.overflowing_shr(3u32).0 == 15i8 && i8.MAX.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #547") }
    if !(i8.MAX.unbounded_shl(3u32) == (-8i8)) { panic("unbounded_shl #548") }
    if !(i8.MAX.unbounded_shr(3u32) == 15i8) { panic("unbounded_shr #549") }
    if !(i8.MAX.strict_shl(3u32) == (-8i8)) { panic("strict_shl #550") }
    if !(i8.MAX.strict_shr(3u32) == 15i8) { panic("strict_shr #551") }
    if !(unsafe { i8.MAX.unchecked_shl(3u32) } == (-8i8)) { panic("unchecked_shl #552") }
    if !(unsafe { i8.MAX.unchecked_shr(3u32) } == 15i8) { panic("unchecked_shr #553") }
    if !(i8.MAX.rotate_left(7u32) == (-65i8)) { panic("rotate_left #554") }
    if !(i8.MAX.rotate_right(7u32) == (-2i8)) { panic("rotate_right #555") }
    if !(i8.MAX.checked_shl(7u32) == present(i8.MIN)) { panic("checked_shl #556") }
    if !(i8.MAX.checked_shr(7u32) == present(0i8)) { panic("checked_shr #557") }
    if !(i8.MAX.wrapping_shl(7u32) == i8.MIN) { panic("wrapping_shl #558") }
    if !(i8.MAX.wrapping_shr(7u32) == 0i8) { panic("wrapping_shr #559") }
    if !(i8.MAX.overflowing_shl(7u32).0 == i8.MIN && i8.MAX.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #560") }
    if !(i8.MAX.overflowing_shr(7u32).0 == 0i8 && i8.MAX.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #561") }
    if !(i8.MAX.unbounded_shl(7u32) == i8.MIN) { panic("unbounded_shl #562") }
    if !(i8.MAX.unbounded_shr(7u32) == 0i8) { panic("unbounded_shr #563") }
    if !(i8.MAX.strict_shl(7u32) == i8.MIN) { panic("strict_shl #564") }
    if !(i8.MAX.strict_shr(7u32) == 0i8) { panic("strict_shr #565") }
    if !(unsafe { i8.MAX.unchecked_shl(7u32) } == i8.MIN) { panic("unchecked_shl #566") }
    if !(unsafe { i8.MAX.unchecked_shr(7u32) } == 0i8) { panic("unchecked_shr #567") }
    if !(i8.MAX.rotate_left(8u32) == i8.MAX) { panic("rotate_left #568") }
    if !(i8.MAX.rotate_right(8u32) == i8.MAX) { panic("rotate_right #569") }
    if !(missing(i8.MAX.checked_shl(8u32))) { panic("checked_shl #570") }
    if !(missing(i8.MAX.checked_shr(8u32))) { panic("checked_shr #571") }
    if !(i8.MAX.wrapping_shl(8u32) == i8.MAX) { panic("wrapping_shl #572") }
    if !(i8.MAX.wrapping_shr(8u32) == i8.MAX) { panic("wrapping_shr #573") }
    if !(i8.MAX.overflowing_shl(8u32).0 == i8.MAX && i8.MAX.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #574") }
    if !(i8.MAX.overflowing_shr(8u32).0 == i8.MAX && i8.MAX.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #575") }
    if !(i8.MAX.unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #576") }
    if !(i8.MAX.unbounded_shr(8u32) == 0i8) { panic("unbounded_shr #577") }
    if !(i8.MAX.rotate_left(13u32) == (-17i8)) { panic("rotate_left #578") }
    if !(i8.MAX.rotate_right(13u32) == (-5i8)) { panic("rotate_right #579") }
    if !(missing(i8.MAX.checked_shl(13u32))) { panic("checked_shl #580") }
    if !(missing(i8.MAX.checked_shr(13u32))) { panic("checked_shr #581") }
    if !(i8.MAX.wrapping_shl(13u32) == (-32i8)) { panic("wrapping_shl #582") }
    if !(i8.MAX.wrapping_shr(13u32) == 3i8) { panic("wrapping_shr #583") }
    if !(i8.MAX.overflowing_shl(13u32).0 == (-32i8) && i8.MAX.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #584") }
    if !(i8.MAX.overflowing_shr(13u32).0 == 3i8 && i8.MAX.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #585") }
    if !(i8.MAX.unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #586") }
    if !(i8.MAX.unbounded_shr(13u32) == 0i8) { panic("unbounded_shr #587") }
    if !(i8.MAX.checked_pow(0u32) == present(1i8)) { panic("checked_pow #588") }
    if !(i8.MAX.wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #589") }
    if !(i8.MAX.overflowing_pow(0u32).0 == 1i8 && i8.MAX.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #590") }
    if !(i8.MAX.saturating_pow(0u32) == 1i8) { panic("saturating_pow #591") }
    if !(i8.MAX.pow(0u32) == 1i8) { panic("pow #592") }
    if !(i8.MAX.strict_pow(0u32) == 1i8) { panic("strict_pow #593") }
    if !(i8.MAX.checked_pow(1u32) == present(i8.MAX)) { panic("checked_pow #594") }
    if !(i8.MAX.wrapping_pow(1u32) == i8.MAX) { panic("wrapping_pow #595") }
    if !(i8.MAX.overflowing_pow(1u32).0 == i8.MAX && i8.MAX.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #596") }
    if !(i8.MAX.saturating_pow(1u32) == i8.MAX) { panic("saturating_pow #597") }
    if !(i8.MAX.pow(1u32) == i8.MAX) { panic("pow #598") }
    if !(i8.MAX.strict_pow(1u32) == i8.MAX) { panic("strict_pow #599") }
    if !(missing(i8.MAX.checked_pow(2u32))) { panic("checked_pow #600") }
}

fn group5() {
    if !(i8.MAX.wrapping_pow(2u32) == 1i8) { panic("wrapping_pow #601") }
    if !(i8.MAX.overflowing_pow(2u32).0 == 1i8 && i8.MAX.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #602") }
    if !(i8.MAX.saturating_pow(2u32) == i8.MAX) { panic("saturating_pow #603") }
    if !(missing(i8.MAX.checked_pow(3u32))) { panic("checked_pow #604") }
    if !(i8.MAX.wrapping_pow(3u32) == i8.MAX) { panic("wrapping_pow #605") }
    if !(i8.MAX.overflowing_pow(3u32).0 == i8.MAX && i8.MAX.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #606") }
    if !(i8.MAX.saturating_pow(3u32) == i8.MAX) { panic("saturating_pow #607") }
    if !(missing(i8.MAX.checked_pow(7u32))) { panic("checked_pow #608") }
    if !(i8.MAX.wrapping_pow(7u32) == i8.MAX) { panic("wrapping_pow #609") }
    if !(i8.MAX.overflowing_pow(7u32).0 == i8.MAX && i8.MAX.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #610") }
    if !(i8.MAX.saturating_pow(7u32) == i8.MAX) { panic("saturating_pow #611") }
    if !(missing(i8.MAX.checked_pow(8u32))) { panic("checked_pow #612") }
    if !(i8.MAX.wrapping_pow(8u32) == 1i8) { panic("wrapping_pow #613") }
    if !(i8.MAX.overflowing_pow(8u32).0 == 1i8 && i8.MAX.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #614") }
    if !(i8.MAX.saturating_pow(8u32) == i8.MAX) { panic("saturating_pow #615") }
    if !(i8.MAX.ilog2() == 6u32) { panic("ilog2 #616") }
    if !(i8.MAX.ilog10() == 2u32) { panic("ilog10 #617") }
    if !(i8.MAX.checked_ilog2() == present(6u32)) { panic("checked_ilog2 #618") }
    if !(i8.MAX.checked_ilog10() == present(2u32)) { panic("checked_ilog10 #619") }
    if !(i8.MAX.ilog(2i8) == 6u32) { panic("ilog #620") }
    if !(i8.MAX.checked_ilog(2i8) == present(6u32)) { panic("checked_ilog #621") }
    if !(i8.MAX.ilog(3i8) == 4u32) { panic("ilog #622") }
    if !(i8.MAX.checked_ilog(3i8) == present(4u32)) { panic("checked_ilog #623") }
    if !(i8.MAX.ilog(7i8) == 2u32) { panic("ilog #624") }
    if !(i8.MAX.checked_ilog(7i8) == present(2u32)) { panic("checked_ilog #625") }
    if !(missing(i8.MAX.checked_ilog(1i8))) { panic("checked_ilog #626") }
    if !(i8.MAX.isqrt() == 11i8) { panic("isqrt #627") }
    if !(i8.MAX.checked_isqrt() == present(11i8)) { panic("checked_isqrt #628") }
    if !(i8.MAX.highest_one() == present(6u32)) { panic("highest_one #629") }
    if !(i8.MAX.lowest_one() == present(0u32)) { panic("lowest_one #630") }
    if !(i8.MAX.isolate_highest_one() == 64i8) { panic("isolate_highest_one #631") }
    if !(i8.MAX.isolate_lowest_one() == 1i8) { panic("isolate_lowest_one #632") }
    if !(missing(i8.MIN.checked_neg())) { panic("checked_neg #633") }
    if !(i8.MIN.wrapping_neg() == i8.MIN) { panic("wrapping_neg #634") }
    if !(i8.MIN.overflowing_neg().0 == i8.MIN && i8.MIN.overflowing_neg().1 == true) { panic("overflowing_neg #635") }
    if !(i8.MIN.saturating_neg() == i8.MAX) { panic("saturating_neg #636") }
    if !(missing(i8.MIN.checked_abs())) { panic("checked_abs #637") }
    if !(i8.MIN.wrapping_abs() == i8.MIN) { panic("wrapping_abs #638") }
    if !(i8.MIN.overflowing_abs().0 == i8.MIN && i8.MIN.overflowing_abs().1 == true) { panic("overflowing_abs #639") }
    if !(i8.MIN.saturating_abs() == i8.MAX) { panic("saturating_abs #640") }
    if !(i8.MIN.unsigned_abs() == 128u8) { panic("unsigned_abs #641") }
    if !(i8.MIN.signum() == (-1i8)) { panic("signum #642") }
    if !(i8.MIN.is_positive() == false) { panic("is_positive #643") }
    if !(i8.MIN.is_negative() == true) { panic("is_negative #644") }
    if !(i8.MIN.cast_unsigned() == 128u8) { panic("cast_unsigned #645") }
    if !(i8.MIN.count_ones() == 1u32) { panic("count_ones #646") }
    if !(i8.MIN.count_zeros() == 7u32) { panic("count_zeros #647") }
    if !(i8.MIN.leading_zeros() == 0u32) { panic("leading_zeros #648") }
    if !(i8.MIN.trailing_zeros() == 7u32) { panic("trailing_zeros #649") }
    if !(i8.MIN.leading_ones() == 1u32) { panic("leading_ones #650") }
    if !(i8.MIN.trailing_ones() == 0u32) { panic("trailing_ones #651") }
    if !(i8.MIN.reverse_bits() == 1i8) { panic("reverse_bits #652") }
    if !(i8.MIN.swap_bytes() == i8.MIN) { panic("swap_bytes #653") }
    if !(i8.MIN.to_be() == i8.MIN) { panic("to_be #654") }
    if !(i8.MIN.to_le() == i8.MIN) { panic("to_le #655") }
    if !(i8.from_be(i8.MIN) == i8.MIN) { panic("from_be #656") }
    if !(i8.from_le(i8.MIN) == i8.MIN) { panic("from_le #657") }
    if !(i8.MIN.to_le_bytes() == [128u8]) { panic("to_le_bytes #658") }
    if !(i8.MIN.to_be_bytes() == [128u8]) { panic("to_be_bytes #659") }
    if !(i8.MIN.to_ne_bytes() == [128u8]) { panic("to_ne_bytes #660") }
    if !(i8.from_le_bytes([128u8]) == i8.MIN) { panic("from_le_bytes #661") }
    if !(i8.from_be_bytes([128u8]) == i8.MIN) { panic("from_be_bytes #662") }
    if !(i8.from_ne_bytes([128u8]) == i8.MIN) { panic("from_ne_bytes #663") }
    if !(i8.MIN.rotate_left(0u32) == i8.MIN) { panic("rotate_left #664") }
    if !(i8.MIN.rotate_right(0u32) == i8.MIN) { panic("rotate_right #665") }
    if !(i8.MIN.checked_shl(0u32) == present(i8.MIN)) { panic("checked_shl #666") }
    if !(i8.MIN.checked_shr(0u32) == present(i8.MIN)) { panic("checked_shr #667") }
    if !(i8.MIN.wrapping_shl(0u32) == i8.MIN) { panic("wrapping_shl #668") }
    if !(i8.MIN.wrapping_shr(0u32) == i8.MIN) { panic("wrapping_shr #669") }
    if !(i8.MIN.overflowing_shl(0u32).0 == i8.MIN && i8.MIN.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #670") }
    if !(i8.MIN.overflowing_shr(0u32).0 == i8.MIN && i8.MIN.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #671") }
    if !(i8.MIN.unbounded_shl(0u32) == i8.MIN) { panic("unbounded_shl #672") }
    if !(i8.MIN.unbounded_shr(0u32) == i8.MIN) { panic("unbounded_shr #673") }
    if !(i8.MIN.strict_shl(0u32) == i8.MIN) { panic("strict_shl #674") }
    if !(i8.MIN.strict_shr(0u32) == i8.MIN) { panic("strict_shr #675") }
    if !(unsafe { i8.MIN.unchecked_shl(0u32) } == i8.MIN) { panic("unchecked_shl #676") }
    if !(unsafe { i8.MIN.unchecked_shr(0u32) } == i8.MIN) { panic("unchecked_shr #677") }
    if !(i8.MIN.rotate_left(1u32) == 1i8) { panic("rotate_left #678") }
    if !(i8.MIN.rotate_right(1u32) == 64i8) { panic("rotate_right #679") }
    if !(i8.MIN.checked_shl(1u32) == present(0i8)) { panic("checked_shl #680") }
    if !(i8.MIN.checked_shr(1u32) == present((-64i8))) { panic("checked_shr #681") }
    if !(i8.MIN.wrapping_shl(1u32) == 0i8) { panic("wrapping_shl #682") }
    if !(i8.MIN.wrapping_shr(1u32) == (-64i8)) { panic("wrapping_shr #683") }
    if !(i8.MIN.overflowing_shl(1u32).0 == 0i8 && i8.MIN.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #684") }
    if !(i8.MIN.overflowing_shr(1u32).0 == (-64i8) && i8.MIN.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #685") }
    if !(i8.MIN.unbounded_shl(1u32) == 0i8) { panic("unbounded_shl #686") }
    if !(i8.MIN.unbounded_shr(1u32) == (-64i8)) { panic("unbounded_shr #687") }
    if !(i8.MIN.strict_shl(1u32) == 0i8) { panic("strict_shl #688") }
    if !(i8.MIN.strict_shr(1u32) == (-64i8)) { panic("strict_shr #689") }
    if !(unsafe { i8.MIN.unchecked_shl(1u32) } == 0i8) { panic("unchecked_shl #690") }
    if !(unsafe { i8.MIN.unchecked_shr(1u32) } == (-64i8)) { panic("unchecked_shr #691") }
    if !(i8.MIN.rotate_left(3u32) == 4i8) { panic("rotate_left #692") }
    if !(i8.MIN.rotate_right(3u32) == 16i8) { panic("rotate_right #693") }
    if !(i8.MIN.checked_shl(3u32) == present(0i8)) { panic("checked_shl #694") }
    if !(i8.MIN.checked_shr(3u32) == present((-16i8))) { panic("checked_shr #695") }
    if !(i8.MIN.wrapping_shl(3u32) == 0i8) { panic("wrapping_shl #696") }
    if !(i8.MIN.wrapping_shr(3u32) == (-16i8)) { panic("wrapping_shr #697") }
    if !(i8.MIN.overflowing_shl(3u32).0 == 0i8 && i8.MIN.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #698") }
    if !(i8.MIN.overflowing_shr(3u32).0 == (-16i8) && i8.MIN.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #699") }
    if !(i8.MIN.unbounded_shl(3u32) == 0i8) { panic("unbounded_shl #700") }
    if !(i8.MIN.unbounded_shr(3u32) == (-16i8)) { panic("unbounded_shr #701") }
    if !(i8.MIN.strict_shl(3u32) == 0i8) { panic("strict_shl #702") }
    if !(i8.MIN.strict_shr(3u32) == (-16i8)) { panic("strict_shr #703") }
    if !(unsafe { i8.MIN.unchecked_shl(3u32) } == 0i8) { panic("unchecked_shl #704") }
    if !(unsafe { i8.MIN.unchecked_shr(3u32) } == (-16i8)) { panic("unchecked_shr #705") }
    if !(i8.MIN.rotate_left(7u32) == 64i8) { panic("rotate_left #706") }
    if !(i8.MIN.rotate_right(7u32) == 1i8) { panic("rotate_right #707") }
    if !(i8.MIN.checked_shl(7u32) == present(0i8)) { panic("checked_shl #708") }
    if !(i8.MIN.checked_shr(7u32) == present((-1i8))) { panic("checked_shr #709") }
    if !(i8.MIN.wrapping_shl(7u32) == 0i8) { panic("wrapping_shl #710") }
    if !(i8.MIN.wrapping_shr(7u32) == (-1i8)) { panic("wrapping_shr #711") }
    if !(i8.MIN.overflowing_shl(7u32).0 == 0i8 && i8.MIN.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #712") }
    if !(i8.MIN.overflowing_shr(7u32).0 == (-1i8) && i8.MIN.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #713") }
    if !(i8.MIN.unbounded_shl(7u32) == 0i8) { panic("unbounded_shl #714") }
    if !(i8.MIN.unbounded_shr(7u32) == (-1i8)) { panic("unbounded_shr #715") }
    if !(i8.MIN.strict_shl(7u32) == 0i8) { panic("strict_shl #716") }
    if !(i8.MIN.strict_shr(7u32) == (-1i8)) { panic("strict_shr #717") }
    if !(unsafe { i8.MIN.unchecked_shl(7u32) } == 0i8) { panic("unchecked_shl #718") }
    if !(unsafe { i8.MIN.unchecked_shr(7u32) } == (-1i8)) { panic("unchecked_shr #719") }
    if !(i8.MIN.rotate_left(8u32) == i8.MIN) { panic("rotate_left #720") }
}

fn group6() {
    if !(i8.MIN.rotate_right(8u32) == i8.MIN) { panic("rotate_right #721") }
    if !(missing(i8.MIN.checked_shl(8u32))) { panic("checked_shl #722") }
    if !(missing(i8.MIN.checked_shr(8u32))) { panic("checked_shr #723") }
    if !(i8.MIN.wrapping_shl(8u32) == i8.MIN) { panic("wrapping_shl #724") }
    if !(i8.MIN.wrapping_shr(8u32) == i8.MIN) { panic("wrapping_shr #725") }
    if !(i8.MIN.overflowing_shl(8u32).0 == i8.MIN && i8.MIN.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #726") }
    if !(i8.MIN.overflowing_shr(8u32).0 == i8.MIN && i8.MIN.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #727") }
    if !(i8.MIN.unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #728") }
    if !(i8.MIN.unbounded_shr(8u32) == (-1i8)) { panic("unbounded_shr #729") }
    if !(i8.MIN.rotate_left(13u32) == 16i8) { panic("rotate_left #730") }
    if !(i8.MIN.rotate_right(13u32) == 4i8) { panic("rotate_right #731") }
    if !(missing(i8.MIN.checked_shl(13u32))) { panic("checked_shl #732") }
    if !(missing(i8.MIN.checked_shr(13u32))) { panic("checked_shr #733") }
    if !(i8.MIN.wrapping_shl(13u32) == 0i8) { panic("wrapping_shl #734") }
    if !(i8.MIN.wrapping_shr(13u32) == (-4i8)) { panic("wrapping_shr #735") }
    if !(i8.MIN.overflowing_shl(13u32).0 == 0i8 && i8.MIN.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #736") }
    if !(i8.MIN.overflowing_shr(13u32).0 == (-4i8) && i8.MIN.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #737") }
    if !(i8.MIN.unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #738") }
    if !(i8.MIN.unbounded_shr(13u32) == (-1i8)) { panic("unbounded_shr #739") }
    if !(i8.MIN.checked_pow(0u32) == present(1i8)) { panic("checked_pow #740") }
    if !(i8.MIN.wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #741") }
    if !(i8.MIN.overflowing_pow(0u32).0 == 1i8 && i8.MIN.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #742") }
    if !(i8.MIN.saturating_pow(0u32) == 1i8) { panic("saturating_pow #743") }
    if !(i8.MIN.pow(0u32) == 1i8) { panic("pow #744") }
    if !(i8.MIN.strict_pow(0u32) == 1i8) { panic("strict_pow #745") }
    if !(i8.MIN.checked_pow(1u32) == present(i8.MIN)) { panic("checked_pow #746") }
    if !(i8.MIN.wrapping_pow(1u32) == i8.MIN) { panic("wrapping_pow #747") }
    if !(i8.MIN.overflowing_pow(1u32).0 == i8.MIN && i8.MIN.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #748") }
    if !(i8.MIN.saturating_pow(1u32) == i8.MIN) { panic("saturating_pow #749") }
    if !(i8.MIN.pow(1u32) == i8.MIN) { panic("pow #750") }
    if !(i8.MIN.strict_pow(1u32) == i8.MIN) { panic("strict_pow #751") }
    if !(missing(i8.MIN.checked_pow(2u32))) { panic("checked_pow #752") }
    if !(i8.MIN.wrapping_pow(2u32) == 0i8) { panic("wrapping_pow #753") }
    if !(i8.MIN.overflowing_pow(2u32).0 == 0i8 && i8.MIN.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #754") }
    if !(i8.MIN.saturating_pow(2u32) == i8.MAX) { panic("saturating_pow #755") }
    if !(missing(i8.MIN.checked_pow(3u32))) { panic("checked_pow #756") }
    if !(i8.MIN.wrapping_pow(3u32) == 0i8) { panic("wrapping_pow #757") }
    if !(i8.MIN.overflowing_pow(3u32).0 == 0i8 && i8.MIN.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #758") }
    if !(i8.MIN.saturating_pow(3u32) == i8.MIN) { panic("saturating_pow #759") }
    if !(missing(i8.MIN.checked_pow(7u32))) { panic("checked_pow #760") }
    if !(i8.MIN.wrapping_pow(7u32) == 0i8) { panic("wrapping_pow #761") }
    if !(i8.MIN.overflowing_pow(7u32).0 == 0i8 && i8.MIN.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #762") }
    if !(i8.MIN.saturating_pow(7u32) == i8.MIN) { panic("saturating_pow #763") }
    if !(missing(i8.MIN.checked_pow(8u32))) { panic("checked_pow #764") }
    if !(i8.MIN.wrapping_pow(8u32) == 0i8) { panic("wrapping_pow #765") }
    if !(i8.MIN.overflowing_pow(8u32).0 == 0i8 && i8.MIN.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #766") }
    if !(i8.MIN.saturating_pow(8u32) == i8.MAX) { panic("saturating_pow #767") }
    if !(missing(i8.MIN.checked_ilog2())) { panic("checked_ilog2 #768") }
    if !(missing(i8.MIN.checked_ilog10())) { panic("checked_ilog10 #769") }
    if !(missing(i8.MIN.checked_ilog(2i8))) { panic("checked_ilog #770") }
    if !(missing(i8.MIN.checked_isqrt())) { panic("checked_isqrt #771") }
    if !(i8.MIN.highest_one() == present(7u32)) { panic("highest_one #772") }
    if !(i8.MIN.lowest_one() == present(7u32)) { panic("lowest_one #773") }
    if !(i8.MIN.isolate_highest_one() == i8.MIN) { panic("isolate_highest_one #774") }
    if !(i8.MIN.isolate_lowest_one() == i8.MIN) { panic("isolate_lowest_one #775") }
    if !(3i8.checked_neg() == present((-3i8))) { panic("checked_neg #776") }
    if !(3i8.wrapping_neg() == (-3i8)) { panic("wrapping_neg #777") }
    if !(3i8.overflowing_neg().0 == (-3i8) && 3i8.overflowing_neg().1 == false) { panic("overflowing_neg #778") }
    if !(3i8.strict_neg() == (-3i8)) { panic("strict_neg #779") }
    if !(unsafe { 3i8.unchecked_neg() } == (-3i8)) { panic("unchecked_neg #780") }
    if !(3i8.saturating_neg() == (-3i8)) { panic("saturating_neg #781") }
    if !(3i8.checked_abs() == present(3i8)) { panic("checked_abs #782") }
    if !(3i8.wrapping_abs() == 3i8) { panic("wrapping_abs #783") }
    if !(3i8.overflowing_abs().0 == 3i8 && 3i8.overflowing_abs().1 == false) { panic("overflowing_abs #784") }
    if !(3i8.saturating_abs() == 3i8) { panic("saturating_abs #785") }
    if !(3i8.strict_abs() == 3i8) { panic("strict_abs #786") }
    if !(3i8.abs() == 3i8) { panic("abs #787") }
    if !(3i8.unsigned_abs() == 3u8) { panic("unsigned_abs #788") }
    if !(3i8.signum() == 1i8) { panic("signum #789") }
    if !(3i8.is_positive() == true) { panic("is_positive #790") }
    if !(3i8.is_negative() == false) { panic("is_negative #791") }
    if !(3i8.cast_unsigned() == 3u8) { panic("cast_unsigned #792") }
    if !(3i8.count_ones() == 2u32) { panic("count_ones #793") }
    if !(3i8.count_zeros() == 6u32) { panic("count_zeros #794") }
    if !(3i8.leading_zeros() == 6u32) { panic("leading_zeros #795") }
    if !(3i8.trailing_zeros() == 0u32) { panic("trailing_zeros #796") }
    if !(3i8.leading_ones() == 0u32) { panic("leading_ones #797") }
    if !(3i8.trailing_ones() == 2u32) { panic("trailing_ones #798") }
    if !(3i8.reverse_bits() == (-64i8)) { panic("reverse_bits #799") }
    if !(3i8.swap_bytes() == 3i8) { panic("swap_bytes #800") }
    if !(3i8.to_be() == 3i8) { panic("to_be #801") }
    if !(3i8.to_le() == 3i8) { panic("to_le #802") }
    if !(i8.from_be(3i8) == 3i8) { panic("from_be #803") }
    if !(i8.from_le(3i8) == 3i8) { panic("from_le #804") }
    if !(3i8.to_le_bytes() == [3u8]) { panic("to_le_bytes #805") }
    if !(3i8.to_be_bytes() == [3u8]) { panic("to_be_bytes #806") }
    if !(3i8.to_ne_bytes() == [3u8]) { panic("to_ne_bytes #807") }
    if !(i8.from_le_bytes([3u8]) == 3i8) { panic("from_le_bytes #808") }
    if !(i8.from_be_bytes([3u8]) == 3i8) { panic("from_be_bytes #809") }
    if !(i8.from_ne_bytes([3u8]) == 3i8) { panic("from_ne_bytes #810") }
    if !(3i8.rotate_left(0u32) == 3i8) { panic("rotate_left #811") }
    if !(3i8.rotate_right(0u32) == 3i8) { panic("rotate_right #812") }
    if !(3i8.checked_shl(0u32) == present(3i8)) { panic("checked_shl #813") }
    if !(3i8.checked_shr(0u32) == present(3i8)) { panic("checked_shr #814") }
    if !(3i8.wrapping_shl(0u32) == 3i8) { panic("wrapping_shl #815") }
    if !(3i8.wrapping_shr(0u32) == 3i8) { panic("wrapping_shr #816") }
    if !(3i8.overflowing_shl(0u32).0 == 3i8 && 3i8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #817") }
    if !(3i8.overflowing_shr(0u32).0 == 3i8 && 3i8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #818") }
    if !(3i8.unbounded_shl(0u32) == 3i8) { panic("unbounded_shl #819") }
    if !(3i8.unbounded_shr(0u32) == 3i8) { panic("unbounded_shr #820") }
    if !(3i8.strict_shl(0u32) == 3i8) { panic("strict_shl #821") }
    if !(3i8.strict_shr(0u32) == 3i8) { panic("strict_shr #822") }
    if !(unsafe { 3i8.unchecked_shl(0u32) } == 3i8) { panic("unchecked_shl #823") }
    if !(unsafe { 3i8.unchecked_shr(0u32) } == 3i8) { panic("unchecked_shr #824") }
    if !(3i8.rotate_left(1u32) == 6i8) { panic("rotate_left #825") }
    if !(3i8.rotate_right(1u32) == (-127i8)) { panic("rotate_right #826") }
    if !(3i8.checked_shl(1u32) == present(6i8)) { panic("checked_shl #827") }
    if !(3i8.checked_shr(1u32) == present(1i8)) { panic("checked_shr #828") }
    if !(3i8.wrapping_shl(1u32) == 6i8) { panic("wrapping_shl #829") }
    if !(3i8.wrapping_shr(1u32) == 1i8) { panic("wrapping_shr #830") }
    if !(3i8.overflowing_shl(1u32).0 == 6i8 && 3i8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #831") }
    if !(3i8.overflowing_shr(1u32).0 == 1i8 && 3i8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #832") }
    if !(3i8.unbounded_shl(1u32) == 6i8) { panic("unbounded_shl #833") }
    if !(3i8.unbounded_shr(1u32) == 1i8) { panic("unbounded_shr #834") }
    if !(3i8.strict_shl(1u32) == 6i8) { panic("strict_shl #835") }
    if !(3i8.strict_shr(1u32) == 1i8) { panic("strict_shr #836") }
    if !(unsafe { 3i8.unchecked_shl(1u32) } == 6i8) { panic("unchecked_shl #837") }
    if !(unsafe { 3i8.unchecked_shr(1u32) } == 1i8) { panic("unchecked_shr #838") }
    if !(3i8.rotate_left(3u32) == 24i8) { panic("rotate_left #839") }
    if !(3i8.rotate_right(3u32) == 96i8) { panic("rotate_right #840") }
}

fn group7() {
    if !(3i8.checked_shl(3u32) == present(24i8)) { panic("checked_shl #841") }
    if !(3i8.checked_shr(3u32) == present(0i8)) { panic("checked_shr #842") }
    if !(3i8.wrapping_shl(3u32) == 24i8) { panic("wrapping_shl #843") }
    if !(3i8.wrapping_shr(3u32) == 0i8) { panic("wrapping_shr #844") }
    if !(3i8.overflowing_shl(3u32).0 == 24i8 && 3i8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #845") }
    if !(3i8.overflowing_shr(3u32).0 == 0i8 && 3i8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #846") }
    if !(3i8.unbounded_shl(3u32) == 24i8) { panic("unbounded_shl #847") }
    if !(3i8.unbounded_shr(3u32) == 0i8) { panic("unbounded_shr #848") }
    if !(3i8.strict_shl(3u32) == 24i8) { panic("strict_shl #849") }
    if !(3i8.strict_shr(3u32) == 0i8) { panic("strict_shr #850") }
    if !(unsafe { 3i8.unchecked_shl(3u32) } == 24i8) { panic("unchecked_shl #851") }
    if !(unsafe { 3i8.unchecked_shr(3u32) } == 0i8) { panic("unchecked_shr #852") }
    if !(3i8.rotate_left(7u32) == (-127i8)) { panic("rotate_left #853") }
    if !(3i8.rotate_right(7u32) == 6i8) { panic("rotate_right #854") }
    if !(3i8.checked_shl(7u32) == present(i8.MIN)) { panic("checked_shl #855") }
    if !(3i8.checked_shr(7u32) == present(0i8)) { panic("checked_shr #856") }
    if !(3i8.wrapping_shl(7u32) == i8.MIN) { panic("wrapping_shl #857") }
    if !(3i8.wrapping_shr(7u32) == 0i8) { panic("wrapping_shr #858") }
    if !(3i8.overflowing_shl(7u32).0 == i8.MIN && 3i8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #859") }
    if !(3i8.overflowing_shr(7u32).0 == 0i8 && 3i8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #860") }
    if !(3i8.unbounded_shl(7u32) == i8.MIN) { panic("unbounded_shl #861") }
    if !(3i8.unbounded_shr(7u32) == 0i8) { panic("unbounded_shr #862") }
    if !(3i8.strict_shl(7u32) == i8.MIN) { panic("strict_shl #863") }
    if !(3i8.strict_shr(7u32) == 0i8) { panic("strict_shr #864") }
    if !(unsafe { 3i8.unchecked_shl(7u32) } == i8.MIN) { panic("unchecked_shl #865") }
    if !(unsafe { 3i8.unchecked_shr(7u32) } == 0i8) { panic("unchecked_shr #866") }
    if !(3i8.rotate_left(8u32) == 3i8) { panic("rotate_left #867") }
    if !(3i8.rotate_right(8u32) == 3i8) { panic("rotate_right #868") }
    if !(missing(3i8.checked_shl(8u32))) { panic("checked_shl #869") }
    if !(missing(3i8.checked_shr(8u32))) { panic("checked_shr #870") }
    if !(3i8.wrapping_shl(8u32) == 3i8) { panic("wrapping_shl #871") }
    if !(3i8.wrapping_shr(8u32) == 3i8) { panic("wrapping_shr #872") }
    if !(3i8.overflowing_shl(8u32).0 == 3i8 && 3i8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #873") }
    if !(3i8.overflowing_shr(8u32).0 == 3i8 && 3i8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #874") }
    if !(3i8.unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #875") }
    if !(3i8.unbounded_shr(8u32) == 0i8) { panic("unbounded_shr #876") }
    if !(3i8.rotate_left(13u32) == 96i8) { panic("rotate_left #877") }
    if !(3i8.rotate_right(13u32) == 24i8) { panic("rotate_right #878") }
    if !(missing(3i8.checked_shl(13u32))) { panic("checked_shl #879") }
    if !(missing(3i8.checked_shr(13u32))) { panic("checked_shr #880") }
    if !(3i8.wrapping_shl(13u32) == 96i8) { panic("wrapping_shl #881") }
    if !(3i8.wrapping_shr(13u32) == 0i8) { panic("wrapping_shr #882") }
    if !(3i8.overflowing_shl(13u32).0 == 96i8 && 3i8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #883") }
    if !(3i8.overflowing_shr(13u32).0 == 0i8 && 3i8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #884") }
    if !(3i8.unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #885") }
    if !(3i8.unbounded_shr(13u32) == 0i8) { panic("unbounded_shr #886") }
    if !(3i8.checked_pow(0u32) == present(1i8)) { panic("checked_pow #887") }
    if !(3i8.wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #888") }
    if !(3i8.overflowing_pow(0u32).0 == 1i8 && 3i8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #889") }
    if !(3i8.saturating_pow(0u32) == 1i8) { panic("saturating_pow #890") }
    if !(3i8.pow(0u32) == 1i8) { panic("pow #891") }
    if !(3i8.strict_pow(0u32) == 1i8) { panic("strict_pow #892") }
    if !(3i8.checked_pow(1u32) == present(3i8)) { panic("checked_pow #893") }
    if !(3i8.wrapping_pow(1u32) == 3i8) { panic("wrapping_pow #894") }
    if !(3i8.overflowing_pow(1u32).0 == 3i8 && 3i8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #895") }
    if !(3i8.saturating_pow(1u32) == 3i8) { panic("saturating_pow #896") }
    if !(3i8.pow(1u32) == 3i8) { panic("pow #897") }
    if !(3i8.strict_pow(1u32) == 3i8) { panic("strict_pow #898") }
    if !(3i8.checked_pow(2u32) == present(9i8)) { panic("checked_pow #899") }
    if !(3i8.wrapping_pow(2u32) == 9i8) { panic("wrapping_pow #900") }
    if !(3i8.overflowing_pow(2u32).0 == 9i8 && 3i8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #901") }
    if !(3i8.saturating_pow(2u32) == 9i8) { panic("saturating_pow #902") }
    if !(3i8.pow(2u32) == 9i8) { panic("pow #903") }
    if !(3i8.strict_pow(2u32) == 9i8) { panic("strict_pow #904") }
    if !(3i8.checked_pow(3u32) == present(27i8)) { panic("checked_pow #905") }
    if !(3i8.wrapping_pow(3u32) == 27i8) { panic("wrapping_pow #906") }
    if !(3i8.overflowing_pow(3u32).0 == 27i8 && 3i8.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #907") }
    if !(3i8.saturating_pow(3u32) == 27i8) { panic("saturating_pow #908") }
    if !(3i8.pow(3u32) == 27i8) { panic("pow #909") }
    if !(3i8.strict_pow(3u32) == 27i8) { panic("strict_pow #910") }
    if !(missing(3i8.checked_pow(7u32))) { panic("checked_pow #911") }
    if !(3i8.wrapping_pow(7u32) == (-117i8)) { panic("wrapping_pow #912") }
    if !(3i8.overflowing_pow(7u32).0 == (-117i8) && 3i8.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #913") }
    if !(3i8.saturating_pow(7u32) == i8.MAX) { panic("saturating_pow #914") }
    if !(missing(3i8.checked_pow(8u32))) { panic("checked_pow #915") }
    if !(3i8.wrapping_pow(8u32) == (-95i8)) { panic("wrapping_pow #916") }
    if !(3i8.overflowing_pow(8u32).0 == (-95i8) && 3i8.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #917") }
    if !(3i8.saturating_pow(8u32) == i8.MAX) { panic("saturating_pow #918") }
    if !(3i8.ilog2() == 1u32) { panic("ilog2 #919") }
    if !(3i8.ilog10() == 0u32) { panic("ilog10 #920") }
    if !(3i8.checked_ilog2() == present(1u32)) { panic("checked_ilog2 #921") }
    if !(3i8.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #922") }
    if !(3i8.ilog(2i8) == 1u32) { panic("ilog #923") }
    if !(3i8.checked_ilog(2i8) == present(1u32)) { panic("checked_ilog #924") }
    if !(3i8.ilog(3i8) == 1u32) { panic("ilog #925") }
    if !(3i8.checked_ilog(3i8) == present(1u32)) { panic("checked_ilog #926") }
    if !(3i8.ilog(7i8) == 0u32) { panic("ilog #927") }
    if !(3i8.checked_ilog(7i8) == present(0u32)) { panic("checked_ilog #928") }
    if !(missing(3i8.checked_ilog(1i8))) { panic("checked_ilog #929") }
    if !(3i8.isqrt() == 1i8) { panic("isqrt #930") }
    if !(3i8.checked_isqrt() == present(1i8)) { panic("checked_isqrt #931") }
    if !(3i8.highest_one() == present(1u32)) { panic("highest_one #932") }
    if !(3i8.lowest_one() == present(0u32)) { panic("lowest_one #933") }
    if !(3i8.isolate_highest_one() == 2i8) { panic("isolate_highest_one #934") }
    if !(3i8.isolate_lowest_one() == 1i8) { panic("isolate_lowest_one #935") }
    if !(7i8.checked_neg() == present((-7i8))) { panic("checked_neg #936") }
    if !(7i8.wrapping_neg() == (-7i8)) { panic("wrapping_neg #937") }
    if !(7i8.overflowing_neg().0 == (-7i8) && 7i8.overflowing_neg().1 == false) { panic("overflowing_neg #938") }
    if !(7i8.strict_neg() == (-7i8)) { panic("strict_neg #939") }
    if !(unsafe { 7i8.unchecked_neg() } == (-7i8)) { panic("unchecked_neg #940") }
    if !(7i8.saturating_neg() == (-7i8)) { panic("saturating_neg #941") }
    if !(7i8.checked_abs() == present(7i8)) { panic("checked_abs #942") }
    if !(7i8.wrapping_abs() == 7i8) { panic("wrapping_abs #943") }
    if !(7i8.overflowing_abs().0 == 7i8 && 7i8.overflowing_abs().1 == false) { panic("overflowing_abs #944") }
    if !(7i8.saturating_abs() == 7i8) { panic("saturating_abs #945") }
    if !(7i8.strict_abs() == 7i8) { panic("strict_abs #946") }
    if !(7i8.abs() == 7i8) { panic("abs #947") }
    if !(7i8.unsigned_abs() == 7u8) { panic("unsigned_abs #948") }
    if !(7i8.signum() == 1i8) { panic("signum #949") }
    if !(7i8.is_positive() == true) { panic("is_positive #950") }
    if !(7i8.is_negative() == false) { panic("is_negative #951") }
    if !(7i8.cast_unsigned() == 7u8) { panic("cast_unsigned #952") }
    if !(7i8.count_ones() == 3u32) { panic("count_ones #953") }
    if !(7i8.count_zeros() == 5u32) { panic("count_zeros #954") }
    if !(7i8.leading_zeros() == 5u32) { panic("leading_zeros #955") }
    if !(7i8.trailing_zeros() == 0u32) { panic("trailing_zeros #956") }
    if !(7i8.leading_ones() == 0u32) { panic("leading_ones #957") }
    if !(7i8.trailing_ones() == 3u32) { panic("trailing_ones #958") }
    if !(7i8.reverse_bits() == (-32i8)) { panic("reverse_bits #959") }
    if !(7i8.swap_bytes() == 7i8) { panic("swap_bytes #960") }
}

fn group8() {
    if !(7i8.to_be() == 7i8) { panic("to_be #961") }
    if !(7i8.to_le() == 7i8) { panic("to_le #962") }
    if !(i8.from_be(7i8) == 7i8) { panic("from_be #963") }
    if !(i8.from_le(7i8) == 7i8) { panic("from_le #964") }
    if !(7i8.to_le_bytes() == [7u8]) { panic("to_le_bytes #965") }
    if !(7i8.to_be_bytes() == [7u8]) { panic("to_be_bytes #966") }
    if !(7i8.to_ne_bytes() == [7u8]) { panic("to_ne_bytes #967") }
    if !(i8.from_le_bytes([7u8]) == 7i8) { panic("from_le_bytes #968") }
    if !(i8.from_be_bytes([7u8]) == 7i8) { panic("from_be_bytes #969") }
    if !(i8.from_ne_bytes([7u8]) == 7i8) { panic("from_ne_bytes #970") }
    if !(7i8.rotate_left(0u32) == 7i8) { panic("rotate_left #971") }
    if !(7i8.rotate_right(0u32) == 7i8) { panic("rotate_right #972") }
    if !(7i8.checked_shl(0u32) == present(7i8)) { panic("checked_shl #973") }
    if !(7i8.checked_shr(0u32) == present(7i8)) { panic("checked_shr #974") }
    if !(7i8.wrapping_shl(0u32) == 7i8) { panic("wrapping_shl #975") }
    if !(7i8.wrapping_shr(0u32) == 7i8) { panic("wrapping_shr #976") }
    if !(7i8.overflowing_shl(0u32).0 == 7i8 && 7i8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #977") }
    if !(7i8.overflowing_shr(0u32).0 == 7i8 && 7i8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #978") }
    if !(7i8.unbounded_shl(0u32) == 7i8) { panic("unbounded_shl #979") }
    if !(7i8.unbounded_shr(0u32) == 7i8) { panic("unbounded_shr #980") }
    if !(7i8.strict_shl(0u32) == 7i8) { panic("strict_shl #981") }
    if !(7i8.strict_shr(0u32) == 7i8) { panic("strict_shr #982") }
    if !(unsafe { 7i8.unchecked_shl(0u32) } == 7i8) { panic("unchecked_shl #983") }
    if !(unsafe { 7i8.unchecked_shr(0u32) } == 7i8) { panic("unchecked_shr #984") }
    if !(7i8.rotate_left(1u32) == 14i8) { panic("rotate_left #985") }
    if !(7i8.rotate_right(1u32) == (-125i8)) { panic("rotate_right #986") }
    if !(7i8.checked_shl(1u32) == present(14i8)) { panic("checked_shl #987") }
    if !(7i8.checked_shr(1u32) == present(3i8)) { panic("checked_shr #988") }
    if !(7i8.wrapping_shl(1u32) == 14i8) { panic("wrapping_shl #989") }
    if !(7i8.wrapping_shr(1u32) == 3i8) { panic("wrapping_shr #990") }
    if !(7i8.overflowing_shl(1u32).0 == 14i8 && 7i8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #991") }
    if !(7i8.overflowing_shr(1u32).0 == 3i8 && 7i8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #992") }
    if !(7i8.unbounded_shl(1u32) == 14i8) { panic("unbounded_shl #993") }
    if !(7i8.unbounded_shr(1u32) == 3i8) { panic("unbounded_shr #994") }
    if !(7i8.strict_shl(1u32) == 14i8) { panic("strict_shl #995") }
    if !(7i8.strict_shr(1u32) == 3i8) { panic("strict_shr #996") }
    if !(unsafe { 7i8.unchecked_shl(1u32) } == 14i8) { panic("unchecked_shl #997") }
    if !(unsafe { 7i8.unchecked_shr(1u32) } == 3i8) { panic("unchecked_shr #998") }
    if !(7i8.rotate_left(3u32) == 56i8) { panic("rotate_left #999") }
    if !(7i8.rotate_right(3u32) == (-32i8)) { panic("rotate_right #1000") }
    if !(7i8.checked_shl(3u32) == present(56i8)) { panic("checked_shl #1001") }
    if !(7i8.checked_shr(3u32) == present(0i8)) { panic("checked_shr #1002") }
    if !(7i8.wrapping_shl(3u32) == 56i8) { panic("wrapping_shl #1003") }
    if !(7i8.wrapping_shr(3u32) == 0i8) { panic("wrapping_shr #1004") }
    if !(7i8.overflowing_shl(3u32).0 == 56i8 && 7i8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1005") }
    if !(7i8.overflowing_shr(3u32).0 == 0i8 && 7i8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1006") }
    if !(7i8.unbounded_shl(3u32) == 56i8) { panic("unbounded_shl #1007") }
    if !(7i8.unbounded_shr(3u32) == 0i8) { panic("unbounded_shr #1008") }
    if !(7i8.strict_shl(3u32) == 56i8) { panic("strict_shl #1009") }
    if !(7i8.strict_shr(3u32) == 0i8) { panic("strict_shr #1010") }
    if !(unsafe { 7i8.unchecked_shl(3u32) } == 56i8) { panic("unchecked_shl #1011") }
    if !(unsafe { 7i8.unchecked_shr(3u32) } == 0i8) { panic("unchecked_shr #1012") }
    if !(7i8.rotate_left(7u32) == (-125i8)) { panic("rotate_left #1013") }
    if !(7i8.rotate_right(7u32) == 14i8) { panic("rotate_right #1014") }
    if !(7i8.checked_shl(7u32) == present(i8.MIN)) { panic("checked_shl #1015") }
    if !(7i8.checked_shr(7u32) == present(0i8)) { panic("checked_shr #1016") }
    if !(7i8.wrapping_shl(7u32) == i8.MIN) { panic("wrapping_shl #1017") }
    if !(7i8.wrapping_shr(7u32) == 0i8) { panic("wrapping_shr #1018") }
    if !(7i8.overflowing_shl(7u32).0 == i8.MIN && 7i8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #1019") }
    if !(7i8.overflowing_shr(7u32).0 == 0i8 && 7i8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #1020") }
    if !(7i8.unbounded_shl(7u32) == i8.MIN) { panic("unbounded_shl #1021") }
    if !(7i8.unbounded_shr(7u32) == 0i8) { panic("unbounded_shr #1022") }
    if !(7i8.strict_shl(7u32) == i8.MIN) { panic("strict_shl #1023") }
    if !(7i8.strict_shr(7u32) == 0i8) { panic("strict_shr #1024") }
    if !(unsafe { 7i8.unchecked_shl(7u32) } == i8.MIN) { panic("unchecked_shl #1025") }
    if !(unsafe { 7i8.unchecked_shr(7u32) } == 0i8) { panic("unchecked_shr #1026") }
    if !(7i8.rotate_left(8u32) == 7i8) { panic("rotate_left #1027") }
    if !(7i8.rotate_right(8u32) == 7i8) { panic("rotate_right #1028") }
    if !(missing(7i8.checked_shl(8u32))) { panic("checked_shl #1029") }
    if !(missing(7i8.checked_shr(8u32))) { panic("checked_shr #1030") }
    if !(7i8.wrapping_shl(8u32) == 7i8) { panic("wrapping_shl #1031") }
    if !(7i8.wrapping_shr(8u32) == 7i8) { panic("wrapping_shr #1032") }
    if !(7i8.overflowing_shl(8u32).0 == 7i8 && 7i8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #1033") }
    if !(7i8.overflowing_shr(8u32).0 == 7i8 && 7i8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #1034") }
    if !(7i8.unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #1035") }
    if !(7i8.unbounded_shr(8u32) == 0i8) { panic("unbounded_shr #1036") }
    if !(7i8.rotate_left(13u32) == (-32i8)) { panic("rotate_left #1037") }
    if !(7i8.rotate_right(13u32) == 56i8) { panic("rotate_right #1038") }
    if !(missing(7i8.checked_shl(13u32))) { panic("checked_shl #1039") }
    if !(missing(7i8.checked_shr(13u32))) { panic("checked_shr #1040") }
    if !(7i8.wrapping_shl(13u32) == (-32i8)) { panic("wrapping_shl #1041") }
    if !(7i8.wrapping_shr(13u32) == 0i8) { panic("wrapping_shr #1042") }
    if !(7i8.overflowing_shl(13u32).0 == (-32i8) && 7i8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #1043") }
    if !(7i8.overflowing_shr(13u32).0 == 0i8 && 7i8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #1044") }
    if !(7i8.unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #1045") }
    if !(7i8.unbounded_shr(13u32) == 0i8) { panic("unbounded_shr #1046") }
    if !(7i8.checked_pow(0u32) == present(1i8)) { panic("checked_pow #1047") }
    if !(7i8.wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #1048") }
    if !(7i8.overflowing_pow(0u32).0 == 1i8 && 7i8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1049") }
    if !(7i8.saturating_pow(0u32) == 1i8) { panic("saturating_pow #1050") }
    if !(7i8.pow(0u32) == 1i8) { panic("pow #1051") }
    if !(7i8.strict_pow(0u32) == 1i8) { panic("strict_pow #1052") }
    if !(7i8.checked_pow(1u32) == present(7i8)) { panic("checked_pow #1053") }
    if !(7i8.wrapping_pow(1u32) == 7i8) { panic("wrapping_pow #1054") }
    if !(7i8.overflowing_pow(1u32).0 == 7i8 && 7i8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1055") }
    if !(7i8.saturating_pow(1u32) == 7i8) { panic("saturating_pow #1056") }
    if !(7i8.pow(1u32) == 7i8) { panic("pow #1057") }
    if !(7i8.strict_pow(1u32) == 7i8) { panic("strict_pow #1058") }
    if !(7i8.checked_pow(2u32) == present(49i8)) { panic("checked_pow #1059") }
    if !(7i8.wrapping_pow(2u32) == 49i8) { panic("wrapping_pow #1060") }
    if !(7i8.overflowing_pow(2u32).0 == 49i8 && 7i8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1061") }
    if !(7i8.saturating_pow(2u32) == 49i8) { panic("saturating_pow #1062") }
    if !(7i8.pow(2u32) == 49i8) { panic("pow #1063") }
    if !(7i8.strict_pow(2u32) == 49i8) { panic("strict_pow #1064") }
    if !(missing(7i8.checked_pow(3u32))) { panic("checked_pow #1065") }
    if !(7i8.wrapping_pow(3u32) == 87i8) { panic("wrapping_pow #1066") }
    if !(7i8.overflowing_pow(3u32).0 == 87i8 && 7i8.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #1067") }
    if !(7i8.saturating_pow(3u32) == i8.MAX) { panic("saturating_pow #1068") }
    if !(missing(7i8.checked_pow(7u32))) { panic("checked_pow #1069") }
    if !(7i8.wrapping_pow(7u32) == (-9i8)) { panic("wrapping_pow #1070") }
    if !(7i8.overflowing_pow(7u32).0 == (-9i8) && 7i8.overflowing_pow(7u32).1 == true) { panic("overflowing_pow #1071") }
    if !(7i8.saturating_pow(7u32) == i8.MAX) { panic("saturating_pow #1072") }
    if !(missing(7i8.checked_pow(8u32))) { panic("checked_pow #1073") }
    if !(7i8.wrapping_pow(8u32) == (-63i8)) { panic("wrapping_pow #1074") }
    if !(7i8.overflowing_pow(8u32).0 == (-63i8) && 7i8.overflowing_pow(8u32).1 == true) { panic("overflowing_pow #1075") }
    if !(7i8.saturating_pow(8u32) == i8.MAX) { panic("saturating_pow #1076") }
    if !(7i8.ilog2() == 2u32) { panic("ilog2 #1077") }
    if !(7i8.ilog10() == 0u32) { panic("ilog10 #1078") }
    if !(7i8.checked_ilog2() == present(2u32)) { panic("checked_ilog2 #1079") }
    if !(7i8.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1080") }
}

fn group9() {
    if !(7i8.ilog(2i8) == 2u32) { panic("ilog #1081") }
    if !(7i8.checked_ilog(2i8) == present(2u32)) { panic("checked_ilog #1082") }
    if !(7i8.ilog(3i8) == 1u32) { panic("ilog #1083") }
    if !(7i8.checked_ilog(3i8) == present(1u32)) { panic("checked_ilog #1084") }
    if !(7i8.ilog(7i8) == 1u32) { panic("ilog #1085") }
    if !(7i8.checked_ilog(7i8) == present(1u32)) { panic("checked_ilog #1086") }
    if !(missing(7i8.checked_ilog(1i8))) { panic("checked_ilog #1087") }
    if !(7i8.isqrt() == 2i8) { panic("isqrt #1088") }
    if !(7i8.checked_isqrt() == present(2i8)) { panic("checked_isqrt #1089") }
    if !(7i8.highest_one() == present(2u32)) { panic("highest_one #1090") }
    if !(7i8.lowest_one() == present(0u32)) { panic("lowest_one #1091") }
    if !(7i8.isolate_highest_one() == 4i8) { panic("isolate_highest_one #1092") }
    if !(7i8.isolate_lowest_one() == 1i8) { panic("isolate_lowest_one #1093") }
    if !(0i8.checked_neg() == present(0i8)) { panic("checked_neg #1094") }
    if !(0i8.wrapping_neg() == 0i8) { panic("wrapping_neg #1095") }
    if !(0i8.overflowing_neg().0 == 0i8 && 0i8.overflowing_neg().1 == false) { panic("overflowing_neg #1096") }
    if !(0i8.strict_neg() == 0i8) { panic("strict_neg #1097") }
    if !(unsafe { 0i8.unchecked_neg() } == 0i8) { panic("unchecked_neg #1098") }
    if !(0i8.saturating_neg() == 0i8) { panic("saturating_neg #1099") }
    if !(0i8.checked_abs() == present(0i8)) { panic("checked_abs #1100") }
    if !(0i8.wrapping_abs() == 0i8) { panic("wrapping_abs #1101") }
    if !(0i8.overflowing_abs().0 == 0i8 && 0i8.overflowing_abs().1 == false) { panic("overflowing_abs #1102") }
    if !(0i8.saturating_abs() == 0i8) { panic("saturating_abs #1103") }
    if !(0i8.strict_abs() == 0i8) { panic("strict_abs #1104") }
    if !(0i8.abs() == 0i8) { panic("abs #1105") }
    if !(0i8.unsigned_abs() == 0u8) { panic("unsigned_abs #1106") }
    if !(0i8.signum() == 0i8) { panic("signum #1107") }
    if !(0i8.is_positive() == false) { panic("is_positive #1108") }
    if !(0i8.is_negative() == false) { panic("is_negative #1109") }
    if !(0i8.cast_unsigned() == 0u8) { panic("cast_unsigned #1110") }
    if !(0i8.count_ones() == 0u32) { panic("count_ones #1111") }
    if !(0i8.count_zeros() == 8u32) { panic("count_zeros #1112") }
    if !(0i8.leading_zeros() == 8u32) { panic("leading_zeros #1113") }
    if !(0i8.trailing_zeros() == 8u32) { panic("trailing_zeros #1114") }
    if !(0i8.leading_ones() == 0u32) { panic("leading_ones #1115") }
    if !(0i8.trailing_ones() == 0u32) { panic("trailing_ones #1116") }
    if !(0i8.reverse_bits() == 0i8) { panic("reverse_bits #1117") }
    if !(0i8.swap_bytes() == 0i8) { panic("swap_bytes #1118") }
    if !(0i8.to_be() == 0i8) { panic("to_be #1119") }
    if !(0i8.to_le() == 0i8) { panic("to_le #1120") }
    if !(i8.from_be(0i8) == 0i8) { panic("from_be #1121") }
    if !(i8.from_le(0i8) == 0i8) { panic("from_le #1122") }
    if !(0i8.to_le_bytes() == [0u8]) { panic("to_le_bytes #1123") }
    if !(0i8.to_be_bytes() == [0u8]) { panic("to_be_bytes #1124") }
    if !(0i8.to_ne_bytes() == [0u8]) { panic("to_ne_bytes #1125") }
    if !(i8.from_le_bytes([0u8]) == 0i8) { panic("from_le_bytes #1126") }
    if !(i8.from_be_bytes([0u8]) == 0i8) { panic("from_be_bytes #1127") }
    if !(i8.from_ne_bytes([0u8]) == 0i8) { panic("from_ne_bytes #1128") }
    if !(0i8.rotate_left(0u32) == 0i8) { panic("rotate_left #1129") }
    if !(0i8.rotate_right(0u32) == 0i8) { panic("rotate_right #1130") }
    if !(0i8.checked_shl(0u32) == present(0i8)) { panic("checked_shl #1131") }
    if !(0i8.checked_shr(0u32) == present(0i8)) { panic("checked_shr #1132") }
    if !(0i8.wrapping_shl(0u32) == 0i8) { panic("wrapping_shl #1133") }
    if !(0i8.wrapping_shr(0u32) == 0i8) { panic("wrapping_shr #1134") }
    if !(0i8.overflowing_shl(0u32).0 == 0i8 && 0i8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1135") }
    if !(0i8.overflowing_shr(0u32).0 == 0i8 && 0i8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1136") }
    if !(0i8.unbounded_shl(0u32) == 0i8) { panic("unbounded_shl #1137") }
    if !(0i8.unbounded_shr(0u32) == 0i8) { panic("unbounded_shr #1138") }
    if !(0i8.strict_shl(0u32) == 0i8) { panic("strict_shl #1139") }
    if !(0i8.strict_shr(0u32) == 0i8) { panic("strict_shr #1140") }
    if !(unsafe { 0i8.unchecked_shl(0u32) } == 0i8) { panic("unchecked_shl #1141") }
    if !(unsafe { 0i8.unchecked_shr(0u32) } == 0i8) { panic("unchecked_shr #1142") }
    if !(0i8.rotate_left(1u32) == 0i8) { panic("rotate_left #1143") }
    if !(0i8.rotate_right(1u32) == 0i8) { panic("rotate_right #1144") }
    if !(0i8.checked_shl(1u32) == present(0i8)) { panic("checked_shl #1145") }
    if !(0i8.checked_shr(1u32) == present(0i8)) { panic("checked_shr #1146") }
    if !(0i8.wrapping_shl(1u32) == 0i8) { panic("wrapping_shl #1147") }
    if !(0i8.wrapping_shr(1u32) == 0i8) { panic("wrapping_shr #1148") }
    if !(0i8.overflowing_shl(1u32).0 == 0i8 && 0i8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1149") }
    if !(0i8.overflowing_shr(1u32).0 == 0i8 && 0i8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1150") }
    if !(0i8.unbounded_shl(1u32) == 0i8) { panic("unbounded_shl #1151") }
    if !(0i8.unbounded_shr(1u32) == 0i8) { panic("unbounded_shr #1152") }
    if !(0i8.strict_shl(1u32) == 0i8) { panic("strict_shl #1153") }
    if !(0i8.strict_shr(1u32) == 0i8) { panic("strict_shr #1154") }
    if !(unsafe { 0i8.unchecked_shl(1u32) } == 0i8) { panic("unchecked_shl #1155") }
    if !(unsafe { 0i8.unchecked_shr(1u32) } == 0i8) { panic("unchecked_shr #1156") }
    if !(0i8.rotate_left(3u32) == 0i8) { panic("rotate_left #1157") }
    if !(0i8.rotate_right(3u32) == 0i8) { panic("rotate_right #1158") }
    if !(0i8.checked_shl(3u32) == present(0i8)) { panic("checked_shl #1159") }
    if !(0i8.checked_shr(3u32) == present(0i8)) { panic("checked_shr #1160") }
    if !(0i8.wrapping_shl(3u32) == 0i8) { panic("wrapping_shl #1161") }
    if !(0i8.wrapping_shr(3u32) == 0i8) { panic("wrapping_shr #1162") }
    if !(0i8.overflowing_shl(3u32).0 == 0i8 && 0i8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1163") }
    if !(0i8.overflowing_shr(3u32).0 == 0i8 && 0i8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1164") }
    if !(0i8.unbounded_shl(3u32) == 0i8) { panic("unbounded_shl #1165") }
    if !(0i8.unbounded_shr(3u32) == 0i8) { panic("unbounded_shr #1166") }
    if !(0i8.strict_shl(3u32) == 0i8) { panic("strict_shl #1167") }
    if !(0i8.strict_shr(3u32) == 0i8) { panic("strict_shr #1168") }
    if !(unsafe { 0i8.unchecked_shl(3u32) } == 0i8) { panic("unchecked_shl #1169") }
    if !(unsafe { 0i8.unchecked_shr(3u32) } == 0i8) { panic("unchecked_shr #1170") }
    if !(0i8.rotate_left(7u32) == 0i8) { panic("rotate_left #1171") }
    if !(0i8.rotate_right(7u32) == 0i8) { panic("rotate_right #1172") }
    if !(0i8.checked_shl(7u32) == present(0i8)) { panic("checked_shl #1173") }
    if !(0i8.checked_shr(7u32) == present(0i8)) { panic("checked_shr #1174") }
    if !(0i8.wrapping_shl(7u32) == 0i8) { panic("wrapping_shl #1175") }
    if !(0i8.wrapping_shr(7u32) == 0i8) { panic("wrapping_shr #1176") }
    if !(0i8.overflowing_shl(7u32).0 == 0i8 && 0i8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #1177") }
    if !(0i8.overflowing_shr(7u32).0 == 0i8 && 0i8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #1178") }
    if !(0i8.unbounded_shl(7u32) == 0i8) { panic("unbounded_shl #1179") }
    if !(0i8.unbounded_shr(7u32) == 0i8) { panic("unbounded_shr #1180") }
    if !(0i8.strict_shl(7u32) == 0i8) { panic("strict_shl #1181") }
    if !(0i8.strict_shr(7u32) == 0i8) { panic("strict_shr #1182") }
    if !(unsafe { 0i8.unchecked_shl(7u32) } == 0i8) { panic("unchecked_shl #1183") }
    if !(unsafe { 0i8.unchecked_shr(7u32) } == 0i8) { panic("unchecked_shr #1184") }
    if !(0i8.rotate_left(8u32) == 0i8) { panic("rotate_left #1185") }
    if !(0i8.rotate_right(8u32) == 0i8) { panic("rotate_right #1186") }
    if !(missing(0i8.checked_shl(8u32))) { panic("checked_shl #1187") }
    if !(missing(0i8.checked_shr(8u32))) { panic("checked_shr #1188") }
    if !(0i8.wrapping_shl(8u32) == 0i8) { panic("wrapping_shl #1189") }
    if !(0i8.wrapping_shr(8u32) == 0i8) { panic("wrapping_shr #1190") }
    if !(0i8.overflowing_shl(8u32).0 == 0i8 && 0i8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #1191") }
    if !(0i8.overflowing_shr(8u32).0 == 0i8 && 0i8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #1192") }
    if !(0i8.unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #1193") }
    if !(0i8.unbounded_shr(8u32) == 0i8) { panic("unbounded_shr #1194") }
    if !(0i8.rotate_left(13u32) == 0i8) { panic("rotate_left #1195") }
    if !(0i8.rotate_right(13u32) == 0i8) { panic("rotate_right #1196") }
    if !(missing(0i8.checked_shl(13u32))) { panic("checked_shl #1197") }
    if !(missing(0i8.checked_shr(13u32))) { panic("checked_shr #1198") }
    if !(0i8.wrapping_shl(13u32) == 0i8) { panic("wrapping_shl #1199") }
    if !(0i8.wrapping_shr(13u32) == 0i8) { panic("wrapping_shr #1200") }
}

fn group10() {
    if !(0i8.overflowing_shl(13u32).0 == 0i8 && 0i8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #1201") }
    if !(0i8.overflowing_shr(13u32).0 == 0i8 && 0i8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #1202") }
    if !(0i8.unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #1203") }
    if !(0i8.unbounded_shr(13u32) == 0i8) { panic("unbounded_shr #1204") }
    if !(0i8.checked_pow(0u32) == present(1i8)) { panic("checked_pow #1205") }
    if !(0i8.wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #1206") }
    if !(0i8.overflowing_pow(0u32).0 == 1i8 && 0i8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1207") }
    if !(0i8.saturating_pow(0u32) == 1i8) { panic("saturating_pow #1208") }
    if !(0i8.pow(0u32) == 1i8) { panic("pow #1209") }
    if !(0i8.strict_pow(0u32) == 1i8) { panic("strict_pow #1210") }
    if !(0i8.checked_pow(1u32) == present(0i8)) { panic("checked_pow #1211") }
    if !(0i8.wrapping_pow(1u32) == 0i8) { panic("wrapping_pow #1212") }
    if !(0i8.overflowing_pow(1u32).0 == 0i8 && 0i8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1213") }
    if !(0i8.saturating_pow(1u32) == 0i8) { panic("saturating_pow #1214") }
    if !(0i8.pow(1u32) == 0i8) { panic("pow #1215") }
    if !(0i8.strict_pow(1u32) == 0i8) { panic("strict_pow #1216") }
    if !(0i8.checked_pow(2u32) == present(0i8)) { panic("checked_pow #1217") }
    if !(0i8.wrapping_pow(2u32) == 0i8) { panic("wrapping_pow #1218") }
    if !(0i8.overflowing_pow(2u32).0 == 0i8 && 0i8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1219") }
    if !(0i8.saturating_pow(2u32) == 0i8) { panic("saturating_pow #1220") }
    if !(0i8.pow(2u32) == 0i8) { panic("pow #1221") }
    if !(0i8.strict_pow(2u32) == 0i8) { panic("strict_pow #1222") }
    if !(0i8.checked_pow(3u32) == present(0i8)) { panic("checked_pow #1223") }
    if !(0i8.wrapping_pow(3u32) == 0i8) { panic("wrapping_pow #1224") }
    if !(0i8.overflowing_pow(3u32).0 == 0i8 && 0i8.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1225") }
    if !(0i8.saturating_pow(3u32) == 0i8) { panic("saturating_pow #1226") }
    if !(0i8.pow(3u32) == 0i8) { panic("pow #1227") }
    if !(0i8.strict_pow(3u32) == 0i8) { panic("strict_pow #1228") }
    if !(0i8.checked_pow(7u32) == present(0i8)) { panic("checked_pow #1229") }
    if !(0i8.wrapping_pow(7u32) == 0i8) { panic("wrapping_pow #1230") }
    if !(0i8.overflowing_pow(7u32).0 == 0i8 && 0i8.overflowing_pow(7u32).1 == false) { panic("overflowing_pow #1231") }
    if !(0i8.saturating_pow(7u32) == 0i8) { panic("saturating_pow #1232") }
    if !(0i8.pow(7u32) == 0i8) { panic("pow #1233") }
    if !(0i8.strict_pow(7u32) == 0i8) { panic("strict_pow #1234") }
    if !(0i8.checked_pow(8u32) == present(0i8)) { panic("checked_pow #1235") }
    if !(0i8.wrapping_pow(8u32) == 0i8) { panic("wrapping_pow #1236") }
    if !(0i8.overflowing_pow(8u32).0 == 0i8 && 0i8.overflowing_pow(8u32).1 == false) { panic("overflowing_pow #1237") }
    if !(0i8.saturating_pow(8u32) == 0i8) { panic("saturating_pow #1238") }
    if !(0i8.pow(8u32) == 0i8) { panic("pow #1239") }
    if !(0i8.strict_pow(8u32) == 0i8) { panic("strict_pow #1240") }
    if !(missing(0i8.checked_ilog2())) { panic("checked_ilog2 #1241") }
    if !(missing(0i8.checked_ilog10())) { panic("checked_ilog10 #1242") }
    if !(missing(0i8.checked_ilog(2i8))) { panic("checked_ilog #1243") }
    if !(0i8.isqrt() == 0i8) { panic("isqrt #1244") }
    if !(0i8.checked_isqrt() == present(0i8)) { panic("checked_isqrt #1245") }
    if !(missing(0i8.highest_one())) { panic("highest_one #1246") }
    if !(missing(0i8.lowest_one())) { panic("lowest_one #1247") }
    if !(0i8.isolate_highest_one() == 0i8) { panic("isolate_highest_one #1248") }
    if !(0i8.isolate_lowest_one() == 0i8) { panic("isolate_lowest_one #1249") }
    if !(1i8.checked_neg() == present((-1i8))) { panic("checked_neg #1250") }
    if !(1i8.wrapping_neg() == (-1i8)) { panic("wrapping_neg #1251") }
    if !(1i8.overflowing_neg().0 == (-1i8) && 1i8.overflowing_neg().1 == false) { panic("overflowing_neg #1252") }
    if !(1i8.strict_neg() == (-1i8)) { panic("strict_neg #1253") }
    if !(unsafe { 1i8.unchecked_neg() } == (-1i8)) { panic("unchecked_neg #1254") }
    if !(1i8.saturating_neg() == (-1i8)) { panic("saturating_neg #1255") }
    if !(1i8.checked_abs() == present(1i8)) { panic("checked_abs #1256") }
    if !(1i8.wrapping_abs() == 1i8) { panic("wrapping_abs #1257") }
    if !(1i8.overflowing_abs().0 == 1i8 && 1i8.overflowing_abs().1 == false) { panic("overflowing_abs #1258") }
    if !(1i8.saturating_abs() == 1i8) { panic("saturating_abs #1259") }
    if !(1i8.strict_abs() == 1i8) { panic("strict_abs #1260") }
    if !(1i8.abs() == 1i8) { panic("abs #1261") }
    if !(1i8.unsigned_abs() == 1u8) { panic("unsigned_abs #1262") }
    if !(1i8.signum() == 1i8) { panic("signum #1263") }
    if !(1i8.is_positive() == true) { panic("is_positive #1264") }
    if !(1i8.is_negative() == false) { panic("is_negative #1265") }
    if !(1i8.cast_unsigned() == 1u8) { panic("cast_unsigned #1266") }
    if !(1i8.count_ones() == 1u32) { panic("count_ones #1267") }
    if !(1i8.count_zeros() == 7u32) { panic("count_zeros #1268") }
    if !(1i8.leading_zeros() == 7u32) { panic("leading_zeros #1269") }
    if !(1i8.trailing_zeros() == 0u32) { panic("trailing_zeros #1270") }
    if !(1i8.leading_ones() == 0u32) { panic("leading_ones #1271") }
    if !(1i8.trailing_ones() == 1u32) { panic("trailing_ones #1272") }
    if !(1i8.reverse_bits() == i8.MIN) { panic("reverse_bits #1273") }
    if !(1i8.swap_bytes() == 1i8) { panic("swap_bytes #1274") }
    if !(1i8.to_be() == 1i8) { panic("to_be #1275") }
    if !(1i8.to_le() == 1i8) { panic("to_le #1276") }
    if !(i8.from_be(1i8) == 1i8) { panic("from_be #1277") }
    if !(i8.from_le(1i8) == 1i8) { panic("from_le #1278") }
    if !(1i8.to_le_bytes() == [1u8]) { panic("to_le_bytes #1279") }
    if !(1i8.to_be_bytes() == [1u8]) { panic("to_be_bytes #1280") }
    if !(1i8.to_ne_bytes() == [1u8]) { panic("to_ne_bytes #1281") }
    if !(i8.from_le_bytes([1u8]) == 1i8) { panic("from_le_bytes #1282") }
    if !(i8.from_be_bytes([1u8]) == 1i8) { panic("from_be_bytes #1283") }
    if !(i8.from_ne_bytes([1u8]) == 1i8) { panic("from_ne_bytes #1284") }
    if !(1i8.rotate_left(0u32) == 1i8) { panic("rotate_left #1285") }
    if !(1i8.rotate_right(0u32) == 1i8) { panic("rotate_right #1286") }
    if !(1i8.checked_shl(0u32) == present(1i8)) { panic("checked_shl #1287") }
    if !(1i8.checked_shr(0u32) == present(1i8)) { panic("checked_shr #1288") }
    if !(1i8.wrapping_shl(0u32) == 1i8) { panic("wrapping_shl #1289") }
    if !(1i8.wrapping_shr(0u32) == 1i8) { panic("wrapping_shr #1290") }
    if !(1i8.overflowing_shl(0u32).0 == 1i8 && 1i8.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1291") }
    if !(1i8.overflowing_shr(0u32).0 == 1i8 && 1i8.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1292") }
    if !(1i8.unbounded_shl(0u32) == 1i8) { panic("unbounded_shl #1293") }
    if !(1i8.unbounded_shr(0u32) == 1i8) { panic("unbounded_shr #1294") }
    if !(1i8.strict_shl(0u32) == 1i8) { panic("strict_shl #1295") }
    if !(1i8.strict_shr(0u32) == 1i8) { panic("strict_shr #1296") }
    if !(unsafe { 1i8.unchecked_shl(0u32) } == 1i8) { panic("unchecked_shl #1297") }
    if !(unsafe { 1i8.unchecked_shr(0u32) } == 1i8) { panic("unchecked_shr #1298") }
    if !(1i8.rotate_left(1u32) == 2i8) { panic("rotate_left #1299") }
    if !(1i8.rotate_right(1u32) == i8.MIN) { panic("rotate_right #1300") }
    if !(1i8.checked_shl(1u32) == present(2i8)) { panic("checked_shl #1301") }
    if !(1i8.checked_shr(1u32) == present(0i8)) { panic("checked_shr #1302") }
    if !(1i8.wrapping_shl(1u32) == 2i8) { panic("wrapping_shl #1303") }
    if !(1i8.wrapping_shr(1u32) == 0i8) { panic("wrapping_shr #1304") }
    if !(1i8.overflowing_shl(1u32).0 == 2i8 && 1i8.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1305") }
    if !(1i8.overflowing_shr(1u32).0 == 0i8 && 1i8.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1306") }
    if !(1i8.unbounded_shl(1u32) == 2i8) { panic("unbounded_shl #1307") }
    if !(1i8.unbounded_shr(1u32) == 0i8) { panic("unbounded_shr #1308") }
    if !(1i8.strict_shl(1u32) == 2i8) { panic("strict_shl #1309") }
    if !(1i8.strict_shr(1u32) == 0i8) { panic("strict_shr #1310") }
    if !(unsafe { 1i8.unchecked_shl(1u32) } == 2i8) { panic("unchecked_shl #1311") }
    if !(unsafe { 1i8.unchecked_shr(1u32) } == 0i8) { panic("unchecked_shr #1312") }
    if !(1i8.rotate_left(3u32) == 8i8) { panic("rotate_left #1313") }
    if !(1i8.rotate_right(3u32) == 32i8) { panic("rotate_right #1314") }
    if !(1i8.checked_shl(3u32) == present(8i8)) { panic("checked_shl #1315") }
    if !(1i8.checked_shr(3u32) == present(0i8)) { panic("checked_shr #1316") }
    if !(1i8.wrapping_shl(3u32) == 8i8) { panic("wrapping_shl #1317") }
    if !(1i8.wrapping_shr(3u32) == 0i8) { panic("wrapping_shr #1318") }
    if !(1i8.overflowing_shl(3u32).0 == 8i8 && 1i8.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1319") }
    if !(1i8.overflowing_shr(3u32).0 == 0i8 && 1i8.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1320") }
}

fn group11() {
    if !(1i8.unbounded_shl(3u32) == 8i8) { panic("unbounded_shl #1321") }
    if !(1i8.unbounded_shr(3u32) == 0i8) { panic("unbounded_shr #1322") }
    if !(1i8.strict_shl(3u32) == 8i8) { panic("strict_shl #1323") }
    if !(1i8.strict_shr(3u32) == 0i8) { panic("strict_shr #1324") }
    if !(unsafe { 1i8.unchecked_shl(3u32) } == 8i8) { panic("unchecked_shl #1325") }
    if !(unsafe { 1i8.unchecked_shr(3u32) } == 0i8) { panic("unchecked_shr #1326") }
    if !(1i8.rotate_left(7u32) == i8.MIN) { panic("rotate_left #1327") }
    if !(1i8.rotate_right(7u32) == 2i8) { panic("rotate_right #1328") }
    if !(1i8.checked_shl(7u32) == present(i8.MIN)) { panic("checked_shl #1329") }
    if !(1i8.checked_shr(7u32) == present(0i8)) { panic("checked_shr #1330") }
    if !(1i8.wrapping_shl(7u32) == i8.MIN) { panic("wrapping_shl #1331") }
    if !(1i8.wrapping_shr(7u32) == 0i8) { panic("wrapping_shr #1332") }
    if !(1i8.overflowing_shl(7u32).0 == i8.MIN && 1i8.overflowing_shl(7u32).1 == false) { panic("overflowing_shl #1333") }
    if !(1i8.overflowing_shr(7u32).0 == 0i8 && 1i8.overflowing_shr(7u32).1 == false) { panic("overflowing_shr #1334") }
    if !(1i8.unbounded_shl(7u32) == i8.MIN) { panic("unbounded_shl #1335") }
    if !(1i8.unbounded_shr(7u32) == 0i8) { panic("unbounded_shr #1336") }
    if !(1i8.strict_shl(7u32) == i8.MIN) { panic("strict_shl #1337") }
    if !(1i8.strict_shr(7u32) == 0i8) { panic("strict_shr #1338") }
    if !(unsafe { 1i8.unchecked_shl(7u32) } == i8.MIN) { panic("unchecked_shl #1339") }
    if !(unsafe { 1i8.unchecked_shr(7u32) } == 0i8) { panic("unchecked_shr #1340") }
    if !(1i8.rotate_left(8u32) == 1i8) { panic("rotate_left #1341") }
    if !(1i8.rotate_right(8u32) == 1i8) { panic("rotate_right #1342") }
    if !(missing(1i8.checked_shl(8u32))) { panic("checked_shl #1343") }
    if !(missing(1i8.checked_shr(8u32))) { panic("checked_shr #1344") }
    if !(1i8.wrapping_shl(8u32) == 1i8) { panic("wrapping_shl #1345") }
    if !(1i8.wrapping_shr(8u32) == 1i8) { panic("wrapping_shr #1346") }
    if !(1i8.overflowing_shl(8u32).0 == 1i8 && 1i8.overflowing_shl(8u32).1 == true) { panic("overflowing_shl #1347") }
    if !(1i8.overflowing_shr(8u32).0 == 1i8 && 1i8.overflowing_shr(8u32).1 == true) { panic("overflowing_shr #1348") }
    if !(1i8.unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #1349") }
    if !(1i8.unbounded_shr(8u32) == 0i8) { panic("unbounded_shr #1350") }
    if !(1i8.rotate_left(13u32) == 32i8) { panic("rotate_left #1351") }
    if !(1i8.rotate_right(13u32) == 8i8) { panic("rotate_right #1352") }
    if !(missing(1i8.checked_shl(13u32))) { panic("checked_shl #1353") }
    if !(missing(1i8.checked_shr(13u32))) { panic("checked_shr #1354") }
    if !(1i8.wrapping_shl(13u32) == 32i8) { panic("wrapping_shl #1355") }
    if !(1i8.wrapping_shr(13u32) == 0i8) { panic("wrapping_shr #1356") }
    if !(1i8.overflowing_shl(13u32).0 == 32i8 && 1i8.overflowing_shl(13u32).1 == true) { panic("overflowing_shl #1357") }
    if !(1i8.overflowing_shr(13u32).0 == 0i8 && 1i8.overflowing_shr(13u32).1 == true) { panic("overflowing_shr #1358") }
    if !(1i8.unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #1359") }
    if !(1i8.unbounded_shr(13u32) == 0i8) { panic("unbounded_shr #1360") }
    if !(1i8.checked_pow(0u32) == present(1i8)) { panic("checked_pow #1361") }
    if !(1i8.wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #1362") }
    if !(1i8.overflowing_pow(0u32).0 == 1i8 && 1i8.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1363") }
    if !(1i8.saturating_pow(0u32) == 1i8) { panic("saturating_pow #1364") }
    if !(1i8.pow(0u32) == 1i8) { panic("pow #1365") }
    if !(1i8.strict_pow(0u32) == 1i8) { panic("strict_pow #1366") }
    if !(1i8.checked_pow(1u32) == present(1i8)) { panic("checked_pow #1367") }
    if !(1i8.wrapping_pow(1u32) == 1i8) { panic("wrapping_pow #1368") }
    if !(1i8.overflowing_pow(1u32).0 == 1i8 && 1i8.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1369") }
    if !(1i8.saturating_pow(1u32) == 1i8) { panic("saturating_pow #1370") }
    if !(1i8.pow(1u32) == 1i8) { panic("pow #1371") }
    if !(1i8.strict_pow(1u32) == 1i8) { panic("strict_pow #1372") }
    if !(1i8.checked_pow(2u32) == present(1i8)) { panic("checked_pow #1373") }
    if !(1i8.wrapping_pow(2u32) == 1i8) { panic("wrapping_pow #1374") }
    if !(1i8.overflowing_pow(2u32).0 == 1i8 && 1i8.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1375") }
    if !(1i8.saturating_pow(2u32) == 1i8) { panic("saturating_pow #1376") }
    if !(1i8.pow(2u32) == 1i8) { panic("pow #1377") }
    if !(1i8.strict_pow(2u32) == 1i8) { panic("strict_pow #1378") }
    if !(1i8.checked_pow(3u32) == present(1i8)) { panic("checked_pow #1379") }
    if !(1i8.wrapping_pow(3u32) == 1i8) { panic("wrapping_pow #1380") }
    if !(1i8.overflowing_pow(3u32).0 == 1i8 && 1i8.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1381") }
    if !(1i8.saturating_pow(3u32) == 1i8) { panic("saturating_pow #1382") }
    if !(1i8.pow(3u32) == 1i8) { panic("pow #1383") }
    if !(1i8.strict_pow(3u32) == 1i8) { panic("strict_pow #1384") }
    if !(1i8.checked_pow(7u32) == present(1i8)) { panic("checked_pow #1385") }
    if !(1i8.wrapping_pow(7u32) == 1i8) { panic("wrapping_pow #1386") }
    if !(1i8.overflowing_pow(7u32).0 == 1i8 && 1i8.overflowing_pow(7u32).1 == false) { panic("overflowing_pow #1387") }
    if !(1i8.saturating_pow(7u32) == 1i8) { panic("saturating_pow #1388") }
    if !(1i8.pow(7u32) == 1i8) { panic("pow #1389") }
    if !(1i8.strict_pow(7u32) == 1i8) { panic("strict_pow #1390") }
    if !(1i8.checked_pow(8u32) == present(1i8)) { panic("checked_pow #1391") }
    if !(1i8.wrapping_pow(8u32) == 1i8) { panic("wrapping_pow #1392") }
    if !(1i8.overflowing_pow(8u32).0 == 1i8 && 1i8.overflowing_pow(8u32).1 == false) { panic("overflowing_pow #1393") }
    if !(1i8.saturating_pow(8u32) == 1i8) { panic("saturating_pow #1394") }
    if !(1i8.pow(8u32) == 1i8) { panic("pow #1395") }
    if !(1i8.strict_pow(8u32) == 1i8) { panic("strict_pow #1396") }
    if !(1i8.ilog2() == 0u32) { panic("ilog2 #1397") }
    if !(1i8.ilog10() == 0u32) { panic("ilog10 #1398") }
    if !(1i8.checked_ilog2() == present(0u32)) { panic("checked_ilog2 #1399") }
    if !(1i8.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1400") }
    if !(1i8.ilog(2i8) == 0u32) { panic("ilog #1401") }
    if !(1i8.checked_ilog(2i8) == present(0u32)) { panic("checked_ilog #1402") }
    if !(1i8.ilog(3i8) == 0u32) { panic("ilog #1403") }
    if !(1i8.checked_ilog(3i8) == present(0u32)) { panic("checked_ilog #1404") }
    if !(1i8.ilog(7i8) == 0u32) { panic("ilog #1405") }
    if !(1i8.checked_ilog(7i8) == present(0u32)) { panic("checked_ilog #1406") }
    if !(missing(1i8.checked_ilog(1i8))) { panic("checked_ilog #1407") }
    if !(1i8.isqrt() == 1i8) { panic("isqrt #1408") }
    if !(1i8.checked_isqrt() == present(1i8)) { panic("checked_isqrt #1409") }
    if !(1i8.highest_one() == present(0u32)) { panic("highest_one #1410") }
    if !(1i8.lowest_one() == present(0u32)) { panic("lowest_one #1411") }
    if !(1i8.isolate_highest_one() == 1i8) { panic("isolate_highest_one #1412") }
    if !(1i8.isolate_lowest_one() == 1i8) { panic("isolate_lowest_one #1413") }
    if !((-7i8).checked_neg() == present(7i8)) { panic("checked_neg #1414") }
    if !((-7i8).wrapping_neg() == 7i8) { panic("wrapping_neg #1415") }
    if !((-7i8).overflowing_neg().0 == 7i8 && (-7i8).overflowing_neg().1 == false) { panic("overflowing_neg #1416") }
    if !((-7i8).strict_neg() == 7i8) { panic("strict_neg #1417") }
    if !(unsafe { (-7i8).unchecked_neg() } == 7i8) { panic("unchecked_neg #1418") }
    if !((-7i8).saturating_neg() == 7i8) { panic("saturating_neg #1419") }
    if !((-7i8).checked_abs() == present(7i8)) { panic("checked_abs #1420") }
    if !((-7i8).wrapping_abs() == 7i8) { panic("wrapping_abs #1421") }
    if !((-7i8).overflowing_abs().0 == 7i8 && (-7i8).overflowing_abs().1 == false) { panic("overflowing_abs #1422") }
    if !((-7i8).saturating_abs() == 7i8) { panic("saturating_abs #1423") }
    if !((-7i8).strict_abs() == 7i8) { panic("strict_abs #1424") }
    if !((-7i8).abs() == 7i8) { panic("abs #1425") }
    if !((-7i8).unsigned_abs() == 7u8) { panic("unsigned_abs #1426") }
    if !((-7i8).signum() == (-1i8)) { panic("signum #1427") }
    if !((-7i8).is_positive() == false) { panic("is_positive #1428") }
    if !((-7i8).is_negative() == true) { panic("is_negative #1429") }
    if !((-7i8).cast_unsigned() == 249u8) { panic("cast_unsigned #1430") }
    if !((-7i8).count_ones() == 6u32) { panic("count_ones #1431") }
    if !((-7i8).count_zeros() == 2u32) { panic("count_zeros #1432") }
    if !((-7i8).leading_zeros() == 0u32) { panic("leading_zeros #1433") }
    if !((-7i8).trailing_zeros() == 0u32) { panic("trailing_zeros #1434") }
    if !((-7i8).leading_ones() == 5u32) { panic("leading_ones #1435") }
    if !((-7i8).trailing_ones() == 1u32) { panic("trailing_ones #1436") }
    if !((-7i8).reverse_bits() == (-97i8)) { panic("reverse_bits #1437") }
    if !((-7i8).swap_bytes() == (-7i8)) { panic("swap_bytes #1438") }
    if !((-7i8).to_be() == (-7i8)) { panic("to_be #1439") }
    if !((-7i8).to_le() == (-7i8)) { panic("to_le #1440") }
}

fn group12() {
    if !(i8.from_be((-7i8)) == (-7i8)) { panic("from_be #1441") }
    if !(i8.from_le((-7i8)) == (-7i8)) { panic("from_le #1442") }
    if !((-7i8).to_le_bytes() == [249u8]) { panic("to_le_bytes #1443") }
    if !((-7i8).to_be_bytes() == [249u8]) { panic("to_be_bytes #1444") }
    if !((-7i8).to_ne_bytes() == [249u8]) { panic("to_ne_bytes #1445") }
    if !(i8.from_le_bytes([249u8]) == (-7i8)) { panic("from_le_bytes #1446") }
    if !(i8.from_be_bytes([249u8]) == (-7i8)) { panic("from_be_bytes #1447") }
    if !(i8.from_ne_bytes([249u8]) == (-7i8)) { panic("from_ne_bytes #1448") }
    if !((-7i8).rotate_left(0u32) == (-7i8)) { panic("rotate_left #1449") }
    if !((-7i8).rotate_right(0u32) == (-7i8)) { panic("rotate_right #1450") }
    if !((-7i8).checked_shl(0u32) == present((-7i8))) { panic("checked_shl #1451") }
    if !((-7i8).checked_shr(0u32) == present((-7i8))) { panic("checked_shr #1452") }
    if !((-7i8).wrapping_shl(0u32) == (-7i8)) { panic("wrapping_shl #1453") }
    if !((-7i8).wrapping_shr(0u32) == (-7i8)) { panic("wrapping_shr #1454") }
    if !((-7i8).overflowing_shl(0u32).0 == (-7i8) && (-7i8).overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1455") }
    if !((-7i8).overflowing_shr(0u32).0 == (-7i8) && (-7i8).overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1456") }
    if !((-7i8).unbounded_shl(0u32) == (-7i8)) { panic("unbounded_shl #1457") }
    if !((-7i8).unbounded_shr(0u32) == (-7i8)) { panic("unbounded_shr #1458") }
    if !((-7i8).strict_shl(0u32) == (-7i8)) { panic("strict_shl #1459") }
    if !((-7i8).strict_shr(0u32) == (-7i8)) { panic("strict_shr #1460") }
    if !(unsafe { (-7i8).unchecked_shl(0u32) } == (-7i8)) { panic("unchecked_shl #1461") }
    if !(unsafe { (-7i8).unchecked_shr(0u32) } == (-7i8)) { panic("unchecked_shr #1462") }
    if !((-7i8).rotate_left(1u32) == (-13i8)) { panic("rotate_left #1463") }
    if !((-7i8).rotate_right(1u32) == (-4i8)) { panic("rotate_right #1464") }
    if !((-7i8).checked_shl(1u32) == present((-14i8))) { panic("checked_shl #1465") }
    if !((-7i8).checked_shr(1u32) == present((-4i8))) { panic("checked_shr #1466") }
    if !((-7i8).wrapping_shl(1u32) == (-14i8)) { panic("wrapping_shl #1467") }
    if !((-7i8).wrapping_shr(1u32) == (-4i8)) { panic("wrapping_shr #1468") }
    if !((-7i8).overflowing_shl(1u32).0 == (-14i8) && (-7i8).overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1469") }
    if !((-7i8).overflowing_shr(1u32).0 == (-4i8) && (-7i8).overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1470") }
    if !((-7i8).unbounded_shl(1u32) == (-14i8)) { panic("unbounded_shl #1471") }
    if !((-7i8).unbounded_shr(1u32) == (-4i8)) { panic("unbounded_shr #1472") }
    if !((-7i8).strict_shl(1u32) == (-14i8)) { panic("strict_shl #1473") }
    if !((-7i8).strict_shr(1u32) == (-4i8)) { panic("strict_shr #1474") }
    if !(unsafe { (-7i8).unchecked_shl(1u32) } == (-14i8)) { panic("unchecked_shl #1475") }
    if !(unsafe { (-7i8).unchecked_shr(1u32) } == (-4i8)) { panic("unchecked_shr #1476") }
    if !((-7i8).rotate_left(3u32) == (-49i8)) { panic("rotate_left #1477") }
    if !((-7i8).rotate_right(3u32) == 63i8) { panic("rotate_right #1478") }
    if !((-7i8).checked_shl(3u32) == present((-56i8))) { panic("checked_shl #1479") }
    if !((-7i8).checked_shr(3u32) == present((-1i8))) { panic("checked_shr #1480") }
    if !((-7i8).wrapping_shl(3u32) == (-56i8)) { panic("wrapping_shl #1481") }
    if !((-7i8).wrapping_shr(3u32) == (-1i8)) { panic("wrapping_shr #1482") }
    if !((-7i8).overflowing_shl(3u32).0 == (-56i8) && (-7i8).overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1483") }
    if !((-7i8).overflowing_shr(3u32).0 == (-1i8) && (-7i8).overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1484") }
    if !((-7i8).unbounded_shl(3u32) == (-56i8)) { panic("unbounded_shl #1485") }
    if !((-7i8).unbounded_shr(3u32) == (-1i8)) { panic("unbounded_shr #1486") }
    if !((-7i8).strict_shl(3u32) == (-56i8)) { panic("strict_shl #1487") }
    if !((-7i8).strict_shr(3u32) == (-1i8)) { panic("strict_shr #1488") }
    if !(unsafe { (-7i8).unchecked_shl(3u32) } == (-56i8)) { panic("unchecked_shl #1489") }
    if !(unsafe { (-7i8).unchecked_shr(3u32) } == (-1i8)) { panic("unchecked_shr #1490") }
    if !((-7i8).rotate_left(7u32) == (-4i8)) { panic("rotate_left #1491") }
    if !((-7i8).rotate_right(7u32) == (-13i8)) { panic("rotate_right #1492") }
    if !((-7i8).checked_shl(7u32) == present(i8.MIN)) { panic("checked_shl #1493") }
    if !((-7i8).checked_shr(7u32) == present((-1i8))) { panic("checked_shr #1494") }
    if !((-7i8).wrapping_shl(7u32) == i8.MIN) { panic("wrapping_shl #1495") }
    if !((-7i8).wrapping_shr(7u32) == (-1i8)) { panic("wrapping_shr #1496") }
    if !((-7i8).overflowing_shl(7u32).0 == i8.MIN && (-7i8).overflowing_shl(7u32).1 == false) { panic("overflowing_shl #1497") }
    if !((-7i8).overflowing_shr(7u32).0 == (-1i8) && (-7i8).overflowing_shr(7u32).1 == false) { panic("overflowing_shr #1498") }
    if !((-7i8).unbounded_shl(7u32) == i8.MIN) { panic("unbounded_shl #1499") }
    if !((-7i8).unbounded_shr(7u32) == (-1i8)) { panic("unbounded_shr #1500") }
    if !((-7i8).strict_shl(7u32) == i8.MIN) { panic("strict_shl #1501") }
    if !((-7i8).strict_shr(7u32) == (-1i8)) { panic("strict_shr #1502") }
    if !(unsafe { (-7i8).unchecked_shl(7u32) } == i8.MIN) { panic("unchecked_shl #1503") }
    if !(unsafe { (-7i8).unchecked_shr(7u32) } == (-1i8)) { panic("unchecked_shr #1504") }
    if !((-7i8).rotate_left(8u32) == (-7i8)) { panic("rotate_left #1505") }
    if !((-7i8).rotate_right(8u32) == (-7i8)) { panic("rotate_right #1506") }
    if !(missing((-7i8).checked_shl(8u32))) { panic("checked_shl #1507") }
    if !(missing((-7i8).checked_shr(8u32))) { panic("checked_shr #1508") }
    if !((-7i8).wrapping_shl(8u32) == (-7i8)) { panic("wrapping_shl #1509") }
    if !((-7i8).wrapping_shr(8u32) == (-7i8)) { panic("wrapping_shr #1510") }
    if !((-7i8).overflowing_shl(8u32).0 == (-7i8) && (-7i8).overflowing_shl(8u32).1 == true) { panic("overflowing_shl #1511") }
    if !((-7i8).overflowing_shr(8u32).0 == (-7i8) && (-7i8).overflowing_shr(8u32).1 == true) { panic("overflowing_shr #1512") }
    if !((-7i8).unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #1513") }
    if !((-7i8).unbounded_shr(8u32) == (-1i8)) { panic("unbounded_shr #1514") }
    if !((-7i8).rotate_left(13u32) == 63i8) { panic("rotate_left #1515") }
    if !((-7i8).rotate_right(13u32) == (-49i8)) { panic("rotate_right #1516") }
    if !(missing((-7i8).checked_shl(13u32))) { panic("checked_shl #1517") }
    if !(missing((-7i8).checked_shr(13u32))) { panic("checked_shr #1518") }
    if !((-7i8).wrapping_shl(13u32) == 32i8) { panic("wrapping_shl #1519") }
    if !((-7i8).wrapping_shr(13u32) == (-1i8)) { panic("wrapping_shr #1520") }
    if !((-7i8).overflowing_shl(13u32).0 == 32i8 && (-7i8).overflowing_shl(13u32).1 == true) { panic("overflowing_shl #1521") }
    if !((-7i8).overflowing_shr(13u32).0 == (-1i8) && (-7i8).overflowing_shr(13u32).1 == true) { panic("overflowing_shr #1522") }
    if !((-7i8).unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #1523") }
    if !((-7i8).unbounded_shr(13u32) == (-1i8)) { panic("unbounded_shr #1524") }
    if !((-7i8).checked_pow(0u32) == present(1i8)) { panic("checked_pow #1525") }
    if !((-7i8).wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #1526") }
    if !((-7i8).overflowing_pow(0u32).0 == 1i8 && (-7i8).overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1527") }
    if !((-7i8).saturating_pow(0u32) == 1i8) { panic("saturating_pow #1528") }
    if !((-7i8).pow(0u32) == 1i8) { panic("pow #1529") }
    if !((-7i8).strict_pow(0u32) == 1i8) { panic("strict_pow #1530") }
    if !((-7i8).checked_pow(1u32) == present((-7i8))) { panic("checked_pow #1531") }
    if !((-7i8).wrapping_pow(1u32) == (-7i8)) { panic("wrapping_pow #1532") }
    if !((-7i8).overflowing_pow(1u32).0 == (-7i8) && (-7i8).overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1533") }
    if !((-7i8).saturating_pow(1u32) == (-7i8)) { panic("saturating_pow #1534") }
    if !((-7i8).pow(1u32) == (-7i8)) { panic("pow #1535") }
    if !((-7i8).strict_pow(1u32) == (-7i8)) { panic("strict_pow #1536") }
    if !((-7i8).checked_pow(2u32) == present(49i8)) { panic("checked_pow #1537") }
    if !((-7i8).wrapping_pow(2u32) == 49i8) { panic("wrapping_pow #1538") }
    if !((-7i8).overflowing_pow(2u32).0 == 49i8 && (-7i8).overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1539") }
    if !((-7i8).saturating_pow(2u32) == 49i8) { panic("saturating_pow #1540") }
    if !((-7i8).pow(2u32) == 49i8) { panic("pow #1541") }
    if !((-7i8).strict_pow(2u32) == 49i8) { panic("strict_pow #1542") }
    if !(missing((-7i8).checked_pow(3u32))) { panic("checked_pow #1543") }
    if !((-7i8).wrapping_pow(3u32) == (-87i8)) { panic("wrapping_pow #1544") }
    if !((-7i8).overflowing_pow(3u32).0 == (-87i8) && (-7i8).overflowing_pow(3u32).1 == true) { panic("overflowing_pow #1545") }
    if !((-7i8).saturating_pow(3u32) == i8.MIN) { panic("saturating_pow #1546") }
    if !(missing((-7i8).checked_pow(7u32))) { panic("checked_pow #1547") }
    if !((-7i8).wrapping_pow(7u32) == 9i8) { panic("wrapping_pow #1548") }
    if !((-7i8).overflowing_pow(7u32).0 == 9i8 && (-7i8).overflowing_pow(7u32).1 == true) { panic("overflowing_pow #1549") }
    if !((-7i8).saturating_pow(7u32) == i8.MIN) { panic("saturating_pow #1550") }
    if !(missing((-7i8).checked_pow(8u32))) { panic("checked_pow #1551") }
    if !((-7i8).wrapping_pow(8u32) == (-63i8)) { panic("wrapping_pow #1552") }
    if !((-7i8).overflowing_pow(8u32).0 == (-63i8) && (-7i8).overflowing_pow(8u32).1 == true) { panic("overflowing_pow #1553") }
    if !((-7i8).saturating_pow(8u32) == i8.MAX) { panic("saturating_pow #1554") }
    if !(missing((-7i8).checked_ilog2())) { panic("checked_ilog2 #1555") }
    if !(missing((-7i8).checked_ilog10())) { panic("checked_ilog10 #1556") }
    if !(missing((-7i8).checked_ilog(2i8))) { panic("checked_ilog #1557") }
    if !(missing((-7i8).checked_isqrt())) { panic("checked_isqrt #1558") }
    if !((-7i8).highest_one() == present(7u32)) { panic("highest_one #1559") }
    if !((-7i8).lowest_one() == present(0u32)) { panic("lowest_one #1560") }
}

fn group13() {
    if !((-7i8).isolate_highest_one() == i8.MIN) { panic("isolate_highest_one #1561") }
    if !((-7i8).isolate_lowest_one() == 1i8) { panic("isolate_lowest_one #1562") }
    if !((-1i8).checked_neg() == present(1i8)) { panic("checked_neg #1563") }
    if !((-1i8).wrapping_neg() == 1i8) { panic("wrapping_neg #1564") }
    if !((-1i8).overflowing_neg().0 == 1i8 && (-1i8).overflowing_neg().1 == false) { panic("overflowing_neg #1565") }
    if !((-1i8).strict_neg() == 1i8) { panic("strict_neg #1566") }
    if !(unsafe { (-1i8).unchecked_neg() } == 1i8) { panic("unchecked_neg #1567") }
    if !((-1i8).saturating_neg() == 1i8) { panic("saturating_neg #1568") }
    if !((-1i8).checked_abs() == present(1i8)) { panic("checked_abs #1569") }
    if !((-1i8).wrapping_abs() == 1i8) { panic("wrapping_abs #1570") }
    if !((-1i8).overflowing_abs().0 == 1i8 && (-1i8).overflowing_abs().1 == false) { panic("overflowing_abs #1571") }
    if !((-1i8).saturating_abs() == 1i8) { panic("saturating_abs #1572") }
    if !((-1i8).strict_abs() == 1i8) { panic("strict_abs #1573") }
    if !((-1i8).abs() == 1i8) { panic("abs #1574") }
    if !((-1i8).unsigned_abs() == 1u8) { panic("unsigned_abs #1575") }
    if !((-1i8).signum() == (-1i8)) { panic("signum #1576") }
    if !((-1i8).is_positive() == false) { panic("is_positive #1577") }
    if !((-1i8).is_negative() == true) { panic("is_negative #1578") }
    if !((-1i8).cast_unsigned() == 255u8) { panic("cast_unsigned #1579") }
    if !((-1i8).count_ones() == 8u32) { panic("count_ones #1580") }
    if !((-1i8).count_zeros() == 0u32) { panic("count_zeros #1581") }
    if !((-1i8).leading_zeros() == 0u32) { panic("leading_zeros #1582") }
    if !((-1i8).trailing_zeros() == 0u32) { panic("trailing_zeros #1583") }
    if !((-1i8).leading_ones() == 8u32) { panic("leading_ones #1584") }
    if !((-1i8).trailing_ones() == 8u32) { panic("trailing_ones #1585") }
    if !((-1i8).reverse_bits() == (-1i8)) { panic("reverse_bits #1586") }
    if !((-1i8).swap_bytes() == (-1i8)) { panic("swap_bytes #1587") }
    if !((-1i8).to_be() == (-1i8)) { panic("to_be #1588") }
    if !((-1i8).to_le() == (-1i8)) { panic("to_le #1589") }
    if !(i8.from_be((-1i8)) == (-1i8)) { panic("from_be #1590") }
    if !(i8.from_le((-1i8)) == (-1i8)) { panic("from_le #1591") }
    if !((-1i8).to_le_bytes() == [255u8]) { panic("to_le_bytes #1592") }
    if !((-1i8).to_be_bytes() == [255u8]) { panic("to_be_bytes #1593") }
    if !((-1i8).to_ne_bytes() == [255u8]) { panic("to_ne_bytes #1594") }
    if !(i8.from_le_bytes([255u8]) == (-1i8)) { panic("from_le_bytes #1595") }
    if !(i8.from_be_bytes([255u8]) == (-1i8)) { panic("from_be_bytes #1596") }
    if !(i8.from_ne_bytes([255u8]) == (-1i8)) { panic("from_ne_bytes #1597") }
    if !((-1i8).rotate_left(0u32) == (-1i8)) { panic("rotate_left #1598") }
    if !((-1i8).rotate_right(0u32) == (-1i8)) { panic("rotate_right #1599") }
    if !((-1i8).checked_shl(0u32) == present((-1i8))) { panic("checked_shl #1600") }
    if !((-1i8).checked_shr(0u32) == present((-1i8))) { panic("checked_shr #1601") }
    if !((-1i8).wrapping_shl(0u32) == (-1i8)) { panic("wrapping_shl #1602") }
    if !((-1i8).wrapping_shr(0u32) == (-1i8)) { panic("wrapping_shr #1603") }
    if !((-1i8).overflowing_shl(0u32).0 == (-1i8) && (-1i8).overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1604") }
    if !((-1i8).overflowing_shr(0u32).0 == (-1i8) && (-1i8).overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1605") }
    if !((-1i8).unbounded_shl(0u32) == (-1i8)) { panic("unbounded_shl #1606") }
    if !((-1i8).unbounded_shr(0u32) == (-1i8)) { panic("unbounded_shr #1607") }
    if !((-1i8).strict_shl(0u32) == (-1i8)) { panic("strict_shl #1608") }
    if !((-1i8).strict_shr(0u32) == (-1i8)) { panic("strict_shr #1609") }
    if !(unsafe { (-1i8).unchecked_shl(0u32) } == (-1i8)) { panic("unchecked_shl #1610") }
    if !(unsafe { (-1i8).unchecked_shr(0u32) } == (-1i8)) { panic("unchecked_shr #1611") }
    if !((-1i8).rotate_left(1u32) == (-1i8)) { panic("rotate_left #1612") }
    if !((-1i8).rotate_right(1u32) == (-1i8)) { panic("rotate_right #1613") }
    if !((-1i8).checked_shl(1u32) == present((-2i8))) { panic("checked_shl #1614") }
    if !((-1i8).checked_shr(1u32) == present((-1i8))) { panic("checked_shr #1615") }
    if !((-1i8).wrapping_shl(1u32) == (-2i8)) { panic("wrapping_shl #1616") }
    if !((-1i8).wrapping_shr(1u32) == (-1i8)) { panic("wrapping_shr #1617") }
    if !((-1i8).overflowing_shl(1u32).0 == (-2i8) && (-1i8).overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1618") }
    if !((-1i8).overflowing_shr(1u32).0 == (-1i8) && (-1i8).overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1619") }
    if !((-1i8).unbounded_shl(1u32) == (-2i8)) { panic("unbounded_shl #1620") }
    if !((-1i8).unbounded_shr(1u32) == (-1i8)) { panic("unbounded_shr #1621") }
    if !((-1i8).strict_shl(1u32) == (-2i8)) { panic("strict_shl #1622") }
    if !((-1i8).strict_shr(1u32) == (-1i8)) { panic("strict_shr #1623") }
    if !(unsafe { (-1i8).unchecked_shl(1u32) } == (-2i8)) { panic("unchecked_shl #1624") }
    if !(unsafe { (-1i8).unchecked_shr(1u32) } == (-1i8)) { panic("unchecked_shr #1625") }
    if !((-1i8).rotate_left(3u32) == (-1i8)) { panic("rotate_left #1626") }
    if !((-1i8).rotate_right(3u32) == (-1i8)) { panic("rotate_right #1627") }
    if !((-1i8).checked_shl(3u32) == present((-8i8))) { panic("checked_shl #1628") }
    if !((-1i8).checked_shr(3u32) == present((-1i8))) { panic("checked_shr #1629") }
    if !((-1i8).wrapping_shl(3u32) == (-8i8)) { panic("wrapping_shl #1630") }
    if !((-1i8).wrapping_shr(3u32) == (-1i8)) { panic("wrapping_shr #1631") }
    if !((-1i8).overflowing_shl(3u32).0 == (-8i8) && (-1i8).overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1632") }
    if !((-1i8).overflowing_shr(3u32).0 == (-1i8) && (-1i8).overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1633") }
    if !((-1i8).unbounded_shl(3u32) == (-8i8)) { panic("unbounded_shl #1634") }
    if !((-1i8).unbounded_shr(3u32) == (-1i8)) { panic("unbounded_shr #1635") }
    if !((-1i8).strict_shl(3u32) == (-8i8)) { panic("strict_shl #1636") }
    if !((-1i8).strict_shr(3u32) == (-1i8)) { panic("strict_shr #1637") }
    if !(unsafe { (-1i8).unchecked_shl(3u32) } == (-8i8)) { panic("unchecked_shl #1638") }
    if !(unsafe { (-1i8).unchecked_shr(3u32) } == (-1i8)) { panic("unchecked_shr #1639") }
    if !((-1i8).rotate_left(7u32) == (-1i8)) { panic("rotate_left #1640") }
    if !((-1i8).rotate_right(7u32) == (-1i8)) { panic("rotate_right #1641") }
    if !((-1i8).checked_shl(7u32) == present(i8.MIN)) { panic("checked_shl #1642") }
    if !((-1i8).checked_shr(7u32) == present((-1i8))) { panic("checked_shr #1643") }
    if !((-1i8).wrapping_shl(7u32) == i8.MIN) { panic("wrapping_shl #1644") }
    if !((-1i8).wrapping_shr(7u32) == (-1i8)) { panic("wrapping_shr #1645") }
    if !((-1i8).overflowing_shl(7u32).0 == i8.MIN && (-1i8).overflowing_shl(7u32).1 == false) { panic("overflowing_shl #1646") }
    if !((-1i8).overflowing_shr(7u32).0 == (-1i8) && (-1i8).overflowing_shr(7u32).1 == false) { panic("overflowing_shr #1647") }
    if !((-1i8).unbounded_shl(7u32) == i8.MIN) { panic("unbounded_shl #1648") }
    if !((-1i8).unbounded_shr(7u32) == (-1i8)) { panic("unbounded_shr #1649") }
    if !((-1i8).strict_shl(7u32) == i8.MIN) { panic("strict_shl #1650") }
    if !((-1i8).strict_shr(7u32) == (-1i8)) { panic("strict_shr #1651") }
    if !(unsafe { (-1i8).unchecked_shl(7u32) } == i8.MIN) { panic("unchecked_shl #1652") }
    if !(unsafe { (-1i8).unchecked_shr(7u32) } == (-1i8)) { panic("unchecked_shr #1653") }
    if !((-1i8).rotate_left(8u32) == (-1i8)) { panic("rotate_left #1654") }
    if !((-1i8).rotate_right(8u32) == (-1i8)) { panic("rotate_right #1655") }
    if !(missing((-1i8).checked_shl(8u32))) { panic("checked_shl #1656") }
    if !(missing((-1i8).checked_shr(8u32))) { panic("checked_shr #1657") }
    if !((-1i8).wrapping_shl(8u32) == (-1i8)) { panic("wrapping_shl #1658") }
    if !((-1i8).wrapping_shr(8u32) == (-1i8)) { panic("wrapping_shr #1659") }
    if !((-1i8).overflowing_shl(8u32).0 == (-1i8) && (-1i8).overflowing_shl(8u32).1 == true) { panic("overflowing_shl #1660") }
    if !((-1i8).overflowing_shr(8u32).0 == (-1i8) && (-1i8).overflowing_shr(8u32).1 == true) { panic("overflowing_shr #1661") }
    if !((-1i8).unbounded_shl(8u32) == 0i8) { panic("unbounded_shl #1662") }
    if !((-1i8).unbounded_shr(8u32) == (-1i8)) { panic("unbounded_shr #1663") }
    if !((-1i8).rotate_left(13u32) == (-1i8)) { panic("rotate_left #1664") }
    if !((-1i8).rotate_right(13u32) == (-1i8)) { panic("rotate_right #1665") }
    if !(missing((-1i8).checked_shl(13u32))) { panic("checked_shl #1666") }
    if !(missing((-1i8).checked_shr(13u32))) { panic("checked_shr #1667") }
    if !((-1i8).wrapping_shl(13u32) == (-32i8)) { panic("wrapping_shl #1668") }
    if !((-1i8).wrapping_shr(13u32) == (-1i8)) { panic("wrapping_shr #1669") }
    if !((-1i8).overflowing_shl(13u32).0 == (-32i8) && (-1i8).overflowing_shl(13u32).1 == true) { panic("overflowing_shl #1670") }
    if !((-1i8).overflowing_shr(13u32).0 == (-1i8) && (-1i8).overflowing_shr(13u32).1 == true) { panic("overflowing_shr #1671") }
    if !((-1i8).unbounded_shl(13u32) == 0i8) { panic("unbounded_shl #1672") }
    if !((-1i8).unbounded_shr(13u32) == (-1i8)) { panic("unbounded_shr #1673") }
    if !((-1i8).checked_pow(0u32) == present(1i8)) { panic("checked_pow #1674") }
    if !((-1i8).wrapping_pow(0u32) == 1i8) { panic("wrapping_pow #1675") }
    if !((-1i8).overflowing_pow(0u32).0 == 1i8 && (-1i8).overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1676") }
    if !((-1i8).saturating_pow(0u32) == 1i8) { panic("saturating_pow #1677") }
    if !((-1i8).pow(0u32) == 1i8) { panic("pow #1678") }
    if !((-1i8).strict_pow(0u32) == 1i8) { panic("strict_pow #1679") }
    if !((-1i8).checked_pow(1u32) == present((-1i8))) { panic("checked_pow #1680") }
}

fn group14() {
    if !((-1i8).wrapping_pow(1u32) == (-1i8)) { panic("wrapping_pow #1681") }
    if !((-1i8).overflowing_pow(1u32).0 == (-1i8) && (-1i8).overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1682") }
    if !((-1i8).saturating_pow(1u32) == (-1i8)) { panic("saturating_pow #1683") }
    if !((-1i8).pow(1u32) == (-1i8)) { panic("pow #1684") }
    if !((-1i8).strict_pow(1u32) == (-1i8)) { panic("strict_pow #1685") }
    if !((-1i8).checked_pow(2u32) == present(1i8)) { panic("checked_pow #1686") }
    if !((-1i8).wrapping_pow(2u32) == 1i8) { panic("wrapping_pow #1687") }
    if !((-1i8).overflowing_pow(2u32).0 == 1i8 && (-1i8).overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1688") }
    if !((-1i8).saturating_pow(2u32) == 1i8) { panic("saturating_pow #1689") }
    if !((-1i8).pow(2u32) == 1i8) { panic("pow #1690") }
    if !((-1i8).strict_pow(2u32) == 1i8) { panic("strict_pow #1691") }
    if !((-1i8).checked_pow(3u32) == present((-1i8))) { panic("checked_pow #1692") }
    if !((-1i8).wrapping_pow(3u32) == (-1i8)) { panic("wrapping_pow #1693") }
    if !((-1i8).overflowing_pow(3u32).0 == (-1i8) && (-1i8).overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1694") }
    if !((-1i8).saturating_pow(3u32) == (-1i8)) { panic("saturating_pow #1695") }
    if !((-1i8).pow(3u32) == (-1i8)) { panic("pow #1696") }
    if !((-1i8).strict_pow(3u32) == (-1i8)) { panic("strict_pow #1697") }
    if !((-1i8).checked_pow(7u32) == present((-1i8))) { panic("checked_pow #1698") }
    if !((-1i8).wrapping_pow(7u32) == (-1i8)) { panic("wrapping_pow #1699") }
    if !((-1i8).overflowing_pow(7u32).0 == (-1i8) && (-1i8).overflowing_pow(7u32).1 == false) { panic("overflowing_pow #1700") }
    if !((-1i8).saturating_pow(7u32) == (-1i8)) { panic("saturating_pow #1701") }
    if !((-1i8).pow(7u32) == (-1i8)) { panic("pow #1702") }
    if !((-1i8).strict_pow(7u32) == (-1i8)) { panic("strict_pow #1703") }
    if !((-1i8).checked_pow(8u32) == present(1i8)) { panic("checked_pow #1704") }
    if !((-1i8).wrapping_pow(8u32) == 1i8) { panic("wrapping_pow #1705") }
    if !((-1i8).overflowing_pow(8u32).0 == 1i8 && (-1i8).overflowing_pow(8u32).1 == false) { panic("overflowing_pow #1706") }
    if !((-1i8).saturating_pow(8u32) == 1i8) { panic("saturating_pow #1707") }
    if !((-1i8).pow(8u32) == 1i8) { panic("pow #1708") }
    if !((-1i8).strict_pow(8u32) == 1i8) { panic("strict_pow #1709") }
    if !(missing((-1i8).checked_ilog2())) { panic("checked_ilog2 #1710") }
    if !(missing((-1i8).checked_ilog10())) { panic("checked_ilog10 #1711") }
    if !(missing((-1i8).checked_ilog(2i8))) { panic("checked_ilog #1712") }
    if !(missing((-1i8).checked_isqrt())) { panic("checked_isqrt #1713") }
    if !((-1i8).highest_one() == present(7u32)) { panic("highest_one #1714") }
    if !((-1i8).lowest_one() == present(0u32)) { panic("lowest_one #1715") }
    if !((-1i8).isolate_highest_one() == i8.MIN) { panic("isolate_highest_one #1716") }
    if !((-1i8).isolate_lowest_one() == 1i8) { panic("isolate_lowest_one #1717") }
    if !(parsed(capture num.from_str_radix<i8>("127", 10u32)) == present(i8.MAX)) { panic("from_str_radix #1718") }
    if !(parsed(capture num.from_str_radix<i8>("7f", 16u32)) == present(i8.MAX)) { panic("from_str_radix #1719") }
    if !(parsed(capture num.from_str_radix<i8>("1111111", 2u32)) == present(i8.MAX)) { panic("from_str_radix #1720") }
    if !(parsed(capture num.from_str_radix<i8>("3j", 36u32)) == present(i8.MAX)) { panic("from_str_radix #1721") }
    if !(parsed(capture num.from_str_radix<i8>("7F", 16u32)) == present(i8.MAX)) { panic("from_str_radix #1722") }
    if !(parsed(capture num.from_str_radix<i8>("-128", 10u32)) == present(i8.MIN)) { panic("from_str_radix #1723") }
    if !(parsed(capture num.from_str_radix<i8>("-80", 16u32)) == present(i8.MIN)) { panic("from_str_radix #1724") }
    if !(parsed(capture num.from_str_radix<i8>("-10000000", 2u32)) == present(i8.MIN)) { panic("from_str_radix #1725") }
    if !(parsed(capture num.from_str_radix<i8>("-3k", 36u32)) == present(i8.MIN)) { panic("from_str_radix #1726") }
    if !(parsed(capture num.from_str_radix<i8>("7", 10u32)) == present(7i8)) { panic("from_str_radix #1728") }
    if !(parsed(capture num.from_str_radix<i8>("7", 16u32)) == present(7i8)) { panic("from_str_radix #1729") }
    if !(parsed(capture num.from_str_radix<i8>("111", 2u32)) == present(7i8)) { panic("from_str_radix #1730") }
    if !(parsed(capture num.from_str_radix<i8>("7", 36u32)) == present(7i8)) { panic("from_str_radix #1731") }
    if !(parsed(capture num.from_str_radix<i8>("0", 10u32)) == present(0i8)) { panic("from_str_radix #1733") }
    if !(parsed(capture num.from_str_radix<i8>("0", 16u32)) == present(0i8)) { panic("from_str_radix #1734") }
    if !(parsed(capture num.from_str_radix<i8>("0", 2u32)) == present(0i8)) { panic("from_str_radix #1735") }
    if !(parsed(capture num.from_str_radix<i8>("0", 36u32)) == present(0i8)) { panic("from_str_radix #1736") }
    if !(parsed(capture num.from_str_radix<i8>("-7", 10u32)) == present((-7i8))) { panic("from_str_radix #1738") }
    if !(parsed(capture num.from_str_radix<i8>("-7", 16u32)) == present((-7i8))) { panic("from_str_radix #1739") }
    if !(parsed(capture num.from_str_radix<i8>("-111", 2u32)) == present((-7i8))) { panic("from_str_radix #1740") }
    if !(parsed(capture num.from_str_radix<i8>("-7", 36u32)) == present((-7i8))) { panic("from_str_radix #1741") }
    if !(parsed(capture num.from_str_radix<i8>("+7", 10u32)) == present(7i8)) { panic("from_str_radix #1743") }
    if !(kind(capture num.from_str_radix<i8>("", 10u32)) == present(IntErrorKind.Empty)) { panic("from_str_radix #1744") }
    if !(kind(capture num.from_str_radix<i8>("-", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1745") }
    if !(kind(capture num.from_str_radix<i8>("+", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1746") }
    if !(kind(capture num.from_str_radix<i8>("1_0", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1747") }
    if !(kind(capture num.from_str_radix<i8>("12", 2u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1748") }
    if !(kind(capture num.from_str_radix<i8>(" 1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1749") }
    if !(kind(capture num.from_str_radix<i8>("128", 10u32)) == present(IntErrorKind.PosOverflow)) { panic("from_str_radix #1750") }
    if !(kind(capture num.from_str_radix<i8>("1", 37u32)) == present(IntErrorKind.InvalidRadix)) { panic("from_str_radix #1751") }
    if !(kind(capture num.from_str_radix<i8>("1", 1u32)) == present(IntErrorKind.InvalidRadix)) { panic("from_str_radix #1752") }
    if !(kind(capture num.from_str_radix<i8>("-129", 10u32)) == present(IntErrorKind.NegOverflow)) { panic("from_str_radix #1753") }
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
    0
}
