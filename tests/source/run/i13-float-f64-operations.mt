// profiles: debug release
// Every stable f64 operation family; inputs and exact results are bit
// patterns. Correctly rounded operations match bit-for-bit; libm-backed
// functions are within a few ULP of a double-precision reference.
import core.cmp.{Ordering, PartialEq}
import core.float.FpCategory
import core.panic.panic

fn V(bits: u64): f64 { f64.from_bits(bits) }

fn ordered(value: f64): i64 {
    let raw = value.to_bits() as i64
    if raw < 0i64 { i64.MIN - raw } else { raw }
}

fn near(actual: f64, expected: f64, ulps: u64): bool {
    if actual.is_nan() || expected.is_nan() { return actual.is_nan() && expected.is_nan() }
    ordered(actual).abs_diff(ordered(expected)) <= ulps
}

fn group0() {
    if !(f64.MAX.to_bits() == 0x7fefffffffffffffu64) { panic("MAX #1") }
    if !(f64.MIN.to_bits() == 0xffefffffffffffffu64) { panic("MIN #2") }
    if !(f64.MIN_POSITIVE.to_bits() == 0x10000000000000u64) { panic("MIN_POSITIVE #3") }
    if !(f64.EPSILON.to_bits() == 0x3cb0000000000000u64) { panic("EPSILON #4") }
    if !(f64.INFINITY.to_bits() == 0x7ff0000000000000u64) { panic("INFINITY #5") }
    if !(f64.NEG_INFINITY.to_bits() == 0xfff0000000000000u64) { panic("NEG_INFINITY #6") }
    if !(f64.NAN.is_nan()) { panic("NAN #7") }
    if !(f64.DIGITS == 15u32) { panic("DIGITS #8") }
    if !(f64.MANTISSA_DIGITS == 53u32) { panic("MANTISSA_DIGITS #9") }
    if !(f64.RADIX == 2u32) { panic("RADIX #10") }
    if !(f64.MIN_EXP == (-1021i32)) { panic("MIN_EXP #11") }
    if !(f64.MAX_EXP == 1024i32) { panic("MAX_EXP #12") }
    if !(f64.MIN_10_EXP == (-307i32)) { panic("MIN_10_EXP #13") }
    if !(f64.MAX_10_EXP == 308i32) { panic("MAX_10_EXP #14") }
    if !(V(0x0u64).is_nan() == false) { panic("is_nan #15") }
    if !(V(0x0u64).is_infinite() == false) { panic("is_infinite #16") }
    if !(V(0x0u64).is_finite() == true) { panic("is_finite #17") }
    if !(V(0x0u64).is_normal() == false) { panic("is_normal #18") }
    if !(V(0x0u64).is_subnormal() == false) { panic("is_subnormal #19") }
    if !(V(0x0u64).is_sign_negative() == false) { panic("is_sign_negative #20") }
    if !(V(0x0u64).is_sign_positive() == true) { panic("is_sign_positive #21") }
    if !(V(0x0u64).classify() == FpCategory.Zero) { panic("classify #22") }
    if !(V(0x0u64).abs().to_bits() == 0x0u64) { panic("abs #23") }
    if !(V(0x0u64).floor().to_bits() == 0x0u64) { panic("floor #24") }
    if !(V(0x0u64).ceil().to_bits() == 0x0u64) { panic("ceil #25") }
    if !(V(0x0u64).trunc().to_bits() == 0x0u64) { panic("trunc #26") }
    if !(V(0x0u64).round().to_bits() == 0x0u64) { panic("round #27") }
    if !(V(0x0u64).round_ties_even().to_bits() == 0x0u64) { panic("round_ties_even #28") }
    if !(V(0x0u64).fract().to_bits() == 0x0u64) { panic("fract #29") }
    if !(V(0x0u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #30") }
    if !(V(0x0u64).recip().to_bits() == 0x7ff0000000000000u64) { panic("recip #31") }
    if !(V(0x0u64).sqrt().to_bits() == 0x0u64) { panic("sqrt #32") }
    if !(V(0x0u64).to_bits() == 0x0u64) { panic("to_bits #33") }
    if !(V(0x0u64).to_bits() == 0x0u64) { panic("to_bits #34") }
    if !(f64.from_bits(0x0u64).to_bits() == 0x0u64) { panic("from_bits #35") }
    if !(V(0x0u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #36") }
    if !(V(0x0u64).to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #37") }
    if !(V(0x0u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #38") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x0u64) { panic("from_le_bytes #39") }
    if !(f64.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x0u64) { panic("from_be_bytes #40") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x0u64) { panic("from_ne_bytes #41") }
    if !(V(0x0u64).next_up().to_bits() == 0x1u64) { panic("next_up #42") }
    if !(V(0x0u64).next_down().to_bits() == 0x8000000000000001u64) { panic("next_down #43") }
    if !(unsafe { V(0x0u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #44") }
    if !(V(0x0u64).total_cmp(V(0x0u64)) == Ordering.Equal) { panic("total_cmp #45") }
    if !(V(0x0u64).to_degrees().to_bits() == 0x0u64) { panic("to_degrees #46") }
    if !(V(0x8000000000000000u64).is_nan() == false) { panic("is_nan #47") }
    if !(V(0x8000000000000000u64).is_infinite() == false) { panic("is_infinite #48") }
    if !(V(0x8000000000000000u64).is_finite() == true) { panic("is_finite #49") }
    if !(V(0x8000000000000000u64).is_normal() == false) { panic("is_normal #50") }
    if !(V(0x8000000000000000u64).is_subnormal() == false) { panic("is_subnormal #51") }
    if !(V(0x8000000000000000u64).is_sign_negative() == true) { panic("is_sign_negative #52") }
    if !(V(0x8000000000000000u64).is_sign_positive() == false) { panic("is_sign_positive #53") }
    if !(V(0x8000000000000000u64).classify() == FpCategory.Zero) { panic("classify #54") }
    if !(V(0x8000000000000000u64).abs().to_bits() == 0x0u64) { panic("abs #55") }
    if !(V(0x8000000000000000u64).floor().to_bits() == 0x8000000000000000u64) { panic("floor #56") }
    if !(V(0x8000000000000000u64).ceil().to_bits() == 0x8000000000000000u64) { panic("ceil #57") }
    if !(V(0x8000000000000000u64).trunc().to_bits() == 0x8000000000000000u64) { panic("trunc #58") }
    if !(V(0x8000000000000000u64).round().to_bits() == 0x8000000000000000u64) { panic("round #59") }
    if !(V(0x8000000000000000u64).round_ties_even().to_bits() == 0x8000000000000000u64) { panic("round_ties_even #60") }
    if !(V(0x8000000000000000u64).fract().to_bits() == 0x0u64) { panic("fract #61") }
    if !(V(0x8000000000000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #62") }
    if !(V(0x8000000000000000u64).recip().to_bits() == 0xfff0000000000000u64) { panic("recip #63") }
    if !(V(0x8000000000000000u64).sqrt().to_bits() == 0x8000000000000000u64) { panic("sqrt #64") }
    if !(V(0x8000000000000000u64).to_bits() == 0x8000000000000000u64) { panic("to_bits #65") }
    if !(V(0x8000000000000000u64).to_bits() == 0x8000000000000000u64) { panic("to_bits #66") }
    if !(f64.from_bits(0x8000000000000000u64).to_bits() == 0x8000000000000000u64) { panic("from_bits #67") }
    if !(V(0x8000000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) { panic("to_le_bytes #68") }
    if !(V(0x8000000000000000u64).to_be_bytes() == [128u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #69") }
    if !(V(0x8000000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) { panic("to_ne_bytes #70") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]).to_bits() == 0x8000000000000000u64) { panic("from_le_bytes #71") }
    if !(f64.from_be_bytes([128u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x8000000000000000u64) { panic("from_be_bytes #72") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]).to_bits() == 0x8000000000000000u64) { panic("from_ne_bytes #73") }
    if !(V(0x8000000000000000u64).next_up().to_bits() == 0x1u64) { panic("next_up #74") }
    if !(V(0x8000000000000000u64).next_down().to_bits() == 0x8000000000000001u64) { panic("next_down #75") }
    if !(unsafe { V(0x8000000000000000u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #76") }
    if !(V(0x8000000000000000u64).total_cmp(V(0x8000000000000000u64)) == Ordering.Equal) { panic("total_cmp #77") }
    if !(V(0x8000000000000000u64).to_degrees().to_bits() == 0x8000000000000000u64) { panic("to_degrees #78") }
    if !(V(0x3ff0000000000000u64).is_nan() == false) { panic("is_nan #79") }
    if !(V(0x3ff0000000000000u64).is_infinite() == false) { panic("is_infinite #80") }
    if !(V(0x3ff0000000000000u64).is_finite() == true) { panic("is_finite #81") }
    if !(V(0x3ff0000000000000u64).is_normal() == true) { panic("is_normal #82") }
    if !(V(0x3ff0000000000000u64).is_subnormal() == false) { panic("is_subnormal #83") }
    if !(V(0x3ff0000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #84") }
    if !(V(0x3ff0000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #85") }
    if !(V(0x3ff0000000000000u64).classify() == FpCategory.Normal) { panic("classify #86") }
    if !(V(0x3ff0000000000000u64).abs().to_bits() == 0x3ff0000000000000u64) { panic("abs #87") }
    if !(V(0x3ff0000000000000u64).floor().to_bits() == 0x3ff0000000000000u64) { panic("floor #88") }
    if !(V(0x3ff0000000000000u64).ceil().to_bits() == 0x3ff0000000000000u64) { panic("ceil #89") }
    if !(V(0x3ff0000000000000u64).trunc().to_bits() == 0x3ff0000000000000u64) { panic("trunc #90") }
    if !(V(0x3ff0000000000000u64).round().to_bits() == 0x3ff0000000000000u64) { panic("round #91") }
    if !(V(0x3ff0000000000000u64).round_ties_even().to_bits() == 0x3ff0000000000000u64) { panic("round_ties_even #92") }
    if !(V(0x3ff0000000000000u64).fract().to_bits() == 0x0u64) { panic("fract #93") }
    if !(V(0x3ff0000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #94") }
    if !(V(0x3ff0000000000000u64).recip().to_bits() == 0x3ff0000000000000u64) { panic("recip #95") }
    if !(V(0x3ff0000000000000u64).sqrt().to_bits() == 0x3ff0000000000000u64) { panic("sqrt #96") }
    if !(V(0x3ff0000000000000u64).to_bits() == 0x3ff0000000000000u64) { panic("to_bits #97") }
    if !(V(0x3ff0000000000000u64).to_bits() == 0x3ff0000000000000u64) { panic("to_bits #98") }
    if !(f64.from_bits(0x3ff0000000000000u64).to_bits() == 0x3ff0000000000000u64) { panic("from_bits #99") }
    if !(V(0x3ff0000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 63u8]) { panic("to_le_bytes #100") }
    if !(V(0x3ff0000000000000u64).to_be_bytes() == [63u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #101") }
    if !(V(0x3ff0000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 63u8]) { panic("to_ne_bytes #102") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 63u8]).to_bits() == 0x3ff0000000000000u64) { panic("from_le_bytes #103") }
    if !(f64.from_be_bytes([63u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x3ff0000000000000u64) { panic("from_be_bytes #104") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 63u8]).to_bits() == 0x3ff0000000000000u64) { panic("from_ne_bytes #105") }
    if !(V(0x3ff0000000000000u64).next_up().to_bits() == 0x3ff0000000000001u64) { panic("next_up #106") }
    if !(V(0x3ff0000000000000u64).next_down().to_bits() == 0x3fefffffffffffffu64) { panic("next_down #107") }
    if !(unsafe { V(0x3ff0000000000000u64).to_int_unchecked<i32>() } == 1i32) { panic("to_int_unchecked #108") }
    if !(V(0x3ff0000000000000u64).total_cmp(V(0x3ff0000000000000u64)) == Ordering.Equal) { panic("total_cmp #109") }
    if !(V(0xbff0000000000000u64).is_nan() == false) { panic("is_nan #110") }
    if !(V(0xbff0000000000000u64).is_infinite() == false) { panic("is_infinite #111") }
    if !(V(0xbff0000000000000u64).is_finite() == true) { panic("is_finite #112") }
    if !(V(0xbff0000000000000u64).is_normal() == true) { panic("is_normal #113") }
    if !(V(0xbff0000000000000u64).is_subnormal() == false) { panic("is_subnormal #114") }
    if !(V(0xbff0000000000000u64).is_sign_negative() == true) { panic("is_sign_negative #115") }
    if !(V(0xbff0000000000000u64).is_sign_positive() == false) { panic("is_sign_positive #116") }
    if !(V(0xbff0000000000000u64).classify() == FpCategory.Normal) { panic("classify #117") }
    if !(V(0xbff0000000000000u64).abs().to_bits() == 0x3ff0000000000000u64) { panic("abs #118") }
    if !(V(0xbff0000000000000u64).floor().to_bits() == 0xbff0000000000000u64) { panic("floor #119") }
    if !(V(0xbff0000000000000u64).ceil().to_bits() == 0xbff0000000000000u64) { panic("ceil #120") }
}

fn group1() {
    if !(V(0xbff0000000000000u64).trunc().to_bits() == 0xbff0000000000000u64) { panic("trunc #121") }
    if !(V(0xbff0000000000000u64).round().to_bits() == 0xbff0000000000000u64) { panic("round #122") }
    if !(V(0xbff0000000000000u64).round_ties_even().to_bits() == 0xbff0000000000000u64) { panic("round_ties_even #123") }
    if !(V(0xbff0000000000000u64).fract().to_bits() == 0x0u64) { panic("fract #124") }
    if !(V(0xbff0000000000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #125") }
    if !(V(0xbff0000000000000u64).recip().to_bits() == 0xbff0000000000000u64) { panic("recip #126") }
    if !(V(0xbff0000000000000u64).sqrt().is_nan()) { panic("sqrt #127") }
    if !(V(0xbff0000000000000u64).to_bits() == 0xbff0000000000000u64) { panic("to_bits #128") }
    if !(V(0xbff0000000000000u64).to_bits() == 0xbff0000000000000u64) { panic("to_bits #129") }
    if !(f64.from_bits(0xbff0000000000000u64).to_bits() == 0xbff0000000000000u64) { panic("from_bits #130") }
    if !(V(0xbff0000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 191u8]) { panic("to_le_bytes #131") }
    if !(V(0xbff0000000000000u64).to_be_bytes() == [191u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #132") }
    if !(V(0xbff0000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 191u8]) { panic("to_ne_bytes #133") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 191u8]).to_bits() == 0xbff0000000000000u64) { panic("from_le_bytes #134") }
    if !(f64.from_be_bytes([191u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0xbff0000000000000u64) { panic("from_be_bytes #135") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 191u8]).to_bits() == 0xbff0000000000000u64) { panic("from_ne_bytes #136") }
    if !(V(0xbff0000000000000u64).next_up().to_bits() == 0xbfefffffffffffffu64) { panic("next_up #137") }
    if !(V(0xbff0000000000000u64).next_down().to_bits() == 0xbff0000000000001u64) { panic("next_down #138") }
    if !(unsafe { V(0xbff0000000000000u64).to_int_unchecked<i32>() } == (-1i32)) { panic("to_int_unchecked #139") }
    if !(V(0xbff0000000000000u64).total_cmp(V(0xbff0000000000000u64)) == Ordering.Equal) { panic("total_cmp #140") }
    if !(V(0x3fe0000000000000u64).is_nan() == false) { panic("is_nan #141") }
    if !(V(0x3fe0000000000000u64).is_infinite() == false) { panic("is_infinite #142") }
    if !(V(0x3fe0000000000000u64).is_finite() == true) { panic("is_finite #143") }
    if !(V(0x3fe0000000000000u64).is_normal() == true) { panic("is_normal #144") }
    if !(V(0x3fe0000000000000u64).is_subnormal() == false) { panic("is_subnormal #145") }
    if !(V(0x3fe0000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #146") }
    if !(V(0x3fe0000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #147") }
    if !(V(0x3fe0000000000000u64).classify() == FpCategory.Normal) { panic("classify #148") }
    if !(V(0x3fe0000000000000u64).abs().to_bits() == 0x3fe0000000000000u64) { panic("abs #149") }
    if !(V(0x3fe0000000000000u64).floor().to_bits() == 0x0u64) { panic("floor #150") }
    if !(V(0x3fe0000000000000u64).ceil().to_bits() == 0x3ff0000000000000u64) { panic("ceil #151") }
    if !(V(0x3fe0000000000000u64).trunc().to_bits() == 0x0u64) { panic("trunc #152") }
    if !(V(0x3fe0000000000000u64).round().to_bits() == 0x3ff0000000000000u64) { panic("round #153") }
    if !(V(0x3fe0000000000000u64).round_ties_even().to_bits() == 0x0u64) { panic("round_ties_even #154") }
    if !(V(0x3fe0000000000000u64).fract().to_bits() == 0x3fe0000000000000u64) { panic("fract #155") }
    if !(V(0x3fe0000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #156") }
    if !(V(0x3fe0000000000000u64).recip().to_bits() == 0x4000000000000000u64) { panic("recip #157") }
    if !(V(0x3fe0000000000000u64).sqrt().to_bits() == 0x3fe6a09e667f3bcdu64) { panic("sqrt #158") }
    if !(V(0x3fe0000000000000u64).to_bits() == 0x3fe0000000000000u64) { panic("to_bits #159") }
    if !(V(0x3fe0000000000000u64).to_bits() == 0x3fe0000000000000u64) { panic("to_bits #160") }
    if !(f64.from_bits(0x3fe0000000000000u64).to_bits() == 0x3fe0000000000000u64) { panic("from_bits #161") }
    if !(V(0x3fe0000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 63u8]) { panic("to_le_bytes #162") }
    if !(V(0x3fe0000000000000u64).to_be_bytes() == [63u8, 224u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #163") }
    if !(V(0x3fe0000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 63u8]) { panic("to_ne_bytes #164") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 63u8]).to_bits() == 0x3fe0000000000000u64) { panic("from_le_bytes #165") }
    if !(f64.from_be_bytes([63u8, 224u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x3fe0000000000000u64) { panic("from_be_bytes #166") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 63u8]).to_bits() == 0x3fe0000000000000u64) { panic("from_ne_bytes #167") }
    if !(V(0x3fe0000000000000u64).next_up().to_bits() == 0x3fe0000000000001u64) { panic("next_up #168") }
    if !(V(0x3fe0000000000000u64).next_down().to_bits() == 0x3fdfffffffffffffu64) { panic("next_down #169") }
    if !(unsafe { V(0x3fe0000000000000u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #170") }
    if !(V(0x3fe0000000000000u64).total_cmp(V(0x3fe0000000000000u64)) == Ordering.Equal) { panic("total_cmp #171") }
    if !(V(0xbfe0000000000000u64).is_nan() == false) { panic("is_nan #172") }
    if !(V(0xbfe0000000000000u64).is_infinite() == false) { panic("is_infinite #173") }
    if !(V(0xbfe0000000000000u64).is_finite() == true) { panic("is_finite #174") }
    if !(V(0xbfe0000000000000u64).is_normal() == true) { panic("is_normal #175") }
    if !(V(0xbfe0000000000000u64).is_subnormal() == false) { panic("is_subnormal #176") }
    if !(V(0xbfe0000000000000u64).is_sign_negative() == true) { panic("is_sign_negative #177") }
    if !(V(0xbfe0000000000000u64).is_sign_positive() == false) { panic("is_sign_positive #178") }
    if !(V(0xbfe0000000000000u64).classify() == FpCategory.Normal) { panic("classify #179") }
    if !(V(0xbfe0000000000000u64).abs().to_bits() == 0x3fe0000000000000u64) { panic("abs #180") }
    if !(V(0xbfe0000000000000u64).floor().to_bits() == 0xbff0000000000000u64) { panic("floor #181") }
    if !(V(0xbfe0000000000000u64).ceil().to_bits() == 0x8000000000000000u64) { panic("ceil #182") }
    if !(V(0xbfe0000000000000u64).trunc().to_bits() == 0x8000000000000000u64) { panic("trunc #183") }
    if !(V(0xbfe0000000000000u64).round().to_bits() == 0xbff0000000000000u64) { panic("round #184") }
    if !(V(0xbfe0000000000000u64).round_ties_even().to_bits() == 0x8000000000000000u64) { panic("round_ties_even #185") }
    if !(V(0xbfe0000000000000u64).fract().to_bits() == 0xbfe0000000000000u64) { panic("fract #186") }
    if !(V(0xbfe0000000000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #187") }
    if !(V(0xbfe0000000000000u64).recip().to_bits() == 0xc000000000000000u64) { panic("recip #188") }
    if !(V(0xbfe0000000000000u64).sqrt().is_nan()) { panic("sqrt #189") }
    if !(V(0xbfe0000000000000u64).to_bits() == 0xbfe0000000000000u64) { panic("to_bits #190") }
    if !(V(0xbfe0000000000000u64).to_bits() == 0xbfe0000000000000u64) { panic("to_bits #191") }
    if !(f64.from_bits(0xbfe0000000000000u64).to_bits() == 0xbfe0000000000000u64) { panic("from_bits #192") }
    if !(V(0xbfe0000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 191u8]) { panic("to_le_bytes #193") }
    if !(V(0xbfe0000000000000u64).to_be_bytes() == [191u8, 224u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #194") }
    if !(V(0xbfe0000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 191u8]) { panic("to_ne_bytes #195") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 191u8]).to_bits() == 0xbfe0000000000000u64) { panic("from_le_bytes #196") }
    if !(f64.from_be_bytes([191u8, 224u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0xbfe0000000000000u64) { panic("from_be_bytes #197") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 224u8, 191u8]).to_bits() == 0xbfe0000000000000u64) { panic("from_ne_bytes #198") }
    if !(V(0xbfe0000000000000u64).next_up().to_bits() == 0xbfdfffffffffffffu64) { panic("next_up #199") }
    if !(V(0xbfe0000000000000u64).next_down().to_bits() == 0xbfe0000000000001u64) { panic("next_down #200") }
    if !(unsafe { V(0xbfe0000000000000u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #201") }
    if !(V(0xbfe0000000000000u64).total_cmp(V(0xbfe0000000000000u64)) == Ordering.Equal) { panic("total_cmp #202") }
    if !(V(0x3ff8000000000000u64).is_nan() == false) { panic("is_nan #203") }
    if !(V(0x3ff8000000000000u64).is_infinite() == false) { panic("is_infinite #204") }
    if !(V(0x3ff8000000000000u64).is_finite() == true) { panic("is_finite #205") }
    if !(V(0x3ff8000000000000u64).is_normal() == true) { panic("is_normal #206") }
    if !(V(0x3ff8000000000000u64).is_subnormal() == false) { panic("is_subnormal #207") }
    if !(V(0x3ff8000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #208") }
    if !(V(0x3ff8000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #209") }
    if !(V(0x3ff8000000000000u64).classify() == FpCategory.Normal) { panic("classify #210") }
    if !(V(0x3ff8000000000000u64).abs().to_bits() == 0x3ff8000000000000u64) { panic("abs #211") }
    if !(V(0x3ff8000000000000u64).floor().to_bits() == 0x3ff0000000000000u64) { panic("floor #212") }
    if !(V(0x3ff8000000000000u64).ceil().to_bits() == 0x4000000000000000u64) { panic("ceil #213") }
    if !(V(0x3ff8000000000000u64).trunc().to_bits() == 0x3ff0000000000000u64) { panic("trunc #214") }
    if !(V(0x3ff8000000000000u64).round().to_bits() == 0x4000000000000000u64) { panic("round #215") }
    if !(V(0x3ff8000000000000u64).round_ties_even().to_bits() == 0x4000000000000000u64) { panic("round_ties_even #216") }
    if !(V(0x3ff8000000000000u64).fract().to_bits() == 0x3fe0000000000000u64) { panic("fract #217") }
    if !(V(0x3ff8000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #218") }
    if !(V(0x3ff8000000000000u64).recip().to_bits() == 0x3fe5555555555555u64) { panic("recip #219") }
    if !(V(0x3ff8000000000000u64).sqrt().to_bits() == 0x3ff3988e1409212eu64) { panic("sqrt #220") }
    if !(V(0x3ff8000000000000u64).to_bits() == 0x3ff8000000000000u64) { panic("to_bits #221") }
    if !(V(0x3ff8000000000000u64).to_bits() == 0x3ff8000000000000u64) { panic("to_bits #222") }
    if !(f64.from_bits(0x3ff8000000000000u64).to_bits() == 0x3ff8000000000000u64) { panic("from_bits #223") }
    if !(V(0x3ff8000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 63u8]) { panic("to_le_bytes #224") }
    if !(V(0x3ff8000000000000u64).to_be_bytes() == [63u8, 248u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #225") }
    if !(V(0x3ff8000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 63u8]) { panic("to_ne_bytes #226") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 63u8]).to_bits() == 0x3ff8000000000000u64) { panic("from_le_bytes #227") }
    if !(f64.from_be_bytes([63u8, 248u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x3ff8000000000000u64) { panic("from_be_bytes #228") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 63u8]).to_bits() == 0x3ff8000000000000u64) { panic("from_ne_bytes #229") }
    if !(V(0x3ff8000000000000u64).next_up().to_bits() == 0x3ff8000000000001u64) { panic("next_up #230") }
    if !(V(0x3ff8000000000000u64).next_down().to_bits() == 0x3ff7ffffffffffffu64) { panic("next_down #231") }
    if !(unsafe { V(0x3ff8000000000000u64).to_int_unchecked<i32>() } == 1i32) { panic("to_int_unchecked #232") }
    if !(V(0x3ff8000000000000u64).total_cmp(V(0x3ff8000000000000u64)) == Ordering.Equal) { panic("total_cmp #233") }
    if !(V(0x4004000000000000u64).is_nan() == false) { panic("is_nan #234") }
    if !(V(0x4004000000000000u64).is_infinite() == false) { panic("is_infinite #235") }
    if !(V(0x4004000000000000u64).is_finite() == true) { panic("is_finite #236") }
    if !(V(0x4004000000000000u64).is_normal() == true) { panic("is_normal #237") }
    if !(V(0x4004000000000000u64).is_subnormal() == false) { panic("is_subnormal #238") }
    if !(V(0x4004000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #239") }
    if !(V(0x4004000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #240") }
}

fn group2() {
    if !(V(0x4004000000000000u64).classify() == FpCategory.Normal) { panic("classify #241") }
    if !(V(0x4004000000000000u64).abs().to_bits() == 0x4004000000000000u64) { panic("abs #242") }
    if !(V(0x4004000000000000u64).floor().to_bits() == 0x4000000000000000u64) { panic("floor #243") }
    if !(V(0x4004000000000000u64).ceil().to_bits() == 0x4008000000000000u64) { panic("ceil #244") }
    if !(V(0x4004000000000000u64).trunc().to_bits() == 0x4000000000000000u64) { panic("trunc #245") }
    if !(V(0x4004000000000000u64).round().to_bits() == 0x4008000000000000u64) { panic("round #246") }
    if !(V(0x4004000000000000u64).round_ties_even().to_bits() == 0x4000000000000000u64) { panic("round_ties_even #247") }
    if !(V(0x4004000000000000u64).fract().to_bits() == 0x3fe0000000000000u64) { panic("fract #248") }
    if !(V(0x4004000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #249") }
    if !(V(0x4004000000000000u64).recip().to_bits() == 0x3fd999999999999au64) { panic("recip #250") }
    if !(V(0x4004000000000000u64).sqrt().to_bits() == 0x3ff94c583ada5b53u64) { panic("sqrt #251") }
    if !(V(0x4004000000000000u64).to_bits() == 0x4004000000000000u64) { panic("to_bits #252") }
    if !(V(0x4004000000000000u64).to_bits() == 0x4004000000000000u64) { panic("to_bits #253") }
    if !(f64.from_bits(0x4004000000000000u64).to_bits() == 0x4004000000000000u64) { panic("from_bits #254") }
    if !(V(0x4004000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 64u8]) { panic("to_le_bytes #255") }
    if !(V(0x4004000000000000u64).to_be_bytes() == [64u8, 4u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #256") }
    if !(V(0x4004000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 64u8]) { panic("to_ne_bytes #257") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 64u8]).to_bits() == 0x4004000000000000u64) { panic("from_le_bytes #258") }
    if !(f64.from_be_bytes([64u8, 4u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x4004000000000000u64) { panic("from_be_bytes #259") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 64u8]).to_bits() == 0x4004000000000000u64) { panic("from_ne_bytes #260") }
    if !(V(0x4004000000000000u64).next_up().to_bits() == 0x4004000000000001u64) { panic("next_up #261") }
    if !(V(0x4004000000000000u64).next_down().to_bits() == 0x4003ffffffffffffu64) { panic("next_down #262") }
    if !(unsafe { V(0x4004000000000000u64).to_int_unchecked<i32>() } == 2i32) { panic("to_int_unchecked #263") }
    if !(V(0x4004000000000000u64).total_cmp(V(0x4004000000000000u64)) == Ordering.Equal) { panic("total_cmp #264") }
    if !(V(0xc004000000000000u64).is_nan() == false) { panic("is_nan #265") }
    if !(V(0xc004000000000000u64).is_infinite() == false) { panic("is_infinite #266") }
    if !(V(0xc004000000000000u64).is_finite() == true) { panic("is_finite #267") }
    if !(V(0xc004000000000000u64).is_normal() == true) { panic("is_normal #268") }
    if !(V(0xc004000000000000u64).is_subnormal() == false) { panic("is_subnormal #269") }
    if !(V(0xc004000000000000u64).is_sign_negative() == true) { panic("is_sign_negative #270") }
    if !(V(0xc004000000000000u64).is_sign_positive() == false) { panic("is_sign_positive #271") }
    if !(V(0xc004000000000000u64).classify() == FpCategory.Normal) { panic("classify #272") }
    if !(V(0xc004000000000000u64).abs().to_bits() == 0x4004000000000000u64) { panic("abs #273") }
    if !(V(0xc004000000000000u64).floor().to_bits() == 0xc008000000000000u64) { panic("floor #274") }
    if !(V(0xc004000000000000u64).ceil().to_bits() == 0xc000000000000000u64) { panic("ceil #275") }
    if !(V(0xc004000000000000u64).trunc().to_bits() == 0xc000000000000000u64) { panic("trunc #276") }
    if !(V(0xc004000000000000u64).round().to_bits() == 0xc008000000000000u64) { panic("round #277") }
    if !(V(0xc004000000000000u64).round_ties_even().to_bits() == 0xc000000000000000u64) { panic("round_ties_even #278") }
    if !(V(0xc004000000000000u64).fract().to_bits() == 0xbfe0000000000000u64) { panic("fract #279") }
    if !(V(0xc004000000000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #280") }
    if !(V(0xc004000000000000u64).recip().to_bits() == 0xbfd999999999999au64) { panic("recip #281") }
    if !(V(0xc004000000000000u64).sqrt().is_nan()) { panic("sqrt #282") }
    if !(V(0xc004000000000000u64).to_bits() == 0xc004000000000000u64) { panic("to_bits #283") }
    if !(V(0xc004000000000000u64).to_bits() == 0xc004000000000000u64) { panic("to_bits #284") }
    if !(f64.from_bits(0xc004000000000000u64).to_bits() == 0xc004000000000000u64) { panic("from_bits #285") }
    if !(V(0xc004000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 192u8]) { panic("to_le_bytes #286") }
    if !(V(0xc004000000000000u64).to_be_bytes() == [192u8, 4u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #287") }
    if !(V(0xc004000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 192u8]) { panic("to_ne_bytes #288") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 192u8]).to_bits() == 0xc004000000000000u64) { panic("from_le_bytes #289") }
    if !(f64.from_be_bytes([192u8, 4u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0xc004000000000000u64) { panic("from_be_bytes #290") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 4u8, 192u8]).to_bits() == 0xc004000000000000u64) { panic("from_ne_bytes #291") }
    if !(V(0xc004000000000000u64).next_up().to_bits() == 0xc003ffffffffffffu64) { panic("next_up #292") }
    if !(V(0xc004000000000000u64).next_down().to_bits() == 0xc004000000000001u64) { panic("next_down #293") }
    if !(unsafe { V(0xc004000000000000u64).to_int_unchecked<i32>() } == (-2i32)) { panic("to_int_unchecked #294") }
    if !(V(0xc004000000000000u64).total_cmp(V(0xc004000000000000u64)) == Ordering.Equal) { panic("total_cmp #295") }
    if !(V(0x400e000000000000u64).is_nan() == false) { panic("is_nan #296") }
    if !(V(0x400e000000000000u64).is_infinite() == false) { panic("is_infinite #297") }
    if !(V(0x400e000000000000u64).is_finite() == true) { panic("is_finite #298") }
    if !(V(0x400e000000000000u64).is_normal() == true) { panic("is_normal #299") }
    if !(V(0x400e000000000000u64).is_subnormal() == false) { panic("is_subnormal #300") }
    if !(V(0x400e000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #301") }
    if !(V(0x400e000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #302") }
    if !(V(0x400e000000000000u64).classify() == FpCategory.Normal) { panic("classify #303") }
    if !(V(0x400e000000000000u64).abs().to_bits() == 0x400e000000000000u64) { panic("abs #304") }
    if !(V(0x400e000000000000u64).floor().to_bits() == 0x4008000000000000u64) { panic("floor #305") }
    if !(V(0x400e000000000000u64).ceil().to_bits() == 0x4010000000000000u64) { panic("ceil #306") }
    if !(V(0x400e000000000000u64).trunc().to_bits() == 0x4008000000000000u64) { panic("trunc #307") }
    if !(V(0x400e000000000000u64).round().to_bits() == 0x4010000000000000u64) { panic("round #308") }
    if !(V(0x400e000000000000u64).round_ties_even().to_bits() == 0x4010000000000000u64) { panic("round_ties_even #309") }
    if !(V(0x400e000000000000u64).fract().to_bits() == 0x3fe8000000000000u64) { panic("fract #310") }
    if !(V(0x400e000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #311") }
    if !(V(0x400e000000000000u64).recip().to_bits() == 0x3fd1111111111111u64) { panic("recip #312") }
    if !(V(0x400e000000000000u64).sqrt().to_bits() == 0x3ffefbdeb14f4edau64) { panic("sqrt #313") }
    if !(V(0x400e000000000000u64).to_bits() == 0x400e000000000000u64) { panic("to_bits #314") }
    if !(V(0x400e000000000000u64).to_bits() == 0x400e000000000000u64) { panic("to_bits #315") }
    if !(f64.from_bits(0x400e000000000000u64).to_bits() == 0x400e000000000000u64) { panic("from_bits #316") }
    if !(V(0x400e000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 64u8]) { panic("to_le_bytes #317") }
    if !(V(0x400e000000000000u64).to_be_bytes() == [64u8, 14u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #318") }
    if !(V(0x400e000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 64u8]) { panic("to_ne_bytes #319") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 64u8]).to_bits() == 0x400e000000000000u64) { panic("from_le_bytes #320") }
    if !(f64.from_be_bytes([64u8, 14u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x400e000000000000u64) { panic("from_be_bytes #321") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 64u8]).to_bits() == 0x400e000000000000u64) { panic("from_ne_bytes #322") }
    if !(V(0x400e000000000000u64).next_up().to_bits() == 0x400e000000000001u64) { panic("next_up #323") }
    if !(V(0x400e000000000000u64).next_down().to_bits() == 0x400dffffffffffffu64) { panic("next_down #324") }
    if !(unsafe { V(0x400e000000000000u64).to_int_unchecked<i32>() } == 3i32) { panic("to_int_unchecked #325") }
    if !(V(0x400e000000000000u64).total_cmp(V(0x400e000000000000u64)) == Ordering.Equal) { panic("total_cmp #326") }
    if !(V(0xc00e000000000000u64).is_nan() == false) { panic("is_nan #327") }
    if !(V(0xc00e000000000000u64).is_infinite() == false) { panic("is_infinite #328") }
    if !(V(0xc00e000000000000u64).is_finite() == true) { panic("is_finite #329") }
    if !(V(0xc00e000000000000u64).is_normal() == true) { panic("is_normal #330") }
    if !(V(0xc00e000000000000u64).is_subnormal() == false) { panic("is_subnormal #331") }
    if !(V(0xc00e000000000000u64).is_sign_negative() == true) { panic("is_sign_negative #332") }
    if !(V(0xc00e000000000000u64).is_sign_positive() == false) { panic("is_sign_positive #333") }
    if !(V(0xc00e000000000000u64).classify() == FpCategory.Normal) { panic("classify #334") }
    if !(V(0xc00e000000000000u64).abs().to_bits() == 0x400e000000000000u64) { panic("abs #335") }
    if !(V(0xc00e000000000000u64).floor().to_bits() == 0xc010000000000000u64) { panic("floor #336") }
    if !(V(0xc00e000000000000u64).ceil().to_bits() == 0xc008000000000000u64) { panic("ceil #337") }
    if !(V(0xc00e000000000000u64).trunc().to_bits() == 0xc008000000000000u64) { panic("trunc #338") }
    if !(V(0xc00e000000000000u64).round().to_bits() == 0xc010000000000000u64) { panic("round #339") }
    if !(V(0xc00e000000000000u64).round_ties_even().to_bits() == 0xc010000000000000u64) { panic("round_ties_even #340") }
    if !(V(0xc00e000000000000u64).fract().to_bits() == 0xbfe8000000000000u64) { panic("fract #341") }
    if !(V(0xc00e000000000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #342") }
    if !(V(0xc00e000000000000u64).recip().to_bits() == 0xbfd1111111111111u64) { panic("recip #343") }
    if !(V(0xc00e000000000000u64).sqrt().is_nan()) { panic("sqrt #344") }
    if !(V(0xc00e000000000000u64).to_bits() == 0xc00e000000000000u64) { panic("to_bits #345") }
    if !(V(0xc00e000000000000u64).to_bits() == 0xc00e000000000000u64) { panic("to_bits #346") }
    if !(f64.from_bits(0xc00e000000000000u64).to_bits() == 0xc00e000000000000u64) { panic("from_bits #347") }
    if !(V(0xc00e000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 192u8]) { panic("to_le_bytes #348") }
    if !(V(0xc00e000000000000u64).to_be_bytes() == [192u8, 14u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #349") }
    if !(V(0xc00e000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 192u8]) { panic("to_ne_bytes #350") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 192u8]).to_bits() == 0xc00e000000000000u64) { panic("from_le_bytes #351") }
    if !(f64.from_be_bytes([192u8, 14u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0xc00e000000000000u64) { panic("from_be_bytes #352") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 14u8, 192u8]).to_bits() == 0xc00e000000000000u64) { panic("from_ne_bytes #353") }
    if !(V(0xc00e000000000000u64).next_up().to_bits() == 0xc00dffffffffffffu64) { panic("next_up #354") }
    if !(V(0xc00e000000000000u64).next_down().to_bits() == 0xc00e000000000001u64) { panic("next_down #355") }
    if !(unsafe { V(0xc00e000000000000u64).to_int_unchecked<i32>() } == (-3i32)) { panic("to_int_unchecked #356") }
    if !(V(0xc00e000000000000u64).total_cmp(V(0xc00e000000000000u64)) == Ordering.Equal) { panic("total_cmp #357") }
    if !(V(0x3fb999999999999au64).is_nan() == false) { panic("is_nan #358") }
    if !(V(0x3fb999999999999au64).is_infinite() == false) { panic("is_infinite #359") }
    if !(V(0x3fb999999999999au64).is_finite() == true) { panic("is_finite #360") }
}

fn group3() {
    if !(V(0x3fb999999999999au64).is_normal() == true) { panic("is_normal #361") }
    if !(V(0x3fb999999999999au64).is_subnormal() == false) { panic("is_subnormal #362") }
    if !(V(0x3fb999999999999au64).is_sign_negative() == false) { panic("is_sign_negative #363") }
    if !(V(0x3fb999999999999au64).is_sign_positive() == true) { panic("is_sign_positive #364") }
    if !(V(0x3fb999999999999au64).classify() == FpCategory.Normal) { panic("classify #365") }
    if !(V(0x3fb999999999999au64).abs().to_bits() == 0x3fb999999999999au64) { panic("abs #366") }
    if !(V(0x3fb999999999999au64).floor().to_bits() == 0x0u64) { panic("floor #367") }
    if !(V(0x3fb999999999999au64).ceil().to_bits() == 0x3ff0000000000000u64) { panic("ceil #368") }
    if !(V(0x3fb999999999999au64).trunc().to_bits() == 0x0u64) { panic("trunc #369") }
    if !(V(0x3fb999999999999au64).round().to_bits() == 0x0u64) { panic("round #370") }
    if !(V(0x3fb999999999999au64).round_ties_even().to_bits() == 0x0u64) { panic("round_ties_even #371") }
    if !(V(0x3fb999999999999au64).fract().to_bits() == 0x3fb999999999999au64) { panic("fract #372") }
    if !(V(0x3fb999999999999au64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #373") }
    if !(V(0x3fb999999999999au64).recip().to_bits() == 0x4024000000000000u64) { panic("recip #374") }
    if !(V(0x3fb999999999999au64).sqrt().to_bits() == 0x3fd43d136248490fu64) { panic("sqrt #375") }
    if !(V(0x3fb999999999999au64).to_bits() == 0x3fb999999999999au64) { panic("to_bits #376") }
    if !(V(0x3fb999999999999au64).to_bits() == 0x3fb999999999999au64) { panic("to_bits #377") }
    if !(f64.from_bits(0x3fb999999999999au64).to_bits() == 0x3fb999999999999au64) { panic("from_bits #378") }
    if !(V(0x3fb999999999999au64).to_le_bytes() == [154u8, 153u8, 153u8, 153u8, 153u8, 153u8, 185u8, 63u8]) { panic("to_le_bytes #379") }
    if !(V(0x3fb999999999999au64).to_be_bytes() == [63u8, 185u8, 153u8, 153u8, 153u8, 153u8, 153u8, 154u8]) { panic("to_be_bytes #380") }
    if !(V(0x3fb999999999999au64).to_ne_bytes() == [154u8, 153u8, 153u8, 153u8, 153u8, 153u8, 185u8, 63u8]) { panic("to_ne_bytes #381") }
    if !(f64.from_le_bytes([154u8, 153u8, 153u8, 153u8, 153u8, 153u8, 185u8, 63u8]).to_bits() == 0x3fb999999999999au64) { panic("from_le_bytes #382") }
    if !(f64.from_be_bytes([63u8, 185u8, 153u8, 153u8, 153u8, 153u8, 153u8, 154u8]).to_bits() == 0x3fb999999999999au64) { panic("from_be_bytes #383") }
    if !(f64.from_ne_bytes([154u8, 153u8, 153u8, 153u8, 153u8, 153u8, 185u8, 63u8]).to_bits() == 0x3fb999999999999au64) { panic("from_ne_bytes #384") }
    if !(V(0x3fb999999999999au64).next_up().to_bits() == 0x3fb999999999999bu64) { panic("next_up #385") }
    if !(V(0x3fb999999999999au64).next_down().to_bits() == 0x3fb9999999999999u64) { panic("next_down #386") }
    if !(unsafe { V(0x3fb999999999999au64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #387") }
    if !(V(0x3fb999999999999au64).total_cmp(V(0x3fb999999999999au64)) == Ordering.Equal) { panic("total_cmp #388") }
    if !(V(0x4202a05f20000000u64).is_nan() == false) { panic("is_nan #389") }
    if !(V(0x4202a05f20000000u64).is_infinite() == false) { panic("is_infinite #390") }
    if !(V(0x4202a05f20000000u64).is_finite() == true) { panic("is_finite #391") }
    if !(V(0x4202a05f20000000u64).is_normal() == true) { panic("is_normal #392") }
    if !(V(0x4202a05f20000000u64).is_subnormal() == false) { panic("is_subnormal #393") }
    if !(V(0x4202a05f20000000u64).is_sign_negative() == false) { panic("is_sign_negative #394") }
    if !(V(0x4202a05f20000000u64).is_sign_positive() == true) { panic("is_sign_positive #395") }
    if !(V(0x4202a05f20000000u64).classify() == FpCategory.Normal) { panic("classify #396") }
    if !(V(0x4202a05f20000000u64).abs().to_bits() == 0x4202a05f20000000u64) { panic("abs #397") }
    if !(V(0x4202a05f20000000u64).floor().to_bits() == 0x4202a05f20000000u64) { panic("floor #398") }
    if !(V(0x4202a05f20000000u64).ceil().to_bits() == 0x4202a05f20000000u64) { panic("ceil #399") }
    if !(V(0x4202a05f20000000u64).trunc().to_bits() == 0x4202a05f20000000u64) { panic("trunc #400") }
    if !(V(0x4202a05f20000000u64).round().to_bits() == 0x4202a05f20000000u64) { panic("round #401") }
    if !(V(0x4202a05f20000000u64).round_ties_even().to_bits() == 0x4202a05f20000000u64) { panic("round_ties_even #402") }
    if !(V(0x4202a05f20000000u64).fract().to_bits() == 0x0u64) { panic("fract #403") }
    if !(V(0x4202a05f20000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #404") }
    if !(V(0x4202a05f20000000u64).recip().to_bits() == 0x3ddb7cdfd9d7bdbbu64) { panic("recip #405") }
    if !(V(0x4202a05f20000000u64).sqrt().to_bits() == 0x40f86a0000000000u64) { panic("sqrt #406") }
    if !(V(0x4202a05f20000000u64).to_bits() == 0x4202a05f20000000u64) { panic("to_bits #407") }
    if !(V(0x4202a05f20000000u64).to_bits() == 0x4202a05f20000000u64) { panic("to_bits #408") }
    if !(f64.from_bits(0x4202a05f20000000u64).to_bits() == 0x4202a05f20000000u64) { panic("from_bits #409") }
    if !(V(0x4202a05f20000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 66u8]) { panic("to_le_bytes #410") }
    if !(V(0x4202a05f20000000u64).to_be_bytes() == [66u8, 2u8, 160u8, 95u8, 32u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #411") }
    if !(V(0x4202a05f20000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 66u8]) { panic("to_ne_bytes #412") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 66u8]).to_bits() == 0x4202a05f20000000u64) { panic("from_le_bytes #413") }
    if !(f64.from_be_bytes([66u8, 2u8, 160u8, 95u8, 32u8, 0u8, 0u8, 0u8]).to_bits() == 0x4202a05f20000000u64) { panic("from_be_bytes #414") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 66u8]).to_bits() == 0x4202a05f20000000u64) { panic("from_ne_bytes #415") }
    if !(V(0x4202a05f20000000u64).next_up().to_bits() == 0x4202a05f20000001u64) { panic("next_up #416") }
    if !(V(0x4202a05f20000000u64).next_down().to_bits() == 0x4202a05f1fffffffu64) { panic("next_down #417") }
    if !(V(0x4202a05f20000000u64).total_cmp(V(0x4202a05f20000000u64)) == Ordering.Equal) { panic("total_cmp #418") }
    if !(V(0xc202a05f20000000u64).is_nan() == false) { panic("is_nan #419") }
    if !(V(0xc202a05f20000000u64).is_infinite() == false) { panic("is_infinite #420") }
    if !(V(0xc202a05f20000000u64).is_finite() == true) { panic("is_finite #421") }
    if !(V(0xc202a05f20000000u64).is_normal() == true) { panic("is_normal #422") }
    if !(V(0xc202a05f20000000u64).is_subnormal() == false) { panic("is_subnormal #423") }
    if !(V(0xc202a05f20000000u64).is_sign_negative() == true) { panic("is_sign_negative #424") }
    if !(V(0xc202a05f20000000u64).is_sign_positive() == false) { panic("is_sign_positive #425") }
    if !(V(0xc202a05f20000000u64).classify() == FpCategory.Normal) { panic("classify #426") }
    if !(V(0xc202a05f20000000u64).abs().to_bits() == 0x4202a05f20000000u64) { panic("abs #427") }
    if !(V(0xc202a05f20000000u64).floor().to_bits() == 0xc202a05f20000000u64) { panic("floor #428") }
    if !(V(0xc202a05f20000000u64).ceil().to_bits() == 0xc202a05f20000000u64) { panic("ceil #429") }
    if !(V(0xc202a05f20000000u64).trunc().to_bits() == 0xc202a05f20000000u64) { panic("trunc #430") }
    if !(V(0xc202a05f20000000u64).round().to_bits() == 0xc202a05f20000000u64) { panic("round #431") }
    if !(V(0xc202a05f20000000u64).round_ties_even().to_bits() == 0xc202a05f20000000u64) { panic("round_ties_even #432") }
    if !(V(0xc202a05f20000000u64).fract().to_bits() == 0x0u64) { panic("fract #433") }
    if !(V(0xc202a05f20000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #434") }
    if !(V(0xc202a05f20000000u64).recip().to_bits() == 0xbddb7cdfd9d7bdbbu64) { panic("recip #435") }
    if !(V(0xc202a05f20000000u64).sqrt().is_nan()) { panic("sqrt #436") }
    if !(V(0xc202a05f20000000u64).to_bits() == 0xc202a05f20000000u64) { panic("to_bits #437") }
    if !(V(0xc202a05f20000000u64).to_bits() == 0xc202a05f20000000u64) { panic("to_bits #438") }
    if !(f64.from_bits(0xc202a05f20000000u64).to_bits() == 0xc202a05f20000000u64) { panic("from_bits #439") }
    if !(V(0xc202a05f20000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 194u8]) { panic("to_le_bytes #440") }
    if !(V(0xc202a05f20000000u64).to_be_bytes() == [194u8, 2u8, 160u8, 95u8, 32u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #441") }
    if !(V(0xc202a05f20000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 194u8]) { panic("to_ne_bytes #442") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 194u8]).to_bits() == 0xc202a05f20000000u64) { panic("from_le_bytes #443") }
    if !(f64.from_be_bytes([194u8, 2u8, 160u8, 95u8, 32u8, 0u8, 0u8, 0u8]).to_bits() == 0xc202a05f20000000u64) { panic("from_be_bytes #444") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 32u8, 95u8, 160u8, 2u8, 194u8]).to_bits() == 0xc202a05f20000000u64) { panic("from_ne_bytes #445") }
    if !(V(0xc202a05f20000000u64).next_up().to_bits() == 0xc202a05f1fffffffu64) { panic("next_up #446") }
    if !(V(0xc202a05f20000000u64).next_down().to_bits() == 0xc202a05f20000001u64) { panic("next_down #447") }
    if !(V(0xc202a05f20000000u64).total_cmp(V(0xc202a05f20000000u64)) == Ordering.Equal) { panic("total_cmp #448") }
    if !(V(0x7fefffffffffffffu64).is_nan() == false) { panic("is_nan #449") }
    if !(V(0x7fefffffffffffffu64).is_infinite() == false) { panic("is_infinite #450") }
    if !(V(0x7fefffffffffffffu64).is_finite() == true) { panic("is_finite #451") }
    if !(V(0x7fefffffffffffffu64).is_normal() == true) { panic("is_normal #452") }
    if !(V(0x7fefffffffffffffu64).is_subnormal() == false) { panic("is_subnormal #453") }
    if !(V(0x7fefffffffffffffu64).is_sign_negative() == false) { panic("is_sign_negative #454") }
    if !(V(0x7fefffffffffffffu64).is_sign_positive() == true) { panic("is_sign_positive #455") }
    if !(V(0x7fefffffffffffffu64).classify() == FpCategory.Normal) { panic("classify #456") }
    if !(V(0x7fefffffffffffffu64).abs().to_bits() == 0x7fefffffffffffffu64) { panic("abs #457") }
    if !(V(0x7fefffffffffffffu64).floor().to_bits() == 0x7fefffffffffffffu64) { panic("floor #458") }
    if !(V(0x7fefffffffffffffu64).ceil().to_bits() == 0x7fefffffffffffffu64) { panic("ceil #459") }
    if !(V(0x7fefffffffffffffu64).trunc().to_bits() == 0x7fefffffffffffffu64) { panic("trunc #460") }
    if !(V(0x7fefffffffffffffu64).round().to_bits() == 0x7fefffffffffffffu64) { panic("round #461") }
    if !(V(0x7fefffffffffffffu64).round_ties_even().to_bits() == 0x7fefffffffffffffu64) { panic("round_ties_even #462") }
    if !(V(0x7fefffffffffffffu64).fract().to_bits() == 0x0u64) { panic("fract #463") }
    if !(V(0x7fefffffffffffffu64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #464") }
    if !(V(0x7fefffffffffffffu64).recip().to_bits() == 0x4000000000000u64) { panic("recip #465") }
    if !(V(0x7fefffffffffffffu64).sqrt().to_bits() == 0x5fefffffffffffffu64) { panic("sqrt #466") }
    if !(V(0x7fefffffffffffffu64).to_bits() == 0x7fefffffffffffffu64) { panic("to_bits #467") }
    if !(V(0x7fefffffffffffffu64).to_bits() == 0x7fefffffffffffffu64) { panic("to_bits #468") }
    if !(f64.from_bits(0x7fefffffffffffffu64).to_bits() == 0x7fefffffffffffffu64) { panic("from_bits #469") }
    if !(V(0x7fefffffffffffffu64).to_le_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 127u8]) { panic("to_le_bytes #470") }
    if !(V(0x7fefffffffffffffu64).to_be_bytes() == [127u8, 239u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_be_bytes #471") }
    if !(V(0x7fefffffffffffffu64).to_ne_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 127u8]) { panic("to_ne_bytes #472") }
    if !(f64.from_le_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 127u8]).to_bits() == 0x7fefffffffffffffu64) { panic("from_le_bytes #473") }
    if !(f64.from_be_bytes([127u8, 239u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]).to_bits() == 0x7fefffffffffffffu64) { panic("from_be_bytes #474") }
    if !(f64.from_ne_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 127u8]).to_bits() == 0x7fefffffffffffffu64) { panic("from_ne_bytes #475") }
    if !(V(0x7fefffffffffffffu64).next_up().to_bits() == 0x7ff0000000000000u64) { panic("next_up #476") }
    if !(V(0x7fefffffffffffffu64).next_down().to_bits() == 0x7feffffffffffffeu64) { panic("next_down #477") }
    if !(V(0x7fefffffffffffffu64).total_cmp(V(0x7fefffffffffffffu64)) == Ordering.Equal) { panic("total_cmp #478") }
    if !(V(0xffefffffffffffffu64).is_nan() == false) { panic("is_nan #479") }
    if !(V(0xffefffffffffffffu64).is_infinite() == false) { panic("is_infinite #480") }
}

fn group4() {
    if !(V(0xffefffffffffffffu64).is_finite() == true) { panic("is_finite #481") }
    if !(V(0xffefffffffffffffu64).is_normal() == true) { panic("is_normal #482") }
    if !(V(0xffefffffffffffffu64).is_subnormal() == false) { panic("is_subnormal #483") }
    if !(V(0xffefffffffffffffu64).is_sign_negative() == true) { panic("is_sign_negative #484") }
    if !(V(0xffefffffffffffffu64).is_sign_positive() == false) { panic("is_sign_positive #485") }
    if !(V(0xffefffffffffffffu64).classify() == FpCategory.Normal) { panic("classify #486") }
    if !(V(0xffefffffffffffffu64).abs().to_bits() == 0x7fefffffffffffffu64) { panic("abs #487") }
    if !(V(0xffefffffffffffffu64).floor().to_bits() == 0xffefffffffffffffu64) { panic("floor #488") }
    if !(V(0xffefffffffffffffu64).ceil().to_bits() == 0xffefffffffffffffu64) { panic("ceil #489") }
    if !(V(0xffefffffffffffffu64).trunc().to_bits() == 0xffefffffffffffffu64) { panic("trunc #490") }
    if !(V(0xffefffffffffffffu64).round().to_bits() == 0xffefffffffffffffu64) { panic("round #491") }
    if !(V(0xffefffffffffffffu64).round_ties_even().to_bits() == 0xffefffffffffffffu64) { panic("round_ties_even #492") }
    if !(V(0xffefffffffffffffu64).fract().to_bits() == 0x0u64) { panic("fract #493") }
    if !(V(0xffefffffffffffffu64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #494") }
    if !(V(0xffefffffffffffffu64).recip().to_bits() == 0x8004000000000000u64) { panic("recip #495") }
    if !(V(0xffefffffffffffffu64).sqrt().is_nan()) { panic("sqrt #496") }
    if !(V(0xffefffffffffffffu64).to_bits() == 0xffefffffffffffffu64) { panic("to_bits #497") }
    if !(V(0xffefffffffffffffu64).to_bits() == 0xffefffffffffffffu64) { panic("to_bits #498") }
    if !(f64.from_bits(0xffefffffffffffffu64).to_bits() == 0xffefffffffffffffu64) { panic("from_bits #499") }
    if !(V(0xffefffffffffffffu64).to_le_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 255u8]) { panic("to_le_bytes #500") }
    if !(V(0xffefffffffffffffu64).to_be_bytes() == [255u8, 239u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]) { panic("to_be_bytes #501") }
    if !(V(0xffefffffffffffffu64).to_ne_bytes() == [255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 255u8]) { panic("to_ne_bytes #502") }
    if !(f64.from_le_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 255u8]).to_bits() == 0xffefffffffffffffu64) { panic("from_le_bytes #503") }
    if !(f64.from_be_bytes([255u8, 239u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8]).to_bits() == 0xffefffffffffffffu64) { panic("from_be_bytes #504") }
    if !(f64.from_ne_bytes([255u8, 255u8, 255u8, 255u8, 255u8, 255u8, 239u8, 255u8]).to_bits() == 0xffefffffffffffffu64) { panic("from_ne_bytes #505") }
    if !(V(0xffefffffffffffffu64).next_up().to_bits() == 0xffeffffffffffffeu64) { panic("next_up #506") }
    if !(V(0xffefffffffffffffu64).next_down().to_bits() == 0xfff0000000000000u64) { panic("next_down #507") }
    if !(V(0xffefffffffffffffu64).total_cmp(V(0xffefffffffffffffu64)) == Ordering.Equal) { panic("total_cmp #508") }
    if !(V(0x10000000000000u64).is_nan() == false) { panic("is_nan #509") }
    if !(V(0x10000000000000u64).is_infinite() == false) { panic("is_infinite #510") }
    if !(V(0x10000000000000u64).is_finite() == true) { panic("is_finite #511") }
    if !(V(0x10000000000000u64).is_normal() == true) { panic("is_normal #512") }
    if !(V(0x10000000000000u64).is_subnormal() == false) { panic("is_subnormal #513") }
    if !(V(0x10000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #514") }
    if !(V(0x10000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #515") }
    if !(V(0x10000000000000u64).classify() == FpCategory.Normal) { panic("classify #516") }
    if !(V(0x10000000000000u64).abs().to_bits() == 0x10000000000000u64) { panic("abs #517") }
    if !(V(0x10000000000000u64).floor().to_bits() == 0x0u64) { panic("floor #518") }
    if !(V(0x10000000000000u64).ceil().to_bits() == 0x3ff0000000000000u64) { panic("ceil #519") }
    if !(V(0x10000000000000u64).trunc().to_bits() == 0x0u64) { panic("trunc #520") }
    if !(V(0x10000000000000u64).round().to_bits() == 0x0u64) { panic("round #521") }
    if !(V(0x10000000000000u64).round_ties_even().to_bits() == 0x0u64) { panic("round_ties_even #522") }
    if !(V(0x10000000000000u64).fract().to_bits() == 0x10000000000000u64) { panic("fract #523") }
    if !(V(0x10000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #524") }
    if !(V(0x10000000000000u64).recip().to_bits() == 0x7fd0000000000000u64) { panic("recip #525") }
    if !(V(0x10000000000000u64).sqrt().to_bits() == 0x2000000000000000u64) { panic("sqrt #526") }
    if !(V(0x10000000000000u64).to_bits() == 0x10000000000000u64) { panic("to_bits #527") }
    if !(V(0x10000000000000u64).to_bits() == 0x10000000000000u64) { panic("to_bits #528") }
    if !(f64.from_bits(0x10000000000000u64).to_bits() == 0x10000000000000u64) { panic("from_bits #529") }
    if !(V(0x10000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 16u8, 0u8]) { panic("to_le_bytes #530") }
    if !(V(0x10000000000000u64).to_be_bytes() == [0u8, 16u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #531") }
    if !(V(0x10000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 16u8, 0u8]) { panic("to_ne_bytes #532") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 16u8, 0u8]).to_bits() == 0x10000000000000u64) { panic("from_le_bytes #533") }
    if !(f64.from_be_bytes([0u8, 16u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x10000000000000u64) { panic("from_be_bytes #534") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 16u8, 0u8]).to_bits() == 0x10000000000000u64) { panic("from_ne_bytes #535") }
    if !(V(0x10000000000000u64).next_up().to_bits() == 0x10000000000001u64) { panic("next_up #536") }
    if !(V(0x10000000000000u64).next_down().to_bits() == 0xfffffffffffffu64) { panic("next_down #537") }
    if !(unsafe { V(0x10000000000000u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #538") }
    if !(V(0x10000000000000u64).total_cmp(V(0x10000000000000u64)) == Ordering.Equal) { panic("total_cmp #539") }
    if !(V(0x1u64).is_nan() == false) { panic("is_nan #540") }
    if !(V(0x1u64).is_infinite() == false) { panic("is_infinite #541") }
    if !(V(0x1u64).is_finite() == true) { panic("is_finite #542") }
    if !(V(0x1u64).is_normal() == false) { panic("is_normal #543") }
    if !(V(0x1u64).is_subnormal() == true) { panic("is_subnormal #544") }
    if !(V(0x1u64).is_sign_negative() == false) { panic("is_sign_negative #545") }
    if !(V(0x1u64).is_sign_positive() == true) { panic("is_sign_positive #546") }
    if !(V(0x1u64).classify() == FpCategory.Subnormal) { panic("classify #547") }
    if !(V(0x1u64).abs().to_bits() == 0x1u64) { panic("abs #548") }
    if !(V(0x1u64).floor().to_bits() == 0x0u64) { panic("floor #549") }
    if !(V(0x1u64).ceil().to_bits() == 0x3ff0000000000000u64) { panic("ceil #550") }
    if !(V(0x1u64).trunc().to_bits() == 0x0u64) { panic("trunc #551") }
    if !(V(0x1u64).round().to_bits() == 0x0u64) { panic("round #552") }
    if !(V(0x1u64).round_ties_even().to_bits() == 0x0u64) { panic("round_ties_even #553") }
    if !(V(0x1u64).fract().to_bits() == 0x1u64) { panic("fract #554") }
    if !(V(0x1u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #555") }
    if !(V(0x1u64).recip().to_bits() == 0x7ff0000000000000u64) { panic("recip #556") }
    if !(V(0x1u64).sqrt().to_bits() == 0x1e60000000000000u64) { panic("sqrt #557") }
    if !(V(0x1u64).to_bits() == 0x1u64) { panic("to_bits #558") }
    if !(V(0x1u64).to_bits() == 0x1u64) { panic("to_bits #559") }
    if !(f64.from_bits(0x1u64).to_bits() == 0x1u64) { panic("from_bits #560") }
    if !(V(0x1u64).to_le_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #561") }
    if !(V(0x1u64).to_be_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #562") }
    if !(V(0x1u64).to_ne_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #563") }
    if !(f64.from_le_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x1u64) { panic("from_le_bytes #564") }
    if !(f64.from_be_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]).to_bits() == 0x1u64) { panic("from_be_bytes #565") }
    if !(f64.from_ne_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x1u64) { panic("from_ne_bytes #566") }
    if !(V(0x1u64).next_up().to_bits() == 0x2u64) { panic("next_up #567") }
    if !(V(0x1u64).next_down().to_bits() == 0x0u64) { panic("next_down #568") }
    if !(unsafe { V(0x1u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #569") }
    if !(V(0x1u64).total_cmp(V(0x1u64)) == Ordering.Equal) { panic("total_cmp #570") }
    if !(V(0x8000000000000001u64).is_nan() == false) { panic("is_nan #571") }
    if !(V(0x8000000000000001u64).is_infinite() == false) { panic("is_infinite #572") }
    if !(V(0x8000000000000001u64).is_finite() == true) { panic("is_finite #573") }
    if !(V(0x8000000000000001u64).is_normal() == false) { panic("is_normal #574") }
    if !(V(0x8000000000000001u64).is_subnormal() == true) { panic("is_subnormal #575") }
    if !(V(0x8000000000000001u64).is_sign_negative() == true) { panic("is_sign_negative #576") }
    if !(V(0x8000000000000001u64).is_sign_positive() == false) { panic("is_sign_positive #577") }
    if !(V(0x8000000000000001u64).classify() == FpCategory.Subnormal) { panic("classify #578") }
    if !(V(0x8000000000000001u64).abs().to_bits() == 0x1u64) { panic("abs #579") }
    if !(V(0x8000000000000001u64).floor().to_bits() == 0xbff0000000000000u64) { panic("floor #580") }
    if !(V(0x8000000000000001u64).ceil().to_bits() == 0x8000000000000000u64) { panic("ceil #581") }
    if !(V(0x8000000000000001u64).trunc().to_bits() == 0x8000000000000000u64) { panic("trunc #582") }
    if !(V(0x8000000000000001u64).round().to_bits() == 0x8000000000000000u64) { panic("round #583") }
    if !(V(0x8000000000000001u64).round_ties_even().to_bits() == 0x8000000000000000u64) { panic("round_ties_even #584") }
    if !(V(0x8000000000000001u64).fract().to_bits() == 0x8000000000000001u64) { panic("fract #585") }
    if !(V(0x8000000000000001u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #586") }
    if !(V(0x8000000000000001u64).recip().to_bits() == 0xfff0000000000000u64) { panic("recip #587") }
    if !(V(0x8000000000000001u64).sqrt().is_nan()) { panic("sqrt #588") }
    if !(V(0x8000000000000001u64).to_bits() == 0x8000000000000001u64) { panic("to_bits #589") }
    if !(V(0x8000000000000001u64).to_bits() == 0x8000000000000001u64) { panic("to_bits #590") }
    if !(f64.from_bits(0x8000000000000001u64).to_bits() == 0x8000000000000001u64) { panic("from_bits #591") }
    if !(V(0x8000000000000001u64).to_le_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) { panic("to_le_bytes #592") }
    if !(V(0x8000000000000001u64).to_be_bytes() == [128u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #593") }
    if !(V(0x8000000000000001u64).to_ne_bytes() == [1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]) { panic("to_ne_bytes #594") }
    if !(f64.from_le_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]).to_bits() == 0x8000000000000001u64) { panic("from_le_bytes #595") }
    if !(f64.from_be_bytes([128u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8]).to_bits() == 0x8000000000000001u64) { panic("from_be_bytes #596") }
    if !(f64.from_ne_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 128u8]).to_bits() == 0x8000000000000001u64) { panic("from_ne_bytes #597") }
    if !(V(0x8000000000000001u64).next_up().to_bits() == 0x8000000000000000u64) { panic("next_up #598") }
    if !(V(0x8000000000000001u64).next_down().to_bits() == 0x8000000000000002u64) { panic("next_down #599") }
    if !(unsafe { V(0x8000000000000001u64).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #600") }
}

fn group5() {
    if !(V(0x8000000000000001u64).total_cmp(V(0x8000000000000001u64)) == Ordering.Equal) { panic("total_cmp #601") }
    if !(V(0x7ff0000000000000u64).is_nan() == false) { panic("is_nan #602") }
    if !(V(0x7ff0000000000000u64).is_infinite() == true) { panic("is_infinite #603") }
    if !(V(0x7ff0000000000000u64).is_finite() == false) { panic("is_finite #604") }
    if !(V(0x7ff0000000000000u64).is_normal() == false) { panic("is_normal #605") }
    if !(V(0x7ff0000000000000u64).is_subnormal() == false) { panic("is_subnormal #606") }
    if !(V(0x7ff0000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #607") }
    if !(V(0x7ff0000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #608") }
    if !(V(0x7ff0000000000000u64).classify() == FpCategory.Infinite) { panic("classify #609") }
    if !(V(0x7ff0000000000000u64).abs().to_bits() == 0x7ff0000000000000u64) { panic("abs #610") }
    if !(V(0x7ff0000000000000u64).floor().to_bits() == 0x7ff0000000000000u64) { panic("floor #611") }
    if !(V(0x7ff0000000000000u64).ceil().to_bits() == 0x7ff0000000000000u64) { panic("ceil #612") }
    if !(V(0x7ff0000000000000u64).trunc().to_bits() == 0x7ff0000000000000u64) { panic("trunc #613") }
    if !(V(0x7ff0000000000000u64).round().to_bits() == 0x7ff0000000000000u64) { panic("round #614") }
    if !(V(0x7ff0000000000000u64).round_ties_even().to_bits() == 0x7ff0000000000000u64) { panic("round_ties_even #615") }
    if !(V(0x7ff0000000000000u64).fract().is_nan()) { panic("fract #616") }
    if !(V(0x7ff0000000000000u64).signum().to_bits() == 0x3ff0000000000000u64) { panic("signum #617") }
    if !(V(0x7ff0000000000000u64).recip().to_bits() == 0x0u64) { panic("recip #618") }
    if !(V(0x7ff0000000000000u64).sqrt().to_bits() == 0x7ff0000000000000u64) { panic("sqrt #619") }
    if !(V(0x7ff0000000000000u64).to_bits() == 0x7ff0000000000000u64) { panic("to_bits #620") }
    if !(V(0x7ff0000000000000u64).to_bits() == 0x7ff0000000000000u64) { panic("to_bits #621") }
    if !(f64.from_bits(0x7ff0000000000000u64).to_bits() == 0x7ff0000000000000u64) { panic("from_bits #622") }
    if !(V(0x7ff0000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 127u8]) { panic("to_le_bytes #623") }
    if !(V(0x7ff0000000000000u64).to_be_bytes() == [127u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #624") }
    if !(V(0x7ff0000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 127u8]) { panic("to_ne_bytes #625") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 127u8]).to_bits() == 0x7ff0000000000000u64) { panic("from_le_bytes #626") }
    if !(f64.from_be_bytes([127u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x7ff0000000000000u64) { panic("from_be_bytes #627") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 127u8]).to_bits() == 0x7ff0000000000000u64) { panic("from_ne_bytes #628") }
    if !(V(0x7ff0000000000000u64).next_up().to_bits() == 0x7ff0000000000000u64) { panic("next_up #629") }
    if !(V(0x7ff0000000000000u64).next_down().to_bits() == 0x7fefffffffffffffu64) { panic("next_down #630") }
    if !(V(0x7ff0000000000000u64).total_cmp(V(0x7ff0000000000000u64)) == Ordering.Equal) { panic("total_cmp #631") }
    if !(V(0x7ff0000000000000u64).to_degrees().to_bits() == 0x7ff0000000000000u64) { panic("to_degrees #632") }
    if !(V(0xfff0000000000000u64).is_nan() == false) { panic("is_nan #633") }
    if !(V(0xfff0000000000000u64).is_infinite() == true) { panic("is_infinite #634") }
    if !(V(0xfff0000000000000u64).is_finite() == false) { panic("is_finite #635") }
    if !(V(0xfff0000000000000u64).is_normal() == false) { panic("is_normal #636") }
    if !(V(0xfff0000000000000u64).is_subnormal() == false) { panic("is_subnormal #637") }
    if !(V(0xfff0000000000000u64).is_sign_negative() == true) { panic("is_sign_negative #638") }
    if !(V(0xfff0000000000000u64).is_sign_positive() == false) { panic("is_sign_positive #639") }
    if !(V(0xfff0000000000000u64).classify() == FpCategory.Infinite) { panic("classify #640") }
    if !(V(0xfff0000000000000u64).abs().to_bits() == 0x7ff0000000000000u64) { panic("abs #641") }
    if !(V(0xfff0000000000000u64).floor().to_bits() == 0xfff0000000000000u64) { panic("floor #642") }
    if !(V(0xfff0000000000000u64).ceil().to_bits() == 0xfff0000000000000u64) { panic("ceil #643") }
    if !(V(0xfff0000000000000u64).trunc().to_bits() == 0xfff0000000000000u64) { panic("trunc #644") }
    if !(V(0xfff0000000000000u64).round().to_bits() == 0xfff0000000000000u64) { panic("round #645") }
    if !(V(0xfff0000000000000u64).round_ties_even().to_bits() == 0xfff0000000000000u64) { panic("round_ties_even #646") }
    if !(V(0xfff0000000000000u64).fract().is_nan()) { panic("fract #647") }
    if !(V(0xfff0000000000000u64).signum().to_bits() == 0xbff0000000000000u64) { panic("signum #648") }
    if !(V(0xfff0000000000000u64).recip().to_bits() == 0x8000000000000000u64) { panic("recip #649") }
    if !(V(0xfff0000000000000u64).sqrt().is_nan()) { panic("sqrt #650") }
    if !(V(0xfff0000000000000u64).to_bits() == 0xfff0000000000000u64) { panic("to_bits #651") }
    if !(V(0xfff0000000000000u64).to_bits() == 0xfff0000000000000u64) { panic("to_bits #652") }
    if !(f64.from_bits(0xfff0000000000000u64).to_bits() == 0xfff0000000000000u64) { panic("from_bits #653") }
    if !(V(0xfff0000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 255u8]) { panic("to_le_bytes #654") }
    if !(V(0xfff0000000000000u64).to_be_bytes() == [255u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #655") }
    if !(V(0xfff0000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 255u8]) { panic("to_ne_bytes #656") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 255u8]).to_bits() == 0xfff0000000000000u64) { panic("from_le_bytes #657") }
    if !(f64.from_be_bytes([255u8, 240u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0xfff0000000000000u64) { panic("from_be_bytes #658") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 240u8, 255u8]).to_bits() == 0xfff0000000000000u64) { panic("from_ne_bytes #659") }
    if !(V(0xfff0000000000000u64).next_up().to_bits() == 0xffefffffffffffffu64) { panic("next_up #660") }
    if !(V(0xfff0000000000000u64).next_down().to_bits() == 0xfff0000000000000u64) { panic("next_down #661") }
    if !(V(0xfff0000000000000u64).total_cmp(V(0xfff0000000000000u64)) == Ordering.Equal) { panic("total_cmp #662") }
    if !(V(0xfff0000000000000u64).to_degrees().to_bits() == 0xfff0000000000000u64) { panic("to_degrees #663") }
    if !(V(0x7ff8000000000000u64).is_nan() == true) { panic("is_nan #664") }
    if !(V(0x7ff8000000000000u64).is_infinite() == false) { panic("is_infinite #665") }
    if !(V(0x7ff8000000000000u64).is_finite() == false) { panic("is_finite #666") }
    if !(V(0x7ff8000000000000u64).is_normal() == false) { panic("is_normal #667") }
    if !(V(0x7ff8000000000000u64).is_subnormal() == false) { panic("is_subnormal #668") }
    if !(V(0x7ff8000000000000u64).is_sign_negative() == false) { panic("is_sign_negative #669") }
    if !(V(0x7ff8000000000000u64).is_sign_positive() == true) { panic("is_sign_positive #670") }
    if !(V(0x7ff8000000000000u64).classify() == FpCategory.Nan) { panic("classify #671") }
    if !(V(0x7ff8000000000000u64).abs().is_nan()) { panic("abs #672") }
    if !(V(0x7ff8000000000000u64).floor().is_nan()) { panic("floor #673") }
    if !(V(0x7ff8000000000000u64).ceil().is_nan()) { panic("ceil #674") }
    if !(V(0x7ff8000000000000u64).trunc().is_nan()) { panic("trunc #675") }
    if !(V(0x7ff8000000000000u64).round().is_nan()) { panic("round #676") }
    if !(V(0x7ff8000000000000u64).round_ties_even().is_nan()) { panic("round_ties_even #677") }
    if !(V(0x7ff8000000000000u64).fract().is_nan()) { panic("fract #678") }
    if !(V(0x7ff8000000000000u64).signum().is_nan()) { panic("signum #679") }
    if !(V(0x7ff8000000000000u64).recip().is_nan()) { panic("recip #680") }
    if !(V(0x7ff8000000000000u64).is_nan()) { panic("to_bits #681") }
    if !(V(0x7ff8000000000000u64).to_bits() == 0x7ff8000000000000u64) { panic("to_bits #682") }
    if !(f64.from_bits(0x7ff8000000000000u64).to_bits() == 0x7ff8000000000000u64) { panic("from_bits #683") }
    if !(V(0x7ff8000000000000u64).to_le_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 127u8]) { panic("to_le_bytes #684") }
    if !(V(0x7ff8000000000000u64).to_be_bytes() == [127u8, 248u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #685") }
    if !(V(0x7ff8000000000000u64).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 127u8]) { panic("to_ne_bytes #686") }
    if !(f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 127u8]).to_bits() == 0x7ff8000000000000u64) { panic("from_le_bytes #687") }
    if !(f64.from_be_bytes([127u8, 248u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]).to_bits() == 0x7ff8000000000000u64) { panic("from_be_bytes #688") }
    if !(f64.from_ne_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 248u8, 127u8]).to_bits() == 0x7ff8000000000000u64) { panic("from_ne_bytes #689") }
    if !(V(0x7ff8000000000000u64).next_up().is_nan()) { panic("next_up #690") }
    if !(V(0x7ff8000000000000u64).next_down().is_nan()) { panic("next_down #691") }
    if !(V(0x7ff8000000000000u64).total_cmp(V(0x7ff8000000000000u64)) == Ordering.Equal) { panic("total_cmp #692") }
    if !(V(0x7ff8000000000000u64).to_degrees().is_nan()) { panic("to_degrees #693") }
    if !(V(0x3ff0000000000000u64).copysign(V(0x4000000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("copysign #694") }
    if !(V(0x3ff0000000000000u64).min(V(0x4000000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("min #695") }
    if !(V(0x3ff0000000000000u64).max(V(0x4000000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("max #696") }
    if !(V(0x3ff0000000000000u64).total_cmp(V(0x4000000000000000u64)) == Ordering.Less) { panic("total_cmp #697") }
    if !(V(0x3ff0000000000000u64).rem_euclid(V(0x4000000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("rem_euclid #698") }
    if !(V(0x3ff0000000000000u64).div_euclid(V(0x4000000000000000u64)).to_bits() == 0x0u64) { panic("div_euclid #699") }
    if !(V(0x3ff0000000000000u64).midpoint(V(0x4000000000000000u64)).to_bits() == 0x3ff8000000000000u64) { panic("midpoint #700") }
    if !(near(V(0x3ff0000000000000u64).algebraic_add(V(0x4000000000000000u64)), V(0x4008000000000000u64), 1u64)) { panic("algebraic_add #701") }
    if !(near(V(0x3ff0000000000000u64).algebraic_sub(V(0x4000000000000000u64)), V(0xbff0000000000000u64), 1u64)) { panic("algebraic_sub #702") }
    if !(near(V(0x3ff0000000000000u64).algebraic_mul(V(0x4000000000000000u64)), V(0x4000000000000000u64), 1u64)) { panic("algebraic_mul #703") }
    if !(near(V(0x3ff0000000000000u64).algebraic_div(V(0x4000000000000000u64)), V(0x3fe0000000000000u64), 1u64)) { panic("algebraic_div #704") }
    if !(near(V(0x3ff0000000000000u64).algebraic_rem(V(0x4000000000000000u64)), V(0x3ff0000000000000u64), 1u64)) { panic("algebraic_rem #705") }
    if !(near(V(0x3ff0000000000000u64).hypot(V(0x4000000000000000u64)), V(0x4001e3779b97f4a8u64), 2u64)) { panic("hypot #706") }
    if !(near(V(0x3ff0000000000000u64).atan2(V(0x4000000000000000u64)), V(0x3fddac670561bb4fu64), 2u64)) { panic("atan2 #707") }
    if !(V(0xbff0000000000000u64).copysign(V(0x4000000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("copysign #708") }
    if !(V(0xbff0000000000000u64).min(V(0x4000000000000000u64)).to_bits() == 0xbff0000000000000u64) { panic("min #709") }
    if !(V(0xbff0000000000000u64).max(V(0x4000000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("max #710") }
    if !(V(0xbff0000000000000u64).total_cmp(V(0x4000000000000000u64)) == Ordering.Less) { panic("total_cmp #711") }
    if !(V(0xbff0000000000000u64).rem_euclid(V(0x4000000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("rem_euclid #712") }
    if !(V(0xbff0000000000000u64).div_euclid(V(0x4000000000000000u64)).to_bits() == 0xbff0000000000000u64) { panic("div_euclid #713") }
    if !(V(0xbff0000000000000u64).midpoint(V(0x4000000000000000u64)).to_bits() == 0x3fe0000000000000u64) { panic("midpoint #714") }
    if !(near(V(0xbff0000000000000u64).algebraic_add(V(0x4000000000000000u64)), V(0x3ff0000000000000u64), 1u64)) { panic("algebraic_add #715") }
    if !(near(V(0xbff0000000000000u64).algebraic_sub(V(0x4000000000000000u64)), V(0xc008000000000000u64), 1u64)) { panic("algebraic_sub #716") }
    if !(near(V(0xbff0000000000000u64).algebraic_mul(V(0x4000000000000000u64)), V(0xc000000000000000u64), 1u64)) { panic("algebraic_mul #717") }
    if !(near(V(0xbff0000000000000u64).algebraic_div(V(0x4000000000000000u64)), V(0xbfe0000000000000u64), 1u64)) { panic("algebraic_div #718") }
    if !(near(V(0xbff0000000000000u64).algebraic_rem(V(0x4000000000000000u64)), V(0xbff0000000000000u64), 1u64)) { panic("algebraic_rem #719") }
    if !(near(V(0xbff0000000000000u64).hypot(V(0x4000000000000000u64)), V(0x4001e3779b97f4a8u64), 2u64)) { panic("hypot #720") }
}

fn group6() {
    if !(near(V(0xbff0000000000000u64).atan2(V(0x4000000000000000u64)), V(0xbfddac670561bb4fu64), 2u64)) { panic("atan2 #721") }
    if !(V(0x4004000000000000u64).copysign(V(0xbfe0000000000000u64)).to_bits() == 0xc004000000000000u64) { panic("copysign #722") }
    if !(V(0x4004000000000000u64).min(V(0xbfe0000000000000u64)).to_bits() == 0xbfe0000000000000u64) { panic("min #723") }
    if !(V(0x4004000000000000u64).max(V(0xbfe0000000000000u64)).to_bits() == 0x4004000000000000u64) { panic("max #724") }
    if !(V(0x4004000000000000u64).total_cmp(V(0xbfe0000000000000u64)) == Ordering.Greater) { panic("total_cmp #725") }
    if !(V(0x4004000000000000u64).rem_euclid(V(0xbfe0000000000000u64)).to_bits() == 0x0u64) { panic("rem_euclid #726") }
    if !(V(0x4004000000000000u64).div_euclid(V(0xbfe0000000000000u64)).to_bits() == 0xc014000000000000u64) { panic("div_euclid #727") }
    if !(V(0x4004000000000000u64).midpoint(V(0xbfe0000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("midpoint #728") }
    if !(near(V(0x4004000000000000u64).algebraic_add(V(0xbfe0000000000000u64)), V(0x4000000000000000u64), 1u64)) { panic("algebraic_add #729") }
    if !(near(V(0x4004000000000000u64).algebraic_sub(V(0xbfe0000000000000u64)), V(0x4008000000000000u64), 1u64)) { panic("algebraic_sub #730") }
    if !(near(V(0x4004000000000000u64).algebraic_mul(V(0xbfe0000000000000u64)), V(0xbff4000000000000u64), 1u64)) { panic("algebraic_mul #731") }
    if !(near(V(0x4004000000000000u64).algebraic_div(V(0xbfe0000000000000u64)), V(0xc014000000000000u64), 1u64)) { panic("algebraic_div #732") }
    if !(V(0x4004000000000000u64).algebraic_rem(V(0xbfe0000000000000u64)).to_bits() == 0x0u64) { panic("algebraic_rem #733") }
    if !(near(V(0x4004000000000000u64).hypot(V(0xbfe0000000000000u64)), V(0x400465655f122ff6u64), 2u64)) { panic("hypot #734") }
    if !(near(V(0x4004000000000000u64).atan2(V(0xbfe0000000000000u64)), V(0x3ffc4a83936311dau64), 2u64)) { panic("atan2 #735") }
    if !(V(0x0u64).copysign(V(0x8000000000000000u64)).to_bits() == 0x8000000000000000u64) { panic("copysign #736") }
    if !(V(0x0u64).min(V(0x8000000000000000u64)) == V(0x0u64)) { panic("min #737") }
    if !(V(0x0u64).max(V(0x8000000000000000u64)) == V(0x0u64)) { panic("max #738") }
    if !(V(0x0u64).total_cmp(V(0x8000000000000000u64)) == Ordering.Greater) { panic("total_cmp #739") }
    if !(V(0x8000000000000000u64).copysign(V(0x0u64)).to_bits() == 0x0u64) { panic("copysign #740") }
    if !(V(0x8000000000000000u64).min(V(0x0u64)) == V(0x0u64)) { panic("min #741") }
    if !(V(0x8000000000000000u64).max(V(0x0u64)) == V(0x0u64)) { panic("max #742") }
    if !(V(0x8000000000000000u64).total_cmp(V(0x0u64)) == Ordering.Less) { panic("total_cmp #743") }
    if !(V(0x7fefffffffffffffu64).copysign(V(0x7fefffffffffffffu64)).to_bits() == 0x7fefffffffffffffu64) { panic("copysign #744") }
    if !(V(0x7fefffffffffffffu64).min(V(0x7fefffffffffffffu64)).to_bits() == 0x7fefffffffffffffu64) { panic("min #745") }
    if !(V(0x7fefffffffffffffu64).max(V(0x7fefffffffffffffu64)).to_bits() == 0x7fefffffffffffffu64) { panic("max #746") }
    if !(V(0x7fefffffffffffffu64).total_cmp(V(0x7fefffffffffffffu64)) == Ordering.Equal) { panic("total_cmp #747") }
    if !(V(0x7fefffffffffffffu64).rem_euclid(V(0x7fefffffffffffffu64)).to_bits() == 0x0u64) { panic("rem_euclid #748") }
    if !(V(0x7fefffffffffffffu64).div_euclid(V(0x7fefffffffffffffu64)).to_bits() == 0x3ff0000000000000u64) { panic("div_euclid #749") }
    if !(V(0x7fefffffffffffffu64).midpoint(V(0x7fefffffffffffffu64)).to_bits() == 0x7fefffffffffffffu64) { panic("midpoint #750") }
    if !(V(0x7fefffffffffffffu64).algebraic_add(V(0x7fefffffffffffffu64)).to_bits() == 0x7ff0000000000000u64) { panic("algebraic_add #751") }
    if !(V(0x7fefffffffffffffu64).algebraic_sub(V(0x7fefffffffffffffu64)).to_bits() == 0x0u64) { panic("algebraic_sub #752") }
    if !(V(0x7fefffffffffffffu64).algebraic_mul(V(0x7fefffffffffffffu64)).to_bits() == 0x7ff0000000000000u64) { panic("algebraic_mul #753") }
    if !(near(V(0x7fefffffffffffffu64).algebraic_div(V(0x7fefffffffffffffu64)), V(0x3ff0000000000000u64), 1u64)) { panic("algebraic_div #754") }
    if !(V(0x7fefffffffffffffu64).algebraic_rem(V(0x7fefffffffffffffu64)).to_bits() == 0x0u64) { panic("algebraic_rem #755") }
    if !(V(0x3ff0000000000000u64).min(V(0x7ff8000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("min #756") }
    if !(V(0x3ff0000000000000u64).max(V(0x7ff8000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("max #757") }
    if !(V(0x3ff0000000000000u64).total_cmp(V(0x7ff8000000000000u64)) == Ordering.Less) { panic("total_cmp #758") }
    if !(V(0x7ff8000000000000u64).copysign(V(0x3ff0000000000000u64)).is_nan()) { panic("copysign #759") }
    if !(V(0x7ff8000000000000u64).min(V(0x3ff0000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("min #760") }
    if !(V(0x7ff8000000000000u64).max(V(0x3ff0000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("max #761") }
    if !(V(0x7ff8000000000000u64).total_cmp(V(0x3ff0000000000000u64)) == Ordering.Greater) { panic("total_cmp #762") }
    if !(V(0x7ff0000000000000u64).copysign(V(0x3ff0000000000000u64)).to_bits() == 0x7ff0000000000000u64) { panic("copysign #763") }
    if !(V(0x7ff0000000000000u64).min(V(0x3ff0000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("min #764") }
    if !(V(0x7ff0000000000000u64).max(V(0x3ff0000000000000u64)).to_bits() == 0x7ff0000000000000u64) { panic("max #765") }
    if !(V(0x7ff0000000000000u64).total_cmp(V(0x3ff0000000000000u64)) == Ordering.Greater) { panic("total_cmp #766") }
    if !(V(0x401c000000000000u64).copysign(V(0x4008000000000000u64)).to_bits() == 0x401c000000000000u64) { panic("copysign #767") }
    if !(V(0x401c000000000000u64).min(V(0x4008000000000000u64)).to_bits() == 0x4008000000000000u64) { panic("min #768") }
    if !(V(0x401c000000000000u64).max(V(0x4008000000000000u64)).to_bits() == 0x401c000000000000u64) { panic("max #769") }
    if !(V(0x401c000000000000u64).total_cmp(V(0x4008000000000000u64)) == Ordering.Greater) { panic("total_cmp #770") }
    if !(V(0x401c000000000000u64).rem_euclid(V(0x4008000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("rem_euclid #771") }
    if !(V(0x401c000000000000u64).div_euclid(V(0x4008000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("div_euclid #772") }
    if !(V(0x401c000000000000u64).midpoint(V(0x4008000000000000u64)).to_bits() == 0x4014000000000000u64) { panic("midpoint #773") }
    if !(near(V(0x401c000000000000u64).algebraic_add(V(0x4008000000000000u64)), V(0x4024000000000000u64), 1u64)) { panic("algebraic_add #774") }
    if !(near(V(0x401c000000000000u64).algebraic_sub(V(0x4008000000000000u64)), V(0x4010000000000000u64), 1u64)) { panic("algebraic_sub #775") }
    if !(near(V(0x401c000000000000u64).algebraic_mul(V(0x4008000000000000u64)), V(0x4035000000000000u64), 1u64)) { panic("algebraic_mul #776") }
    if !(near(V(0x401c000000000000u64).algebraic_div(V(0x4008000000000000u64)), V(0x4002aaaaaaaaaaabu64), 1u64)) { panic("algebraic_div #777") }
    if !(near(V(0x401c000000000000u64).algebraic_rem(V(0x4008000000000000u64)), V(0x3ff0000000000000u64), 1u64)) { panic("algebraic_rem #778") }
    if !(near(V(0x401c000000000000u64).hypot(V(0x4008000000000000u64)), V(0x401e768d399dc470u64), 2u64)) { panic("hypot #779") }
    if !(near(V(0x401c000000000000u64).atan2(V(0x4008000000000000u64)), V(0x3ff2a78b84fbf5fcu64), 2u64)) { panic("atan2 #780") }
    if !(V(0xc01c000000000000u64).copysign(V(0x4008000000000000u64)).to_bits() == 0x401c000000000000u64) { panic("copysign #781") }
    if !(V(0xc01c000000000000u64).min(V(0x4008000000000000u64)).to_bits() == 0xc01c000000000000u64) { panic("min #782") }
    if !(V(0xc01c000000000000u64).max(V(0x4008000000000000u64)).to_bits() == 0x4008000000000000u64) { panic("max #783") }
    if !(V(0xc01c000000000000u64).total_cmp(V(0x4008000000000000u64)) == Ordering.Less) { panic("total_cmp #784") }
    if !(V(0xc01c000000000000u64).rem_euclid(V(0x4008000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("rem_euclid #785") }
    if !(V(0xc01c000000000000u64).div_euclid(V(0x4008000000000000u64)).to_bits() == 0xc008000000000000u64) { panic("div_euclid #786") }
    if !(V(0xc01c000000000000u64).midpoint(V(0x4008000000000000u64)).to_bits() == 0xc000000000000000u64) { panic("midpoint #787") }
    if !(near(V(0xc01c000000000000u64).algebraic_add(V(0x4008000000000000u64)), V(0xc010000000000000u64), 1u64)) { panic("algebraic_add #788") }
    if !(near(V(0xc01c000000000000u64).algebraic_sub(V(0x4008000000000000u64)), V(0xc024000000000000u64), 1u64)) { panic("algebraic_sub #789") }
    if !(near(V(0xc01c000000000000u64).algebraic_mul(V(0x4008000000000000u64)), V(0xc035000000000000u64), 1u64)) { panic("algebraic_mul #790") }
    if !(near(V(0xc01c000000000000u64).algebraic_div(V(0x4008000000000000u64)), V(0xc002aaaaaaaaaaabu64), 1u64)) { panic("algebraic_div #791") }
    if !(near(V(0xc01c000000000000u64).algebraic_rem(V(0x4008000000000000u64)), V(0xbff0000000000000u64), 1u64)) { panic("algebraic_rem #792") }
    if !(near(V(0xc01c000000000000u64).hypot(V(0x4008000000000000u64)), V(0x401e768d399dc470u64), 2u64)) { panic("hypot #793") }
    if !(near(V(0xc01c000000000000u64).atan2(V(0x4008000000000000u64)), V(0xbff2a78b84fbf5fcu64), 2u64)) { panic("atan2 #794") }
    if !(V(0x401c000000000000u64).copysign(V(0xc008000000000000u64)).to_bits() == 0xc01c000000000000u64) { panic("copysign #795") }
    if !(V(0x401c000000000000u64).min(V(0xc008000000000000u64)).to_bits() == 0xc008000000000000u64) { panic("min #796") }
    if !(V(0x401c000000000000u64).max(V(0xc008000000000000u64)).to_bits() == 0x401c000000000000u64) { panic("max #797") }
    if !(V(0x401c000000000000u64).total_cmp(V(0xc008000000000000u64)) == Ordering.Greater) { panic("total_cmp #798") }
    if !(V(0x401c000000000000u64).rem_euclid(V(0xc008000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("rem_euclid #799") }
    if !(V(0x401c000000000000u64).div_euclid(V(0xc008000000000000u64)).to_bits() == 0xc000000000000000u64) { panic("div_euclid #800") }
    if !(V(0x401c000000000000u64).midpoint(V(0xc008000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("midpoint #801") }
    if !(near(V(0x401c000000000000u64).algebraic_add(V(0xc008000000000000u64)), V(0x4010000000000000u64), 1u64)) { panic("algebraic_add #802") }
    if !(near(V(0x401c000000000000u64).algebraic_sub(V(0xc008000000000000u64)), V(0x4024000000000000u64), 1u64)) { panic("algebraic_sub #803") }
    if !(near(V(0x401c000000000000u64).algebraic_mul(V(0xc008000000000000u64)), V(0xc035000000000000u64), 1u64)) { panic("algebraic_mul #804") }
    if !(near(V(0x401c000000000000u64).algebraic_div(V(0xc008000000000000u64)), V(0xc002aaaaaaaaaaabu64), 1u64)) { panic("algebraic_div #805") }
    if !(near(V(0x401c000000000000u64).algebraic_rem(V(0xc008000000000000u64)), V(0x3ff0000000000000u64), 1u64)) { panic("algebraic_rem #806") }
    if !(near(V(0x401c000000000000u64).hypot(V(0xc008000000000000u64)), V(0x401e768d399dc470u64), 2u64)) { panic("hypot #807") }
    if !(near(V(0x401c000000000000u64).atan2(V(0xc008000000000000u64)), V(0x3fff9c6b238c6434u64), 2u64)) { panic("atan2 #808") }
    if !(V(0xc01c000000000000u64).copysign(V(0xc008000000000000u64)).to_bits() == 0xc01c000000000000u64) { panic("copysign #809") }
    if !(V(0xc01c000000000000u64).min(V(0xc008000000000000u64)).to_bits() == 0xc01c000000000000u64) { panic("min #810") }
    if !(V(0xc01c000000000000u64).max(V(0xc008000000000000u64)).to_bits() == 0xc008000000000000u64) { panic("max #811") }
    if !(V(0xc01c000000000000u64).total_cmp(V(0xc008000000000000u64)) == Ordering.Less) { panic("total_cmp #812") }
    if !(V(0xc01c000000000000u64).rem_euclid(V(0xc008000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("rem_euclid #813") }
    if !(V(0xc01c000000000000u64).div_euclid(V(0xc008000000000000u64)).to_bits() == 0x4008000000000000u64) { panic("div_euclid #814") }
    if !(V(0xc01c000000000000u64).midpoint(V(0xc008000000000000u64)).to_bits() == 0xc014000000000000u64) { panic("midpoint #815") }
    if !(near(V(0xc01c000000000000u64).algebraic_add(V(0xc008000000000000u64)), V(0xc024000000000000u64), 1u64)) { panic("algebraic_add #816") }
    if !(near(V(0xc01c000000000000u64).algebraic_sub(V(0xc008000000000000u64)), V(0xc010000000000000u64), 1u64)) { panic("algebraic_sub #817") }
    if !(near(V(0xc01c000000000000u64).algebraic_mul(V(0xc008000000000000u64)), V(0x4035000000000000u64), 1u64)) { panic("algebraic_mul #818") }
    if !(near(V(0xc01c000000000000u64).algebraic_div(V(0xc008000000000000u64)), V(0x4002aaaaaaaaaaabu64), 1u64)) { panic("algebraic_div #819") }
    if !(near(V(0xc01c000000000000u64).algebraic_rem(V(0xc008000000000000u64)), V(0xbff0000000000000u64), 1u64)) { panic("algebraic_rem #820") }
    if !(near(V(0xc01c000000000000u64).hypot(V(0xc008000000000000u64)), V(0x401e768d399dc470u64), 2u64)) { panic("hypot #821") }
    if !(near(V(0xc01c000000000000u64).atan2(V(0xc008000000000000u64)), V(0xbfff9c6b238c6434u64), 2u64)) { panic("atan2 #822") }
    if !(V(0x3fb999999999999au64).copysign(V(0x4008000000000000u64)).to_bits() == 0x3fb999999999999au64) { panic("copysign #823") }
    if !(V(0x3fb999999999999au64).min(V(0x4008000000000000u64)).to_bits() == 0x3fb999999999999au64) { panic("min #824") }
    if !(V(0x3fb999999999999au64).max(V(0x4008000000000000u64)).to_bits() == 0x4008000000000000u64) { panic("max #825") }
    if !(V(0x3fb999999999999au64).total_cmp(V(0x4008000000000000u64)) == Ordering.Less) { panic("total_cmp #826") }
    if !(V(0x3fb999999999999au64).rem_euclid(V(0x4008000000000000u64)).to_bits() == 0x3fb999999999999au64) { panic("rem_euclid #827") }
    if !(V(0x3fb999999999999au64).div_euclid(V(0x4008000000000000u64)).to_bits() == 0x0u64) { panic("div_euclid #828") }
    if !(V(0x3fb999999999999au64).midpoint(V(0x4008000000000000u64)).to_bits() == 0x3ff8cccccccccccdu64) { panic("midpoint #829") }
    if !(near(V(0x3fb999999999999au64).algebraic_add(V(0x4008000000000000u64)), V(0x4008cccccccccccdu64), 1u64)) { panic("algebraic_add #830") }
    if !(near(V(0x3fb999999999999au64).algebraic_sub(V(0x4008000000000000u64)), V(0xc007333333333333u64), 1u64)) { panic("algebraic_sub #831") }
    if !(near(V(0x3fb999999999999au64).algebraic_mul(V(0x4008000000000000u64)), V(0x3fd3333333333334u64), 1u64)) { panic("algebraic_mul #832") }
    if !(near(V(0x3fb999999999999au64).algebraic_div(V(0x4008000000000000u64)), V(0x3fa1111111111111u64), 1u64)) { panic("algebraic_div #833") }
    if !(near(V(0x3fb999999999999au64).algebraic_rem(V(0x4008000000000000u64)), V(0x3fb999999999999au64), 1u64)) { panic("algebraic_rem #834") }
    if !(near(V(0x3fb999999999999au64).hypot(V(0x4008000000000000u64)), V(0x40080369921c2886u64), 2u64)) { panic("hypot #835") }
    if !(near(V(0x3fb999999999999au64).atan2(V(0x4008000000000000u64)), V(0x3fa10f7317226afdu64), 2u64)) { panic("atan2 #836") }
    if !(V(0x1u64).copysign(V(0x10000000000000u64)).to_bits() == 0x1u64) { panic("copysign #837") }
    if !(V(0x1u64).min(V(0x10000000000000u64)).to_bits() == 0x1u64) { panic("min #838") }
    if !(V(0x1u64).max(V(0x10000000000000u64)).to_bits() == 0x10000000000000u64) { panic("max #839") }
    if !(V(0x1u64).total_cmp(V(0x10000000000000u64)) == Ordering.Less) { panic("total_cmp #840") }
}

fn group7() {
    if !(V(0x1u64).rem_euclid(V(0x10000000000000u64)).to_bits() == 0x1u64) { panic("rem_euclid #841") }
    if !(V(0x1u64).div_euclid(V(0x10000000000000u64)).to_bits() == 0x0u64) { panic("div_euclid #842") }
    if !(V(0x1u64).midpoint(V(0x10000000000000u64)).to_bits() == 0x8000000000000u64) { panic("midpoint #843") }
    if !(near(V(0x1u64).algebraic_add(V(0x10000000000000u64)), V(0x10000000000001u64), 1u64)) { panic("algebraic_add #844") }
    if !(near(V(0x1u64).algebraic_sub(V(0x10000000000000u64)), V(0x800fffffffffffffu64), 1u64)) { panic("algebraic_sub #845") }
    if !(V(0x1u64).algebraic_mul(V(0x10000000000000u64)).to_bits() == 0x0u64) { panic("algebraic_mul #846") }
    if !(near(V(0x1u64).algebraic_div(V(0x10000000000000u64)), V(0x3cb0000000000000u64), 1u64)) { panic("algebraic_div #847") }
    if !(near(V(0x1u64).algebraic_rem(V(0x10000000000000u64)), V(0x1u64), 1u64)) { panic("algebraic_rem #848") }
    if !(near(V(0x1u64).hypot(V(0x10000000000000u64)), V(0x10000000000000u64), 2u64)) { panic("hypot #849") }
    if !(near(V(0x1u64).atan2(V(0x10000000000000u64)), V(0x3cb0000000000000u64), 2u64)) { panic("atan2 #850") }
    if !(V(0x4014000000000000u64).clamp(V(0x3ff0000000000000u64), V(0x4008000000000000u64)).to_bits() == 0x4008000000000000u64) { panic("clamp #851") }
    if !(V(0xc014000000000000u64).clamp(V(0x3ff0000000000000u64), V(0x4008000000000000u64)).to_bits() == 0x3ff0000000000000u64) { panic("clamp #852") }
    if !(V(0x4000000000000000u64).clamp(V(0x3ff0000000000000u64), V(0x4008000000000000u64)).to_bits() == 0x4000000000000000u64) { panic("clamp #853") }
    if !(V(0x7ff8000000000000u64).clamp(V(0x3ff0000000000000u64), V(0x4008000000000000u64)).is_nan()) { panic("clamp #854") }
    if !(V(0x8000000000000000u64).clamp(V(0x0u64), V(0x3ff0000000000000u64)).to_bits() == 0x8000000000000000u64) { panic("clamp #855") }
    if !(V(0x4000000000000000u64).mul_add(V(0x4008000000000000u64), V(0x4010000000000000u64)).to_bits() == 0x4024000000000000u64) { panic("mul_add #856") }
    if !(V(0xbff8000000000000u64).mul_add(V(0x4000000000000000u64), V(0x3fd0000000000000u64)).to_bits() == 0xc006000000000000u64) { panic("mul_add #857") }
    if !(V(0x3fb999999999999au64).mul_add(V(0x4024000000000000u64), V(0xbff0000000000000u64)).to_bits() == 0x3c90000000000000u64) { panic("mul_add #858") }
    if !(V(0x7fefffffffffffffu64).mul_add(V(0x4000000000000000u64), V(0xffefffffffffffffu64)).to_bits() == 0x7fefffffffffffffu64) { panic("mul_add #859") }
    if !(near(V(0xc024000000000000u64).sin(), V(0x3fe1689ef5f34f52u64), 2u64)) { panic("sin #860") }
    if !(near(V(0xbff8000000000000u64).sin(), V(0xbfefeb7a9b2c6d8bu64), 2u64)) { panic("sin #861") }
    if !(near(V(0xbfb999999999999au64).sin(), V(0xbfb98eaecb8bcb2cu64), 2u64)) { panic("sin #862") }
    if !(V(0x0u64).sin().to_bits() == 0x0u64) { panic("sin #863") }
    if !(near(V(0x3fe6666666666666u64).sin(), V(0x3fe49d6e694619b8u64), 2u64)) { panic("sin #864") }
    if !(near(V(0x4000000000000000u64).sin(), V(0x3fed18f6ead1b446u64), 2u64)) { panic("sin #865") }
    if !(near(V(0x403e000000000000u64).sin(), V(0xbfef9df47f1c903du64), 2u64)) { panic("sin #866") }
    if !(near(V(0xc024000000000000u64).cos(), V(0xbfead9ac890c6b1fu64), 2u64)) { panic("cos #867") }
    if !(near(V(0xbff8000000000000u64).cos(), V(0x3fb21bd54fc5f9a7u64), 2u64)) { panic("cos #868") }
    if !(near(V(0xbfb999999999999au64).cos(), V(0x3fefd712f9a817c1u64), 2u64)) { panic("cos #869") }
    if !(near(V(0x0u64).cos(), V(0x3ff0000000000000u64), 2u64)) { panic("cos #870") }
    if !(near(V(0x3fe6666666666666u64).cos(), V(0x3fe87996529f9d93u64), 2u64)) { panic("cos #871") }
    if !(near(V(0x4000000000000000u64).cos(), V(0xbfdaa22657537205u64), 2u64)) { panic("cos #872") }
    if !(near(V(0x403e000000000000u64).cos(), V(0x3fc3be82f2505a52u64), 2u64)) { panic("cos #873") }
    if !(near(V(0xc024000000000000u64).tan(), V(0xbfe4bf5f34be3782u64), 4u64)) { panic("tan #874") }
    if !(near(V(0xbff8000000000000u64).tan(), V(0xc02c33ed50b88777u64), 4u64)) { panic("tan #875") }
    if !(near(V(0xbfb999999999999au64).tan(), V(0xbfb9af8877430b80u64), 4u64)) { panic("tan #876") }
    if !(V(0x0u64).tan().to_bits() == 0x0u64) { panic("tan #877") }
    if !(near(V(0x3fe6666666666666u64).tan(), V(0x3feaf406c2fc78aeu64), 4u64)) { panic("tan #878") }
    if !(near(V(0x4000000000000000u64).tan(), V(0xc0017af62e0950f8u64), 4u64)) { panic("tan #879") }
    if !(near(V(0x403e000000000000u64).tan(), V(0xc0199f0f242693c3u64), 4u64)) { panic("tan #880") }
    if !(near(V(0xbfeccccccccccccdu64).asin(), V(0xbff1ea93705fa172u64), 2u64)) { panic("asin #881") }
    if !(near(V(0xbfe0000000000000u64).asin(), V(0xbfe0c152382d7366u64), 2u64)) { panic("asin #882") }
    if !(V(0x0u64).asin().to_bits() == 0x0u64) { panic("asin #883") }
    if !(near(V(0x3fd3333333333333u64).asin(), V(0x3fd380159e14f6ffu64), 2u64)) { panic("asin #884") }
    if !(near(V(0x3fe8000000000000u64).asin(), V(0x3feb235315c680dcu64), 2u64)) { panic("asin #885") }
    if !(near(V(0xbfeccccccccccccdu64).acos(), V(0x400586476251e745u64), 2u64)) { panic("acos #886") }
    if !(near(V(0xbfe0000000000000u64).acos(), V(0x4000c152382d7366u64), 2u64)) { panic("acos #887") }
    if !(near(V(0x0u64).acos(), V(0x3ff921fb54442d18u64), 2u64)) { panic("acos #888") }
    if !(near(V(0x3fd3333333333333u64).acos(), V(0x3ff441f5ecbeef59u64), 2u64)) { panic("acos #889") }
    if !(near(V(0x3fe8000000000000u64).acos(), V(0x3fe720a392c1d955u64), 2u64)) { panic("acos #890") }
    if !(near(V(0xc024000000000000u64).atan(), V(0xbff789bd2c160054u64), 2u64)) { panic("atan #891") }
    if !(near(V(0xbff8000000000000u64).atan(), V(0xbfef730bd281f69bu64), 2u64)) { panic("atan #892") }
    if !(near(V(0xbfb999999999999au64).atan(), V(0xbfb983e282e2cc4du64), 2u64)) { panic("atan #893") }
    if !(V(0x0u64).atan().to_bits() == 0x0u64) { panic("atan #894") }
    if !(near(V(0x3fe6666666666666u64).atan(), V(0x3fe38b112d7bd4adu64), 2u64)) { panic("atan #895") }
    if !(near(V(0x4000000000000000u64).atan(), V(0x3ff1b6e192ebbe44u64), 2u64)) { panic("atan #896") }
    if !(near(V(0x403e000000000000u64).atan(), V(0x3ff8997fbb8b19c0u64), 2u64)) { panic("atan #897") }
    if !(near(V(0xc024000000000000u64).sinh(), V(0xc0c5829dced69992u64), 2u64)) { panic("sinh #898") }
    if !(near(V(0xbff8000000000000u64).sinh(), V(0xc00108c3aabd6a60u64), 2u64)) { panic("sinh #899") }
    if !(near(V(0xbfb999999999999au64).sinh(), V(0xbfb9a487337b59b3u64), 2u64)) { panic("sinh #900") }
    if !(V(0x0u64).sinh().to_bits() == 0x0u64) { panic("sinh #901") }
    if !(near(V(0x3fe6666666666666u64).sinh(), V(0x3fe8465153d5bdbcu64), 2u64)) { panic("sinh #902") }
    if !(near(V(0x4000000000000000u64).sinh(), V(0x400d03cf63b6e1a0u64), 2u64)) { panic("sinh #903") }
    if !(near(V(0x403e000000000000u64).sinh(), V(0x429370470aec28edu64), 2u64)) { panic("sinh #904") }
    if !(near(V(0xc024000000000000u64).cosh(), V(0x40c5829dd053712eu64), 2u64)) { panic("cosh #905") }
    if !(near(V(0xbff8000000000000u64).cosh(), V(0x4002d1bc21e22022u64), 2u64)) { panic("cosh #906") }
    if !(near(V(0xbfb999999999999au64).cosh(), V(0x3ff0147f40224b38u64), 2u64)) { panic("cosh #907") }
    if !(near(V(0x0u64).cosh(), V(0x3ff0000000000000u64), 2u64)) { panic("cosh #908") }
    if !(near(V(0x3fe6666666666666u64).cosh(), V(0x3ff4152c1862342fu64), 2u64)) { panic("cosh #909") }
    if !(near(V(0x4000000000000000u64).cosh(), V(0x400e18fa0df2d9bcu64), 2u64)) { panic("cosh #910") }
    if !(near(V(0x403e000000000000u64).cosh(), V(0x429370470aec28edu64), 2u64)) { panic("cosh #911") }
    if !(near(V(0xc024000000000000u64).tanh(), V(0xbfeffffffdc96f35u64), 2u64)) { panic("tanh #912") }
    if !(near(V(0xbff8000000000000u64).tanh(), V(0xbfecf6f9786df577u64), 2u64)) { panic("tanh #913") }
    if !(near(V(0xbfb999999999999au64).tanh(), V(0xbfb983d7795f413au64), 2u64)) { panic("tanh #914") }
    if !(V(0x0u64).tanh().to_bits() == 0x0u64) { panic("tanh #915") }
    if !(near(V(0x3fe6666666666666u64).tanh(), V(0x3fe356fb17af2e92u64), 2u64)) { panic("tanh #916") }
    if !(near(V(0x4000000000000000u64).tanh(), V(0x3feed9505e1bc3d4u64), 2u64)) { panic("tanh #917") }
    if !(near(V(0x403e000000000000u64).tanh(), V(0x3ff0000000000000u64), 2u64)) { panic("tanh #918") }
    if !(near(V(0xc024000000000000u64).asinh(), V(0xc007fc5c506d2bdbu64), 2u64)) { panic("asinh #919") }
    if !(near(V(0xbff8000000000000u64).asinh(), V(0xbff31dc0090b63d8u64), 2u64)) { panic("asinh #920") }
    if !(near(V(0xbfb999999999999au64).asinh(), V(0xbfb98eb9e7e5fc3eu64), 2u64)) { panic("asinh #921") }
    if !(V(0x0u64).asinh().to_bits() == 0x0u64) { panic("asinh #922") }
    if !(near(V(0x3fe6666666666666u64).asinh(), V(0x3fe4e2a4fe9085ddu64), 2u64)) { panic("asinh #923") }
    if !(near(V(0x4000000000000000u64).asinh(), V(0x3ff719218313d087u64), 2u64)) { panic("asinh #924") }
    if !(near(V(0x403e000000000000u64).asinh(), V(0x401060e4a5fbe5cau64), 2u64)) { panic("asinh #925") }
    if !(near(V(0x3ff4000000000000u64).acosh(), V(0x3fe62e42fefa39efu64), 2u64)) { panic("acosh #926") }
    if !(near(V(0x3ff8000000000000u64).acosh(), V(0x3feecc2caec5160au64), 2u64)) { panic("acosh #927") }
    if !(near(V(0x4000000000000000u64).acosh(), V(0x3ff5124271980435u64), 2u64)) { panic("acosh #928") }
    if !(near(V(0x4004000000000000u64).acosh(), V(0x3ff9119c13a31bb0u64), 2u64)) { panic("acosh #929") }
    if !(near(V(0x4008000000000000u64).acosh(), V(0x3ffc34366179d427u64), 2u64)) { panic("acosh #930") }
    if !(near(V(0x4026000000000000u64).acosh(), V(0x4008b635da7d161fu64), 2u64)) { panic("acosh #931") }
    if !(near(V(0x405f1d2f1a9fbe77u64).acosh(), V(0x4016117e477fc72du64), 2u64)) { panic("acosh #932") }
    if !(near(V(0x3ff0000a7c5ac472u64).acosh(), V(0x3f72515eda9e7930u64), 2u64)) { panic("acosh #933") }
    if !(near(V(0xbfeccccccccccccdu64).atanh(), V(0xbff78e360604b32du64), 2u64)) { panic("atanh #934") }
    if !(near(V(0xbfe0000000000000u64).atanh(), V(0xbfe193ea7aad030bu64), 2u64)) { panic("atanh #935") }
    if !(V(0x0u64).atanh().to_bits() == 0x0u64) { panic("atanh #936") }
    if !(near(V(0x3fd3333333333333u64).atanh(), V(0x3fd3cf2b50617c95u64), 2u64)) { panic("atanh #937") }
    if !(near(V(0x3fe8000000000000u64).atanh(), V(0x3fef2272ae325a57u64), 2u64)) { panic("atanh #938") }
    if !(near(V(0xc024000000000000u64).exp(), V(0x3f07cd79b5647c9bu64), 2u64)) { panic("exp #939") }
    if !(near(V(0xbff8000000000000u64).exp(), V(0x3fcc8f87724b5c1du64), 2u64)) { panic("exp #940") }
    if !(near(V(0xbfb999999999999au64).exp(), V(0x3fecf46d99d52b3au64), 2u64)) { panic("exp #941") }
    if !(near(V(0x0u64).exp(), V(0x3ff0000000000000u64), 2u64)) { panic("exp #942") }
    if !(near(V(0x3fe6666666666666u64).exp(), V(0x40001c2a61268987u64), 2u64)) { panic("exp #943") }
    if !(near(V(0x4000000000000000u64).exp(), V(0x401d8e64b8d4ddaeu64), 2u64)) { panic("exp #944") }
    if !(near(V(0x403e000000000000u64).exp(), V(0x42a370470aec28edu64), 2u64)) { panic("exp #945") }
    if !(near(V(0xc024000000000000u64).exp2(), V(0x3f50000000000000u64), 4u64)) { panic("exp2 #946") }
    if !(near(V(0xbff8000000000000u64).exp2(), V(0x3fd6a09e667f3bcdu64), 4u64)) { panic("exp2 #947") }
    if !(near(V(0xbfb999999999999au64).exp2(), V(0x3feddb680117ab12u64), 4u64)) { panic("exp2 #948") }
    if !(near(V(0x0u64).exp2(), V(0x3ff0000000000000u64), 4u64)) { panic("exp2 #949") }
    if !(near(V(0x3fe6666666666666u64).exp2(), V(0x3ff9fdf8bcce533du64), 4u64)) { panic("exp2 #950") }
    if !(near(V(0x4000000000000000u64).exp2(), V(0x4010000000000000u64), 4u64)) { panic("exp2 #951") }
    if !(near(V(0x403e000000000000u64).exp2(), V(0x41d0000000000000u64), 4u64)) { panic("exp2 #952") }
    if !(near(V(0xc024000000000000u64).exp_m1(), V(0xbfefffa0ca192a6eu64), 2u64)) { panic("exp_m1 #953") }
    if !(near(V(0xbff8000000000000u64).exp_m1(), V(0xbfe8dc1e236d28f9u64), 2u64)) { panic("exp_m1 #954") }
    if !(near(V(0xbfb999999999999au64).exp_m1(), V(0xbfb85c933156a62cu64), 2u64)) { panic("exp_m1 #955") }
    if !(V(0x0u64).exp_m1().to_bits() == 0x0u64) { panic("exp_m1 #956") }
    if !(near(V(0x3fe6666666666666u64).exp_m1(), V(0x3ff03854c24d130du64), 2u64)) { panic("exp_m1 #957") }
    if !(near(V(0x4000000000000000u64).exp_m1(), V(0x40198e64b8d4ddaeu64), 2u64)) { panic("exp_m1 #958") }
    if !(near(V(0x403e000000000000u64).exp_m1(), V(0x42a370470aec26edu64), 2u64)) { panic("exp_m1 #959") }
    if !(near(V(0x3fd0000000000000u64).ln(), V(0xbff62e42fefa39efu64), 2u64)) { panic("ln #960") }
}

fn group8() {
    if !(near(V(0x3fe0000000000000u64).ln(), V(0xbfe62e42fefa39efu64), 2u64)) { panic("ln #961") }
    if !(V(0x3ff0000000000000u64).ln().to_bits() == 0x0u64) { panic("ln #962") }
    if !(near(V(0x3ff8000000000000u64).ln(), V(0x3fd9f323ecbf984cu64), 2u64)) { panic("ln #963") }
    if !(near(V(0x4000000000000000u64).ln(), V(0x3fe62e42fefa39efu64), 2u64)) { panic("ln #964") }
    if !(near(V(0x4024000000000000u64).ln(), V(0x40026bb1bbb55516u64), 2u64)) { panic("ln #965") }
    if !(near(V(0x405edd2f1a9fbe77u64).ln(), V(0x401343774f3e2362u64), 2u64)) { panic("ln #966") }
    if !(near(V(0x3ee4f8b588e368f1u64).ln(), V(0xc027069e2aa2aa5bu64), 2u64)) { panic("ln #967") }
    if !(near(V(0x3fd0000000000000u64).ln_1p(), V(0x3fcc8ff7c79a9a22u64), 2u64)) { panic("ln_1p #968") }
    if !(near(V(0x3fe0000000000000u64).ln_1p(), V(0x3fd9f323ecbf984cu64), 2u64)) { panic("ln_1p #969") }
    if !(near(V(0x3ff0000000000000u64).ln_1p(), V(0x3fe62e42fefa39efu64), 2u64)) { panic("ln_1p #970") }
    if !(near(V(0x3ff8000000000000u64).ln_1p(), V(0x3fed5240f0e0e078u64), 2u64)) { panic("ln_1p #971") }
    if !(near(V(0x4000000000000000u64).ln_1p(), V(0x3ff193ea7aad030au64), 2u64)) { panic("ln_1p #972") }
    if !(near(V(0x4024000000000000u64).ln_1p(), V(0x40032ee3b77f374cu64), 2u64)) { panic("ln_1p #973") }
    if !(near(V(0x405edd2f1a9fbe77u64).ln_1p(), V(0x40134bba22cd5df5u64), 2u64)) { panic("ln_1p #974") }
    if !(near(V(0x3ee4f8b588e368f1u64).ln_1p(), V(0x3ee4f8aea9ae7317u64), 2u64)) { panic("ln_1p #975") }
    if !(near(V(0xbfeccccccccccccdu64).ln_1p(), V(0xc0026bb1bbb55516u64), 2u64)) { panic("ln_1p #976") }
    if !(near(V(0xbfe0000000000000u64).ln_1p(), V(0xbfe62e42fefa39efu64), 2u64)) { panic("ln_1p #977") }
    if !(V(0x0u64).ln_1p().to_bits() == 0x0u64) { panic("ln_1p #978") }
    if !(near(V(0x3fd3333333333333u64).ln_1p(), V(0x3fd0ca937be1b9dcu64), 2u64)) { panic("ln_1p #979") }
    if !(near(V(0x3fe8000000000000u64).ln_1p(), V(0x3fe1e85f5e7040d0u64), 2u64)) { panic("ln_1p #980") }
    if !(near(V(0x3fd0000000000000u64).log2(), V(0xc000000000000000u64), 2u64)) { panic("log2 #981") }
    if !(near(V(0x3fe0000000000000u64).log2(), V(0xbff0000000000000u64), 2u64)) { panic("log2 #982") }
    if !(V(0x3ff0000000000000u64).log2().to_bits() == 0x0u64) { panic("log2 #983") }
    if !(near(V(0x3ff8000000000000u64).log2(), V(0x3fe2b803473f7ad1u64), 2u64)) { panic("log2 #984") }
    if !(near(V(0x4000000000000000u64).log2(), V(0x3ff0000000000000u64), 2u64)) { panic("log2 #985") }
    if !(near(V(0x4024000000000000u64).log2(), V(0x400a934f0979a371u64), 2u64)) { panic("log2 #986") }
    if !(near(V(0x405edd2f1a9fbe77u64).log2(), V(0x401bca9a03b1083au64), 2u64)) { panic("log2 #987") }
    if !(near(V(0x3ee4f8b588e368f1u64).log2(), V(0xc0309c1165ec0627u64), 2u64)) { panic("log2 #988") }
    if !(near(V(0x3fd0000000000000u64).log10(), V(0xbfe34413509f79ffu64), 2u64)) { panic("log10 #989") }
    if !(near(V(0x3fe0000000000000u64).log10(), V(0xbfd34413509f79ffu64), 2u64)) { panic("log10 #990") }
    if !(V(0x3ff0000000000000u64).log10().to_bits() == 0x0u64) { panic("log10 #991") }
    if !(near(V(0x3ff8000000000000u64).log10(), V(0x3fc68a288b60b7fcu64), 2u64)) { panic("log10 #992") }
    if !(near(V(0x4000000000000000u64).log10(), V(0x3fd34413509f79ffu64), 2u64)) { panic("log10 #993") }
    if !(near(V(0x4024000000000000u64).log10(), V(0x3ff0000000000000u64), 2u64)) { panic("log10 #994") }
    if !(near(V(0x405edd2f1a9fbe77u64).log10(), V(0x4000bb6abfc968efu64), 2u64)) { panic("log10 #995") }
    if !(near(V(0x3ee4f8b588e368f1u64).log10(), V(0xc014000000000000u64), 2u64)) { panic("log10 #996") }
    if !(near(V(0xc024000000000000u64).cbrt(), V(0xc0013c484138704fu64), 4u64)) { panic("cbrt #997") }
    if !(near(V(0xbff8000000000000u64).cbrt(), V(0xbff250bfe1b082f5u64), 4u64)) { panic("cbrt #998") }
    if !(near(V(0xbfb999999999999au64).cbrt(), V(0xbfddb4c7760bcff3u64), 4u64)) { panic("cbrt #999") }
    if !(V(0x0u64).cbrt().to_bits() == 0x0u64) { panic("cbrt #1000") }
    if !(near(V(0x3fe6666666666666u64).cbrt(), V(0x3fec69b5a72f1a99u64), 4u64)) { panic("cbrt #1001") }
    if !(near(V(0x4000000000000000u64).cbrt(), V(0x3ff428a2f98d728bu64), 4u64)) { panic("cbrt #1002") }
    if !(near(V(0x403e000000000000u64).cbrt(), V(0x4008db9cb7511e9du64), 4u64)) { panic("cbrt #1003") }
    if !(V(0x0u64).ln().to_bits() == 0xfff0000000000000u64) { panic("ln #1004") }
    if !(V(0xbff0000000000000u64).ln().is_nan()) { panic("ln #1005") }
    if !(V(0xbff0000000000000u64).sqrt().is_nan()) { panic("sqrt #1006") }
    if !(V(0xfff0000000000000u64).exp().to_bits() == 0x0u64) { panic("exp #1007") }
    if !(V(0x7ff0000000000000u64).exp().to_bits() == 0x7ff0000000000000u64) { panic("exp #1008") }
    if !(V(0x4000000000000000u64).asin().is_nan()) { panic("asin #1009") }
    if !(V(0x3ff0000000000000u64).ln().to_bits() == 0x0u64) { panic("ln #1010") }
    if !(V(0x0u64).exp().to_bits() == 0x3ff0000000000000u64) { panic("exp #1011") }
    if !(near(V(0xc024000000000000u64).sin_cos().0, V(0x3fe1689ef5f34f52u64), 2u64) && near(V(0xc024000000000000u64).sin_cos().1, V(0xbfead9ac890c6b1fu64), 2u64)) { panic("sin_cos #1012") }
    if !(near(V(0xc024000000000000u64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1013") }
    if !(near(V(0xc024000000000000u64).powi(1i32), V(0xc024000000000000u64), 4u64)) { panic("powi #1014") }
    if !(near(V(0xc024000000000000u64).powi(2i32), V(0x4059000000000000u64), 4u64)) { panic("powi #1015") }
    if !(near(V(0xc024000000000000u64).powi(3i32), V(0xc08f400000000000u64), 4u64)) { panic("powi #1016") }
    if !(near(V(0xc024000000000000u64).powi((-2i32)), V(0x3f847ae147ae147bu64), 4u64)) { panic("powi #1017") }
    if !(near(V(0xc024000000000000u64).to_degrees(), V(0xc081e7a9907e593bu64), 1u64)) { panic("to_degrees #1018") }
    if !(near(V(0xc024000000000000u64).to_radians(), V(0xbfc657184ae74487u64), 1u64)) { panic("to_radians #1019") }
    if !(near(V(0xbff8000000000000u64).sin_cos().0, V(0xbfefeb7a9b2c6d8bu64), 2u64) && near(V(0xbff8000000000000u64).sin_cos().1, V(0x3fb21bd54fc5f9a7u64), 2u64)) { panic("sin_cos #1020") }
    if !(near(V(0xbff8000000000000u64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1021") }
    if !(near(V(0xbff8000000000000u64).powi(1i32), V(0xbff8000000000000u64), 4u64)) { panic("powi #1022") }
    if !(near(V(0xbff8000000000000u64).powi(2i32), V(0x4002000000000000u64), 4u64)) { panic("powi #1023") }
    if !(near(V(0xbff8000000000000u64).powi(3i32), V(0xc00b000000000000u64), 4u64)) { panic("powi #1024") }
    if !(near(V(0xbff8000000000000u64).powi((-2i32)), V(0x3fdc71c71c71c71cu64), 4u64)) { panic("powi #1025") }
    if !(near(V(0xbff8000000000000u64).to_degrees(), V(0xc0557c6513cad17au64), 1u64)) { panic("to_degrees #1026") }
    if !(near(V(0xbff8000000000000u64).to_radians(), V(0xbf9acee9f37bebd6u64), 1u64)) { panic("to_radians #1027") }
    if !(near(V(0xbfb999999999999au64).sin_cos().0, V(0xbfb98eaecb8bcb2cu64), 2u64) && near(V(0xbfb999999999999au64).sin_cos().1, V(0x3fefd712f9a817c1u64), 2u64)) { panic("sin_cos #1028") }
    if !(near(V(0xbfb999999999999au64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1029") }
    if !(near(V(0xbfb999999999999au64).powi(1i32), V(0xbfb999999999999au64), 4u64)) { panic("powi #1030") }
    if !(near(V(0xbfb999999999999au64).powi(2i32), V(0x3f847ae147ae147cu64), 4u64)) { panic("powi #1031") }
    if !(near(V(0xbfb999999999999au64).powi(3i32), V(0xbf50624dd2f1a9fdu64), 4u64)) { panic("powi #1032") }
    if !(near(V(0xbfb999999999999au64).powi((-2i32)), V(0x4058ffffffffffffu64), 4u64)) { panic("powi #1033") }
    if !(near(V(0xbfb999999999999au64).to_degrees(), V(0xc016eb167b830194u64), 1u64)) { panic("to_degrees #1034") }
    if !(near(V(0xbfb999999999999au64).to_radians(), V(0xbf5c987103b761f5u64), 1u64)) { panic("to_radians #1035") }
    if !(near(V(0x0u64).sin_cos().0, V(0x0u64), 2u64) && near(V(0x0u64).sin_cos().1, V(0x3ff0000000000000u64), 2u64)) { panic("sin_cos #1036") }
    if !(near(V(0x0u64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1037") }
    if !(V(0x0u64).powi(1i32).to_bits() == 0x0u64) { panic("powi #1038") }
    if !(V(0x0u64).powi(2i32).to_bits() == 0x0u64) { panic("powi #1039") }
    if !(V(0x0u64).powi(3i32).to_bits() == 0x0u64) { panic("powi #1040") }
    if !(V(0x0u64).powi((-2i32)).to_bits() == 0x7ff0000000000000u64) { panic("powi #1041") }
    if !(V(0x0u64).to_degrees().to_bits() == 0x0u64) { panic("to_degrees #1042") }
    if !(V(0x0u64).to_radians().to_bits() == 0x0u64) { panic("to_radians #1043") }
    if !(near(V(0x3fe6666666666666u64).sin_cos().0, V(0x3fe49d6e694619b8u64), 2u64) && near(V(0x3fe6666666666666u64).sin_cos().1, V(0x3fe87996529f9d93u64), 2u64)) { panic("sin_cos #1044") }
    if !(near(V(0x3fe6666666666666u64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1045") }
    if !(near(V(0x3fe6666666666666u64).powi(1i32), V(0x3fe6666666666666u64), 4u64)) { panic("powi #1046") }
    if !(near(V(0x3fe6666666666666u64).powi(2i32), V(0x3fdf5c28f5c28f5bu64), 4u64)) { panic("powi #1047") }
    if !(near(V(0x3fe6666666666666u64).powi(3i32), V(0x3fd5f3b645a1cabfu64), 4u64)) { panic("powi #1048") }
    if !(near(V(0x3fe6666666666666u64).powi((-2i32)), V(0x40005397829cbc15u64), 4u64)) { panic("powi #1049") }
    if !(near(V(0x3fe6666666666666u64).to_degrees(), V(0x40440db3ac12a160u64), 1u64)) { panic("to_degrees #1050") }
    if !(near(V(0x3fe6666666666666u64).to_radians(), V(0x3f890562e34075b6u64), 1u64)) { panic("to_radians #1051") }
    if !(near(V(0x4000000000000000u64).sin_cos().0, V(0x3fed18f6ead1b446u64), 2u64) && near(V(0x4000000000000000u64).sin_cos().1, V(0xbfdaa22657537205u64), 2u64)) { panic("sin_cos #1052") }
    if !(near(V(0x4000000000000000u64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1053") }
    if !(near(V(0x4000000000000000u64).powi(1i32), V(0x4000000000000000u64), 4u64)) { panic("powi #1054") }
    if !(near(V(0x4000000000000000u64).powi(2i32), V(0x4010000000000000u64), 4u64)) { panic("powi #1055") }
    if !(near(V(0x4000000000000000u64).powi(3i32), V(0x4020000000000000u64), 4u64)) { panic("powi #1056") }
    if !(near(V(0x4000000000000000u64).powi((-2i32)), V(0x3fd0000000000000u64), 4u64)) { panic("powi #1057") }
    if !(near(V(0x4000000000000000u64).to_degrees(), V(0x405ca5dc1a63c1f8u64), 1u64)) { panic("to_degrees #1058") }
    if !(near(V(0x4000000000000000u64).to_radians(), V(0x3fa1df46a2529d39u64), 1u64)) { panic("to_radians #1059") }
    if !(near(V(0x403e000000000000u64).sin_cos().0, V(0xbfef9df47f1c903du64), 2u64) && near(V(0x403e000000000000u64).sin_cos().1, V(0x3fc3be82f2505a52u64), 2u64)) { panic("sin_cos #1060") }
    if !(near(V(0x403e000000000000u64).powi(0i32), V(0x3ff0000000000000u64), 4u64)) { panic("powi #1061") }
    if !(near(V(0x403e000000000000u64).powi(1i32), V(0x403e000000000000u64), 4u64)) { panic("powi #1062") }
    if !(near(V(0x403e000000000000u64).powi(2i32), V(0x408c200000000000u64), 4u64)) { panic("powi #1063") }
    if !(near(V(0x403e000000000000u64).powi(3i32), V(0x40da5e0000000000u64), 4u64)) { panic("powi #1064") }
    if !(near(V(0x403e000000000000u64).powi((-2i32)), V(0x3f523456789abcdfu64), 4u64)) { panic("powi #1065") }
    if !(near(V(0x403e000000000000u64).to_degrees(), V(0x409adb7e58bd85d8u64), 1u64)) { panic("to_degrees #1066") }
    if !(near(V(0x403e000000000000u64).to_radians(), V(0x3fe0c152382d7365u64), 1u64)) { panic("to_radians #1067") }
    if !(near(V(0x3fd0000000000000u64).powf(V(0x3fe0000000000000u64)), V(0x3fe0000000000000u64), 2u64)) { panic("powf #1068") }
    if !(near(V(0x3fd0000000000000u64).powf(V(0x4000000000000000u64)), V(0x3fb0000000000000u64), 2u64)) { panic("powf #1069") }
    if !(near(V(0x3fd0000000000000u64).powf(V(0xbff8000000000000u64)), V(0x4020000000000000u64), 2u64)) { panic("powf #1070") }
    if !(near(V(0x3fd0000000000000u64).powf(V(0x4008000000000000u64)), V(0x3f90000000000000u64), 2u64)) { panic("powf #1071") }
    if !(near(V(0x3fd0000000000000u64).log(V(0x4000000000000000u64)), V(0xc000000000000000u64), 4u64)) { panic("log #1072") }
    if !(near(V(0x3fd0000000000000u64).log(V(0x4024000000000000u64)), V(0xbfe34413509f79feu64), 4u64)) { panic("log #1073") }
    if !(near(V(0x3fd0000000000000u64).log(V(0x400c000000000000u64)), V(0xbff1b497341428b2u64), 4u64)) { panic("log #1074") }
    if !(near(V(0x3fe0000000000000u64).powf(V(0x3fe0000000000000u64)), V(0x3fe6a09e667f3bcdu64), 2u64)) { panic("powf #1075") }
    if !(near(V(0x3fe0000000000000u64).powf(V(0x4000000000000000u64)), V(0x3fd0000000000000u64), 2u64)) { panic("powf #1076") }
    if !(near(V(0x3fe0000000000000u64).powf(V(0xbff8000000000000u64)), V(0x4006a09e667f3bcdu64), 2u64)) { panic("powf #1077") }
    if !(near(V(0x3fe0000000000000u64).powf(V(0x4008000000000000u64)), V(0x3fc0000000000000u64), 2u64)) { panic("powf #1078") }
    if !(near(V(0x3fe0000000000000u64).log(V(0x4000000000000000u64)), V(0xbff0000000000000u64), 4u64)) { panic("log #1079") }
    if !(near(V(0x3fe0000000000000u64).log(V(0x4024000000000000u64)), V(0xbfd34413509f79feu64), 4u64)) { panic("log #1080") }
}

fn group9() {
    if !(near(V(0x3fe0000000000000u64).log(V(0x400c000000000000u64)), V(0xbfe1b497341428b2u64), 4u64)) { panic("log #1081") }
    if !(near(V(0x3ff0000000000000u64).powf(V(0x3fe0000000000000u64)), V(0x3ff0000000000000u64), 2u64)) { panic("powf #1082") }
    if !(near(V(0x3ff0000000000000u64).powf(V(0x4000000000000000u64)), V(0x3ff0000000000000u64), 2u64)) { panic("powf #1083") }
    if !(near(V(0x3ff0000000000000u64).powf(V(0xbff8000000000000u64)), V(0x3ff0000000000000u64), 2u64)) { panic("powf #1084") }
    if !(near(V(0x3ff0000000000000u64).powf(V(0x4008000000000000u64)), V(0x3ff0000000000000u64), 2u64)) { panic("powf #1085") }
    if !(V(0x3ff0000000000000u64).log(V(0x4000000000000000u64)).to_bits() == 0x0u64) { panic("log #1086") }
    if !(V(0x3ff0000000000000u64).log(V(0x4024000000000000u64)).to_bits() == 0x0u64) { panic("log #1087") }
    if !(V(0x3ff0000000000000u64).log(V(0x400c000000000000u64)).to_bits() == 0x0u64) { panic("log #1088") }
    if !(near(V(0x3ff8000000000000u64).powf(V(0x3fe0000000000000u64)), V(0x3ff3988e1409212eu64), 2u64)) { panic("powf #1089") }
    if !(near(V(0x3ff8000000000000u64).powf(V(0x4000000000000000u64)), V(0x4002000000000000u64), 2u64)) { panic("powf #1090") }
    if !(near(V(0x3ff8000000000000u64).powf(V(0xbff8000000000000u64)), V(0x3fe16b28f55d72d4u64), 2u64)) { panic("powf #1091") }
    if !(near(V(0x3ff8000000000000u64).powf(V(0x4008000000000000u64)), V(0x400b000000000000u64), 2u64)) { panic("powf #1092") }
    if !(near(V(0x3ff8000000000000u64).log(V(0x4000000000000000u64)), V(0x3fe2b803473f7ad1u64), 4u64)) { panic("log #1093") }
    if !(near(V(0x3ff8000000000000u64).log(V(0x4024000000000000u64)), V(0x3fc68a288b60b7fcu64), 4u64)) { panic("log #1094") }
    if !(near(V(0x3ff8000000000000u64).log(V(0x400c000000000000u64)), V(0x3fd4b6ca86218d53u64), 4u64)) { panic("log #1095") }
    if !(near(V(0x4000000000000000u64).powf(V(0x3fe0000000000000u64)), V(0x3ff6a09e667f3bcdu64), 2u64)) { panic("powf #1096") }
    if !(near(V(0x4000000000000000u64).powf(V(0x4000000000000000u64)), V(0x4010000000000000u64), 2u64)) { panic("powf #1097") }
    if !(near(V(0x4000000000000000u64).powf(V(0xbff8000000000000u64)), V(0x3fd6a09e667f3bcdu64), 2u64)) { panic("powf #1098") }
    if !(near(V(0x4000000000000000u64).powf(V(0x4008000000000000u64)), V(0x4020000000000000u64), 2u64)) { panic("powf #1099") }
    if !(near(V(0x4000000000000000u64).log(V(0x4000000000000000u64)), V(0x3ff0000000000000u64), 4u64)) { panic("log #1100") }
    if !(near(V(0x4000000000000000u64).log(V(0x4024000000000000u64)), V(0x3fd34413509f79feu64), 4u64)) { panic("log #1101") }
    if !(near(V(0x4000000000000000u64).log(V(0x400c000000000000u64)), V(0x3fe1b497341428b2u64), 4u64)) { panic("log #1102") }
    if !(near(V(0x4024000000000000u64).powf(V(0x3fe0000000000000u64)), V(0x40094c583ada5b53u64), 2u64)) { panic("powf #1103") }
    if !(near(V(0x4024000000000000u64).powf(V(0x4000000000000000u64)), V(0x4059000000000000u64), 2u64)) { panic("powf #1104") }
    if !(near(V(0x4024000000000000u64).powf(V(0xbff8000000000000u64)), V(0x3fa030dc4ea03a72u64), 2u64)) { panic("powf #1105") }
    if !(near(V(0x4024000000000000u64).powf(V(0x4008000000000000u64)), V(0x408f400000000000u64), 2u64)) { panic("powf #1106") }
    if !(near(V(0x4024000000000000u64).log(V(0x4000000000000000u64)), V(0x400a934f0979a372u64), 4u64)) { panic("log #1107") }
    if !(near(V(0x4024000000000000u64).log(V(0x4024000000000000u64)), V(0x3ff0000000000000u64), 4u64)) { panic("log #1108") }
    if !(near(V(0x4024000000000000u64).log(V(0x400c000000000000u64)), V(0x3ffd687857f5fc1du64), 4u64)) { panic("log #1109") }
    if !(near(V(0x405edd2f1a9fbe77u64).powf(V(0x3fe0000000000000u64)), V(0x402638dee52c80edu64), 2u64)) { panic("powf #1110") }
    if !(near(V(0x405edd2f1a9fbe77u64).powf(V(0x4000000000000000u64)), V(0x40cdc4b124d099e1u64), 2u64)) { panic("powf #1111") }
    if !(near(V(0x405edd2f1a9fbe77u64).powf(V(0xbff8000000000000u64)), V(0x3f47e35a9bc426f5u64), 2u64)) { panic("powf #1112") }
    if !(near(V(0x405edd2f1a9fbe77u64).powf(V(0x4008000000000000u64)), V(0x413cb6284b926969u64), 2u64)) { panic("powf #1113") }
    if !(near(V(0x405edd2f1a9fbe77u64).log(V(0x4000000000000000u64)), V(0x401bca9a03b1083au64), 4u64)) { panic("log #1114") }
    if !(near(V(0x405edd2f1a9fbe77u64).log(V(0x4024000000000000u64)), V(0x4000bb6abfc968efu64), 4u64)) { panic("log #1115") }
    if !(near(V(0x405edd2f1a9fbe77u64).log(V(0x400c000000000000u64)), V(0x400ec0f18b189badu64), 4u64)) { panic("log #1116") }
    if !(near(V(0x3ee4f8b588e368f1u64).powf(V(0x3fe0000000000000u64)), V(0x3f69e7c6e43390b7u64), 2u64)) { panic("powf #1117") }
    if !(near(V(0x3ee4f8b588e368f1u64).powf(V(0x4000000000000000u64)), V(0x3ddb7cdfd9d7bdbcu64), 2u64)) { panic("powf #1118") }
    if !(near(V(0x3ee4f8b588e368f1u64).powf(V(0xbff8000000000000u64)), V(0x417e286789a07f2eu64), 2u64)) { panic("powf #1119") }
    if !(near(V(0x3ee4f8b588e368f1u64).powf(V(0x4008000000000000u64)), V(0x3cd203af9ee75617u64), 2u64)) { panic("powf #1120") }
    if !(near(V(0x3ee4f8b588e368f1u64).log(V(0x4000000000000000u64)), V(0xc0309c1165ec0627u64), 4u64)) { panic("log #1121") }
    if !(near(V(0x3ee4f8b588e368f1u64).log(V(0x4024000000000000u64)), V(0xc014000000000000u64), 4u64)) { panic("log #1122") }
    if !(near(V(0x3ee4f8b588e368f1u64).log(V(0x400c000000000000u64)), V(0xc022614b36f9bd92u64), 4u64)) { panic("log #1123") }
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
    0
}
