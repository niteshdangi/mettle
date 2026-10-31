#!/usr/bin/env python3
"""Execute Mettle/C layout, call, callback, promotion and unwind round trips."""

import argparse
import hashlib
import json
import platform
import re
import subprocess
from pathlib import Path


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

DARWIN_ARM64_SOURCES = ({
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
} if DARWIN_ARM64 else {})

SOURCES = {
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
       integers == 55i64 && pair.first + pair.second == 42 &&
       reals == 55.0f64 && floats.first + floats.second == 42.0f32 &&
       large.first + large.second + large.third == 42i64 &&
       packed.first as i32 + packed.second == 42 { 42 } else { -1 }
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
    unsafe fn mettle_c_union(value: take Bits): Bits;
    unsafe fn mettle_c_double_union(value: take Doubles, increment: f64): Doubles;
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
    let pair = unsafe { mettle_c_pair(Pair(20,20)) }
    let exported = unsafe { mettle_c_call_export(Pair(20,20)) }
    let floats = unsafe { mettle_c_floats(Floats(20.0f32,20.0f32)) }
    let mixed = unsafe { mettle_c_mixed(Mixed(20.0f64,20)) }
    let large = unsafe { mettle_c_large(Large(10i64,11i64,18i64)) }
    let packed = unsafe { mettle_c_packed(Packed(20u8,20)) }
    let called = unsafe { mettle_c_callback(callback,context,2) }
    let integer = unsafe { mettle_c_integer(-2i8,255u8,-211i64) }
    let size = unsafe { mettle_c_pair_size() }
    let offset = unsafe { mettle_c_packed_offset() }
    if pair.first + pair.second == 42 &&
       exported.first + exported.second == 42 &&
       floats.first + floats.second == 42.0f32 &&
       mixed.first + mixed.second as f64 == 42.0f64 &&
       large.first + large.second + large.third == 42i64 &&
       packed.first as i32 + packed.second == 42 &&
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


def functions(text):
    return re.findall(r"^define [^\n]*?(@[^\s(]+)\(([^)]*)\)[^\n]*\{\n(.*?)^\}", text,
                      re.M | re.S)


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("cxx", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("callbacks", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--sysroot")
    parser.add_argument("--sanitizers", action="store_true")
    parser.add_argument("--link-arg", action="append", default=[])
    parser.add_argument("--case", action="append", choices=tuple(SOURCES), default=[])
    parser.add_argument("--case-prefix", default="")
    args = parser.parse_args()
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"status": "in_progress", "system": platform.platform(),
                "compiler_sha256": digest(args.compiler),
                "runtime_sha256": digest(args.runtime),
                "callbacks_sha256": digest(args.callbacks),
                "commands": [], "cases": []}

    def run(command, expected=0):
        result = subprocess.run(list(map(str, command)), text=True, capture_output=True,
                                timeout=60)
        evidence["commands"].append({"command": list(map(str, command)),
                                     "exit_status": result.returncode,
                                     "stdout": result.stdout, "stderr": result.stderr})
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
                libraries = [darwin_callbacks_object, args.runtime]
            if name == "machine-target-guarded-wide-vector-c-physical-abi":
                vector_object = directory / "machine_vectors.o"
                command = [args.cxx.with_name("clang"), "-std=c11", "-mavx",
                           "-c", Path(__file__).with_name("machine_vectors.c"),
                           "-o", vector_object]
                if args.sysroot:
                    command.append("--sysroot=" + args.sysroot)
                if args.sanitizers:
                    command.append("-fsanitize=address,undefined")
                run(command)
                libraries.insert(0, vector_object)
            for profile in ("debug", "release"):
                obj = directory / (name + "-" + profile + ".o")
                program = directory / (name + "-" + profile)
                run([args.compiler, "build", path, "--emit", "object", "-o", obj,
                     "--profile", profile])
                command = [args.cxx, obj, *libraries, "-o", program]
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
                if name in DARWIN_ARM64_SOURCES:
                    case["c_fixture_sha256"] = digest(
                        Path(__file__).with_name("machine_callbacks.c"))
                    case["c_object_sha256"] = digest(darwin_callbacks_object)
                evidence["cases"].append(case)
        for name, source in MACHINE_REJECTIONS.items():
            if args.case or not name.startswith(args.case_prefix):
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
        if not args.case and "machine-target-freestanding-no-services".startswith(args.case_prefix):
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
            for profile in ("debug", "release"):
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
        if args.case or args.case_prefix:
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
            result = subprocess.run(list(map(str, command)), text=True, capture_output=True,
                                    timeout=30, check=True)
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
    finally:
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    round_trips = sum("profile" in case for case in evidence["cases"])
    rejections = len(evidence["cases"]) - round_trips
    print(f"C interop: {round_trips} source/profile round trips, "
          f"{rejections} intended rejections passed")


if __name__ == "__main__":
    main()
