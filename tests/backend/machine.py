#!/usr/bin/env python3
"""Execute Mettle/C layout, call, callback, promotion and unwind round trips."""

import argparse
import hashlib
import json
import os
import platform
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import processes
import scheduling


ARM64 = globals().get("TARGET_ARCH", platform.machine()).lower() in ("aarch64", "arm64")
DARWIN_ARM64 = platform.system() == "Darwin" and ARM64
VECTOR = "core.arch.aarch64.int32x4_t" if ARM64 else "core.arch.x86_64.__m128i"
MACHINE_FREESTANDING_SOURCE = ("""
@export_name("mettle_core_count")
unsafe extern "C" fn core_count(input:i32):i32 {
    var answer = input
    asm!(\"""" + ("add {value:w}, {value:w}, #2" if ARM64 else
                   "add {value:e}, 2") +
    """\", value = inout(reg) answer,options(nomem,nostack))
    """ + (
        """
    let vector = core.arch.aarch64.vdupq_n_s32(answer)
    if is_aarch64_feature_detected!("neon") {
        core.arch.aarch64.vgetq_lane_s32(vector,0)
    } else { 0 }
""" if ARM64 else """
    if is_x86_feature_detected!("avx2") {
        let vector = core.arch.x86_64._mm256_set1_epi32(answer)
        let lanes = core.mem.transmute<[i32;8]>(vector)
        lanes[7]
    } else {
        let vector = core.arch.x86_64._mm_set1_epi32(answer)
        let lanes = core.mem.transmute<[i32;4]>(vector)
        lanes[3]
    }
""") + """
}
""")
MACHINE_REJECTIONS = {
    "machine-asm-invalid-instruction-preserves-artifact":
        'fn main() { unsafe { asm!("mettle_invalid_instruction",options(nostack)) }; 0 }',
}


def atomic_operation_matrix(category):
    orderings = ("Relaxed", "Acquire", "Release", "AcqRel", "SeqCst")
    all_orders = ", ".join(
        f"core.sync.atomic.Ordering.{name}" for name in orderings)
    load_orders = ", ".join(
        f"core.sync.atomic.Ordering.{name}"
        for name in ("Relaxed", "Acquire", "SeqCst"))
    store_orders = ", ".join(
        f"core.sync.atomic.Ordering.{name}"
        for name in ("Relaxed", "Release", "SeqCst"))
    valid_pairs = (
        ("Relaxed", "Relaxed"),
        ("Acquire", "Relaxed"), ("Acquire", "Acquire"),
        ("Release", "Relaxed"),
        ("AcqRel", "Relaxed"), ("AcqRel", "Acquire"),
        ("SeqCst", "Relaxed"), ("SeqCst", "Acquire"),
        ("SeqCst", "SeqCst"),
    )
    pair_values = ", ".join(
        "(core.sync.atomic.Ordering.{},core.sync.atomic.Ordering.{})".format(
            success, failure)
        for success, failure in valid_pairs)
    types = (
        ("i8", "AtomicI8", "40i8", "42i8", "41i8", "2i8",
         "12i8", "10i8", "8i8", "-9i8"),
        ("u8", "AtomicU8", "40u8", "42u8", "41u8", "2u8",
         "12u8", "10u8", "8u8", "247u8"),
        ("i16", "AtomicI16", "40i16", "42i16", "41i16", "2i16",
         "12i16", "10i16", "8i16", "-9i16"),
        ("u16", "AtomicU16", "40u16", "42u16", "41u16", "2u16",
         "12u16", "10u16", "8u16", "65527u16"),
        ("i32", "AtomicI32", "40i32", "42i32", "41i32", "2i32",
         "12i32", "10i32", "8i32", "-9i32"),
        ("u32", "AtomicU32", "40u32", "42u32", "41u32", "2u32",
         "12u32", "10u32", "8u32", "4294967287u32"),
        ("i64", "AtomicI64", "40i64", "42i64", "41i64", "2i64",
         "12i64", "10i64", "8i64", "-9i64"),
        ("u64", "AtomicU64", "40u64", "42u64", "41u64", "2u64",
         "12u64", "10u64", "8u64", "18446744073709551607u64"),
        ("isize", "AtomicIsize", "40isize", "42isize", "41isize", "2isize",
         "12isize", "10isize", "8isize", "-9isize"),
        ("usize", "AtomicUsize", "40usize", "42usize", "41usize", "2usize",
         "12usize", "10usize", "8usize", "18446744073709551607usize"),
    )
    sections = []

    def append_cas_helpers(suffix, atomic, zero, one, two):
        prefix = f"check_{suffix}_cas"
        ordering_type = "core.sync.atomic.Ordering"
        for kind, method in (("strong_success", "compare_exchange"),
                             ("strong_failure", "compare_exchange"),
                             ("weak_failure", "compare_exchange_weak")):
            expected = zero
            desired = two
            start = zero if kind == "strong_success" else one
            body = [
                f"fn {prefix}_{kind}(success_order: {ordering_type}, "
                f"failure_order: {ordering_type}): bool {{",
                f"    let value = core.sync.atomic.{atomic}.new({start})",
                f"    match value.{method}({expected},{desired},success_order,"
                "failure_order) {",
            ]
            if kind == "strong_success":
                body.extend((
                    f"        success(old) => old == {zero} && "
                    f"value.load(core.sync.atomic.Ordering.Relaxed) == {two}",
                    "        failure(_) => false",
                ))
            else:
                body.extend((
                    "        success(_) => false",
                    f"        failure(old) => old == {one} && "
                    f"value.load(core.sync.atomic.Ordering.Relaxed) == {one}",
                ))
            body.extend(("    }", "}"))
            sections.append("\n".join(body))
        body = [
            f"fn {prefix}_weak_success(success_order: {ordering_type}, "
            f"failure_order: {ordering_type}): bool {{",
            f"    let value = core.sync.atomic.{atomic}.new({zero})",
            f"    match value.compare_exchange_weak({zero},{two},"
            "success_order,failure_order) {",
            f"        success(old) => old == {zero} && "
            f"value.load(core.sync.atomic.Ordering.Relaxed) == {two}",
            f"        failure(old) => old == {zero} && "
            f"value.load(core.sync.atomic.Ordering.Relaxed) == {zero}",
            "    }",
            "}",
        ]
        sections.append("\n".join(body))

    def append_scalar_matrix(suffix, atomic, zero, forty_two, forty_one,
                             two, twelve, ten, eight, nand_result):
        body = [f"fn check_{suffix}(): bool {{"]
        if category == "basic":
            body.extend((
                f"    for order in [{load_orders}] {{",
                f"        let value = core.sync.atomic.{atomic}.new({forty_two})",
                f"        if value.load(order) != {forty_two} {{ return false }}",
                "    }",
                f"    for order in [{store_orders}] {{",
                f"        let value = core.sync.atomic.{atomic}.new({zero})",
                f"        value.store({forty_two},order)",
                "        if value.load(core.sync.atomic.Ordering.Relaxed) != "
                f"{forty_two} {{ return false }}",
                "    }",
                f"    for order in [{all_orders}] {{",
                f"        let value = core.sync.atomic.{atomic}.new({zero})",
                f"        if value.swap({forty_two},order) != {zero} || "
                f"value.load(core.sync.atomic.Ordering.Relaxed) != {forty_two} "
                "{ return false }",
                "    }",
            ))
        elif category == "fetch":
            body.extend((
                f"    for order in [{all_orders}] {{",
                f"        let added = core.sync.atomic.{atomic}.new({zero})",
                f"        if added.fetch_add({two},order) != {zero} || "
                f"added.load(core.sync.atomic.Ordering.Relaxed) != {forty_two} "
                "{ return false }",
                f"        let subtracted = core.sync.atomic.{atomic}.new({forty_two})",
                f"        if subtracted.fetch_sub({two},order) != {forty_two} || "
                f"subtracted.load(core.sync.atomic.Ordering.Relaxed) != {zero} "
                "{ return false }",
                f"        let anded = core.sync.atomic.{atomic}.new({twelve})",
                f"        if anded.fetch_and({ten},order) != {twelve} || "
                f"anded.load(core.sync.atomic.Ordering.Relaxed) != {eight} "
                "{ return false }",
                f"        let ored = core.sync.atomic.{atomic}.new({eight})",
                f"        if ored.fetch_or(3{suffix},order) != {eight} || "
                f"ored.load(core.sync.atomic.Ordering.Relaxed) != 11{suffix} "
                "{ return false }",
                f"        let xored = core.sync.atomic.{atomic}.new(10{suffix})",
                f"        if xored.fetch_xor(3{suffix},order) != 10{suffix} || "
                f"xored.load(core.sync.atomic.Ordering.Relaxed) != 9{suffix} "
                "{ return false }",
                f"        let nanded = core.sync.atomic.{atomic}.new({twelve})",
                f"        if nanded.fetch_nand({ten},order) != {twelve} || "
                f"nanded.load(core.sync.atomic.Ordering.Relaxed) != {nand_result} "
                "{ return false }",
                f"        let minimum = core.sync.atomic.{atomic}.new({forty_two})",
                f"        if minimum.fetch_min({forty_one},order) != {forty_two} || "
                f"minimum.load(core.sync.atomic.Ordering.Relaxed) != {forty_one} "
                "{ return false }",
                f"        let maximum = core.sync.atomic.{atomic}.new({forty_one})",
                f"        if maximum.fetch_max({forty_two},order) != {forty_one} || "
                f"maximum.load(core.sync.atomic.Ordering.Relaxed) != {forty_two} "
                "{ return false }",
                "    }",
            ))
        else:
            append_cas_helpers(suffix, atomic, zero, forty_one, forty_two)
            prefix = f"check_{suffix}_cas"
            body.extend((
                f"    for (success_order,failure_order) in [{pair_values}] {{",
                f"        if !{prefix}_strong_success(success_order,failure_order) ||",
                f"           !{prefix}_strong_failure(success_order,failure_order) ||",
                f"           !{prefix}_weak_failure(success_order,failure_order) ||",
                f"           !{prefix}_weak_success(success_order,failure_order) "
                "{ return false }",
                "    }",
            ))
        body.extend(("    true", "}"))
        sections.append("\n".join(body))

    for spec in types:
        append_scalar_matrix(*spec)

    if category == "basic":
        sections.extend((
        """fn check_bool_cas(success_order: core.sync.atomic.Ordering,
                           failure_order: core.sync.atomic.Ordering): bool {
    let value = core.sync.atomic.AtomicBool.new(false)
    match value.compare_exchange(false,true,success_order,failure_order) {
        success(old) => !old && value.load(core.sync.atomic.Ordering.Relaxed),
        failure(_) => false
    }
}""",
        """fn check_bool_cas_failure(success_order: core.sync.atomic.Ordering,
                                   failure_order: core.sync.atomic.Ordering): bool {
    let value = core.sync.atomic.AtomicBool.new(true)
    match value.compare_exchange(false,false,success_order,failure_order) {
        success(_) => false,
        failure(old) => old && value.load(core.sync.atomic.Ordering.Relaxed)
    }
}""",
        """fn check_bool_cas_weak_failure(success_order: core.sync.atomic.Ordering,
                                        failure_order: core.sync.atomic.Ordering): bool {
    let value = core.sync.atomic.AtomicBool.new(true)
    match value.compare_exchange_weak(false,false,success_order,failure_order) {
        success(_) => false,
        failure(old) => old && value.load(core.sync.atomic.Ordering.Relaxed)
    }
}""",
        """fn check_bool_cas_weak_success(success_order: core.sync.atomic.Ordering,
                                        failure_order: core.sync.atomic.Ordering): bool {
    let value = core.sync.atomic.AtomicBool.new(false)
    match value.compare_exchange_weak(false,true,success_order,failure_order) {
        success(old) => !old && value.load(core.sync.atomic.Ordering.Relaxed),
        failure(old) => !old && !value.load(core.sync.atomic.Ordering.Relaxed)
    }
}""",
        """fn check_bool(): bool {
    for order in [core.sync.atomic.Ordering.Relaxed,
                  core.sync.atomic.Ordering.Acquire,
                  core.sync.atomic.Ordering.SeqCst] {
        if !core.sync.atomic.AtomicBool.new(true).load(order) { return false }
    }
    for order in [core.sync.atomic.Ordering.Relaxed,
                  core.sync.atomic.Ordering.Release,
                  core.sync.atomic.Ordering.SeqCst] {
        let value = core.sync.atomic.AtomicBool.new(false)
        value.store(true,order)
        if !value.load(core.sync.atomic.Ordering.Relaxed) { return false }
    }
    for order in [""" + all_orders + """] {
        let swapped = core.sync.atomic.AtomicBool.new(false)
        if swapped.swap(true,order) || !swapped.load(core.sync.atomic.Ordering.Relaxed) {
            return false
        }
        let anded = core.sync.atomic.AtomicBool.new(true)
        if !anded.fetch_and(false,order) || anded.load(core.sync.atomic.Ordering.Relaxed) {
            return false
        }
        let ored = core.sync.atomic.AtomicBool.new(false)
        if ored.fetch_or(true,order) || !ored.load(core.sync.atomic.Ordering.Relaxed) {
            return false
        }
        let xored = core.sync.atomic.AtomicBool.new(true)
        if !xored.fetch_xor(true,order) || xored.load(core.sync.atomic.Ordering.Relaxed) {
            return false
        }
        let nanded = core.sync.atomic.AtomicBool.new(true)
        if !nanded.fetch_nand(true,order) || nanded.load(core.sync.atomic.Ordering.Relaxed) {
            return false
        }
    }
    for (success_order,failure_order) in [""" + pair_values + """] {
        if !check_bool_cas(success_order,failure_order) ||
           !check_bool_cas_failure(success_order,failure_order) ||
           !check_bool_cas_weak_failure(success_order,failure_order) ||
           !check_bool_cas_weak_success(success_order,failure_order) {
            return false
        }
    }
    true
}""",
        ))
    pointer = """fn check_pointer_cas(success_order: core.sync.atomic.Ordering,
                            failure_order: core.sync.atomic.Ordering): bool {
    var storage = [1i32,2i32,3i32]
    let first = core.ptr.from_mut(storage[0])
    let second = unsafe { first.add(1) }
    let value = core.sync.atomic.AtomicPtr<i32>.new(first)
    match value.compare_exchange(first,second,success_order,failure_order) {
        success(old) => old == first && value.load(core.sync.atomic.Ordering.Relaxed) == second,
        failure(_) => false
    }
}
fn check_pointer_cas_failure(success_order: core.sync.atomic.Ordering,
                                    failure_order: core.sync.atomic.Ordering): bool {
    var storage = [1i32,2i32,3i32]
    let first = core.ptr.from_mut(storage[0])
    let second = unsafe { first.add(1) }
    let value = core.sync.atomic.AtomicPtr<i32>.new(second)
    match value.compare_exchange(first,first,success_order,failure_order) {
        success(_) => false,
        failure(old) => old == second && value.load(core.sync.atomic.Ordering.Relaxed) == second
    }
}
fn check_pointer_cas_weak_failure(success_order: core.sync.atomic.Ordering,
                                         failure_order: core.sync.atomic.Ordering): bool {
    var storage = [1i32,2i32,3i32]
    let first = core.ptr.from_mut(storage[0])
    let second = unsafe { first.add(1) }
    let value = core.sync.atomic.AtomicPtr<i32>.new(second)
    match value.compare_exchange_weak(first,first,success_order,failure_order) {
        success(_) => false,
        failure(old) => old == second && value.load(core.sync.atomic.Ordering.Relaxed) == second
    }
}
fn check_pointer_cas_weak_success(success_order: core.sync.atomic.Ordering,
                                         failure_order: core.sync.atomic.Ordering): bool {
    var storage = [1i32,2i32,3i32]
    let first = core.ptr.from_mut(storage[0])
    let second = unsafe { first.add(1) }
    let value = core.sync.atomic.AtomicPtr<i32>.new(first)
    match value.compare_exchange_weak(first,second,success_order,failure_order) {
        success(old) => old == first && value.load(core.sync.atomic.Ordering.Relaxed) == second,
        failure(old) => old == first && value.load(core.sync.atomic.Ordering.Relaxed) == first
    }
}
fn check_pointer(): bool {
    for order in [""" + load_orders + """] {
        var storage = [1i32,2i32,3i32]
        let first = core.ptr.from_mut(storage[0])
        if core.sync.atomic.AtomicPtr<i32>.new(first).load(order) != first {
            return false
        }
    }
    for order in [""" + store_orders + """] {
        var storage = [1i32,2i32,3i32]
        let first = core.ptr.from_mut(storage[0])
        let second = unsafe { first.add(1) }
        let value = core.sync.atomic.AtomicPtr<i32>.new(first)
        value.store(second,order)
        if value.load(core.sync.atomic.Ordering.Relaxed) != second { return false }
    }
    for order in [""" + all_orders + """] {
        var storage = [1i32,2i32,3i32]
        let first = core.ptr.from_mut(storage[0])
        let second = unsafe { first.add(1) }
        let swapped = core.sync.atomic.AtomicPtr<i32>.new(first)
        if swapped.swap(second,order) != first ||
           swapped.load(core.sync.atomic.Ordering.Relaxed) != second {
            return false
        }
        let added = core.sync.atomic.AtomicPtr<i32>.new(first)
        if added.fetch_ptr_add(1usize,order) != first ||
           added.load(core.sync.atomic.Ordering.Relaxed) != second {
            return false
        }
        let subtracted = core.sync.atomic.AtomicPtr<i32>.new(second)
        if subtracted.fetch_ptr_sub(1usize,order) != second ||
           subtracted.load(core.sync.atomic.Ordering.Relaxed) != first {
            return false
        }
        let byte_added = core.sync.atomic.AtomicPtr<i32>.new(first)
        if byte_added.fetch_byte_add(core.mem.size_of<i32>(),order) != first ||
           byte_added.load(core.sync.atomic.Ordering.Relaxed) != second {
            return false
        }
        let byte_subtracted = core.sync.atomic.AtomicPtr<i32>.new(second)
        if byte_subtracted.fetch_byte_sub(core.mem.size_of<i32>(),order) != second ||
           byte_subtracted.load(core.sync.atomic.Ordering.Relaxed) != first {
            return false
        }
    }
    for (success_order,failure_order) in [""" + pair_values + """] {
        if !check_pointer_cas(success_order,failure_order) ||
           !check_pointer_cas_failure(success_order,failure_order) ||
           !check_pointer_cas_weak_failure(success_order,failure_order) ||
           !check_pointer_cas_weak_success(success_order,failure_order) {
            return false
        }
    }
    true
}"""
    sections.append(pointer) if category == "basic" else None
    sections.append(
        """fn check_fences(): bool {
    core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
    core.sync.atomic.fence(core.sync.atomic.Ordering.Release)
    core.sync.atomic.fence(core.sync.atomic.Ordering.AcqRel)
    core.sync.atomic.fence(core.sync.atomic.Ordering.SeqCst)
    core.sync.atomic.compiler_fence(core.sync.atomic.Ordering.Acquire)
    core.sync.atomic.compiler_fence(core.sync.atomic.Ordering.Release)
    core.sync.atomic.compiler_fence(core.sync.atomic.Ordering.AcqRel)
    core.sync.atomic.compiler_fence(core.sync.atomic.Ordering.SeqCst)
    true
}""") if category == "basic" else None
    checks = [f"check_{spec[0]}()" for spec in types]
    if category == "basic":
        checks.extend(("check_bool()", "check_pointer()", "check_fences()"))
    main = ["fn main(): i32 {"]
    main.extend(f"    if !{check} {{ return {index} }}" for index, check in
                enumerate(checks, 1))
    main.extend(("    0", "}"))
    return "\n\n".join(sections) + "\n" + "\n".join(main) + "\n"


MACHINE_SOURCES = {
    "machine-target-variadic-vector-c-physical-entry": """
unsafe extern "C" fn inspect(first:i32,args: ...):i32 {
    let vector = args.arg<""" + VECTOR + """>()
    let integer = args.arg<i32>()
    let floating = args.arg<f64>()
    let lanes = core.mem.transmute<[i32;4]>(vector)
    if first == 1 && lanes[0] == 42 && lanes[3] == 42 &&
       integer == 2 && floating == 40.0 { 42 } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_machine_vector_definition(
        callback:unsafe extern "C" fn(i32,...):i32):i32;
}
fn main() { if unsafe { mettle_c_machine_vector_definition(inspect) } == 42 { 0 } else { 1 } }
""",
    **({
    "machine-target-wide-vector-aggregate-c-abi": """
@layout(C) copy type Wide { value: core.arch.x86_64.__m256i }
@layout(C) copy type ScalarFloat { value: f64 }
@target_feature("avx")
unsafe extern "C" fn mettle_c_machine_wide_aggregate(value: Wide): Wide;
@target_feature("avx")
unsafe extern "C" fn mettle_c_machine_wide_callback(value: Wide): Wide;
@target_feature("avx")
unsafe extern "C" fn mettle_c_machine_wide_variadic(count: i32, ...): f64;
@export_name("mettle_wide_aggregate_identity")
@target_feature("avx")
unsafe extern "C" fn identity(value: Wide): Wide { value }
fn main() {
    if is_x86_feature_detected!("avx") {
        let value = Wide(unsafe { core.arch.x86_64._mm256_set1_epi32(41) })
        let next = unsafe { mettle_c_machine_wide_aggregate(value) }
        let next_lanes = unsafe { core.mem.transmute<[i32;8]>(next.value) }
        if next_lanes[0] != 42 || next_lanes[7] != 42 { return 1 }
        let result = unsafe { mettle_c_machine_wide_callback(next) }
        let lanes = unsafe { core.mem.transmute<[i32;8]>(result.value) }
        if lanes[0] != 42 || lanes[7] != 42 { return 2 }
        let small = Wide(unsafe { core.arch.x86_64._mm256_set1_epi32(1) })
        let variadic = unsafe { mettle_c_machine_wide_variadic(
            7, small, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, ScalarFloat(13.0)) }
        if variadic == 42.0 { 0 } else { 3 }
    } else { 0 }
}
""",
    "machine-target-guarded-wide-vector-c-physical-abi": """
@target_feature("avx")
unsafe extern "C" fn mettle_c_machine_vector256(
    value:core.arch.x86_64.__m256i):core.arch.x86_64.__m256i;
fn main() {
    if is_x86_feature_detected!("avx") {
        let value = unsafe { core.arch.x86_64._mm256_set1_epi32(41) }
        let callback = mettle_c_machine_vector256
        let returned = unsafe { callback(value) }
        let lanes = unsafe { core.mem.transmute<[i32;8]>(returned) }
        if lanes[0] == 42 && lanes[7] == 42 { 0 } else { 1 }
    } else { 0 }
}
""",
    "machine-target-variadic-wide-vector-overflow-area": """
@target_feature("avx")
unsafe extern "C" fn inspect(first:i32,args: ...):i32 {
    let vector = args.arg<core.arch.x86_64.__m256i>()
    let integer = args.arg<i32>()
    let floating = args.arg<f64>()
    let lanes = core.mem.transmute<[i32;8]>(vector)
    if first == 1 && lanes[0] == 42 && lanes[7] == 42 &&
       integer == 2 && floating == 40.0 { 42 } else { -1 }
}
fn main() {
    if is_x86_feature_detected!("avx") {
        let vector = unsafe { core.arch.x86_64._mm256_set1_epi32(42) }
        if unsafe { inspect(1,vector,2,40.0) } == 42 { 0 } else { 1 }
    } else { 0 }
}
""",
        "machine-target-wide-vector-vararg-preserves-sse-register-budget": """
@layout(C) copy type ScalarFloat { value:f64 }
@target_feature("avx")
unsafe extern "C" fn mettle_c_machine_vector_variadic(count:i32,...):f64;
fn main() {
    if is_x86_feature_detected!("avx") {
        let vector = unsafe { core.arch.x86_64._mm256_set1_epi32(1) }
        let result = unsafe { mettle_c_machine_vector_variadic(
            7,vector,1.0,2.0,3.0,4.0,5.0,6.0,7.0,ScalarFloat(13.0)) }
        if result == 42.0 { 0 } else { 1 }
    } else { 0 }
}
""",
    } if not ARM64 else {}),
    "machine-target-vector-aggregate-and-mixed-union-abi": """
@layout(C)
copy type VectorPair { first: """ + VECTOR + """; second: """ + (
    "core.arch.aarch64.int64x2_t" if ARM64 else
    "core.arch.x86_64.__m128i") + """ }
@layout(C)
copy union VectorUnion { vector: """ + VECTOR + """; floating:f64; integer:u64 }
extern "C" {
    unsafe fn mettle_c_machine_vector_pair(value:VectorPair):VectorPair;
    unsafe fn mettle_c_machine_vector_union(value:VectorUnion):VectorUnion;
}
fn main() {
    unsafe {
        let first = """ + (
            "core.arch.aarch64.vdupq_n_s32(40)" if ARM64 else
            "core.arch.x86_64._mm_set1_epi32(40)") + """
        let second = """ + (
            "core.arch.aarch64.vdupq_n_s64(40i64)" if ARM64 else
            "core.arch.x86_64._mm_set1_epi64x(40i64)") + """
        let pair = mettle_c_machine_vector_pair(VectorPair(first,second))
        let result = mettle_c_machine_vector_union(VectorUnion(vector:pair.first))
        let narrow = core.mem.transmute<[i32;4]>(pair.first)
        let wide = core.mem.transmute<[i64;2]>(pair.second)
        let union_lanes = core.mem.transmute<[i32;4]>(result.vector)
        if narrow[0] == 41 && wide[1] == 42i64 && union_lanes[3] == 42 { 0 } else { 1 }
    }
}
""",
    "machine-asm-global-symbol-physical-mangling": """
global_asm!(\"""" + (
    ".globl _mettle_machine_jump\\n_mettle_machine_jump:\\nb {symbol}" if ARM64 else
    ".globl mettle_machine_jump\\nmettle_machine_jump:\\njmp {symbol}"
    ) + """\",symbol = sym mettle_c_machine_answer)
extern "C" {
    unsafe fn mettle_c_machine_answer():i32;
    unsafe fn mettle_machine_jump():i32;
}
fn main() { if unsafe { mettle_machine_jump() } == 42 { 0 } else { 1 } }
""",
    "machine-asm-global-generic-symbol-retention": """
fn identity<T:Copy>(value:T):T { value }
core.arch.global_asm!(".data\\n.p2align 3\\n.quad {symbol}\\n.text",
                       symbol = sym identity<i64>)
fn main() { 0 }
""",
    "machine-asm-publishes-no-output-after-input-unwind": """
unsafe fn failing_input(): i32 {
    let zero = 0
    1 / zero
}
unsafe extern "C-unwind" fn failed_assembly(context: ptr<mut Unit>) {
    let pointer = context.cast<i32>()
    asm!(\"""" + ('mov {out:w}, {input:w}' if ARM64 else
                   'mov {out:e}, {input:e}') + """\",
         out = out(reg) *pointer, input = in(reg) failing_input(),
         options(nomem,nostack))
}
extern "C" {
    unsafe fn mettle_c_machine_catch(
        callback: unsafe extern "C-unwind" fn(ptr<mut Unit>): Unit,
        context: ptr<mut Unit>): i32;
}
fn main() {
    var value = 42
    let pointer = core.ptr.from_mut(value).cast<Unit>()
    let caught = unsafe { mettle_c_machine_catch(failed_assembly,pointer) }
    if caught == 1 && value == 42 { 0 } else { 1 }
}
""",
    "machine-asm-naked-real-c-register-and-stack-abi": """
@naked
@export_name("mettle_machine_naked_sum")
unsafe extern "C" fn naked_sum(left: i32,right: i32): i32 {
    naked_asm!(\"""" + ('add w0, w0, w1\\nret' if ARM64
                        else 'lea eax, [edi + esi]\\nret') + """\")
}
@naked
@export_name("mettle_machine_naked_stack")
unsafe extern "C" fn naked_stack(a:i32,b:i32,c:i32,d:i32,e:i32,
                                f:i32,g:i32,h:i32,i:i32,j:i32): i32 {
    naked_asm!(\"""" + ('ldr w8, [sp, #4]\\nadd w0, w0, w8\\nret' if ARM64
                       else 'mov eax, dword ptr [rsp + 32]\\nadd eax, edi\\nret') + """\")
}
extern "C" {
    unsafe fn mettle_c_machine_binary(callback: unsafe extern "C" fn(i32,i32):i32):i32;
    unsafe fn mettle_c_machine_stack(callback: unsafe extern "C" fn(
        i32,i32,i32,i32,i32,i32,i32,i32,i32,i32):i32):i32;
}
fn main() {
    if unsafe { mettle_c_machine_binary(naked_sum) } == 42 &&
       unsafe { mettle_c_machine_stack(naked_stack) } == 42 { 0 } else { 1 }
}
""",
    "machine-asm-global-constant-real-call": """
static RETURN_CODE: i128 = (1i128 << 80) + 42;
global_asm!(\"""" + (
    '.globl _mettle_machine_global\\n_mettle_machine_global:\\nmov w0, #{answer}\\nret'
    if ARM64 else
    '.globl mettle_machine_global\\nmettle_machine_global:\\nmov eax, {answer}\\nret'
) + """\", answer = const RETURN_CODE - (1i128 << 80))
extern "C" { unsafe fn mettle_machine_global(): i32; }
fn main() { if unsafe { mettle_machine_global() } == 42 { 0 } else { 1 } }
""",
    "machine-asm-symbol-and-c-abi-clobbers": """
extern "C" { unsafe fn mettle_c_machine_answer(): i32; }
fn main() {
    var answer = 0i32
    unsafe {
        asm!(\"""" + ('bl {symbol}' if ARM64 else 'call {symbol}') + """\",
             symbol = sym mettle_c_machine_answer,
             out(\"""" + ('w0' if ARM64 else 'eax') + """\") answer,
             clobber_abi("C"))
    }
    if answer == 42 { 0 } else { 1 }
}
""",
    "machine-target-native-vector-c-abi-and-callback": """
unsafe extern "C" fn vector_callback(value: """ + VECTOR + """): """ + VECTOR + """ {
    """ + (
        "core.arch.aarch64.vaddq_s32(value,core.arch.aarch64.vdupq_n_s32(1))"
        if ARM64 else
        "core.arch.x86_64._mm_add_epi32(value,core.arch.x86_64._mm_set1_epi32(1))"
    ) + """
}
extern "C" {
    unsafe fn mettle_c_machine_vector(value: """ + VECTOR + """): """ + VECTOR + """;
    unsafe fn mettle_c_machine_vector_callback(
        callback: unsafe extern "C" fn(""" + VECTOR + """): """ + VECTOR + """,
        value: """ + VECTOR + """): """ + VECTOR + """;
}
fn main() {
    unsafe {
        let value = """ + (
            "core.arch.aarch64.vdupq_n_s32(40)" if ARM64 else
            "core.arch.x86_64._mm_set1_epi32(40)") + """
        let incremented = mettle_c_machine_vector(value)
        let result = mettle_c_machine_vector_callback(vector_callback,incremented)
        let lanes = core.mem.transmute<[i32;4]>(result)
        if lanes[0] == 42 && lanes[3] == 42 { 0 } else { 1 }
    }
}
""",
}


PRELUDE = """
@layout(C)
copy type Pair { first: i32; second: i32 }
@layout(C)
copy type Floats { first: f32; second: f32 }
@layout(C)
copy type Mixed { first: f64; second: i32 }
@layout(C)
copy type Large { first: i64; second: i64; third: i64 }
@layout(C)
@packed(1)
copy type Packed { first: u8; second: i32 }
@export_name("mettle_export_pair")
extern "C" fn exported_pair(value: Pair): Pair {
    if value.first != 19 || value.second != 22 { return Pair(0,0) }
    Pair(value.first + 1,value.second + 1)
}
extern "C" {
    unsafe fn mettle_c_integer(first: i8, second: u8, third: i64): i64;
    unsafe fn mettle_c_pair(value: Pair): Pair;
    unsafe fn mettle_c_call_export(value: Pair): Pair;
    unsafe fn mettle_c_floats(value: Floats): Floats;
    unsafe fn mettle_c_mixed(value: Mixed): Mixed;
    unsafe fn mettle_c_large(value: Large): Large;
    unsafe fn mettle_c_packed(value: Packed): Packed;
    unsafe fn mettle_c_pair_size(): usize;
    unsafe fn mettle_c_packed_offset(): usize;
    unsafe fn mettle_c_variadic(count: i32, ...): f64;
    unsafe fn mettle_c_callback(
        callback: unsafe extern "C" fn(ptr<mut Unit>,i32): i32,
        context: ptr<mut Unit>, value: i32): i32;
    unsafe fn mettle_c_catch(
        callback: unsafe extern "C-unwind" fn(ptr<mut Unit>): Unit,
        context: ptr<mut Unit>): i32;
    unsafe fn mettle_atomic_publication(
        store: unsafe extern "C" fn(ptr<mut Unit>,u32): Unit,
        load: unsafe extern "C" fn(ptr<mut Unit>): u32,
        context: ptr<mut Unit>): i32;
}
unsafe extern "C" fn callback(context: ptr<mut Unit>, value: i32): i32 {
    let counter = context.cast<i32>()
    *counter += value
    *counter
}
type Guard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
unsafe extern "C-unwind" fn panic_callback(context: ptr<mut Unit>) {
    let guard = Guard(context.cast<i32>())
    let zero = 0
    let quotient = 1 / zero
}
type Leaf {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
type PanicDrop {
    first: Leaf; second: Leaf
    drop {
        unsafe { *self.first.counter += 100 }
        let zero = 0
        let quotient = 1 / zero
    }
}
unsafe extern "C-unwind" fn drop_callback(context: ptr<mut Unit>) {
    let counter = context.cast<i32>()
    var storage = core.mem.ManuallyDrop.new(
        PanicDrop(Leaf(counter,1),Leaf(counter,10)))
    storage.drop()
}
@packed(1)
type PackedDrop { tag: u8; payload: PanicDrop }
unsafe extern "C-unwind" fn packed_drop_callback(context: ptr<mut Unit>) {
    let counter = context.cast<i32>()
    let value = PackedDrop(1u8,PanicDrop(Leaf(counter,1),Leaf(counter,10)))
}
unsafe extern "C" fn release_flag(context: ptr<mut Unit>, value: u32) {
    core.intrinsics.atomic_store(context.cast<u32>(),value,
                                    core.sync.atomic.Ordering.Release)
}
unsafe extern "C" fn acquire_flag(context: ptr<mut Unit>): u32 {
    core.intrinsics.atomic_load(context.cast<u32>(),
                                  core.sync.atomic.Ordering.Acquire)
}
"""

DARWIN_ABI_COMMON = """
@layout(C)
copy type DarwinExportPair { first:i32; second:i32 }
@export_name("mettle_export_pair")
extern "C" fn darwin_export_pair(value:DarwinExportPair):DarwinExportPair {
    DarwinExportPair(value.first + 1,value.second + 1)
}
@export_name("mettle_darwin_exported_increment")
extern "C" fn darwin_exported_increment(value:i32):i32 { value + 1 }
"""

def darwin_neon_operation_matrix():
    element_types = (
        ("s8", "i8", 8, True),
        ("u8", "u8", 8, True),
        ("s16", "i16", 16, True),
        ("u16", "u16", 16, True),
        ("s32", "i32", 32, True),
        ("u32", "u32", 32, True),
        ("s64", "i64", 64, True),
        ("u64", "u64", 64, True),
        ("f32", "f32", 32, False),
        ("f64", "f64", 64, False),
    )
    functions, calls = [], []
    for suffix, scalar_type, width, integer in element_types:
        def scalar(value):
            return f"{value}{scalar_type}" if integer else f"{value}.0{scalar_type}"

        for bits in (64, 128):
            lanes = bits // width
            q = "q" if bits == 128 else ""
            prefix = "core.arch.aarch64."
            splat = prefix + f"vdup{q}_n_{suffix}"
            add = prefix + f"vadd{q}_{suffix}"
            sub = prefix + f"vsub{q}_{suffix}"
            mul = prefix + f"vmul{q}_{suffix}"
            load = prefix + f"vld1{q}_{suffix}"
            store = prefix + f"vst1{q}_{suffix}"
            extract = prefix + f"vget{q}_lane_{suffix}"
            insert = prefix + f"vset{q}_lane_{suffix}"
            name = f"check_{suffix}x{lanes}"
            source = [
                f"unsafe fn {name}(): bool {{",
                f"    let base = {splat}({scalar(10)})",
                f"    let delta = {splat}({scalar(2)})",
                f"    let added = {add}(base, delta)",
                f"    let subtracted = {sub}(base, delta)",
            ]
            if not (integer and width == 64):
                source.append(f"    let multiplied = {mul}(base, delta)")
            if integer:
                mask = splat + f"({scalar(3)})"
                source.extend(
                    (
                        f"    let anded = core.arch.aarch64.vand{q}_{suffix}"
                        f"(base, {mask})",
                        f"    let ored = core.arch.aarch64.vorr{q}_{suffix}"
                        f"(base, {mask})",
                        f"    let xored = core.arch.aarch64.veor{q}_{suffix}"
                        f"(base, {mask})",
                    )
                )
            values = ", ".join(scalar(10) for _ in range(lanes))
            zeroes = ", ".join(scalar(0) for _ in range(lanes))
            source.extend(
                (
                    f"    let input = [{values}]",
                    f"    let loaded = {load}(core.ptr.from_ref(input[0]))",
                    f"    var output = [{zeroes}]",
                    f"    {store}(core.ptr.from_mut(output[0]), loaded)",
                )
            )
            checks = [
                f"{extract}(added, 0) == {scalar(12)}",
                f"{extract}(subtracted, {lanes - 1}) == {scalar(8)}",
                f"{extract}(loaded, 0) == {scalar(10)}",
                f"{extract}({insert}({scalar(12)}, base, {lanes - 1}), "
                f"{lanes - 1}) == {scalar(12)}",
                f"output[0] == {scalar(10)}",
                f"output[{lanes - 1}] == {scalar(10)}",
            ]
            if not (integer and width == 64):
                checks.append(f"{extract}(multiplied, 0) == {scalar(20)}")
            if integer:
                checks.extend((
                    f"{extract}(anded, 0) == {scalar(2)}",
                    f"{extract}(ored, 0) == {scalar(11)}",
                    f"{extract}(xored, 0) == {scalar(9)}",
                ))
            source.append("    " + " &&\n        ".join(checks))
            source.append("}")
            functions.append("\n".join(source))
            calls.append(f"check_{suffix}x{lanes}()")
    return (
        "\n".join(functions)
        + "\nfn main(): i32 {\n    if unsafe {\n        "
        + " &&\n        ".join(calls)
        + "\n    } { 0 } else { 1 }\n}\n"
    )

DARWIN_ARM64_SOURCES = ({
    "darwin-arm64-c-hfa-hva-shape-matrix": """
@layout(C)
copy type DarwinHfa1 { first:f64 }
@layout(C)
copy type DarwinHfa2 { first:f64; second:f64 }
@layout(C)
copy type DarwinHfa4 { first:f64; second:f64; third:f64; fourth:f64 }
@layout(C)
copy type DarwinHva1 { first:core.arch.aarch64.int32x4_t }
@layout(C)
copy type DarwinHva3 {
    first:core.arch.aarch64.int32x4_t;
    second:core.arch.aarch64.int32x4_t;
    third:core.arch.aarch64.int32x4_t
}
@layout(C)
copy type DarwinHva4 {
    first:core.arch.aarch64.int32x4_t;
    second:core.arch.aarch64.int32x4_t;
    third:core.arch.aarch64.int32x4_t;
    fourth:core.arch.aarch64.int32x4_t
}
unsafe extern "C" fn hfa1_callback(value:DarwinHfa1):DarwinHfa1 {
    DarwinHfa1(value.first + 1.0f64)
}
unsafe extern "C" fn hva4_callback(value:DarwinHva4):DarwinHva4 {
    DarwinHva4(
        core.arch.aarch64.vaddq_s32(
            value.first,core.arch.aarch64.vdupq_n_s32(1)),
        core.arch.aarch64.vaddq_s32(
            value.second,core.arch.aarch64.vdupq_n_s32(2)),
        core.arch.aarch64.vaddq_s32(
            value.third,core.arch.aarch64.vdupq_n_s32(3)),
        core.arch.aarch64.vaddq_s32(
            value.fourth,core.arch.aarch64.vdupq_n_s32(4)))
}
extern "C" {
    unsafe fn mettle_c_darwin_hfa1(value:DarwinHfa1):DarwinHfa1;
    unsafe fn mettle_c_darwin_hfa2(value:DarwinHfa2):DarwinHfa2;
    unsafe fn mettle_c_darwin_hfa4(value:DarwinHfa4):DarwinHfa4;
    unsafe fn mettle_c_darwin_hfa1_callback(
        callback:unsafe extern "C" fn(DarwinHfa1):DarwinHfa1,
        value:DarwinHfa1):DarwinHfa1;
    unsafe fn mettle_c_darwin_hva1(value:DarwinHva1):DarwinHva1;
    unsafe fn mettle_c_darwin_hva3(value:DarwinHva3):DarwinHva3;
    unsafe fn mettle_c_darwin_hva4(value:DarwinHva4):DarwinHva4;
    unsafe fn mettle_c_darwin_hva4_callback(
        callback:unsafe extern "C" fn(DarwinHva4):DarwinHva4,
        value:DarwinHva4):DarwinHva4;
}
fn main() {
    unsafe {
        let hfa1 = mettle_c_darwin_hfa1(DarwinHfa1(40.0f64))
        let hfa2 = mettle_c_darwin_hfa2(DarwinHfa2(20.0f64,21.0f64))
        let hfa4 = mettle_c_darwin_hfa4(
            DarwinHfa4(10.0f64,11.0f64,12.0f64,13.0f64))
        let hfa_callback = mettle_c_darwin_hfa1_callback(
            hfa1_callback,DarwinHfa1(41.0f64))
        let hva1 = mettle_c_darwin_hva1(
            DarwinHva1(core.arch.aarch64.vdupq_n_s32(40)))
        let hva3 = mettle_c_darwin_hva3(DarwinHva3(
            core.arch.aarch64.vdupq_n_s32(10),
            core.arch.aarch64.vdupq_n_s32(20),
            core.arch.aarch64.vdupq_n_s32(30)))
        let hva4_input = DarwinHva4(
            core.arch.aarch64.vdupq_n_s32(10),
            core.arch.aarch64.vdupq_n_s32(20),
            core.arch.aarch64.vdupq_n_s32(30),
            core.arch.aarch64.vdupq_n_s32(40))
        let hva4 = mettle_c_darwin_hva4(hva4_input)
        let hva4_callback_result = mettle_c_darwin_hva4_callback(
            hva4_callback,hva4_input)
        if hfa1.first == 41.0f64 &&
           hfa2.first == 21.0f64 && hfa2.second == 22.0f64 &&
           hfa4.first == 11.0f64 && hfa4.fourth == 14.0f64 &&
           hfa_callback.first == 42.0f64 &&
           core.arch.aarch64.vgetq_lane_s32(hva1.first,0) == 41 &&
           core.arch.aarch64.vgetq_lane_s32(hva3.first,0) == 11 &&
           core.arch.aarch64.vgetq_lane_s32(hva3.second,3) == 22 &&
           core.arch.aarch64.vgetq_lane_s32(hva3.third,0) == 33 &&
           core.arch.aarch64.vgetq_lane_s32(hva4.first,0) == 11 &&
           core.arch.aarch64.vgetq_lane_s32(hva4.fourth,3) == 44 &&
           core.arch.aarch64.vgetq_lane_s32(hva4_callback_result.first,0) == 11 &&
           core.arch.aarch64.vgetq_lane_s32(hva4_callback_result.fourth,3) == 44 {
            0
        } else { 1 }
    }
}
""",
    "darwin-arm64-c-hfa-hva-large-and-varargs": """
@layout(C)
copy type DarwinHfa3 { first:f64; second:f64; third:f64 }
@layout(C)
copy type DarwinHva2 {
    first:core.arch.aarch64.int32x4_t;
    second:core.arch.aarch64.int32x4_t
}
@layout(C)
copy type DarwinLarge { first:i64; second:i64; third:i64 }
unsafe extern "C" fn hfa_callback(value:DarwinHfa3):DarwinHfa3 {
    DarwinHfa3(value.first + 1.0f64,value.second + 1.0f64,
               value.third + 1.0f64)
}
unsafe extern "C" fn hva_callback(value:DarwinHva2):DarwinHva2 {
    DarwinHva2(
        core.arch.aarch64.vaddq_s32(
            value.first,core.arch.aarch64.vdupq_n_s32(3)),
        core.arch.aarch64.vaddq_s32(
            value.second,core.arch.aarch64.vdupq_n_s32(4)))
}
unsafe extern "C" fn large_callback(value:DarwinLarge):DarwinLarge {
    DarwinLarge(value.first + 1i64,value.second + 1i64,value.third + 1i64)
}
unsafe extern "C" fn inspect(count:i32,args: ...):i32 {
    let hva = args.arg<DarwinHva2>()
    let hfa = args.arg<DarwinHfa3>()
    let large = args.arg<DarwinLarge>()
    if count == 3 && hfa.first == 1.0f64 && hfa.second == 2.0f64 &&
       hfa.third == 3.0f64 &&
       core.arch.aarch64.vgetq_lane_s32(hva.first,0) == 4 &&
       core.arch.aarch64.vgetq_lane_s32(hva.second,3) == 5 &&
       large.first == 10i64 && large.second == 12i64 && large.third == 20i64 {
        42
    } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_darwin_hfa(value:DarwinHfa3):DarwinHfa3;
    unsafe fn mettle_c_darwin_hfa_callback(
        callback:unsafe extern "C" fn(DarwinHfa3):DarwinHfa3,
        value:DarwinHfa3):DarwinHfa3;
    unsafe fn mettle_c_darwin_hva(value:DarwinHva2):DarwinHva2;
    unsafe fn mettle_c_darwin_hva_callback(
        callback:unsafe extern "C" fn(DarwinHva2):DarwinHva2,
        value:DarwinHva2):DarwinHva2;
    unsafe fn mettle_c_darwin_large_callback(
        callback:unsafe extern "C" fn(DarwinLarge):DarwinLarge):i32;
    unsafe fn mettle_c_darwin_variadic(count:i32,...):i32;
    unsafe fn mettle_c_darwin_variadic_definition(
        callback:unsafe extern "C" fn(i32,...):i32):i32;
}
fn main() {
    unsafe {
        let hfa = mettle_c_darwin_hfa(DarwinHfa3(10.0f64,12.0f64,20.0f64))
        let hfa_callback_result = mettle_c_darwin_hfa_callback(
            hfa_callback,DarwinHfa3(1.0f64,2.0f64,3.0f64))
        let initial = core.arch.aarch64.vdupq_n_s32(20)
        let hva = mettle_c_darwin_hva(DarwinHva2(initial,initial))
        let hva_callback_result = mettle_c_darwin_hva_callback(
            hva_callback,DarwinHva2(initial,initial))
        let large_callback_ok = mettle_c_darwin_large_callback(large_callback)
        let c_varargs_ok = mettle_c_darwin_variadic(
            3,DarwinHva2(core.arch.aarch64.vdupq_n_s32(4),
                         core.arch.aarch64.vdupq_n_s32(5)),
            DarwinHfa3(1.0f64,2.0f64,3.0f64),
            DarwinLarge(10i64,12i64,20i64))
        let callback_varargs_ok = mettle_c_darwin_variadic_definition(inspect)
        if hfa.first == 11.0f64 && hfa.second == 13.0f64 &&
           hfa.third == 21.0f64 &&
           hfa_callback_result.first == 2.0f64 &&
           hfa_callback_result.third == 4.0f64 &&
           core.arch.aarch64.vgetq_lane_s32(hva.first,0) == 21 &&
           core.arch.aarch64.vgetq_lane_s32(hva.second,3) == 22 &&
           core.arch.aarch64.vgetq_lane_s32(hva_callback_result.first,0) == 23 &&
           core.arch.aarch64.vgetq_lane_s32(hva_callback_result.second,3) == 24 &&
           large_callback_ok == 1 && c_varargs_ok == 1 &&
           callback_varargs_ok == 42 { 0 } else { 1 }
    }
}
""",
    "darwin-arm64-c-layout-alignment-packed-and-offsets": """
@layout(C)
copy type DarwinLayoutLeaf { tag:u8; value:u64 }
@layout(C)
@align(32)
copy type DarwinLayout {
    prefix:u8;
    leaf:DarwinLayoutLeaf;
    tail:u32
}
@layout(C)
@packed(1)
copy type DarwinPacked { tag:u8; payload:u32 }
extern "C" {
    unsafe fn mettle_c_darwin_layout_metrics(
        size:usize,alignment:usize,leaf_offset:usize,value_offset:usize,
        tail_offset:usize):i32;
    unsafe fn mettle_c_darwin_packed_echo(value:DarwinPacked):DarwinPacked;
}
fn main() {
    let value = DarwinLayout(1u8,DarwinLayoutLeaf(2u8,3u64),4u32)
    let base = core.ptr.from_ref(value).cast<u8>()
    let leaf = core.ptr.from_ref(value.leaf).cast<u8>()
    let nested_value = core.ptr.from_ref(value.leaf.value).cast<u8>()
    let tail = core.ptr.from_ref(value.tail).cast<u8>()
    let leaf_offset = unsafe { leaf.byte_offset_from_unsigned(base) }
    let value_offset = unsafe { nested_value.byte_offset_from_unsigned(base) }
    let tail_offset = unsafe { tail.byte_offset_from_unsigned(base) }
    let metrics_match = unsafe {
        mettle_c_darwin_layout_metrics(
            core.mem.size_of<DarwinLayout>(),
            core.mem.align_of<DarwinLayout>(),
            leaf_offset,value_offset,tail_offset)
    }
    let packed = unsafe { mettle_c_darwin_packed_echo(DarwinPacked(7u8,41u32)) }
    if metrics_match == 1 && packed.tag == 7u8 && packed.payload == 42u32 &&
       core.mem.size_of<DarwinPacked>() == 5usize { 0 } else { 1 }
}
""",
"darwin-arm64-c-layout-union-tagged-and-transparent": """
@layout(C)
union DarwinLayoutUnion { integer:i64; real:f64 }
@layout(C)
copy enum DarwinLayoutTagged {
    Empty = 1;
    Integer(i64) = 7;
    Real(f64) = 11
}
@layout(transparent)
copy type DarwinLayoutTransparent { value:u64 }
extern "C" {
    unsafe fn mettle_c_darwin_layout_extra_metrics(
        union_size:usize,union_alignment:usize,tagged_size:usize,
        tagged_alignment:usize,transparent_size:usize,
        transparent_alignment:usize):i32;
    unsafe fn mettle_c_darwin_layout_union(
        take value:DarwinLayoutUnion):DarwinLayoutUnion;
    unsafe fn mettle_c_darwin_layout_tagged(
        value:DarwinLayoutTagged):DarwinLayoutTagged;
    unsafe fn mettle_c_darwin_layout_transparent(
        value:DarwinLayoutTransparent):DarwinLayoutTransparent;
}
fn main() {
    let union_value = unsafe {
        mettle_c_darwin_layout_union(DarwinLayoutUnion(integer:41i64))
    }
    let tagged = unsafe {
        mettle_c_darwin_layout_tagged(DarwinLayoutTagged.Integer(41i64))
    }
    let transparent = unsafe {
        mettle_c_darwin_layout_transparent(DarwinLayoutTransparent(41u64))
    }
    let metrics = unsafe {
        mettle_c_darwin_layout_extra_metrics(
            core.mem.size_of<DarwinLayoutUnion>(),
            core.mem.align_of<DarwinLayoutUnion>(),
            core.mem.size_of<DarwinLayoutTagged>(),
            core.mem.align_of<DarwinLayoutTagged>(),
            core.mem.size_of<DarwinLayoutTransparent>(),
            core.mem.align_of<DarwinLayoutTransparent>())
    }
    let tagged_ok = match tagged {
        DarwinLayoutTagged.Integer(value) => value == 42i64,
        _ => false
    }
    if metrics == 1 && unsafe { union_value.integer == 42i64 } &&
       tagged_ok && transparent.value == 42u64 { 0 } else { 1 }
}
""",
"darwin-arm64-c-scalar-bool-callback-and-float-promotion": """
unsafe extern "C" fn invert(value:bool):bool { !value }
unsafe extern "C" fn next_char(value:char):char {
    if value == '\\u{1f600}' { '\\u{1f601}' } else { 'x' }
}
unsafe extern "C" fn inspect_float(count:i32,args: ...):i32 {
    let value = args.arg<f64>()
    if count == 1 && value == 42.0f64 { 42 } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_darwin_bool_roundtrip(value:bool):bool;
    unsafe fn mettle_c_darwin_bool_callback(
        callback:unsafe extern "C" fn(bool):bool,value:bool):bool;
    unsafe fn mettle_c_darwin_variadic_float_definition(
        callback:unsafe extern "C" fn(i32,...):i32):i32;
    unsafe fn mettle_c_darwin_char_next(value:char):char;
    unsafe fn mettle_c_darwin_char_callback(
        callback:unsafe extern "C" fn(char):char,value:char):char;
}
fn main() {
    if unsafe { mettle_c_darwin_char_next('\\u{1f600}') } != '\\u{1f601}' {
        return 2
    }
    let through = unsafe {
        mettle_c_darwin_char_callback(next_char,'\\u{1f600}')
    }
    if through != '\\u{10ffff}' { return 3 }
    let roundtrip = unsafe { mettle_c_darwin_bool_roundtrip(true) }
    let callback = unsafe { mettle_c_darwin_bool_callback(invert,true) }
    let promoted = unsafe {
        mettle_c_darwin_variadic_float_definition(inspect_float)
    }
    if roundtrip && !callback && promoted == 42 { 0 } else { 1 }
}
""",
"darwin-arm64-cpp-exception-unwinds-through-mettle-cleanup": """
type UnwindGuard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
unsafe extern "C-unwind" fn indirect_throw(context:ptr<mut i32>):Unit {
    let guard = UnwindGuard(context)
    unsafe { mettle_cpp_throw() }
}
extern "C-unwind" {
    unsafe fn mettle_cpp_throw():Never;
}
extern "C" {
    unsafe fn mettle_cpp_indirect_throw_catch(
        callback:unsafe extern "C-unwind" fn(ptr<mut i32>):Unit,
        context:ptr<mut i32>):i32;
}
fn main() {
    var count = 0
    let indirect = unsafe {
        mettle_cpp_indirect_throw_catch(
            indirect_throw,core.ptr.from_mut(count))
    }
    if indirect == 1 && count == 2 { 0 } else { 1 }
}
""",
"darwin-arm64-c-export-link-and-relocation": """
extern "C" {
unsafe fn mettle_c_darwin_exported_call(value:i32):i32;
}
fn main() {
    if unsafe { mettle_c_darwin_exported_call(41) } == 42 { 0 } else { 1 }
}
""",
    "darwin-arm64-inline-assembly-c-caller-and-clobbers": """
unsafe extern "C" fn assembly_sum(left:i32,right:i32):i32 {
    var sum = left
    asm!("add {sum:w}, {sum:w}, {right:w}",
         sum = inout(reg) sum,right = in(reg) right,options(nomem,nostack))
    var answer = 0i32
    asm!("bl {symbol}",symbol = sym mettle_c_machine_answer,
         out("w0") answer,clobber_abi("C"))
    if answer == 42 { sum } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_machine_answer():i32;
    unsafe fn mettle_c_darwin_asm_call(
        callback:unsafe extern "C" fn(i32,i32):i32,
        left:i32,right:i32):i32;
}
fn main() {
    if unsafe { mettle_c_darwin_asm_call(assembly_sum,20,22) } == 42 {
        0
    } else { 1 }
}
""",
    "darwin-arm64-neon-operation-c-parity": """
extern "C" {
    unsafe fn mettle_c_darwin_neon_transform(
        left:ptr<read i32>,right:ptr<read i32>,output:ptr<mut i32>):Unit;
}
fn main() {
    let left = [20i32,21i32,22i32,23i32]
    let right = [1i32,2i32,3i32,4i32]
    var mettle_output = [0i32,0i32,0i32,0i32]
    var c_output = [0i32,0i32,0i32,0i32]
    let left_pointer = core.ptr.from_ref(left[0])
    let right_pointer = core.ptr.from_ref(right[0])
    let mettle_pointer = core.ptr.from_mut(mettle_output[0])
    let c_pointer = core.ptr.from_mut(c_output[0])
    unsafe {
        let first = core.arch.aarch64.vld1q_s32(left_pointer)
        let second = core.arch.aarch64.vld1q_s32(right_pointer)
        let sum = core.arch.aarch64.vaddq_s32(first,second)
        core.arch.aarch64.vst1q_s32(mettle_pointer,sum)
        mettle_c_darwin_neon_transform(left_pointer,right_pointer,c_pointer)
    }
    if mettle_output[0] == 21 && mettle_output[3] == 27 &&
       c_output[0] == mettle_output[0] &&
       c_output[1] == mettle_output[1] &&
       c_output[2] == mettle_output[2] &&
       c_output[3] == mettle_output[3] { 0 } else { 1 }
}
""",
    "darwin-arm64-volatile-c-observer": """
unsafe extern "C" fn volatile_update(pointer:ptr<mut i32>):i32 {
    pointer.write_volatile(41)
    let observed = pointer.read_volatile()
    pointer.write_volatile(observed + 1)
    observed
}
extern "C" {
    unsafe fn mettle_c_darwin_volatile_observe(
        callback:unsafe extern "C" fn(ptr<mut i32>):i32):i32;
}
fn main() {
    if unsafe { mettle_c_darwin_volatile_observe(volatile_update) } == 42 {
        0
    } else { 1 }
}
""",
    "darwin-arm64-neon-operation-contract-matrix":
        darwin_neon_operation_matrix(),
} if DARWIN_ARM64 else {})

SOURCES = {
    "c-nested-packed-aggregate-absolute-field-alignment": PRELUDE + """
@layout(C)
@packed(1)
copy type PackedInner { value:u64 }
@layout(C)
copy type PackedOuter { prefix:u8; payload:PackedInner }
@layout(C)
@packed(1)
copy type OffsetInner { pad:u8; value:u64 }
@layout(C)
copy type RepairedOuter { prefix:[u8;7]; payload:OffsetInner }
unsafe extern "C" fn nested_increment(value:PackedOuter):PackedOuter {
    PackedOuter(value.prefix,PackedInner(value.payload.value + 1u64))
}
extern "C" {
    unsafe fn mettle_c_nested_packed(value:PackedOuter):PackedOuter;
    unsafe fn mettle_c_nested_packed_callback(
        callback:unsafe extern "C" fn(PackedOuter):PackedOuter,
        value:PackedOuter):PackedOuter;
    unsafe fn mettle_c_packed_inner(value:PackedInner):PackedInner;
    unsafe fn mettle_c_repaired_packed(value:RepairedOuter):RepairedOuter;
}
fn main() {
    let input = PackedOuter(7u8,PackedInner(41u64))
    let direct = unsafe { mettle_c_nested_packed(input) }
    let callback = unsafe { mettle_c_nested_packed_callback(nested_increment,input) }
    let inner = unsafe { mettle_c_packed_inner(PackedInner(41u64)) }
    let repaired = unsafe { mettle_c_repaired_packed(
        RepairedOuter([1u8,2u8,3u8,4u8,5u8,6u8,7u8],OffsetInner(9u8,41u64))) }
    if input.prefix == 7u8 && input.payload.value == 41u64 &&
       direct.prefix == 7u8 && direct.payload.value == 42u64 &&
       callback.prefix == 7u8 && callback.payload.value == 42u64 &&
       inner.value == 42u64 &&
       repaired.prefix[0] == 1u8 && repaired.prefix[1] == 2u8 &&
       repaired.prefix[2] == 3u8 && repaired.prefix[3] == 4u8 &&
       repaired.prefix[4] == 5u8 && repaired.prefix[5] == 6u8 &&
       repaired.prefix[6] == 7u8 && repaired.payload.pad == 9u8 &&
       repaired.payload.value == 42u64 { 0 } else { 1 }
}
""",
    "review-aligned-wide-aggregate-stack-and-varargs": PRELUDE + """
@layout(C)
copy type AlignedWide { value:i128 }
unsafe extern "C" fn aligned_callback(a:i64,b:i64,c:i64,d:i64,e:i64,f:i64,g:i64,h:i64,
                              marker:i32,q:AlignedWide):i32 {
    if a+b+c+d+e+f+g+h == 36i64 && marker == 9 && q.value == 77i128 { 1 } else { 0 }
}
unsafe extern "C" fn inspect(first:i32,args: ...):i32 {
    let marker = args.arg<i32>()
    let q = args.arg<AlignedWide>()
    let tail = args.arg<i32>()
    if first == 1 && marker == 5 && q.value == 77i128 && tail == 6 { 1 } else { 0 }
}
extern "C" {
    unsafe fn mettle_c_aligned_wide_stack(
        a:i64,b:i64,c:i64,d:i64,e:i64,f:i64,g:i64,h:i64,marker:i32,q:AlignedWide):i32;
    unsafe fn mettle_c_aligned_wide_callback(
        callback:unsafe extern "C" fn(i64,i64,i64,i64,i64,i64,i64,i64,i32,AlignedWide):i32):i32;
    unsafe fn mettle_c_aligned_wide_varargs(first:i32,...):i32;
}
fn main() {
    unsafe {
        if mettle_c_aligned_wide_stack(1,2,3,4,5,6,7,8,9,AlignedWide(77)) == 1 &&
           mettle_c_aligned_wide_callback(aligned_callback) == 1 &&
           mettle_c_aligned_wide_varargs(1,5,AlignedWide(77),6) == 1 &&
           inspect(1,5,AlignedWide(77),6) == 1 { 0 } else { 1 }
    }
}
""",
    "c-thread-failed-cas-acquire-publication": PRELUDE + """
extern "C" {
    unsafe fn mettle_atomic_failed_acquire(
        store: unsafe extern "C" fn(ptr<mut Unit>,u32): Unit,
        compare: unsafe extern "C" fn(ptr<mut Unit>): u32,
        context: ptr<mut Unit>): i32;
}
unsafe extern "C" fn acquire_failure(context: ptr<mut Unit>): u32 {
    let result = core.intrinsics.atomic_compare_exchange(
        context.cast<u32>(),0u32,0u32,
        core.sync.atomic.Ordering.Relaxed,
        core.sync.atomic.Ordering.Acquire)
    match result { success(_) => 0u32, failure(value) => value }
}
fn main() {
    let flag = core.sync.atomic.AtomicU32.new(0)
    unsafe { mettle_atomic_failed_acquire(
        release_flag,acquire_failure,flag.as_ptr().cast<Unit>()) }
}
""",
    "c-thread-sequentially-consistent-store-buffering": PRELUDE + """
extern "C" {
    unsafe fn mettle_atomic_sequential_consistency(
        store: unsafe extern "C" fn(ptr<mut Unit>,u32,u32): Unit,
        load: unsafe extern "C" fn(ptr<mut Unit>,u32): u32,
        context: ptr<mut Unit>): i32;
}
unsafe extern "C" fn seq_store(context: ptr<mut Unit>,index: u32,value: u32) {
    core.intrinsics.atomic_store(
        context.cast<u32>().add(index as usize),value,
        core.sync.atomic.Ordering.SeqCst)
}
unsafe extern "C" fn seq_load(context: ptr<mut Unit>,index: u32): u32 {
    core.intrinsics.atomic_load(
        context.cast<u32>().add(index as usize),
        core.sync.atomic.Ordering.SeqCst)
}
fn main() {
    var flags = [0u32,0u32]
    let context = core.ptr.from_mut(flags).cast<Unit>()
    unsafe { mettle_atomic_sequential_consistency(seq_store,seq_load,context) }
}
""",
    "c-variadic-definition-wide-aligned-scalar-and-large-hfa": PRELUDE + """
@layout(C)
copy type Triple { first: f64; second: f64; third: f64 }
unsafe extern "C" fn inspect(count: i32,args: ...): i32 {
    let triple = args.arg<Triple>()
    let wide = args.arg<i128>()
    let last = args.arg<i32>()
    if triple.first + triple.second + triple.third == 42.0f64 &&
       wide == 1267650600228229401496703205418i128 && last == 42 { 42 } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_variadic_definition_wide(
        callback: unsafe extern "C" fn(i32,...): i32): i32;
}
fn main() {
    if unsafe { mettle_c_variadic_definition_wide(inspect) } == 42 { 0 } else { 1 }
}
""",
    "machine-static-owned-replacement-drops-only-the-old-value": PRELUDE + """
type CountedStatic {
    number: i32
    drop { unsafe { mettle_c_zst_drop() } }
}
static mut OWNER: CountedStatic = CountedStatic(1);
extern "C" {
    unsafe fn mettle_c_zst_reset(): Unit;
    unsafe fn mettle_c_zst_drop(): Unit;
    unsafe fn mettle_c_zst_count(): i32;
}
fn main() {
    unsafe { mettle_c_zst_reset(); OWNER = CountedStatic(42) }
    let count = unsafe { mettle_c_zst_count() }
    if count == 1 && unsafe { OWNER.number == 42 } { 0 } else { 1 }
}
""",
    "c-variadic-definition-compatible-unwind-and-native-cursor-cleanup": PRELUDE + """
unsafe extern "C-unwind" fn fail(context: ptr<mut Unit>,args: ...): i32 {
    let counter = context.cast<i32>()
    let guard = Guard(counter)
    var copied = args.copy()
    let number = copied.arg<i32>()
    let zero = 0
    number / zero
}
extern "C" {
    unsafe fn mettle_c_variadic_definition_catch(
        callback: unsafe extern "C-unwind" fn(ptr<mut Unit>,...): i32,
        context: ptr<mut Unit>): i32;
}
fn main() {
    var count = 40
    let caught = unsafe {
        mettle_c_variadic_definition_catch(fail,core.ptr.from_mut(count).cast<Unit>())
    }
    if caught == 1 && count == 42 { 0 } else { 1 }
}
""",
    "machine-static-owned-storage-never-scope-dropped": PRELUDE + """
type StaticOwner {
    number: i32
    drop { unsafe { mettle_c_zst_drop() } }
}
static OWNER: StaticOwner = StaticOwner(42);
extern "C" {
    unsafe fn mettle_c_zst_reset(): Unit;
    unsafe fn mettle_c_zst_drop(): Unit;
    unsafe fn mettle_c_zst_count(): i32;
}
fn touch() { OWNER.number }
fn main() {
    unsafe { mettle_c_zst_reset() }
    let value = touch()
    let count = unsafe { mettle_c_zst_count() }
    if value == 42 && count == 0 { 0 } else { 1 }
}
""",
    "c-variadic-definition-copy-and-independent-advancement": PRELUDE + """
unsafe extern "C" fn sum(count: i32,args: ...): i32 {
    let first = args.arg<i32>()
    var copied = args.copy()
    let second = args.arg<i32>()
    let again = copied.arg<i32>()
    args.end()
    if count == 2 && second == again { first + second } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_variadic_definition_scalars(
        callback: unsafe extern "C" fn(i32,...): i32): i32;
}
fn main() {
    if unsafe { mettle_c_variadic_definition_scalars(sum) } == 42 { 0 } else { 1 }
}
""",
    "c-variadic-definition-register-pressure-and-aggregates": PRELUDE + """
unsafe extern "C" fn inspect(count: i32,args: ...): i32 {
    let mixed = args.arg<Mixed>()
    var integers = 0i64
    for index in 0..10 { integers += args.arg<i64>() }
    let pair = args.arg<Pair>()
    var reals = 0.0f64
    for index in 0..10 { reals += args.arg<f64>() }
    let floats = args.arg<Floats>()
    let large = args.arg<Large>()
    let packed = args.arg<Packed>()
    if mixed.first == 20.0f64 && mixed.second == 22 &&
       integers == 55i64 && pair.first == 20 && pair.second == 22 &&
       reals == 55.0f64 && floats.first == 20.0f32 && floats.second == 22.0f32 &&
       large.first == 10i64 && large.second == 12i64 && large.third == 20i64 &&
       packed.first == 20u8 && packed.second == 22 { 42 } else { -1 }
}
extern "C" {
    unsafe fn mettle_c_variadic_definition_aggregates(
        callback: unsafe extern "C" fn(i32,...): i32): i32;
}
fn main() {
    if unsafe { mettle_c_variadic_definition_aggregates(inspect) } == 42 { 0 } else { 1 }
}
""",
    "machine-static-c-storage-symbols-and-relocation": PRELUDE + """
@export_name("mettle_exported_static")
static ANSWER: i32 = 42;
@export_name("mettle_mutable_static")
static mut COUNT: i32 = 1;
extern "C" {
    @link_name("mettle_exported_static")
    static IMPORTED: i32;
    @link_name("mettle_mutable_static")
    static mut IMPORTED_COUNT: i32;
    unsafe fn mettle_c_static_storage(value: ptr<read i32>, count: ptr<mut i32>): i32;
}
fn main() {
    let result = unsafe {
        mettle_c_static_storage(core.ptr.from_ref(ANSWER),core.ptr.from_mut(COUNT))
    }
    if result == 42 && IMPORTED == 42 && unsafe { IMPORTED_COUNT == 42 } { 0 } else { 1 }
}
""",
    "machine-cell-unwind-releases-packed-guard-once": """
extern "C" {
    unsafe fn mettle_cell_catch(
        callback: unsafe extern "C-unwind" fn(ptr<read Unit>): Unit,
        context: ptr<read Unit>): i32;
}
@packed(1)
type PanicGuard<region r> {
    byte: u8; guard: core.cell.RefMut<i32> from r
    drop { let zero = 0; let quotient = 1 / zero }
}
unsafe extern "C-unwind" fn callback(context: ptr<read Unit>) {
    let cell = read *context.cast<core.cell.RefCell<i32>>()
    var guard = cell.borrow_mut()
    *guard.get_mut() = 42
    let value = PanicGuard(1u8,guard)
}
fn main() {
    let cell = core.cell.RefCell.new(0)
    let context = core.ptr.from_ref(cell).cast<Unit>()
    let caught = unsafe { mettle_cell_catch(callback,context) }
    {
        var guard = cell.borrow_mut()
        *guard.get_mut() += 1
    }
    let guard = cell.borrow()
    if caught == 1 && *guard.get_ref() == 43 { 0 } else { 1 }
}
""",
    "machine-cell-set-installs-before-old-destructor-panics": """
extern "C" {
    unsafe fn mettle_cell_catch(
        callback: unsafe extern "C-unwind" fn(ptr<read Unit>): Unit,
        context: ptr<read Unit>): i32;
}
type Reenter {
    cell: ptr<read core.cell.Cell<Reenter>>
    observed: ptr<mut i32>; amount: i32
    drop {
        if self.amount == 1 {
            unsafe { *self.observed = (*(*self.cell).as_ptr()).amount }
            let zero = 0
            let quotient = 1 / zero
        } else { unsafe { *self.observed += 1 } }
    }
}
unsafe extern "C-unwind" fn callback(context: ptr<read Unit>) {
    let pointer = context.cast<core.cell.Cell<Reenter>>()
    let cell = read *pointer
    let observed = (*cell.as_ptr()).observed
    cell.set(Reenter(pointer,observed,42))
}
fn main() {
    var observed = 0
    let log = core.ptr.from_mut(observed)
    let cell = core.cell.Cell.new(
        Reenter(core.ptr.null<core.cell.Cell<Reenter>>(),log,1))
    let pointer = core.ptr.from_ref(cell)
    unsafe { (*cell.as_ptr()).cell = pointer }
    let caught = unsafe { mettle_cell_catch(callback,pointer.cast<Unit>()) }
    if caught != 1 || observed != 42 { return 1 }
    { let value = cell.into_inner() }
    if observed == 43 { 0 } else { 2 }
}
""",
    **{name: PRELUDE + source for name, source in MACHINE_SOURCES.items()},
    **({
        "machine-atomic-basic-ordering-matrix":
            PRELUDE + atomic_operation_matrix("basic"),
        "machine-atomic-fetch-ordering-matrix":
            PRELUDE + atomic_operation_matrix("fetch"),
        "machine-atomic-compare-exchange-ordering-matrix":
            PRELUDE + atomic_operation_matrix("compare-exchange"),
    } if DARWIN_ARM64 else {}),
    **{name: DARWIN_ABI_COMMON + source
       for name, source in DARWIN_ARM64_SOURCES.items()},
    "c-zero-size-owned-iteration-drops-every-element-once": PRELUDE + """
extern "C" {
    unsafe fn mettle_c_zst_reset(): Unit;
    unsafe fn mettle_c_zst_drop(): Unit;
    unsafe fn mettle_c_zst_count(): i32;
}
type Empty { drop { unsafe { mettle_c_zst_drop() } } }
fn main() {
    unsafe { mettle_c_zst_reset() }
    let values = [Empty(),Empty(),Empty()]
    for value in take values {}
    let count = unsafe { mettle_c_zst_count() }
    let pointer = core.ptr.null<Empty>()
    if count == 3 && core.mem.size_of<Empty>() == 0usize &&
       pointer.wrapping_add(18446744073709551615usize) == pointer &&
       pointer.wrapping_offset(-9223372036854775808isize) == pointer { 0 } else { 1 }
}
""",
    "c-combined-enum-and-transparent-payload-abi-forwarding": PRELUDE + """
@layout(C,u8)
copy enum Tiny { Empty = 7; Byte(u8) = 9; Wide(u64) = 42 }
@layout(transparent)
copy type Signed { value: i8 }
@layout(transparent)
copy enum Wrapped { Value(Signed,Unit) }
@layout(transparent)
copy enum Real { Value(f64) }
unsafe extern "C" fn transparent_callback(value: Wrapped): Wrapped {
    match value { Wrapped.Value(number,_) => Wrapped.Value(Signed(number.value - 1),()) }
}
extern "C" {
    unsafe fn mettle_c_tiny_tagged(value: Tiny): Tiny;
    unsafe fn mettle_c_transparent_callback(
        callback: unsafe extern "C" fn(Wrapped): Wrapped,value: Wrapped): Wrapped;
    unsafe fn mettle_c_transparent_double(value: Real): Real;
    unsafe fn mettle_c_enum_variadic(count: i32,...): i32;
}
fn main() {
    let tagged = unsafe { mettle_c_tiny_tagged(Tiny.Byte(41u8)) }
    let number = unsafe { mettle_c_transparent_callback(transparent_callback,Wrapped.Value(Signed(-1i8),())) }
    let real = unsafe { mettle_c_transparent_double(Real.Value(41.0f64)) }
    let promoted = unsafe { mettle_c_enum_variadic(1,Wrapped.Value(Signed(42i8),())) }
    let first = match tagged { Tiny.Byte(value) => value == 42u8, _ => false }
    let second = match number { Wrapped.Value(value,_) => value.value == -2i8 }
    let third = match real { Real.Value(value) => value == 42.0f64 }
    if first && second && third && promoted == 42 { 0 } else { 1 }
}
""",
    "c-union-integer-and-overlapping-homogeneous-float-layout": PRELUDE + """
@layout(C)
union Bits { integer: i64; real: f64 }
@layout(C)
union Doubles { first: f64; second: f64 }
extern "C" {
    unsafe fn mettle_c_union(take value: Bits): Bits;
    unsafe fn mettle_c_double_union(take value: Doubles, increment: f64): Doubles;
}
fn main() {
    let integer = unsafe { mettle_c_union(Bits(integer: 41i64)) }
    let real = unsafe { mettle_c_double_union(Doubles(second: 41.0f64),1.0f64) }
    if unsafe { integer.integer == 42i64 && real.second == 42.0f64 } { 0 } else { 1 }
}
""",
    "c-tagged-enum-layout-and-byte-enum-promotions": PRELUDE + """
@layout(C)
copy enum Tagged { Empty = 1; Integer(i64) = 7; Real(f64) = 11 }
@layout(u8)
copy enum Byte { First = 41; Last = 42 }
extern "C" {
    unsafe fn mettle_c_tagged(value: Tagged): Tagged;
    unsafe fn mettle_c_tagged_size(): usize;
    unsafe fn mettle_c_byte_enum(value: Byte): Byte;
    unsafe fn mettle_c_enum_variadic(count: i32, ...): i32;
}
fn main() {
    let integer = unsafe { mettle_c_tagged(Tagged.Integer(41i64)) }
    let real = unsafe { mettle_c_tagged(Tagged.Real(41.0f64)) }
    let byte = unsafe { mettle_c_byte_enum(Byte.First) }
    let promoted = unsafe { mettle_c_enum_variadic(1,Byte.Last) }
    let size = unsafe { mettle_c_tagged_size() }
    let first = match integer { Tagged.Integer(value) => value == 42i64, _ => false }
    let second = match real { Tagged.Real(value) => value == 42.0f64, _ => false }
    let last = match byte { Byte.Last => true, _ => false }
    if first && second && last && promoted == 42 &&
       size == core.mem.size_of<Tagged>() { 0 } else { 1 }
}
""",
    "c-unwind-packed-drop-finishes-relocated-fields-once": PRELUDE + """
fn main() {
    var counter = 0
    let context = core.ptr.from_mut(counter).cast<Unit>()
    let caught = unsafe { mettle_c_catch(packed_drop_callback,context) }
    if caught == 1 && counter == 112 { 0 } else { 1 }
}
""",
    "c-thread-release-acquire-publication": PRELUDE + """
fn main() {
    let flag = core.sync.atomic.AtomicU32.new(0)
    let context = flag.as_ptr().cast<Unit>()
    unsafe { mettle_atomic_publication(release_flag,acquire_flag,context) }
}
""",
    "c-unwind-explicit-in-place-cleanup": PRELUDE + """
fn main() {
    var counter = 0
    let context = core.ptr.from_mut(counter).cast<Unit>()
    let caught = unsafe { mettle_c_catch(drop_callback,context) }
    if caught == 1 && counter == 112 { 0 } else { 1 }
}
""",
    "c-layout-calls-and-callbacks": PRELUDE + """
fn main() {
    var counter = 40
    let context = core.ptr.from_mut(counter).cast<Unit>()
    let pair = unsafe { mettle_c_pair(Pair(19,22)) }
    let exported = unsafe { mettle_c_call_export(Pair(19,22)) }
    let floats = unsafe { mettle_c_floats(Floats(19.0f32,22.0f32)) }
    let mixed = unsafe { mettle_c_mixed(Mixed(19.0f64,22)) }
    let large = unsafe { mettle_c_large(Large(10i64,11i64,18i64)) }
    let packed = unsafe { mettle_c_packed(Packed(19u8,22)) }
    let called = unsafe { mettle_c_callback(callback,context,2) }
    let integer = unsafe { mettle_c_integer(-2i8,255u8,-211i64) }
    let size = unsafe { mettle_c_pair_size() }
    let offset = unsafe { mettle_c_packed_offset() }
    if pair.first == 20 && pair.second == 23 &&
       exported.first == 20 && exported.second == 23 &&
       floats.first == 20.0f32 && floats.second == 23.0f32 &&
       mixed.first == 20.0f64 && mixed.second == 23 &&
       large.first == 11i64 && large.second == 12i64 && large.third == 19i64 &&
       packed.first == 20u8 && packed.second == 23 &&
       called == 42 && counter == 42 && integer == 42i64 &&
       size == core.mem.size_of<Pair>() &&
       offset == 1usize && core.mem.size_of<Packed>() == 5usize { 0 } else { 1 }
}
""",
    "c-variadic-promotions": PRELUDE + """
fn main() {
    let value = unsafe { mettle_c_variadic(3,10.5f64,20.0f32,11.5f64) }
    let pointer: unsafe extern "C" fn(i32,...): f64 = mettle_c_variadic
    let indirect = unsafe { pointer(3,10.5f64,20.0f32,11.5f64) }
    if value == 42.0f64 && indirect == 42.0f64 { 0 } else { 1 }
}
""",
    "c-compatible-unwind-cleans-both-languages": PRELUDE + """
fn main() {
    var counter = 40
    let context = core.ptr.from_mut(counter).cast<Unit>()
    let caught = unsafe { mettle_c_catch(panic_callback,context) }
    if caught == 1 && counter == 42 { 0 } else { 1 }
}
""",
}

FREESTANDING_SOURCE = """
static OFFSET: i32 = 1;
static ATOMIC: core.sync.atomic.AtomicI32 =
    core.sync.atomic.AtomicI32.new(0);
type Guard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
@export_name("mettle_core_count")
extern "C" fn core_count(value: i32): i32 {
    var count = value
    {
        let guard = Guard(core.ptr.from_mut(count))
    }
    ATOMIC.store(count,core.sync.atomic.Ordering.Relaxed)
    let previous = ATOMIC.fetch_add(OFFSET,core.sync.atomic.Ordering.SeqCst)
    ATOMIC.load(core.sync.atomic.Ordering.Relaxed)
}
"""

FREESTANDING_DRIVER = """
extern int mettle_core_count(int);
int main(void) { return mettle_core_count(40) == 42 ? 0 : 1; }
"""


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

TRIVIAL_SOURCE = """
fn add(a: i32, b: i32): i32 { a + b }
fn main(): i32 { if add(1, 2) == 3 { 0 } else { 1 } }
"""
CLEANUP_SOURCE = """
type Guard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
fn run(value: i32): i32 {
    var count = value
    { let guard = Guard(core.ptr.from_mut(count)) }
    count
}
fn main(): i32 { if run(1) == 2 { 0 } else { 1 } }
"""
VARIADIC_SOURCE = """
unsafe extern "C" fn sum(count: i32, args: ...): i32 { args.arg<i32>() + count }
fn main(): i32 { 0 }
"""
INVALID_ASM_SOURCE = 'fn main() { unsafe { asm!("mettle_invalid_instruction",options(nostack)) }; 0 }\n'
VOLATILE_SOURCE = """
fn main(): i32 {
    var value = 40i64
    let pointer = core.ptr.from_mut(value)
    unsafe {
        pointer.write_volatile(41i64)
        let observed = pointer.read_volatile()
        pointer.write_volatile(observed + 1i64)
    }
    if value == 42i64 { 0 } else { 1 }
}
"""


def functions(text):
    return re.findall(r"^define [^\n]*?(@[^\s(]+)\(([^)]*)\)[^\n]*\{\n(.*?)^\}", text,
                      re.M | re.S)


def large_volatile_accesses(parameters, body):
    pointers = lambda text: re.findall(r"\bptr\b[^,%\n]*?(%[-\w.]+)", text)
    arguments = pointers(parameters)
    if len(arguments) != 1:
        raise AssertionError("large volatile probe requires one pointer parameter")
    lines = body.splitlines()
    slots = set()
    for line in lines:
        assigned = re.match(r"\s*(%[-\w.]+) = (getelementptr .*)", line)
        if assigned and pointers(assigned[2]) == arguments and re.search(
                r", i32 0, i32 0\s*$", assigned[2]):
            slots.add(assigned[1])
    aliases = set() if slots else {arguments[0]}
    while True:
        before = (len(aliases), len(slots))
        for line in lines:
            references = pointers(line)
            assigned = re.match(r"\s*(%[-\w.]+) = (.*)", line)
            if re.search(r"\bstore ptr\b", line) and len(references) == 2:
                if references[0] in aliases:
                    slots.add(references[1])
            if assigned and references:
                value, operation = assigned.groups()
                if (operation.startswith("load ptr") and references[-1] in slots) or (
                        operation.startswith(("getelementptr", "bitcast", "addrspacecast")) and
                        references[0] in aliases):
                    aliases.add(value)
        if before == (len(aliases), len(slots)):
            break
    reads = writes = False
    for line in lines:
        references = pointers(line)
        if not references:
            continue
        reads |= "load volatile" in line and references[-1] in aliases
        writes |= "store volatile" in line and references[-1] in aliases
        if re.search(r"@llvm\.mem(?:cpy|move|set)[^(]*\(", line) and re.search(
                r"\bi1 true\s*\)", line):
            writes |= references[0] in aliases
            if "@llvm.memset" not in line and len(references) >= 2:
                reads |= references[1] in aliases
    return reads, writes


def check_ir_shape(run, args, directory, evidence):
    def emit_llvm(name, source, *extra):
        path = directory / (name + ".mt")
        path.write_text(source)
        out = directory / (name + ".ll")
        run([args.compiler, "build", path, "--emit", "llvm", "-o", out, *extra])
        return out.read_text()

    # A function with no cleanup obligation must not pay for the unwind runtime.
    trivial = emit_llvm("shape-trivial", TRIVIAL_SOURCE, "--profile", "release")
    for forbidden in ("mettle_rt_run", "mettle_rt_replace", "mettle_rt_cleanup",
                      "mettle_rt_panicking", "invoke ", "landingpad"):
        if forbidden in trivial:
            raise AssertionError(f"Trivial release module uses {forbidden}:\n{trivial}")
    obj = directory / "shape-trivial.o"
    run([args.compiler, "build", directory / "shape-trivial.mt", "--emit", "object",
         "-o", obj, "--profile", "release"])
    undefined = run([args.cxx.with_name("llvm-nm"), "--undefined-only", obj]).stdout
    if "mettle_rt_run" in undefined or "mettle_rt_panicking" in undefined:
        raise AssertionError("Trivial release object links the unwind runtime:\n" + undefined)
    cleanup = emit_llvm("shape-cleanup", CLEANUP_SOURCE, "--profile", "release")
    if "mettle_rt_run" not in cleanup:
        raise AssertionError("A function with a destructor lost its cleanup frame")
    evidence["cases"].append({"name": "ir-shape-no-cleanup-no-unwind-runtime",
                              "phase": "backend"})

    # va_start and va_end of the incoming cursor must share one function.
    variadic = emit_llvm("shape-variadic", VARIADIC_SOURCE)
    starts = 0
    for name, parameters, body in functions(variadic):
        arguments = set(re.findall(r"%\d+(?=[,)]|$)", parameters))
        started = set(re.findall(r"llvm\.va_start\.p0\(ptr (%\w+)\)", body))
        starts += len(started)
        for cursor in re.findall(r"llvm\.va_end\.p0\(ptr (%\w+)\)", body):
            if cursor in arguments and cursor not in started:
                raise AssertionError(f"{name} ends a cursor it did not start:\n{variadic}")
        for cursor in started:
            if f"llvm.va_end.p0(ptr {cursor})" not in body:
                raise AssertionError(f"{name} starts a cursor it never ends:\n{variadic}")
    if starts != 1:
        raise AssertionError("Expected exactly one physical va_start:\n" + variadic)
    evidence["cases"].append({"name": "variadic-va-start-end-same-function",
                              "phase": "backend"})

    volatile = emit_llvm("shape-volatile", VOLATILE_SOURCE,
                         "--profile", "release")
    volatile_bodies = [
        body for _, _, body in functions(volatile)
        if "load volatile" in body or "store volatile" in body
    ]
    if not volatile_bodies:
        raise AssertionError("Optimized volatile accesses were removed:\n" + volatile)
    volatile_body = "\n".join(volatile_bodies)
    if "load volatile" not in volatile_body or "store volatile" not in volatile_body:
        raise AssertionError("Expected both volatile loads and stores:\n" + volatile_body)
    if re.search(r"\b(?:atomicrmw|cmpxchg|fence)\b", volatile_body):
        raise AssertionError("Volatile accesses were incorrectly made atomic:\n" +
                             volatile_body)
    evidence["cases"].append({"name": "volatile-accesses-remain-nonsynchronizing",
                              "phase": "backend"})

    large_path = Path(__file__).resolve().parents[1] / "source" / "run" / "machine-large-volatile-pointer-accesses.mt"
    for profile in ("debug", "release"):
        large = emit_llvm("shape-large-volatile-" + profile, large_path.read_text(),
                          "--profile", profile)
        bodies = [(parameters, body) for name, parameters, body in functions(large)
                  if name.strip('@"') == "mettle.abi.volatile_large.body"]
        if len(bodies) != 1 or large_volatile_accesses(*bodies[0]) != (True, True):
            raise AssertionError("Large volatile write or unused read was lost:\n" + large)
        if re.search(r"\b(?:atomicrmw|cmpxchg|fence)\b|\b(?:load|store)\s+atomic\b",
                     bodies[0][1]):
            raise AssertionError("Large volatile accesses became synchronizing:\n" + large)
        evidence["cases"].append({"name": "large-volatile-write-and-unused-read",
                                  "phase": "backend", "profile": profile,
                                  "source_sha256": digest(large_path)})

    # The module data layout is the target machine's, not a hand-written one.
    empty = directory / "empty.c"
    empty.write_text("")
    path = directory / "layout.mt"
    path.write_text(TRIVIAL_SOURCE)
    for triple in ("x86_64-unknown-linux-gnu", "arm64-apple-macosx15.0"):
        expected = run([args.cxx.with_name("clang"), "-S", "-emit-llvm", "-x", "c", empty,
                        "--target=" + triple, "-o", directory / "layout.ll"])
        reference = re.search(r'target datalayout = "([^"]*)"',
                              (directory / "layout.ll").read_text()).group(1)
        out = directory / "layout-module.ll"
        run([args.compiler, "build", path, "--emit", "llvm", "--target", triple, "-o", out])
        actual = re.search(r'target datalayout = "([^"]*)"', out.read_text()).group(1)
        if actual != reference:
            raise AssertionError(f"{triple}: data layout {actual!r} != target {reference!r}")
    evidence["cases"].append({"name": "data-layout-from-target-machine", "phase": "backend"})


def check_driver_outputs(run, args, directory, evidence):
    linkage = directory / "explicit-library-linkage"
    linkage.mkdir(exist_ok=True)
    companion = linkage / "probe.c"
    companion.write_text("int mettle_linkage_probe(int value) { return value + 2; }\n")
    obj = linkage / "probe.o"
    archive = linkage / "libmettle_linkage_probe.a"
    run([args.cxx.with_name("clang"), "-std=c11", "-c", companion, "-o", obj])
    run([args.cxx.with_name("llvm-ar"), "rcs", archive, obj])
    search = {"LIBRARY_PATH": os.pathsep.join(filter(None, (
        str(linkage), os.environ.get("LIBRARY_PATH"))))}
    declaration = ('extern "C" { unsafe fn mettle_linkage_probe(value:i32):i32; }\n'
                   'fn main():i32 { if unsafe { mettle_linkage_probe(40) } == 42 '
                   '{ 0 } else { 1 } }\n')
    source = linkage / "main.mt"
    for profile in ("debug", "release"):
        output = linkage / ("program-" + profile)
        source.write_text('@link("mettle_linkage_probe")\n' + declaration)
        run([args.compiler, "build", source, "--profile", profile, "-o", output],
            environment=search)
        run([output])
        source.write_text(declaration)
        output.write_bytes(b"preserve linkage output")
        result = run([args.compiler, "build", source, "--profile", profile,
                      "-o", output], expected=1, environment=search)
        if ("error[link]" not in result.stderr or
                "mettle_linkage_probe" not in result.stderr or
                output.read_bytes() != b"preserve linkage output"):
            raise AssertionError("Missing @link did not preserve the intended link failure:\n" +
                                 result.stderr)
        evidence["cases"].append({"name": "explicit-library-linkage-and-missing-link-control",
                                  "phase": "link", "profile": profile,
                                  "archive_sha256": digest(archive)})

    path = directory / "driver-output.mt"
    path.write_text(TRIVIAL_SOURCE)
    for emission in ("executable", "object", "llvm", "ir"):
        missing = directory / "missing-directory" / "out"
        result = run([args.compiler, "build", path, "--emit", emission, "-o", missing],
                     expected=1)
        if "error[io]" not in result.stderr or missing.parent.exists():
            raise AssertionError(f"{emission}: unclear or partial output failure:\n{result.stderr}")
        target = directory / "output-is-a-directory"
        target.mkdir(exist_ok=True)
        result = run([args.compiler, "build", path, "--emit", emission, "-o", target],
                     expected=1)
        leftovers = [entry.name for entry in directory.iterdir() if ".mettle-" in entry.name
                     or ".object-" in entry.name]
        if "error[io]" not in result.stderr or leftovers:
            raise AssertionError(f"{emission}: failed publish left {leftovers}:\n{result.stderr}")
    evidence["cases"].append({"name": "driver-output-write-failures", "phase": "io"})

    # An executable for a target without the runtime fails before code generation
    # (this source would otherwise be rejected by the target assembler).
    rejected = directory / "early-link.mt"
    rejected.write_text(INVALID_ASM_SOURCE)
    output = directory / "early-link.out"
    output.write_bytes(b"preserve existing output")
    result = run([args.compiler, "build", rejected, "--emit", "executable", "--target",
                  "x86_64-unknown-linux-gnu" if ARM64 else "arm64-apple-macosx15.0",
                  "-o", output], expected=1)
    if "error[link]" not in result.stderr or "error[assembly]" in result.stderr:
        raise AssertionError("Unsupported executable target was not rejected early:\n" + result.stderr)
    if output.read_bytes() != b"preserve existing output":
        raise AssertionError("Early link rejection damaged an existing output")
    evidence["cases"].append({"name": "executable-target-rejected-before-codegen",
                              "phase": "link"})

    if platform.system() == "Darwin":
        # The default target uses the documented deployment target and the
        # resulting executable links without deployment-version warnings.
        out = directory / "default-target.ll"
        run([args.compiler, "build", path, "--emit", "llvm", "-o", out])
        triple = re.search(r'target triple = "([^"]*)"', out.read_text()).group(1)
        if not re.fullmatch(r"arm64-apple-macosx\d+\.\d+(\.\d+)?", triple):
            raise AssertionError("Default target embeds a kernel version: " + triple)
        program = directory / "default-target"
        result = run([args.compiler, "build", path, "-o", program])
        if result.stderr.strip():
            raise AssertionError("Linking emitted diagnostics:\n" + result.stderr)
        run([program])
        evidence["cases"].append({"name": "darwin-default-target-links-cleanly",
                                  "phase": "link"})


SOURCES["c-memory-represented-aggregate-snapshots"] = (
    Path(__file__).with_name("foreign_storage.mt").read_text())

SOURCES["atomic-bool-not-pointer-masks"] = (
    Path(__file__).resolve().parents[1] / "source" / "run" /
    "machine-atomic-bool-not-pointer-masks.mt").read_text()

SOURCES["c-thread-atomic-bool-not-pointer-masks"] = (
    Path(__file__).with_name("atomic_bitwise_contention.mt").read_text())

if platform.system() == "Linux":
    SOURCES["heap-sorted-no-global-allocation"] = (
        Path(__file__).with_name("heap_sorted_no_global_allocation.mt").read_text())
    SOURCES["once-force-waits-through-poison"] = (
        Path(__file__).with_name("once_force_wait.mt").read_text())


def run_scheduled(args):
    directory = args.directory.resolve()
    if args.shard_count > 1:
        directory /= f"shard-{args.shard_index}"
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"status": "in_progress", "system": platform.platform(),
                "compiler_sha256": digest(args.compiler),
                "runtime_sha256": digest(args.runtime),
                "callbacks_sha256": digest(args.callbacks),
                "commands": [], "cases": [], "workers": [], "errors": []}
    tasks = [(name, profile) for name in SOURCES
             if (not args.case or name in args.case) and name.startswith(args.case_prefix)
             for profile in ("debug", "release")]
    tasks += [(name, None) for name in MACHINE_REJECTIONS
              if (not args.case or name in args.case) and name.startswith(args.case_prefix)]
    name = "machine-target-freestanding-no-services"
    if (not args.case or name in args.case) and name.startswith(args.case_prefix):
        tasks += [(name, profile) for profile in ("debug", "release")]
    if not args.case and not args.case_prefix:
        tasks.append(("supplemental", None))
    if not tasks:
        evidence["status"] = "failed"
        evidence["errors"] = ["no machine cases selected"]
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        raise ValueError("no machine cases selected")
    key = lambda task: task[0] + (":" + task[1] if task[1] else "")
    tasks = scheduling.select(tasks, key, args.shard_index, args.shard_count)

    def execute(task):
        name, profile = task
        target = directory / name / (profile or "checks")
        command = [sys.executable, Path(__file__).resolve(), args.compiler, args.cxx,
                   args.runtime, args.callbacks, target, "--worker"]
        command += ["--supplemental"] if name == "supplemental" else ["--case", name]
        if profile:
            command += ["--profile", profile]
        if args.sysroot:
            command += ["--sysroot", args.sysroot]
        if args.sanitizers:
            command += ["--sanitizers"]
        for argument in args.link_arg:
            command += ["--link-arg=" + argument]
        result = processes.run(list(map(str, command)), text=True, capture_output=True)
        try:
            child = json.loads((target / "evidence.json").read_text())
        except (OSError, ValueError):
            child = {"commands": [], "cases": []}
        child["worker"] = {"command": list(map(str, command)),
                           "exit_status": result.returncode,
                           "stdout": result.stdout, "stderr": result.stderr}
        if result.returncode:
            child["error"] = result.stdout + result.stderr
        return child

    for task, child, error, elapsed in scheduling.run(
            tasks, execute, directory, args.jobs, key):
        if child is not None:
            evidence["commands"] += child["commands"]
            evidence["cases"] += child["cases"]
            evidence["workers"].append({"name": key(task), "elapsed_seconds": elapsed,
                                        **child["worker"]})
            error = child.get("error", error)
        if error:
            evidence["errors"].append(f"{key(task)}: {error}")
    evidence["status"] = "failed" if evidence["errors"] else "passed"
    (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    if evidence["errors"]:
        raise AssertionError("\n".join(evidence["errors"]))
    print(f"C interop: {len(tasks)} independent units passed with {args.jobs} workers")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("cxx", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("callbacks", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--sysroot")
    parser.add_argument("--sanitizers", action="store_true")
    parser.add_argument("--link-arg", action="append", default=[])
    parser.add_argument("--case", action="append",
                        choices=(*SOURCES, *MACHINE_REJECTIONS,
                                 "machine-target-freestanding-no-services"), default=[])
    parser.add_argument("--case-prefix", default="")
    scheduling.arguments(parser, 4)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--supplemental", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--profile", action="append", choices=("debug", "release"),
                        help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if not args.worker:
        return run_scheduled(args)
    if args.supplemental:
        args.case = ["supplemental"]
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"status": "in_progress", "system": platform.platform(),
                "compiler_sha256": digest(args.compiler),
                "runtime_sha256": digest(args.runtime),
                "callbacks_sha256": digest(args.callbacks),
                "commands": [], "cases": []}

    def run(command, expected=0, environment=None):
        begin = time.perf_counter()
        result = processes.run(list(map(str, command)), text=True, capture_output=True,
                                env=None if environment is None else {**os.environ, **environment})
        evidence["commands"].append({"command": list(map(str, command)),
                                     "exit_status": result.returncode,
                                     "elapsed_seconds": time.perf_counter() - begin,
                                     "stdout": result.stdout, "stderr": result.stderr})
        if environment is not None:
            evidence["commands"][-1]["environment_overrides"] = environment
        if result.returncode != expected:
            raise AssertionError(f"{command!r}: exit {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")
        return result

    try:
        selected_darwin_cases = [
            name for name in DARWIN_ARM64_SOURCES
            if (not args.case or name in args.case) and name.startswith(args.case_prefix)
        ]
        darwin_callbacks_object = None
        if selected_darwin_cases:
            darwin_callbacks_object = directory / "machine_callbacks-darwin-arm64.o"
            command = [
                args.cxx.with_name("clang"), "-std=c11", "-Wall", "-Wextra",
                "-Wpedantic", "-Werror", "-DMETTLE_DARWIN_PROBE=1",
                "--target=arm64-apple-macosx15.0",
                "-c", Path(__file__).with_name("machine_callbacks.c"),
                "-o", darwin_callbacks_object,
            ]
            if args.sysroot:
                command.append("--sysroot=" + args.sysroot)
            run(command)
        for name, source in SOURCES.items():
            if (args.case and name not in args.case) or not name.startswith(args.case_prefix):
                continue
            path = directory / (name + ".mt")
            path.write_text(source)
            libraries = [args.callbacks, args.runtime]
            if name in DARWIN_ARM64_SOURCES:
                libraries = [
                    darwin_callbacks_object, args.callbacks, args.runtime
                ]
            if name in ("machine-target-guarded-wide-vector-c-physical-abi",
                        "machine-target-wide-vector-aggregate-c-abi"):
                vector_object = directory / (name + "-fixture.o")
                fixture = ("machine_wide_aggregate.c"
                           if name == "machine-target-wide-vector-aggregate-c-abi"
                           else "machine_vectors.c")
                command = [args.cxx.with_name("clang"), "-std=c11", "-mavx",
                           "-c", Path(__file__).with_name(fixture),
                           "-o", vector_object]
                if args.sysroot:
                    command.append("--sysroot=" + args.sysroot)
                if args.sanitizers:
                    command.append("-fsanitize=address,undefined")
                run(command)
                libraries.insert(0, vector_object)
            if name == "c-memory-represented-aggregate-snapshots":
                storage_object = directory / "foreign_storage.o"
                command = [args.cxx.with_name("clang"), "-std=c11",
                           "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                           "-c", Path(__file__).with_name("foreign_storage.c"),
                           "-o", storage_object]
                if args.sysroot:
                    command.append("--sysroot=" + args.sysroot)
                if args.sanitizers:
                    command.append("-fsanitize=address,undefined")
                run(command)
                libraries.insert(0, storage_object)
            if name in ("heap-sorted-no-global-allocation",
                        "once-force-waits-through-poison"):
                fixture = Path(__file__).with_name(
                    "once_force_wait.cpp" if name == "once-force-waits-through-poison"
                    else "heap_sorted_no_global_allocation.c")
                allocation_object = directory / (fixture.stem + ".o")
                cpp = fixture.suffix == ".cpp"
                command = [args.cxx if cpp else args.cxx.with_name("clang"),
                           "-std=c++20" if cpp else "-std=c11",
                           "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                           "-c", fixture,
                           "-o", allocation_object]
                if args.sysroot:
                    command.append("--sysroot=" + args.sysroot)
                if args.sanitizers:
                    command.append("-fsanitize=address,undefined")
                run(command)
                libraries.insert(0, allocation_object)
            for profile in args.profile or ("debug", "release"):
                obj = directory / (name + "-" + profile + ".o")
                program = directory / (name + "-" + profile)
                if name == "atomic-bool-not-pointer-masks":
                    ir = obj.with_suffix(".ll")
                    run([args.compiler, "build", path, "--emit", "llvm", "-o", ir,
                         "--profile", profile])
                    if profile == "debug":
                        text = "\n".join(
                            body for function, _, body in functions(ir.read_text())
                            if function.strip('@"') in ("mettle.check", "mettle.check.body"))
                        for pattern in (r"load atomic ptr",
                                        r"cmpxchg ptr [^,\n]+, ptr [^,\n]+, ptr ",
                                        r"getelementptr i8, ptr ",
                                        r"atomicrmw xor ptr [^,\n]+, i8 1 "):
                            if not re.search(pattern, text):
                                raise AssertionError(
                                    "Atomic pointer/bool representation lost " + pattern)
                        if "inttoptr" in text:
                            raise AssertionError(
                                "Atomic pointer mask reconstructed an address-only pointer")
                    run([args.cxx, "-x", "ir", "-c", ir, "-o", obj])
                else:
                    run([args.compiler, "build", path, "--emit", "object", "-o", obj,
                         "--profile", profile])
                volatile_disassembly = None
                if name == "darwin-arm64-volatile-c-observer" and profile == "release":
                    volatile_disassembly = run([
                        args.cxx.with_name("llvm-objdump"), "-d", obj
                    ]).stdout
                    body = re.search(
                        r"<_mettle\.abi\.volatile_update\.body>:\n(.*?)(?=\n\n|\n[0-9a-fA-F]+ <)",
                        volatile_disassembly, re.S)
                    if body is None:
                        raise AssertionError(
                            "Release object has no volatile_update body:\n" +
                            volatile_disassembly)
                    instructions = body.group(1)
                    loads = re.findall(r"\bldr\s+w\d+,\s*\[x\d+\]", instructions)
                    stores = re.findall(r"\bstr\s+w\d+,\s*\[x\d+\]", instructions)
                    if len(loads) < 1 or len(stores) < 2:
                        raise AssertionError(
                            "Release volatile callback lost load/store instructions:\n" +
                            instructions)
                    if re.search(r"\b(?:ldar|stlr|ldaxr|stlxr|cas|swp|dmb)\b",
                                 instructions):
                        raise AssertionError(
                            "Volatile callback was lowered as synchronization:\n" +
                            instructions)
                command = [args.cxx, obj, *libraries, "-o", program]
                if name == "heap-sorted-no-global-allocation":
                    command.extend(["-Wl,--wrap=mettle_rt_alloc",
                                    "-Wl,--wrap=mettle_rt_realloc"])
                if name == "once-force-waits-through-poison":
                    command.append("-Wl,--wrap=mettle_rt_thread_yield")
                command.extend(args.link_arg)
                if args.sysroot:
                    command.append("--sysroot=" + args.sysroot)
                if args.sanitizers:
                    command.append("-fsanitize=address,undefined")
                run(command)
                run([program])
                case = {"name": name, "profile": profile,
                        "source_sha256": digest(path),
                        "object_sha256": digest(obj),
                        "program_sha256": digest(program)}
                if volatile_disassembly is not None:
                    case["release_volatile_instruction_counts"] = {
                        "loads": len(loads), "stores": len(stores)}
                if name in DARWIN_ARM64_SOURCES:
                    case["c_fixture_sha256"] = digest(
                        Path(__file__).with_name("machine_callbacks.c"))
                    case["c_object_sha256"] = digest(darwin_callbacks_object)
                if name == "c-memory-represented-aggregate-snapshots":
                    case["c_fixture_sha256"] = digest(
                        Path(__file__).with_name("foreign_storage.c"))
                    case["c_object_sha256"] = digest(storage_object)
                if name in ("heap-sorted-no-global-allocation",
                            "once-force-waits-through-poison"):
                    case["c_fixture_sha256"] = digest(fixture)
                    case["c_object_sha256"] = digest(allocation_object)
                evidence["cases"].append(case)
        for name, source in MACHINE_REJECTIONS.items():
            if (args.case and name not in args.case) or not name.startswith(args.case_prefix):
                continue
            path = directory / (name + ".mt")
            path.write_text(source)
            obj = directory / (name + ".o")
            obj.write_bytes(b"preserve existing object")
            result = run([args.compiler, "build", path, "--emit", "object",
                          "-o", obj], expected=1)
            if "error[assembly]" not in result.stderr:
                raise AssertionError("Wrong assembler rejection:\n" + result.stderr)
            if obj.read_bytes() != b"preserve existing object":
                raise AssertionError("Assembler failure damaged an existing object")
            evidence["cases"].append({"name": name, "phase": "assembly",
                                      "source_sha256": digest(path)})
        if (not args.case or "machine-target-freestanding-no-services" in args.case) and \
                "machine-target-freestanding-no-services".startswith(args.case_prefix):
            name = "machine-target-freestanding-no-services"
            path = directory / (name + ".mt")
            path.write_text(MACHINE_FREESTANDING_SOURCE)
            harness = directory / (name + ".c")
            harness.write_text(FREESTANDING_DRIVER)
            harness_object = directory / (name + "-driver.o")
            command = [args.cxx.with_name("clang"), "-std=c11", "-c",
                       harness, "-o", harness_object]
            if args.sysroot:
                command.append("--sysroot=" + args.sysroot)
            run(command)
            for profile in args.profile or ("debug", "release"):
                obj = directory / (name + "-" + profile + ".o")
                program = directory / (name + "-" + profile)
                run([args.compiler, "build", path, "--freestanding", "--emit",
                     "object", "-o", obj, "--profile", profile])
                symbols = run([args.cxx.with_name("llvm-nm"),
                               "--undefined-only", obj]).stdout
                if symbols.strip():
                    raise AssertionError("Core assembly/SIMD acquired services:\n" + symbols)
                command = [args.cxx, obj, harness_object, "-o", program, *args.link_arg]
                if args.sysroot:
                    command.append("--sysroot=" + args.sysroot)
                if args.sanitizers:
                    command.append("-fsanitize=address,undefined")
                run(command)
                run([program])
                evidence["cases"].append({"name": name, "profile": profile,
                                          "source_sha256": digest(path),
                                          "object_sha256": digest(obj),
                                          "program_sha256": digest(program),
                                          "undefined_symbols": []})
        if not args.supplemental:
            if not evidence["cases"]:
                raise ValueError("no machine cases selected")
            evidence["status"] = "passed"
            profiles = sum("profile" in case for case in evidence["cases"])
            rejected = len(evidence["cases"]) - profiles
            print(f"Focused machine boundary: {profiles} round trips, {rejected} rejections passed")
            return
        path = directory / "freestanding.mt"
        path.write_text(FREESTANDING_SOURCE)
        harness = directory / "freestanding_driver.c"
        harness.write_text(FREESTANDING_DRIVER)
        harness_object = directory / "freestanding_driver.o"
        clang = args.cxx.with_name("clang")
        command = [clang, "-std=c11", "-c", harness, "-o", harness_object]
        if args.sysroot:
            command.append("--sysroot=" + args.sysroot)
        run(command)
        for profile in ("debug", "release"):
            obj = directory / ("freestanding-" + profile + ".o")
            program = directory / ("freestanding-" + profile)
            run([args.compiler, "build", path, "--freestanding", "--emit", "object",
                 "-o", obj, "--profile", profile])
            command = [args.cxx.with_name("llvm-nm"), "--undefined-only", obj]
            result = processes.run(list(map(str, command)), text=True, capture_output=True, check=True)
            if result.stdout.strip():
                raise AssertionError("Freestanding core has undeclared runtime dependencies:\n" +
                                     result.stdout)
            evidence["commands"].append({"command": list(map(str, command)),
                                         "exit_status": result.returncode,
                                         "stdout": result.stdout, "stderr": result.stderr})
            command = [args.cxx, obj, harness_object, "-o", program, *args.link_arg]
            if args.sysroot:
                command.append("--sysroot=" + args.sysroot)
            run(command)
            run([program])
            evidence["cases"].append({"name": "freestanding-no-hosted-runtime",
                                      "profile": profile, "source_sha256": digest(path),
                                      "object_sha256": digest(obj),
                                      "program_sha256": digest(program),
                                      "undefined_symbols": []})
        rejected = {
            "direct-unwind": 'extern "C-unwind" fn callback(): i32 { 42 }',
            "indirect-unwind": """
extern "C" fn invoke(callback: unsafe extern "C-unwind" fn(): i32): i32 {
    unsafe { callback() }
}
""",
        }
        for name, source in rejected.items():
            path = directory / (name + ".mt")
            path.write_text(source)
            obj = directory / (name + ".o")
            obj.write_bytes(b"preserve existing object")
            result = run([args.compiler, "build", path, "--freestanding",
                          "--emit", "object", "-o", obj], expected=1)
            if "error[feature]" not in result.stderr or "foreign unwind" not in result.stderr:
                raise AssertionError("Wrong freestanding foreign-unwind rejection:\n" + result.stderr)
            if obj.read_bytes() != b"preserve existing object":
                raise AssertionError("Rejected foreign unwind damaged an existing object")
            evidence["cases"].append({"name": "freestanding-reject-" + name,
                                      "source_sha256": digest(path),
                                      "phase": "feature"})
        check_ir_shape(run, args, directory, evidence)
        check_driver_outputs(run, args, directory, evidence)
        path = directory / "unsupported-indirect-abi.mt"
        path.write_text("""
fn invoke(callback: unsafe extern "C" fn(): i32): i32 {
    unsafe { callback() }
}
""")
        obj = directory / "unsupported-indirect-abi.o"
        result = run([args.compiler, "build", path, "--freestanding",
                      "--emit", "object", "--target", "x86_64-pc-windows-msvc",
                      "-o", obj], expected=1)
        if "error[feature]" not in result.stderr or not any(
                gate in result.stderr
                for gate in ("C ABI implementation", "source compilation supports")):
            raise AssertionError("Indirect foreign call bypassed the target ABI gate:\n" + result.stderr)
        if obj.exists():
            raise AssertionError("Unsupported indirect ABI published an object")
        evidence["cases"].append({"name": "reject-unsupported-indirect-abi",
                                  "source_sha256": digest(path),
                                  "phase": "feature"})
        evidence["status"] = "passed"
    except BaseException as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    round_trips = sum("profile" in case for case in evidence["cases"])
    rejections = len(evidence["cases"]) - round_trips
    print(f"C interop: {round_trips} source/profile round trips, "
          f"{rejections} intended rejections passed")


if __name__ == "__main__":
    main()
