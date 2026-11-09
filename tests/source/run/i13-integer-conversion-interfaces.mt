// profiles: debug release
// Lossless and range-checked integer conversions at every width.
// Assertions moved unchanged from the combined operator fixture.
import core.num
import core.convert.{From, Into, TryFrom}
import core.panic.panic

fn widen<A, B: From<A>>(take a: A): B { B.(From<A>).from(a) }
fn widen_into<A: Into<B>, B>(take a: A): B { A.(Into<B>).into(a) }
fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(_) => false }
}
fn narrow<A, B: TryFrom<A>>(take a: A): B? {
    match take B.(TryFrom<A>).try_from(a) { success(value) => present(value), failure(_) => none }
}

fn group15() {
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
    group15()
    group16()
    group17()
    group18()
    group19()
    0
}
