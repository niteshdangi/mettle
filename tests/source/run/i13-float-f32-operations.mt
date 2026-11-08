// profiles: debug release
// Every stable f32 operation family; inputs and exact results are bit
// patterns. Correctly rounded operations match bit-for-bit; libm-backed
// functions are within a few ULP of a double-precision reference.
import core.cmp.{Ordering, PartialEq}
import core.float.FpCategory
import core.panic.panic

fn V(bits: u32): f32 { f32.from_bits(bits) }

fn ordered(value: f32): i32 {
    let raw = value.to_bits() as i32
    if raw < 0i32 { i32.MIN - raw } else { raw }
}

fn near(actual: f32, expected: f32, ulps: u32): bool {
    if actual.is_nan() || expected.is_nan() { return actual.is_nan() && expected.is_nan() }
    ordered(actual).abs_diff(ordered(expected)) <= ulps
}

fn group0() {
    if !(f32.MAX.to_bits() == 0x7f7fffffu32) { panic("MAX #1") }
    if !(f32.MIN.to_bits() == 0xff7fffffu32) { panic("MIN #2") }
    if !(f32.MIN_POSITIVE.to_bits() == 0x800000u32) { panic("MIN_POSITIVE #3") }
    if !(f32.EPSILON.to_bits() == 0x34000000u32) { panic("EPSILON #4") }
    if !(f32.INFINITY.to_bits() == 0x7f800000u32) { panic("INFINITY #5") }
    if !(f32.NEG_INFINITY.to_bits() == 0xff800000u32) { panic("NEG_INFINITY #6") }
    if !(f32.NAN.is_nan()) { panic("NAN #7") }
    if !(f32.DIGITS == 6u32) { panic("DIGITS #8") }
    if !(f32.MANTISSA_DIGITS == 24u32) { panic("MANTISSA_DIGITS #9") }
    if !(f32.RADIX == 2u32) { panic("RADIX #10") }
    if !(f32.MIN_EXP == (-125i32)) { panic("MIN_EXP #11") }
    if !(f32.MAX_EXP == 128i32) { panic("MAX_EXP #12") }
    if !(f32.MIN_10_EXP == (-37i32)) { panic("MIN_10_EXP #13") }
    if !(f32.MAX_10_EXP == 38i32) { panic("MAX_10_EXP #14") }
    if !(V(0x0u32).is_nan() == false) { panic("is_nan #15") }
    if !(V(0x0u32).is_infinite() == false) { panic("is_infinite #16") }
    if !(V(0x0u32).is_finite() == true) { panic("is_finite #17") }
    if !(V(0x0u32).is_normal() == false) { panic("is_normal #18") }
    if !(V(0x0u32).is_subnormal() == false) { panic("is_subnormal #19") }
    if !(V(0x0u32).is_sign_negative() == false) { panic("is_sign_negative #20") }
    if !(V(0x0u32).is_sign_positive() == true) { panic("is_sign_positive #21") }
    if !(V(0x0u32).classify() == FpCategory.Zero) { panic("classify #22") }
    if !(V(0x0u32).abs().to_bits() == 0x0u32) { panic("abs #23") }
    if !(V(0x0u32).floor().to_bits() == 0x0u32) { panic("floor #24") }
    if !(V(0x0u32).ceil().to_bits() == 0x0u32) { panic("ceil #25") }
    if !(V(0x0u32).trunc().to_bits() == 0x0u32) { panic("trunc #26") }
    if !(V(0x0u32).round().to_bits() == 0x0u32) { panic("round #27") }
    if !(V(0x0u32).round_ties_even().to_bits() == 0x0u32) { panic("round_ties_even #28") }
    if !(V(0x0u32).fract().to_bits() == 0x0u32) { panic("fract #29") }
    if !(V(0x0u32).signum().to_bits() == 0x3f800000u32) { panic("signum #30") }
    if !(V(0x0u32).recip().to_bits() == 0x7f800000u32) { panic("recip #31") }
    if !(V(0x0u32).sqrt().to_bits() == 0x0u32) { panic("sqrt #32") }
    if !(V(0x0u32).to_bits() == 0x0u32) { panic("to_bits #33") }
    if !(V(0x0u32).to_bits() == 0x0u32) { panic("to_bits #34") }
    if !(f32.from_bits(0x0u32).to_bits() == 0x0u32) { panic("from_bits #35") }
    if !(V(0x0u32).to_le_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #36") }
    if !(V(0x0u32).to_be_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #37") }
    if !(V(0x0u32).to_ne_bytes() == [0u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #38") }
    if !(f32.from_le_bytes([0u8, 0u8, 0u8, 0u8]).to_bits() == 0x0u32) { panic("from_le_bytes #39") }
    if !(f32.from_be_bytes([0u8, 0u8, 0u8, 0u8]).to_bits() == 0x0u32) { panic("from_be_bytes #40") }
    if !(f32.from_ne_bytes([0u8, 0u8, 0u8, 0u8]).to_bits() == 0x0u32) { panic("from_ne_bytes #41") }
    if !(V(0x0u32).next_up().to_bits() == 0x1u32) { panic("next_up #42") }
    if !(V(0x0u32).next_down().to_bits() == 0x80000001u32) { panic("next_down #43") }
    if !(unsafe { V(0x0u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #44") }
    if !(V(0x0u32).total_cmp(V(0x0u32)) == Ordering.Equal) { panic("total_cmp #45") }
    if !(V(0x0u32).to_degrees().to_bits() == 0x0u32) { panic("to_degrees #46") }
    if !(V(0x80000000u32).is_nan() == false) { panic("is_nan #47") }
    if !(V(0x80000000u32).is_infinite() == false) { panic("is_infinite #48") }
    if !(V(0x80000000u32).is_finite() == true) { panic("is_finite #49") }
    if !(V(0x80000000u32).is_normal() == false) { panic("is_normal #50") }
    if !(V(0x80000000u32).is_subnormal() == false) { panic("is_subnormal #51") }
    if !(V(0x80000000u32).is_sign_negative() == true) { panic("is_sign_negative #52") }
    if !(V(0x80000000u32).is_sign_positive() == false) { panic("is_sign_positive #53") }
    if !(V(0x80000000u32).classify() == FpCategory.Zero) { panic("classify #54") }
    if !(V(0x80000000u32).abs().to_bits() == 0x0u32) { panic("abs #55") }
    if !(V(0x80000000u32).floor().to_bits() == 0x80000000u32) { panic("floor #56") }
    if !(V(0x80000000u32).ceil().to_bits() == 0x80000000u32) { panic("ceil #57") }
    if !(V(0x80000000u32).trunc().to_bits() == 0x80000000u32) { panic("trunc #58") }
    if !(V(0x80000000u32).round().to_bits() == 0x80000000u32) { panic("round #59") }
    if !(V(0x80000000u32).round_ties_even().to_bits() == 0x80000000u32) { panic("round_ties_even #60") }
    if !(V(0x80000000u32).fract().to_bits() == 0x0u32) { panic("fract #61") }
    if !(V(0x80000000u32).signum().to_bits() == 0xbf800000u32) { panic("signum #62") }
    if !(V(0x80000000u32).recip().to_bits() == 0xff800000u32) { panic("recip #63") }
    if !(V(0x80000000u32).sqrt().to_bits() == 0x80000000u32) { panic("sqrt #64") }
    if !(V(0x80000000u32).to_bits() == 0x80000000u32) { panic("to_bits #65") }
    if !(V(0x80000000u32).to_bits() == 0x80000000u32) { panic("to_bits #66") }
    if !(f32.from_bits(0x80000000u32).to_bits() == 0x80000000u32) { panic("from_bits #67") }
    if !(V(0x80000000u32).to_le_bytes() == [0u8, 0u8, 0u8, 128u8]) { panic("to_le_bytes #68") }
    if !(V(0x80000000u32).to_be_bytes() == [128u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #69") }
    if !(V(0x80000000u32).to_ne_bytes() == [0u8, 0u8, 0u8, 128u8]) { panic("to_ne_bytes #70") }
    if !(f32.from_le_bytes([0u8, 0u8, 0u8, 128u8]).to_bits() == 0x80000000u32) { panic("from_le_bytes #71") }
    if !(f32.from_be_bytes([128u8, 0u8, 0u8, 0u8]).to_bits() == 0x80000000u32) { panic("from_be_bytes #72") }
    if !(f32.from_ne_bytes([0u8, 0u8, 0u8, 128u8]).to_bits() == 0x80000000u32) { panic("from_ne_bytes #73") }
    if !(V(0x80000000u32).next_up().to_bits() == 0x1u32) { panic("next_up #74") }
    if !(V(0x80000000u32).next_down().to_bits() == 0x80000001u32) { panic("next_down #75") }
    if !(unsafe { V(0x80000000u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #76") }
    if !(V(0x80000000u32).total_cmp(V(0x80000000u32)) == Ordering.Equal) { panic("total_cmp #77") }
    if !(V(0x80000000u32).to_degrees().to_bits() == 0x80000000u32) { panic("to_degrees #78") }
    if !(V(0x3f800000u32).is_nan() == false) { panic("is_nan #79") }
    if !(V(0x3f800000u32).is_infinite() == false) { panic("is_infinite #80") }
    if !(V(0x3f800000u32).is_finite() == true) { panic("is_finite #81") }
    if !(V(0x3f800000u32).is_normal() == true) { panic("is_normal #82") }
    if !(V(0x3f800000u32).is_subnormal() == false) { panic("is_subnormal #83") }
    if !(V(0x3f800000u32).is_sign_negative() == false) { panic("is_sign_negative #84") }
    if !(V(0x3f800000u32).is_sign_positive() == true) { panic("is_sign_positive #85") }
    if !(V(0x3f800000u32).classify() == FpCategory.Normal) { panic("classify #86") }
    if !(V(0x3f800000u32).abs().to_bits() == 0x3f800000u32) { panic("abs #87") }
    if !(V(0x3f800000u32).floor().to_bits() == 0x3f800000u32) { panic("floor #88") }
    if !(V(0x3f800000u32).ceil().to_bits() == 0x3f800000u32) { panic("ceil #89") }
    if !(V(0x3f800000u32).trunc().to_bits() == 0x3f800000u32) { panic("trunc #90") }
    if !(V(0x3f800000u32).round().to_bits() == 0x3f800000u32) { panic("round #91") }
    if !(V(0x3f800000u32).round_ties_even().to_bits() == 0x3f800000u32) { panic("round_ties_even #92") }
    if !(V(0x3f800000u32).fract().to_bits() == 0x0u32) { panic("fract #93") }
    if !(V(0x3f800000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #94") }
    if !(V(0x3f800000u32).recip().to_bits() == 0x3f800000u32) { panic("recip #95") }
    if !(V(0x3f800000u32).sqrt().to_bits() == 0x3f800000u32) { panic("sqrt #96") }
    if !(V(0x3f800000u32).to_bits() == 0x3f800000u32) { panic("to_bits #97") }
    if !(V(0x3f800000u32).to_bits() == 0x3f800000u32) { panic("to_bits #98") }
    if !(f32.from_bits(0x3f800000u32).to_bits() == 0x3f800000u32) { panic("from_bits #99") }
    if !(V(0x3f800000u32).to_le_bytes() == [0u8, 0u8, 128u8, 63u8]) { panic("to_le_bytes #100") }
    if !(V(0x3f800000u32).to_be_bytes() == [63u8, 128u8, 0u8, 0u8]) { panic("to_be_bytes #101") }
    if !(V(0x3f800000u32).to_ne_bytes() == [0u8, 0u8, 128u8, 63u8]) { panic("to_ne_bytes #102") }
    if !(f32.from_le_bytes([0u8, 0u8, 128u8, 63u8]).to_bits() == 0x3f800000u32) { panic("from_le_bytes #103") }
    if !(f32.from_be_bytes([63u8, 128u8, 0u8, 0u8]).to_bits() == 0x3f800000u32) { panic("from_be_bytes #104") }
    if !(f32.from_ne_bytes([0u8, 0u8, 128u8, 63u8]).to_bits() == 0x3f800000u32) { panic("from_ne_bytes #105") }
    if !(V(0x3f800000u32).next_up().to_bits() == 0x3f800001u32) { panic("next_up #106") }
    if !(V(0x3f800000u32).next_down().to_bits() == 0x3f7fffffu32) { panic("next_down #107") }
    if !(unsafe { V(0x3f800000u32).to_int_unchecked<i32>() } == 1i32) { panic("to_int_unchecked #108") }
    if !(V(0x3f800000u32).total_cmp(V(0x3f800000u32)) == Ordering.Equal) { panic("total_cmp #109") }
    if !(V(0xbf800000u32).is_nan() == false) { panic("is_nan #110") }
    if !(V(0xbf800000u32).is_infinite() == false) { panic("is_infinite #111") }
    if !(V(0xbf800000u32).is_finite() == true) { panic("is_finite #112") }
    if !(V(0xbf800000u32).is_normal() == true) { panic("is_normal #113") }
    if !(V(0xbf800000u32).is_subnormal() == false) { panic("is_subnormal #114") }
    if !(V(0xbf800000u32).is_sign_negative() == true) { panic("is_sign_negative #115") }
    if !(V(0xbf800000u32).is_sign_positive() == false) { panic("is_sign_positive #116") }
    if !(V(0xbf800000u32).classify() == FpCategory.Normal) { panic("classify #117") }
    if !(V(0xbf800000u32).abs().to_bits() == 0x3f800000u32) { panic("abs #118") }
    if !(V(0xbf800000u32).floor().to_bits() == 0xbf800000u32) { panic("floor #119") }
    if !(V(0xbf800000u32).ceil().to_bits() == 0xbf800000u32) { panic("ceil #120") }
}

fn group1() {
    if !(V(0xbf800000u32).trunc().to_bits() == 0xbf800000u32) { panic("trunc #121") }
    if !(V(0xbf800000u32).round().to_bits() == 0xbf800000u32) { panic("round #122") }
    if !(V(0xbf800000u32).round_ties_even().to_bits() == 0xbf800000u32) { panic("round_ties_even #123") }
    if !(V(0xbf800000u32).fract().to_bits() == 0x0u32) { panic("fract #124") }
    if !(V(0xbf800000u32).signum().to_bits() == 0xbf800000u32) { panic("signum #125") }
    if !(V(0xbf800000u32).recip().to_bits() == 0xbf800000u32) { panic("recip #126") }
    if !(V(0xbf800000u32).sqrt().is_nan()) { panic("sqrt #127") }
    if !(V(0xbf800000u32).to_bits() == 0xbf800000u32) { panic("to_bits #128") }
    if !(V(0xbf800000u32).to_bits() == 0xbf800000u32) { panic("to_bits #129") }
    if !(f32.from_bits(0xbf800000u32).to_bits() == 0xbf800000u32) { panic("from_bits #130") }
    if !(V(0xbf800000u32).to_le_bytes() == [0u8, 0u8, 128u8, 191u8]) { panic("to_le_bytes #131") }
    if !(V(0xbf800000u32).to_be_bytes() == [191u8, 128u8, 0u8, 0u8]) { panic("to_be_bytes #132") }
    if !(V(0xbf800000u32).to_ne_bytes() == [0u8, 0u8, 128u8, 191u8]) { panic("to_ne_bytes #133") }
    if !(f32.from_le_bytes([0u8, 0u8, 128u8, 191u8]).to_bits() == 0xbf800000u32) { panic("from_le_bytes #134") }
    if !(f32.from_be_bytes([191u8, 128u8, 0u8, 0u8]).to_bits() == 0xbf800000u32) { panic("from_be_bytes #135") }
    if !(f32.from_ne_bytes([0u8, 0u8, 128u8, 191u8]).to_bits() == 0xbf800000u32) { panic("from_ne_bytes #136") }
    if !(V(0xbf800000u32).next_up().to_bits() == 0xbf7fffffu32) { panic("next_up #137") }
    if !(V(0xbf800000u32).next_down().to_bits() == 0xbf800001u32) { panic("next_down #138") }
    if !(unsafe { V(0xbf800000u32).to_int_unchecked<i32>() } == (-1i32)) { panic("to_int_unchecked #139") }
    if !(V(0xbf800000u32).total_cmp(V(0xbf800000u32)) == Ordering.Equal) { panic("total_cmp #140") }
    if !(V(0x3f000000u32).is_nan() == false) { panic("is_nan #141") }
    if !(V(0x3f000000u32).is_infinite() == false) { panic("is_infinite #142") }
    if !(V(0x3f000000u32).is_finite() == true) { panic("is_finite #143") }
    if !(V(0x3f000000u32).is_normal() == true) { panic("is_normal #144") }
    if !(V(0x3f000000u32).is_subnormal() == false) { panic("is_subnormal #145") }
    if !(V(0x3f000000u32).is_sign_negative() == false) { panic("is_sign_negative #146") }
    if !(V(0x3f000000u32).is_sign_positive() == true) { panic("is_sign_positive #147") }
    if !(V(0x3f000000u32).classify() == FpCategory.Normal) { panic("classify #148") }
    if !(V(0x3f000000u32).abs().to_bits() == 0x3f000000u32) { panic("abs #149") }
    if !(V(0x3f000000u32).floor().to_bits() == 0x0u32) { panic("floor #150") }
    if !(V(0x3f000000u32).ceil().to_bits() == 0x3f800000u32) { panic("ceil #151") }
    if !(V(0x3f000000u32).trunc().to_bits() == 0x0u32) { panic("trunc #152") }
    if !(V(0x3f000000u32).round().to_bits() == 0x3f800000u32) { panic("round #153") }
    if !(V(0x3f000000u32).round_ties_even().to_bits() == 0x0u32) { panic("round_ties_even #154") }
    if !(V(0x3f000000u32).fract().to_bits() == 0x3f000000u32) { panic("fract #155") }
    if !(V(0x3f000000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #156") }
    if !(V(0x3f000000u32).recip().to_bits() == 0x40000000u32) { panic("recip #157") }
    if !(V(0x3f000000u32).sqrt().to_bits() == 0x3f3504f3u32) { panic("sqrt #158") }
    if !(V(0x3f000000u32).to_bits() == 0x3f000000u32) { panic("to_bits #159") }
    if !(V(0x3f000000u32).to_bits() == 0x3f000000u32) { panic("to_bits #160") }
    if !(f32.from_bits(0x3f000000u32).to_bits() == 0x3f000000u32) { panic("from_bits #161") }
    if !(V(0x3f000000u32).to_le_bytes() == [0u8, 0u8, 0u8, 63u8]) { panic("to_le_bytes #162") }
    if !(V(0x3f000000u32).to_be_bytes() == [63u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #163") }
    if !(V(0x3f000000u32).to_ne_bytes() == [0u8, 0u8, 0u8, 63u8]) { panic("to_ne_bytes #164") }
    if !(f32.from_le_bytes([0u8, 0u8, 0u8, 63u8]).to_bits() == 0x3f000000u32) { panic("from_le_bytes #165") }
    if !(f32.from_be_bytes([63u8, 0u8, 0u8, 0u8]).to_bits() == 0x3f000000u32) { panic("from_be_bytes #166") }
    if !(f32.from_ne_bytes([0u8, 0u8, 0u8, 63u8]).to_bits() == 0x3f000000u32) { panic("from_ne_bytes #167") }
    if !(V(0x3f000000u32).next_up().to_bits() == 0x3f000001u32) { panic("next_up #168") }
    if !(V(0x3f000000u32).next_down().to_bits() == 0x3effffffu32) { panic("next_down #169") }
    if !(unsafe { V(0x3f000000u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #170") }
    if !(V(0x3f000000u32).total_cmp(V(0x3f000000u32)) == Ordering.Equal) { panic("total_cmp #171") }
    if !(V(0xbf000000u32).is_nan() == false) { panic("is_nan #172") }
    if !(V(0xbf000000u32).is_infinite() == false) { panic("is_infinite #173") }
    if !(V(0xbf000000u32).is_finite() == true) { panic("is_finite #174") }
    if !(V(0xbf000000u32).is_normal() == true) { panic("is_normal #175") }
    if !(V(0xbf000000u32).is_subnormal() == false) { panic("is_subnormal #176") }
    if !(V(0xbf000000u32).is_sign_negative() == true) { panic("is_sign_negative #177") }
    if !(V(0xbf000000u32).is_sign_positive() == false) { panic("is_sign_positive #178") }
    if !(V(0xbf000000u32).classify() == FpCategory.Normal) { panic("classify #179") }
    if !(V(0xbf000000u32).abs().to_bits() == 0x3f000000u32) { panic("abs #180") }
    if !(V(0xbf000000u32).floor().to_bits() == 0xbf800000u32) { panic("floor #181") }
    if !(V(0xbf000000u32).ceil().to_bits() == 0x80000000u32) { panic("ceil #182") }
    if !(V(0xbf000000u32).trunc().to_bits() == 0x80000000u32) { panic("trunc #183") }
    if !(V(0xbf000000u32).round().to_bits() == 0xbf800000u32) { panic("round #184") }
    if !(V(0xbf000000u32).round_ties_even().to_bits() == 0x80000000u32) { panic("round_ties_even #185") }
    if !(V(0xbf000000u32).fract().to_bits() == 0xbf000000u32) { panic("fract #186") }
    if !(V(0xbf000000u32).signum().to_bits() == 0xbf800000u32) { panic("signum #187") }
    if !(V(0xbf000000u32).recip().to_bits() == 0xc0000000u32) { panic("recip #188") }
    if !(V(0xbf000000u32).sqrt().is_nan()) { panic("sqrt #189") }
    if !(V(0xbf000000u32).to_bits() == 0xbf000000u32) { panic("to_bits #190") }
    if !(V(0xbf000000u32).to_bits() == 0xbf000000u32) { panic("to_bits #191") }
    if !(f32.from_bits(0xbf000000u32).to_bits() == 0xbf000000u32) { panic("from_bits #192") }
    if !(V(0xbf000000u32).to_le_bytes() == [0u8, 0u8, 0u8, 191u8]) { panic("to_le_bytes #193") }
    if !(V(0xbf000000u32).to_be_bytes() == [191u8, 0u8, 0u8, 0u8]) { panic("to_be_bytes #194") }
    if !(V(0xbf000000u32).to_ne_bytes() == [0u8, 0u8, 0u8, 191u8]) { panic("to_ne_bytes #195") }
    if !(f32.from_le_bytes([0u8, 0u8, 0u8, 191u8]).to_bits() == 0xbf000000u32) { panic("from_le_bytes #196") }
    if !(f32.from_be_bytes([191u8, 0u8, 0u8, 0u8]).to_bits() == 0xbf000000u32) { panic("from_be_bytes #197") }
    if !(f32.from_ne_bytes([0u8, 0u8, 0u8, 191u8]).to_bits() == 0xbf000000u32) { panic("from_ne_bytes #198") }
    if !(V(0xbf000000u32).next_up().to_bits() == 0xbeffffffu32) { panic("next_up #199") }
    if !(V(0xbf000000u32).next_down().to_bits() == 0xbf000001u32) { panic("next_down #200") }
    if !(unsafe { V(0xbf000000u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #201") }
    if !(V(0xbf000000u32).total_cmp(V(0xbf000000u32)) == Ordering.Equal) { panic("total_cmp #202") }
    if !(V(0x3fc00000u32).is_nan() == false) { panic("is_nan #203") }
    if !(V(0x3fc00000u32).is_infinite() == false) { panic("is_infinite #204") }
    if !(V(0x3fc00000u32).is_finite() == true) { panic("is_finite #205") }
    if !(V(0x3fc00000u32).is_normal() == true) { panic("is_normal #206") }
    if !(V(0x3fc00000u32).is_subnormal() == false) { panic("is_subnormal #207") }
    if !(V(0x3fc00000u32).is_sign_negative() == false) { panic("is_sign_negative #208") }
    if !(V(0x3fc00000u32).is_sign_positive() == true) { panic("is_sign_positive #209") }
    if !(V(0x3fc00000u32).classify() == FpCategory.Normal) { panic("classify #210") }
    if !(V(0x3fc00000u32).abs().to_bits() == 0x3fc00000u32) { panic("abs #211") }
    if !(V(0x3fc00000u32).floor().to_bits() == 0x3f800000u32) { panic("floor #212") }
    if !(V(0x3fc00000u32).ceil().to_bits() == 0x40000000u32) { panic("ceil #213") }
    if !(V(0x3fc00000u32).trunc().to_bits() == 0x3f800000u32) { panic("trunc #214") }
    if !(V(0x3fc00000u32).round().to_bits() == 0x40000000u32) { panic("round #215") }
    if !(V(0x3fc00000u32).round_ties_even().to_bits() == 0x40000000u32) { panic("round_ties_even #216") }
    if !(V(0x3fc00000u32).fract().to_bits() == 0x3f000000u32) { panic("fract #217") }
    if !(V(0x3fc00000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #218") }
    if !(V(0x3fc00000u32).recip().to_bits() == 0x3f2aaaabu32) { panic("recip #219") }
    if !(V(0x3fc00000u32).sqrt().to_bits() == 0x3f9cc471u32) { panic("sqrt #220") }
    if !(V(0x3fc00000u32).to_bits() == 0x3fc00000u32) { panic("to_bits #221") }
    if !(V(0x3fc00000u32).to_bits() == 0x3fc00000u32) { panic("to_bits #222") }
    if !(f32.from_bits(0x3fc00000u32).to_bits() == 0x3fc00000u32) { panic("from_bits #223") }
    if !(V(0x3fc00000u32).to_le_bytes() == [0u8, 0u8, 192u8, 63u8]) { panic("to_le_bytes #224") }
    if !(V(0x3fc00000u32).to_be_bytes() == [63u8, 192u8, 0u8, 0u8]) { panic("to_be_bytes #225") }
    if !(V(0x3fc00000u32).to_ne_bytes() == [0u8, 0u8, 192u8, 63u8]) { panic("to_ne_bytes #226") }
    if !(f32.from_le_bytes([0u8, 0u8, 192u8, 63u8]).to_bits() == 0x3fc00000u32) { panic("from_le_bytes #227") }
    if !(f32.from_be_bytes([63u8, 192u8, 0u8, 0u8]).to_bits() == 0x3fc00000u32) { panic("from_be_bytes #228") }
    if !(f32.from_ne_bytes([0u8, 0u8, 192u8, 63u8]).to_bits() == 0x3fc00000u32) { panic("from_ne_bytes #229") }
    if !(V(0x3fc00000u32).next_up().to_bits() == 0x3fc00001u32) { panic("next_up #230") }
    if !(V(0x3fc00000u32).next_down().to_bits() == 0x3fbfffffu32) { panic("next_down #231") }
    if !(unsafe { V(0x3fc00000u32).to_int_unchecked<i32>() } == 1i32) { panic("to_int_unchecked #232") }
    if !(V(0x3fc00000u32).total_cmp(V(0x3fc00000u32)) == Ordering.Equal) { panic("total_cmp #233") }
    if !(V(0x40200000u32).is_nan() == false) { panic("is_nan #234") }
    if !(V(0x40200000u32).is_infinite() == false) { panic("is_infinite #235") }
    if !(V(0x40200000u32).is_finite() == true) { panic("is_finite #236") }
    if !(V(0x40200000u32).is_normal() == true) { panic("is_normal #237") }
    if !(V(0x40200000u32).is_subnormal() == false) { panic("is_subnormal #238") }
    if !(V(0x40200000u32).is_sign_negative() == false) { panic("is_sign_negative #239") }
    if !(V(0x40200000u32).is_sign_positive() == true) { panic("is_sign_positive #240") }
}

fn group2() {
    if !(V(0x40200000u32).classify() == FpCategory.Normal) { panic("classify #241") }
    if !(V(0x40200000u32).abs().to_bits() == 0x40200000u32) { panic("abs #242") }
    if !(V(0x40200000u32).floor().to_bits() == 0x40000000u32) { panic("floor #243") }
    if !(V(0x40200000u32).ceil().to_bits() == 0x40400000u32) { panic("ceil #244") }
    if !(V(0x40200000u32).trunc().to_bits() == 0x40000000u32) { panic("trunc #245") }
    if !(V(0x40200000u32).round().to_bits() == 0x40400000u32) { panic("round #246") }
    if !(V(0x40200000u32).round_ties_even().to_bits() == 0x40000000u32) { panic("round_ties_even #247") }
    if !(V(0x40200000u32).fract().to_bits() == 0x3f000000u32) { panic("fract #248") }
    if !(V(0x40200000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #249") }
    if !(V(0x40200000u32).recip().to_bits() == 0x3ecccccdu32) { panic("recip #250") }
    if !(V(0x40200000u32).sqrt().to_bits() == 0x3fca62c2u32) { panic("sqrt #251") }
    if !(V(0x40200000u32).to_bits() == 0x40200000u32) { panic("to_bits #252") }
    if !(V(0x40200000u32).to_bits() == 0x40200000u32) { panic("to_bits #253") }
    if !(f32.from_bits(0x40200000u32).to_bits() == 0x40200000u32) { panic("from_bits #254") }
    if !(V(0x40200000u32).to_le_bytes() == [0u8, 0u8, 32u8, 64u8]) { panic("to_le_bytes #255") }
    if !(V(0x40200000u32).to_be_bytes() == [64u8, 32u8, 0u8, 0u8]) { panic("to_be_bytes #256") }
    if !(V(0x40200000u32).to_ne_bytes() == [0u8, 0u8, 32u8, 64u8]) { panic("to_ne_bytes #257") }
    if !(f32.from_le_bytes([0u8, 0u8, 32u8, 64u8]).to_bits() == 0x40200000u32) { panic("from_le_bytes #258") }
    if !(f32.from_be_bytes([64u8, 32u8, 0u8, 0u8]).to_bits() == 0x40200000u32) { panic("from_be_bytes #259") }
    if !(f32.from_ne_bytes([0u8, 0u8, 32u8, 64u8]).to_bits() == 0x40200000u32) { panic("from_ne_bytes #260") }
    if !(V(0x40200000u32).next_up().to_bits() == 0x40200001u32) { panic("next_up #261") }
    if !(V(0x40200000u32).next_down().to_bits() == 0x401fffffu32) { panic("next_down #262") }
    if !(unsafe { V(0x40200000u32).to_int_unchecked<i32>() } == 2i32) { panic("to_int_unchecked #263") }
    if !(V(0x40200000u32).total_cmp(V(0x40200000u32)) == Ordering.Equal) { panic("total_cmp #264") }
    if !(V(0xc0200000u32).is_nan() == false) { panic("is_nan #265") }
    if !(V(0xc0200000u32).is_infinite() == false) { panic("is_infinite #266") }
    if !(V(0xc0200000u32).is_finite() == true) { panic("is_finite #267") }
    if !(V(0xc0200000u32).is_normal() == true) { panic("is_normal #268") }
    if !(V(0xc0200000u32).is_subnormal() == false) { panic("is_subnormal #269") }
    if !(V(0xc0200000u32).is_sign_negative() == true) { panic("is_sign_negative #270") }
    if !(V(0xc0200000u32).is_sign_positive() == false) { panic("is_sign_positive #271") }
    if !(V(0xc0200000u32).classify() == FpCategory.Normal) { panic("classify #272") }
    if !(V(0xc0200000u32).abs().to_bits() == 0x40200000u32) { panic("abs #273") }
    if !(V(0xc0200000u32).floor().to_bits() == 0xc0400000u32) { panic("floor #274") }
    if !(V(0xc0200000u32).ceil().to_bits() == 0xc0000000u32) { panic("ceil #275") }
    if !(V(0xc0200000u32).trunc().to_bits() == 0xc0000000u32) { panic("trunc #276") }
    if !(V(0xc0200000u32).round().to_bits() == 0xc0400000u32) { panic("round #277") }
    if !(V(0xc0200000u32).round_ties_even().to_bits() == 0xc0000000u32) { panic("round_ties_even #278") }
    if !(V(0xc0200000u32).fract().to_bits() == 0xbf000000u32) { panic("fract #279") }
    if !(V(0xc0200000u32).signum().to_bits() == 0xbf800000u32) { panic("signum #280") }
    if !(V(0xc0200000u32).recip().to_bits() == 0xbecccccdu32) { panic("recip #281") }
    if !(V(0xc0200000u32).sqrt().is_nan()) { panic("sqrt #282") }
    if !(V(0xc0200000u32).to_bits() == 0xc0200000u32) { panic("to_bits #283") }
    if !(V(0xc0200000u32).to_bits() == 0xc0200000u32) { panic("to_bits #284") }
    if !(f32.from_bits(0xc0200000u32).to_bits() == 0xc0200000u32) { panic("from_bits #285") }
    if !(V(0xc0200000u32).to_le_bytes() == [0u8, 0u8, 32u8, 192u8]) { panic("to_le_bytes #286") }
    if !(V(0xc0200000u32).to_be_bytes() == [192u8, 32u8, 0u8, 0u8]) { panic("to_be_bytes #287") }
    if !(V(0xc0200000u32).to_ne_bytes() == [0u8, 0u8, 32u8, 192u8]) { panic("to_ne_bytes #288") }
    if !(f32.from_le_bytes([0u8, 0u8, 32u8, 192u8]).to_bits() == 0xc0200000u32) { panic("from_le_bytes #289") }
    if !(f32.from_be_bytes([192u8, 32u8, 0u8, 0u8]).to_bits() == 0xc0200000u32) { panic("from_be_bytes #290") }
    if !(f32.from_ne_bytes([0u8, 0u8, 32u8, 192u8]).to_bits() == 0xc0200000u32) { panic("from_ne_bytes #291") }
    if !(V(0xc0200000u32).next_up().to_bits() == 0xc01fffffu32) { panic("next_up #292") }
    if !(V(0xc0200000u32).next_down().to_bits() == 0xc0200001u32) { panic("next_down #293") }
    if !(unsafe { V(0xc0200000u32).to_int_unchecked<i32>() } == (-2i32)) { panic("to_int_unchecked #294") }
    if !(V(0xc0200000u32).total_cmp(V(0xc0200000u32)) == Ordering.Equal) { panic("total_cmp #295") }
    if !(V(0x40700000u32).is_nan() == false) { panic("is_nan #296") }
    if !(V(0x40700000u32).is_infinite() == false) { panic("is_infinite #297") }
    if !(V(0x40700000u32).is_finite() == true) { panic("is_finite #298") }
    if !(V(0x40700000u32).is_normal() == true) { panic("is_normal #299") }
    if !(V(0x40700000u32).is_subnormal() == false) { panic("is_subnormal #300") }
    if !(V(0x40700000u32).is_sign_negative() == false) { panic("is_sign_negative #301") }
    if !(V(0x40700000u32).is_sign_positive() == true) { panic("is_sign_positive #302") }
    if !(V(0x40700000u32).classify() == FpCategory.Normal) { panic("classify #303") }
    if !(V(0x40700000u32).abs().to_bits() == 0x40700000u32) { panic("abs #304") }
    if !(V(0x40700000u32).floor().to_bits() == 0x40400000u32) { panic("floor #305") }
    if !(V(0x40700000u32).ceil().to_bits() == 0x40800000u32) { panic("ceil #306") }
    if !(V(0x40700000u32).trunc().to_bits() == 0x40400000u32) { panic("trunc #307") }
    if !(V(0x40700000u32).round().to_bits() == 0x40800000u32) { panic("round #308") }
    if !(V(0x40700000u32).round_ties_even().to_bits() == 0x40800000u32) { panic("round_ties_even #309") }
    if !(V(0x40700000u32).fract().to_bits() == 0x3f400000u32) { panic("fract #310") }
    if !(V(0x40700000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #311") }
    if !(V(0x40700000u32).recip().to_bits() == 0x3e888889u32) { panic("recip #312") }
    if !(V(0x40700000u32).sqrt().to_bits() == 0x3ff7def6u32) { panic("sqrt #313") }
    if !(V(0x40700000u32).to_bits() == 0x40700000u32) { panic("to_bits #314") }
    if !(V(0x40700000u32).to_bits() == 0x40700000u32) { panic("to_bits #315") }
    if !(f32.from_bits(0x40700000u32).to_bits() == 0x40700000u32) { panic("from_bits #316") }
    if !(V(0x40700000u32).to_le_bytes() == [0u8, 0u8, 112u8, 64u8]) { panic("to_le_bytes #317") }
    if !(V(0x40700000u32).to_be_bytes() == [64u8, 112u8, 0u8, 0u8]) { panic("to_be_bytes #318") }
    if !(V(0x40700000u32).to_ne_bytes() == [0u8, 0u8, 112u8, 64u8]) { panic("to_ne_bytes #319") }
    if !(f32.from_le_bytes([0u8, 0u8, 112u8, 64u8]).to_bits() == 0x40700000u32) { panic("from_le_bytes #320") }
    if !(f32.from_be_bytes([64u8, 112u8, 0u8, 0u8]).to_bits() == 0x40700000u32) { panic("from_be_bytes #321") }
    if !(f32.from_ne_bytes([0u8, 0u8, 112u8, 64u8]).to_bits() == 0x40700000u32) { panic("from_ne_bytes #322") }
    if !(V(0x40700000u32).next_up().to_bits() == 0x40700001u32) { panic("next_up #323") }
    if !(V(0x40700000u32).next_down().to_bits() == 0x406fffffu32) { panic("next_down #324") }
    if !(unsafe { V(0x40700000u32).to_int_unchecked<i32>() } == 3i32) { panic("to_int_unchecked #325") }
    if !(V(0x40700000u32).total_cmp(V(0x40700000u32)) == Ordering.Equal) { panic("total_cmp #326") }
    if !(V(0xc0700000u32).is_nan() == false) { panic("is_nan #327") }
    if !(V(0xc0700000u32).is_infinite() == false) { panic("is_infinite #328") }
    if !(V(0xc0700000u32).is_finite() == true) { panic("is_finite #329") }
    if !(V(0xc0700000u32).is_normal() == true) { panic("is_normal #330") }
    if !(V(0xc0700000u32).is_subnormal() == false) { panic("is_subnormal #331") }
    if !(V(0xc0700000u32).is_sign_negative() == true) { panic("is_sign_negative #332") }
    if !(V(0xc0700000u32).is_sign_positive() == false) { panic("is_sign_positive #333") }
    if !(V(0xc0700000u32).classify() == FpCategory.Normal) { panic("classify #334") }
    if !(V(0xc0700000u32).abs().to_bits() == 0x40700000u32) { panic("abs #335") }
    if !(V(0xc0700000u32).floor().to_bits() == 0xc0800000u32) { panic("floor #336") }
    if !(V(0xc0700000u32).ceil().to_bits() == 0xc0400000u32) { panic("ceil #337") }
    if !(V(0xc0700000u32).trunc().to_bits() == 0xc0400000u32) { panic("trunc #338") }
    if !(V(0xc0700000u32).round().to_bits() == 0xc0800000u32) { panic("round #339") }
    if !(V(0xc0700000u32).round_ties_even().to_bits() == 0xc0800000u32) { panic("round_ties_even #340") }
    if !(V(0xc0700000u32).fract().to_bits() == 0xbf400000u32) { panic("fract #341") }
    if !(V(0xc0700000u32).signum().to_bits() == 0xbf800000u32) { panic("signum #342") }
    if !(V(0xc0700000u32).recip().to_bits() == 0xbe888889u32) { panic("recip #343") }
    if !(V(0xc0700000u32).sqrt().is_nan()) { panic("sqrt #344") }
    if !(V(0xc0700000u32).to_bits() == 0xc0700000u32) { panic("to_bits #345") }
    if !(V(0xc0700000u32).to_bits() == 0xc0700000u32) { panic("to_bits #346") }
    if !(f32.from_bits(0xc0700000u32).to_bits() == 0xc0700000u32) { panic("from_bits #347") }
    if !(V(0xc0700000u32).to_le_bytes() == [0u8, 0u8, 112u8, 192u8]) { panic("to_le_bytes #348") }
    if !(V(0xc0700000u32).to_be_bytes() == [192u8, 112u8, 0u8, 0u8]) { panic("to_be_bytes #349") }
    if !(V(0xc0700000u32).to_ne_bytes() == [0u8, 0u8, 112u8, 192u8]) { panic("to_ne_bytes #350") }
    if !(f32.from_le_bytes([0u8, 0u8, 112u8, 192u8]).to_bits() == 0xc0700000u32) { panic("from_le_bytes #351") }
    if !(f32.from_be_bytes([192u8, 112u8, 0u8, 0u8]).to_bits() == 0xc0700000u32) { panic("from_be_bytes #352") }
    if !(f32.from_ne_bytes([0u8, 0u8, 112u8, 192u8]).to_bits() == 0xc0700000u32) { panic("from_ne_bytes #353") }
    if !(V(0xc0700000u32).next_up().to_bits() == 0xc06fffffu32) { panic("next_up #354") }
    if !(V(0xc0700000u32).next_down().to_bits() == 0xc0700001u32) { panic("next_down #355") }
    if !(unsafe { V(0xc0700000u32).to_int_unchecked<i32>() } == (-3i32)) { panic("to_int_unchecked #356") }
    if !(V(0xc0700000u32).total_cmp(V(0xc0700000u32)) == Ordering.Equal) { panic("total_cmp #357") }
    if !(V(0x3dcccccdu32).is_nan() == false) { panic("is_nan #358") }
    if !(V(0x3dcccccdu32).is_infinite() == false) { panic("is_infinite #359") }
    if !(V(0x3dcccccdu32).is_finite() == true) { panic("is_finite #360") }
}

fn group3() {
    if !(V(0x3dcccccdu32).is_normal() == true) { panic("is_normal #361") }
    if !(V(0x3dcccccdu32).is_subnormal() == false) { panic("is_subnormal #362") }
    if !(V(0x3dcccccdu32).is_sign_negative() == false) { panic("is_sign_negative #363") }
    if !(V(0x3dcccccdu32).is_sign_positive() == true) { panic("is_sign_positive #364") }
    if !(V(0x3dcccccdu32).classify() == FpCategory.Normal) { panic("classify #365") }
    if !(V(0x3dcccccdu32).abs().to_bits() == 0x3dcccccdu32) { panic("abs #366") }
    if !(V(0x3dcccccdu32).floor().to_bits() == 0x0u32) { panic("floor #367") }
    if !(V(0x3dcccccdu32).ceil().to_bits() == 0x3f800000u32) { panic("ceil #368") }
    if !(V(0x3dcccccdu32).trunc().to_bits() == 0x0u32) { panic("trunc #369") }
    if !(V(0x3dcccccdu32).round().to_bits() == 0x0u32) { panic("round #370") }
    if !(V(0x3dcccccdu32).round_ties_even().to_bits() == 0x0u32) { panic("round_ties_even #371") }
    if !(V(0x3dcccccdu32).fract().to_bits() == 0x3dcccccdu32) { panic("fract #372") }
    if !(V(0x3dcccccdu32).signum().to_bits() == 0x3f800000u32) { panic("signum #373") }
    if !(V(0x3dcccccdu32).recip().to_bits() == 0x41200000u32) { panic("recip #374") }
    if !(V(0x3dcccccdu32).sqrt().to_bits() == 0x3ea1e89bu32) { panic("sqrt #375") }
    if !(V(0x3dcccccdu32).to_bits() == 0x3dcccccdu32) { panic("to_bits #376") }
    if !(V(0x3dcccccdu32).to_bits() == 0x3dcccccdu32) { panic("to_bits #377") }
    if !(f32.from_bits(0x3dcccccdu32).to_bits() == 0x3dcccccdu32) { panic("from_bits #378") }
    if !(V(0x3dcccccdu32).to_le_bytes() == [205u8, 204u8, 204u8, 61u8]) { panic("to_le_bytes #379") }
    if !(V(0x3dcccccdu32).to_be_bytes() == [61u8, 204u8, 204u8, 205u8]) { panic("to_be_bytes #380") }
    if !(V(0x3dcccccdu32).to_ne_bytes() == [205u8, 204u8, 204u8, 61u8]) { panic("to_ne_bytes #381") }
    if !(f32.from_le_bytes([205u8, 204u8, 204u8, 61u8]).to_bits() == 0x3dcccccdu32) { panic("from_le_bytes #382") }
    if !(f32.from_be_bytes([61u8, 204u8, 204u8, 205u8]).to_bits() == 0x3dcccccdu32) { panic("from_be_bytes #383") }
    if !(f32.from_ne_bytes([205u8, 204u8, 204u8, 61u8]).to_bits() == 0x3dcccccdu32) { panic("from_ne_bytes #384") }
    if !(V(0x3dcccccdu32).next_up().to_bits() == 0x3dccccceu32) { panic("next_up #385") }
    if !(V(0x3dcccccdu32).next_down().to_bits() == 0x3dccccccu32) { panic("next_down #386") }
    if !(unsafe { V(0x3dcccccdu32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #387") }
    if !(V(0x3dcccccdu32).total_cmp(V(0x3dcccccdu32)) == Ordering.Equal) { panic("total_cmp #388") }
    if !(V(0x501502f9u32).is_nan() == false) { panic("is_nan #389") }
    if !(V(0x501502f9u32).is_infinite() == false) { panic("is_infinite #390") }
    if !(V(0x501502f9u32).is_finite() == true) { panic("is_finite #391") }
    if !(V(0x501502f9u32).is_normal() == true) { panic("is_normal #392") }
    if !(V(0x501502f9u32).is_subnormal() == false) { panic("is_subnormal #393") }
    if !(V(0x501502f9u32).is_sign_negative() == false) { panic("is_sign_negative #394") }
    if !(V(0x501502f9u32).is_sign_positive() == true) { panic("is_sign_positive #395") }
    if !(V(0x501502f9u32).classify() == FpCategory.Normal) { panic("classify #396") }
    if !(V(0x501502f9u32).abs().to_bits() == 0x501502f9u32) { panic("abs #397") }
    if !(V(0x501502f9u32).floor().to_bits() == 0x501502f9u32) { panic("floor #398") }
    if !(V(0x501502f9u32).ceil().to_bits() == 0x501502f9u32) { panic("ceil #399") }
    if !(V(0x501502f9u32).trunc().to_bits() == 0x501502f9u32) { panic("trunc #400") }
    if !(V(0x501502f9u32).round().to_bits() == 0x501502f9u32) { panic("round #401") }
    if !(V(0x501502f9u32).round_ties_even().to_bits() == 0x501502f9u32) { panic("round_ties_even #402") }
    if !(V(0x501502f9u32).fract().to_bits() == 0x0u32) { panic("fract #403") }
    if !(V(0x501502f9u32).signum().to_bits() == 0x3f800000u32) { panic("signum #404") }
    if !(V(0x501502f9u32).recip().to_bits() == 0x2edbe6ffu32) { panic("recip #405") }
    if !(V(0x501502f9u32).sqrt().to_bits() == 0x47c35000u32) { panic("sqrt #406") }
    if !(V(0x501502f9u32).to_bits() == 0x501502f9u32) { panic("to_bits #407") }
    if !(V(0x501502f9u32).to_bits() == 0x501502f9u32) { panic("to_bits #408") }
    if !(f32.from_bits(0x501502f9u32).to_bits() == 0x501502f9u32) { panic("from_bits #409") }
    if !(V(0x501502f9u32).to_le_bytes() == [249u8, 2u8, 21u8, 80u8]) { panic("to_le_bytes #410") }
    if !(V(0x501502f9u32).to_be_bytes() == [80u8, 21u8, 2u8, 249u8]) { panic("to_be_bytes #411") }
    if !(V(0x501502f9u32).to_ne_bytes() == [249u8, 2u8, 21u8, 80u8]) { panic("to_ne_bytes #412") }
    if !(f32.from_le_bytes([249u8, 2u8, 21u8, 80u8]).to_bits() == 0x501502f9u32) { panic("from_le_bytes #413") }
    if !(f32.from_be_bytes([80u8, 21u8, 2u8, 249u8]).to_bits() == 0x501502f9u32) { panic("from_be_bytes #414") }
    if !(f32.from_ne_bytes([249u8, 2u8, 21u8, 80u8]).to_bits() == 0x501502f9u32) { panic("from_ne_bytes #415") }
    if !(V(0x501502f9u32).next_up().to_bits() == 0x501502fau32) { panic("next_up #416") }
    if !(V(0x501502f9u32).next_down().to_bits() == 0x501502f8u32) { panic("next_down #417") }
    if !(V(0x501502f9u32).total_cmp(V(0x501502f9u32)) == Ordering.Equal) { panic("total_cmp #418") }
    if !(V(0xd01502f9u32).is_nan() == false) { panic("is_nan #419") }
    if !(V(0xd01502f9u32).is_infinite() == false) { panic("is_infinite #420") }
    if !(V(0xd01502f9u32).is_finite() == true) { panic("is_finite #421") }
    if !(V(0xd01502f9u32).is_normal() == true) { panic("is_normal #422") }
    if !(V(0xd01502f9u32).is_subnormal() == false) { panic("is_subnormal #423") }
    if !(V(0xd01502f9u32).is_sign_negative() == true) { panic("is_sign_negative #424") }
    if !(V(0xd01502f9u32).is_sign_positive() == false) { panic("is_sign_positive #425") }
    if !(V(0xd01502f9u32).classify() == FpCategory.Normal) { panic("classify #426") }
    if !(V(0xd01502f9u32).abs().to_bits() == 0x501502f9u32) { panic("abs #427") }
    if !(V(0xd01502f9u32).floor().to_bits() == 0xd01502f9u32) { panic("floor #428") }
    if !(V(0xd01502f9u32).ceil().to_bits() == 0xd01502f9u32) { panic("ceil #429") }
    if !(V(0xd01502f9u32).trunc().to_bits() == 0xd01502f9u32) { panic("trunc #430") }
    if !(V(0xd01502f9u32).round().to_bits() == 0xd01502f9u32) { panic("round #431") }
    if !(V(0xd01502f9u32).round_ties_even().to_bits() == 0xd01502f9u32) { panic("round_ties_even #432") }
    if !(V(0xd01502f9u32).fract().to_bits() == 0x0u32) { panic("fract #433") }
    if !(V(0xd01502f9u32).signum().to_bits() == 0xbf800000u32) { panic("signum #434") }
    if !(V(0xd01502f9u32).recip().to_bits() == 0xaedbe6ffu32) { panic("recip #435") }
    if !(V(0xd01502f9u32).sqrt().is_nan()) { panic("sqrt #436") }
    if !(V(0xd01502f9u32).to_bits() == 0xd01502f9u32) { panic("to_bits #437") }
    if !(V(0xd01502f9u32).to_bits() == 0xd01502f9u32) { panic("to_bits #438") }
    if !(f32.from_bits(0xd01502f9u32).to_bits() == 0xd01502f9u32) { panic("from_bits #439") }
    if !(V(0xd01502f9u32).to_le_bytes() == [249u8, 2u8, 21u8, 208u8]) { panic("to_le_bytes #440") }
    if !(V(0xd01502f9u32).to_be_bytes() == [208u8, 21u8, 2u8, 249u8]) { panic("to_be_bytes #441") }
    if !(V(0xd01502f9u32).to_ne_bytes() == [249u8, 2u8, 21u8, 208u8]) { panic("to_ne_bytes #442") }
    if !(f32.from_le_bytes([249u8, 2u8, 21u8, 208u8]).to_bits() == 0xd01502f9u32) { panic("from_le_bytes #443") }
    if !(f32.from_be_bytes([208u8, 21u8, 2u8, 249u8]).to_bits() == 0xd01502f9u32) { panic("from_be_bytes #444") }
    if !(f32.from_ne_bytes([249u8, 2u8, 21u8, 208u8]).to_bits() == 0xd01502f9u32) { panic("from_ne_bytes #445") }
    if !(V(0xd01502f9u32).next_up().to_bits() == 0xd01502f8u32) { panic("next_up #446") }
    if !(V(0xd01502f9u32).next_down().to_bits() == 0xd01502fau32) { panic("next_down #447") }
    if !(V(0xd01502f9u32).total_cmp(V(0xd01502f9u32)) == Ordering.Equal) { panic("total_cmp #448") }
    if !(V(0x7f7fffffu32).is_nan() == false) { panic("is_nan #449") }
    if !(V(0x7f7fffffu32).is_infinite() == false) { panic("is_infinite #450") }
    if !(V(0x7f7fffffu32).is_finite() == true) { panic("is_finite #451") }
    if !(V(0x7f7fffffu32).is_normal() == true) { panic("is_normal #452") }
    if !(V(0x7f7fffffu32).is_subnormal() == false) { panic("is_subnormal #453") }
    if !(V(0x7f7fffffu32).is_sign_negative() == false) { panic("is_sign_negative #454") }
    if !(V(0x7f7fffffu32).is_sign_positive() == true) { panic("is_sign_positive #455") }
    if !(V(0x7f7fffffu32).classify() == FpCategory.Normal) { panic("classify #456") }
    if !(V(0x7f7fffffu32).abs().to_bits() == 0x7f7fffffu32) { panic("abs #457") }
    if !(V(0x7f7fffffu32).floor().to_bits() == 0x7f7fffffu32) { panic("floor #458") }
    if !(V(0x7f7fffffu32).ceil().to_bits() == 0x7f7fffffu32) { panic("ceil #459") }
    if !(V(0x7f7fffffu32).trunc().to_bits() == 0x7f7fffffu32) { panic("trunc #460") }
    if !(V(0x7f7fffffu32).round().to_bits() == 0x7f7fffffu32) { panic("round #461") }
    if !(V(0x7f7fffffu32).round_ties_even().to_bits() == 0x7f7fffffu32) { panic("round_ties_even #462") }
    if !(V(0x7f7fffffu32).fract().to_bits() == 0x0u32) { panic("fract #463") }
    if !(V(0x7f7fffffu32).signum().to_bits() == 0x3f800000u32) { panic("signum #464") }
    if !(V(0x7f7fffffu32).recip().to_bits() == 0x200000u32) { panic("recip #465") }
    if !(V(0x7f7fffffu32).sqrt().to_bits() == 0x5f7fffffu32) { panic("sqrt #466") }
    if !(V(0x7f7fffffu32).to_bits() == 0x7f7fffffu32) { panic("to_bits #467") }
    if !(V(0x7f7fffffu32).to_bits() == 0x7f7fffffu32) { panic("to_bits #468") }
    if !(f32.from_bits(0x7f7fffffu32).to_bits() == 0x7f7fffffu32) { panic("from_bits #469") }
    if !(V(0x7f7fffffu32).to_le_bytes() == [255u8, 255u8, 127u8, 127u8]) { panic("to_le_bytes #470") }
    if !(V(0x7f7fffffu32).to_be_bytes() == [127u8, 127u8, 255u8, 255u8]) { panic("to_be_bytes #471") }
    if !(V(0x7f7fffffu32).to_ne_bytes() == [255u8, 255u8, 127u8, 127u8]) { panic("to_ne_bytes #472") }
    if !(f32.from_le_bytes([255u8, 255u8, 127u8, 127u8]).to_bits() == 0x7f7fffffu32) { panic("from_le_bytes #473") }
    if !(f32.from_be_bytes([127u8, 127u8, 255u8, 255u8]).to_bits() == 0x7f7fffffu32) { panic("from_be_bytes #474") }
    if !(f32.from_ne_bytes([255u8, 255u8, 127u8, 127u8]).to_bits() == 0x7f7fffffu32) { panic("from_ne_bytes #475") }
    if !(V(0x7f7fffffu32).next_up().to_bits() == 0x7f800000u32) { panic("next_up #476") }
    if !(V(0x7f7fffffu32).next_down().to_bits() == 0x7f7ffffeu32) { panic("next_down #477") }
    if !(V(0x7f7fffffu32).total_cmp(V(0x7f7fffffu32)) == Ordering.Equal) { panic("total_cmp #478") }
    if !(V(0xff7fffffu32).is_nan() == false) { panic("is_nan #479") }
    if !(V(0xff7fffffu32).is_infinite() == false) { panic("is_infinite #480") }
}

fn group4() {
    if !(V(0xff7fffffu32).is_finite() == true) { panic("is_finite #481") }
    if !(V(0xff7fffffu32).is_normal() == true) { panic("is_normal #482") }
    if !(V(0xff7fffffu32).is_subnormal() == false) { panic("is_subnormal #483") }
    if !(V(0xff7fffffu32).is_sign_negative() == true) { panic("is_sign_negative #484") }
    if !(V(0xff7fffffu32).is_sign_positive() == false) { panic("is_sign_positive #485") }
    if !(V(0xff7fffffu32).classify() == FpCategory.Normal) { panic("classify #486") }
    if !(V(0xff7fffffu32).abs().to_bits() == 0x7f7fffffu32) { panic("abs #487") }
    if !(V(0xff7fffffu32).floor().to_bits() == 0xff7fffffu32) { panic("floor #488") }
    if !(V(0xff7fffffu32).ceil().to_bits() == 0xff7fffffu32) { panic("ceil #489") }
    if !(V(0xff7fffffu32).trunc().to_bits() == 0xff7fffffu32) { panic("trunc #490") }
    if !(V(0xff7fffffu32).round().to_bits() == 0xff7fffffu32) { panic("round #491") }
    if !(V(0xff7fffffu32).round_ties_even().to_bits() == 0xff7fffffu32) { panic("round_ties_even #492") }
    if !(V(0xff7fffffu32).fract().to_bits() == 0x0u32) { panic("fract #493") }
    if !(V(0xff7fffffu32).signum().to_bits() == 0xbf800000u32) { panic("signum #494") }
    if !(V(0xff7fffffu32).recip().to_bits() == 0x80200000u32) { panic("recip #495") }
    if !(V(0xff7fffffu32).sqrt().is_nan()) { panic("sqrt #496") }
    if !(V(0xff7fffffu32).to_bits() == 0xff7fffffu32) { panic("to_bits #497") }
    if !(V(0xff7fffffu32).to_bits() == 0xff7fffffu32) { panic("to_bits #498") }
    if !(f32.from_bits(0xff7fffffu32).to_bits() == 0xff7fffffu32) { panic("from_bits #499") }
    if !(V(0xff7fffffu32).to_le_bytes() == [255u8, 255u8, 127u8, 255u8]) { panic("to_le_bytes #500") }
    if !(V(0xff7fffffu32).to_be_bytes() == [255u8, 127u8, 255u8, 255u8]) { panic("to_be_bytes #501") }
    if !(V(0xff7fffffu32).to_ne_bytes() == [255u8, 255u8, 127u8, 255u8]) { panic("to_ne_bytes #502") }
    if !(f32.from_le_bytes([255u8, 255u8, 127u8, 255u8]).to_bits() == 0xff7fffffu32) { panic("from_le_bytes #503") }
    if !(f32.from_be_bytes([255u8, 127u8, 255u8, 255u8]).to_bits() == 0xff7fffffu32) { panic("from_be_bytes #504") }
    if !(f32.from_ne_bytes([255u8, 255u8, 127u8, 255u8]).to_bits() == 0xff7fffffu32) { panic("from_ne_bytes #505") }
    if !(V(0xff7fffffu32).next_up().to_bits() == 0xff7ffffeu32) { panic("next_up #506") }
    if !(V(0xff7fffffu32).next_down().to_bits() == 0xff800000u32) { panic("next_down #507") }
    if !(V(0xff7fffffu32).total_cmp(V(0xff7fffffu32)) == Ordering.Equal) { panic("total_cmp #508") }
    if !(V(0x800000u32).is_nan() == false) { panic("is_nan #509") }
    if !(V(0x800000u32).is_infinite() == false) { panic("is_infinite #510") }
    if !(V(0x800000u32).is_finite() == true) { panic("is_finite #511") }
    if !(V(0x800000u32).is_normal() == true) { panic("is_normal #512") }
    if !(V(0x800000u32).is_subnormal() == false) { panic("is_subnormal #513") }
    if !(V(0x800000u32).is_sign_negative() == false) { panic("is_sign_negative #514") }
    if !(V(0x800000u32).is_sign_positive() == true) { panic("is_sign_positive #515") }
    if !(V(0x800000u32).classify() == FpCategory.Normal) { panic("classify #516") }
    if !(V(0x800000u32).abs().to_bits() == 0x800000u32) { panic("abs #517") }
    if !(V(0x800000u32).floor().to_bits() == 0x0u32) { panic("floor #518") }
    if !(V(0x800000u32).ceil().to_bits() == 0x3f800000u32) { panic("ceil #519") }
    if !(V(0x800000u32).trunc().to_bits() == 0x0u32) { panic("trunc #520") }
    if !(V(0x800000u32).round().to_bits() == 0x0u32) { panic("round #521") }
    if !(V(0x800000u32).round_ties_even().to_bits() == 0x0u32) { panic("round_ties_even #522") }
    if !(V(0x800000u32).fract().to_bits() == 0x800000u32) { panic("fract #523") }
    if !(V(0x800000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #524") }
    if !(V(0x800000u32).recip().to_bits() == 0x7e800000u32) { panic("recip #525") }
    if !(V(0x800000u32).sqrt().to_bits() == 0x20000000u32) { panic("sqrt #526") }
    if !(V(0x800000u32).to_bits() == 0x800000u32) { panic("to_bits #527") }
    if !(V(0x800000u32).to_bits() == 0x800000u32) { panic("to_bits #528") }
    if !(f32.from_bits(0x800000u32).to_bits() == 0x800000u32) { panic("from_bits #529") }
    if !(V(0x800000u32).to_le_bytes() == [0u8, 0u8, 128u8, 0u8]) { panic("to_le_bytes #530") }
    if !(V(0x800000u32).to_be_bytes() == [0u8, 128u8, 0u8, 0u8]) { panic("to_be_bytes #531") }
    if !(V(0x800000u32).to_ne_bytes() == [0u8, 0u8, 128u8, 0u8]) { panic("to_ne_bytes #532") }
    if !(f32.from_le_bytes([0u8, 0u8, 128u8, 0u8]).to_bits() == 0x800000u32) { panic("from_le_bytes #533") }
    if !(f32.from_be_bytes([0u8, 128u8, 0u8, 0u8]).to_bits() == 0x800000u32) { panic("from_be_bytes #534") }
    if !(f32.from_ne_bytes([0u8, 0u8, 128u8, 0u8]).to_bits() == 0x800000u32) { panic("from_ne_bytes #535") }
    if !(V(0x800000u32).next_up().to_bits() == 0x800001u32) { panic("next_up #536") }
    if !(V(0x800000u32).next_down().to_bits() == 0x7fffffu32) { panic("next_down #537") }
    if !(unsafe { V(0x800000u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #538") }
    if !(V(0x800000u32).total_cmp(V(0x800000u32)) == Ordering.Equal) { panic("total_cmp #539") }
    if !(V(0x1u32).is_nan() == false) { panic("is_nan #540") }
    if !(V(0x1u32).is_infinite() == false) { panic("is_infinite #541") }
    if !(V(0x1u32).is_finite() == true) { panic("is_finite #542") }
    if !(V(0x1u32).is_normal() == false) { panic("is_normal #543") }
    if !(V(0x1u32).is_subnormal() == true) { panic("is_subnormal #544") }
    if !(V(0x1u32).is_sign_negative() == false) { panic("is_sign_negative #545") }
    if !(V(0x1u32).is_sign_positive() == true) { panic("is_sign_positive #546") }
    if !(V(0x1u32).classify() == FpCategory.Subnormal) { panic("classify #547") }
    if !(V(0x1u32).abs().to_bits() == 0x1u32) { panic("abs #548") }
    if !(V(0x1u32).floor().to_bits() == 0x0u32) { panic("floor #549") }
    if !(V(0x1u32).ceil().to_bits() == 0x3f800000u32) { panic("ceil #550") }
    if !(V(0x1u32).trunc().to_bits() == 0x0u32) { panic("trunc #551") }
    if !(V(0x1u32).round().to_bits() == 0x0u32) { panic("round #552") }
    if !(V(0x1u32).round_ties_even().to_bits() == 0x0u32) { panic("round_ties_even #553") }
    if !(V(0x1u32).fract().to_bits() == 0x1u32) { panic("fract #554") }
    if !(V(0x1u32).signum().to_bits() == 0x3f800000u32) { panic("signum #555") }
    if !(V(0x1u32).recip().to_bits() == 0x7f800000u32) { panic("recip #556") }
    if !(V(0x1u32).sqrt().to_bits() == 0x1a3504f3u32) { panic("sqrt #557") }
    if !(V(0x1u32).to_bits() == 0x1u32) { panic("to_bits #558") }
    if !(V(0x1u32).to_bits() == 0x1u32) { panic("to_bits #559") }
    if !(f32.from_bits(0x1u32).to_bits() == 0x1u32) { panic("from_bits #560") }
    if !(V(0x1u32).to_le_bytes() == [1u8, 0u8, 0u8, 0u8]) { panic("to_le_bytes #561") }
    if !(V(0x1u32).to_be_bytes() == [0u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #562") }
    if !(V(0x1u32).to_ne_bytes() == [1u8, 0u8, 0u8, 0u8]) { panic("to_ne_bytes #563") }
    if !(f32.from_le_bytes([1u8, 0u8, 0u8, 0u8]).to_bits() == 0x1u32) { panic("from_le_bytes #564") }
    if !(f32.from_be_bytes([0u8, 0u8, 0u8, 1u8]).to_bits() == 0x1u32) { panic("from_be_bytes #565") }
    if !(f32.from_ne_bytes([1u8, 0u8, 0u8, 0u8]).to_bits() == 0x1u32) { panic("from_ne_bytes #566") }
    if !(V(0x1u32).next_up().to_bits() == 0x2u32) { panic("next_up #567") }
    if !(V(0x1u32).next_down().to_bits() == 0x0u32) { panic("next_down #568") }
    if !(unsafe { V(0x1u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #569") }
    if !(V(0x1u32).total_cmp(V(0x1u32)) == Ordering.Equal) { panic("total_cmp #570") }
    if !(V(0x80000001u32).is_nan() == false) { panic("is_nan #571") }
    if !(V(0x80000001u32).is_infinite() == false) { panic("is_infinite #572") }
    if !(V(0x80000001u32).is_finite() == true) { panic("is_finite #573") }
    if !(V(0x80000001u32).is_normal() == false) { panic("is_normal #574") }
    if !(V(0x80000001u32).is_subnormal() == true) { panic("is_subnormal #575") }
    if !(V(0x80000001u32).is_sign_negative() == true) { panic("is_sign_negative #576") }
    if !(V(0x80000001u32).is_sign_positive() == false) { panic("is_sign_positive #577") }
    if !(V(0x80000001u32).classify() == FpCategory.Subnormal) { panic("classify #578") }
    if !(V(0x80000001u32).abs().to_bits() == 0x1u32) { panic("abs #579") }
    if !(V(0x80000001u32).floor().to_bits() == 0xbf800000u32) { panic("floor #580") }
    if !(V(0x80000001u32).ceil().to_bits() == 0x80000000u32) { panic("ceil #581") }
    if !(V(0x80000001u32).trunc().to_bits() == 0x80000000u32) { panic("trunc #582") }
    if !(V(0x80000001u32).round().to_bits() == 0x80000000u32) { panic("round #583") }
    if !(V(0x80000001u32).round_ties_even().to_bits() == 0x80000000u32) { panic("round_ties_even #584") }
    if !(V(0x80000001u32).fract().to_bits() == 0x80000001u32) { panic("fract #585") }
    if !(V(0x80000001u32).signum().to_bits() == 0xbf800000u32) { panic("signum #586") }
    if !(V(0x80000001u32).recip().to_bits() == 0xff800000u32) { panic("recip #587") }
    if !(V(0x80000001u32).sqrt().is_nan()) { panic("sqrt #588") }
    if !(V(0x80000001u32).to_bits() == 0x80000001u32) { panic("to_bits #589") }
    if !(V(0x80000001u32).to_bits() == 0x80000001u32) { panic("to_bits #590") }
    if !(f32.from_bits(0x80000001u32).to_bits() == 0x80000001u32) { panic("from_bits #591") }
    if !(V(0x80000001u32).to_le_bytes() == [1u8, 0u8, 0u8, 128u8]) { panic("to_le_bytes #592") }
    if !(V(0x80000001u32).to_be_bytes() == [128u8, 0u8, 0u8, 1u8]) { panic("to_be_bytes #593") }
    if !(V(0x80000001u32).to_ne_bytes() == [1u8, 0u8, 0u8, 128u8]) { panic("to_ne_bytes #594") }
    if !(f32.from_le_bytes([1u8, 0u8, 0u8, 128u8]).to_bits() == 0x80000001u32) { panic("from_le_bytes #595") }
    if !(f32.from_be_bytes([128u8, 0u8, 0u8, 1u8]).to_bits() == 0x80000001u32) { panic("from_be_bytes #596") }
    if !(f32.from_ne_bytes([1u8, 0u8, 0u8, 128u8]).to_bits() == 0x80000001u32) { panic("from_ne_bytes #597") }
    if !(V(0x80000001u32).next_up().to_bits() == 0x80000000u32) { panic("next_up #598") }
    if !(V(0x80000001u32).next_down().to_bits() == 0x80000002u32) { panic("next_down #599") }
    if !(unsafe { V(0x80000001u32).to_int_unchecked<i32>() } == 0i32) { panic("to_int_unchecked #600") }
}

fn group5() {
    if !(V(0x80000001u32).total_cmp(V(0x80000001u32)) == Ordering.Equal) { panic("total_cmp #601") }
    if !(V(0x7f800000u32).is_nan() == false) { panic("is_nan #602") }
    if !(V(0x7f800000u32).is_infinite() == true) { panic("is_infinite #603") }
    if !(V(0x7f800000u32).is_finite() == false) { panic("is_finite #604") }
    if !(V(0x7f800000u32).is_normal() == false) { panic("is_normal #605") }
    if !(V(0x7f800000u32).is_subnormal() == false) { panic("is_subnormal #606") }
    if !(V(0x7f800000u32).is_sign_negative() == false) { panic("is_sign_negative #607") }
    if !(V(0x7f800000u32).is_sign_positive() == true) { panic("is_sign_positive #608") }
    if !(V(0x7f800000u32).classify() == FpCategory.Infinite) { panic("classify #609") }
    if !(V(0x7f800000u32).abs().to_bits() == 0x7f800000u32) { panic("abs #610") }
    if !(V(0x7f800000u32).floor().to_bits() == 0x7f800000u32) { panic("floor #611") }
    if !(V(0x7f800000u32).ceil().to_bits() == 0x7f800000u32) { panic("ceil #612") }
    if !(V(0x7f800000u32).trunc().to_bits() == 0x7f800000u32) { panic("trunc #613") }
    if !(V(0x7f800000u32).round().to_bits() == 0x7f800000u32) { panic("round #614") }
    if !(V(0x7f800000u32).round_ties_even().to_bits() == 0x7f800000u32) { panic("round_ties_even #615") }
    if !(V(0x7f800000u32).fract().is_nan()) { panic("fract #616") }
    if !(V(0x7f800000u32).signum().to_bits() == 0x3f800000u32) { panic("signum #617") }
    if !(V(0x7f800000u32).recip().to_bits() == 0x0u32) { panic("recip #618") }
    if !(V(0x7f800000u32).sqrt().to_bits() == 0x7f800000u32) { panic("sqrt #619") }
    if !(V(0x7f800000u32).to_bits() == 0x7f800000u32) { panic("to_bits #620") }
    if !(V(0x7f800000u32).to_bits() == 0x7f800000u32) { panic("to_bits #621") }
    if !(f32.from_bits(0x7f800000u32).to_bits() == 0x7f800000u32) { panic("from_bits #622") }
    if !(V(0x7f800000u32).to_le_bytes() == [0u8, 0u8, 128u8, 127u8]) { panic("to_le_bytes #623") }
    if !(V(0x7f800000u32).to_be_bytes() == [127u8, 128u8, 0u8, 0u8]) { panic("to_be_bytes #624") }
    if !(V(0x7f800000u32).to_ne_bytes() == [0u8, 0u8, 128u8, 127u8]) { panic("to_ne_bytes #625") }
    if !(f32.from_le_bytes([0u8, 0u8, 128u8, 127u8]).to_bits() == 0x7f800000u32) { panic("from_le_bytes #626") }
    if !(f32.from_be_bytes([127u8, 128u8, 0u8, 0u8]).to_bits() == 0x7f800000u32) { panic("from_be_bytes #627") }
    if !(f32.from_ne_bytes([0u8, 0u8, 128u8, 127u8]).to_bits() == 0x7f800000u32) { panic("from_ne_bytes #628") }
    if !(V(0x7f800000u32).next_up().to_bits() == 0x7f800000u32) { panic("next_up #629") }
    if !(V(0x7f800000u32).next_down().to_bits() == 0x7f7fffffu32) { panic("next_down #630") }
    if !(V(0x7f800000u32).total_cmp(V(0x7f800000u32)) == Ordering.Equal) { panic("total_cmp #631") }
    if !(V(0x7f800000u32).to_degrees().to_bits() == 0x7f800000u32) { panic("to_degrees #632") }
    if !(V(0xff800000u32).is_nan() == false) { panic("is_nan #633") }
    if !(V(0xff800000u32).is_infinite() == true) { panic("is_infinite #634") }
    if !(V(0xff800000u32).is_finite() == false) { panic("is_finite #635") }
    if !(V(0xff800000u32).is_normal() == false) { panic("is_normal #636") }
    if !(V(0xff800000u32).is_subnormal() == false) { panic("is_subnormal #637") }
    if !(V(0xff800000u32).is_sign_negative() == true) { panic("is_sign_negative #638") }
    if !(V(0xff800000u32).is_sign_positive() == false) { panic("is_sign_positive #639") }
    if !(V(0xff800000u32).classify() == FpCategory.Infinite) { panic("classify #640") }
    if !(V(0xff800000u32).abs().to_bits() == 0x7f800000u32) { panic("abs #641") }
    if !(V(0xff800000u32).floor().to_bits() == 0xff800000u32) { panic("floor #642") }
    if !(V(0xff800000u32).ceil().to_bits() == 0xff800000u32) { panic("ceil #643") }
    if !(V(0xff800000u32).trunc().to_bits() == 0xff800000u32) { panic("trunc #644") }
    if !(V(0xff800000u32).round().to_bits() == 0xff800000u32) { panic("round #645") }
    if !(V(0xff800000u32).round_ties_even().to_bits() == 0xff800000u32) { panic("round_ties_even #646") }
    if !(V(0xff800000u32).fract().is_nan()) { panic("fract #647") }
    if !(V(0xff800000u32).signum().to_bits() == 0xbf800000u32) { panic("signum #648") }
    if !(V(0xff800000u32).recip().to_bits() == 0x80000000u32) { panic("recip #649") }
    if !(V(0xff800000u32).sqrt().is_nan()) { panic("sqrt #650") }
    if !(V(0xff800000u32).to_bits() == 0xff800000u32) { panic("to_bits #651") }
    if !(V(0xff800000u32).to_bits() == 0xff800000u32) { panic("to_bits #652") }
    if !(f32.from_bits(0xff800000u32).to_bits() == 0xff800000u32) { panic("from_bits #653") }
    if !(V(0xff800000u32).to_le_bytes() == [0u8, 0u8, 128u8, 255u8]) { panic("to_le_bytes #654") }
    if !(V(0xff800000u32).to_be_bytes() == [255u8, 128u8, 0u8, 0u8]) { panic("to_be_bytes #655") }
    if !(V(0xff800000u32).to_ne_bytes() == [0u8, 0u8, 128u8, 255u8]) { panic("to_ne_bytes #656") }
    if !(f32.from_le_bytes([0u8, 0u8, 128u8, 255u8]).to_bits() == 0xff800000u32) { panic("from_le_bytes #657") }
    if !(f32.from_be_bytes([255u8, 128u8, 0u8, 0u8]).to_bits() == 0xff800000u32) { panic("from_be_bytes #658") }
    if !(f32.from_ne_bytes([0u8, 0u8, 128u8, 255u8]).to_bits() == 0xff800000u32) { panic("from_ne_bytes #659") }
    if !(V(0xff800000u32).next_up().to_bits() == 0xff7fffffu32) { panic("next_up #660") }
    if !(V(0xff800000u32).next_down().to_bits() == 0xff800000u32) { panic("next_down #661") }
    if !(V(0xff800000u32).total_cmp(V(0xff800000u32)) == Ordering.Equal) { panic("total_cmp #662") }
    if !(V(0xff800000u32).to_degrees().to_bits() == 0xff800000u32) { panic("to_degrees #663") }
    if !(V(0x7fc00000u32).is_nan() == true) { panic("is_nan #664") }
    if !(V(0x7fc00000u32).is_infinite() == false) { panic("is_infinite #665") }
    if !(V(0x7fc00000u32).is_finite() == false) { panic("is_finite #666") }
    if !(V(0x7fc00000u32).is_normal() == false) { panic("is_normal #667") }
    if !(V(0x7fc00000u32).is_subnormal() == false) { panic("is_subnormal #668") }
    if !(V(0x7fc00000u32).is_sign_negative() == false) { panic("is_sign_negative #669") }
    if !(V(0x7fc00000u32).is_sign_positive() == true) { panic("is_sign_positive #670") }
    if !(V(0x7fc00000u32).classify() == FpCategory.Nan) { panic("classify #671") }
    if !(V(0x7fc00000u32).abs().is_nan()) { panic("abs #672") }
    if !(V(0x7fc00000u32).floor().is_nan()) { panic("floor #673") }
    if !(V(0x7fc00000u32).ceil().is_nan()) { panic("ceil #674") }
    if !(V(0x7fc00000u32).trunc().is_nan()) { panic("trunc #675") }
    if !(V(0x7fc00000u32).round().is_nan()) { panic("round #676") }
    if !(V(0x7fc00000u32).round_ties_even().is_nan()) { panic("round_ties_even #677") }
    if !(V(0x7fc00000u32).fract().is_nan()) { panic("fract #678") }
    if !(V(0x7fc00000u32).signum().is_nan()) { panic("signum #679") }
    if !(V(0x7fc00000u32).recip().is_nan()) { panic("recip #680") }
    if !(V(0x7fc00000u32).is_nan()) { panic("to_bits #681") }
    if !(V(0x7fc00000u32).to_bits() == 0x7fc00000u32) { panic("to_bits #682") }
    if !(f32.from_bits(0x7fc00000u32).to_bits() == 0x7fc00000u32) { panic("from_bits #683") }
    if !(V(0x7fc00000u32).to_le_bytes() == [0u8, 0u8, 192u8, 127u8]) { panic("to_le_bytes #684") }
    if !(V(0x7fc00000u32).to_be_bytes() == [127u8, 192u8, 0u8, 0u8]) { panic("to_be_bytes #685") }
    if !(V(0x7fc00000u32).to_ne_bytes() == [0u8, 0u8, 192u8, 127u8]) { panic("to_ne_bytes #686") }
    if !(f32.from_le_bytes([0u8, 0u8, 192u8, 127u8]).to_bits() == 0x7fc00000u32) { panic("from_le_bytes #687") }
    if !(f32.from_be_bytes([127u8, 192u8, 0u8, 0u8]).to_bits() == 0x7fc00000u32) { panic("from_be_bytes #688") }
    if !(f32.from_ne_bytes([0u8, 0u8, 192u8, 127u8]).to_bits() == 0x7fc00000u32) { panic("from_ne_bytes #689") }
    if !(V(0x7fc00000u32).next_up().is_nan()) { panic("next_up #690") }
    if !(V(0x7fc00000u32).next_down().is_nan()) { panic("next_down #691") }
    if !(V(0x7fc00000u32).total_cmp(V(0x7fc00000u32)) == Ordering.Equal) { panic("total_cmp #692") }
    if !(V(0x7fc00000u32).to_degrees().is_nan()) { panic("to_degrees #693") }
    if !(V(0x3f800000u32).copysign(V(0x40000000u32)).to_bits() == 0x3f800000u32) { panic("copysign #694") }
    if !(V(0x3f800000u32).min(V(0x40000000u32)).to_bits() == 0x3f800000u32) { panic("min #695") }
    if !(V(0x3f800000u32).max(V(0x40000000u32)).to_bits() == 0x40000000u32) { panic("max #696") }
    if !(V(0x3f800000u32).total_cmp(V(0x40000000u32)) == Ordering.Less) { panic("total_cmp #697") }
    if !(V(0x3f800000u32).rem_euclid(V(0x40000000u32)).to_bits() == 0x3f800000u32) { panic("rem_euclid #698") }
    if !(V(0x3f800000u32).div_euclid(V(0x40000000u32)).to_bits() == 0x0u32) { panic("div_euclid #699") }
    if !(V(0x3f800000u32).midpoint(V(0x40000000u32)).to_bits() == 0x3fc00000u32) { panic("midpoint #700") }
    if !(near(V(0x3f800000u32).algebraic_add(V(0x40000000u32)), V(0x40400000u32), 1u32)) { panic("algebraic_add #701") }
    if !(near(V(0x3f800000u32).algebraic_sub(V(0x40000000u32)), V(0xbf800000u32), 1u32)) { panic("algebraic_sub #702") }
    if !(near(V(0x3f800000u32).algebraic_mul(V(0x40000000u32)), V(0x40000000u32), 1u32)) { panic("algebraic_mul #703") }
    if !(near(V(0x3f800000u32).algebraic_div(V(0x40000000u32)), V(0x3f000000u32), 1u32)) { panic("algebraic_div #704") }
    if !(near(V(0x3f800000u32).algebraic_rem(V(0x40000000u32)), V(0x3f800000u32), 1u32)) { panic("algebraic_rem #705") }
    if !(near(V(0x3f800000u32).hypot(V(0x40000000u32)), V(0x400f1bbdu32), 2u32)) { panic("hypot #706") }
    if !(near(V(0x3f800000u32).atan2(V(0x40000000u32)), V(0x3eed6338u32), 2u32)) { panic("atan2 #707") }
    if !(V(0xbf800000u32).copysign(V(0x40000000u32)).to_bits() == 0x3f800000u32) { panic("copysign #708") }
    if !(V(0xbf800000u32).min(V(0x40000000u32)).to_bits() == 0xbf800000u32) { panic("min #709") }
    if !(V(0xbf800000u32).max(V(0x40000000u32)).to_bits() == 0x40000000u32) { panic("max #710") }
    if !(V(0xbf800000u32).total_cmp(V(0x40000000u32)) == Ordering.Less) { panic("total_cmp #711") }
    if !(V(0xbf800000u32).rem_euclid(V(0x40000000u32)).to_bits() == 0x3f800000u32) { panic("rem_euclid #712") }
    if !(V(0xbf800000u32).div_euclid(V(0x40000000u32)).to_bits() == 0xbf800000u32) { panic("div_euclid #713") }
    if !(V(0xbf800000u32).midpoint(V(0x40000000u32)).to_bits() == 0x3f000000u32) { panic("midpoint #714") }
    if !(near(V(0xbf800000u32).algebraic_add(V(0x40000000u32)), V(0x3f800000u32), 1u32)) { panic("algebraic_add #715") }
    if !(near(V(0xbf800000u32).algebraic_sub(V(0x40000000u32)), V(0xc0400000u32), 1u32)) { panic("algebraic_sub #716") }
    if !(near(V(0xbf800000u32).algebraic_mul(V(0x40000000u32)), V(0xc0000000u32), 1u32)) { panic("algebraic_mul #717") }
    if !(near(V(0xbf800000u32).algebraic_div(V(0x40000000u32)), V(0xbf000000u32), 1u32)) { panic("algebraic_div #718") }
    if !(near(V(0xbf800000u32).algebraic_rem(V(0x40000000u32)), V(0xbf800000u32), 1u32)) { panic("algebraic_rem #719") }
    if !(near(V(0xbf800000u32).hypot(V(0x40000000u32)), V(0x400f1bbdu32), 2u32)) { panic("hypot #720") }
}

fn group6() {
    if !(near(V(0xbf800000u32).atan2(V(0x40000000u32)), V(0xbeed6338u32), 2u32)) { panic("atan2 #721") }
    if !(V(0x40200000u32).copysign(V(0xbf000000u32)).to_bits() == 0xc0200000u32) { panic("copysign #722") }
    if !(V(0x40200000u32).min(V(0xbf000000u32)).to_bits() == 0xbf000000u32) { panic("min #723") }
    if !(V(0x40200000u32).max(V(0xbf000000u32)).to_bits() == 0x40200000u32) { panic("max #724") }
    if !(V(0x40200000u32).total_cmp(V(0xbf000000u32)) == Ordering.Greater) { panic("total_cmp #725") }
    if !(V(0x40200000u32).rem_euclid(V(0xbf000000u32)).to_bits() == 0x0u32) { panic("rem_euclid #726") }
    if !(V(0x40200000u32).div_euclid(V(0xbf000000u32)).to_bits() == 0xc0a00000u32) { panic("div_euclid #727") }
    if !(V(0x40200000u32).midpoint(V(0xbf000000u32)).to_bits() == 0x3f800000u32) { panic("midpoint #728") }
    if !(near(V(0x40200000u32).algebraic_add(V(0xbf000000u32)), V(0x40000000u32), 1u32)) { panic("algebraic_add #729") }
    if !(near(V(0x40200000u32).algebraic_sub(V(0xbf000000u32)), V(0x40400000u32), 1u32)) { panic("algebraic_sub #730") }
    if !(near(V(0x40200000u32).algebraic_mul(V(0xbf000000u32)), V(0xbfa00000u32), 1u32)) { panic("algebraic_mul #731") }
    if !(near(V(0x40200000u32).algebraic_div(V(0xbf000000u32)), V(0xc0a00000u32), 1u32)) { panic("algebraic_div #732") }
    if !(V(0x40200000u32).algebraic_rem(V(0xbf000000u32)).to_bits() == 0x0u32) { panic("algebraic_rem #733") }
    if !(near(V(0x40200000u32).hypot(V(0xbf000000u32)), V(0x40232b2bu32), 2u32)) { panic("hypot #734") }
    if !(near(V(0x40200000u32).atan2(V(0xbf000000u32)), V(0x3fe2541du32), 2u32)) { panic("atan2 #735") }
    if !(V(0x0u32).copysign(V(0x80000000u32)).to_bits() == 0x80000000u32) { panic("copysign #736") }
    if !(V(0x0u32).min(V(0x80000000u32)) == V(0x0u32)) { panic("min #737") }
    if !(V(0x0u32).max(V(0x80000000u32)) == V(0x0u32)) { panic("max #738") }
    if !(V(0x0u32).total_cmp(V(0x80000000u32)) == Ordering.Greater) { panic("total_cmp #739") }
    if !(V(0x80000000u32).copysign(V(0x0u32)).to_bits() == 0x0u32) { panic("copysign #740") }
    if !(V(0x80000000u32).min(V(0x0u32)) == V(0x0u32)) { panic("min #741") }
    if !(V(0x80000000u32).max(V(0x0u32)) == V(0x0u32)) { panic("max #742") }
    if !(V(0x80000000u32).total_cmp(V(0x0u32)) == Ordering.Less) { panic("total_cmp #743") }
    if !(V(0x7f7fffffu32).copysign(V(0x7f7fffffu32)).to_bits() == 0x7f7fffffu32) { panic("copysign #744") }
    if !(V(0x7f7fffffu32).min(V(0x7f7fffffu32)).to_bits() == 0x7f7fffffu32) { panic("min #745") }
    if !(V(0x7f7fffffu32).max(V(0x7f7fffffu32)).to_bits() == 0x7f7fffffu32) { panic("max #746") }
    if !(V(0x7f7fffffu32).total_cmp(V(0x7f7fffffu32)) == Ordering.Equal) { panic("total_cmp #747") }
    if !(V(0x7f7fffffu32).rem_euclid(V(0x7f7fffffu32)).to_bits() == 0x0u32) { panic("rem_euclid #748") }
    if !(V(0x7f7fffffu32).div_euclid(V(0x7f7fffffu32)).to_bits() == 0x3f800000u32) { panic("div_euclid #749") }
    if !(V(0x7f7fffffu32).midpoint(V(0x7f7fffffu32)).to_bits() == 0x7f7fffffu32) { panic("midpoint #750") }
    if !(V(0x7f7fffffu32).algebraic_add(V(0x7f7fffffu32)).to_bits() == 0x7f800000u32) { panic("algebraic_add #751") }
    if !(V(0x7f7fffffu32).algebraic_sub(V(0x7f7fffffu32)).to_bits() == 0x0u32) { panic("algebraic_sub #752") }
    if !(V(0x7f7fffffu32).algebraic_mul(V(0x7f7fffffu32)).to_bits() == 0x7f800000u32) { panic("algebraic_mul #753") }
    if !(near(V(0x7f7fffffu32).algebraic_div(V(0x7f7fffffu32)), V(0x3f800000u32), 1u32)) { panic("algebraic_div #754") }
    if !(V(0x7f7fffffu32).algebraic_rem(V(0x7f7fffffu32)).to_bits() == 0x0u32) { panic("algebraic_rem #755") }
    if !(V(0x3f800000u32).min(V(0x7fc00000u32)).to_bits() == 0x3f800000u32) { panic("min #756") }
    if !(V(0x3f800000u32).max(V(0x7fc00000u32)).to_bits() == 0x3f800000u32) { panic("max #757") }
    if !(V(0x3f800000u32).total_cmp(V(0x7fc00000u32)) == Ordering.Less) { panic("total_cmp #758") }
    if !(V(0x7fc00000u32).copysign(V(0x3f800000u32)).is_nan()) { panic("copysign #759") }
    if !(V(0x7fc00000u32).min(V(0x3f800000u32)).to_bits() == 0x3f800000u32) { panic("min #760") }
    if !(V(0x7fc00000u32).max(V(0x3f800000u32)).to_bits() == 0x3f800000u32) { panic("max #761") }
    if !(V(0x7fc00000u32).total_cmp(V(0x3f800000u32)) == Ordering.Greater) { panic("total_cmp #762") }
    if !(V(0x7f800000u32).copysign(V(0x3f800000u32)).to_bits() == 0x7f800000u32) { panic("copysign #763") }
    if !(V(0x7f800000u32).min(V(0x3f800000u32)).to_bits() == 0x3f800000u32) { panic("min #764") }
    if !(V(0x7f800000u32).max(V(0x3f800000u32)).to_bits() == 0x7f800000u32) { panic("max #765") }
    if !(V(0x7f800000u32).total_cmp(V(0x3f800000u32)) == Ordering.Greater) { panic("total_cmp #766") }
    if !(V(0x40e00000u32).copysign(V(0x40400000u32)).to_bits() == 0x40e00000u32) { panic("copysign #767") }
    if !(V(0x40e00000u32).min(V(0x40400000u32)).to_bits() == 0x40400000u32) { panic("min #768") }
    if !(V(0x40e00000u32).max(V(0x40400000u32)).to_bits() == 0x40e00000u32) { panic("max #769") }
    if !(V(0x40e00000u32).total_cmp(V(0x40400000u32)) == Ordering.Greater) { panic("total_cmp #770") }
    if !(V(0x40e00000u32).rem_euclid(V(0x40400000u32)).to_bits() == 0x3f800000u32) { panic("rem_euclid #771") }
    if !(V(0x40e00000u32).div_euclid(V(0x40400000u32)).to_bits() == 0x40000000u32) { panic("div_euclid #772") }
    if !(V(0x40e00000u32).midpoint(V(0x40400000u32)).to_bits() == 0x40a00000u32) { panic("midpoint #773") }
    if !(near(V(0x40e00000u32).algebraic_add(V(0x40400000u32)), V(0x41200000u32), 1u32)) { panic("algebraic_add #774") }
    if !(near(V(0x40e00000u32).algebraic_sub(V(0x40400000u32)), V(0x40800000u32), 1u32)) { panic("algebraic_sub #775") }
    if !(near(V(0x40e00000u32).algebraic_mul(V(0x40400000u32)), V(0x41a80000u32), 1u32)) { panic("algebraic_mul #776") }
    if !(near(V(0x40e00000u32).algebraic_div(V(0x40400000u32)), V(0x40155555u32), 1u32)) { panic("algebraic_div #777") }
    if !(near(V(0x40e00000u32).algebraic_rem(V(0x40400000u32)), V(0x3f800000u32), 1u32)) { panic("algebraic_rem #778") }
    if !(near(V(0x40e00000u32).hypot(V(0x40400000u32)), V(0x40f3b46au32), 2u32)) { panic("hypot #779") }
    if !(near(V(0x40e00000u32).atan2(V(0x40400000u32)), V(0x3f953c5cu32), 2u32)) { panic("atan2 #780") }
    if !(V(0xc0e00000u32).copysign(V(0x40400000u32)).to_bits() == 0x40e00000u32) { panic("copysign #781") }
    if !(V(0xc0e00000u32).min(V(0x40400000u32)).to_bits() == 0xc0e00000u32) { panic("min #782") }
    if !(V(0xc0e00000u32).max(V(0x40400000u32)).to_bits() == 0x40400000u32) { panic("max #783") }
    if !(V(0xc0e00000u32).total_cmp(V(0x40400000u32)) == Ordering.Less) { panic("total_cmp #784") }
    if !(V(0xc0e00000u32).rem_euclid(V(0x40400000u32)).to_bits() == 0x40000000u32) { panic("rem_euclid #785") }
    if !(V(0xc0e00000u32).div_euclid(V(0x40400000u32)).to_bits() == 0xc0400000u32) { panic("div_euclid #786") }
    if !(V(0xc0e00000u32).midpoint(V(0x40400000u32)).to_bits() == 0xc0000000u32) { panic("midpoint #787") }
    if !(near(V(0xc0e00000u32).algebraic_add(V(0x40400000u32)), V(0xc0800000u32), 1u32)) { panic("algebraic_add #788") }
    if !(near(V(0xc0e00000u32).algebraic_sub(V(0x40400000u32)), V(0xc1200000u32), 1u32)) { panic("algebraic_sub #789") }
    if !(near(V(0xc0e00000u32).algebraic_mul(V(0x40400000u32)), V(0xc1a80000u32), 1u32)) { panic("algebraic_mul #790") }
    if !(near(V(0xc0e00000u32).algebraic_div(V(0x40400000u32)), V(0xc0155555u32), 1u32)) { panic("algebraic_div #791") }
    if !(near(V(0xc0e00000u32).algebraic_rem(V(0x40400000u32)), V(0xbf800000u32), 1u32)) { panic("algebraic_rem #792") }
    if !(near(V(0xc0e00000u32).hypot(V(0x40400000u32)), V(0x40f3b46au32), 2u32)) { panic("hypot #793") }
    if !(near(V(0xc0e00000u32).atan2(V(0x40400000u32)), V(0xbf953c5cu32), 2u32)) { panic("atan2 #794") }
    if !(V(0x40e00000u32).copysign(V(0xc0400000u32)).to_bits() == 0xc0e00000u32) { panic("copysign #795") }
    if !(V(0x40e00000u32).min(V(0xc0400000u32)).to_bits() == 0xc0400000u32) { panic("min #796") }
    if !(V(0x40e00000u32).max(V(0xc0400000u32)).to_bits() == 0x40e00000u32) { panic("max #797") }
    if !(V(0x40e00000u32).total_cmp(V(0xc0400000u32)) == Ordering.Greater) { panic("total_cmp #798") }
    if !(V(0x40e00000u32).rem_euclid(V(0xc0400000u32)).to_bits() == 0x3f800000u32) { panic("rem_euclid #799") }
    if !(V(0x40e00000u32).div_euclid(V(0xc0400000u32)).to_bits() == 0xc0000000u32) { panic("div_euclid #800") }
    if !(V(0x40e00000u32).midpoint(V(0xc0400000u32)).to_bits() == 0x40000000u32) { panic("midpoint #801") }
    if !(near(V(0x40e00000u32).algebraic_add(V(0xc0400000u32)), V(0x40800000u32), 1u32)) { panic("algebraic_add #802") }
    if !(near(V(0x40e00000u32).algebraic_sub(V(0xc0400000u32)), V(0x41200000u32), 1u32)) { panic("algebraic_sub #803") }
    if !(near(V(0x40e00000u32).algebraic_mul(V(0xc0400000u32)), V(0xc1a80000u32), 1u32)) { panic("algebraic_mul #804") }
    if !(near(V(0x40e00000u32).algebraic_div(V(0xc0400000u32)), V(0xc0155555u32), 1u32)) { panic("algebraic_div #805") }
    if !(near(V(0x40e00000u32).algebraic_rem(V(0xc0400000u32)), V(0x3f800000u32), 1u32)) { panic("algebraic_rem #806") }
    if !(near(V(0x40e00000u32).hypot(V(0xc0400000u32)), V(0x40f3b46au32), 2u32)) { panic("hypot #807") }
    if !(near(V(0x40e00000u32).atan2(V(0xc0400000u32)), V(0x3ffce359u32), 2u32)) { panic("atan2 #808") }
    if !(V(0xc0e00000u32).copysign(V(0xc0400000u32)).to_bits() == 0xc0e00000u32) { panic("copysign #809") }
    if !(V(0xc0e00000u32).min(V(0xc0400000u32)).to_bits() == 0xc0e00000u32) { panic("min #810") }
    if !(V(0xc0e00000u32).max(V(0xc0400000u32)).to_bits() == 0xc0400000u32) { panic("max #811") }
    if !(V(0xc0e00000u32).total_cmp(V(0xc0400000u32)) == Ordering.Less) { panic("total_cmp #812") }
    if !(V(0xc0e00000u32).rem_euclid(V(0xc0400000u32)).to_bits() == 0x40000000u32) { panic("rem_euclid #813") }
    if !(V(0xc0e00000u32).div_euclid(V(0xc0400000u32)).to_bits() == 0x40400000u32) { panic("div_euclid #814") }
    if !(V(0xc0e00000u32).midpoint(V(0xc0400000u32)).to_bits() == 0xc0a00000u32) { panic("midpoint #815") }
    if !(near(V(0xc0e00000u32).algebraic_add(V(0xc0400000u32)), V(0xc1200000u32), 1u32)) { panic("algebraic_add #816") }
    if !(near(V(0xc0e00000u32).algebraic_sub(V(0xc0400000u32)), V(0xc0800000u32), 1u32)) { panic("algebraic_sub #817") }
    if !(near(V(0xc0e00000u32).algebraic_mul(V(0xc0400000u32)), V(0x41a80000u32), 1u32)) { panic("algebraic_mul #818") }
    if !(near(V(0xc0e00000u32).algebraic_div(V(0xc0400000u32)), V(0x40155555u32), 1u32)) { panic("algebraic_div #819") }
    if !(near(V(0xc0e00000u32).algebraic_rem(V(0xc0400000u32)), V(0xbf800000u32), 1u32)) { panic("algebraic_rem #820") }
    if !(near(V(0xc0e00000u32).hypot(V(0xc0400000u32)), V(0x40f3b46au32), 2u32)) { panic("hypot #821") }
    if !(near(V(0xc0e00000u32).atan2(V(0xc0400000u32)), V(0xbffce359u32), 2u32)) { panic("atan2 #822") }
    if !(V(0x3dcccccdu32).copysign(V(0x40400000u32)).to_bits() == 0x3dcccccdu32) { panic("copysign #823") }
    if !(V(0x3dcccccdu32).min(V(0x40400000u32)).to_bits() == 0x3dcccccdu32) { panic("min #824") }
    if !(V(0x3dcccccdu32).max(V(0x40400000u32)).to_bits() == 0x40400000u32) { panic("max #825") }
    if !(V(0x3dcccccdu32).total_cmp(V(0x40400000u32)) == Ordering.Less) { panic("total_cmp #826") }
    if !(V(0x3dcccccdu32).rem_euclid(V(0x40400000u32)).to_bits() == 0x3dcccccdu32) { panic("rem_euclid #827") }
    if !(V(0x3dcccccdu32).div_euclid(V(0x40400000u32)).to_bits() == 0x0u32) { panic("div_euclid #828") }
    if !(V(0x3dcccccdu32).midpoint(V(0x40400000u32)).to_bits() == 0x3fc66666u32) { panic("midpoint #829") }
    if !(near(V(0x3dcccccdu32).algebraic_add(V(0x40400000u32)), V(0x40466666u32), 1u32)) { panic("algebraic_add #830") }
    if !(near(V(0x3dcccccdu32).algebraic_sub(V(0x40400000u32)), V(0xc039999au32), 1u32)) { panic("algebraic_sub #831") }
    if !(near(V(0x3dcccccdu32).algebraic_mul(V(0x40400000u32)), V(0x3e99999au32), 1u32)) { panic("algebraic_mul #832") }
    if !(near(V(0x3dcccccdu32).algebraic_div(V(0x40400000u32)), V(0x3d088889u32), 1u32)) { panic("algebraic_div #833") }
    if !(near(V(0x3dcccccdu32).algebraic_rem(V(0x40400000u32)), V(0x3dcccccdu32), 1u32)) { panic("algebraic_rem #834") }
    if !(near(V(0x3dcccccdu32).hypot(V(0x40400000u32)), V(0x40401b4du32), 2u32)) { panic("hypot #835") }
    if !(near(V(0x3dcccccdu32).atan2(V(0x40400000u32)), V(0x3d087b99u32), 2u32)) { panic("atan2 #836") }
    if !(V(0x1u32).copysign(V(0x800000u32)).to_bits() == 0x1u32) { panic("copysign #837") }
    if !(V(0x1u32).min(V(0x800000u32)).to_bits() == 0x1u32) { panic("min #838") }
    if !(V(0x1u32).max(V(0x800000u32)).to_bits() == 0x800000u32) { panic("max #839") }
    if !(V(0x1u32).total_cmp(V(0x800000u32)) == Ordering.Less) { panic("total_cmp #840") }
}

fn group7() {
    if !(V(0x1u32).rem_euclid(V(0x800000u32)).to_bits() == 0x1u32) { panic("rem_euclid #841") }
    if !(V(0x1u32).div_euclid(V(0x800000u32)).to_bits() == 0x0u32) { panic("div_euclid #842") }
    if !(V(0x1u32).midpoint(V(0x800000u32)).to_bits() == 0x400000u32) { panic("midpoint #843") }
    if !(near(V(0x1u32).algebraic_add(V(0x800000u32)), V(0x800001u32), 1u32)) { panic("algebraic_add #844") }
    if !(near(V(0x1u32).algebraic_sub(V(0x800000u32)), V(0x807fffffu32), 1u32)) { panic("algebraic_sub #845") }
    if !(V(0x1u32).algebraic_mul(V(0x800000u32)).to_bits() == 0x0u32) { panic("algebraic_mul #846") }
    if !(near(V(0x1u32).algebraic_div(V(0x800000u32)), V(0x34000000u32), 1u32)) { panic("algebraic_div #847") }
    if !(near(V(0x1u32).algebraic_rem(V(0x800000u32)), V(0x1u32), 1u32)) { panic("algebraic_rem #848") }
    if !(near(V(0x1u32).hypot(V(0x800000u32)), V(0x800000u32), 2u32)) { panic("hypot #849") }
    if !(near(V(0x1u32).atan2(V(0x800000u32)), V(0x34000000u32), 2u32)) { panic("atan2 #850") }
    if !(V(0x40a00000u32).clamp(V(0x3f800000u32), V(0x40400000u32)).to_bits() == 0x40400000u32) { panic("clamp #851") }
    if !(V(0xc0a00000u32).clamp(V(0x3f800000u32), V(0x40400000u32)).to_bits() == 0x3f800000u32) { panic("clamp #852") }
    if !(V(0x40000000u32).clamp(V(0x3f800000u32), V(0x40400000u32)).to_bits() == 0x40000000u32) { panic("clamp #853") }
    if !(V(0x7fc00000u32).clamp(V(0x3f800000u32), V(0x40400000u32)).is_nan()) { panic("clamp #854") }
    if !(V(0x80000000u32).clamp(V(0x0u32), V(0x3f800000u32)).to_bits() == 0x80000000u32) { panic("clamp #855") }
    if !(V(0x40000000u32).mul_add(V(0x40400000u32), V(0x40800000u32)).to_bits() == 0x41200000u32) { panic("mul_add #856") }
    if !(V(0xbfc00000u32).mul_add(V(0x40000000u32), V(0x3e800000u32)).to_bits() == 0xc0300000u32) { panic("mul_add #857") }
    if !(V(0x3dcccccdu32).mul_add(V(0x41200000u32), V(0xbf800000u32)).to_bits() == 0x32800000u32) { panic("mul_add #858") }
    if !(V(0x7f7fffffu32).mul_add(V(0x40000000u32), V(0xff7fffffu32)).to_bits() == 0x7f7fffffu32) { panic("mul_add #859") }
    if !(near(V(0xc1200000u32).sin(), V(0x3f0b44f8u32), 2u32)) { panic("sin #860") }
    if !(near(V(0xbfc00000u32).sin(), V(0xbf7f5bd5u32), 2u32)) { panic("sin #861") }
    if !(near(V(0xbdcccccdu32).sin(), V(0xbdcc7577u32), 2u32)) { panic("sin #862") }
    if !(V(0x0u32).sin().to_bits() == 0x0u32) { panic("sin #863") }
    if !(near(V(0x3f333333u32).sin(), V(0x3f24eb73u32), 2u32)) { panic("sin #864") }
    if !(near(V(0x40000000u32).sin(), V(0x3f68c7b7u32), 2u32)) { panic("sin #865") }
    if !(near(V(0x41f00000u32).sin(), V(0xbf7cefa4u32), 2u32)) { panic("sin #866") }
    if !(near(V(0xc1200000u32).cos(), V(0xbf56cd64u32), 2u32)) { panic("cos #867") }
    if !(near(V(0xbfc00000u32).cos(), V(0x3d90deaau32), 2u32)) { panic("cos #868") }
    if !(near(V(0xbdcccccdu32).cos(), V(0x3f7eb898u32), 2u32)) { panic("cos #869") }
    if !(near(V(0x0u32).cos(), V(0x3f800000u32), 2u32)) { panic("cos #870") }
    if !(near(V(0x3f333333u32).cos(), V(0x3f43ccb3u32), 2u32)) { panic("cos #871") }
    if !(near(V(0x40000000u32).cos(), V(0xbed51133u32), 2u32)) { panic("cos #872") }
    if !(near(V(0x41f00000u32).cos(), V(0x3e1df418u32), 2u32)) { panic("cos #873") }
    if !(near(V(0xc1200000u32).tan(), V(0xbf25fafau32), 4u32)) { panic("tan #874") }
    if !(near(V(0xbfc00000u32).tan(), V(0xc1619f6bu32), 4u32)) { panic("tan #875") }
    if !(near(V(0xbdcccccdu32).tan(), V(0xbdcd7c44u32), 4u32)) { panic("tan #876") }
    if !(V(0x0u32).tan().to_bits() == 0x0u32) { panic("tan #877") }
    if !(near(V(0x3f333333u32).tan(), V(0x3f57a036u32), 4u32)) { panic("tan #878") }
    if !(near(V(0x40000000u32).tan(), V(0xc00bd7b1u32), 4u32)) { panic("tan #879") }
    if !(near(V(0x41f00000u32).tan(), V(0xc0ccf879u32), 4u32)) { panic("tan #880") }
    if !(near(V(0xbf666666u32).asin(), V(0xbf8f549bu32), 2u32)) { panic("asin #881") }
    if !(near(V(0xbf000000u32).asin(), V(0xbf060a92u32), 2u32)) { panic("asin #882") }
    if !(V(0x0u32).asin().to_bits() == 0x0u32) { panic("asin #883") }
    if !(near(V(0x3e99999au32).asin(), V(0x3e9c00adu32), 2u32)) { panic("asin #884") }
    if !(near(V(0x3f400000u32).asin(), V(0x3f591a99u32), 2u32)) { panic("asin #885") }
    if !(near(V(0xbf666666u32).acos(), V(0x402c323bu32), 2u32)) { panic("acos #886") }
    if !(near(V(0xbf000000u32).acos(), V(0x40060a92u32), 2u32)) { panic("acos #887") }
    if !(near(V(0x0u32).acos(), V(0x3fc90fdbu32), 2u32)) { panic("acos #888") }
    if !(near(V(0x3e99999au32).acos(), V(0x3fa20fafu32), 2u32)) { panic("acos #889") }
    if !(near(V(0x3f400000u32).acos(), V(0x3f39051du32), 2u32)) { panic("acos #890") }
    if !(near(V(0xc1200000u32).atan(), V(0xbfbc4de9u32), 2u32)) { panic("atan #891") }
    if !(near(V(0xbfc00000u32).atan(), V(0xbf7b985fu32), 2u32)) { panic("atan #892") }
    if !(near(V(0xbdcccccdu32).atan(), V(0xbdcc1f14u32), 2u32)) { panic("atan #893") }
    if !(V(0x0u32).atan().to_bits() == 0x0u32) { panic("atan #894") }
    if !(near(V(0x3f333333u32).atan(), V(0x3f1c5889u32), 2u32)) { panic("atan #895") }
    if !(near(V(0x40000000u32).atan(), V(0x3f8db70du32), 2u32)) { panic("atan #896") }
    if !(near(V(0x41f00000u32).atan(), V(0x3fc4cbfeu32), 2u32)) { panic("atan #897") }
    if !(near(V(0xc1200000u32).sinh(), V(0xc62c14eeu32), 2u32)) { panic("sinh #898") }
    if !(near(V(0xbfc00000u32).sinh(), V(0xc008461du32), 2u32)) { panic("sinh #899") }
    if !(near(V(0xbdcccccdu32).sinh(), V(0xbdcd243au32), 2u32)) { panic("sinh #900") }
    if !(V(0x0u32).sinh().to_bits() == 0x0u32) { panic("sinh #901") }
    if !(near(V(0x3f333333u32).sinh(), V(0x3f42328au32), 2u32)) { panic("sinh #902") }
    if !(near(V(0x40000000u32).sinh(), V(0x40681e7bu32), 2u32)) { panic("sinh #903") }
    if !(near(V(0x41f00000u32).sinh(), V(0x549b8238u32), 2u32)) { panic("sinh #904") }
    if !(near(V(0xc1200000u32).cosh(), V(0x462c14efu32), 2u32)) { panic("cosh #905") }
    if !(near(V(0xbfc00000u32).cosh(), V(0x40168de1u32), 2u32)) { panic("cosh #906") }
    if !(near(V(0xbdcccccdu32).cosh(), V(0x3f80a3fau32), 2u32)) { panic("cosh #907") }
    if !(near(V(0x0u32).cosh(), V(0x3f800000u32), 2u32)) { panic("cosh #908") }
    if !(near(V(0x3f333333u32).cosh(), V(0x3fa0a961u32), 2u32)) { panic("cosh #909") }
    if !(near(V(0x40000000u32).cosh(), V(0x4070c7d0u32), 2u32)) { panic("cosh #910") }
    if !(near(V(0x41f00000u32).cosh(), V(0x549b8238u32), 2u32)) { panic("cosh #911") }
    if !(near(V(0xc1200000u32).tanh(), V(0xbf800000u32), 2u32)) { panic("tanh #912") }
    if !(near(V(0xbfc00000u32).tanh(), V(0xbf67b7ccu32), 2u32)) { panic("tanh #913") }
    if !(near(V(0xbdcccccdu32).tanh(), V(0xbdcc1ebcu32), 2u32)) { panic("tanh #914") }
    if !(V(0x0u32).tanh().to_bits() == 0x0u32) { panic("tanh #915") }
    if !(near(V(0x3f333333u32).tanh(), V(0x3f1ab7d9u32), 2u32)) { panic("tanh #916") }
    if !(near(V(0x40000000u32).tanh(), V(0x3f76ca83u32), 2u32)) { panic("tanh #917") }
    if !(near(V(0x41f00000u32).tanh(), V(0x3f800000u32), 2u32)) { panic("tanh #918") }
    if !(near(V(0xc1200000u32).asinh(), V(0xc03fe2e3u32), 2u32)) { panic("asinh #919") }
    if !(near(V(0xbfc00000u32).asinh(), V(0xbf98ee00u32), 2u32)) { panic("asinh #920") }
    if !(near(V(0xbdcccccdu32).asinh(), V(0xbdcc75cfu32), 2u32)) { panic("asinh #921") }
    if !(V(0x0u32).asinh().to_bits() == 0x0u32) { panic("asinh #922") }
    if !(near(V(0x3f333333u32).asinh(), V(0x3f271528u32), 2u32)) { panic("asinh #923") }
    if !(near(V(0x40000000u32).asinh(), V(0x3fb8c90cu32), 2u32)) { panic("asinh #924") }
    if !(near(V(0x41f00000u32).asinh(), V(0x40830725u32), 2u32)) { panic("asinh #925") }
    if !(near(V(0x3fa00000u32).acosh(), V(0x3f317218u32), 2u32)) { panic("acosh #926") }
    if !(near(V(0x3fc00000u32).acosh(), V(0x3f766165u32), 2u32)) { panic("acosh #927") }
    if !(near(V(0x40000000u32).acosh(), V(0x3fa89214u32), 2u32)) { panic("acosh #928") }
    if !(near(V(0x40200000u32).acosh(), V(0x3fc88ce1u32), 2u32)) { panic("acosh #929") }
    if !(near(V(0x40400000u32).acosh(), V(0x3fe1a1b3u32), 2u32)) { panic("acosh #930") }
    if !(near(V(0x41300000u32).acosh(), V(0x4045b1afu32), 2u32)) { panic("acosh #931") }
    if !(near(V(0x42f8e979u32).acosh(), V(0x40b08bf2u32), 2u32)) { panic("acosh #932") }
    if !(near(V(0x3f800054u32).acosh(), V(0x3b92a46eu32), 2u32)) { panic("acosh #933") }
    if !(near(V(0xbf666666u32).atanh(), V(0xbfbc71afu32), 2u32)) { panic("atanh #934") }
    if !(near(V(0xbf000000u32).atanh(), V(0xbf0c9f54u32), 2u32)) { panic("atanh #935") }
    if !(V(0x0u32).atanh().to_bits() == 0x0u32) { panic("atanh #936") }
    if !(near(V(0x3e99999au32).atanh(), V(0x3e9e795bu32), 2u32)) { panic("atanh #937") }
    if !(near(V(0x3f400000u32).atanh(), V(0x3f791395u32), 2u32)) { panic("atanh #938") }
    if !(near(V(0xc1200000u32).exp(), V(0x383e6bceu32), 2u32)) { panic("exp #939") }
    if !(near(V(0xbfc00000u32).exp(), V(0x3e647c3cu32), 2u32)) { panic("exp #940") }
    if !(near(V(0xbdcccccdu32).exp(), V(0x3f67a36du32), 2u32)) { panic("exp #941") }
    if !(near(V(0x0u32).exp(), V(0x3f800000u32), 2u32)) { panic("exp #942") }
    if !(near(V(0x3f333333u32).exp(), V(0x4000e153u32), 2u32)) { panic("exp #943") }
    if !(near(V(0x40000000u32).exp(), V(0x40ec7326u32), 2u32)) { panic("exp #944") }
    if !(near(V(0x41f00000u32).exp(), V(0x551b8238u32), 2u32)) { panic("exp #945") }
    if !(near(V(0xc1200000u32).exp2(), V(0x3a800000u32), 4u32)) { panic("exp2 #946") }
    if !(near(V(0xbfc00000u32).exp2(), V(0x3eb504f3u32), 4u32)) { panic("exp2 #947") }
    if !(near(V(0xbdcccccdu32).exp2(), V(0x3f6edb40u32), 4u32)) { panic("exp2 #948") }
    if !(near(V(0x0u32).exp2(), V(0x3f800000u32), 4u32)) { panic("exp2 #949") }
    if !(near(V(0x3f333333u32).exp2(), V(0x3fcfefc6u32), 4u32)) { panic("exp2 #950") }
    if !(near(V(0x40000000u32).exp2(), V(0x40800000u32), 4u32)) { panic("exp2 #951") }
    if !(near(V(0x41f00000u32).exp2(), V(0x4e800000u32), 4u32)) { panic("exp2 #952") }
    if !(near(V(0xc1200000u32).exp_m1(), V(0xbf7ffd06u32), 2u32)) { panic("exp_m1 #953") }
    if !(near(V(0xbfc00000u32).exp_m1(), V(0xbf46e0f1u32), 2u32)) { panic("exp_m1 #954") }
    if !(near(V(0xbdcccccdu32).exp_m1(), V(0xbdc2e49au32), 2u32)) { panic("exp_m1 #955") }
    if !(V(0x0u32).exp_m1().to_bits() == 0x0u32) { panic("exp_m1 #956") }
    if !(near(V(0x3f333333u32).exp_m1(), V(0x3f81c2a6u32), 2u32)) { panic("exp_m1 #957") }
    if !(near(V(0x40000000u32).exp_m1(), V(0x40cc7326u32), 2u32)) { panic("exp_m1 #958") }
    if !(near(V(0x41f00000u32).exp_m1(), V(0x551b8238u32), 2u32)) { panic("exp_m1 #959") }
    if !(near(V(0x3e800000u32).ln(), V(0xbfb17218u32), 2u32)) { panic("ln #960") }
}

fn group8() {
    if !(near(V(0x3f000000u32).ln(), V(0xbf317218u32), 2u32)) { panic("ln #961") }
    if !(V(0x3f800000u32).ln().to_bits() == 0x0u32) { panic("ln #962") }
    if !(near(V(0x3fc00000u32).ln(), V(0x3ecf991fu32), 2u32)) { panic("ln #963") }
    if !(near(V(0x40000000u32).ln(), V(0x3f317218u32), 2u32)) { panic("ln #964") }
    if !(near(V(0x41200000u32).ln(), V(0x40135d8eu32), 2u32)) { panic("ln #965") }
    if !(near(V(0x42f6e979u32).ln(), V(0x409a1bbau32), 2u32)) { panic("ln #966") }
    if !(near(V(0x3727c5acu32).ln(), V(0xc13834f1u32), 2u32)) { panic("ln #967") }
    if !(near(V(0x3e800000u32).ln_1p(), V(0x3e647fbeu32), 2u32)) { panic("ln_1p #968") }
    if !(near(V(0x3f000000u32).ln_1p(), V(0x3ecf991fu32), 2u32)) { panic("ln_1p #969") }
    if !(near(V(0x3f800000u32).ln_1p(), V(0x3f317218u32), 2u32)) { panic("ln_1p #970") }
    if !(near(V(0x3fc00000u32).ln_1p(), V(0x3f6a9208u32), 2u32)) { panic("ln_1p #971") }
    if !(near(V(0x40000000u32).ln_1p(), V(0x3f8c9f54u32), 2u32)) { panic("ln_1p #972") }
    if !(near(V(0x41200000u32).ln_1p(), V(0x4019771eu32), 2u32)) { panic("ln_1p #973") }
    if !(near(V(0x42f6e979u32).ln_1p(), V(0x409a5dd1u32), 2u32)) { panic("ln_1p #974") }
    if !(near(V(0x3727c5acu32).ln_1p(), V(0x3727c575u32), 2u32)) { panic("ln_1p #975") }
    if !(near(V(0xbf666666u32).ln_1p(), V(0xc0135d8du32), 2u32)) { panic("ln_1p #976") }
    if !(near(V(0xbf000000u32).ln_1p(), V(0xbf317218u32), 2u32)) { panic("ln_1p #977") }
    if !(V(0x0u32).ln_1p().to_bits() == 0x0u32) { panic("ln_1p #978") }
    if !(near(V(0x3e99999au32).ln_1p(), V(0x3e86549cu32), 2u32)) { panic("ln_1p #979") }
    if !(near(V(0x3f400000u32).ln_1p(), V(0x3f0f42fbu32), 2u32)) { panic("ln_1p #980") }
    if !(near(V(0x3e800000u32).log2(), V(0xc0000000u32), 2u32)) { panic("log2 #981") }
    if !(near(V(0x3f000000u32).log2(), V(0xbf800000u32), 2u32)) { panic("log2 #982") }
    if !(V(0x3f800000u32).log2().to_bits() == 0x0u32) { panic("log2 #983") }
    if !(near(V(0x3fc00000u32).log2(), V(0x3f15c01au32), 2u32)) { panic("log2 #984") }
    if !(near(V(0x40000000u32).log2(), V(0x3f800000u32), 2u32)) { panic("log2 #985") }
    if !(near(V(0x41200000u32).log2(), V(0x40549a78u32), 2u32)) { panic("log2 #986") }
    if !(near(V(0x42f6e979u32).log2(), V(0x40de54d0u32), 2u32)) { panic("log2 #987") }
    if !(near(V(0x3727c5acu32).log2(), V(0xc184e08bu32), 2u32)) { panic("log2 #988") }
    if !(near(V(0x3e800000u32).log10(), V(0xbf1a209bu32), 2u32)) { panic("log10 #989") }
    if !(near(V(0x3f000000u32).log10(), V(0xbe9a209bu32), 2u32)) { panic("log10 #990") }
    if !(V(0x3f800000u32).log10().to_bits() == 0x0u32) { panic("log10 #991") }
    if !(near(V(0x3fc00000u32).log10(), V(0x3e345144u32), 2u32)) { panic("log10 #992") }
    if !(near(V(0x40000000u32).log10(), V(0x3e9a209bu32), 2u32)) { panic("log10 #993") }
    if !(near(V(0x41200000u32).log10(), V(0x3f800000u32), 2u32)) { panic("log10 #994") }
    if !(near(V(0x42f6e979u32).log10(), V(0x4005db56u32), 2u32)) { panic("log10 #995") }
    if !(near(V(0x3727c5acu32).log10(), V(0xc0a00000u32), 2u32)) { panic("log10 #996") }
    if !(near(V(0xc1200000u32).cbrt(), V(0xc009e242u32), 4u32)) { panic("cbrt #997") }
    if !(near(V(0xbfc00000u32).cbrt(), V(0xbf9285ffu32), 4u32)) { panic("cbrt #998") }
    if !(near(V(0xbdcccccdu32).cbrt(), V(0xbeeda63cu32), 4u32)) { panic("cbrt #999") }
    if !(V(0x0u32).cbrt().to_bits() == 0x0u32) { panic("cbrt #1000") }
    if !(near(V(0x3f333333u32).cbrt(), V(0x3f634dadu32), 4u32)) { panic("cbrt #1001") }
    if !(near(V(0x40000000u32).cbrt(), V(0x3fa14518u32), 4u32)) { panic("cbrt #1002") }
    if !(near(V(0x41f00000u32).cbrt(), V(0x4046dce6u32), 4u32)) { panic("cbrt #1003") }
    if !(V(0x0u32).ln().to_bits() == 0xff800000u32) { panic("ln #1004") }
    if !(V(0xbf800000u32).ln().is_nan()) { panic("ln #1005") }
    if !(V(0xbf800000u32).sqrt().is_nan()) { panic("sqrt #1006") }
    if !(V(0xff800000u32).exp().to_bits() == 0x0u32) { panic("exp #1007") }
    if !(V(0x7f800000u32).exp().to_bits() == 0x7f800000u32) { panic("exp #1008") }
    if !(V(0x40000000u32).asin().is_nan()) { panic("asin #1009") }
    if !(V(0x3f800000u32).ln().to_bits() == 0x0u32) { panic("ln #1010") }
    if !(V(0x0u32).exp().to_bits() == 0x3f800000u32) { panic("exp #1011") }
    if !(near(V(0xc1200000u32).sin_cos().0, V(0x3f0b44f8u32), 2u32) && near(V(0xc1200000u32).sin_cos().1, V(0xbf56cd64u32), 2u32)) { panic("sin_cos #1012") }
    if !(near(V(0xc1200000u32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1013") }
    if !(near(V(0xc1200000u32).powi(1i32), V(0xc1200000u32), 4u32)) { panic("powi #1014") }
    if !(near(V(0xc1200000u32).powi(2i32), V(0x42c80000u32), 4u32)) { panic("powi #1015") }
    if !(near(V(0xc1200000u32).powi(3i32), V(0xc47a0000u32), 4u32)) { panic("powi #1016") }
    if !(near(V(0xc1200000u32).powi((-2i32)), V(0x3c23d70au32), 4u32)) { panic("powi #1017") }
    if !(near(V(0xc1200000u32).to_degrees(), V(0xc40f3d4du32), 1u32)) { panic("to_degrees #1018") }
    if !(near(V(0xc1200000u32).to_radians(), V(0xbe32b8c2u32), 1u32)) { panic("to_radians #1019") }
    if !(near(V(0xbfc00000u32).sin_cos().0, V(0xbf7f5bd5u32), 2u32) && near(V(0xbfc00000u32).sin_cos().1, V(0x3d90deaau32), 2u32)) { panic("sin_cos #1020") }
    if !(near(V(0xbfc00000u32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1021") }
    if !(near(V(0xbfc00000u32).powi(1i32), V(0xbfc00000u32), 4u32)) { panic("powi #1022") }
    if !(near(V(0xbfc00000u32).powi(2i32), V(0x40100000u32), 4u32)) { panic("powi #1023") }
    if !(near(V(0xbfc00000u32).powi(3i32), V(0xc0580000u32), 4u32)) { panic("powi #1024") }
    if !(near(V(0xbfc00000u32).powi((-2i32)), V(0x3ee38e39u32), 4u32)) { panic("powi #1025") }
    if !(near(V(0xbfc00000u32).to_degrees(), V(0xc2abe329u32), 1u32)) { panic("to_degrees #1026") }
    if !(near(V(0xbfc00000u32).to_radians(), V(0xbcd67750u32), 1u32)) { panic("to_radians #1027") }
    if !(near(V(0xbdcccccdu32).sin_cos().0, V(0xbdcc7577u32), 2u32) && near(V(0xbdcccccdu32).sin_cos().1, V(0x3f7eb898u32), 2u32)) { panic("sin_cos #1028") }
    if !(near(V(0xbdcccccdu32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1029") }
    if !(near(V(0xbdcccccdu32).powi(1i32), V(0xbdcccccdu32), 4u32)) { panic("powi #1030") }
    if !(near(V(0xbdcccccdu32).powi(2i32), V(0x3c23d70bu32), 4u32)) { panic("powi #1031") }
    if !(near(V(0xbdcccccdu32).powi(3i32), V(0xba83126fu32), 4u32)) { panic("powi #1032") }
    if !(near(V(0xbdcccccdu32).powi((-2i32)), V(0x42c80000u32), 4u32)) { panic("powi #1033") }
    if !(near(V(0xbdcccccdu32).to_degrees(), V(0xc0b758b4u32), 1u32)) { panic("to_degrees #1034") }
    if !(near(V(0xbdcccccdu32).to_radians(), V(0xbae4c388u32), 1u32)) { panic("to_radians #1035") }
    if !(near(V(0x0u32).sin_cos().0, V(0x0u32), 2u32) && near(V(0x0u32).sin_cos().1, V(0x3f800000u32), 2u32)) { panic("sin_cos #1036") }
    if !(near(V(0x0u32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1037") }
    if !(V(0x0u32).powi(1i32).to_bits() == 0x0u32) { panic("powi #1038") }
    if !(V(0x0u32).powi(2i32).to_bits() == 0x0u32) { panic("powi #1039") }
    if !(V(0x0u32).powi(3i32).to_bits() == 0x0u32) { panic("powi #1040") }
    if !(V(0x0u32).powi((-2i32)).to_bits() == 0x7f800000u32) { panic("powi #1041") }
    if !(V(0x0u32).to_degrees().to_bits() == 0x0u32) { panic("to_degrees #1042") }
    if !(V(0x0u32).to_radians().to_bits() == 0x0u32) { panic("to_radians #1043") }
    if !(near(V(0x3f333333u32).sin_cos().0, V(0x3f24eb73u32), 2u32) && near(V(0x3f333333u32).sin_cos().1, V(0x3f43ccb3u32), 2u32)) { panic("sin_cos #1044") }
    if !(near(V(0x3f333333u32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1045") }
    if !(near(V(0x3f333333u32).powi(1i32), V(0x3f333333u32), 4u32)) { panic("powi #1046") }
    if !(near(V(0x3f333333u32).powi(2i32), V(0x3efae147u32), 4u32)) { panic("powi #1047") }
    if !(near(V(0x3f333333u32).powi(3i32), V(0x3eaf9db2u32), 4u32)) { panic("powi #1048") }
    if !(near(V(0x3f333333u32).powi((-2i32)), V(0x40029cbcu32), 4u32)) { panic("powi #1049") }
    if !(near(V(0x3f333333u32).to_degrees(), V(0x42206d9du32), 1u32)) { panic("to_degrees #1050") }
    if !(near(V(0x3f333333u32).to_radians(), V(0x3c482b17u32), 1u32)) { panic("to_radians #1051") }
    if !(near(V(0x40000000u32).sin_cos().0, V(0x3f68c7b7u32), 2u32) && near(V(0x40000000u32).sin_cos().1, V(0xbed51133u32), 2u32)) { panic("sin_cos #1052") }
    if !(near(V(0x40000000u32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1053") }
    if !(near(V(0x40000000u32).powi(1i32), V(0x40000000u32), 4u32)) { panic("powi #1054") }
    if !(near(V(0x40000000u32).powi(2i32), V(0x40800000u32), 4u32)) { panic("powi #1055") }
    if !(near(V(0x40000000u32).powi(3i32), V(0x41000000u32), 4u32)) { panic("powi #1056") }
    if !(near(V(0x40000000u32).powi((-2i32)), V(0x3e800000u32), 4u32)) { panic("powi #1057") }
    if !(near(V(0x40000000u32).to_degrees(), V(0x42e52ee1u32), 1u32)) { panic("to_degrees #1058") }
    if !(near(V(0x40000000u32).to_radians(), V(0x3d0efa35u32), 1u32)) { panic("to_radians #1059") }
    if !(near(V(0x41f00000u32).sin_cos().0, V(0xbf7cefa4u32), 2u32) && near(V(0x41f00000u32).sin_cos().1, V(0x3e1df418u32), 2u32)) { panic("sin_cos #1060") }
    if !(near(V(0x41f00000u32).powi(0i32), V(0x3f800000u32), 4u32)) { panic("powi #1061") }
    if !(near(V(0x41f00000u32).powi(1i32), V(0x41f00000u32), 4u32)) { panic("powi #1062") }
    if !(near(V(0x41f00000u32).powi(2i32), V(0x44610000u32), 4u32)) { panic("powi #1063") }
    if !(near(V(0x41f00000u32).powi(3i32), V(0x46d2f000u32), 4u32)) { panic("powi #1064") }
    if !(near(V(0x41f00000u32).powi((-2i32)), V(0x3a91a2b4u32), 4u32)) { panic("powi #1065") }
    if !(near(V(0x41f00000u32).to_degrees(), V(0x44d6dbf3u32), 1u32)) { panic("to_degrees #1066") }
    if !(near(V(0x41f00000u32).to_radians(), V(0x3f060a92u32), 1u32)) { panic("to_radians #1067") }
    if !(near(V(0x3e800000u32).powf(V(0x3f000000u32)), V(0x3f000000u32), 2u32)) { panic("powf #1068") }
    if !(near(V(0x3e800000u32).powf(V(0x40000000u32)), V(0x3d800000u32), 2u32)) { panic("powf #1069") }
    if !(near(V(0x3e800000u32).powf(V(0xbfc00000u32)), V(0x41000000u32), 2u32)) { panic("powf #1070") }
    if !(near(V(0x3e800000u32).powf(V(0x40400000u32)), V(0x3c800000u32), 2u32)) { panic("powf #1071") }
    if !(near(V(0x3e800000u32).log(V(0x40000000u32)), V(0xc0000000u32), 4u32)) { panic("log #1072") }
    if !(near(V(0x3e800000u32).log(V(0x41200000u32)), V(0xbf1a209bu32), 4u32)) { panic("log #1073") }
    if !(near(V(0x3e800000u32).log(V(0x40600000u32)), V(0xbf8da4bau32), 4u32)) { panic("log #1074") }
    if !(near(V(0x3f000000u32).powf(V(0x3f000000u32)), V(0x3f3504f3u32), 2u32)) { panic("powf #1075") }
    if !(near(V(0x3f000000u32).powf(V(0x40000000u32)), V(0x3e800000u32), 2u32)) { panic("powf #1076") }
    if !(near(V(0x3f000000u32).powf(V(0xbfc00000u32)), V(0x403504f3u32), 2u32)) { panic("powf #1077") }
    if !(near(V(0x3f000000u32).powf(V(0x40400000u32)), V(0x3e000000u32), 2u32)) { panic("powf #1078") }
    if !(near(V(0x3f000000u32).log(V(0x40000000u32)), V(0xbf800000u32), 4u32)) { panic("log #1079") }
    if !(near(V(0x3f000000u32).log(V(0x41200000u32)), V(0xbe9a209bu32), 4u32)) { panic("log #1080") }
}

fn group9() {
    if !(near(V(0x3f000000u32).log(V(0x40600000u32)), V(0xbf0da4bau32), 4u32)) { panic("log #1081") }
    if !(near(V(0x3f800000u32).powf(V(0x3f000000u32)), V(0x3f800000u32), 2u32)) { panic("powf #1082") }
    if !(near(V(0x3f800000u32).powf(V(0x40000000u32)), V(0x3f800000u32), 2u32)) { panic("powf #1083") }
    if !(near(V(0x3f800000u32).powf(V(0xbfc00000u32)), V(0x3f800000u32), 2u32)) { panic("powf #1084") }
    if !(near(V(0x3f800000u32).powf(V(0x40400000u32)), V(0x3f800000u32), 2u32)) { panic("powf #1085") }
    if !(V(0x3f800000u32).log(V(0x40000000u32)).to_bits() == 0x0u32) { panic("log #1086") }
    if !(V(0x3f800000u32).log(V(0x41200000u32)).to_bits() == 0x0u32) { panic("log #1087") }
    if !(V(0x3f800000u32).log(V(0x40600000u32)).to_bits() == 0x0u32) { panic("log #1088") }
    if !(near(V(0x3fc00000u32).powf(V(0x3f000000u32)), V(0x3f9cc471u32), 2u32)) { panic("powf #1089") }
    if !(near(V(0x3fc00000u32).powf(V(0x40000000u32)), V(0x40100000u32), 2u32)) { panic("powf #1090") }
    if !(near(V(0x3fc00000u32).powf(V(0xbfc00000u32)), V(0x3f0b5948u32), 2u32)) { panic("powf #1091") }
    if !(near(V(0x3fc00000u32).powf(V(0x40400000u32)), V(0x40580000u32), 2u32)) { panic("powf #1092") }
    if !(near(V(0x3fc00000u32).log(V(0x40000000u32)), V(0x3f15c01au32), 4u32)) { panic("log #1093") }
    if !(near(V(0x3fc00000u32).log(V(0x41200000u32)), V(0x3e345144u32), 4u32)) { panic("log #1094") }
    if !(near(V(0x3fc00000u32).log(V(0x40600000u32)), V(0x3ea5b654u32), 4u32)) { panic("log #1095") }
    if !(near(V(0x40000000u32).powf(V(0x3f000000u32)), V(0x3fb504f3u32), 2u32)) { panic("powf #1096") }
    if !(near(V(0x40000000u32).powf(V(0x40000000u32)), V(0x40800000u32), 2u32)) { panic("powf #1097") }
    if !(near(V(0x40000000u32).powf(V(0xbfc00000u32)), V(0x3eb504f3u32), 2u32)) { panic("powf #1098") }
    if !(near(V(0x40000000u32).powf(V(0x40400000u32)), V(0x41000000u32), 2u32)) { panic("powf #1099") }
    if !(near(V(0x40000000u32).log(V(0x40000000u32)), V(0x3f800000u32), 4u32)) { panic("log #1100") }
    if !(near(V(0x40000000u32).log(V(0x41200000u32)), V(0x3e9a209bu32), 4u32)) { panic("log #1101") }
    if !(near(V(0x40000000u32).log(V(0x40600000u32)), V(0x3f0da4bau32), 4u32)) { panic("log #1102") }
    if !(near(V(0x41200000u32).powf(V(0x3f000000u32)), V(0x404a62c2u32), 2u32)) { panic("powf #1103") }
    if !(near(V(0x41200000u32).powf(V(0x40000000u32)), V(0x42c80000u32), 2u32)) { panic("powf #1104") }
    if !(near(V(0x41200000u32).powf(V(0xbfc00000u32)), V(0x3d0186e2u32), 2u32)) { panic("powf #1105") }
    if !(near(V(0x41200000u32).powf(V(0x40400000u32)), V(0x447a0000u32), 2u32)) { panic("powf #1106") }
    if !(near(V(0x41200000u32).log(V(0x40000000u32)), V(0x40549a78u32), 4u32)) { panic("log #1107") }
    if !(near(V(0x41200000u32).log(V(0x41200000u32)), V(0x3f800000u32), 4u32)) { panic("log #1108") }
    if !(near(V(0x41200000u32).log(V(0x40600000u32)), V(0x3feb43c3u32), 4u32)) { panic("log #1109") }
    if !(near(V(0x42f6e979u32).powf(V(0x3f000000u32)), V(0x4131c6f7u32), 2u32)) { panic("powf #1110") }
    if !(near(V(0x42f6e979u32).powf(V(0x40000000u32)), V(0x466e2589u32), 2u32)) { panic("powf #1111") }
    if !(near(V(0x42f6e979u32).powf(V(0xbfc00000u32)), V(0x3a3f1ad5u32), 2u32)) { panic("powf #1112") }
    if !(near(V(0x42f6e979u32).powf(V(0x40400000u32)), V(0x49e5b143u32), 2u32)) { panic("powf #1113") }
    if !(near(V(0x42f6e979u32).log(V(0x40000000u32)), V(0x40de54d0u32), 4u32)) { panic("log #1114") }
    if !(near(V(0x42f6e979u32).log(V(0x41200000u32)), V(0x4005db56u32), 4u32)) { panic("log #1115") }
    if !(near(V(0x42f6e979u32).log(V(0x40600000u32)), V(0x4076078cu32), 4u32)) { panic("log #1116") }
    if !(near(V(0x3727c5acu32).powf(V(0x3f000000u32)), V(0x3b4f3e37u32), 2u32)) { panic("powf #1117") }
    if !(near(V(0x3727c5acu32).powf(V(0x40000000u32)), V(0x2edbe6feu32), 2u32)) { panic("powf #1118") }
    if !(near(V(0x3727c5acu32).powf(V(0xbfc00000u32)), V(0x4bf1433du32), 2u32)) { panic("powf #1119") }
    if !(near(V(0x3727c5acu32).powf(V(0x40400000u32)), V(0x26901d7cu32), 2u32)) { panic("powf #1120") }
    if !(near(V(0x3727c5acu32).log(V(0x40000000u32)), V(0xc184e08bu32), 4u32)) { panic("log #1121") }
    if !(near(V(0x3727c5acu32).log(V(0x41200000u32)), V(0xc0a00000u32), 4u32)) { panic("log #1122") }
    if !(near(V(0x3727c5acu32).log(V(0x40600000u32)), V(0xc1130a5au32), 4u32)) { panic("log #1123") }
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
