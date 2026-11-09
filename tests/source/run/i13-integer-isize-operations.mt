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
    if !(isize.BITS == 64u32) { panic("BITS #1") }
    if !(isize.MIN == -9223372036854775808isize) { panic("MIN #2") }
    if !(isize.MAX == 9223372036854775807isize) { panic("MAX #3") }
    if !(missing(isize.MAX.checked_add(1isize))) { panic("checked_add #4") }
    if !(isize.MAX.wrapping_add(1isize) == isize.MIN) { panic("wrapping_add #5") }
    if !(isize.MAX.overflowing_add(1isize).0 == isize.MIN && isize.MAX.overflowing_add(1isize).1 == true) { panic("overflowing_add #6") }
    if !(isize.MAX.saturating_add(1isize) == isize.MAX) { panic("saturating_add #7") }
    if !(isize.MAX.checked_sub(1isize) == present(9223372036854775806isize)) { panic("checked_sub #8") }
    if !(isize.MAX.wrapping_sub(1isize) == 9223372036854775806isize) { panic("wrapping_sub #9") }
    if !(isize.MAX.overflowing_sub(1isize).0 == 9223372036854775806isize && isize.MAX.overflowing_sub(1isize).1 == false) { panic("overflowing_sub #10") }
    if !(isize.MAX.saturating_sub(1isize) == 9223372036854775806isize) { panic("saturating_sub #11") }
    if !(isize.MAX.strict_sub(1isize) == 9223372036854775806isize) { panic("strict_sub #12") }
    if !(unsafe { isize.MAX.unchecked_sub(1isize) } == 9223372036854775806isize) { panic("unchecked_sub #13") }
    if !(isize.MAX.checked_mul(1isize) == present(isize.MAX)) { panic("checked_mul #14") }
    if !(isize.MAX.wrapping_mul(1isize) == isize.MAX) { panic("wrapping_mul #15") }
    if !(isize.MAX.overflowing_mul(1isize).0 == isize.MAX && isize.MAX.overflowing_mul(1isize).1 == false) { panic("overflowing_mul #16") }
    if !(isize.MAX.saturating_mul(1isize) == isize.MAX) { panic("saturating_mul #17") }
    if !(isize.MAX.strict_mul(1isize) == isize.MAX) { panic("strict_mul #18") }
    if !(unsafe { isize.MAX.unchecked_mul(1isize) } == isize.MAX) { panic("unchecked_mul #19") }
    if !(isize.MAX.checked_div(1isize) == present(isize.MAX)) { panic("checked_div #20") }
    if !(isize.MAX.wrapping_div(1isize) == isize.MAX) { panic("wrapping_div #21") }
    if !(isize.MAX.overflowing_div(1isize).0 == isize.MAX && isize.MAX.overflowing_div(1isize).1 == false) { panic("overflowing_div #22") }
    if !(isize.MAX.strict_div(1isize) == isize.MAX) { panic("strict_div #23") }
    if !(isize.MAX.saturating_div(1isize) == isize.MAX) { panic("saturating_div #24") }
    if !(isize.MAX.checked_rem(1isize) == present(0isize)) { panic("checked_rem #25") }
    if !(isize.MAX.wrapping_rem(1isize) == 0isize) { panic("wrapping_rem #26") }
    if !(isize.MAX.overflowing_rem(1isize).0 == 0isize && isize.MAX.overflowing_rem(1isize).1 == false) { panic("overflowing_rem #27") }
    if !(isize.MAX.strict_rem(1isize) == 0isize) { panic("strict_rem #28") }
    if !(isize.MAX.checked_div_euclid(1isize) == present(isize.MAX)) { panic("checked_div_euclid #29") }
    if !(isize.MAX.wrapping_div_euclid(1isize) == isize.MAX) { panic("wrapping_div_euclid #30") }
    if !(isize.MAX.overflowing_div_euclid(1isize).0 == isize.MAX && isize.MAX.overflowing_div_euclid(1isize).1 == false) { panic("overflowing_div_euclid #31") }
    if !(isize.MAX.strict_div_euclid(1isize) == isize.MAX) { panic("strict_div_euclid #32") }
    if !(isize.MAX.div_euclid(1isize) == isize.MAX) { panic("div_euclid #33") }
    if !(isize.MAX.checked_rem_euclid(1isize) == present(0isize)) { panic("checked_rem_euclid #34") }
    if !(isize.MAX.wrapping_rem_euclid(1isize) == 0isize) { panic("wrapping_rem_euclid #35") }
    if !(isize.MAX.overflowing_rem_euclid(1isize).0 == 0isize && isize.MAX.overflowing_rem_euclid(1isize).1 == false) { panic("overflowing_rem_euclid #36") }
    if !(isize.MAX.strict_rem_euclid(1isize) == 0isize) { panic("strict_rem_euclid #37") }
    if !(isize.MAX.rem_euclid(1isize) == 0isize) { panic("rem_euclid #38") }
    if !(isize.MAX.abs_diff(1isize) == 9223372036854775806usize) { panic("abs_diff #39") }
    if !(isize.MAX.midpoint(1isize) == 4611686018427387904isize) { panic("midpoint #40") }
    if !(isize.MIN.checked_add(1isize) == present((-9223372036854775807isize))) { panic("checked_add #41") }
    if !(isize.MIN.wrapping_add(1isize) == (-9223372036854775807isize)) { panic("wrapping_add #42") }
    if !(isize.MIN.overflowing_add(1isize).0 == (-9223372036854775807isize) && isize.MIN.overflowing_add(1isize).1 == false) { panic("overflowing_add #43") }
    if !(isize.MIN.saturating_add(1isize) == (-9223372036854775807isize)) { panic("saturating_add #44") }
    if !(isize.MIN.strict_add(1isize) == (-9223372036854775807isize)) { panic("strict_add #45") }
    if !(unsafe { isize.MIN.unchecked_add(1isize) } == (-9223372036854775807isize)) { panic("unchecked_add #46") }
    if !(missing(isize.MIN.checked_sub(1isize))) { panic("checked_sub #47") }
    if !(isize.MIN.wrapping_sub(1isize) == isize.MAX) { panic("wrapping_sub #48") }
    if !(isize.MIN.overflowing_sub(1isize).0 == isize.MAX && isize.MIN.overflowing_sub(1isize).1 == true) { panic("overflowing_sub #49") }
    if !(isize.MIN.saturating_sub(1isize) == isize.MIN) { panic("saturating_sub #50") }
    if !(isize.MIN.checked_mul(1isize) == present(isize.MIN)) { panic("checked_mul #51") }
    if !(isize.MIN.wrapping_mul(1isize) == isize.MIN) { panic("wrapping_mul #52") }
    if !(isize.MIN.overflowing_mul(1isize).0 == isize.MIN && isize.MIN.overflowing_mul(1isize).1 == false) { panic("overflowing_mul #53") }
    if !(isize.MIN.saturating_mul(1isize) == isize.MIN) { panic("saturating_mul #54") }
    if !(isize.MIN.strict_mul(1isize) == isize.MIN) { panic("strict_mul #55") }
    if !(unsafe { isize.MIN.unchecked_mul(1isize) } == isize.MIN) { panic("unchecked_mul #56") }
    if !(isize.MIN.checked_div(1isize) == present(isize.MIN)) { panic("checked_div #57") }
    if !(isize.MIN.wrapping_div(1isize) == isize.MIN) { panic("wrapping_div #58") }
    if !(isize.MIN.overflowing_div(1isize).0 == isize.MIN && isize.MIN.overflowing_div(1isize).1 == false) { panic("overflowing_div #59") }
    if !(isize.MIN.strict_div(1isize) == isize.MIN) { panic("strict_div #60") }
    if !(isize.MIN.saturating_div(1isize) == isize.MIN) { panic("saturating_div #61") }
    if !(isize.MIN.checked_rem(1isize) == present(0isize)) { panic("checked_rem #62") }
    if !(isize.MIN.wrapping_rem(1isize) == 0isize) { panic("wrapping_rem #63") }
    if !(isize.MIN.overflowing_rem(1isize).0 == 0isize && isize.MIN.overflowing_rem(1isize).1 == false) { panic("overflowing_rem #64") }
    if !(isize.MIN.strict_rem(1isize) == 0isize) { panic("strict_rem #65") }
    if !(isize.MIN.checked_div_euclid(1isize) == present(isize.MIN)) { panic("checked_div_euclid #66") }
    if !(isize.MIN.wrapping_div_euclid(1isize) == isize.MIN) { panic("wrapping_div_euclid #67") }
    if !(isize.MIN.overflowing_div_euclid(1isize).0 == isize.MIN && isize.MIN.overflowing_div_euclid(1isize).1 == false) { panic("overflowing_div_euclid #68") }
    if !(isize.MIN.strict_div_euclid(1isize) == isize.MIN) { panic("strict_div_euclid #69") }
    if !(isize.MIN.div_euclid(1isize) == isize.MIN) { panic("div_euclid #70") }
    if !(isize.MIN.checked_rem_euclid(1isize) == present(0isize)) { panic("checked_rem_euclid #71") }
    if !(isize.MIN.wrapping_rem_euclid(1isize) == 0isize) { panic("wrapping_rem_euclid #72") }
    if !(isize.MIN.overflowing_rem_euclid(1isize).0 == 0isize && isize.MIN.overflowing_rem_euclid(1isize).1 == false) { panic("overflowing_rem_euclid #73") }
    if !(isize.MIN.strict_rem_euclid(1isize) == 0isize) { panic("strict_rem_euclid #74") }
    if !(isize.MIN.rem_euclid(1isize) == 0isize) { panic("rem_euclid #75") }
    if !(isize.MIN.abs_diff(1isize) == 9223372036854775809usize) { panic("abs_diff #76") }
    if !(isize.MIN.midpoint(1isize) == (-4611686018427387903isize)) { panic("midpoint #77") }
    if !(1000isize.checked_add(7isize) == present(1007isize)) { panic("checked_add #78") }
    if !(1000isize.wrapping_add(7isize) == 1007isize) { panic("wrapping_add #79") }
    if !(1000isize.overflowing_add(7isize).0 == 1007isize && 1000isize.overflowing_add(7isize).1 == false) { panic("overflowing_add #80") }
    if !(1000isize.saturating_add(7isize) == 1007isize) { panic("saturating_add #81") }
    if !(1000isize.strict_add(7isize) == 1007isize) { panic("strict_add #82") }
    if !(unsafe { 1000isize.unchecked_add(7isize) } == 1007isize) { panic("unchecked_add #83") }
    if !(1000isize.checked_sub(7isize) == present(993isize)) { panic("checked_sub #84") }
    if !(1000isize.wrapping_sub(7isize) == 993isize) { panic("wrapping_sub #85") }
    if !(1000isize.overflowing_sub(7isize).0 == 993isize && 1000isize.overflowing_sub(7isize).1 == false) { panic("overflowing_sub #86") }
    if !(1000isize.saturating_sub(7isize) == 993isize) { panic("saturating_sub #87") }
    if !(1000isize.strict_sub(7isize) == 993isize) { panic("strict_sub #88") }
    if !(unsafe { 1000isize.unchecked_sub(7isize) } == 993isize) { panic("unchecked_sub #89") }
    if !(1000isize.checked_mul(7isize) == present(7000isize)) { panic("checked_mul #90") }
    if !(1000isize.wrapping_mul(7isize) == 7000isize) { panic("wrapping_mul #91") }
    if !(1000isize.overflowing_mul(7isize).0 == 7000isize && 1000isize.overflowing_mul(7isize).1 == false) { panic("overflowing_mul #92") }
    if !(1000isize.saturating_mul(7isize) == 7000isize) { panic("saturating_mul #93") }
    if !(1000isize.strict_mul(7isize) == 7000isize) { panic("strict_mul #94") }
    if !(unsafe { 1000isize.unchecked_mul(7isize) } == 7000isize) { panic("unchecked_mul #95") }
    if !(1000isize.checked_div(7isize) == present(142isize)) { panic("checked_div #96") }
    if !(1000isize.wrapping_div(7isize) == 142isize) { panic("wrapping_div #97") }
    if !(1000isize.overflowing_div(7isize).0 == 142isize && 1000isize.overflowing_div(7isize).1 == false) { panic("overflowing_div #98") }
    if !(1000isize.strict_div(7isize) == 142isize) { panic("strict_div #99") }
    if !(1000isize.saturating_div(7isize) == 142isize) { panic("saturating_div #100") }
    if !(1000isize.checked_rem(7isize) == present(6isize)) { panic("checked_rem #101") }
    if !(1000isize.wrapping_rem(7isize) == 6isize) { panic("wrapping_rem #102") }
    if !(1000isize.overflowing_rem(7isize).0 == 6isize && 1000isize.overflowing_rem(7isize).1 == false) { panic("overflowing_rem #103") }
    if !(1000isize.strict_rem(7isize) == 6isize) { panic("strict_rem #104") }
    if !(1000isize.checked_div_euclid(7isize) == present(142isize)) { panic("checked_div_euclid #105") }
    if !(1000isize.wrapping_div_euclid(7isize) == 142isize) { panic("wrapping_div_euclid #106") }
    if !(1000isize.overflowing_div_euclid(7isize).0 == 142isize && 1000isize.overflowing_div_euclid(7isize).1 == false) { panic("overflowing_div_euclid #107") }
    if !(1000isize.strict_div_euclid(7isize) == 142isize) { panic("strict_div_euclid #108") }
    if !(1000isize.div_euclid(7isize) == 142isize) { panic("div_euclid #109") }
    if !(1000isize.checked_rem_euclid(7isize) == present(6isize)) { panic("checked_rem_euclid #110") }
    if !(1000isize.wrapping_rem_euclid(7isize) == 6isize) { panic("wrapping_rem_euclid #111") }
    if !(1000isize.overflowing_rem_euclid(7isize).0 == 6isize && 1000isize.overflowing_rem_euclid(7isize).1 == false) { panic("overflowing_rem_euclid #112") }
    if !(1000isize.strict_rem_euclid(7isize) == 6isize) { panic("strict_rem_euclid #113") }
    if !(1000isize.rem_euclid(7isize) == 6isize) { panic("rem_euclid #114") }
    if !(1000isize.abs_diff(7isize) == 993usize) { panic("abs_diff #115") }
    if !(1000isize.midpoint(7isize) == 503isize) { panic("midpoint #116") }
    if !(7isize.checked_add(1000isize) == present(1007isize)) { panic("checked_add #117") }
    if !(7isize.wrapping_add(1000isize) == 1007isize) { panic("wrapping_add #118") }
    if !(7isize.overflowing_add(1000isize).0 == 1007isize && 7isize.overflowing_add(1000isize).1 == false) { panic("overflowing_add #119") }
    if !(7isize.saturating_add(1000isize) == 1007isize) { panic("saturating_add #120") }
}

fn group1() {
    if !(7isize.strict_add(1000isize) == 1007isize) { panic("strict_add #121") }
    if !(unsafe { 7isize.unchecked_add(1000isize) } == 1007isize) { panic("unchecked_add #122") }
    if !(7isize.checked_sub(1000isize) == present((-993isize))) { panic("checked_sub #123") }
    if !(7isize.wrapping_sub(1000isize) == (-993isize)) { panic("wrapping_sub #124") }
    if !(7isize.overflowing_sub(1000isize).0 == (-993isize) && 7isize.overflowing_sub(1000isize).1 == false) { panic("overflowing_sub #125") }
    if !(7isize.saturating_sub(1000isize) == (-993isize)) { panic("saturating_sub #126") }
    if !(7isize.strict_sub(1000isize) == (-993isize)) { panic("strict_sub #127") }
    if !(unsafe { 7isize.unchecked_sub(1000isize) } == (-993isize)) { panic("unchecked_sub #128") }
    if !(7isize.checked_mul(1000isize) == present(7000isize)) { panic("checked_mul #129") }
    if !(7isize.wrapping_mul(1000isize) == 7000isize) { panic("wrapping_mul #130") }
    if !(7isize.overflowing_mul(1000isize).0 == 7000isize && 7isize.overflowing_mul(1000isize).1 == false) { panic("overflowing_mul #131") }
    if !(7isize.saturating_mul(1000isize) == 7000isize) { panic("saturating_mul #132") }
    if !(7isize.strict_mul(1000isize) == 7000isize) { panic("strict_mul #133") }
    if !(unsafe { 7isize.unchecked_mul(1000isize) } == 7000isize) { panic("unchecked_mul #134") }
    if !(7isize.checked_div(1000isize) == present(0isize)) { panic("checked_div #135") }
    if !(7isize.wrapping_div(1000isize) == 0isize) { panic("wrapping_div #136") }
    if !(7isize.overflowing_div(1000isize).0 == 0isize && 7isize.overflowing_div(1000isize).1 == false) { panic("overflowing_div #137") }
    if !(7isize.strict_div(1000isize) == 0isize) { panic("strict_div #138") }
    if !(7isize.saturating_div(1000isize) == 0isize) { panic("saturating_div #139") }
    if !(7isize.checked_rem(1000isize) == present(7isize)) { panic("checked_rem #140") }
    if !(7isize.wrapping_rem(1000isize) == 7isize) { panic("wrapping_rem #141") }
    if !(7isize.overflowing_rem(1000isize).0 == 7isize && 7isize.overflowing_rem(1000isize).1 == false) { panic("overflowing_rem #142") }
    if !(7isize.strict_rem(1000isize) == 7isize) { panic("strict_rem #143") }
    if !(7isize.checked_div_euclid(1000isize) == present(0isize)) { panic("checked_div_euclid #144") }
    if !(7isize.wrapping_div_euclid(1000isize) == 0isize) { panic("wrapping_div_euclid #145") }
    if !(7isize.overflowing_div_euclid(1000isize).0 == 0isize && 7isize.overflowing_div_euclid(1000isize).1 == false) { panic("overflowing_div_euclid #146") }
    if !(7isize.strict_div_euclid(1000isize) == 0isize) { panic("strict_div_euclid #147") }
    if !(7isize.div_euclid(1000isize) == 0isize) { panic("div_euclid #148") }
    if !(7isize.checked_rem_euclid(1000isize) == present(7isize)) { panic("checked_rem_euclid #149") }
    if !(7isize.wrapping_rem_euclid(1000isize) == 7isize) { panic("wrapping_rem_euclid #150") }
    if !(7isize.overflowing_rem_euclid(1000isize).0 == 7isize && 7isize.overflowing_rem_euclid(1000isize).1 == false) { panic("overflowing_rem_euclid #151") }
    if !(7isize.strict_rem_euclid(1000isize) == 7isize) { panic("strict_rem_euclid #152") }
    if !(7isize.rem_euclid(1000isize) == 7isize) { panic("rem_euclid #153") }
    if !(7isize.abs_diff(1000isize) == 993usize) { panic("abs_diff #154") }
    if !(7isize.midpoint(1000isize) == 503isize) { panic("midpoint #155") }
    if !(missing(isize.MAX.checked_add(2isize))) { panic("checked_add #156") }
    if !(isize.MAX.wrapping_add(2isize) == (-9223372036854775807isize)) { panic("wrapping_add #157") }
    if !(isize.MAX.overflowing_add(2isize).0 == (-9223372036854775807isize) && isize.MAX.overflowing_add(2isize).1 == true) { panic("overflowing_add #158") }
    if !(isize.MAX.saturating_add(2isize) == isize.MAX) { panic("saturating_add #159") }
    if !(isize.MAX.checked_sub(2isize) == present(9223372036854775805isize)) { panic("checked_sub #160") }
    if !(isize.MAX.wrapping_sub(2isize) == 9223372036854775805isize) { panic("wrapping_sub #161") }
    if !(isize.MAX.overflowing_sub(2isize).0 == 9223372036854775805isize && isize.MAX.overflowing_sub(2isize).1 == false) { panic("overflowing_sub #162") }
    if !(isize.MAX.saturating_sub(2isize) == 9223372036854775805isize) { panic("saturating_sub #163") }
    if !(isize.MAX.strict_sub(2isize) == 9223372036854775805isize) { panic("strict_sub #164") }
    if !(unsafe { isize.MAX.unchecked_sub(2isize) } == 9223372036854775805isize) { panic("unchecked_sub #165") }
    if !(missing(isize.MAX.checked_mul(2isize))) { panic("checked_mul #166") }
    if !(isize.MAX.wrapping_mul(2isize) == (-2isize)) { panic("wrapping_mul #167") }
    if !(isize.MAX.overflowing_mul(2isize).0 == (-2isize) && isize.MAX.overflowing_mul(2isize).1 == true) { panic("overflowing_mul #168") }
    if !(isize.MAX.saturating_mul(2isize) == isize.MAX) { panic("saturating_mul #169") }
    if !(isize.MAX.checked_div(2isize) == present(4611686018427387903isize)) { panic("checked_div #170") }
    if !(isize.MAX.wrapping_div(2isize) == 4611686018427387903isize) { panic("wrapping_div #171") }
    if !(isize.MAX.overflowing_div(2isize).0 == 4611686018427387903isize && isize.MAX.overflowing_div(2isize).1 == false) { panic("overflowing_div #172") }
    if !(isize.MAX.strict_div(2isize) == 4611686018427387903isize) { panic("strict_div #173") }
    if !(isize.MAX.saturating_div(2isize) == 4611686018427387903isize) { panic("saturating_div #174") }
    if !(isize.MAX.checked_rem(2isize) == present(1isize)) { panic("checked_rem #175") }
    if !(isize.MAX.wrapping_rem(2isize) == 1isize) { panic("wrapping_rem #176") }
    if !(isize.MAX.overflowing_rem(2isize).0 == 1isize && isize.MAX.overflowing_rem(2isize).1 == false) { panic("overflowing_rem #177") }
    if !(isize.MAX.strict_rem(2isize) == 1isize) { panic("strict_rem #178") }
    if !(isize.MAX.checked_div_euclid(2isize) == present(4611686018427387903isize)) { panic("checked_div_euclid #179") }
    if !(isize.MAX.wrapping_div_euclid(2isize) == 4611686018427387903isize) { panic("wrapping_div_euclid #180") }
    if !(isize.MAX.overflowing_div_euclid(2isize).0 == 4611686018427387903isize && isize.MAX.overflowing_div_euclid(2isize).1 == false) { panic("overflowing_div_euclid #181") }
    if !(isize.MAX.strict_div_euclid(2isize) == 4611686018427387903isize) { panic("strict_div_euclid #182") }
    if !(isize.MAX.div_euclid(2isize) == 4611686018427387903isize) { panic("div_euclid #183") }
    if !(isize.MAX.checked_rem_euclid(2isize) == present(1isize)) { panic("checked_rem_euclid #184") }
    if !(isize.MAX.wrapping_rem_euclid(2isize) == 1isize) { panic("wrapping_rem_euclid #185") }
    if !(isize.MAX.overflowing_rem_euclid(2isize).0 == 1isize && isize.MAX.overflowing_rem_euclid(2isize).1 == false) { panic("overflowing_rem_euclid #186") }
    if !(isize.MAX.strict_rem_euclid(2isize) == 1isize) { panic("strict_rem_euclid #187") }
    if !(isize.MAX.rem_euclid(2isize) == 1isize) { panic("rem_euclid #188") }
    if !(isize.MAX.abs_diff(2isize) == 9223372036854775805usize) { panic("abs_diff #189") }
    if !(isize.MAX.midpoint(2isize) == 4611686018427387904isize) { panic("midpoint #190") }
    if !(0isize.checked_add(0isize) == present(0isize)) { panic("checked_add #191") }
    if !(0isize.wrapping_add(0isize) == 0isize) { panic("wrapping_add #192") }
    if !(0isize.overflowing_add(0isize).0 == 0isize && 0isize.overflowing_add(0isize).1 == false) { panic("overflowing_add #193") }
    if !(0isize.saturating_add(0isize) == 0isize) { panic("saturating_add #194") }
    if !(0isize.strict_add(0isize) == 0isize) { panic("strict_add #195") }
    if !(unsafe { 0isize.unchecked_add(0isize) } == 0isize) { panic("unchecked_add #196") }
    if !(0isize.checked_sub(0isize) == present(0isize)) { panic("checked_sub #197") }
    if !(0isize.wrapping_sub(0isize) == 0isize) { panic("wrapping_sub #198") }
    if !(0isize.overflowing_sub(0isize).0 == 0isize && 0isize.overflowing_sub(0isize).1 == false) { panic("overflowing_sub #199") }
    if !(0isize.saturating_sub(0isize) == 0isize) { panic("saturating_sub #200") }
    if !(0isize.strict_sub(0isize) == 0isize) { panic("strict_sub #201") }
    if !(unsafe { 0isize.unchecked_sub(0isize) } == 0isize) { panic("unchecked_sub #202") }
    if !(0isize.checked_mul(0isize) == present(0isize)) { panic("checked_mul #203") }
    if !(0isize.wrapping_mul(0isize) == 0isize) { panic("wrapping_mul #204") }
    if !(0isize.overflowing_mul(0isize).0 == 0isize && 0isize.overflowing_mul(0isize).1 == false) { panic("overflowing_mul #205") }
    if !(0isize.saturating_mul(0isize) == 0isize) { panic("saturating_mul #206") }
    if !(0isize.strict_mul(0isize) == 0isize) { panic("strict_mul #207") }
    if !(unsafe { 0isize.unchecked_mul(0isize) } == 0isize) { panic("unchecked_mul #208") }
    if !(missing(0isize.checked_div(0isize))) { panic("checked_div #209") }
    if !(missing(0isize.checked_rem(0isize))) { panic("checked_rem #210") }
    if !(missing(0isize.checked_div_euclid(0isize))) { panic("checked_div_euclid #211") }
    if !(missing(0isize.checked_rem_euclid(0isize))) { panic("checked_rem_euclid #212") }
    if !(0isize.abs_diff(0isize) == 0usize) { panic("abs_diff #213") }
    if !(0isize.midpoint(0isize) == 0isize) { panic("midpoint #214") }
    if !(missing(isize.MAX.checked_add(isize.MAX))) { panic("checked_add #215") }
    if !(isize.MAX.wrapping_add(isize.MAX) == (-2isize)) { panic("wrapping_add #216") }
    if !(isize.MAX.overflowing_add(isize.MAX).0 == (-2isize) && isize.MAX.overflowing_add(isize.MAX).1 == true) { panic("overflowing_add #217") }
    if !(isize.MAX.saturating_add(isize.MAX) == isize.MAX) { panic("saturating_add #218") }
    if !(isize.MAX.checked_sub(isize.MAX) == present(0isize)) { panic("checked_sub #219") }
    if !(isize.MAX.wrapping_sub(isize.MAX) == 0isize) { panic("wrapping_sub #220") }
    if !(isize.MAX.overflowing_sub(isize.MAX).0 == 0isize && isize.MAX.overflowing_sub(isize.MAX).1 == false) { panic("overflowing_sub #221") }
    if !(isize.MAX.saturating_sub(isize.MAX) == 0isize) { panic("saturating_sub #222") }
    if !(isize.MAX.strict_sub(isize.MAX) == 0isize) { panic("strict_sub #223") }
    if !(unsafe { isize.MAX.unchecked_sub(isize.MAX) } == 0isize) { panic("unchecked_sub #224") }
    if !(missing(isize.MAX.checked_mul(isize.MAX))) { panic("checked_mul #225") }
    if !(isize.MAX.wrapping_mul(isize.MAX) == 1isize) { panic("wrapping_mul #226") }
    if !(isize.MAX.overflowing_mul(isize.MAX).0 == 1isize && isize.MAX.overflowing_mul(isize.MAX).1 == true) { panic("overflowing_mul #227") }
    if !(isize.MAX.saturating_mul(isize.MAX) == isize.MAX) { panic("saturating_mul #228") }
    if !(isize.MAX.checked_div(isize.MAX) == present(1isize)) { panic("checked_div #229") }
    if !(isize.MAX.wrapping_div(isize.MAX) == 1isize) { panic("wrapping_div #230") }
    if !(isize.MAX.overflowing_div(isize.MAX).0 == 1isize && isize.MAX.overflowing_div(isize.MAX).1 == false) { panic("overflowing_div #231") }
    if !(isize.MAX.strict_div(isize.MAX) == 1isize) { panic("strict_div #232") }
    if !(isize.MAX.saturating_div(isize.MAX) == 1isize) { panic("saturating_div #233") }
    if !(isize.MAX.checked_rem(isize.MAX) == present(0isize)) { panic("checked_rem #234") }
    if !(isize.MAX.wrapping_rem(isize.MAX) == 0isize) { panic("wrapping_rem #235") }
    if !(isize.MAX.overflowing_rem(isize.MAX).0 == 0isize && isize.MAX.overflowing_rem(isize.MAX).1 == false) { panic("overflowing_rem #236") }
    if !(isize.MAX.strict_rem(isize.MAX) == 0isize) { panic("strict_rem #237") }
    if !(isize.MAX.checked_div_euclid(isize.MAX) == present(1isize)) { panic("checked_div_euclid #238") }
    if !(isize.MAX.wrapping_div_euclid(isize.MAX) == 1isize) { panic("wrapping_div_euclid #239") }
    if !(isize.MAX.overflowing_div_euclid(isize.MAX).0 == 1isize && isize.MAX.overflowing_div_euclid(isize.MAX).1 == false) { panic("overflowing_div_euclid #240") }
}

fn group2() {
    if !(isize.MAX.strict_div_euclid(isize.MAX) == 1isize) { panic("strict_div_euclid #241") }
    if !(isize.MAX.div_euclid(isize.MAX) == 1isize) { panic("div_euclid #242") }
    if !(isize.MAX.checked_rem_euclid(isize.MAX) == present(0isize)) { panic("checked_rem_euclid #243") }
    if !(isize.MAX.wrapping_rem_euclid(isize.MAX) == 0isize) { panic("wrapping_rem_euclid #244") }
    if !(isize.MAX.overflowing_rem_euclid(isize.MAX).0 == 0isize && isize.MAX.overflowing_rem_euclid(isize.MAX).1 == false) { panic("overflowing_rem_euclid #245") }
    if !(isize.MAX.strict_rem_euclid(isize.MAX) == 0isize) { panic("strict_rem_euclid #246") }
    if !(isize.MAX.rem_euclid(isize.MAX) == 0isize) { panic("rem_euclid #247") }
    if !(isize.MAX.abs_diff(isize.MAX) == 0usize) { panic("abs_diff #248") }
    if !(isize.MAX.midpoint(isize.MAX) == isize.MAX) { panic("midpoint #249") }
    if !(missing(isize.MIN.checked_add((-1isize)))) { panic("checked_add #250") }
    if !(isize.MIN.wrapping_add((-1isize)) == isize.MAX) { panic("wrapping_add #251") }
    if !(isize.MIN.overflowing_add((-1isize)).0 == isize.MAX && isize.MIN.overflowing_add((-1isize)).1 == true) { panic("overflowing_add #252") }
    if !(isize.MIN.saturating_add((-1isize)) == isize.MIN) { panic("saturating_add #253") }
    if !(isize.MIN.checked_sub((-1isize)) == present((-9223372036854775807isize))) { panic("checked_sub #254") }
    if !(isize.MIN.wrapping_sub((-1isize)) == (-9223372036854775807isize)) { panic("wrapping_sub #255") }
    if !(isize.MIN.overflowing_sub((-1isize)).0 == (-9223372036854775807isize) && isize.MIN.overflowing_sub((-1isize)).1 == false) { panic("overflowing_sub #256") }
    if !(isize.MIN.saturating_sub((-1isize)) == (-9223372036854775807isize)) { panic("saturating_sub #257") }
    if !(isize.MIN.strict_sub((-1isize)) == (-9223372036854775807isize)) { panic("strict_sub #258") }
    if !(unsafe { isize.MIN.unchecked_sub((-1isize)) } == (-9223372036854775807isize)) { panic("unchecked_sub #259") }
    if !(missing(isize.MIN.checked_mul((-1isize)))) { panic("checked_mul #260") }
    if !(isize.MIN.wrapping_mul((-1isize)) == isize.MIN) { panic("wrapping_mul #261") }
    if !(isize.MIN.overflowing_mul((-1isize)).0 == isize.MIN && isize.MIN.overflowing_mul((-1isize)).1 == true) { panic("overflowing_mul #262") }
    if !(isize.MIN.saturating_mul((-1isize)) == isize.MAX) { panic("saturating_mul #263") }
    if !(missing(isize.MIN.checked_div((-1isize)))) { panic("checked_div #264") }
    if !(isize.MIN.wrapping_div((-1isize)) == isize.MIN) { panic("wrapping_div #265") }
    if !(isize.MIN.overflowing_div((-1isize)).0 == isize.MIN && isize.MIN.overflowing_div((-1isize)).1 == true) { panic("overflowing_div #266") }
    if !(isize.MIN.saturating_div((-1isize)) == isize.MAX) { panic("saturating_div #267") }
    if !(missing(isize.MIN.checked_rem((-1isize)))) { panic("checked_rem #268") }
    if !(isize.MIN.wrapping_rem((-1isize)) == 0isize) { panic("wrapping_rem #269") }
    if !(isize.MIN.overflowing_rem((-1isize)).0 == 0isize && isize.MIN.overflowing_rem((-1isize)).1 == true) { panic("overflowing_rem #270") }
    if !(missing(isize.MIN.checked_div_euclid((-1isize)))) { panic("checked_div_euclid #271") }
    if !(isize.MIN.wrapping_div_euclid((-1isize)) == isize.MIN) { panic("wrapping_div_euclid #272") }
    if !(isize.MIN.overflowing_div_euclid((-1isize)).0 == isize.MIN && isize.MIN.overflowing_div_euclid((-1isize)).1 == true) { panic("overflowing_div_euclid #273") }
    if !(missing(isize.MIN.checked_rem_euclid((-1isize)))) { panic("checked_rem_euclid #274") }
    if !(isize.MIN.wrapping_rem_euclid((-1isize)) == 0isize) { panic("wrapping_rem_euclid #275") }
    if !(isize.MIN.overflowing_rem_euclid((-1isize)).0 == 0isize && isize.MIN.overflowing_rem_euclid((-1isize)).1 == true) { panic("overflowing_rem_euclid #276") }
    if !(isize.MIN.abs_diff((-1isize)) == 9223372036854775807usize) { panic("abs_diff #277") }
    if !(isize.MIN.midpoint((-1isize)) == (-4611686018427387904isize)) { panic("midpoint #278") }
    if !((-7isize).checked_add(3isize) == present((-4isize))) { panic("checked_add #279") }
    if !((-7isize).wrapping_add(3isize) == (-4isize)) { panic("wrapping_add #280") }
    if !((-7isize).overflowing_add(3isize).0 == (-4isize) && (-7isize).overflowing_add(3isize).1 == false) { panic("overflowing_add #281") }
    if !((-7isize).saturating_add(3isize) == (-4isize)) { panic("saturating_add #282") }
    if !((-7isize).strict_add(3isize) == (-4isize)) { panic("strict_add #283") }
    if !(unsafe { (-7isize).unchecked_add(3isize) } == (-4isize)) { panic("unchecked_add #284") }
    if !((-7isize).checked_sub(3isize) == present((-10isize))) { panic("checked_sub #285") }
    if !((-7isize).wrapping_sub(3isize) == (-10isize)) { panic("wrapping_sub #286") }
    if !((-7isize).overflowing_sub(3isize).0 == (-10isize) && (-7isize).overflowing_sub(3isize).1 == false) { panic("overflowing_sub #287") }
    if !((-7isize).saturating_sub(3isize) == (-10isize)) { panic("saturating_sub #288") }
    if !((-7isize).strict_sub(3isize) == (-10isize)) { panic("strict_sub #289") }
    if !(unsafe { (-7isize).unchecked_sub(3isize) } == (-10isize)) { panic("unchecked_sub #290") }
    if !((-7isize).checked_mul(3isize) == present((-21isize))) { panic("checked_mul #291") }
    if !((-7isize).wrapping_mul(3isize) == (-21isize)) { panic("wrapping_mul #292") }
    if !((-7isize).overflowing_mul(3isize).0 == (-21isize) && (-7isize).overflowing_mul(3isize).1 == false) { panic("overflowing_mul #293") }
    if !((-7isize).saturating_mul(3isize) == (-21isize)) { panic("saturating_mul #294") }
    if !((-7isize).strict_mul(3isize) == (-21isize)) { panic("strict_mul #295") }
    if !(unsafe { (-7isize).unchecked_mul(3isize) } == (-21isize)) { panic("unchecked_mul #296") }
    if !((-7isize).checked_div(3isize) == present((-2isize))) { panic("checked_div #297") }
    if !((-7isize).wrapping_div(3isize) == (-2isize)) { panic("wrapping_div #298") }
    if !((-7isize).overflowing_div(3isize).0 == (-2isize) && (-7isize).overflowing_div(3isize).1 == false) { panic("overflowing_div #299") }
    if !((-7isize).strict_div(3isize) == (-2isize)) { panic("strict_div #300") }
    if !((-7isize).saturating_div(3isize) == (-2isize)) { panic("saturating_div #301") }
    if !((-7isize).checked_rem(3isize) == present((-1isize))) { panic("checked_rem #302") }
    if !((-7isize).wrapping_rem(3isize) == (-1isize)) { panic("wrapping_rem #303") }
    if !((-7isize).overflowing_rem(3isize).0 == (-1isize) && (-7isize).overflowing_rem(3isize).1 == false) { panic("overflowing_rem #304") }
    if !((-7isize).strict_rem(3isize) == (-1isize)) { panic("strict_rem #305") }
    if !((-7isize).checked_div_euclid(3isize) == present((-3isize))) { panic("checked_div_euclid #306") }
    if !((-7isize).wrapping_div_euclid(3isize) == (-3isize)) { panic("wrapping_div_euclid #307") }
    if !((-7isize).overflowing_div_euclid(3isize).0 == (-3isize) && (-7isize).overflowing_div_euclid(3isize).1 == false) { panic("overflowing_div_euclid #308") }
    if !((-7isize).strict_div_euclid(3isize) == (-3isize)) { panic("strict_div_euclid #309") }
    if !((-7isize).div_euclid(3isize) == (-3isize)) { panic("div_euclid #310") }
    if !((-7isize).checked_rem_euclid(3isize) == present(2isize)) { panic("checked_rem_euclid #311") }
    if !((-7isize).wrapping_rem_euclid(3isize) == 2isize) { panic("wrapping_rem_euclid #312") }
    if !((-7isize).overflowing_rem_euclid(3isize).0 == 2isize && (-7isize).overflowing_rem_euclid(3isize).1 == false) { panic("overflowing_rem_euclid #313") }
    if !((-7isize).strict_rem_euclid(3isize) == 2isize) { panic("strict_rem_euclid #314") }
    if !((-7isize).rem_euclid(3isize) == 2isize) { panic("rem_euclid #315") }
    if !((-7isize).abs_diff(3isize) == 10usize) { panic("abs_diff #316") }
    if !((-7isize).midpoint(3isize) == (-2isize)) { panic("midpoint #317") }
    if !(7isize.checked_add((-3isize)) == present(4isize)) { panic("checked_add #318") }
    if !(7isize.wrapping_add((-3isize)) == 4isize) { panic("wrapping_add #319") }
    if !(7isize.overflowing_add((-3isize)).0 == 4isize && 7isize.overflowing_add((-3isize)).1 == false) { panic("overflowing_add #320") }
    if !(7isize.saturating_add((-3isize)) == 4isize) { panic("saturating_add #321") }
    if !(7isize.strict_add((-3isize)) == 4isize) { panic("strict_add #322") }
    if !(unsafe { 7isize.unchecked_add((-3isize)) } == 4isize) { panic("unchecked_add #323") }
    if !(7isize.checked_sub((-3isize)) == present(10isize)) { panic("checked_sub #324") }
    if !(7isize.wrapping_sub((-3isize)) == 10isize) { panic("wrapping_sub #325") }
    if !(7isize.overflowing_sub((-3isize)).0 == 10isize && 7isize.overflowing_sub((-3isize)).1 == false) { panic("overflowing_sub #326") }
    if !(7isize.saturating_sub((-3isize)) == 10isize) { panic("saturating_sub #327") }
    if !(7isize.strict_sub((-3isize)) == 10isize) { panic("strict_sub #328") }
    if !(unsafe { 7isize.unchecked_sub((-3isize)) } == 10isize) { panic("unchecked_sub #329") }
    if !(7isize.checked_mul((-3isize)) == present((-21isize))) { panic("checked_mul #330") }
    if !(7isize.wrapping_mul((-3isize)) == (-21isize)) { panic("wrapping_mul #331") }
    if !(7isize.overflowing_mul((-3isize)).0 == (-21isize) && 7isize.overflowing_mul((-3isize)).1 == false) { panic("overflowing_mul #332") }
    if !(7isize.saturating_mul((-3isize)) == (-21isize)) { panic("saturating_mul #333") }
    if !(7isize.strict_mul((-3isize)) == (-21isize)) { panic("strict_mul #334") }
    if !(unsafe { 7isize.unchecked_mul((-3isize)) } == (-21isize)) { panic("unchecked_mul #335") }
    if !(7isize.checked_div((-3isize)) == present((-2isize))) { panic("checked_div #336") }
    if !(7isize.wrapping_div((-3isize)) == (-2isize)) { panic("wrapping_div #337") }
    if !(7isize.overflowing_div((-3isize)).0 == (-2isize) && 7isize.overflowing_div((-3isize)).1 == false) { panic("overflowing_div #338") }
    if !(7isize.strict_div((-3isize)) == (-2isize)) { panic("strict_div #339") }
    if !(7isize.saturating_div((-3isize)) == (-2isize)) { panic("saturating_div #340") }
    if !(7isize.checked_rem((-3isize)) == present(1isize)) { panic("checked_rem #341") }
    if !(7isize.wrapping_rem((-3isize)) == 1isize) { panic("wrapping_rem #342") }
    if !(7isize.overflowing_rem((-3isize)).0 == 1isize && 7isize.overflowing_rem((-3isize)).1 == false) { panic("overflowing_rem #343") }
    if !(7isize.strict_rem((-3isize)) == 1isize) { panic("strict_rem #344") }
    if !(7isize.checked_div_euclid((-3isize)) == present((-2isize))) { panic("checked_div_euclid #345") }
    if !(7isize.wrapping_div_euclid((-3isize)) == (-2isize)) { panic("wrapping_div_euclid #346") }
    if !(7isize.overflowing_div_euclid((-3isize)).0 == (-2isize) && 7isize.overflowing_div_euclid((-3isize)).1 == false) { panic("overflowing_div_euclid #347") }
    if !(7isize.strict_div_euclid((-3isize)) == (-2isize)) { panic("strict_div_euclid #348") }
    if !(7isize.div_euclid((-3isize)) == (-2isize)) { panic("div_euclid #349") }
    if !(7isize.checked_rem_euclid((-3isize)) == present(1isize)) { panic("checked_rem_euclid #350") }
    if !(7isize.wrapping_rem_euclid((-3isize)) == 1isize) { panic("wrapping_rem_euclid #351") }
    if !(7isize.overflowing_rem_euclid((-3isize)).0 == 1isize && 7isize.overflowing_rem_euclid((-3isize)).1 == false) { panic("overflowing_rem_euclid #352") }
    if !(7isize.strict_rem_euclid((-3isize)) == 1isize) { panic("strict_rem_euclid #353") }
    if !(7isize.rem_euclid((-3isize)) == 1isize) { panic("rem_euclid #354") }
    if !(7isize.abs_diff((-3isize)) == 10usize) { panic("abs_diff #355") }
    if !(7isize.midpoint((-3isize)) == 2isize) { panic("midpoint #356") }
    if !((-7isize).checked_add((-3isize)) == present((-10isize))) { panic("checked_add #357") }
    if !((-7isize).wrapping_add((-3isize)) == (-10isize)) { panic("wrapping_add #358") }
    if !((-7isize).overflowing_add((-3isize)).0 == (-10isize) && (-7isize).overflowing_add((-3isize)).1 == false) { panic("overflowing_add #359") }
    if !((-7isize).saturating_add((-3isize)) == (-10isize)) { panic("saturating_add #360") }
}

fn group3() {
    if !((-7isize).strict_add((-3isize)) == (-10isize)) { panic("strict_add #361") }
    if !(unsafe { (-7isize).unchecked_add((-3isize)) } == (-10isize)) { panic("unchecked_add #362") }
    if !((-7isize).checked_sub((-3isize)) == present((-4isize))) { panic("checked_sub #363") }
    if !((-7isize).wrapping_sub((-3isize)) == (-4isize)) { panic("wrapping_sub #364") }
    if !((-7isize).overflowing_sub((-3isize)).0 == (-4isize) && (-7isize).overflowing_sub((-3isize)).1 == false) { panic("overflowing_sub #365") }
    if !((-7isize).saturating_sub((-3isize)) == (-4isize)) { panic("saturating_sub #366") }
    if !((-7isize).strict_sub((-3isize)) == (-4isize)) { panic("strict_sub #367") }
    if !(unsafe { (-7isize).unchecked_sub((-3isize)) } == (-4isize)) { panic("unchecked_sub #368") }
    if !((-7isize).checked_mul((-3isize)) == present(21isize)) { panic("checked_mul #369") }
    if !((-7isize).wrapping_mul((-3isize)) == 21isize) { panic("wrapping_mul #370") }
    if !((-7isize).overflowing_mul((-3isize)).0 == 21isize && (-7isize).overflowing_mul((-3isize)).1 == false) { panic("overflowing_mul #371") }
    if !((-7isize).saturating_mul((-3isize)) == 21isize) { panic("saturating_mul #372") }
    if !((-7isize).strict_mul((-3isize)) == 21isize) { panic("strict_mul #373") }
    if !(unsafe { (-7isize).unchecked_mul((-3isize)) } == 21isize) { panic("unchecked_mul #374") }
    if !((-7isize).checked_div((-3isize)) == present(2isize)) { panic("checked_div #375") }
    if !((-7isize).wrapping_div((-3isize)) == 2isize) { panic("wrapping_div #376") }
    if !((-7isize).overflowing_div((-3isize)).0 == 2isize && (-7isize).overflowing_div((-3isize)).1 == false) { panic("overflowing_div #377") }
    if !((-7isize).strict_div((-3isize)) == 2isize) { panic("strict_div #378") }
    if !((-7isize).saturating_div((-3isize)) == 2isize) { panic("saturating_div #379") }
    if !((-7isize).checked_rem((-3isize)) == present((-1isize))) { panic("checked_rem #380") }
    if !((-7isize).wrapping_rem((-3isize)) == (-1isize)) { panic("wrapping_rem #381") }
    if !((-7isize).overflowing_rem((-3isize)).0 == (-1isize) && (-7isize).overflowing_rem((-3isize)).1 == false) { panic("overflowing_rem #382") }
    if !((-7isize).strict_rem((-3isize)) == (-1isize)) { panic("strict_rem #383") }
    if !((-7isize).checked_div_euclid((-3isize)) == present(3isize)) { panic("checked_div_euclid #384") }
    if !((-7isize).wrapping_div_euclid((-3isize)) == 3isize) { panic("wrapping_div_euclid #385") }
    if !((-7isize).overflowing_div_euclid((-3isize)).0 == 3isize && (-7isize).overflowing_div_euclid((-3isize)).1 == false) { panic("overflowing_div_euclid #386") }
    if !((-7isize).strict_div_euclid((-3isize)) == 3isize) { panic("strict_div_euclid #387") }
    if !((-7isize).div_euclid((-3isize)) == 3isize) { panic("div_euclid #388") }
    if !((-7isize).checked_rem_euclid((-3isize)) == present(2isize)) { panic("checked_rem_euclid #389") }
    if !((-7isize).wrapping_rem_euclid((-3isize)) == 2isize) { panic("wrapping_rem_euclid #390") }
    if !((-7isize).overflowing_rem_euclid((-3isize)).0 == 2isize && (-7isize).overflowing_rem_euclid((-3isize)).1 == false) { panic("overflowing_rem_euclid #391") }
    if !((-7isize).strict_rem_euclid((-3isize)) == 2isize) { panic("strict_rem_euclid #392") }
    if !((-7isize).rem_euclid((-3isize)) == 2isize) { panic("rem_euclid #393") }
    if !((-7isize).abs_diff((-3isize)) == 4usize) { panic("abs_diff #394") }
    if !((-7isize).midpoint((-3isize)) == (-5isize)) { panic("midpoint #395") }
    if !(missing(isize.MIN.checked_add(isize.MIN))) { panic("checked_add #396") }
    if !(isize.MIN.wrapping_add(isize.MIN) == 0isize) { panic("wrapping_add #397") }
    if !(isize.MIN.overflowing_add(isize.MIN).0 == 0isize && isize.MIN.overflowing_add(isize.MIN).1 == true) { panic("overflowing_add #398") }
    if !(isize.MIN.saturating_add(isize.MIN) == isize.MIN) { panic("saturating_add #399") }
    if !(isize.MIN.checked_sub(isize.MIN) == present(0isize)) { panic("checked_sub #400") }
    if !(isize.MIN.wrapping_sub(isize.MIN) == 0isize) { panic("wrapping_sub #401") }
    if !(isize.MIN.overflowing_sub(isize.MIN).0 == 0isize && isize.MIN.overflowing_sub(isize.MIN).1 == false) { panic("overflowing_sub #402") }
    if !(isize.MIN.saturating_sub(isize.MIN) == 0isize) { panic("saturating_sub #403") }
    if !(isize.MIN.strict_sub(isize.MIN) == 0isize) { panic("strict_sub #404") }
    if !(unsafe { isize.MIN.unchecked_sub(isize.MIN) } == 0isize) { panic("unchecked_sub #405") }
    if !(missing(isize.MIN.checked_mul(isize.MIN))) { panic("checked_mul #406") }
    if !(isize.MIN.wrapping_mul(isize.MIN) == 0isize) { panic("wrapping_mul #407") }
    if !(isize.MIN.overflowing_mul(isize.MIN).0 == 0isize && isize.MIN.overflowing_mul(isize.MIN).1 == true) { panic("overflowing_mul #408") }
    if !(isize.MIN.saturating_mul(isize.MIN) == isize.MAX) { panic("saturating_mul #409") }
    if !(isize.MIN.checked_div(isize.MIN) == present(1isize)) { panic("checked_div #410") }
    if !(isize.MIN.wrapping_div(isize.MIN) == 1isize) { panic("wrapping_div #411") }
    if !(isize.MIN.overflowing_div(isize.MIN).0 == 1isize && isize.MIN.overflowing_div(isize.MIN).1 == false) { panic("overflowing_div #412") }
    if !(isize.MIN.strict_div(isize.MIN) == 1isize) { panic("strict_div #413") }
    if !(isize.MIN.saturating_div(isize.MIN) == 1isize) { panic("saturating_div #414") }
    if !(isize.MIN.checked_rem(isize.MIN) == present(0isize)) { panic("checked_rem #415") }
    if !(isize.MIN.wrapping_rem(isize.MIN) == 0isize) { panic("wrapping_rem #416") }
    if !(isize.MIN.overflowing_rem(isize.MIN).0 == 0isize && isize.MIN.overflowing_rem(isize.MIN).1 == false) { panic("overflowing_rem #417") }
    if !(isize.MIN.strict_rem(isize.MIN) == 0isize) { panic("strict_rem #418") }
    if !(isize.MIN.checked_div_euclid(isize.MIN) == present(1isize)) { panic("checked_div_euclid #419") }
    if !(isize.MIN.wrapping_div_euclid(isize.MIN) == 1isize) { panic("wrapping_div_euclid #420") }
    if !(isize.MIN.overflowing_div_euclid(isize.MIN).0 == 1isize && isize.MIN.overflowing_div_euclid(isize.MIN).1 == false) { panic("overflowing_div_euclid #421") }
    if !(isize.MIN.strict_div_euclid(isize.MIN) == 1isize) { panic("strict_div_euclid #422") }
    if !(isize.MIN.div_euclid(isize.MIN) == 1isize) { panic("div_euclid #423") }
    if !(isize.MIN.checked_rem_euclid(isize.MIN) == present(0isize)) { panic("checked_rem_euclid #424") }
    if !(isize.MIN.wrapping_rem_euclid(isize.MIN) == 0isize) { panic("wrapping_rem_euclid #425") }
    if !(isize.MIN.overflowing_rem_euclid(isize.MIN).0 == 0isize && isize.MIN.overflowing_rem_euclid(isize.MIN).1 == false) { panic("overflowing_rem_euclid #426") }
    if !(isize.MIN.strict_rem_euclid(isize.MIN) == 0isize) { panic("strict_rem_euclid #427") }
    if !(isize.MIN.rem_euclid(isize.MIN) == 0isize) { panic("rem_euclid #428") }
    if !(isize.MIN.abs_diff(isize.MIN) == 0usize) { panic("abs_diff #429") }
    if !(isize.MIN.midpoint(isize.MIN) == isize.MIN) { panic("midpoint #430") }
    if !(missing(isize.MAX.checked_add_unsigned(1usize))) { panic("checked_add_unsigned #431") }
    if !(isize.MAX.wrapping_add_unsigned(1usize) == isize.MIN) { panic("wrapping_add_unsigned #432") }
    if !(isize.MAX.overflowing_add_unsigned(1usize).0 == isize.MIN && isize.MAX.overflowing_add_unsigned(1usize).1 == true) { panic("overflowing_add_unsigned #433") }
    if !(isize.MAX.saturating_add_unsigned(1usize) == isize.MAX) { panic("saturating_add_unsigned #434") }
    if !(isize.MAX.checked_sub_unsigned(1usize) == present(9223372036854775806isize)) { panic("checked_sub_unsigned #435") }
    if !(isize.MAX.wrapping_sub_unsigned(1usize) == 9223372036854775806isize) { panic("wrapping_sub_unsigned #436") }
    if !(isize.MAX.overflowing_sub_unsigned(1usize).0 == 9223372036854775806isize && isize.MAX.overflowing_sub_unsigned(1usize).1 == false) { panic("overflowing_sub_unsigned #437") }
    if !(isize.MAX.saturating_sub_unsigned(1usize) == 9223372036854775806isize) { panic("saturating_sub_unsigned #438") }
    if !(isize.MAX.strict_sub_unsigned(1usize) == 9223372036854775806isize) { panic("strict_sub_unsigned #439") }
    if !(isize.MIN.checked_add_unsigned(usize.MAX) == present(isize.MAX)) { panic("checked_add_unsigned #440") }
    if !(isize.MIN.wrapping_add_unsigned(usize.MAX) == isize.MAX) { panic("wrapping_add_unsigned #441") }
    if !(isize.MIN.overflowing_add_unsigned(usize.MAX).0 == isize.MAX && isize.MIN.overflowing_add_unsigned(usize.MAX).1 == false) { panic("overflowing_add_unsigned #442") }
    if !(isize.MIN.saturating_add_unsigned(usize.MAX) == isize.MAX) { panic("saturating_add_unsigned #443") }
    if !(isize.MIN.strict_add_unsigned(usize.MAX) == isize.MAX) { panic("strict_add_unsigned #444") }
    if !(missing(isize.MIN.checked_sub_unsigned(usize.MAX))) { panic("checked_sub_unsigned #445") }
    if !(isize.MIN.wrapping_sub_unsigned(usize.MAX) == (-9223372036854775807isize)) { panic("wrapping_sub_unsigned #446") }
    if !(isize.MIN.overflowing_sub_unsigned(usize.MAX).0 == (-9223372036854775807isize) && isize.MIN.overflowing_sub_unsigned(usize.MAX).1 == true) { panic("overflowing_sub_unsigned #447") }
    if !(isize.MIN.saturating_sub_unsigned(usize.MAX) == isize.MIN) { panic("saturating_sub_unsigned #448") }
    if !((-7isize).checked_add_unsigned(3usize) == present((-4isize))) { panic("checked_add_unsigned #449") }
    if !((-7isize).wrapping_add_unsigned(3usize) == (-4isize)) { panic("wrapping_add_unsigned #450") }
    if !((-7isize).overflowing_add_unsigned(3usize).0 == (-4isize) && (-7isize).overflowing_add_unsigned(3usize).1 == false) { panic("overflowing_add_unsigned #451") }
    if !((-7isize).saturating_add_unsigned(3usize) == (-4isize)) { panic("saturating_add_unsigned #452") }
    if !((-7isize).strict_add_unsigned(3usize) == (-4isize)) { panic("strict_add_unsigned #453") }
    if !((-7isize).checked_sub_unsigned(3usize) == present((-10isize))) { panic("checked_sub_unsigned #454") }
    if !((-7isize).wrapping_sub_unsigned(3usize) == (-10isize)) { panic("wrapping_sub_unsigned #455") }
    if !((-7isize).overflowing_sub_unsigned(3usize).0 == (-10isize) && (-7isize).overflowing_sub_unsigned(3usize).1 == false) { panic("overflowing_sub_unsigned #456") }
    if !((-7isize).saturating_sub_unsigned(3usize) == (-10isize)) { panic("saturating_sub_unsigned #457") }
    if !((-7isize).strict_sub_unsigned(3usize) == (-10isize)) { panic("strict_sub_unsigned #458") }
    if !(isize.MIN.checked_add_unsigned(0usize) == present(isize.MIN)) { panic("checked_add_unsigned #459") }
    if !(isize.MIN.wrapping_add_unsigned(0usize) == isize.MIN) { panic("wrapping_add_unsigned #460") }
    if !(isize.MIN.overflowing_add_unsigned(0usize).0 == isize.MIN && isize.MIN.overflowing_add_unsigned(0usize).1 == false) { panic("overflowing_add_unsigned #461") }
    if !(isize.MIN.saturating_add_unsigned(0usize) == isize.MIN) { panic("saturating_add_unsigned #462") }
    if !(isize.MIN.strict_add_unsigned(0usize) == isize.MIN) { panic("strict_add_unsigned #463") }
    if !(isize.MIN.checked_sub_unsigned(0usize) == present(isize.MIN)) { panic("checked_sub_unsigned #464") }
    if !(isize.MIN.wrapping_sub_unsigned(0usize) == isize.MIN) { panic("wrapping_sub_unsigned #465") }
    if !(isize.MIN.overflowing_sub_unsigned(0usize).0 == isize.MIN && isize.MIN.overflowing_sub_unsigned(0usize).1 == false) { panic("overflowing_sub_unsigned #466") }
    if !(isize.MIN.saturating_sub_unsigned(0usize) == isize.MIN) { panic("saturating_sub_unsigned #467") }
    if !(isize.MIN.strict_sub_unsigned(0usize) == isize.MIN) { panic("strict_sub_unsigned #468") }
    if !(missing((-1isize).checked_add_unsigned(usize.MAX))) { panic("checked_add_unsigned #469") }
    if !((-1isize).wrapping_add_unsigned(usize.MAX) == (-2isize)) { panic("wrapping_add_unsigned #470") }
    if !((-1isize).overflowing_add_unsigned(usize.MAX).0 == (-2isize) && (-1isize).overflowing_add_unsigned(usize.MAX).1 == true) { panic("overflowing_add_unsigned #471") }
    if !((-1isize).saturating_add_unsigned(usize.MAX) == isize.MAX) { panic("saturating_add_unsigned #472") }
    if !(missing((-1isize).checked_sub_unsigned(usize.MAX))) { panic("checked_sub_unsigned #473") }
    if !((-1isize).wrapping_sub_unsigned(usize.MAX) == 0isize) { panic("wrapping_sub_unsigned #474") }
    if !((-1isize).overflowing_sub_unsigned(usize.MAX).0 == 0isize && (-1isize).overflowing_sub_unsigned(usize.MAX).1 == true) { panic("overflowing_sub_unsigned #475") }
    if !((-1isize).saturating_sub_unsigned(usize.MAX) == isize.MIN) { panic("saturating_sub_unsigned #476") }
    if !(isize.MAX.checked_neg() == present((-9223372036854775807isize))) { panic("checked_neg #477") }
    if !(isize.MAX.wrapping_neg() == (-9223372036854775807isize)) { panic("wrapping_neg #478") }
    if !(isize.MAX.overflowing_neg().0 == (-9223372036854775807isize) && isize.MAX.overflowing_neg().1 == false) { panic("overflowing_neg #479") }
    if !(isize.MAX.strict_neg() == (-9223372036854775807isize)) { panic("strict_neg #480") }
}

fn group4() {
    if !(unsafe { isize.MAX.unchecked_neg() } == (-9223372036854775807isize)) { panic("unchecked_neg #481") }
    if !(isize.MAX.saturating_neg() == (-9223372036854775807isize)) { panic("saturating_neg #482") }
    if !(isize.MAX.checked_abs() == present(isize.MAX)) { panic("checked_abs #483") }
    if !(isize.MAX.wrapping_abs() == isize.MAX) { panic("wrapping_abs #484") }
    if !(isize.MAX.overflowing_abs().0 == isize.MAX && isize.MAX.overflowing_abs().1 == false) { panic("overflowing_abs #485") }
    if !(isize.MAX.saturating_abs() == isize.MAX) { panic("saturating_abs #486") }
    if !(isize.MAX.strict_abs() == isize.MAX) { panic("strict_abs #487") }
    if !(isize.MAX.abs() == isize.MAX) { panic("abs #488") }
    if !(isize.MAX.unsigned_abs() == 9223372036854775807usize) { panic("unsigned_abs #489") }
    if !(isize.MAX.signum() == 1isize) { panic("signum #490") }
    if !(isize.MAX.is_positive() == true) { panic("is_positive #491") }
    if !(isize.MAX.is_negative() == false) { panic("is_negative #492") }
    if !(isize.MAX.cast_unsigned() == 9223372036854775807usize) { panic("cast_unsigned #493") }
    if !(isize.MAX.count_ones() == 63u32) { panic("count_ones #494") }
    if !(isize.MAX.count_zeros() == 1u32) { panic("count_zeros #495") }
    if !(isize.MAX.leading_zeros() == 1u32) { panic("leading_zeros #496") }
    if !(isize.MAX.trailing_zeros() == 0u32) { panic("trailing_zeros #497") }
    if !(isize.MAX.leading_ones() == 0u32) { panic("leading_ones #498") }
    if !(isize.MAX.trailing_ones() == 63u32) { panic("trailing_ones #499") }
    if !(isize.MAX.reverse_bits() == (-2isize)) { panic("reverse_bits #500") }
    if !(isize.MAX.swap_bytes() == (-129isize)) { panic("swap_bytes #501") }
    if !(isize.MAX.to_be() == (-129isize)) { panic("to_be #502") }
    if !(isize.MAX.to_le() == isize.MAX) { panic("to_le #503") }
    if !(isize.from_be(isize.MAX) == (-129isize)) { panic("from_be #504") }
    if !(isize.from_le(isize.MAX) == isize.MAX) { panic("from_le #505") }
    if !(isize.MAX.to_le_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 127u8]) { panic("to_le_bytes #506") }
    if !(isize.MAX.to_be_bytes() == [127u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_be_bytes #507") }
    if !(isize.MAX.to_ne_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 127u8]) { panic("to_ne_bytes #508") }
    if !(isize.from_le_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 127u8]) == isize.MAX) { panic("from_le_bytes #509") }
    if !(isize.from_be_bytes([127u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == isize.MAX) { panic("from_be_bytes #510") }
    if !(isize.from_ne_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 127u8]) == isize.MAX) { panic("from_ne_bytes #511") }
    if !(isize.MAX.rotate_left(0u32) == isize.MAX) { panic("rotate_left #512") }
    if !(isize.MAX.rotate_right(0u32) == isize.MAX) { panic("rotate_right #513") }
    if !(isize.MAX.checked_shl(0u32) == present(isize.MAX)) { panic("checked_shl #514") }
    if !(isize.MAX.checked_shr(0u32) == present(isize.MAX)) { panic("checked_shr #515") }
    if !(isize.MAX.wrapping_shl(0u32) == isize.MAX) { panic("wrapping_shl #516") }
    if !(isize.MAX.wrapping_shr(0u32) == isize.MAX) { panic("wrapping_shr #517") }
    if !(isize.MAX.overflowing_shl(0u32).0 == isize.MAX && isize.MAX.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #518") }
    if !(isize.MAX.overflowing_shr(0u32).0 == isize.MAX && isize.MAX.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #519") }
    if !(isize.MAX.unbounded_shl(0u32) == isize.MAX) { panic("unbounded_shl #520") }
    if !(isize.MAX.unbounded_shr(0u32) == isize.MAX) { panic("unbounded_shr #521") }
    if !(isize.MAX.strict_shl(0u32) == isize.MAX) { panic("strict_shl #522") }
    if !(isize.MAX.strict_shr(0u32) == isize.MAX) { panic("strict_shr #523") }
    if !(unsafe { isize.MAX.unchecked_shl(0u32) } == isize.MAX) { panic("unchecked_shl #524") }
    if !(unsafe { isize.MAX.unchecked_shr(0u32) } == isize.MAX) { panic("unchecked_shr #525") }
    if !(isize.MAX.rotate_left(1u32) == (-2isize)) { panic("rotate_left #526") }
    if !(isize.MAX.rotate_right(1u32) == (-4611686018427387905isize)) { panic("rotate_right #527") }
    if !(isize.MAX.checked_shl(1u32) == present((-2isize))) { panic("checked_shl #528") }
    if !(isize.MAX.checked_shr(1u32) == present(4611686018427387903isize)) { panic("checked_shr #529") }
    if !(isize.MAX.wrapping_shl(1u32) == (-2isize)) { panic("wrapping_shl #530") }
    if !(isize.MAX.wrapping_shr(1u32) == 4611686018427387903isize) { panic("wrapping_shr #531") }
    if !(isize.MAX.overflowing_shl(1u32).0 == (-2isize) && isize.MAX.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #532") }
    if !(isize.MAX.overflowing_shr(1u32).0 == 4611686018427387903isize && isize.MAX.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #533") }
    if !(isize.MAX.unbounded_shl(1u32) == (-2isize)) { panic("unbounded_shl #534") }
    if !(isize.MAX.unbounded_shr(1u32) == 4611686018427387903isize) { panic("unbounded_shr #535") }
    if !(isize.MAX.strict_shl(1u32) == (-2isize)) { panic("strict_shl #536") }
    if !(isize.MAX.strict_shr(1u32) == 4611686018427387903isize) { panic("strict_shr #537") }
    if !(unsafe { isize.MAX.unchecked_shl(1u32) } == (-2isize)) { panic("unchecked_shl #538") }
    if !(unsafe { isize.MAX.unchecked_shr(1u32) } == 4611686018427387903isize) { panic("unchecked_shr #539") }
    if !(isize.MAX.rotate_left(3u32) == (-5isize)) { panic("rotate_left #540") }
    if !(isize.MAX.rotate_right(3u32) == (-1152921504606846977isize)) { panic("rotate_right #541") }
    if !(isize.MAX.checked_shl(3u32) == present((-8isize))) { panic("checked_shl #542") }
    if !(isize.MAX.checked_shr(3u32) == present(1152921504606846975isize)) { panic("checked_shr #543") }
    if !(isize.MAX.wrapping_shl(3u32) == (-8isize)) { panic("wrapping_shl #544") }
    if !(isize.MAX.wrapping_shr(3u32) == 1152921504606846975isize) { panic("wrapping_shr #545") }
    if !(isize.MAX.overflowing_shl(3u32).0 == (-8isize) && isize.MAX.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #546") }
    if !(isize.MAX.overflowing_shr(3u32).0 == 1152921504606846975isize && isize.MAX.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #547") }
    if !(isize.MAX.unbounded_shl(3u32) == (-8isize)) { panic("unbounded_shl #548") }
    if !(isize.MAX.unbounded_shr(3u32) == 1152921504606846975isize) { panic("unbounded_shr #549") }
    if !(isize.MAX.strict_shl(3u32) == (-8isize)) { panic("strict_shl #550") }
    if !(isize.MAX.strict_shr(3u32) == 1152921504606846975isize) { panic("strict_shr #551") }
    if !(unsafe { isize.MAX.unchecked_shl(3u32) } == (-8isize)) { panic("unchecked_shl #552") }
    if !(unsafe { isize.MAX.unchecked_shr(3u32) } == 1152921504606846975isize) { panic("unchecked_shr #553") }
    if !(isize.MAX.rotate_left(63u32) == (-4611686018427387905isize)) { panic("rotate_left #554") }
    if !(isize.MAX.rotate_right(63u32) == (-2isize)) { panic("rotate_right #555") }
    if !(isize.MAX.checked_shl(63u32) == present(isize.MIN)) { panic("checked_shl #556") }
    if !(isize.MAX.checked_shr(63u32) == present(0isize)) { panic("checked_shr #557") }
    if !(isize.MAX.wrapping_shl(63u32) == isize.MIN) { panic("wrapping_shl #558") }
    if !(isize.MAX.wrapping_shr(63u32) == 0isize) { panic("wrapping_shr #559") }
    if !(isize.MAX.overflowing_shl(63u32).0 == isize.MIN && isize.MAX.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #560") }
    if !(isize.MAX.overflowing_shr(63u32).0 == 0isize && isize.MAX.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #561") }
    if !(isize.MAX.unbounded_shl(63u32) == isize.MIN) { panic("unbounded_shl #562") }
    if !(isize.MAX.unbounded_shr(63u32) == 0isize) { panic("unbounded_shr #563") }
    if !(isize.MAX.strict_shl(63u32) == isize.MIN) { panic("strict_shl #564") }
    if !(isize.MAX.strict_shr(63u32) == 0isize) { panic("strict_shr #565") }
    if !(unsafe { isize.MAX.unchecked_shl(63u32) } == isize.MIN) { panic("unchecked_shl #566") }
    if !(unsafe { isize.MAX.unchecked_shr(63u32) } == 0isize) { panic("unchecked_shr #567") }
    if !(isize.MAX.rotate_left(64u32) == isize.MAX) { panic("rotate_left #568") }
    if !(isize.MAX.rotate_right(64u32) == isize.MAX) { panic("rotate_right #569") }
    if !(missing(isize.MAX.checked_shl(64u32))) { panic("checked_shl #570") }
    if !(missing(isize.MAX.checked_shr(64u32))) { panic("checked_shr #571") }
    if !(isize.MAX.wrapping_shl(64u32) == isize.MAX) { panic("wrapping_shl #572") }
    if !(isize.MAX.wrapping_shr(64u32) == isize.MAX) { panic("wrapping_shr #573") }
    if !(isize.MAX.overflowing_shl(64u32).0 == isize.MAX && isize.MAX.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #574") }
    if !(isize.MAX.overflowing_shr(64u32).0 == isize.MAX && isize.MAX.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #575") }
    if !(isize.MAX.unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #576") }
    if !(isize.MAX.unbounded_shr(64u32) == 0isize) { panic("unbounded_shr #577") }
    if !(isize.MAX.rotate_left(69u32) == (-17isize)) { panic("rotate_left #578") }
    if !(isize.MAX.rotate_right(69u32) == (-288230376151711745isize)) { panic("rotate_right #579") }
    if !(missing(isize.MAX.checked_shl(69u32))) { panic("checked_shl #580") }
    if !(missing(isize.MAX.checked_shr(69u32))) { panic("checked_shr #581") }
    if !(isize.MAX.wrapping_shl(69u32) == (-32isize)) { panic("wrapping_shl #582") }
    if !(isize.MAX.wrapping_shr(69u32) == 288230376151711743isize) { panic("wrapping_shr #583") }
    if !(isize.MAX.overflowing_shl(69u32).0 == (-32isize) && isize.MAX.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #584") }
    if !(isize.MAX.overflowing_shr(69u32).0 == 288230376151711743isize && isize.MAX.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #585") }
    if !(isize.MAX.unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #586") }
    if !(isize.MAX.unbounded_shr(69u32) == 0isize) { panic("unbounded_shr #587") }
    if !(isize.MAX.checked_pow(0u32) == present(1isize)) { panic("checked_pow #588") }
    if !(isize.MAX.wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #589") }
    if !(isize.MAX.overflowing_pow(0u32).0 == 1isize && isize.MAX.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #590") }
    if !(isize.MAX.saturating_pow(0u32) == 1isize) { panic("saturating_pow #591") }
    if !(isize.MAX.pow(0u32) == 1isize) { panic("pow #592") }
    if !(isize.MAX.strict_pow(0u32) == 1isize) { panic("strict_pow #593") }
    if !(isize.MAX.checked_pow(1u32) == present(isize.MAX)) { panic("checked_pow #594") }
    if !(isize.MAX.wrapping_pow(1u32) == isize.MAX) { panic("wrapping_pow #595") }
    if !(isize.MAX.overflowing_pow(1u32).0 == isize.MAX && isize.MAX.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #596") }
    if !(isize.MAX.saturating_pow(1u32) == isize.MAX) { panic("saturating_pow #597") }
    if !(isize.MAX.pow(1u32) == isize.MAX) { panic("pow #598") }
    if !(isize.MAX.strict_pow(1u32) == isize.MAX) { panic("strict_pow #599") }
    if !(missing(isize.MAX.checked_pow(2u32))) { panic("checked_pow #600") }
}

fn group5() {
    if !(isize.MAX.wrapping_pow(2u32) == 1isize) { panic("wrapping_pow #601") }
    if !(isize.MAX.overflowing_pow(2u32).0 == 1isize && isize.MAX.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #602") }
    if !(isize.MAX.saturating_pow(2u32) == isize.MAX) { panic("saturating_pow #603") }
    if !(missing(isize.MAX.checked_pow(3u32))) { panic("checked_pow #604") }
    if !(isize.MAX.wrapping_pow(3u32) == isize.MAX) { panic("wrapping_pow #605") }
    if !(isize.MAX.overflowing_pow(3u32).0 == isize.MAX && isize.MAX.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #606") }
    if !(isize.MAX.saturating_pow(3u32) == isize.MAX) { panic("saturating_pow #607") }
    if !(missing(isize.MAX.checked_pow(63u32))) { panic("checked_pow #608") }
    if !(isize.MAX.wrapping_pow(63u32) == isize.MAX) { panic("wrapping_pow #609") }
    if !(isize.MAX.overflowing_pow(63u32).0 == isize.MAX && isize.MAX.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #610") }
    if !(isize.MAX.saturating_pow(63u32) == isize.MAX) { panic("saturating_pow #611") }
    if !(missing(isize.MAX.checked_pow(64u32))) { panic("checked_pow #612") }
    if !(isize.MAX.wrapping_pow(64u32) == 1isize) { panic("wrapping_pow #613") }
    if !(isize.MAX.overflowing_pow(64u32).0 == 1isize && isize.MAX.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #614") }
    if !(isize.MAX.saturating_pow(64u32) == isize.MAX) { panic("saturating_pow #615") }
    if !(isize.MAX.ilog2() == 62u32) { panic("ilog2 #616") }
    if !(isize.MAX.ilog10() == 18u32) { panic("ilog10 #617") }
    if !(isize.MAX.checked_ilog2() == present(62u32)) { panic("checked_ilog2 #618") }
    if !(isize.MAX.checked_ilog10() == present(18u32)) { panic("checked_ilog10 #619") }
    if !(isize.MAX.ilog(2isize) == 62u32) { panic("ilog #620") }
    if !(isize.MAX.checked_ilog(2isize) == present(62u32)) { panic("checked_ilog #621") }
    if !(isize.MAX.ilog(3isize) == 39u32) { panic("ilog #622") }
    if !(isize.MAX.checked_ilog(3isize) == present(39u32)) { panic("checked_ilog #623") }
    if !(isize.MAX.ilog(7isize) == 22u32) { panic("ilog #624") }
    if !(isize.MAX.checked_ilog(7isize) == present(22u32)) { panic("checked_ilog #625") }
    if !(missing(isize.MAX.checked_ilog(1isize))) { panic("checked_ilog #626") }
    if !(isize.MAX.isqrt() == 3037000499isize) { panic("isqrt #627") }
    if !(isize.MAX.checked_isqrt() == present(3037000499isize)) { panic("checked_isqrt #628") }
    if !(isize.MAX.highest_one() == present(62u32)) { panic("highest_one #629") }
    if !(isize.MAX.lowest_one() == present(0u32)) { panic("lowest_one #630") }
    if !(isize.MAX.isolate_highest_one() == 4611686018427387904isize) { panic("isolate_highest_one #631") }
    if !(isize.MAX.isolate_lowest_one() == 1isize) { panic("isolate_lowest_one #632") }
    if !(missing(isize.MIN.checked_neg())) { panic("checked_neg #633") }
    if !(isize.MIN.wrapping_neg() == isize.MIN) { panic("wrapping_neg #634") }
    if !(isize.MIN.overflowing_neg().0 == isize.MIN && isize.MIN.overflowing_neg().1 == true) { panic("overflowing_neg #635") }
    if !(isize.MIN.saturating_neg() == isize.MAX) { panic("saturating_neg #636") }
    if !(missing(isize.MIN.checked_abs())) { panic("checked_abs #637") }
    if !(isize.MIN.wrapping_abs() == isize.MIN) { panic("wrapping_abs #638") }
    if !(isize.MIN.overflowing_abs().0 == isize.MIN && isize.MIN.overflowing_abs().1 == true) { panic("overflowing_abs #639") }
    if !(isize.MIN.saturating_abs() == isize.MAX) { panic("saturating_abs #640") }
    if !(isize.MIN.unsigned_abs() == 9223372036854775808usize) { panic("unsigned_abs #641") }
    if !(isize.MIN.signum() == (-1isize)) { panic("signum #642") }
    if !(isize.MIN.is_positive() == false) { panic("is_positive #643") }
    if !(isize.MIN.is_negative() == true) { panic("is_negative #644") }
    if !(isize.MIN.cast_unsigned() == 9223372036854775808usize) { panic("cast_unsigned #645") }
    if !(isize.MIN.count_ones() == 1u32) { panic("count_ones #646") }
    if !(isize.MIN.count_zeros() == 63u32) { panic("count_zeros #647") }
    if !(isize.MIN.leading_zeros() == 0u32) { panic("leading_zeros #648") }
    if !(isize.MIN.trailing_zeros() == 63u32) { panic("trailing_zeros #649") }
    if !(isize.MIN.leading_ones() == 1u32) { panic("leading_ones #650") }
    if !(isize.MIN.trailing_ones() == 0u32) { panic("trailing_ones #651") }
    if !(isize.MIN.reverse_bits() == 1isize) { panic("reverse_bits #652") }
    if !(isize.MIN.swap_bytes() == 128isize) { panic("swap_bytes #653") }
    if !(isize.MIN.to_be() == 128isize) { panic("to_be #654") }
    if !(isize.MIN.to_le() == isize.MIN) { panic("to_le #655") }
    if !(isize.from_be(isize.MIN) == 128isize) { panic("from_be #656") }
    if !(isize.from_le(isize.MIN) == isize.MIN) { panic("from_le #657") }
    if !(isize.MIN.to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) { panic("to_le_bytes #658") }
    if !(isize.MIN.to_be_bytes() == [128u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #659") }
    if !(isize.MIN.to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) { panic("to_ne_bytes #660") }
    if !(isize.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) == isize.MIN) { panic("from_le_bytes #661") }
    if !(isize.from_be_bytes([128u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == isize.MIN) { panic("from_be_bytes #662") }
    if !(isize.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) == isize.MIN) { panic("from_ne_bytes #663") }
    if !(isize.MIN.rotate_left(0u32) == isize.MIN) { panic("rotate_left #664") }
    if !(isize.MIN.rotate_right(0u32) == isize.MIN) { panic("rotate_right #665") }
    if !(isize.MIN.checked_shl(0u32) == present(isize.MIN)) { panic("checked_shl #666") }
    if !(isize.MIN.checked_shr(0u32) == present(isize.MIN)) { panic("checked_shr #667") }
    if !(isize.MIN.wrapping_shl(0u32) == isize.MIN) { panic("wrapping_shl #668") }
    if !(isize.MIN.wrapping_shr(0u32) == isize.MIN) { panic("wrapping_shr #669") }
    if !(isize.MIN.overflowing_shl(0u32).0 == isize.MIN && isize.MIN.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #670") }
    if !(isize.MIN.overflowing_shr(0u32).0 == isize.MIN && isize.MIN.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #671") }
    if !(isize.MIN.unbounded_shl(0u32) == isize.MIN) { panic("unbounded_shl #672") }
    if !(isize.MIN.unbounded_shr(0u32) == isize.MIN) { panic("unbounded_shr #673") }
    if !(isize.MIN.strict_shl(0u32) == isize.MIN) { panic("strict_shl #674") }
    if !(isize.MIN.strict_shr(0u32) == isize.MIN) { panic("strict_shr #675") }
    if !(unsafe { isize.MIN.unchecked_shl(0u32) } == isize.MIN) { panic("unchecked_shl #676") }
    if !(unsafe { isize.MIN.unchecked_shr(0u32) } == isize.MIN) { panic("unchecked_shr #677") }
    if !(isize.MIN.rotate_left(1u32) == 1isize) { panic("rotate_left #678") }
    if !(isize.MIN.rotate_right(1u32) == 4611686018427387904isize) { panic("rotate_right #679") }
    if !(isize.MIN.checked_shl(1u32) == present(0isize)) { panic("checked_shl #680") }
    if !(isize.MIN.checked_shr(1u32) == present((-4611686018427387904isize))) { panic("checked_shr #681") }
    if !(isize.MIN.wrapping_shl(1u32) == 0isize) { panic("wrapping_shl #682") }
    if !(isize.MIN.wrapping_shr(1u32) == (-4611686018427387904isize)) { panic("wrapping_shr #683") }
    if !(isize.MIN.overflowing_shl(1u32).0 == 0isize && isize.MIN.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #684") }
    if !(isize.MIN.overflowing_shr(1u32).0 == (-4611686018427387904isize) && isize.MIN.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #685") }
    if !(isize.MIN.unbounded_shl(1u32) == 0isize) { panic("unbounded_shl #686") }
    if !(isize.MIN.unbounded_shr(1u32) == (-4611686018427387904isize)) { panic("unbounded_shr #687") }
    if !(isize.MIN.strict_shl(1u32) == 0isize) { panic("strict_shl #688") }
    if !(isize.MIN.strict_shr(1u32) == (-4611686018427387904isize)) { panic("strict_shr #689") }
    if !(unsafe { isize.MIN.unchecked_shl(1u32) } == 0isize) { panic("unchecked_shl #690") }
    if !(unsafe { isize.MIN.unchecked_shr(1u32) } == (-4611686018427387904isize)) { panic("unchecked_shr #691") }
    if !(isize.MIN.rotate_left(3u32) == 4isize) { panic("rotate_left #692") }
    if !(isize.MIN.rotate_right(3u32) == 1152921504606846976isize) { panic("rotate_right #693") }
    if !(isize.MIN.checked_shl(3u32) == present(0isize)) { panic("checked_shl #694") }
    if !(isize.MIN.checked_shr(3u32) == present((-1152921504606846976isize))) { panic("checked_shr #695") }
    if !(isize.MIN.wrapping_shl(3u32) == 0isize) { panic("wrapping_shl #696") }
    if !(isize.MIN.wrapping_shr(3u32) == (-1152921504606846976isize)) { panic("wrapping_shr #697") }
    if !(isize.MIN.overflowing_shl(3u32).0 == 0isize && isize.MIN.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #698") }
    if !(isize.MIN.overflowing_shr(3u32).0 == (-1152921504606846976isize) && isize.MIN.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #699") }
    if !(isize.MIN.unbounded_shl(3u32) == 0isize) { panic("unbounded_shl #700") }
    if !(isize.MIN.unbounded_shr(3u32) == (-1152921504606846976isize)) { panic("unbounded_shr #701") }
    if !(isize.MIN.strict_shl(3u32) == 0isize) { panic("strict_shl #702") }
    if !(isize.MIN.strict_shr(3u32) == (-1152921504606846976isize)) { panic("strict_shr #703") }
    if !(unsafe { isize.MIN.unchecked_shl(3u32) } == 0isize) { panic("unchecked_shl #704") }
    if !(unsafe { isize.MIN.unchecked_shr(3u32) } == (-1152921504606846976isize)) { panic("unchecked_shr #705") }
    if !(isize.MIN.rotate_left(63u32) == 4611686018427387904isize) { panic("rotate_left #706") }
    if !(isize.MIN.rotate_right(63u32) == 1isize) { panic("rotate_right #707") }
    if !(isize.MIN.checked_shl(63u32) == present(0isize)) { panic("checked_shl #708") }
    if !(isize.MIN.checked_shr(63u32) == present((-1isize))) { panic("checked_shr #709") }
    if !(isize.MIN.wrapping_shl(63u32) == 0isize) { panic("wrapping_shl #710") }
    if !(isize.MIN.wrapping_shr(63u32) == (-1isize)) { panic("wrapping_shr #711") }
    if !(isize.MIN.overflowing_shl(63u32).0 == 0isize && isize.MIN.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #712") }
    if !(isize.MIN.overflowing_shr(63u32).0 == (-1isize) && isize.MIN.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #713") }
    if !(isize.MIN.unbounded_shl(63u32) == 0isize) { panic("unbounded_shl #714") }
    if !(isize.MIN.unbounded_shr(63u32) == (-1isize)) { panic("unbounded_shr #715") }
    if !(isize.MIN.strict_shl(63u32) == 0isize) { panic("strict_shl #716") }
    if !(isize.MIN.strict_shr(63u32) == (-1isize)) { panic("strict_shr #717") }
    if !(unsafe { isize.MIN.unchecked_shl(63u32) } == 0isize) { panic("unchecked_shl #718") }
    if !(unsafe { isize.MIN.unchecked_shr(63u32) } == (-1isize)) { panic("unchecked_shr #719") }
    if !(isize.MIN.rotate_left(64u32) == isize.MIN) { panic("rotate_left #720") }
}

fn group6() {
    if !(isize.MIN.rotate_right(64u32) == isize.MIN) { panic("rotate_right #721") }
    if !(missing(isize.MIN.checked_shl(64u32))) { panic("checked_shl #722") }
    if !(missing(isize.MIN.checked_shr(64u32))) { panic("checked_shr #723") }
    if !(isize.MIN.wrapping_shl(64u32) == isize.MIN) { panic("wrapping_shl #724") }
    if !(isize.MIN.wrapping_shr(64u32) == isize.MIN) { panic("wrapping_shr #725") }
    if !(isize.MIN.overflowing_shl(64u32).0 == isize.MIN && isize.MIN.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #726") }
    if !(isize.MIN.overflowing_shr(64u32).0 == isize.MIN && isize.MIN.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #727") }
    if !(isize.MIN.unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #728") }
    if !(isize.MIN.unbounded_shr(64u32) == (-1isize)) { panic("unbounded_shr #729") }
    if !(isize.MIN.rotate_left(69u32) == 16isize) { panic("rotate_left #730") }
    if !(isize.MIN.rotate_right(69u32) == 288230376151711744isize) { panic("rotate_right #731") }
    if !(missing(isize.MIN.checked_shl(69u32))) { panic("checked_shl #732") }
    if !(missing(isize.MIN.checked_shr(69u32))) { panic("checked_shr #733") }
    if !(isize.MIN.wrapping_shl(69u32) == 0isize) { panic("wrapping_shl #734") }
    if !(isize.MIN.wrapping_shr(69u32) == (-288230376151711744isize)) { panic("wrapping_shr #735") }
    if !(isize.MIN.overflowing_shl(69u32).0 == 0isize && isize.MIN.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #736") }
    if !(isize.MIN.overflowing_shr(69u32).0 == (-288230376151711744isize) && isize.MIN.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #737") }
    if !(isize.MIN.unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #738") }
    if !(isize.MIN.unbounded_shr(69u32) == (-1isize)) { panic("unbounded_shr #739") }
    if !(isize.MIN.checked_pow(0u32) == present(1isize)) { panic("checked_pow #740") }
    if !(isize.MIN.wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #741") }
    if !(isize.MIN.overflowing_pow(0u32).0 == 1isize && isize.MIN.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #742") }
    if !(isize.MIN.saturating_pow(0u32) == 1isize) { panic("saturating_pow #743") }
    if !(isize.MIN.pow(0u32) == 1isize) { panic("pow #744") }
    if !(isize.MIN.strict_pow(0u32) == 1isize) { panic("strict_pow #745") }
    if !(isize.MIN.checked_pow(1u32) == present(isize.MIN)) { panic("checked_pow #746") }
    if !(isize.MIN.wrapping_pow(1u32) == isize.MIN) { panic("wrapping_pow #747") }
    if !(isize.MIN.overflowing_pow(1u32).0 == isize.MIN && isize.MIN.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #748") }
    if !(isize.MIN.saturating_pow(1u32) == isize.MIN) { panic("saturating_pow #749") }
    if !(isize.MIN.pow(1u32) == isize.MIN) { panic("pow #750") }
    if !(isize.MIN.strict_pow(1u32) == isize.MIN) { panic("strict_pow #751") }
    if !(missing(isize.MIN.checked_pow(2u32))) { panic("checked_pow #752") }
    if !(isize.MIN.wrapping_pow(2u32) == 0isize) { panic("wrapping_pow #753") }
    if !(isize.MIN.overflowing_pow(2u32).0 == 0isize && isize.MIN.overflowing_pow(2u32).1 == true) { panic("overflowing_pow #754") }
    if !(isize.MIN.saturating_pow(2u32) == isize.MAX) { panic("saturating_pow #755") }
    if !(missing(isize.MIN.checked_pow(3u32))) { panic("checked_pow #756") }
    if !(isize.MIN.wrapping_pow(3u32) == 0isize) { panic("wrapping_pow #757") }
    if !(isize.MIN.overflowing_pow(3u32).0 == 0isize && isize.MIN.overflowing_pow(3u32).1 == true) { panic("overflowing_pow #758") }
    if !(isize.MIN.saturating_pow(3u32) == isize.MIN) { panic("saturating_pow #759") }
    if !(missing(isize.MIN.checked_pow(63u32))) { panic("checked_pow #760") }
    if !(isize.MIN.wrapping_pow(63u32) == 0isize) { panic("wrapping_pow #761") }
    if !(isize.MIN.overflowing_pow(63u32).0 == 0isize && isize.MIN.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #762") }
    if !(isize.MIN.saturating_pow(63u32) == isize.MIN) { panic("saturating_pow #763") }
    if !(missing(isize.MIN.checked_pow(64u32))) { panic("checked_pow #764") }
    if !(isize.MIN.wrapping_pow(64u32) == 0isize) { panic("wrapping_pow #765") }
    if !(isize.MIN.overflowing_pow(64u32).0 == 0isize && isize.MIN.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #766") }
    if !(isize.MIN.saturating_pow(64u32) == isize.MAX) { panic("saturating_pow #767") }
    if !(missing(isize.MIN.checked_ilog2())) { panic("checked_ilog2 #768") }
    if !(missing(isize.MIN.checked_ilog10())) { panic("checked_ilog10 #769") }
    if !(missing(isize.MIN.checked_ilog(2isize))) { panic("checked_ilog #770") }
    if !(missing(isize.MIN.checked_isqrt())) { panic("checked_isqrt #771") }
    if !(isize.MIN.highest_one() == present(63u32)) { panic("highest_one #772") }
    if !(isize.MIN.lowest_one() == present(63u32)) { panic("lowest_one #773") }
    if !(isize.MIN.isolate_highest_one() == isize.MIN) { panic("isolate_highest_one #774") }
    if !(isize.MIN.isolate_lowest_one() == isize.MIN) { panic("isolate_lowest_one #775") }
    if !(1000isize.checked_neg() == present((-1000isize))) { panic("checked_neg #776") }
    if !(1000isize.wrapping_neg() == (-1000isize)) { panic("wrapping_neg #777") }
    if !(1000isize.overflowing_neg().0 == (-1000isize) && 1000isize.overflowing_neg().1 == false) { panic("overflowing_neg #778") }
    if !(1000isize.strict_neg() == (-1000isize)) { panic("strict_neg #779") }
    if !(unsafe { 1000isize.unchecked_neg() } == (-1000isize)) { panic("unchecked_neg #780") }
    if !(1000isize.saturating_neg() == (-1000isize)) { panic("saturating_neg #781") }
    if !(1000isize.checked_abs() == present(1000isize)) { panic("checked_abs #782") }
    if !(1000isize.wrapping_abs() == 1000isize) { panic("wrapping_abs #783") }
    if !(1000isize.overflowing_abs().0 == 1000isize && 1000isize.overflowing_abs().1 == false) { panic("overflowing_abs #784") }
    if !(1000isize.saturating_abs() == 1000isize) { panic("saturating_abs #785") }
    if !(1000isize.strict_abs() == 1000isize) { panic("strict_abs #786") }
    if !(1000isize.abs() == 1000isize) { panic("abs #787") }
    if !(1000isize.unsigned_abs() == 1000usize) { panic("unsigned_abs #788") }
    if !(1000isize.signum() == 1isize) { panic("signum #789") }
    if !(1000isize.is_positive() == true) { panic("is_positive #790") }
    if !(1000isize.is_negative() == false) { panic("is_negative #791") }
    if !(1000isize.cast_unsigned() == 1000usize) { panic("cast_unsigned #792") }
    if !(1000isize.count_ones() == 6u32) { panic("count_ones #793") }
    if !(1000isize.count_zeros() == 58u32) { panic("count_zeros #794") }
    if !(1000isize.leading_zeros() == 54u32) { panic("leading_zeros #795") }
    if !(1000isize.trailing_zeros() == 3u32) { panic("trailing_zeros #796") }
    if !(1000isize.leading_ones() == 0u32) { panic("leading_ones #797") }
    if !(1000isize.trailing_ones() == 0u32) { panic("trailing_ones #798") }
    if !(1000isize.reverse_bits() == 1711367858400788480isize) { panic("reverse_bits #799") }
    if !(1000isize.swap_bytes() == (-1728537831980138496isize)) { panic("swap_bytes #800") }
    if !(1000isize.to_be() == (-1728537831980138496isize)) { panic("to_be #801") }
    if !(1000isize.to_le() == 1000isize) { panic("to_le #802") }
    if !(isize.from_be(1000isize) == (-1728537831980138496isize)) { panic("from_be #803") }
    if !(isize.from_le(1000isize) == 1000isize) { panic("from_le #804") }
    if !(1000isize.to_le_bytes() == [232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #805") }
    if !(1000isize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 3u8, 232u8]) { panic("to_be_bytes #806") }
    if !(1000isize.to_ne_bytes() == [232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #807") }
    if !(isize.from_le_bytes([232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1000isize) { panic("from_le_bytes #808") }
    if !(isize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 3u8, 232u8]) == 1000isize) { panic("from_be_bytes #809") }
    if !(isize.from_ne_bytes([232u8, 3u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1000isize) { panic("from_ne_bytes #810") }
    if !(1000isize.rotate_left(0u32) == 1000isize) { panic("rotate_left #811") }
    if !(1000isize.rotate_right(0u32) == 1000isize) { panic("rotate_right #812") }
    if !(1000isize.checked_shl(0u32) == present(1000isize)) { panic("checked_shl #813") }
    if !(1000isize.checked_shr(0u32) == present(1000isize)) { panic("checked_shr #814") }
    if !(1000isize.wrapping_shl(0u32) == 1000isize) { panic("wrapping_shl #815") }
    if !(1000isize.wrapping_shr(0u32) == 1000isize) { panic("wrapping_shr #816") }
    if !(1000isize.overflowing_shl(0u32).0 == 1000isize && 1000isize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #817") }
    if !(1000isize.overflowing_shr(0u32).0 == 1000isize && 1000isize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #818") }
    if !(1000isize.unbounded_shl(0u32) == 1000isize) { panic("unbounded_shl #819") }
    if !(1000isize.unbounded_shr(0u32) == 1000isize) { panic("unbounded_shr #820") }
    if !(1000isize.strict_shl(0u32) == 1000isize) { panic("strict_shl #821") }
    if !(1000isize.strict_shr(0u32) == 1000isize) { panic("strict_shr #822") }
    if !(unsafe { 1000isize.unchecked_shl(0u32) } == 1000isize) { panic("unchecked_shl #823") }
    if !(unsafe { 1000isize.unchecked_shr(0u32) } == 1000isize) { panic("unchecked_shr #824") }
    if !(1000isize.rotate_left(1u32) == 2000isize) { panic("rotate_left #825") }
    if !(1000isize.rotate_right(1u32) == 500isize) { panic("rotate_right #826") }
    if !(1000isize.checked_shl(1u32) == present(2000isize)) { panic("checked_shl #827") }
    if !(1000isize.checked_shr(1u32) == present(500isize)) { panic("checked_shr #828") }
    if !(1000isize.wrapping_shl(1u32) == 2000isize) { panic("wrapping_shl #829") }
    if !(1000isize.wrapping_shr(1u32) == 500isize) { panic("wrapping_shr #830") }
    if !(1000isize.overflowing_shl(1u32).0 == 2000isize && 1000isize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #831") }
    if !(1000isize.overflowing_shr(1u32).0 == 500isize && 1000isize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #832") }
    if !(1000isize.unbounded_shl(1u32) == 2000isize) { panic("unbounded_shl #833") }
    if !(1000isize.unbounded_shr(1u32) == 500isize) { panic("unbounded_shr #834") }
    if !(1000isize.strict_shl(1u32) == 2000isize) { panic("strict_shl #835") }
    if !(1000isize.strict_shr(1u32) == 500isize) { panic("strict_shr #836") }
    if !(unsafe { 1000isize.unchecked_shl(1u32) } == 2000isize) { panic("unchecked_shl #837") }
    if !(unsafe { 1000isize.unchecked_shr(1u32) } == 500isize) { panic("unchecked_shr #838") }
    if !(1000isize.rotate_left(3u32) == 8000isize) { panic("rotate_left #839") }
    if !(1000isize.rotate_right(3u32) == 125isize) { panic("rotate_right #840") }
}

fn group7() {
    if !(1000isize.checked_shl(3u32) == present(8000isize)) { panic("checked_shl #841") }
    if !(1000isize.checked_shr(3u32) == present(125isize)) { panic("checked_shr #842") }
    if !(1000isize.wrapping_shl(3u32) == 8000isize) { panic("wrapping_shl #843") }
    if !(1000isize.wrapping_shr(3u32) == 125isize) { panic("wrapping_shr #844") }
    if !(1000isize.overflowing_shl(3u32).0 == 8000isize && 1000isize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #845") }
    if !(1000isize.overflowing_shr(3u32).0 == 125isize && 1000isize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #846") }
    if !(1000isize.unbounded_shl(3u32) == 8000isize) { panic("unbounded_shl #847") }
    if !(1000isize.unbounded_shr(3u32) == 125isize) { panic("unbounded_shr #848") }
    if !(1000isize.strict_shl(3u32) == 8000isize) { panic("strict_shl #849") }
    if !(1000isize.strict_shr(3u32) == 125isize) { panic("strict_shr #850") }
    if !(unsafe { 1000isize.unchecked_shl(3u32) } == 8000isize) { panic("unchecked_shl #851") }
    if !(unsafe { 1000isize.unchecked_shr(3u32) } == 125isize) { panic("unchecked_shr #852") }
    if !(1000isize.rotate_left(63u32) == 500isize) { panic("rotate_left #853") }
    if !(1000isize.rotate_right(63u32) == 2000isize) { panic("rotate_right #854") }
    if !(1000isize.checked_shl(63u32) == present(0isize)) { panic("checked_shl #855") }
    if !(1000isize.checked_shr(63u32) == present(0isize)) { panic("checked_shr #856") }
    if !(1000isize.wrapping_shl(63u32) == 0isize) { panic("wrapping_shl #857") }
    if !(1000isize.wrapping_shr(63u32) == 0isize) { panic("wrapping_shr #858") }
    if !(1000isize.overflowing_shl(63u32).0 == 0isize && 1000isize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #859") }
    if !(1000isize.overflowing_shr(63u32).0 == 0isize && 1000isize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #860") }
    if !(1000isize.unbounded_shl(63u32) == 0isize) { panic("unbounded_shl #861") }
    if !(1000isize.unbounded_shr(63u32) == 0isize) { panic("unbounded_shr #862") }
    if !(1000isize.strict_shl(63u32) == 0isize) { panic("strict_shl #863") }
    if !(1000isize.strict_shr(63u32) == 0isize) { panic("strict_shr #864") }
    if !(unsafe { 1000isize.unchecked_shl(63u32) } == 0isize) { panic("unchecked_shl #865") }
    if !(unsafe { 1000isize.unchecked_shr(63u32) } == 0isize) { panic("unchecked_shr #866") }
    if !(1000isize.rotate_left(64u32) == 1000isize) { panic("rotate_left #867") }
    if !(1000isize.rotate_right(64u32) == 1000isize) { panic("rotate_right #868") }
    if !(missing(1000isize.checked_shl(64u32))) { panic("checked_shl #869") }
    if !(missing(1000isize.checked_shr(64u32))) { panic("checked_shr #870") }
    if !(1000isize.wrapping_shl(64u32) == 1000isize) { panic("wrapping_shl #871") }
    if !(1000isize.wrapping_shr(64u32) == 1000isize) { panic("wrapping_shr #872") }
    if !(1000isize.overflowing_shl(64u32).0 == 1000isize && 1000isize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #873") }
    if !(1000isize.overflowing_shr(64u32).0 == 1000isize && 1000isize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #874") }
    if !(1000isize.unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #875") }
    if !(1000isize.unbounded_shr(64u32) == 0isize) { panic("unbounded_shr #876") }
    if !(1000isize.rotate_left(69u32) == 32000isize) { panic("rotate_left #877") }
    if !(1000isize.rotate_right(69u32) == 4611686018427387935isize) { panic("rotate_right #878") }
    if !(missing(1000isize.checked_shl(69u32))) { panic("checked_shl #879") }
    if !(missing(1000isize.checked_shr(69u32))) { panic("checked_shr #880") }
    if !(1000isize.wrapping_shl(69u32) == 32000isize) { panic("wrapping_shl #881") }
    if !(1000isize.wrapping_shr(69u32) == 31isize) { panic("wrapping_shr #882") }
    if !(1000isize.overflowing_shl(69u32).0 == 32000isize && 1000isize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #883") }
    if !(1000isize.overflowing_shr(69u32).0 == 31isize && 1000isize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #884") }
    if !(1000isize.unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #885") }
    if !(1000isize.unbounded_shr(69u32) == 0isize) { panic("unbounded_shr #886") }
    if !(1000isize.checked_pow(0u32) == present(1isize)) { panic("checked_pow #887") }
    if !(1000isize.wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #888") }
    if !(1000isize.overflowing_pow(0u32).0 == 1isize && 1000isize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #889") }
    if !(1000isize.saturating_pow(0u32) == 1isize) { panic("saturating_pow #890") }
    if !(1000isize.pow(0u32) == 1isize) { panic("pow #891") }
    if !(1000isize.strict_pow(0u32) == 1isize) { panic("strict_pow #892") }
    if !(1000isize.checked_pow(1u32) == present(1000isize)) { panic("checked_pow #893") }
    if !(1000isize.wrapping_pow(1u32) == 1000isize) { panic("wrapping_pow #894") }
    if !(1000isize.overflowing_pow(1u32).0 == 1000isize && 1000isize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #895") }
    if !(1000isize.saturating_pow(1u32) == 1000isize) { panic("saturating_pow #896") }
    if !(1000isize.pow(1u32) == 1000isize) { panic("pow #897") }
    if !(1000isize.strict_pow(1u32) == 1000isize) { panic("strict_pow #898") }
    if !(1000isize.checked_pow(2u32) == present(1000000isize)) { panic("checked_pow #899") }
    if !(1000isize.wrapping_pow(2u32) == 1000000isize) { panic("wrapping_pow #900") }
    if !(1000isize.overflowing_pow(2u32).0 == 1000000isize && 1000isize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #901") }
    if !(1000isize.saturating_pow(2u32) == 1000000isize) { panic("saturating_pow #902") }
    if !(1000isize.pow(2u32) == 1000000isize) { panic("pow #903") }
    if !(1000isize.strict_pow(2u32) == 1000000isize) { panic("strict_pow #904") }
    if !(1000isize.checked_pow(3u32) == present(1000000000isize)) { panic("checked_pow #905") }
    if !(1000isize.wrapping_pow(3u32) == 1000000000isize) { panic("wrapping_pow #906") }
    if !(1000isize.overflowing_pow(3u32).0 == 1000000000isize && 1000isize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #907") }
    if !(1000isize.saturating_pow(3u32) == 1000000000isize) { panic("saturating_pow #908") }
    if !(1000isize.pow(3u32) == 1000000000isize) { panic("pow #909") }
    if !(1000isize.strict_pow(3u32) == 1000000000isize) { panic("strict_pow #910") }
    if !(missing(1000isize.checked_pow(63u32))) { panic("checked_pow #911") }
    if !(1000isize.wrapping_pow(63u32) == 0isize) { panic("wrapping_pow #912") }
    if !(1000isize.overflowing_pow(63u32).0 == 0isize && 1000isize.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #913") }
    if !(1000isize.saturating_pow(63u32) == isize.MAX) { panic("saturating_pow #914") }
    if !(missing(1000isize.checked_pow(64u32))) { panic("checked_pow #915") }
    if !(1000isize.wrapping_pow(64u32) == 0isize) { panic("wrapping_pow #916") }
    if !(1000isize.overflowing_pow(64u32).0 == 0isize && 1000isize.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #917") }
    if !(1000isize.saturating_pow(64u32) == isize.MAX) { panic("saturating_pow #918") }
    if !(1000isize.ilog2() == 9u32) { panic("ilog2 #919") }
    if !(1000isize.ilog10() == 3u32) { panic("ilog10 #920") }
    if !(1000isize.checked_ilog2() == present(9u32)) { panic("checked_ilog2 #921") }
    if !(1000isize.checked_ilog10() == present(3u32)) { panic("checked_ilog10 #922") }
    if !(1000isize.ilog(2isize) == 9u32) { panic("ilog #923") }
    if !(1000isize.checked_ilog(2isize) == present(9u32)) { panic("checked_ilog #924") }
    if !(1000isize.ilog(3isize) == 6u32) { panic("ilog #925") }
    if !(1000isize.checked_ilog(3isize) == present(6u32)) { panic("checked_ilog #926") }
    if !(1000isize.ilog(7isize) == 3u32) { panic("ilog #927") }
    if !(1000isize.checked_ilog(7isize) == present(3u32)) { panic("checked_ilog #928") }
    if !(missing(1000isize.checked_ilog(1isize))) { panic("checked_ilog #929") }
    if !(1000isize.isqrt() == 31isize) { panic("isqrt #930") }
    if !(1000isize.checked_isqrt() == present(31isize)) { panic("checked_isqrt #931") }
    if !(1000isize.highest_one() == present(9u32)) { panic("highest_one #932") }
    if !(1000isize.lowest_one() == present(3u32)) { panic("lowest_one #933") }
    if !(1000isize.isolate_highest_one() == 512isize) { panic("isolate_highest_one #934") }
    if !(1000isize.isolate_lowest_one() == 8isize) { panic("isolate_lowest_one #935") }
    if !(7isize.checked_neg() == present((-7isize))) { panic("checked_neg #936") }
    if !(7isize.wrapping_neg() == (-7isize)) { panic("wrapping_neg #937") }
    if !(7isize.overflowing_neg().0 == (-7isize) && 7isize.overflowing_neg().1 == false) { panic("overflowing_neg #938") }
    if !(7isize.strict_neg() == (-7isize)) { panic("strict_neg #939") }
    if !(unsafe { 7isize.unchecked_neg() } == (-7isize)) { panic("unchecked_neg #940") }
    if !(7isize.saturating_neg() == (-7isize)) { panic("saturating_neg #941") }
    if !(7isize.checked_abs() == present(7isize)) { panic("checked_abs #942") }
    if !(7isize.wrapping_abs() == 7isize) { panic("wrapping_abs #943") }
    if !(7isize.overflowing_abs().0 == 7isize && 7isize.overflowing_abs().1 == false) { panic("overflowing_abs #944") }
    if !(7isize.saturating_abs() == 7isize) { panic("saturating_abs #945") }
    if !(7isize.strict_abs() == 7isize) { panic("strict_abs #946") }
    if !(7isize.abs() == 7isize) { panic("abs #947") }
    if !(7isize.unsigned_abs() == 7usize) { panic("unsigned_abs #948") }
    if !(7isize.signum() == 1isize) { panic("signum #949") }
    if !(7isize.is_positive() == true) { panic("is_positive #950") }
    if !(7isize.is_negative() == false) { panic("is_negative #951") }
    if !(7isize.cast_unsigned() == 7usize) { panic("cast_unsigned #952") }
    if !(7isize.count_ones() == 3u32) { panic("count_ones #953") }
    if !(7isize.count_zeros() == 61u32) { panic("count_zeros #954") }
    if !(7isize.leading_zeros() == 61u32) { panic("leading_zeros #955") }
    if !(7isize.trailing_zeros() == 0u32) { panic("trailing_zeros #956") }
    if !(7isize.leading_ones() == 0u32) { panic("leading_ones #957") }
    if !(7isize.trailing_ones() == 3u32) { panic("trailing_ones #958") }
    if !(7isize.reverse_bits() == (-2305843009213693952isize)) { panic("reverse_bits #959") }
    if !(7isize.swap_bytes() == 504403158265495552isize) { panic("swap_bytes #960") }
}

fn group8() {
    if !(7isize.to_be() == 504403158265495552isize) { panic("to_be #961") }
    if !(7isize.to_le() == 7isize) { panic("to_le #962") }
    if !(isize.from_be(7isize) == 504403158265495552isize) { panic("from_be #963") }
    if !(isize.from_le(7isize) == 7isize) { panic("from_le #964") }
    if !(7isize.to_le_bytes() == [7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #965") }
    if !(7isize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 7u8]) { panic("to_be_bytes #966") }
    if !(7isize.to_ne_bytes() == [7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #967") }
    if !(isize.from_le_bytes([7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 7isize) { panic("from_le_bytes #968") }
    if !(isize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 7u8]) == 7isize) { panic("from_be_bytes #969") }
    if !(isize.from_ne_bytes([7u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 7isize) { panic("from_ne_bytes #970") }
    if !(7isize.rotate_left(0u32) == 7isize) { panic("rotate_left #971") }
    if !(7isize.rotate_right(0u32) == 7isize) { panic("rotate_right #972") }
    if !(7isize.checked_shl(0u32) == present(7isize)) { panic("checked_shl #973") }
    if !(7isize.checked_shr(0u32) == present(7isize)) { panic("checked_shr #974") }
    if !(7isize.wrapping_shl(0u32) == 7isize) { panic("wrapping_shl #975") }
    if !(7isize.wrapping_shr(0u32) == 7isize) { panic("wrapping_shr #976") }
    if !(7isize.overflowing_shl(0u32).0 == 7isize && 7isize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #977") }
    if !(7isize.overflowing_shr(0u32).0 == 7isize && 7isize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #978") }
    if !(7isize.unbounded_shl(0u32) == 7isize) { panic("unbounded_shl #979") }
    if !(7isize.unbounded_shr(0u32) == 7isize) { panic("unbounded_shr #980") }
    if !(7isize.strict_shl(0u32) == 7isize) { panic("strict_shl #981") }
    if !(7isize.strict_shr(0u32) == 7isize) { panic("strict_shr #982") }
    if !(unsafe { 7isize.unchecked_shl(0u32) } == 7isize) { panic("unchecked_shl #983") }
    if !(unsafe { 7isize.unchecked_shr(0u32) } == 7isize) { panic("unchecked_shr #984") }
    if !(7isize.rotate_left(1u32) == 14isize) { panic("rotate_left #985") }
    if !(7isize.rotate_right(1u32) == (-9223372036854775805isize)) { panic("rotate_right #986") }
    if !(7isize.checked_shl(1u32) == present(14isize)) { panic("checked_shl #987") }
    if !(7isize.checked_shr(1u32) == present(3isize)) { panic("checked_shr #988") }
    if !(7isize.wrapping_shl(1u32) == 14isize) { panic("wrapping_shl #989") }
    if !(7isize.wrapping_shr(1u32) == 3isize) { panic("wrapping_shr #990") }
    if !(7isize.overflowing_shl(1u32).0 == 14isize && 7isize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #991") }
    if !(7isize.overflowing_shr(1u32).0 == 3isize && 7isize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #992") }
    if !(7isize.unbounded_shl(1u32) == 14isize) { panic("unbounded_shl #993") }
    if !(7isize.unbounded_shr(1u32) == 3isize) { panic("unbounded_shr #994") }
    if !(7isize.strict_shl(1u32) == 14isize) { panic("strict_shl #995") }
    if !(7isize.strict_shr(1u32) == 3isize) { panic("strict_shr #996") }
    if !(unsafe { 7isize.unchecked_shl(1u32) } == 14isize) { panic("unchecked_shl #997") }
    if !(unsafe { 7isize.unchecked_shr(1u32) } == 3isize) { panic("unchecked_shr #998") }
    if !(7isize.rotate_left(3u32) == 56isize) { panic("rotate_left #999") }
    if !(7isize.rotate_right(3u32) == (-2305843009213693952isize)) { panic("rotate_right #1000") }
    if !(7isize.checked_shl(3u32) == present(56isize)) { panic("checked_shl #1001") }
    if !(7isize.checked_shr(3u32) == present(0isize)) { panic("checked_shr #1002") }
    if !(7isize.wrapping_shl(3u32) == 56isize) { panic("wrapping_shl #1003") }
    if !(7isize.wrapping_shr(3u32) == 0isize) { panic("wrapping_shr #1004") }
    if !(7isize.overflowing_shl(3u32).0 == 56isize && 7isize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1005") }
    if !(7isize.overflowing_shr(3u32).0 == 0isize && 7isize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1006") }
    if !(7isize.unbounded_shl(3u32) == 56isize) { panic("unbounded_shl #1007") }
    if !(7isize.unbounded_shr(3u32) == 0isize) { panic("unbounded_shr #1008") }
    if !(7isize.strict_shl(3u32) == 56isize) { panic("strict_shl #1009") }
    if !(7isize.strict_shr(3u32) == 0isize) { panic("strict_shr #1010") }
    if !(unsafe { 7isize.unchecked_shl(3u32) } == 56isize) { panic("unchecked_shl #1011") }
    if !(unsafe { 7isize.unchecked_shr(3u32) } == 0isize) { panic("unchecked_shr #1012") }
    if !(7isize.rotate_left(63u32) == (-9223372036854775805isize)) { panic("rotate_left #1013") }
    if !(7isize.rotate_right(63u32) == 14isize) { panic("rotate_right #1014") }
    if !(7isize.checked_shl(63u32) == present(isize.MIN)) { panic("checked_shl #1015") }
    if !(7isize.checked_shr(63u32) == present(0isize)) { panic("checked_shr #1016") }
    if !(7isize.wrapping_shl(63u32) == isize.MIN) { panic("wrapping_shl #1017") }
    if !(7isize.wrapping_shr(63u32) == 0isize) { panic("wrapping_shr #1018") }
    if !(7isize.overflowing_shl(63u32).0 == isize.MIN && 7isize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #1019") }
    if !(7isize.overflowing_shr(63u32).0 == 0isize && 7isize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #1020") }
    if !(7isize.unbounded_shl(63u32) == isize.MIN) { panic("unbounded_shl #1021") }
    if !(7isize.unbounded_shr(63u32) == 0isize) { panic("unbounded_shr #1022") }
    if !(7isize.strict_shl(63u32) == isize.MIN) { panic("strict_shl #1023") }
    if !(7isize.strict_shr(63u32) == 0isize) { panic("strict_shr #1024") }
    if !(unsafe { 7isize.unchecked_shl(63u32) } == isize.MIN) { panic("unchecked_shl #1025") }
    if !(unsafe { 7isize.unchecked_shr(63u32) } == 0isize) { panic("unchecked_shr #1026") }
    if !(7isize.rotate_left(64u32) == 7isize) { panic("rotate_left #1027") }
    if !(7isize.rotate_right(64u32) == 7isize) { panic("rotate_right #1028") }
    if !(missing(7isize.checked_shl(64u32))) { panic("checked_shl #1029") }
    if !(missing(7isize.checked_shr(64u32))) { panic("checked_shr #1030") }
    if !(7isize.wrapping_shl(64u32) == 7isize) { panic("wrapping_shl #1031") }
    if !(7isize.wrapping_shr(64u32) == 7isize) { panic("wrapping_shr #1032") }
    if !(7isize.overflowing_shl(64u32).0 == 7isize && 7isize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #1033") }
    if !(7isize.overflowing_shr(64u32).0 == 7isize && 7isize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #1034") }
    if !(7isize.unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #1035") }
    if !(7isize.unbounded_shr(64u32) == 0isize) { panic("unbounded_shr #1036") }
    if !(7isize.rotate_left(69u32) == 224isize) { panic("rotate_left #1037") }
    if !(7isize.rotate_right(69u32) == 4035225266123964416isize) { panic("rotate_right #1038") }
    if !(missing(7isize.checked_shl(69u32))) { panic("checked_shl #1039") }
    if !(missing(7isize.checked_shr(69u32))) { panic("checked_shr #1040") }
    if !(7isize.wrapping_shl(69u32) == 224isize) { panic("wrapping_shl #1041") }
    if !(7isize.wrapping_shr(69u32) == 0isize) { panic("wrapping_shr #1042") }
    if !(7isize.overflowing_shl(69u32).0 == 224isize && 7isize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #1043") }
    if !(7isize.overflowing_shr(69u32).0 == 0isize && 7isize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #1044") }
    if !(7isize.unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #1045") }
    if !(7isize.unbounded_shr(69u32) == 0isize) { panic("unbounded_shr #1046") }
    if !(7isize.checked_pow(0u32) == present(1isize)) { panic("checked_pow #1047") }
    if !(7isize.wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #1048") }
    if !(7isize.overflowing_pow(0u32).0 == 1isize && 7isize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1049") }
    if !(7isize.saturating_pow(0u32) == 1isize) { panic("saturating_pow #1050") }
    if !(7isize.pow(0u32) == 1isize) { panic("pow #1051") }
    if !(7isize.strict_pow(0u32) == 1isize) { panic("strict_pow #1052") }
    if !(7isize.checked_pow(1u32) == present(7isize)) { panic("checked_pow #1053") }
    if !(7isize.wrapping_pow(1u32) == 7isize) { panic("wrapping_pow #1054") }
    if !(7isize.overflowing_pow(1u32).0 == 7isize && 7isize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1055") }
    if !(7isize.saturating_pow(1u32) == 7isize) { panic("saturating_pow #1056") }
    if !(7isize.pow(1u32) == 7isize) { panic("pow #1057") }
    if !(7isize.strict_pow(1u32) == 7isize) { panic("strict_pow #1058") }
    if !(7isize.checked_pow(2u32) == present(49isize)) { panic("checked_pow #1059") }
    if !(7isize.wrapping_pow(2u32) == 49isize) { panic("wrapping_pow #1060") }
    if !(7isize.overflowing_pow(2u32).0 == 49isize && 7isize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1061") }
    if !(7isize.saturating_pow(2u32) == 49isize) { panic("saturating_pow #1062") }
    if !(7isize.pow(2u32) == 49isize) { panic("pow #1063") }
    if !(7isize.strict_pow(2u32) == 49isize) { panic("strict_pow #1064") }
    if !(7isize.checked_pow(3u32) == present(343isize)) { panic("checked_pow #1065") }
    if !(7isize.wrapping_pow(3u32) == 343isize) { panic("wrapping_pow #1066") }
    if !(7isize.overflowing_pow(3u32).0 == 343isize && 7isize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1067") }
    if !(7isize.saturating_pow(3u32) == 343isize) { panic("saturating_pow #1068") }
    if !(7isize.pow(3u32) == 343isize) { panic("pow #1069") }
    if !(7isize.strict_pow(3u32) == 343isize) { panic("strict_pow #1070") }
    if !(missing(7isize.checked_pow(63u32))) { panic("checked_pow #1071") }
    if !(7isize.wrapping_pow(63u32) == 2898552624600762295isize) { panic("wrapping_pow #1072") }
    if !(7isize.overflowing_pow(63u32).0 == 2898552624600762295isize && 7isize.overflowing_pow(63u32).1 == true) { panic("overflowing_pow #1073") }
    if !(7isize.saturating_pow(63u32) == isize.MAX) { panic("saturating_pow #1074") }
    if !(missing(7isize.checked_pow(64u32))) { panic("checked_pow #1075") }
    if !(7isize.wrapping_pow(64u32) == 1843124298495784449isize) { panic("wrapping_pow #1076") }
    if !(7isize.overflowing_pow(64u32).0 == 1843124298495784449isize && 7isize.overflowing_pow(64u32).1 == true) { panic("overflowing_pow #1077") }
    if !(7isize.saturating_pow(64u32) == isize.MAX) { panic("saturating_pow #1078") }
    if !(7isize.ilog2() == 2u32) { panic("ilog2 #1079") }
    if !(7isize.ilog10() == 0u32) { panic("ilog10 #1080") }
}

fn group9() {
    if !(7isize.checked_ilog2() == present(2u32)) { panic("checked_ilog2 #1081") }
    if !(7isize.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1082") }
    if !(7isize.ilog(2isize) == 2u32) { panic("ilog #1083") }
    if !(7isize.checked_ilog(2isize) == present(2u32)) { panic("checked_ilog #1084") }
    if !(7isize.ilog(3isize) == 1u32) { panic("ilog #1085") }
    if !(7isize.checked_ilog(3isize) == present(1u32)) { panic("checked_ilog #1086") }
    if !(7isize.ilog(7isize) == 1u32) { panic("ilog #1087") }
    if !(7isize.checked_ilog(7isize) == present(1u32)) { panic("checked_ilog #1088") }
    if !(missing(7isize.checked_ilog(1isize))) { panic("checked_ilog #1089") }
    if !(7isize.isqrt() == 2isize) { panic("isqrt #1090") }
    if !(7isize.checked_isqrt() == present(2isize)) { panic("checked_isqrt #1091") }
    if !(7isize.highest_one() == present(2u32)) { panic("highest_one #1092") }
    if !(7isize.lowest_one() == present(0u32)) { panic("lowest_one #1093") }
    if !(7isize.isolate_highest_one() == 4isize) { panic("isolate_highest_one #1094") }
    if !(7isize.isolate_lowest_one() == 1isize) { panic("isolate_lowest_one #1095") }
    if !(0isize.checked_neg() == present(0isize)) { panic("checked_neg #1096") }
    if !(0isize.wrapping_neg() == 0isize) { panic("wrapping_neg #1097") }
    if !(0isize.overflowing_neg().0 == 0isize && 0isize.overflowing_neg().1 == false) { panic("overflowing_neg #1098") }
    if !(0isize.strict_neg() == 0isize) { panic("strict_neg #1099") }
    if !(unsafe { 0isize.unchecked_neg() } == 0isize) { panic("unchecked_neg #1100") }
    if !(0isize.saturating_neg() == 0isize) { panic("saturating_neg #1101") }
    if !(0isize.checked_abs() == present(0isize)) { panic("checked_abs #1102") }
    if !(0isize.wrapping_abs() == 0isize) { panic("wrapping_abs #1103") }
    if !(0isize.overflowing_abs().0 == 0isize && 0isize.overflowing_abs().1 == false) { panic("overflowing_abs #1104") }
    if !(0isize.saturating_abs() == 0isize) { panic("saturating_abs #1105") }
    if !(0isize.strict_abs() == 0isize) { panic("strict_abs #1106") }
    if !(0isize.abs() == 0isize) { panic("abs #1107") }
    if !(0isize.unsigned_abs() == 0usize) { panic("unsigned_abs #1108") }
    if !(0isize.signum() == 0isize) { panic("signum #1109") }
    if !(0isize.is_positive() == false) { panic("is_positive #1110") }
    if !(0isize.is_negative() == false) { panic("is_negative #1111") }
    if !(0isize.cast_unsigned() == 0usize) { panic("cast_unsigned #1112") }
    if !(0isize.count_ones() == 0u32) { panic("count_ones #1113") }
    if !(0isize.count_zeros() == 64u32) { panic("count_zeros #1114") }
    if !(0isize.leading_zeros() == 64u32) { panic("leading_zeros #1115") }
    if !(0isize.trailing_zeros() == 64u32) { panic("trailing_zeros #1116") }
    if !(0isize.leading_ones() == 0u32) { panic("leading_ones #1117") }
    if !(0isize.trailing_ones() == 0u32) { panic("trailing_ones #1118") }
    if !(0isize.reverse_bits() == 0isize) { panic("reverse_bits #1119") }
    if !(0isize.swap_bytes() == 0isize) { panic("swap_bytes #1120") }
    if !(0isize.to_be() == 0isize) { panic("to_be #1121") }
    if !(0isize.to_le() == 0isize) { panic("to_le #1122") }
    if !(isize.from_be(0isize) == 0isize) { panic("from_be #1123") }
    if !(isize.from_le(0isize) == 0isize) { panic("from_le #1124") }
    if !(0isize.to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #1125") }
    if !(0isize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #1126") }
    if !(0isize.to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #1127") }
    if !(isize.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 0isize) { panic("from_le_bytes #1128") }
    if !(isize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 0isize) { panic("from_be_bytes #1129") }
    if !(isize.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 0isize) { panic("from_ne_bytes #1130") }
    if !(0isize.rotate_left(0u32) == 0isize) { panic("rotate_left #1131") }
    if !(0isize.rotate_right(0u32) == 0isize) { panic("rotate_right #1132") }
    if !(0isize.checked_shl(0u32) == present(0isize)) { panic("checked_shl #1133") }
    if !(0isize.checked_shr(0u32) == present(0isize)) { panic("checked_shr #1134") }
    if !(0isize.wrapping_shl(0u32) == 0isize) { panic("wrapping_shl #1135") }
    if !(0isize.wrapping_shr(0u32) == 0isize) { panic("wrapping_shr #1136") }
    if !(0isize.overflowing_shl(0u32).0 == 0isize && 0isize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1137") }
    if !(0isize.overflowing_shr(0u32).0 == 0isize && 0isize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1138") }
    if !(0isize.unbounded_shl(0u32) == 0isize) { panic("unbounded_shl #1139") }
    if !(0isize.unbounded_shr(0u32) == 0isize) { panic("unbounded_shr #1140") }
    if !(0isize.strict_shl(0u32) == 0isize) { panic("strict_shl #1141") }
    if !(0isize.strict_shr(0u32) == 0isize) { panic("strict_shr #1142") }
    if !(unsafe { 0isize.unchecked_shl(0u32) } == 0isize) { panic("unchecked_shl #1143") }
    if !(unsafe { 0isize.unchecked_shr(0u32) } == 0isize) { panic("unchecked_shr #1144") }
    if !(0isize.rotate_left(1u32) == 0isize) { panic("rotate_left #1145") }
    if !(0isize.rotate_right(1u32) == 0isize) { panic("rotate_right #1146") }
    if !(0isize.checked_shl(1u32) == present(0isize)) { panic("checked_shl #1147") }
    if !(0isize.checked_shr(1u32) == present(0isize)) { panic("checked_shr #1148") }
    if !(0isize.wrapping_shl(1u32) == 0isize) { panic("wrapping_shl #1149") }
    if !(0isize.wrapping_shr(1u32) == 0isize) { panic("wrapping_shr #1150") }
    if !(0isize.overflowing_shl(1u32).0 == 0isize && 0isize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1151") }
    if !(0isize.overflowing_shr(1u32).0 == 0isize && 0isize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1152") }
    if !(0isize.unbounded_shl(1u32) == 0isize) { panic("unbounded_shl #1153") }
    if !(0isize.unbounded_shr(1u32) == 0isize) { panic("unbounded_shr #1154") }
    if !(0isize.strict_shl(1u32) == 0isize) { panic("strict_shl #1155") }
    if !(0isize.strict_shr(1u32) == 0isize) { panic("strict_shr #1156") }
    if !(unsafe { 0isize.unchecked_shl(1u32) } == 0isize) { panic("unchecked_shl #1157") }
    if !(unsafe { 0isize.unchecked_shr(1u32) } == 0isize) { panic("unchecked_shr #1158") }
    if !(0isize.rotate_left(3u32) == 0isize) { panic("rotate_left #1159") }
    if !(0isize.rotate_right(3u32) == 0isize) { panic("rotate_right #1160") }
    if !(0isize.checked_shl(3u32) == present(0isize)) { panic("checked_shl #1161") }
    if !(0isize.checked_shr(3u32) == present(0isize)) { panic("checked_shr #1162") }
    if !(0isize.wrapping_shl(3u32) == 0isize) { panic("wrapping_shl #1163") }
    if !(0isize.wrapping_shr(3u32) == 0isize) { panic("wrapping_shr #1164") }
    if !(0isize.overflowing_shl(3u32).0 == 0isize && 0isize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1165") }
    if !(0isize.overflowing_shr(3u32).0 == 0isize && 0isize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1166") }
    if !(0isize.unbounded_shl(3u32) == 0isize) { panic("unbounded_shl #1167") }
    if !(0isize.unbounded_shr(3u32) == 0isize) { panic("unbounded_shr #1168") }
    if !(0isize.strict_shl(3u32) == 0isize) { panic("strict_shl #1169") }
    if !(0isize.strict_shr(3u32) == 0isize) { panic("strict_shr #1170") }
    if !(unsafe { 0isize.unchecked_shl(3u32) } == 0isize) { panic("unchecked_shl #1171") }
    if !(unsafe { 0isize.unchecked_shr(3u32) } == 0isize) { panic("unchecked_shr #1172") }
    if !(0isize.rotate_left(63u32) == 0isize) { panic("rotate_left #1173") }
    if !(0isize.rotate_right(63u32) == 0isize) { panic("rotate_right #1174") }
    if !(0isize.checked_shl(63u32) == present(0isize)) { panic("checked_shl #1175") }
    if !(0isize.checked_shr(63u32) == present(0isize)) { panic("checked_shr #1176") }
    if !(0isize.wrapping_shl(63u32) == 0isize) { panic("wrapping_shl #1177") }
    if !(0isize.wrapping_shr(63u32) == 0isize) { panic("wrapping_shr #1178") }
    if !(0isize.overflowing_shl(63u32).0 == 0isize && 0isize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #1179") }
    if !(0isize.overflowing_shr(63u32).0 == 0isize && 0isize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #1180") }
    if !(0isize.unbounded_shl(63u32) == 0isize) { panic("unbounded_shl #1181") }
    if !(0isize.unbounded_shr(63u32) == 0isize) { panic("unbounded_shr #1182") }
    if !(0isize.strict_shl(63u32) == 0isize) { panic("strict_shl #1183") }
    if !(0isize.strict_shr(63u32) == 0isize) { panic("strict_shr #1184") }
    if !(unsafe { 0isize.unchecked_shl(63u32) } == 0isize) { panic("unchecked_shl #1185") }
    if !(unsafe { 0isize.unchecked_shr(63u32) } == 0isize) { panic("unchecked_shr #1186") }
    if !(0isize.rotate_left(64u32) == 0isize) { panic("rotate_left #1187") }
    if !(0isize.rotate_right(64u32) == 0isize) { panic("rotate_right #1188") }
    if !(missing(0isize.checked_shl(64u32))) { panic("checked_shl #1189") }
    if !(missing(0isize.checked_shr(64u32))) { panic("checked_shr #1190") }
    if !(0isize.wrapping_shl(64u32) == 0isize) { panic("wrapping_shl #1191") }
    if !(0isize.wrapping_shr(64u32) == 0isize) { panic("wrapping_shr #1192") }
    if !(0isize.overflowing_shl(64u32).0 == 0isize && 0isize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #1193") }
    if !(0isize.overflowing_shr(64u32).0 == 0isize && 0isize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #1194") }
    if !(0isize.unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #1195") }
    if !(0isize.unbounded_shr(64u32) == 0isize) { panic("unbounded_shr #1196") }
    if !(0isize.rotate_left(69u32) == 0isize) { panic("rotate_left #1197") }
    if !(0isize.rotate_right(69u32) == 0isize) { panic("rotate_right #1198") }
    if !(missing(0isize.checked_shl(69u32))) { panic("checked_shl #1199") }
    if !(missing(0isize.checked_shr(69u32))) { panic("checked_shr #1200") }
}

fn group10() {
    if !(0isize.wrapping_shl(69u32) == 0isize) { panic("wrapping_shl #1201") }
    if !(0isize.wrapping_shr(69u32) == 0isize) { panic("wrapping_shr #1202") }
    if !(0isize.overflowing_shl(69u32).0 == 0isize && 0isize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #1203") }
    if !(0isize.overflowing_shr(69u32).0 == 0isize && 0isize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #1204") }
    if !(0isize.unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #1205") }
    if !(0isize.unbounded_shr(69u32) == 0isize) { panic("unbounded_shr #1206") }
    if !(0isize.checked_pow(0u32) == present(1isize)) { panic("checked_pow #1207") }
    if !(0isize.wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #1208") }
    if !(0isize.overflowing_pow(0u32).0 == 1isize && 0isize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1209") }
    if !(0isize.saturating_pow(0u32) == 1isize) { panic("saturating_pow #1210") }
    if !(0isize.pow(0u32) == 1isize) { panic("pow #1211") }
    if !(0isize.strict_pow(0u32) == 1isize) { panic("strict_pow #1212") }
    if !(0isize.checked_pow(1u32) == present(0isize)) { panic("checked_pow #1213") }
    if !(0isize.wrapping_pow(1u32) == 0isize) { panic("wrapping_pow #1214") }
    if !(0isize.overflowing_pow(1u32).0 == 0isize && 0isize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1215") }
    if !(0isize.saturating_pow(1u32) == 0isize) { panic("saturating_pow #1216") }
    if !(0isize.pow(1u32) == 0isize) { panic("pow #1217") }
    if !(0isize.strict_pow(1u32) == 0isize) { panic("strict_pow #1218") }
    if !(0isize.checked_pow(2u32) == present(0isize)) { panic("checked_pow #1219") }
    if !(0isize.wrapping_pow(2u32) == 0isize) { panic("wrapping_pow #1220") }
    if !(0isize.overflowing_pow(2u32).0 == 0isize && 0isize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1221") }
    if !(0isize.saturating_pow(2u32) == 0isize) { panic("saturating_pow #1222") }
    if !(0isize.pow(2u32) == 0isize) { panic("pow #1223") }
    if !(0isize.strict_pow(2u32) == 0isize) { panic("strict_pow #1224") }
    if !(0isize.checked_pow(3u32) == present(0isize)) { panic("checked_pow #1225") }
    if !(0isize.wrapping_pow(3u32) == 0isize) { panic("wrapping_pow #1226") }
    if !(0isize.overflowing_pow(3u32).0 == 0isize && 0isize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1227") }
    if !(0isize.saturating_pow(3u32) == 0isize) { panic("saturating_pow #1228") }
    if !(0isize.pow(3u32) == 0isize) { panic("pow #1229") }
    if !(0isize.strict_pow(3u32) == 0isize) { panic("strict_pow #1230") }
    if !(0isize.checked_pow(63u32) == present(0isize)) { panic("checked_pow #1231") }
    if !(0isize.wrapping_pow(63u32) == 0isize) { panic("wrapping_pow #1232") }
    if !(0isize.overflowing_pow(63u32).0 == 0isize && 0isize.overflowing_pow(63u32).1 == false) { panic("overflowing_pow #1233") }
    if !(0isize.saturating_pow(63u32) == 0isize) { panic("saturating_pow #1234") }
    if !(0isize.pow(63u32) == 0isize) { panic("pow #1235") }
    if !(0isize.strict_pow(63u32) == 0isize) { panic("strict_pow #1236") }
    if !(0isize.checked_pow(64u32) == present(0isize)) { panic("checked_pow #1237") }
    if !(0isize.wrapping_pow(64u32) == 0isize) { panic("wrapping_pow #1238") }
    if !(0isize.overflowing_pow(64u32).0 == 0isize && 0isize.overflowing_pow(64u32).1 == false) { panic("overflowing_pow #1239") }
    if !(0isize.saturating_pow(64u32) == 0isize) { panic("saturating_pow #1240") }
    if !(0isize.pow(64u32) == 0isize) { panic("pow #1241") }
    if !(0isize.strict_pow(64u32) == 0isize) { panic("strict_pow #1242") }
    if !(missing(0isize.checked_ilog2())) { panic("checked_ilog2 #1243") }
    if !(missing(0isize.checked_ilog10())) { panic("checked_ilog10 #1244") }
    if !(missing(0isize.checked_ilog(2isize))) { panic("checked_ilog #1245") }
    if !(0isize.isqrt() == 0isize) { panic("isqrt #1246") }
    if !(0isize.checked_isqrt() == present(0isize)) { panic("checked_isqrt #1247") }
    if !(missing(0isize.highest_one())) { panic("highest_one #1248") }
    if !(missing(0isize.lowest_one())) { panic("lowest_one #1249") }
    if !(0isize.isolate_highest_one() == 0isize) { panic("isolate_highest_one #1250") }
    if !(0isize.isolate_lowest_one() == 0isize) { panic("isolate_lowest_one #1251") }
    if !(1isize.checked_neg() == present((-1isize))) { panic("checked_neg #1252") }
    if !(1isize.wrapping_neg() == (-1isize)) { panic("wrapping_neg #1253") }
    if !(1isize.overflowing_neg().0 == (-1isize) && 1isize.overflowing_neg().1 == false) { panic("overflowing_neg #1254") }
    if !(1isize.strict_neg() == (-1isize)) { panic("strict_neg #1255") }
    if !(unsafe { 1isize.unchecked_neg() } == (-1isize)) { panic("unchecked_neg #1256") }
    if !(1isize.saturating_neg() == (-1isize)) { panic("saturating_neg #1257") }
    if !(1isize.checked_abs() == present(1isize)) { panic("checked_abs #1258") }
    if !(1isize.wrapping_abs() == 1isize) { panic("wrapping_abs #1259") }
    if !(1isize.overflowing_abs().0 == 1isize && 1isize.overflowing_abs().1 == false) { panic("overflowing_abs #1260") }
    if !(1isize.saturating_abs() == 1isize) { panic("saturating_abs #1261") }
    if !(1isize.strict_abs() == 1isize) { panic("strict_abs #1262") }
    if !(1isize.abs() == 1isize) { panic("abs #1263") }
    if !(1isize.unsigned_abs() == 1usize) { panic("unsigned_abs #1264") }
    if !(1isize.signum() == 1isize) { panic("signum #1265") }
    if !(1isize.is_positive() == true) { panic("is_positive #1266") }
    if !(1isize.is_negative() == false) { panic("is_negative #1267") }
    if !(1isize.cast_unsigned() == 1usize) { panic("cast_unsigned #1268") }
    if !(1isize.count_ones() == 1u32) { panic("count_ones #1269") }
    if !(1isize.count_zeros() == 63u32) { panic("count_zeros #1270") }
    if !(1isize.leading_zeros() == 63u32) { panic("leading_zeros #1271") }
    if !(1isize.trailing_zeros() == 0u32) { panic("trailing_zeros #1272") }
    if !(1isize.leading_ones() == 0u32) { panic("leading_ones #1273") }
    if !(1isize.trailing_ones() == 1u32) { panic("trailing_ones #1274") }
    if !(1isize.reverse_bits() == isize.MIN) { panic("reverse_bits #1275") }
    if !(1isize.swap_bytes() == 72057594037927936isize) { panic("swap_bytes #1276") }
    if !(1isize.to_be() == 72057594037927936isize) { panic("to_be #1277") }
    if !(1isize.to_le() == 1isize) { panic("to_le #1278") }
    if !(isize.from_be(1isize) == 72057594037927936isize) { panic("from_be #1279") }
    if !(isize.from_le(1isize) == 1isize) { panic("from_le #1280") }
    if !(1isize.to_le_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #1281") }
    if !(1isize.to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #1282") }
    if !(1isize.to_ne_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #1283") }
    if !(isize.from_le_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1isize) { panic("from_le_bytes #1284") }
    if !(isize.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]) == 1isize) { panic("from_be_bytes #1285") }
    if !(isize.from_ne_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) == 1isize) { panic("from_ne_bytes #1286") }
    if !(1isize.rotate_left(0u32) == 1isize) { panic("rotate_left #1287") }
    if !(1isize.rotate_right(0u32) == 1isize) { panic("rotate_right #1288") }
    if !(1isize.checked_shl(0u32) == present(1isize)) { panic("checked_shl #1289") }
    if !(1isize.checked_shr(0u32) == present(1isize)) { panic("checked_shr #1290") }
    if !(1isize.wrapping_shl(0u32) == 1isize) { panic("wrapping_shl #1291") }
    if !(1isize.wrapping_shr(0u32) == 1isize) { panic("wrapping_shr #1292") }
    if !(1isize.overflowing_shl(0u32).0 == 1isize && 1isize.overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1293") }
    if !(1isize.overflowing_shr(0u32).0 == 1isize && 1isize.overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1294") }
    if !(1isize.unbounded_shl(0u32) == 1isize) { panic("unbounded_shl #1295") }
    if !(1isize.unbounded_shr(0u32) == 1isize) { panic("unbounded_shr #1296") }
    if !(1isize.strict_shl(0u32) == 1isize) { panic("strict_shl #1297") }
    if !(1isize.strict_shr(0u32) == 1isize) { panic("strict_shr #1298") }
    if !(unsafe { 1isize.unchecked_shl(0u32) } == 1isize) { panic("unchecked_shl #1299") }
    if !(unsafe { 1isize.unchecked_shr(0u32) } == 1isize) { panic("unchecked_shr #1300") }
    if !(1isize.rotate_left(1u32) == 2isize) { panic("rotate_left #1301") }
    if !(1isize.rotate_right(1u32) == isize.MIN) { panic("rotate_right #1302") }
    if !(1isize.checked_shl(1u32) == present(2isize)) { panic("checked_shl #1303") }
    if !(1isize.checked_shr(1u32) == present(0isize)) { panic("checked_shr #1304") }
    if !(1isize.wrapping_shl(1u32) == 2isize) { panic("wrapping_shl #1305") }
    if !(1isize.wrapping_shr(1u32) == 0isize) { panic("wrapping_shr #1306") }
    if !(1isize.overflowing_shl(1u32).0 == 2isize && 1isize.overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1307") }
    if !(1isize.overflowing_shr(1u32).0 == 0isize && 1isize.overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1308") }
    if !(1isize.unbounded_shl(1u32) == 2isize) { panic("unbounded_shl #1309") }
    if !(1isize.unbounded_shr(1u32) == 0isize) { panic("unbounded_shr #1310") }
    if !(1isize.strict_shl(1u32) == 2isize) { panic("strict_shl #1311") }
    if !(1isize.strict_shr(1u32) == 0isize) { panic("strict_shr #1312") }
    if !(unsafe { 1isize.unchecked_shl(1u32) } == 2isize) { panic("unchecked_shl #1313") }
    if !(unsafe { 1isize.unchecked_shr(1u32) } == 0isize) { panic("unchecked_shr #1314") }
    if !(1isize.rotate_left(3u32) == 8isize) { panic("rotate_left #1315") }
    if !(1isize.rotate_right(3u32) == 2305843009213693952isize) { panic("rotate_right #1316") }
    if !(1isize.checked_shl(3u32) == present(8isize)) { panic("checked_shl #1317") }
    if !(1isize.checked_shr(3u32) == present(0isize)) { panic("checked_shr #1318") }
    if !(1isize.wrapping_shl(3u32) == 8isize) { panic("wrapping_shl #1319") }
    if !(1isize.wrapping_shr(3u32) == 0isize) { panic("wrapping_shr #1320") }
}

fn group11() {
    if !(1isize.overflowing_shl(3u32).0 == 8isize && 1isize.overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1321") }
    if !(1isize.overflowing_shr(3u32).0 == 0isize && 1isize.overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1322") }
    if !(1isize.unbounded_shl(3u32) == 8isize) { panic("unbounded_shl #1323") }
    if !(1isize.unbounded_shr(3u32) == 0isize) { panic("unbounded_shr #1324") }
    if !(1isize.strict_shl(3u32) == 8isize) { panic("strict_shl #1325") }
    if !(1isize.strict_shr(3u32) == 0isize) { panic("strict_shr #1326") }
    if !(unsafe { 1isize.unchecked_shl(3u32) } == 8isize) { panic("unchecked_shl #1327") }
    if !(unsafe { 1isize.unchecked_shr(3u32) } == 0isize) { panic("unchecked_shr #1328") }
    if !(1isize.rotate_left(63u32) == isize.MIN) { panic("rotate_left #1329") }
    if !(1isize.rotate_right(63u32) == 2isize) { panic("rotate_right #1330") }
    if !(1isize.checked_shl(63u32) == present(isize.MIN)) { panic("checked_shl #1331") }
    if !(1isize.checked_shr(63u32) == present(0isize)) { panic("checked_shr #1332") }
    if !(1isize.wrapping_shl(63u32) == isize.MIN) { panic("wrapping_shl #1333") }
    if !(1isize.wrapping_shr(63u32) == 0isize) { panic("wrapping_shr #1334") }
    if !(1isize.overflowing_shl(63u32).0 == isize.MIN && 1isize.overflowing_shl(63u32).1 == false) { panic("overflowing_shl #1335") }
    if !(1isize.overflowing_shr(63u32).0 == 0isize && 1isize.overflowing_shr(63u32).1 == false) { panic("overflowing_shr #1336") }
    if !(1isize.unbounded_shl(63u32) == isize.MIN) { panic("unbounded_shl #1337") }
    if !(1isize.unbounded_shr(63u32) == 0isize) { panic("unbounded_shr #1338") }
    if !(1isize.strict_shl(63u32) == isize.MIN) { panic("strict_shl #1339") }
    if !(1isize.strict_shr(63u32) == 0isize) { panic("strict_shr #1340") }
    if !(unsafe { 1isize.unchecked_shl(63u32) } == isize.MIN) { panic("unchecked_shl #1341") }
    if !(unsafe { 1isize.unchecked_shr(63u32) } == 0isize) { panic("unchecked_shr #1342") }
    if !(1isize.rotate_left(64u32) == 1isize) { panic("rotate_left #1343") }
    if !(1isize.rotate_right(64u32) == 1isize) { panic("rotate_right #1344") }
    if !(missing(1isize.checked_shl(64u32))) { panic("checked_shl #1345") }
    if !(missing(1isize.checked_shr(64u32))) { panic("checked_shr #1346") }
    if !(1isize.wrapping_shl(64u32) == 1isize) { panic("wrapping_shl #1347") }
    if !(1isize.wrapping_shr(64u32) == 1isize) { panic("wrapping_shr #1348") }
    if !(1isize.overflowing_shl(64u32).0 == 1isize && 1isize.overflowing_shl(64u32).1 == true) { panic("overflowing_shl #1349") }
    if !(1isize.overflowing_shr(64u32).0 == 1isize && 1isize.overflowing_shr(64u32).1 == true) { panic("overflowing_shr #1350") }
    if !(1isize.unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #1351") }
    if !(1isize.unbounded_shr(64u32) == 0isize) { panic("unbounded_shr #1352") }
    if !(1isize.rotate_left(69u32) == 32isize) { panic("rotate_left #1353") }
    if !(1isize.rotate_right(69u32) == 576460752303423488isize) { panic("rotate_right #1354") }
    if !(missing(1isize.checked_shl(69u32))) { panic("checked_shl #1355") }
    if !(missing(1isize.checked_shr(69u32))) { panic("checked_shr #1356") }
    if !(1isize.wrapping_shl(69u32) == 32isize) { panic("wrapping_shl #1357") }
    if !(1isize.wrapping_shr(69u32) == 0isize) { panic("wrapping_shr #1358") }
    if !(1isize.overflowing_shl(69u32).0 == 32isize && 1isize.overflowing_shl(69u32).1 == true) { panic("overflowing_shl #1359") }
    if !(1isize.overflowing_shr(69u32).0 == 0isize && 1isize.overflowing_shr(69u32).1 == true) { panic("overflowing_shr #1360") }
    if !(1isize.unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #1361") }
    if !(1isize.unbounded_shr(69u32) == 0isize) { panic("unbounded_shr #1362") }
    if !(1isize.checked_pow(0u32) == present(1isize)) { panic("checked_pow #1363") }
    if !(1isize.wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #1364") }
    if !(1isize.overflowing_pow(0u32).0 == 1isize && 1isize.overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1365") }
    if !(1isize.saturating_pow(0u32) == 1isize) { panic("saturating_pow #1366") }
    if !(1isize.pow(0u32) == 1isize) { panic("pow #1367") }
    if !(1isize.strict_pow(0u32) == 1isize) { panic("strict_pow #1368") }
    if !(1isize.checked_pow(1u32) == present(1isize)) { panic("checked_pow #1369") }
    if !(1isize.wrapping_pow(1u32) == 1isize) { panic("wrapping_pow #1370") }
    if !(1isize.overflowing_pow(1u32).0 == 1isize && 1isize.overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1371") }
    if !(1isize.saturating_pow(1u32) == 1isize) { panic("saturating_pow #1372") }
    if !(1isize.pow(1u32) == 1isize) { panic("pow #1373") }
    if !(1isize.strict_pow(1u32) == 1isize) { panic("strict_pow #1374") }
    if !(1isize.checked_pow(2u32) == present(1isize)) { panic("checked_pow #1375") }
    if !(1isize.wrapping_pow(2u32) == 1isize) { panic("wrapping_pow #1376") }
    if !(1isize.overflowing_pow(2u32).0 == 1isize && 1isize.overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1377") }
    if !(1isize.saturating_pow(2u32) == 1isize) { panic("saturating_pow #1378") }
    if !(1isize.pow(2u32) == 1isize) { panic("pow #1379") }
    if !(1isize.strict_pow(2u32) == 1isize) { panic("strict_pow #1380") }
    if !(1isize.checked_pow(3u32) == present(1isize)) { panic("checked_pow #1381") }
    if !(1isize.wrapping_pow(3u32) == 1isize) { panic("wrapping_pow #1382") }
    if !(1isize.overflowing_pow(3u32).0 == 1isize && 1isize.overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1383") }
    if !(1isize.saturating_pow(3u32) == 1isize) { panic("saturating_pow #1384") }
    if !(1isize.pow(3u32) == 1isize) { panic("pow #1385") }
    if !(1isize.strict_pow(3u32) == 1isize) { panic("strict_pow #1386") }
    if !(1isize.checked_pow(63u32) == present(1isize)) { panic("checked_pow #1387") }
    if !(1isize.wrapping_pow(63u32) == 1isize) { panic("wrapping_pow #1388") }
    if !(1isize.overflowing_pow(63u32).0 == 1isize && 1isize.overflowing_pow(63u32).1 == false) { panic("overflowing_pow #1389") }
    if !(1isize.saturating_pow(63u32) == 1isize) { panic("saturating_pow #1390") }
    if !(1isize.pow(63u32) == 1isize) { panic("pow #1391") }
    if !(1isize.strict_pow(63u32) == 1isize) { panic("strict_pow #1392") }
    if !(1isize.checked_pow(64u32) == present(1isize)) { panic("checked_pow #1393") }
    if !(1isize.wrapping_pow(64u32) == 1isize) { panic("wrapping_pow #1394") }
    if !(1isize.overflowing_pow(64u32).0 == 1isize && 1isize.overflowing_pow(64u32).1 == false) { panic("overflowing_pow #1395") }
    if !(1isize.saturating_pow(64u32) == 1isize) { panic("saturating_pow #1396") }
    if !(1isize.pow(64u32) == 1isize) { panic("pow #1397") }
    if !(1isize.strict_pow(64u32) == 1isize) { panic("strict_pow #1398") }
    if !(1isize.ilog2() == 0u32) { panic("ilog2 #1399") }
    if !(1isize.ilog10() == 0u32) { panic("ilog10 #1400") }
    if !(1isize.checked_ilog2() == present(0u32)) { panic("checked_ilog2 #1401") }
    if !(1isize.checked_ilog10() == present(0u32)) { panic("checked_ilog10 #1402") }
    if !(1isize.ilog(2isize) == 0u32) { panic("ilog #1403") }
    if !(1isize.checked_ilog(2isize) == present(0u32)) { panic("checked_ilog #1404") }
    if !(1isize.ilog(3isize) == 0u32) { panic("ilog #1405") }
    if !(1isize.checked_ilog(3isize) == present(0u32)) { panic("checked_ilog #1406") }
    if !(1isize.ilog(7isize) == 0u32) { panic("ilog #1407") }
    if !(1isize.checked_ilog(7isize) == present(0u32)) { panic("checked_ilog #1408") }
    if !(missing(1isize.checked_ilog(1isize))) { panic("checked_ilog #1409") }
    if !(1isize.isqrt() == 1isize) { panic("isqrt #1410") }
    if !(1isize.checked_isqrt() == present(1isize)) { panic("checked_isqrt #1411") }
    if !(1isize.highest_one() == present(0u32)) { panic("highest_one #1412") }
    if !(1isize.lowest_one() == present(0u32)) { panic("lowest_one #1413") }
    if !(1isize.isolate_highest_one() == 1isize) { panic("isolate_highest_one #1414") }
    if !(1isize.isolate_lowest_one() == 1isize) { panic("isolate_lowest_one #1415") }
    if !((-7isize).checked_neg() == present(7isize)) { panic("checked_neg #1416") }
    if !((-7isize).wrapping_neg() == 7isize) { panic("wrapping_neg #1417") }
    if !((-7isize).overflowing_neg().0 == 7isize && (-7isize).overflowing_neg().1 == false) { panic("overflowing_neg #1418") }
    if !((-7isize).strict_neg() == 7isize) { panic("strict_neg #1419") }
    if !(unsafe { (-7isize).unchecked_neg() } == 7isize) { panic("unchecked_neg #1420") }
    if !((-7isize).saturating_neg() == 7isize) { panic("saturating_neg #1421") }
    if !((-7isize).checked_abs() == present(7isize)) { panic("checked_abs #1422") }
    if !((-7isize).wrapping_abs() == 7isize) { panic("wrapping_abs #1423") }
    if !((-7isize).overflowing_abs().0 == 7isize && (-7isize).overflowing_abs().1 == false) { panic("overflowing_abs #1424") }
    if !((-7isize).saturating_abs() == 7isize) { panic("saturating_abs #1425") }
    if !((-7isize).strict_abs() == 7isize) { panic("strict_abs #1426") }
    if !((-7isize).abs() == 7isize) { panic("abs #1427") }
    if !((-7isize).unsigned_abs() == 7usize) { panic("unsigned_abs #1428") }
    if !((-7isize).signum() == (-1isize)) { panic("signum #1429") }
    if !((-7isize).is_positive() == false) { panic("is_positive #1430") }
    if !((-7isize).is_negative() == true) { panic("is_negative #1431") }
    if !((-7isize).cast_unsigned() == 18446744073709551609usize) { panic("cast_unsigned #1432") }
    if !((-7isize).count_ones() == 62u32) { panic("count_ones #1433") }
    if !((-7isize).count_zeros() == 2u32) { panic("count_zeros #1434") }
    if !((-7isize).leading_zeros() == 0u32) { panic("leading_zeros #1435") }
    if !((-7isize).trailing_zeros() == 0u32) { panic("trailing_zeros #1436") }
    if !((-7isize).leading_ones() == 61u32) { panic("leading_ones #1437") }
    if !((-7isize).trailing_ones() == 1u32) { panic("trailing_ones #1438") }
    if !((-7isize).reverse_bits() == (-6917529027641081857isize)) { panic("reverse_bits #1439") }
    if !((-7isize).swap_bytes() == (-432345564227567617isize)) { panic("swap_bytes #1440") }
}

fn group12() {
    if !((-7isize).to_be() == (-432345564227567617isize)) { panic("to_be #1441") }
    if !((-7isize).to_le() == (-7isize)) { panic("to_le #1442") }
    if !(isize.from_be((-7isize)) == (-432345564227567617isize)) { panic("from_be #1443") }
    if !(isize.from_le((-7isize)) == (-7isize)) { panic("from_le #1444") }
    if !((-7isize).to_le_bytes() == [249u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_le_bytes #1445") }
    if !((-7isize).to_be_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 249u8]) { panic("to_be_bytes #1446") }
    if !((-7isize).to_ne_bytes() == [249u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_ne_bytes #1447") }
    if !(isize.from_le_bytes([249u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == (-7isize)) { panic("from_le_bytes #1448") }
    if !(isize.from_be_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 249u8]) == (-7isize)) { panic("from_be_bytes #1449") }
    if !(isize.from_ne_bytes([249u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == (-7isize)) { panic("from_ne_bytes #1450") }
    if !((-7isize).rotate_left(0u32) == (-7isize)) { panic("rotate_left #1451") }
    if !((-7isize).rotate_right(0u32) == (-7isize)) { panic("rotate_right #1452") }
    if !((-7isize).checked_shl(0u32) == present((-7isize))) { panic("checked_shl #1453") }
    if !((-7isize).checked_shr(0u32) == present((-7isize))) { panic("checked_shr #1454") }
    if !((-7isize).wrapping_shl(0u32) == (-7isize)) { panic("wrapping_shl #1455") }
    if !((-7isize).wrapping_shr(0u32) == (-7isize)) { panic("wrapping_shr #1456") }
    if !((-7isize).overflowing_shl(0u32).0 == (-7isize) && (-7isize).overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1457") }
    if !((-7isize).overflowing_shr(0u32).0 == (-7isize) && (-7isize).overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1458") }
    if !((-7isize).unbounded_shl(0u32) == (-7isize)) { panic("unbounded_shl #1459") }
    if !((-7isize).unbounded_shr(0u32) == (-7isize)) { panic("unbounded_shr #1460") }
    if !((-7isize).strict_shl(0u32) == (-7isize)) { panic("strict_shl #1461") }
    if !((-7isize).strict_shr(0u32) == (-7isize)) { panic("strict_shr #1462") }
    if !(unsafe { (-7isize).unchecked_shl(0u32) } == (-7isize)) { panic("unchecked_shl #1463") }
    if !(unsafe { (-7isize).unchecked_shr(0u32) } == (-7isize)) { panic("unchecked_shr #1464") }
    if !((-7isize).rotate_left(1u32) == (-13isize)) { panic("rotate_left #1465") }
    if !((-7isize).rotate_right(1u32) == (-4isize)) { panic("rotate_right #1466") }
    if !((-7isize).checked_shl(1u32) == present((-14isize))) { panic("checked_shl #1467") }
    if !((-7isize).checked_shr(1u32) == present((-4isize))) { panic("checked_shr #1468") }
    if !((-7isize).wrapping_shl(1u32) == (-14isize)) { panic("wrapping_shl #1469") }
    if !((-7isize).wrapping_shr(1u32) == (-4isize)) { panic("wrapping_shr #1470") }
    if !((-7isize).overflowing_shl(1u32).0 == (-14isize) && (-7isize).overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1471") }
    if !((-7isize).overflowing_shr(1u32).0 == (-4isize) && (-7isize).overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1472") }
    if !((-7isize).unbounded_shl(1u32) == (-14isize)) { panic("unbounded_shl #1473") }
    if !((-7isize).unbounded_shr(1u32) == (-4isize)) { panic("unbounded_shr #1474") }
    if !((-7isize).strict_shl(1u32) == (-14isize)) { panic("strict_shl #1475") }
    if !((-7isize).strict_shr(1u32) == (-4isize)) { panic("strict_shr #1476") }
    if !(unsafe { (-7isize).unchecked_shl(1u32) } == (-14isize)) { panic("unchecked_shl #1477") }
    if !(unsafe { (-7isize).unchecked_shr(1u32) } == (-4isize)) { panic("unchecked_shr #1478") }
    if !((-7isize).rotate_left(3u32) == (-49isize)) { panic("rotate_left #1479") }
    if !((-7isize).rotate_right(3u32) == 4611686018427387903isize) { panic("rotate_right #1480") }
    if !((-7isize).checked_shl(3u32) == present((-56isize))) { panic("checked_shl #1481") }
    if !((-7isize).checked_shr(3u32) == present((-1isize))) { panic("checked_shr #1482") }
    if !((-7isize).wrapping_shl(3u32) == (-56isize)) { panic("wrapping_shl #1483") }
    if !((-7isize).wrapping_shr(3u32) == (-1isize)) { panic("wrapping_shr #1484") }
    if !((-7isize).overflowing_shl(3u32).0 == (-56isize) && (-7isize).overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1485") }
    if !((-7isize).overflowing_shr(3u32).0 == (-1isize) && (-7isize).overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1486") }
    if !((-7isize).unbounded_shl(3u32) == (-56isize)) { panic("unbounded_shl #1487") }
    if !((-7isize).unbounded_shr(3u32) == (-1isize)) { panic("unbounded_shr #1488") }
    if !((-7isize).strict_shl(3u32) == (-56isize)) { panic("strict_shl #1489") }
    if !((-7isize).strict_shr(3u32) == (-1isize)) { panic("strict_shr #1490") }
    if !(unsafe { (-7isize).unchecked_shl(3u32) } == (-56isize)) { panic("unchecked_shl #1491") }
    if !(unsafe { (-7isize).unchecked_shr(3u32) } == (-1isize)) { panic("unchecked_shr #1492") }
    if !((-7isize).rotate_left(63u32) == (-4isize)) { panic("rotate_left #1493") }
    if !((-7isize).rotate_right(63u32) == (-13isize)) { panic("rotate_right #1494") }
    if !((-7isize).checked_shl(63u32) == present(isize.MIN)) { panic("checked_shl #1495") }
    if !((-7isize).checked_shr(63u32) == present((-1isize))) { panic("checked_shr #1496") }
    if !((-7isize).wrapping_shl(63u32) == isize.MIN) { panic("wrapping_shl #1497") }
    if !((-7isize).wrapping_shr(63u32) == (-1isize)) { panic("wrapping_shr #1498") }
    if !((-7isize).overflowing_shl(63u32).0 == isize.MIN && (-7isize).overflowing_shl(63u32).1 == false) { panic("overflowing_shl #1499") }
    if !((-7isize).overflowing_shr(63u32).0 == (-1isize) && (-7isize).overflowing_shr(63u32).1 == false) { panic("overflowing_shr #1500") }
    if !((-7isize).unbounded_shl(63u32) == isize.MIN) { panic("unbounded_shl #1501") }
    if !((-7isize).unbounded_shr(63u32) == (-1isize)) { panic("unbounded_shr #1502") }
    if !((-7isize).strict_shl(63u32) == isize.MIN) { panic("strict_shl #1503") }
    if !((-7isize).strict_shr(63u32) == (-1isize)) { panic("strict_shr #1504") }
    if !(unsafe { (-7isize).unchecked_shl(63u32) } == isize.MIN) { panic("unchecked_shl #1505") }
    if !(unsafe { (-7isize).unchecked_shr(63u32) } == (-1isize)) { panic("unchecked_shr #1506") }
    if !((-7isize).rotate_left(64u32) == (-7isize)) { panic("rotate_left #1507") }
    if !((-7isize).rotate_right(64u32) == (-7isize)) { panic("rotate_right #1508") }
    if !(missing((-7isize).checked_shl(64u32))) { panic("checked_shl #1509") }
    if !(missing((-7isize).checked_shr(64u32))) { panic("checked_shr #1510") }
    if !((-7isize).wrapping_shl(64u32) == (-7isize)) { panic("wrapping_shl #1511") }
    if !((-7isize).wrapping_shr(64u32) == (-7isize)) { panic("wrapping_shr #1512") }
    if !((-7isize).overflowing_shl(64u32).0 == (-7isize) && (-7isize).overflowing_shl(64u32).1 == true) { panic("overflowing_shl #1513") }
    if !((-7isize).overflowing_shr(64u32).0 == (-7isize) && (-7isize).overflowing_shr(64u32).1 == true) { panic("overflowing_shr #1514") }
    if !((-7isize).unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #1515") }
    if !((-7isize).unbounded_shr(64u32) == (-1isize)) { panic("unbounded_shr #1516") }
    if !((-7isize).rotate_left(69u32) == (-193isize)) { panic("rotate_left #1517") }
    if !((-7isize).rotate_right(69u32) == (-3458764513820540929isize)) { panic("rotate_right #1518") }
    if !(missing((-7isize).checked_shl(69u32))) { panic("checked_shl #1519") }
    if !(missing((-7isize).checked_shr(69u32))) { panic("checked_shr #1520") }
    if !((-7isize).wrapping_shl(69u32) == (-224isize)) { panic("wrapping_shl #1521") }
    if !((-7isize).wrapping_shr(69u32) == (-1isize)) { panic("wrapping_shr #1522") }
    if !((-7isize).overflowing_shl(69u32).0 == (-224isize) && (-7isize).overflowing_shl(69u32).1 == true) { panic("overflowing_shl #1523") }
    if !((-7isize).overflowing_shr(69u32).0 == (-1isize) && (-7isize).overflowing_shr(69u32).1 == true) { panic("overflowing_shr #1524") }
    if !((-7isize).unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #1525") }
    if !((-7isize).unbounded_shr(69u32) == (-1isize)) { panic("unbounded_shr #1526") }
    if !((-7isize).checked_pow(0u32) == present(1isize)) { panic("checked_pow #1527") }
    if !((-7isize).wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #1528") }
    if !((-7isize).overflowing_pow(0u32).0 == 1isize && (-7isize).overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1529") }
    if !((-7isize).saturating_pow(0u32) == 1isize) { panic("saturating_pow #1530") }
    if !((-7isize).pow(0u32) == 1isize) { panic("pow #1531") }
    if !((-7isize).strict_pow(0u32) == 1isize) { panic("strict_pow #1532") }
    if !((-7isize).checked_pow(1u32) == present((-7isize))) { panic("checked_pow #1533") }
    if !((-7isize).wrapping_pow(1u32) == (-7isize)) { panic("wrapping_pow #1534") }
    if !((-7isize).overflowing_pow(1u32).0 == (-7isize) && (-7isize).overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1535") }
    if !((-7isize).saturating_pow(1u32) == (-7isize)) { panic("saturating_pow #1536") }
    if !((-7isize).pow(1u32) == (-7isize)) { panic("pow #1537") }
    if !((-7isize).strict_pow(1u32) == (-7isize)) { panic("strict_pow #1538") }
    if !((-7isize).checked_pow(2u32) == present(49isize)) { panic("checked_pow #1539") }
    if !((-7isize).wrapping_pow(2u32) == 49isize) { panic("wrapping_pow #1540") }
    if !((-7isize).overflowing_pow(2u32).0 == 49isize && (-7isize).overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1541") }
    if !((-7isize).saturating_pow(2u32) == 49isize) { panic("saturating_pow #1542") }
    if !((-7isize).pow(2u32) == 49isize) { panic("pow #1543") }
    if !((-7isize).strict_pow(2u32) == 49isize) { panic("strict_pow #1544") }
    if !((-7isize).checked_pow(3u32) == present((-343isize))) { panic("checked_pow #1545") }
    if !((-7isize).wrapping_pow(3u32) == (-343isize)) { panic("wrapping_pow #1546") }
    if !((-7isize).overflowing_pow(3u32).0 == (-343isize) && (-7isize).overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1547") }
    if !((-7isize).saturating_pow(3u32) == (-343isize)) { panic("saturating_pow #1548") }
    if !((-7isize).pow(3u32) == (-343isize)) { panic("pow #1549") }
    if !((-7isize).strict_pow(3u32) == (-343isize)) { panic("strict_pow #1550") }
    if !(missing((-7isize).checked_pow(63u32))) { panic("checked_pow #1551") }
    if !((-7isize).wrapping_pow(63u32) == (-2898552624600762295isize)) { panic("wrapping_pow #1552") }
    if !((-7isize).overflowing_pow(63u32).0 == (-2898552624600762295isize) && (-7isize).overflowing_pow(63u32).1 == true) { panic("overflowing_pow #1553") }
    if !((-7isize).saturating_pow(63u32) == isize.MIN) { panic("saturating_pow #1554") }
    if !(missing((-7isize).checked_pow(64u32))) { panic("checked_pow #1555") }
    if !((-7isize).wrapping_pow(64u32) == 1843124298495784449isize) { panic("wrapping_pow #1556") }
    if !((-7isize).overflowing_pow(64u32).0 == 1843124298495784449isize && (-7isize).overflowing_pow(64u32).1 == true) { panic("overflowing_pow #1557") }
    if !((-7isize).saturating_pow(64u32) == isize.MAX) { panic("saturating_pow #1558") }
    if !(missing((-7isize).checked_ilog2())) { panic("checked_ilog2 #1559") }
    if !(missing((-7isize).checked_ilog10())) { panic("checked_ilog10 #1560") }
}

fn group13() {
    if !(missing((-7isize).checked_ilog(2isize))) { panic("checked_ilog #1561") }
    if !(missing((-7isize).checked_isqrt())) { panic("checked_isqrt #1562") }
    if !((-7isize).highest_one() == present(63u32)) { panic("highest_one #1563") }
    if !((-7isize).lowest_one() == present(0u32)) { panic("lowest_one #1564") }
    if !((-7isize).isolate_highest_one() == isize.MIN) { panic("isolate_highest_one #1565") }
    if !((-7isize).isolate_lowest_one() == 1isize) { panic("isolate_lowest_one #1566") }
    if !((-1isize).checked_neg() == present(1isize)) { panic("checked_neg #1567") }
    if !((-1isize).wrapping_neg() == 1isize) { panic("wrapping_neg #1568") }
    if !((-1isize).overflowing_neg().0 == 1isize && (-1isize).overflowing_neg().1 == false) { panic("overflowing_neg #1569") }
    if !((-1isize).strict_neg() == 1isize) { panic("strict_neg #1570") }
    if !(unsafe { (-1isize).unchecked_neg() } == 1isize) { panic("unchecked_neg #1571") }
    if !((-1isize).saturating_neg() == 1isize) { panic("saturating_neg #1572") }
    if !((-1isize).checked_abs() == present(1isize)) { panic("checked_abs #1573") }
    if !((-1isize).wrapping_abs() == 1isize) { panic("wrapping_abs #1574") }
    if !((-1isize).overflowing_abs().0 == 1isize && (-1isize).overflowing_abs().1 == false) { panic("overflowing_abs #1575") }
    if !((-1isize).saturating_abs() == 1isize) { panic("saturating_abs #1576") }
    if !((-1isize).strict_abs() == 1isize) { panic("strict_abs #1577") }
    if !((-1isize).abs() == 1isize) { panic("abs #1578") }
    if !((-1isize).unsigned_abs() == 1usize) { panic("unsigned_abs #1579") }
    if !((-1isize).signum() == (-1isize)) { panic("signum #1580") }
    if !((-1isize).is_positive() == false) { panic("is_positive #1581") }
    if !((-1isize).is_negative() == true) { panic("is_negative #1582") }
    if !((-1isize).cast_unsigned() == 18446744073709551615usize) { panic("cast_unsigned #1583") }
    if !((-1isize).count_ones() == 64u32) { panic("count_ones #1584") }
    if !((-1isize).count_zeros() == 0u32) { panic("count_zeros #1585") }
    if !((-1isize).leading_zeros() == 0u32) { panic("leading_zeros #1586") }
    if !((-1isize).trailing_zeros() == 0u32) { panic("trailing_zeros #1587") }
    if !((-1isize).leading_ones() == 64u32) { panic("leading_ones #1588") }
    if !((-1isize).trailing_ones() == 64u32) { panic("trailing_ones #1589") }
    if !((-1isize).reverse_bits() == (-1isize)) { panic("reverse_bits #1590") }
    if !((-1isize).swap_bytes() == (-1isize)) { panic("swap_bytes #1591") }
    if !((-1isize).to_be() == (-1isize)) { panic("to_be #1592") }
    if !((-1isize).to_le() == (-1isize)) { panic("to_le #1593") }
    if !(isize.from_be((-1isize)) == (-1isize)) { panic("from_be #1594") }
    if !(isize.from_le((-1isize)) == (-1isize)) { panic("from_le #1595") }
    if !((-1isize).to_le_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_le_bytes #1596") }
    if !((-1isize).to_be_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_be_bytes #1597") }
    if !((-1isize).to_ne_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_ne_bytes #1598") }
    if !(isize.from_le_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == (-1isize)) { panic("from_le_bytes #1599") }
    if !(isize.from_be_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == (-1isize)) { panic("from_be_bytes #1600") }
    if !(isize.from_ne_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) == (-1isize)) { panic("from_ne_bytes #1601") }
    if !((-1isize).rotate_left(0u32) == (-1isize)) { panic("rotate_left #1602") }
    if !((-1isize).rotate_right(0u32) == (-1isize)) { panic("rotate_right #1603") }
    if !((-1isize).checked_shl(0u32) == present((-1isize))) { panic("checked_shl #1604") }
    if !((-1isize).checked_shr(0u32) == present((-1isize))) { panic("checked_shr #1605") }
    if !((-1isize).wrapping_shl(0u32) == (-1isize)) { panic("wrapping_shl #1606") }
    if !((-1isize).wrapping_shr(0u32) == (-1isize)) { panic("wrapping_shr #1607") }
    if !((-1isize).overflowing_shl(0u32).0 == (-1isize) && (-1isize).overflowing_shl(0u32).1 == false) { panic("overflowing_shl #1608") }
    if !((-1isize).overflowing_shr(0u32).0 == (-1isize) && (-1isize).overflowing_shr(0u32).1 == false) { panic("overflowing_shr #1609") }
    if !((-1isize).unbounded_shl(0u32) == (-1isize)) { panic("unbounded_shl #1610") }
    if !((-1isize).unbounded_shr(0u32) == (-1isize)) { panic("unbounded_shr #1611") }
    if !((-1isize).strict_shl(0u32) == (-1isize)) { panic("strict_shl #1612") }
    if !((-1isize).strict_shr(0u32) == (-1isize)) { panic("strict_shr #1613") }
    if !(unsafe { (-1isize).unchecked_shl(0u32) } == (-1isize)) { panic("unchecked_shl #1614") }
    if !(unsafe { (-1isize).unchecked_shr(0u32) } == (-1isize)) { panic("unchecked_shr #1615") }
    if !((-1isize).rotate_left(1u32) == (-1isize)) { panic("rotate_left #1616") }
    if !((-1isize).rotate_right(1u32) == (-1isize)) { panic("rotate_right #1617") }
    if !((-1isize).checked_shl(1u32) == present((-2isize))) { panic("checked_shl #1618") }
    if !((-1isize).checked_shr(1u32) == present((-1isize))) { panic("checked_shr #1619") }
    if !((-1isize).wrapping_shl(1u32) == (-2isize)) { panic("wrapping_shl #1620") }
    if !((-1isize).wrapping_shr(1u32) == (-1isize)) { panic("wrapping_shr #1621") }
    if !((-1isize).overflowing_shl(1u32).0 == (-2isize) && (-1isize).overflowing_shl(1u32).1 == false) { panic("overflowing_shl #1622") }
    if !((-1isize).overflowing_shr(1u32).0 == (-1isize) && (-1isize).overflowing_shr(1u32).1 == false) { panic("overflowing_shr #1623") }
    if !((-1isize).unbounded_shl(1u32) == (-2isize)) { panic("unbounded_shl #1624") }
    if !((-1isize).unbounded_shr(1u32) == (-1isize)) { panic("unbounded_shr #1625") }
    if !((-1isize).strict_shl(1u32) == (-2isize)) { panic("strict_shl #1626") }
    if !((-1isize).strict_shr(1u32) == (-1isize)) { panic("strict_shr #1627") }
    if !(unsafe { (-1isize).unchecked_shl(1u32) } == (-2isize)) { panic("unchecked_shl #1628") }
    if !(unsafe { (-1isize).unchecked_shr(1u32) } == (-1isize)) { panic("unchecked_shr #1629") }
    if !((-1isize).rotate_left(3u32) == (-1isize)) { panic("rotate_left #1630") }
    if !((-1isize).rotate_right(3u32) == (-1isize)) { panic("rotate_right #1631") }
    if !((-1isize).checked_shl(3u32) == present((-8isize))) { panic("checked_shl #1632") }
    if !((-1isize).checked_shr(3u32) == present((-1isize))) { panic("checked_shr #1633") }
    if !((-1isize).wrapping_shl(3u32) == (-8isize)) { panic("wrapping_shl #1634") }
    if !((-1isize).wrapping_shr(3u32) == (-1isize)) { panic("wrapping_shr #1635") }
    if !((-1isize).overflowing_shl(3u32).0 == (-8isize) && (-1isize).overflowing_shl(3u32).1 == false) { panic("overflowing_shl #1636") }
    if !((-1isize).overflowing_shr(3u32).0 == (-1isize) && (-1isize).overflowing_shr(3u32).1 == false) { panic("overflowing_shr #1637") }
    if !((-1isize).unbounded_shl(3u32) == (-8isize)) { panic("unbounded_shl #1638") }
    if !((-1isize).unbounded_shr(3u32) == (-1isize)) { panic("unbounded_shr #1639") }
    if !((-1isize).strict_shl(3u32) == (-8isize)) { panic("strict_shl #1640") }
    if !((-1isize).strict_shr(3u32) == (-1isize)) { panic("strict_shr #1641") }
    if !(unsafe { (-1isize).unchecked_shl(3u32) } == (-8isize)) { panic("unchecked_shl #1642") }
    if !(unsafe { (-1isize).unchecked_shr(3u32) } == (-1isize)) { panic("unchecked_shr #1643") }
    if !((-1isize).rotate_left(63u32) == (-1isize)) { panic("rotate_left #1644") }
    if !((-1isize).rotate_right(63u32) == (-1isize)) { panic("rotate_right #1645") }
    if !((-1isize).checked_shl(63u32) == present(isize.MIN)) { panic("checked_shl #1646") }
    if !((-1isize).checked_shr(63u32) == present((-1isize))) { panic("checked_shr #1647") }
    if !((-1isize).wrapping_shl(63u32) == isize.MIN) { panic("wrapping_shl #1648") }
    if !((-1isize).wrapping_shr(63u32) == (-1isize)) { panic("wrapping_shr #1649") }
    if !((-1isize).overflowing_shl(63u32).0 == isize.MIN && (-1isize).overflowing_shl(63u32).1 == false) { panic("overflowing_shl #1650") }
    if !((-1isize).overflowing_shr(63u32).0 == (-1isize) && (-1isize).overflowing_shr(63u32).1 == false) { panic("overflowing_shr #1651") }
    if !((-1isize).unbounded_shl(63u32) == isize.MIN) { panic("unbounded_shl #1652") }
    if !((-1isize).unbounded_shr(63u32) == (-1isize)) { panic("unbounded_shr #1653") }
    if !((-1isize).strict_shl(63u32) == isize.MIN) { panic("strict_shl #1654") }
    if !((-1isize).strict_shr(63u32) == (-1isize)) { panic("strict_shr #1655") }
    if !(unsafe { (-1isize).unchecked_shl(63u32) } == isize.MIN) { panic("unchecked_shl #1656") }
    if !(unsafe { (-1isize).unchecked_shr(63u32) } == (-1isize)) { panic("unchecked_shr #1657") }
    if !((-1isize).rotate_left(64u32) == (-1isize)) { panic("rotate_left #1658") }
    if !((-1isize).rotate_right(64u32) == (-1isize)) { panic("rotate_right #1659") }
    if !(missing((-1isize).checked_shl(64u32))) { panic("checked_shl #1660") }
    if !(missing((-1isize).checked_shr(64u32))) { panic("checked_shr #1661") }
    if !((-1isize).wrapping_shl(64u32) == (-1isize)) { panic("wrapping_shl #1662") }
    if !((-1isize).wrapping_shr(64u32) == (-1isize)) { panic("wrapping_shr #1663") }
    if !((-1isize).overflowing_shl(64u32).0 == (-1isize) && (-1isize).overflowing_shl(64u32).1 == true) { panic("overflowing_shl #1664") }
    if !((-1isize).overflowing_shr(64u32).0 == (-1isize) && (-1isize).overflowing_shr(64u32).1 == true) { panic("overflowing_shr #1665") }
    if !((-1isize).unbounded_shl(64u32) == 0isize) { panic("unbounded_shl #1666") }
    if !((-1isize).unbounded_shr(64u32) == (-1isize)) { panic("unbounded_shr #1667") }
    if !((-1isize).rotate_left(69u32) == (-1isize)) { panic("rotate_left #1668") }
    if !((-1isize).rotate_right(69u32) == (-1isize)) { panic("rotate_right #1669") }
    if !(missing((-1isize).checked_shl(69u32))) { panic("checked_shl #1670") }
    if !(missing((-1isize).checked_shr(69u32))) { panic("checked_shr #1671") }
    if !((-1isize).wrapping_shl(69u32) == (-32isize)) { panic("wrapping_shl #1672") }
    if !((-1isize).wrapping_shr(69u32) == (-1isize)) { panic("wrapping_shr #1673") }
    if !((-1isize).overflowing_shl(69u32).0 == (-32isize) && (-1isize).overflowing_shl(69u32).1 == true) { panic("overflowing_shl #1674") }
    if !((-1isize).overflowing_shr(69u32).0 == (-1isize) && (-1isize).overflowing_shr(69u32).1 == true) { panic("overflowing_shr #1675") }
    if !((-1isize).unbounded_shl(69u32) == 0isize) { panic("unbounded_shl #1676") }
    if !((-1isize).unbounded_shr(69u32) == (-1isize)) { panic("unbounded_shr #1677") }
    if !((-1isize).checked_pow(0u32) == present(1isize)) { panic("checked_pow #1678") }
    if !((-1isize).wrapping_pow(0u32) == 1isize) { panic("wrapping_pow #1679") }
    if !((-1isize).overflowing_pow(0u32).0 == 1isize && (-1isize).overflowing_pow(0u32).1 == false) { panic("overflowing_pow #1680") }
}

fn group14() {
    if !((-1isize).saturating_pow(0u32) == 1isize) { panic("saturating_pow #1681") }
    if !((-1isize).pow(0u32) == 1isize) { panic("pow #1682") }
    if !((-1isize).strict_pow(0u32) == 1isize) { panic("strict_pow #1683") }
    if !((-1isize).checked_pow(1u32) == present((-1isize))) { panic("checked_pow #1684") }
    if !((-1isize).wrapping_pow(1u32) == (-1isize)) { panic("wrapping_pow #1685") }
    if !((-1isize).overflowing_pow(1u32).0 == (-1isize) && (-1isize).overflowing_pow(1u32).1 == false) { panic("overflowing_pow #1686") }
    if !((-1isize).saturating_pow(1u32) == (-1isize)) { panic("saturating_pow #1687") }
    if !((-1isize).pow(1u32) == (-1isize)) { panic("pow #1688") }
    if !((-1isize).strict_pow(1u32) == (-1isize)) { panic("strict_pow #1689") }
    if !((-1isize).checked_pow(2u32) == present(1isize)) { panic("checked_pow #1690") }
    if !((-1isize).wrapping_pow(2u32) == 1isize) { panic("wrapping_pow #1691") }
    if !((-1isize).overflowing_pow(2u32).0 == 1isize && (-1isize).overflowing_pow(2u32).1 == false) { panic("overflowing_pow #1692") }
    if !((-1isize).saturating_pow(2u32) == 1isize) { panic("saturating_pow #1693") }
    if !((-1isize).pow(2u32) == 1isize) { panic("pow #1694") }
    if !((-1isize).strict_pow(2u32) == 1isize) { panic("strict_pow #1695") }
    if !((-1isize).checked_pow(3u32) == present((-1isize))) { panic("checked_pow #1696") }
    if !((-1isize).wrapping_pow(3u32) == (-1isize)) { panic("wrapping_pow #1697") }
    if !((-1isize).overflowing_pow(3u32).0 == (-1isize) && (-1isize).overflowing_pow(3u32).1 == false) { panic("overflowing_pow #1698") }
    if !((-1isize).saturating_pow(3u32) == (-1isize)) { panic("saturating_pow #1699") }
    if !((-1isize).pow(3u32) == (-1isize)) { panic("pow #1700") }
    if !((-1isize).strict_pow(3u32) == (-1isize)) { panic("strict_pow #1701") }
    if !((-1isize).checked_pow(63u32) == present((-1isize))) { panic("checked_pow #1702") }
    if !((-1isize).wrapping_pow(63u32) == (-1isize)) { panic("wrapping_pow #1703") }
    if !((-1isize).overflowing_pow(63u32).0 == (-1isize) && (-1isize).overflowing_pow(63u32).1 == false) { panic("overflowing_pow #1704") }
    if !((-1isize).saturating_pow(63u32) == (-1isize)) { panic("saturating_pow #1705") }
    if !((-1isize).pow(63u32) == (-1isize)) { panic("pow #1706") }
    if !((-1isize).strict_pow(63u32) == (-1isize)) { panic("strict_pow #1707") }
    if !((-1isize).checked_pow(64u32) == present(1isize)) { panic("checked_pow #1708") }
    if !((-1isize).wrapping_pow(64u32) == 1isize) { panic("wrapping_pow #1709") }
    if !((-1isize).overflowing_pow(64u32).0 == 1isize && (-1isize).overflowing_pow(64u32).1 == false) { panic("overflowing_pow #1710") }
    if !((-1isize).saturating_pow(64u32) == 1isize) { panic("saturating_pow #1711") }
    if !((-1isize).pow(64u32) == 1isize) { panic("pow #1712") }
    if !((-1isize).strict_pow(64u32) == 1isize) { panic("strict_pow #1713") }
    if !(missing((-1isize).checked_ilog2())) { panic("checked_ilog2 #1714") }
    if !(missing((-1isize).checked_ilog10())) { panic("checked_ilog10 #1715") }
    if !(missing((-1isize).checked_ilog(2isize))) { panic("checked_ilog #1716") }
    if !(missing((-1isize).checked_isqrt())) { panic("checked_isqrt #1717") }
    if !((-1isize).highest_one() == present(63u32)) { panic("highest_one #1718") }
    if !((-1isize).lowest_one() == present(0u32)) { panic("lowest_one #1719") }
    if !((-1isize).isolate_highest_one() == isize.MIN) { panic("isolate_highest_one #1720") }
    if !((-1isize).isolate_lowest_one() == 1isize) { panic("isolate_lowest_one #1721") }
    if !(parsed(capture num.from_str_radix<isize>("9223372036854775807", 10u32)) == present(isize.MAX)) { panic("from_str_radix #1722") }
    if !(parsed(capture num.from_str_radix<isize>("7fffffffffffffff", 16u32)) == present(isize.MAX)) { panic("from_str_radix #1723") }
    if !(parsed(capture num.from_str_radix<isize>("111111111111111111111111111111111111111111111111111111111111111", 2u32)) == present(isize.MAX)) { panic("from_str_radix #1724") }
    if !(parsed(capture num.from_str_radix<isize>("1y2p0ij32e8e7", 36u32)) == present(isize.MAX)) { panic("from_str_radix #1725") }
    if !(parsed(capture num.from_str_radix<isize>("7FFFFFFFFFFFFFFF", 16u32)) == present(isize.MAX)) { panic("from_str_radix #1726") }
    if !(parsed(capture num.from_str_radix<isize>("-9223372036854775808", 10u32)) == present(isize.MIN)) { panic("from_str_radix #1727") }
    if !(parsed(capture num.from_str_radix<isize>("-8000000000000000", 16u32)) == present(isize.MIN)) { panic("from_str_radix #1728") }
    if !(parsed(capture num.from_str_radix<isize>("-1000000000000000000000000000000000000000000000000000000000000000", 2u32)) == present(isize.MIN)) { panic("from_str_radix #1729") }
    if !(parsed(capture num.from_str_radix<isize>("-1y2p0ij32e8e8", 36u32)) == present(isize.MIN)) { panic("from_str_radix #1730") }
    if !(parsed(capture num.from_str_radix<isize>("7", 10u32)) == present(7isize)) { panic("from_str_radix #1732") }
    if !(parsed(capture num.from_str_radix<isize>("7", 16u32)) == present(7isize)) { panic("from_str_radix #1733") }
    if !(parsed(capture num.from_str_radix<isize>("111", 2u32)) == present(7isize)) { panic("from_str_radix #1734") }
    if !(parsed(capture num.from_str_radix<isize>("7", 36u32)) == present(7isize)) { panic("from_str_radix #1735") }
    if !(parsed(capture num.from_str_radix<isize>("0", 10u32)) == present(0isize)) { panic("from_str_radix #1737") }
    if !(parsed(capture num.from_str_radix<isize>("0", 16u32)) == present(0isize)) { panic("from_str_radix #1738") }
    if !(parsed(capture num.from_str_radix<isize>("0", 2u32)) == present(0isize)) { panic("from_str_radix #1739") }
    if !(parsed(capture num.from_str_radix<isize>("0", 36u32)) == present(0isize)) { panic("from_str_radix #1740") }
    if !(parsed(capture num.from_str_radix<isize>("-7", 10u32)) == present((-7isize))) { panic("from_str_radix #1742") }
    if !(parsed(capture num.from_str_radix<isize>("-7", 16u32)) == present((-7isize))) { panic("from_str_radix #1743") }
    if !(parsed(capture num.from_str_radix<isize>("-111", 2u32)) == present((-7isize))) { panic("from_str_radix #1744") }
    if !(parsed(capture num.from_str_radix<isize>("-7", 36u32)) == present((-7isize))) { panic("from_str_radix #1745") }
    if !(parsed(capture num.from_str_radix<isize>("+7", 10u32)) == present(7isize)) { panic("from_str_radix #1747") }
    if !(kind(capture num.from_str_radix<isize>("", 10u32)) == present(IntErrorKind.Empty)) { panic("from_str_radix #1748") }
    if !(kind(capture num.from_str_radix<isize>("-", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1749") }
    if !(kind(capture num.from_str_radix<isize>("+", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1750") }
    if !(kind(capture num.from_str_radix<isize>("1_0", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1751") }
    if !(kind(capture num.from_str_radix<isize>("12", 2u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1752") }
    if !(kind(capture num.from_str_radix<isize>(" 1", 10u32)) == present(IntErrorKind.InvalidDigit)) { panic("from_str_radix #1753") }
    if !(kind(capture num.from_str_radix<isize>("9223372036854775808", 10u32)) == present(IntErrorKind.PosOverflow)) { panic("from_str_radix #1754") }
    if !(kind(capture num.from_str_radix<isize>("1", 37u32)) == present(IntErrorKind.InvalidRadix)) { panic("from_str_radix #1755") }
    if !(kind(capture num.from_str_radix<isize>("1", 1u32)) == present(IntErrorKind.InvalidRadix)) { panic("from_str_radix #1756") }
    if !(kind(capture num.from_str_radix<isize>("-9223372036854775809", 10u32)) == present(IntErrorKind.NegOverflow)) { panic("from_str_radix #1757") }
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
