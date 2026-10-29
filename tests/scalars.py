#!/usr/bin/env python3
"""Execute scalar, product and ownership cases with the existing runner."""

import hashlib
import concurrent.futures
import json
import platform
import re
import resource
import subprocess
import sys
import time
from pathlib import Path


ARM64 = globals().get("TARGET_ARCH", platform.machine()).lower() in ("arm64", "aarch64")
ASM_ADD = "add {out:w}, {left:w}, {right:w}" if ARM64 else "mov {out:e}, {left:e}; add {out:e}, {right:e}"
ASM_MOVE = "mov {out:w}, {input:w}" if ARM64 else "mov {out:e}, {input:e}"
MACHINE_POSITIVE = {
    "machine-asm-required-full-width-and-generic-constants": """
static OFFSET: i128 = (1i128 << 80) + 42;
unsafe fn answer<const N:i64>(value:i32):i32 {
    var result = value
    asm!(\"""" + ("add {value:w}, {value:w}, #{amount}" if ARM64 else
                   "add {value:e}, {amount}") + """\",
         value = inout(reg) result, amount = const N,
         options(nomem,nostack))
    asm!(\"""" + ("add {value:w}, {value:w}, #{amount}" if ARM64 else
                   "add {value:e}, {amount}") + """\",
         value = inout(reg) result, amount = const OFFSET - (1i128 << 80),
         options(nomem,nostack))
    result
}
fn main() { if unsafe { answer::<1i64>(-1) } == 42 { 0 } else { 1 } }
""",
    "machine-asm-static-symbol-global-and-naked-entry": """
static VALUE: i32 = 42;
extern "C" { static ADDRESS: ptr<read i32>; }
global_asm!(".data\\n.globl {address}\\n.p2align 3\\n{address}:\\n.quad {value}\\n.text",
            address = sym ADDRESS, value = sym VALUE)
unsafe extern "C" fn read_value():i32 { *ADDRESS }
@naked
unsafe extern "C" fn answer():i32 {
    naked_asm!(\"""" + ("b {callee}" if ARM64 else "jmp {callee}") + """\",
               callee = sym read_value)
}
fn main() {
    var pointer: ptr<read i32> = core::ptr::null::<i32>()
    unsafe {
        asm!(\"""" + ("adrp {out}, {value}@PAGE\\nadd {out}, {out}, {value}@PAGEOFF"
                       if ARM64 else "lea {out}, [rip + {value}]") + """\",
             out = out(reg) pointer, value = sym VALUE, options(nomem,nostack))
        if *pointer == 42 && answer() == 42 { 0 } else { 1 }
    }
}
""",
    "machine-target-vector-load-store-and-instruction-overflow": (
        """
fn main() {
    var input = [20,22,23,2147483647]
    var output = [0,0,0,0]
    let source = core::ptr::from_mut(input[0])
    let destination = core::ptr::from_mut(output[0])
    unsafe {
        let vector = core::arch::aarch64::vld1q_s32(source)
        let sum = core::arch::aarch64::vaddq_s32(
            vector,core::arch::aarch64::vdupq_n_s32(22))
        core::arch::aarch64::vst1q_s32(destination,sum)
    }
    if input[0] == 20 && output[0] == 42 && output[3] == -2147483627 { 0 } else { 1 }
}
""" if ARM64 else """
fn main() {
    var input = [20,22,23,2147483647]
    var output = [0,0,0,0]
    let source = core::ptr::from_mut(input).cast::<core::arch::x86_64::__m128i>()
    let destination = core::ptr::from_mut(output).cast::<core::arch::x86_64::__m128i>()
    unsafe {
        let vector = core::arch::x86_64::_mm_loadu_si128(source)
        let sum = core::arch::x86_64::_mm_add_epi32(
            vector,core::arch::x86_64::_mm_set1_epi32(22))
        core::arch::x86_64::_mm_storeu_si128(destination,sum)
    }
    if input[0] == 20 && output[0] == 42 && output[3] == -2147483627 { 0 } else { 1 }
}
"""),
    **({
        "machine-target-guarded-wide-vector-function-abi": """
@target_feature("avx2")
unsafe fn identity(value:core::arch::x86_64::__m256i):core::arch::x86_64::__m256i {
    core::arch::x86_64::_mm256_add_epi32(
        plain(value,core::arch::x86_64::_mm256_set1_epi32(41)),
        core::arch::x86_64::_mm256_set1_epi32(1))
}
fn plain<T:Copy>(first:T,second:T):T { second }
@target_feature("avx")
unsafe extern "C" fn foreign(value:core::arch::x86_64::__m256i):core::arch::x86_64::__m256i {
    value
}
fn main() {
    if is_x86_feature_detected!("avx2") {
        let value = unsafe { core::arch::x86_64::_mm256_set1_epi32(42) }
        let callback = identity
        let returned = unsafe { foreign(callback(value)) }
        let lanes = unsafe { core::mem::transmute::<[i32;8]>(returned) }
        if lanes[0] == 42 && lanes[7] == 42 { 0 } else { 1 }
    } else { 0 }
}
""",
        "machine-target-integer-vector-construction-requires-avx-not-avx2": """
fn main() {
    if is_x86_feature_detected!("avx") {
        let vector = unsafe { core::arch::x86_64::_mm256_set1_epi32(42) }
        let lanes = unsafe { core::mem::transmute::<[i32;8]>(vector) }
        if lanes[0] == 42 && lanes[7] == 42 { 0 } else { 1 }
    } else { 0 }
}
""",
        "machine-asm-wide-integer-vector-register-roundtrip": """
fn main() {
    let input = 340282366920938463463374607431768211413u128
    var output = 0u128
    unsafe {
        asm!("movdqa {out:x}, {input:x}",out = out(xmm_reg) output,
             input = in(xmm_reg) input,options(pure,nomem,nostack,preserves_flags))
    }
    if input == output { 0 } else { 1 }
}
""",
    } if not ARM64 else {}),
    "machine-target-feature-default-thunk-contract": (
        """
@target_feature("neon")
unsafe fn answer(value:i32 = unsafe {
    let vector = core::arch::aarch64::vdupq_n_s32(42)
    core::arch::aarch64::vgetq_lane_s32(vector,0)
}):i32 { value }
fn main() {
    if is_aarch64_feature_detected!("neon") {
        if unsafe { answer() } == 42 { 0 } else { 1 }
    } else { 1 }
}
""" if ARM64 else """
@target_feature("avx2")
unsafe fn answer(value:i32 = unsafe {
    let vector = core::arch::x86_64::_mm256_set1_epi32(42)
    let lanes = core::mem::transmute::<[i32;8]>(vector)
    lanes[0]
}):i32 { value }
fn main() {
    if is_x86_feature_detected!("avx2") {
        if unsafe { answer() } == 42 { 0 } else { 1 }
    } else { 0 }
}
"""),
    "machine-target-preserves-distinct-vector-shapes-through-generics": (
        """
fn identity<T:Copy>(value:T):T { value }
fn main() {
    unsafe {
        let short = identity(core::arch::aarch64::vdup_n_s32(42))
        let wide = identity(core::arch::aarch64::vdupq_n_s32(20))
        if core::arch::aarch64::vget_lane_s32(short,1) == 42 &&
           core::arch::aarch64::vgetq_lane_s32(wide,3) == 20 &&
           core::mem::size_of::<core::arch::aarch64::int32x2_t>() == 8usize {
            0
        } else { 1 }
    }
}
""" if ARM64 else """
fn identity<T:Copy>(value:T):T { value }
fn main() {
    unsafe {
        let floating = identity(core::arch::x86_64::_mm_set1_ps(1.25f32))
        let integer = identity(core::arch::x86_64::_mm_set1_epi32(42))
        let floats = core::mem::transmute::<[f32;4]>(floating)
        let ints = core::mem::transmute::<[i32;4]>(integer)
        if floats[2] == 1.25f32 && ints[3] == 42 { 0 } else { 1 }
    }
}
"""),
    "machine-asm-float-bits-and-pointer-inout": """
fn main() {
    var floating = 0.0f64
    var storage = 42
    let pointer = core::ptr::from_mut(storage)
    var address = 0usize
    unsafe {
        asm!("mov {out}, {input}",out = out(reg) floating,input = in(reg) 1.25f64,
             options(pure,nomem,nostack,preserves_flags))
        asm!(\"""" + ("add {pointer}, {pointer}, #0" if ARM64 else
                       "add {pointer}, 0") +
        """\",pointer = inout(reg) pointer => address,options(nomem,nostack))
    }
    if floating == 1.25f64 && address == pointer.addr() && storage == 42 { 0 } else { 1 }
}
""",
    "machine-asm-initializes-uninitialized-output": """
fn main() {
    var value: i32
    unsafe {
        asm!(\"""" + ('mov {out:w}, #42' if ARM64 else 'mov {out:e}, 42') +
        """\",out = out(reg) value, options(pure,nomem,nostack))
    }
    if value == 42 { 0 } else { 1 }
}
""",
    "machine-asm-physical-lateout-overlaps-input": """
fn main() {
    var answer = 0i32
    unsafe {
        asm!(\"""" + ("add w0, w0, #1" if ARM64 else "add eax, 1") + """\",
             in(\"""" + ("x0" if ARM64 else "rax") + """\") 41i64,
             lateout(\"""" + ("w0" if ARM64 else "eax") + """\") answer,
             options(nomem,nostack))
    }
    if answer == 42 { 0 } else { 1 }
}
""",
    "machine-asm-native-vector-registers-and-modifiers": (
        """
fn main() {
    unsafe {
        var left = core::arch::aarch64::vdupq_n_s32(20)
        let right = core::arch::aarch64::vdupq_n_s32(22)
        asm!("add {left:v}.4s, {left:v}.4s, {right:v}.4s",
             left = inlateout(vreg) left, right = in(vreg_low16) right,
             options(pure,nomem,nostack,preserves_flags))
        if core::arch::aarch64::vgetq_lane_s32(left,3) == 42 { 0 } else { 1 }
    }
}
""" if ARM64 else """
fn main() {
    unsafe {
        var left = core::arch::x86_64::_mm_set1_epi32(20)
        let right = core::arch::x86_64::_mm_set1_epi32(22)
        asm!("paddd {left:x}, {right:x}",
             left = inlateout(xmm_reg) left, right = in(xmm_reg) right,
             options(pure,nomem,nostack,preserves_flags))
        let lanes = core::mem::transmute::<[i32;4]>(left)
        if lanes[3] == 42 { 0 } else { 1 }
    }
}
"""),
    "machine-asm-conservative-memory-effects": """
fn main() {
    var value = 0i32
    let pointer = core::ptr::from_mut(value)
    unsafe {
        asm!(\"""" + (
            "mov w8, #42\\nstr w8, [{pointer}]" if ARM64 else
            "mov dword ptr [{pointer}], 42"
        ) + """\", pointer = in(reg) pointer,
        """ + ('out("w8") _,' if ARM64 else '') + """
        options(nostack))
    }
    if value == 42 { 0 } else { 1 }
}
""",
    "machine-target-direct-guarded-vector": (
        """
fn main() {
    if is_aarch64_feature_detected!("neon") {
        let vector = unsafe { core::arch::aarch64::vdupq_n_s32(42) }
        if unsafe { core::arch::aarch64::vgetq_lane_s32(vector,2) } == 42 { 0 } else { 1 }
    } else { 1 }
}
""" if ARM64 else """
fn main() {
    if is_x86_feature_detected!("avx2") {
        let vector = unsafe { core::arch::x86_64::_mm256_set1_epi32(42) }
        let lanes = unsafe { core::mem::transmute::<[i32;8]>(vector) }
        if lanes[5] == 42 { 0 } else { 1 }
    } else { 0 }
}
"""),
    "machine-target-guarded-register-feature": (
        """
fn main() {
    if is_aarch64_feature_detected!("neon") {
        var answer = 0i64
        unsafe {
            asm!("fmov {value:d}, {input}",value = out(vreg) _,
                 input = in(reg) 42i64, options(nomem,nostack))
            asm!("mov {out}, #42",out = out(reg) answer,options(pure,nomem,nostack))
        }
        if answer == 42 { 0 } else { 1 }
    } else { 1 }
}
""" if ARM64 else """
fn main() {
    if is_x86_feature_detected!("avx") {
        unsafe { asm!("vxorpd {value:y}, {value:y}, {value:y}",
                      value = out(ymm_reg) _, options(nomem,nostack)) }
    }
    0
}
"""),
    "machine-asm-operands-source-order": """
fn step(counter: ptr<mut i32>, value: i32): i32 {
    unsafe { *counter = *counter * 10 + value }
    value
}
fn destination(counter: ptr<mut i32>, output: ptr<mut i32>): ptr<mut i32> {
    unsafe { *counter = *counter * 10 + 3 }
    output
}
fn main() {
    var order = 0
    var result = 0
    let counter = core::ptr::from_mut(order)
    let output = core::ptr::from_mut(result)
    unsafe {
        asm!(\"""" + ASM_ADD + """\",
             left = in(reg) step(counter,1),
             right = in(reg) step(counter,2),
             out = out(reg) *destination(counter,output),
             options(nomem,nostack))
    }
    if order == 123 && result == 3 { 0 } else { 1 }
}
""",
    "machine-asm-inout-late-and-copy-input": """
fn main() {
    var value = 20i32
    let input = 22i32
    unsafe {
        asm!(\"""" + ("add {value:w}, {value:w}, {input:w}" if ARM64
                     else "add {value:e}, {input:e}") + """\",
             value = inout(reg) value,
             input = in(reg) input, options(nomem,nostack))
    }
    var result = 0
    unsafe {
        asm!(\"""" + ASM_MOVE + """\", input = in(reg) value,
             out = lateout(reg) result, options(pure,nomem,nostack))
    }
    if result == 42 && value == 42 && input == 22 { 0 } else { 1 }
}
""",
    "machine-asm-constant-immediate-and-raw": """
fn main() {
    var result = 0i32
    unsafe {
        asm!(\"""" + ("mov {out:w}, #{constant}" if ARM64 else "mov {out:e}, {constant}") + """\",
             constant = const (20 + 22), out = out(reg) result,
             options(pure,nomem,nostack,preserves_flags))
        asm!("nop", options(raw,nomem,nostack,preserves_flags))
    }
    if result == 42 { 0 } else { 1 }
}
""",
    "machine-target-native-vector-shape-copy-and-lanes": (
        """
fn main() {
    unsafe {
        let left = core::arch::aarch64::vdupq_n_s32(20)
        let right = core::arch::aarch64::vdupq_n_s32(22)
        let sum = core::arch::aarch64::vaddq_s32(left,right)
        let changed = core::arch::aarch64::vsetq_lane_s32(7,sum,0)
        if core::arch::aarch64::vgetq_lane_s32(sum,3) == 42 &&
           core::arch::aarch64::vgetq_lane_s32(changed,0) == 7 &&
           core::arch::aarch64::vgetq_lane_s32(left,1) == 20 &&
           core::mem::size_of::<core::arch::aarch64::int32x4_t>() == 16usize &&
           core::mem::align_of::<core::arch::aarch64::int32x4_t>() == 16usize {
            0
        } else { 1 }
    }
}
""" if ARM64 else """
fn main() {
    unsafe {
        let left = core::arch::x86_64::_mm_set1_epi32(20)
        let right = core::arch::x86_64::_mm_set_epi32(22,22,22,22)
        let sum = core::arch::x86_64::_mm_add_epi32(left,right)
        let lanes = core::mem::transmute::<[i32;4]>(sum)
        let original = core::mem::transmute::<[i32;4]>(left)
        if lanes[0] == 42 && lanes[3] == 42 && original[2] == 20 &&
           core::mem::size_of::<core::arch::x86_64::__m128i>() == 16usize &&
           core::mem::align_of::<core::arch::x86_64::__m128i>() == 16usize { 0 } else { 1 }
    }
}
"""),
    "machine-target-dominating-feature-dispatch": (
        """
@target_feature("neon")
unsafe fn accelerated(): i32 {
    let vector = core::arch::aarch64::vdupq_n_s32(42)
    core::arch::aarch64::vgetq_lane_s32(vector,0)
}
fn main() {
    if is_aarch64_feature_detected!("neon") {
        if unsafe { accelerated() } == 42 { 0 } else { 1 }
    } else { 1 }
}
""" if ARM64 else """
@target_feature("avx2")
unsafe fn accelerated(): i32 {
    let vector = core::arch::x86_64::_mm256_set1_epi32(42)
    let lanes = core::mem::transmute::<[i32;8]>(vector)
    lanes[7]
}
fn main() {
    if is_x86_feature_detected!("avx2") {
        if unsafe { accelerated() } == 42 { 0 } else { 1 }
    } else { 0 }
}
"""),
}
MACHINE_NEGATIVE = {
    "machine-target-rejects-strengthened-interface-feature-contract": (
        'interface Ready { fn answer():i32; }\n'
        'copy type Value implements Ready { @target_feature("' +
        ("aes" if ARM64 else "avx2") +
        '") fn answer():i32 { 42 } }\nfn main() { 0 }',
        "type", "contract does not match interface"),
    "machine-target-rejects-implicit-nonbaseline-destructor": (
        'type Value { @target_feature("' + ("aes" if ARM64 else "avx2") +
        '") drop {} }\nfn main() { let value=Value(); 0 }',
        "feature", "implicit destructor dispatch"),
    "machine-asm-naked-rejects-owned-cleanup-root": (
        '@layout(C) type Owned { value:i32; drop {} }\n'
        '@naked unsafe extern "C" fn invalid(value: take Owned) { naked_asm!("ret") }\n'
        'fn main() { 0 }', "attribute", "requiring cleanup"),
    **({
        "machine-target-rejects-out-of-bounds-native-lane": (
            'fn main() { unsafe { let vector=core::arch::aarch64::vdupq_n_s32(42);'
            'core::arch::aarch64::vgetq_lane_s32(vector,4) }; 0 }',
            "type", "lane is outside"),
        "machine-target-rejects-dynamic-native-lane": (
            'fn main() { let lane=1; unsafe { '
            'let vector=core::arch::aarch64::vdupq_n_s32(42);'
            'core::arch::aarch64::vgetq_lane_s32(vector,lane) }; 0 }',
            "type", "constant integer"),
    } if ARM64 else {}),
    **({
        "machine-asm-rejects-unavailable-register-feature": (
            'fn main() { unsafe { asm!("/* {value} */",'
            'value = out(ymm_reg) _,options(nomem)) }; 0 }',
            "assembly", "required feature"),
    } if not ARM64 else {
        "machine-target-core-rejects-hosted-optional-detector": (
            'fn main() { if is_aarch64_feature_detected!("aes") { 0 } else { 1 } }',
            "feature", "unsupported core feature detection"),
    }),
    "machine-asm-rejects-impossible-register-pressure": (
        'fn main() { unsafe { asm!("/* ' +
        ' '.join('{v' + str(i) + '}' for i in range(17 if ARM64 else 5)) +
        ' */",' + ','.join('v' + str(i) + '= in(' +
            ('vreg_low16' if ARM64 else 'reg_abcd') + ') ' + str(i + 1) + 'i64'
            for i in range(17 if ARM64 else 5)) +
        ') }; 0 }', "assembly", "available register inventory"),
    "machine-target-rejects-vector-element-shape-mismatch": (
        'fn main() { unsafe { ' + (
            'let value=core::arch::aarch64::vdupq_n_f32(1.0f32);'
            'core::arch::aarch64::vaddq_s32(value,value)' if ARM64 else
            'let value=core::arch::x86_64::_mm_set1_ps(1.0f32);'
            'core::arch::x86_64::_mm_add_epi32(value,value)') +
        ' }; 0 }', "type"),
    "machine-asm-rejects-register-class-used-as-clobber-only": (
        'fn main() { unsafe { asm!("nop",out(' + ("preg" if ARM64 else "x87_reg") +
        ') _) }; 0 }', "assembly", "explicit register"),
    "machine-asm-global-rejects-runtime-constant": (
        'global_asm!("/* {value} */",value = const unknown)\nfn main() { 0 }',
        "type", "integer constant"),
    "machine-asm-rejects-raw-nul-template": (
        'fn main() { unsafe { asm!("nop\\0",options(raw)) }; 0 }',
        "assembly", "NUL"),
    "machine-asm-naked-rejects-unwind-without-metadata": (
        '@naked unsafe extern "C-unwind" fn invalid() { naked_asm!("ret") }\n'
        'fn main() { 0 }', "feature", "unwind metadata"),
    "machine-asm-naked-rejects-hidden-defaults": (
        '@naked unsafe extern "C" fn invalid(value:i32=42):i32 { naked_asm!("ret") }\n'
        'fn main() { 0 }', "attribute", "defaults"),
    "machine-asm-rejects-uninitialized-input": (
        'fn main() { var value:i32; unsafe { asm!("/* {input} */",'
        'input = in(reg) value) }; 0 }', "type", "uninitialized"),
    "machine-asm-rejects-noreturn-output": (
        'fn main() { var value=0; unsafe { asm!("/* {out} */",'
        'out = out(reg) value, options(noreturn)) } }',
        "assembly", "noreturn"),
    "machine-target-rejects-dispatch-proof-after-join": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") unsafe fn accelerated(): i32 { 42 }\n'
        'fn main() { if ' + ('is_aarch64_feature_detected!("neon")' if ARM64 else
                             'is_x86_feature_detected!("avx2")') +
        ' { }; unsafe { accelerated() }; 0 }', "feature"),
    "machine-target-rejects-nonbaseline-hosted-entry": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") fn main() { 0 }', "feature", "hosted entry"),
    "machine-asm-rejects-conflicting-options": (
        'fn main() { unsafe { asm!("nop",options(nomem,readonly)) }; 0 }',
        "assembly", "nomem and readonly"),
    "machine-asm-rejects-pure-without-output": (
        'fn main() { unsafe { asm!("nop",options(pure,nomem)) }; 0 }',
        "assembly", "observable output"),
    "machine-asm-requires-unsafe": (
        'fn main() { asm!("nop"); 0 }', "unsafe"),
    "machine-asm-rejects-reserved-register": (
        'fn main() { unsafe { asm!("nop",out("' + ("x18" if ARM64 else "rsp") +
        '") _) }; 0 }', "assembly", "reserved"),
    "machine-asm-rejects-register-alias-conflict": (
        'fn main() { unsafe { asm!("nop",in("' + ("x0" if ARM64 else "rax") +
        '") 1i64,out("' + ("w0" if ARM64 else "eax") +
        '") _) }; 0 }', "assembly", "conflicting"),
    "machine-asm-rejects-managed-type": (
        'copy type Pair { first: i32; second: i32 }\n'
        'fn main() { let pair = Pair(1,2); unsafe { asm!("/* {value} */",'
        'value = in(reg) pair) }; 0 }', "assembly", "operand type"),
    "machine-asm-rejects-invalid-modifier": (
        'fn main() { unsafe { asm!("/* {value:z} */",value = in(reg) 1) }; 0 }',
        "assembly", "modifier"),
    "machine-asm-rejects-unwind-option": (
        'fn main() { unsafe { asm!("nop",options(may_unwind)) }; 0 }',
        "assembly", "unsupported assembly option"),
    "machine-asm-naked-rejects-ordinary-body": (
        '@naked unsafe extern "C" fn invalid(value: i32): i32 { value }\n'
        'fn main() { 0 }', "attribute", "exactly naked_asm"),
    "machine-target-rejects-unknown-feature": (
        '@target_feature("imaginary") fn invalid() {}\nfn main() { 0 }',
        "feature", "unknown target feature"),
    "machine-target-rejects-unguarded-feature-call": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") unsafe fn accelerated(): i32 { 42 }\n'
        'fn main() { unsafe { accelerated() }; 0 }',
        "feature", "established target feature"),
    "machine-target-rejects-feature-erasure": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") unsafe fn accelerated(): i32 { 42 }\n'
        'fn main() { let callback: unsafe fn(): i32 = accelerated; 0 }',
        "type"),
    "machine-target-rejects-wrong-architecture-operation": (
        'fn main() { unsafe { ' + (
            'core::arch::x86_64::_mm_set1_epi32(42)' if ARM64 else
            'core::arch::aarch64::vdupq_n_s32(42)') + ' }; 0 }', "feature"),
    "machine-target-rejects-known-unimplemented-operation": (
        'fn main() { unsafe { core::arch::' +
        ('aarch64::vaeseq_u8' if ARM64 else 'x86_64::_mm_aesenc_si128') +
        '() }; 0 }', "feature", "unsupported architecture operation"),
}


POSITIVE = {
    "machine-static-native-cell-constructors-and-guard-cleanup": """
static mut CELL: core::cell::Cell<i32> = core::cell::Cell::new(0);
static mut STATE: core::cell::RefCell<i32> = core::cell::RefCell::new(41);
fn main() {
    unsafe {
        CELL.set(42)
        {
            var guard = STATE.borrow_mut()
            *guard.get_mut() += 1
        }
        let value = STATE.borrow()
        if CELL.get() == 42 && *value.get_ref() == 42 { 0 } else { 1 }
    }
}
""",
    "machine-static-full-width-required-arithmetic-and-native-bounds": """
static FIRST: u128 = 1267650600228229401496703205376u128;
static SECOND: u128 = FIRST + 42u128;
static MAXIMUM: u128 = u128::MAX - 1u128;
static NEGATIVE: i128 = i128::MIN + 42i128;
fn mask<const B: bool = true | false>(): bool { B }
fn main() {
    if SECOND - FIRST == 42u128 && MAXIMUM + 1u128 == u128::MAX &&
       NEGATIVE - i128::MIN == 42i128 && mask() { 0 } else { 1 }
}
""",
    "c-variadic-definition-cursor-forgetting-does-not-escape": """
unsafe extern "C" fn callback(count: i32,args: ...): i32 {
    core::mem::forget(take args)
    count
}
fn main() { unsafe { callback(0,42i32) } }
""",
    "machine-numeric-usize-array-count-inference-and-indexing": """
fn repeated<const N: usize>(): [i32;N] { [21;N] }
fn sum<const N: usize>(values: read [i32;N]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn at<const N: usize>(values: read [i32;N],index: usize): i32 { values[index] }
fn from_slice(values: read [i32],index: usize): i32 { values[index] }
fn main() {
    let values = repeated::<2usize>()
    let index = 1usize
    let slice: read [i32] = read values
    if sum(values) == 42 && at(values,index) == 21 &&
       from_slice(slice,index) == 21 && slice[1usize] == 21 &&
       values[0usize] == 21 { 0 } else { 1 }
}
""",
    "machine-numeric-wide-bounded-array-count-and-zero-array-alignment": """
type Tail { first: u8; empty: [u64;0usize] }
fn main() {
    let repeated: [i32;2u128] = [21;2u64]
    if repeated[0] + repeated[1] == 42 &&
       core::mem::size_of::<[u64;0usize]>() == 0usize &&
       core::mem::align_of::<[u64;0usize]>() == 8usize &&
       core::mem::size_of::<Tail>() == 8usize &&
       core::mem::align_of::<Tail>() == 8usize { 0 } else { 1 }
}
""",
    "machine-numeric-full-width-required-constants": """
fn unsigned<const N:u128>(): u128 { N }
fn signed<const N:i128>(): i128 { N }
fn widened<const N:u128>(): u128 { unsigned::<{N + 1}>() }
fn inferred<const N:u64=18446744073709551615>(): u64 { N }
fn main() {
    if unsigned::<340282366920938463463374607431768211455>() ==
           340282366920938463463374607431768211455u128 &&
       signed::<-170141183460469231731687303715884105728>() ==
           -170141183460469231731687303715884105728i128 &&
       widened::<18446744073709551615>() == 18446744073709551616u128 &&
       unsigned::<{(1u128 << 127u32) / 3 * 3 + (1u128 << 127usize) % 3}>() ==
           170141183460469231731687303715884105728u128 &&
       unsigned::<{!0u128}>() == 340282366920938463463374607431768211455u128 &&
       signed::<{-170141183460469231731687303715884105728i128 >> 127}>() == -1i128 &&
       inferred() == 18446744073709551615u64 { 0 } else { 1 }
}
""",
    "machine-numeric-wide-associated-constants-and-enum-expressions": """
interface Number { const VALUE:u128 = 18446744073709551616; }
type Tag {}
impl Tag implements Number { const VALUE:u128 = 340282366920938463463374607431768211455; }
fn get<T:Number>(): u128 { T::VALUE }
@layout(u128)
copy enum Value { First = 1u128 << 127; Next; Last = (1u128 << 127) + 2 }
fn main() {
    if get::<Tag>() == 340282366920938463463374607431768211455u128 &&
       Value::First as u128 == 170141183460469231731687303715884105728u128 &&
       Value::Next as u128 == 170141183460469231731687303715884105729u128 &&
       Value::Last as u128 == 170141183460469231731687303715884105730u128 {
        0
    } else { 1 }
}
""",
    "machine-numeric-required-wide-bitwise-and-comparisons": """
fn unsigned<const N:u128>(): u128 { N }
fn signed<const N:i128>(): i128 { N }
fn condition<const B:bool>(): bool { B }
fn main() {
    if unsigned::<{18446744073709551615u128 + 1}>() == 18446744073709551616u128 &&
       unsigned::<{18446744073709551616u128 - 1}>() == 18446744073709551615u128 &&
       unsigned::<{18446744073709551615u128 * 18446744073709551615u128}>() ==
           340282366920938463426481119284349108225u128 &&
       unsigned::<{340282366920938463463374607431768211455u128 /
                   18446744073709551617u128}>() == 18446744073709551615u128 &&
       unsigned::<{340282366920938463463374607431768211455u128 %
                   18446744073709551617u128}>() == 0u128 &&
       signed::<{-170141183460469231731687303715884105728i128 / 3}>() ==
           -56713727820156410577229101238628035242i128 &&
       signed::<{-170141183460469231731687303715884105728i128 % 3}>() == -2i128 &&
       signed::<{-1i128 ^ 170141183460469231731687303715884105727i128}>() ==
           -170141183460469231731687303715884105728i128 &&
       unsigned::<{(1u128 << 127) | 42u128}>() ==
           170141183460469231731687303715884105770u128 &&
       unsigned::<{(340282366920938463463374607431768211455u128 & 42u128) << 1}>() ==
           84u128 &&
       condition::<{18446744073709551616u128 > 18446744073709551615u128}>() &&
       condition::<{-170141183460469231731687303715884105728i128 < -1i128}>() {
        0
    } else { 1 }
}
""",
    "machine-unpin-method-equality-is-local-to-the-method": """
type Blocked { value: i32 }
impl Blocked not Unpin;
type Parent<T> {
    value: T
    fn access<U: Unpin>(value: mut T): mut T from value where T = U {
        var handle = core::pin::Pin::new(mut value)
        handle.into_inner()
    }
}
fn main() {
    let parent = Parent(0)
    var value = 41
    *parent.access::<i32>(value) += 1
    let unrelated = Parent(Blocked(0))
    if value == 42 { 0 } else { 1 }
}
""",
    "machine-unpin-associated-property-survives-validated-substitution": """
interface Family { type Item: Unpin; }
type Maker {}
impl Maker implements Family { type Item = i32; }
fn access<T: Family>(value: mut <T implements Family>::Item): mut <T implements Family>::Item from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = 41
    *access::<Maker>(value) += 1
    if value == 42 { 0 } else { 1 }
}
""",
    "machine-cell-slice-guards-preserve-metadata-and-state": """
fn total(cell: read core::cell::RefCell<[i32]>): i32 {
    let guard = cell.borrow()
    var total = 0
    for value in guard.get_ref() { total += value }
    total
}
fn main() {
    let cell = core::cell::RefCell::new([20,21])
    let slice: read core::cell::RefCell<[i32]> = read cell
    {
        var guard = slice.borrow_mut()
        guard.get_mut()[1] += 1
    }
    if total(slice) == 42 { 0 } else { 1 }
}
""",
    "machine-cell-erased-guard-respects-dynamic-payload-alignment": """
interface Readable { fn value(): i32; }
@align(64)
type Number { number: i32 }
impl Number implements Readable { fn value(): i32 { self.number } }
fn main() {
    let cell = core::cell::RefCell::new(Number(42))
    let erased: read core::cell::RefCell<any Readable> = read cell
    { let guard = erased.borrow(); if guard.get_ref().value() != 42 { return 1 } }
    let guard = erased.borrow_mut()
    if guard.get_ref().value() == 42 { 0 } else { 2 }
}
""",
    "machine-cell-forgetting-a-cloned-read-guard-keeps-other-views-valid": """
fn main() {
    let cell = core::cell::RefCell::new(42)
    {
        let first = cell.borrow()
        let second = first.clone()
        let payload = first.get_ref()
        core::mem::forget(second)
        if *payload != 42 { return 1 }
    }
    let blocked = cell.try_borrow_mut()
    if match take blocked { success(guard) => false, failure(error) => true } {
        0
    } else { 2 }
}
""",
    "machine-cell-captured-guard-releases-with-its-closure": """
fn main() {
    let cell = core::cell::RefCell::new(42)
    {
        let guard = cell.borrow()
        let inspect = take fn(): i32 { *guard.get_ref() }
        if inspect() != 42 { return 1 }
    }
    var guard = cell.borrow_mut()
    if *guard.get_mut() == 42 { 0 } else { 2 }
}
""",
    "machine-unpin-closure-retains-contextual-product-bound": """
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Copy> Wrapper<T> implements Unpin {}
fn access<T>(value: mut Wrapper<T>): Unit where Wrapper<T>: Unpin {
    var operation = fn(): Unit {
        var handle = core::pin::Pin::new(mut value)
        let reference = handle.into_inner()
    }
    operation()
}
fn main() {
    var value = Wrapper(42,core::marker::PhantomPinned)
    access(value)
    if value.value == 42 { 0 } else { 1 }
}
""",
    "machine-cell-manual-storage-and-aggregate-guard-cleanup": """
fn main() {
    let cell = core::cell::RefCell::new(42)
    { let guards = [cell.borrow(),cell.borrow()] }
    {
        let wrapper = core::mem::ManuallyDrop::new(cell.borrow_mut())
        { let guard = wrapper.into_inner() }
    }
    { let guard = cell.borrow() }
    { let wrapper = core::mem::ManuallyDrop::new(cell.borrow_mut()) }
    let blocked = cell.try_borrow()
    if match take blocked { success(guard) => false, failure(error) => true } {
        0
    } else { 1 }
}
""",
    "machine-numeric-full-width-constant-type-identity": """
interface Code { fn code():i32; }
type Key<const N:u128> {}
impl Key<0> implements Code { fn code():i32 { 1 } }
impl Key<18446744073709551616> implements Code { fn code():i32 { 42 } }
fn inspect<T:Code>(value:read T):i32 { value.code() }
fn main() {
    let first=Key::<0>()
    let second=Key::<18446744073709551616>()
    if inspect(first)==1 && inspect(second)==42 { 0 } else { 1 }
}
""",
    "machine-numeric-wide-patterns-and-exhaustive-endpoints": """
fn byte(value:i8): i32 {
    match value { -128..=-1 => 20, 0..=127 => 22 }
}
fn wide(value:u128): i32 {
    match value {
        0..18446744073709551616 => 1,
        18446744073709551616..=340282366920938463463374607431768211455 => 42
    }
}
fn signed(value:i128): i32 {
    match value {
        -170141183460469231731687303715884105728..=-1 => 20,
        0..=170141183460469231731687303715884105727 => 22
    }
}
fn main() {
    let exact = match 0xffff_ffff_ffff_ffffu64 {
        0xffff_ffff_ffff_ffffu64 => 42,
        _ => 1
    }
    if byte(-128i8) + byte(127i8) == 42 &&
       signed(-170141183460469231731687303715884105728i128) +
       signed(170141183460469231731687303715884105727i128) == 42 &&
       wide(340282366920938463463374607431768211455u128) == 42 &&
       exact == 42 &&
       (match 340282366920938463463374607431768211455 {
           340282366920938463463374607431768211455u128 => true,
           _ => false
       }) { 0 } else { 1 }
}
""",
    "machine-numeric-range-iteration-exceptional-endpoints": """
fn main() {
    var count = 0
    for value in 340282366920938463463374607431768211454u128..=340282366920938463463374607431768211455u128 {
        count += 1
        if value == 340282366920938463463374607431768211455u128 { continue }
    }
    for value in -170141183460469231731687303715884105728i128..=-170141183460469231731687303715884105727i128 {
        count += 1
    }
    for value in 127i8..=127i8 { count += 1 }
    for value in 255u8..255u8 { count += 100 }
    for value in 18446744073709551615u64..=18446744073709551615u64 { count += 1 }
    for value in 2u16..=1u16 { count += 100 }
    if count == 6 { 0 } else { 1 }
}
""",
    "machine-numeric-contextual-aggregates": """
fn answer(values:read [u128;2], pair:(i8,f32)): i32 {
    if values[0] == 18446744073709551616u128 &&
       values[1] == 18446744073709551616u128 &&
       pair.0 == -128i8 && pair.1.to_bits() == 0x3f800001u32 { 42 } else { 1 }
}
fn main() {
    let values:[u128;2] = [18446744073709551616;2]
    if answer(values,(-128,1.00000005960464477539062500000000000000000000000001)) == 42 { 0 } else { 1 }
}
""",
    "machine-numeric-checked-integer-and-floating-conversions": """
fn missing<T:Copy>(value:T?): bool {
    match value { none => true, present(item) => false }
}
fn signed(value:i8?, expected:i8): bool {
    match value { none => false, present(item) => item == expected }
}
fn byte(value:u8?, expected:u8): bool {
    match value { none => false, present(item) => item == expected }
}
fn wide(value:u128?, expected:u128): bool {
    match value { none => false, present(item) => item == expected }
}
fn main() {
    let large = 340282366920938463463374607431768211455u128
    let nan = f64::from_bits(0x7ff8000000000042u64)
    if signed(127.9f64.checked_cast::<i8>(),127i8) &&
       signed((-128.9f64).checked_cast::<i8>(),-128i8) &&
       byte((-0.5f64).checked_cast::<u8>(),0u8) &&
       missing(128.0f64.checked_cast::<i8>()) &&
       missing((-129.0f64).checked_cast::<i8>()) &&
       missing(nan.checked_cast::<u128>()) &&
       missing((1.0f64 / 0.0f64).checked_cast::<i128>()) &&
       missing(18446744073709551616u128.checked_cast::<u64>()) &&
       missing(large.checked_cast::<i128>()) &&
       missing((-1i128).checked_cast::<u128>()) &&
       byte(255u128.checked_cast::<u8>(),255u8) &&
       wide(170141183460469231731687303715884105727i128.checked_cast::<u128>(),
            170141183460469231731687303715884105727u128) &&
       wide(340282346638528859811704183484516925440.0f32.checked_cast::<u128>(),
            340282346638528859811704183484516925440u128) &&
       nan as i8 == 0i8 && 128.0f64 as i8 == 127i8 { 0 } else { 1 }
}
""",
    "machine-numeric-explicit-function-and-module-relaxations": """
@fast_math(contract)
fn multiply_add(a:f32,b:f32,c:f32): f32 { a * b + c }
@fast_math(contract)
fn defaulted(a:f32,b:f32,c:f32=a*b+1.0f32): f32 { c }
@fast_math(contract)
fn closure(a:f32,b:f32,c:f32): f32 {
    let operation=fn(x:f32,y:f32,z:f32):f32{x*y+z}
    operation(a,b,c)
}
@fast_math(no_nans,no_infinities,no_signed_zeros)
fn checked(value:f64): bool {
    match value.checked_cast::<i8>() { none => true, present(item) => false }
}
@fast_math(reassociate,reciprocal,approximate_functions)
module relaxed {
    pub fn calculate(a:f64,b:f64,c:f64): f64 { (a + b) + c }
}
fn strict(value:f64): bool {
    let nan = 0.0f64 / 0.0f64
    value.to_bits() == 0x8000000000000000u64 && nan != nan
}
fn separate(a:f32,b:f32,c:f32): f32 { a*b+c }
fn main() {
    if multiply_add(2.0f32,10.0f32,22.0f32) == 42.0f32 &&
       defaulted(2.0f32,10.0f32) == 21.0f32 &&
       closure(2.0f32,10.0f32,22.0f32) == 42.0f32 &&
       checked(f64::from_bits(0x7ff8000000000042u64)) &&
       relaxed::calculate(20.0f64,20.0f64,2.0f64) == 42.0f64 &&
       separate(1.00000011920928955078125f32,0.99999988079071044921875f32,-1.0f32) == 0.0f32 &&
       1.00000011920928955078125f32.mul_add(
           0.99999988079071044921875f32,-1.0f32) != 0.0f32 &&
       strict(-0.0f64) { 0 } else { 1 }
}
""",
    "c-variadic-definition-direct-indirect-and-zero-size-arguments": """
@layout(C)
copy type Empty {}
unsafe extern "C" fn inspect(count: i32,args: ...): i32 {
    let empty = args.arg::<Empty>()
    args.arg::<i32>()
}
fn main() {
    let callback: unsafe extern "C" fn(i32,...): i32 = inspect
    let first = unsafe { inspect(1,Empty(),42) }
    let second = unsafe { callback(1,Empty(),42) }
    if first == 42 && second == 42 { 0 } else { 1 }
}
""",
    "machine-static-union-enum-and-nested-relocations": """
@layout(C)
union Bits { integer: u64; real: f64 }
@layout(C,u8)
copy enum Number { Empty = 7; Integer(u64) = 9 }
@layout(transparent)
copy enum Wrapper { Value(i64,Unit) }
copy type Nested { first: Number; second: Wrapper }
static BITS: Bits = Bits(integer: 0x3ff0000000000000u64);
static VALUE: Number = Number::Integer(42u64);
static NESTED: Nested = Nested(Number::Empty,Wrapper::Value(42i64,()));
static VALUES: [i32;2] = [20,22];
static ADDRESS: ptr<read i32> = core::ptr::from_ref(VALUES[1]);
fn main() {
    let value = match VALUE { Number::Integer(value) => value, _ => 0u64 }
    let nested = match NESTED.second { Wrapper::Value(value,_) => value }
    if value == 42u64 && nested == 42i64 && unsafe { BITS.real == 1.0f64 && *ADDRESS == 22 } { 0 } else { 1 }
}
""",
    "machine-static-function-pointer-slice-default-and-closure": """
static VALUES: [i32;2] = [21;2];
static SLICE: read [i32] from static = read VALUES;
static ADDRESS: ptr<read i32> = core::ptr::from_ref(ANSWER);
static ANSWER: i32 = 42;
fn identity(value: i32): i32 { value }
static CALLBACK: fn(i32): i32 = identity;
fn with_default(value: i32 = ANSWER): i32 { value }
fn main() {
    let callback = fn() { ANSWER }
    let reader = fn(): read i32 from static { read ANSWER }
    var total = 0
    for value in SLICE { total += value }
    if CALLBACK(total) == 42 && with_default() == 42 &&
       callback() == 42 && *reader() == 42 && unsafe { *ADDRESS } == 42 { 0 } else { 1 }
}
""",
    "machine-static-explicit-library-linkage": """
@link("m")
extern "C" { unsafe fn abs(value: i32): i32; }
fn main() { if unsafe { abs(-42) } == 42 { 0 } else { 1 } }
""",
    "machine-static-initializers-imports-lifetimes-and-interior-mutation": """
module values {
    pub static ANSWER: i32 = 20 + 22;
    pub static WIDE: u128 = 340282366920938463463374607431768211455u128;
    pub static MAXIMUM: u128 = u128::MAX;
    pub static CELL: core::cell::UnsafeCell<i32> = core::cell::UnsafeCell::new(1);
    pub static FLAG: core::sync::atomic::AtomicU32 = core::sync::atomic::AtomicU32::new(0u32);
    pub static mut COUNT: i32 = 1;
}
import values::{ANSWER as NUMBER,CELL,FLAG}
static VIEW: read i32 from static = read values::ANSWER;
fn answer(): read i32 from static { read NUMBER }
fn forward(): read i32 from static { answer() }
fn main() {
    unsafe {
        *CELL.get() = 42
        values::COUNT += 1
    }
    FLAG.store(42u32,core::sync::atomic::Ordering::Relaxed)
    if *forward() == 42 && *VIEW == 42 &&
       values::WIDE == 340282366920938463463374607431768211455u128 &&
       values::WIDE == values::MAXIMUM &&
       unsafe { *CELL.get() == 42 && values::COUNT == 2 } &&
       FLAG.load(core::sync::atomic::Ordering::Relaxed) == 42u32 { 0 } else { 1 }
}
""",
    "machine-static-aggregate-address-relocations-and-shadowing": """
copy type Pair { first: i32; second: i32 }
static PAIR: Pair = Pair(second: 22,first: 20);
static ELEMENT: read i32 from static = read PAIR.second;
static VALUES: [i32;2] = [20,22];
static SELECTED: i32 = PAIR.second;
static INDEXED: i32 = VALUES[1];
static NEGATIVE: i64 = -9223372036854775808i64;
static REAL: f64 = 1.25f64;
static mut COUNT: i32 = 1;
static MUT_ADDRESS: ptr<mut i32> = unsafe { core::ptr::from_mut(COUNT) };
fn main() {
    unsafe { *MUT_ADDRESS = 42 }
    let before = PAIR.first
    let PAIR = 42
    if before + *ELEMENT == PAIR && VALUES[0] + VALUES[1] == 42 &&
       SELECTED == 22 && INDEXED == 22 &&
       NEGATIVE == -9223372036854775808i64 && REAL == 1.25f64 &&
       unsafe { COUNT == 42 } { 0 } else { 1 }
}
""",
    "machine-unpin-region-condition-under-declared-context": """
interface Ready<region r> {}
impl<region r> i32 implements Ready<region r> where region r: static {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready<region static>> Wrapper<T> implements Unpin {}
fn access<region r, T: Ready<region r>>(value: mut Wrapper<T>): mut Wrapper<T> from value where region r: static {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(41,core::marker::PhantomPinned)
    access::<region static,i32>(value).value += 1
    if value.value == 42 { 0 } else { 1 }
}
""",
    "machine-cell-returned-generic-guard-keeps-cell-authority": """
fn borrow<T>(cell: read core::cell::RefCell<T>): core::cell::Ref<T> from cell {
    cell.borrow()
}
fn borrow_mut<T>(cell: read core::cell::RefCell<T>): core::cell::RefMut<T> from cell {
    cell.borrow_mut()
}
fn main() {
    let cell = core::cell::RefCell::new(40)
    { var guard = borrow_mut(cell); *guard.get_mut() += 2 }
    let guard = borrow(cell)
    if *guard.get_ref() == 42 { 0 } else { 1 }
}
""",
    "machine-cell-try-borrow-failure-does-not-release-another-guard": """
fn main() {
    let cell = core::cell::RefCell::new(42)
    {
        var exclusive = cell.borrow_mut()
        { let failed = cell.try_borrow() }
        { let failed = cell.try_borrow_mut() }
        let failed = cell.try_borrow()
        let blocked = match take failed { success(guard) => false, failure(error) => true }
        if !blocked || *exclusive.get_mut() != 42 { return 1 }
    }
    { let guard = cell.borrow() }
    var guard = cell.borrow_mut()
    if *guard.get_mut() == 42 { 0 } else { 2 }
}
""",
    "machine-unpin-opaque-condition-preserves-contract": """
interface Ready {}
type AddressSensitive { marker: core::marker::PhantomPinned }
impl AddressSensitive implements Ready {}
fn make(): some Ready { AddressSensitive(core::marker::PhantomPinned) }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready> Wrapper<T> implements Unpin {}
fn access<T: Ready>(value: mut Wrapper<T>): mut Wrapper<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(make(),core::marker::PhantomPinned)
    let first = access(value)
    var handle = core::pin::Pin::new(mut value)
    let second = handle.get_mut()
    0
}
""",
    "machine-unpin-higher-ranked-interface-condition": """
interface Ready<region r> {}
impl<region r> i32 implements Ready<region r> {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: for<region r> Ready<region r>> Wrapper<T> implements Unpin {}
fn access<T: for<region r> Ready<region r>>(value: mut Wrapper<T>): mut Wrapper<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(41,core::marker::PhantomPinned)
    access(value).value += 1
    if value.value == 42 { 0 } else { 1 }
}
""",
    "machine-unpin-associated-equality-condition": """
interface Family { type Item; }
type Source {}
impl Source implements Family { type Item = i32; }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Family> Wrapper<T> implements Unpin where <T implements Family>::Item = i32 {}
fn access<T: Family>(value: mut Wrapper<T>): mut Wrapper<T> from value where <T implements Family>::Item = i32 {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(Source(),core::marker::PhantomPinned)
    let result = access(value)
    0
}
""",
    "machine-cell-safe-exchange-and-exclusive-access": """
fn main() {
    let first = core::cell::Cell::new(1)
    let second = core::cell::Cell::new(42)
    first.swap(second)
    let old = first.replace(40)
    first.set(first.get() + 2)
    var third = core::cell::Cell::new(0)
    *third.get_mut() = second.into_inner()
    if old == 42 && first.get() == 42 && third.into_inner() == 1 { 0 } else { 1 }
}
""",
    "machine-cell-owned-exchange-drops-once": """
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        let cell = core::cell::Cell::new(Counted(counter,1))
        let old = cell.replace(Counted(counter,10))
        cell.set(Counted(counter,100))
        if count != 10 { return 1 }
    }
    if count == 111 { 0 } else { 2 }
}
""",
    "machine-cell-guards-count-until-destruction-not-last-use": """
fn main() {
    let cell = core::cell::RefCell::new(42)
    {
        let first = cell.borrow()
        let second = first.clone()
        if *first.get_ref() != 42 || *second.get_ref() != 42 { return 1 }
        let blocked = cell.try_borrow_mut()
        if match take blocked { success(guard) => false, failure(error) => true } {
        } else { return 2 }
    }
    {
        var exclusive = cell.borrow_mut()
        *exclusive.get_mut() = 40
        let blocked = cell.try_borrow()
        if match take blocked { success(guard) => false, failure(error) => true } {
        } else { return 3 }
        *exclusive.get_mut() += 2
    }
    let value = cell.borrow()
    if *value.get_ref() == 42 { 0 } else { 4 }
}
""",
    "machine-cell-fallible-success-and-partial-path-release": """
fn choose(cell: read core::cell::RefCell<i32>, condition: bool): i32 {
    if condition {
        var guard = cell.borrow_mut()
        *guard.get_mut() += 1
        return *guard.get_ref()
    }
    let guard = cell.borrow()
    *guard.get_ref()
}
fn main() {
    let cell = core::cell::RefCell::new(40)
    let first = choose(cell,true)
    let second = choose(cell,false)
    let outcome = cell.try_borrow_mut()
    let result = match take outcome {
        success(guard) => { var guard = guard; *guard.get_mut() += 1; *guard.get_ref() },
        failure(error) => 0
    }
    if first == 41 && second == 41 && result == 42 { 0 } else { 1 }
}
""",
    "machine-cell-forgetting-leaks-only-the-counter-state": """
fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    core::mem::forget(guard)
    let blocked = cell.try_borrow_mut()
    let failed = match take blocked { success(guard) => false, failure(error) => true }
    let remaining = cell.borrow()
    if failed && *remaining.get_ref() == 42 { 0 } else { 1 }
}
""",
    "machine-cell-guard-drop-never-drops-the-payload": """
type Counted { counter: ptr<mut i32>; drop { unsafe { *self.counter += 1 } } }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        let cell = core::cell::RefCell::new(Counted(counter))
        { let first = cell.borrow(); let second = cell.borrow() }
        { let exclusive = cell.borrow_mut() }
        if count != 0 { return 1 }
    }
    if count == 1 { 0 } else { 2 }
}
""",
    "machine-cell-exchange-returns-old-view-and-records-new": """
fn exchange<region a>(cell: read core::cell::Cell<read i32 from a>,
                      value: read i32 from a): read i32 from cell {
    cell.replace(read value)
}
fn main() {
    let first = 1
    let second = 42
    let cell = core::cell::Cell::new(read first)
    let old = exchange(cell,read second)
    if *old == 1 && *cell.get() == 42 { 0 } else { 1 }
}
""",
    "machine-cell-refmut-view-writeback": """
type Slot<region r> { value: read i32 from r }
fn assign<region r>(cell: read core::cell::RefCell<Slot<region r>>,
                     value: read i32 from r) {
    var guard = cell.borrow_mut()
    guard.get_mut().value = read value
}
fn main() {
    let first = 1
    let second = 42
    let cell = core::cell::RefCell::new(Slot(read first))
    assign(cell,read second)
    let guard = cell.borrow()
    if *guard.get_ref().value == 42 { 0 } else { 1 }
}
""",
    "machine-unpin-arbitrary-condition-concrete-and-generic": """
interface Ready {}
impl i32 implements Ready {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready> Wrapper<T> implements Unpin {}
fn access<T: Ready>(value: mut Wrapper<T>): mut Wrapper<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn require_unpin<T: Unpin>(value: read T) {}
fn main() {
    var value = Wrapper(40,core::marker::PhantomPinned)
    access(value).value += 2
    require_unpin(value)
    var handle = core::pin::pin(value)
    if handle.get_mut().value == 42 { 0 } else { 1 }
}
""",
    "machine-unpin-nested-conditional-and-associated-condition": """
interface Family { type Item; }
type Source {}
impl Source implements Family { type Item = i32; }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Family<Item=i32>> Wrapper<T> implements Unpin {}
type Outer<T> { nested: Wrapper<T> }
fn access<T: Family<Item=i32>>(value: mut Outer<T>): mut Outer<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Outer(Wrapper(Source(),core::marker::PhantomPinned))
    let result = access(value)
    var handle = core::pin::Pin::new(mut value)
    let inner = handle.get_mut()
    0
}
""",
    "machine-unpin-contextual-product-bound": """
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Copy> Wrapper<T> implements Unpin {}
fn access<T>(value: mut Wrapper<T>): mut Wrapper<T> from value where Wrapper<T>: Unpin {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(41,core::marker::PhantomPinned)
    access(value).value += 1
    if value.value == 42 { 0 } else { 1 }
}
""",
    **MACHINE_POSITIVE,
    "machine-raw-slice-pointer-keeps-metadata-across-address-operations": """
fn total(values: read [i32]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn main() {
    let values = [20,22]
    let slice: read [i32] = read values
    let pointer = slice as ptr<read [i32]>
    let same = pointer.wrapping_byte_add(0usize).with_addr(pointer.addr())
    let borrowed: read [i32] = unsafe { read *same }
    if same == pointer && total(borrowed) == 42 { 0 } else { 1 }
}
""",
    "machine-combined-c-integer-enum-layout": """
@layout(C,u8)
copy enum Value { Empty = 7; Byte(u8) = 9; Wide(u64) = 42 }
fn main() {
    let bytes = unsafe { core::mem::transmute::<[u8;16]>(Value::Byte(42u8)) }
    let answer = match Value::Byte(42u8) {
        Value::Byte(value) => value as i32,
        _ => 0
    }
    if bytes[0] == 9u8 && bytes[8] == 42u8 && answer == 42 &&
       core::mem::align_of::<Value>() == 8usize { 0 } else { 1 }
}
""",
    "machine-transparent-enum-preserves-payload-and-drop": """
type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
@layout(transparent)
enum Wrapped { Value(Counted,Unit) }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    { let value = Wrapped::Value(Counted(counter),()) }
    if count == 1 && core::mem::size_of::<Wrapped>() ==
                       core::mem::size_of::<Counted>() { 0 } else { 1 }
}
""",
    "machine-pinned-destructor-propagates-view-storage-writes": """
type Slot<region r> { value: read i32 from r }
type Writer<region a,region b> {
    @pinned marker: core::marker::PhantomPinned
    destination: mut Slot<region b> from a; value: read i32 from b
    drop { self.project_destination().value = self.get_ref().value }
}
fn main() {
    let first = 1
    let second = 42
    var slot = Slot(read first)
    { let handle = core::pin::pin(Writer(core::marker::PhantomPinned,mut slot,read second)) }
    if *slot.value == 42 { 0 } else { 1 }
}
""",
    "machine-union-overlap-safe-write-and-delayed-initialization": """
@layout(C)
union Bits { integer: u32, real: f32 }
union Generic<T: Copy> { value: T; bytes: u64 }
fn main() {
    var bits = Bits(integer: 0x3f800000u32)
    let first = unsafe { bits.real }
    bits.real = 2.0f32
    let second = unsafe { bits.integer }
    var delayed: Bits
    delayed.integer = 42u32
    let answer = unsafe { delayed.integer }
    let generic = Generic::<i32>(value: 42)
    let value = unsafe { generic.value }
    if first == 1.0f32 && second == 0x40000000u32 && answer == 42u32 &&
       value == 42 && core::mem::size_of::<Bits>() == 4usize { 0 } else { 1 }
}
""",
    "machine-union-manual-destruction-has-no-implicit-field-drop": """
type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
union Storage { owner: core::mem::ManuallyDrop<Counted>; bits: usize }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var storage = Storage(owner: core::mem::ManuallyDrop::new(Counted(counter)))
        unsafe { storage.owner.drop() }
    }
    if count == 1 { 0 } else { 1 }
}
""",
    "machine-explicit-pinned-receiver-preserves-the-payload-address": """
type Payload<T: Copy> {
    value: T; marker: core::marker::PhantomPinned
    fn inspect(receiver self: take pinned mut Self): T {
        self.get_ref().value
    }
}
fn main() {
    var handle = core::pin::pin(Payload(42,core::marker::PhantomPinned))
    let first = handle.as_mut().inspect()
    let second = handle.as_mut().inspect()
    if first == 42 && second == 42 { 0 } else { 1 }
}
""",
    "machine-enum-integer-tags-and-overlapping-variant-layout": """
@layout(u8)
copy enum Byte { First = 64; Next; Last = 255 }
@layout(i128)
copy enum Wide { Minimum = -170141183460469231731687303715884105728i128; Next }
@layout(u8)
copy enum Payload { Empty = 7; Small(u8) = 9; Large(u64) = 42 }
fn main() {
    let bytes = unsafe { core::mem::transmute::<[u8;16]>(Payload::Small(42u8)) }
    let matched = match Byte::Last { Byte::First => 1, Byte::Next => 2, Byte::Last => 42 }
    if Byte::Next as u16 == 65u16 && matched == 42 &&
       Wide::Minimum as i128 == -170141183460469231731687303715884105728i128 &&
       Wide::Next as i128 == -170141183460469231731687303715884105727i128 &&
       bytes[0] == 9u8 && bytes[1] == 42u8 &&
       core::mem::size_of::<Byte>() == 1usize &&
       core::mem::size_of::<Payload>() == 16usize { 0 } else { 1 }
}
""",
    "machine-enum-c-layout-drops-only-the-active-overlapping-payload": """
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
@layout(C)
enum Choice { Empty; One(Counted); Two(Counted,Counted) }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    { let value = Choice::One(Counted(counter,10)) }
    { let value = Choice::Two(Counted(counter,1),Counted(counter,31)) }
    { let value = Choice::Empty }
    if count == 42 && core::mem::size_of::<Choice>() == 40usize { 0 } else { 1 }
}
""",
    "machine-structural-pin-projections-and-pinned-destruction": """
type Child {
    original: usize; counter: ptr<mut i32>; marker: core::marker::PhantomPinned
    drop {
        let address = core::ptr::from_ref(self).addr()
        if address == self.original { unsafe { *self.counter += 1 } }
    }
}
type Parent<T: Copy> {
    @pinned child: Child
    spare: T; counter: ptr<mut i32>
    drop {
        let child = self.project_child()
        let address = core::ptr::from_ref(child.get_ref()).addr()
        if address == child.get_ref().original {
            unsafe { *self.get_ref().counter += 10 }
        }
    }
}
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var handle = core::pin::pin(
            Parent(Child(0usize,counter,core::marker::PhantomPinned),31,counter))
        {
            var child = handle.project_child()
            let address = core::ptr::from_ref(child.get_ref()).addr()
            unsafe { child.get_unchecked_mut().original = address }
        }
        let spare = handle.project_spare()
        *spare += 1
    }
    if count == 11 { 0 } else { 1 }
}
""",
    "machine-generic-unpin-bound-and-safe-pin-construction": """
fn access<T: Unpin>(value: mut pinned mut T): mut T from value {
    value.get_mut()
}
fn main() {
    var value = 41
    {
        var handle = core::pin::Pin::new(mut value)
        let view = access(handle)
        *view += 1
    }
    if value == 42 { 0 } else { 1 }
}
""",
    "machine-unsafe-manual-unpin-preserves-generic-conditions": """
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Unpin> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(41,core::marker::PhantomPinned))
    handle.get_mut().value += 1
    if handle.get_ref().value == 42 { 0 } else { 1 }
}
""",
    "machine-manual-take-and-uninitialized-explicit-destruction": """
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var storage = core::mem::ManuallyDrop::new(Counted(counter,10))
        let value = unsafe { storage.`take`() }
    }
    {
        var storage = core::mem::MaybeUninit::new(Counted(counter,32))
        unsafe { storage.assume_init_drop() }
    }
    let number = core::mem::MaybeUninit::new(42u64)
    let observed = unsafe { number.assume_init_read() }
    if count == 42 && observed == 42u64 { 0 } else { 1 }
}
""",
    "machine-raw-memory-overlap-counts-bytes-and-distance": """
fn copy_values<T>(source: ptr<read T>, target: ptr<mut T>, count: usize) {
    unsafe { core::ptr::copy_nonoverlapping(source,target,count) }
}
fn main() {
    var values = [1u32,2u32,3u32,4u32]
    var output = [0u32,0u32,0u32,0u32]
    let pointer = core::ptr::from_mut(values).cast::<u32>()
    let target = core::ptr::from_mut(output).cast::<u32>()
    unsafe {
        core::ptr::`copy`(pointer,pointer.add(1),3)
        core::ptr::swap(pointer,pointer.add(3))
    }
    copy_values(pointer.cast_const(),target,4)
    let copied = output[0] == 3u32 && output[1] == 1u32 &&
                 output[2] == 2u32 && output[3] == 1u32
    unsafe {
        core::ptr::swap_nonoverlapping(pointer,target,4)
        core::ptr::write_bytes(target,42,1)
        core::ptr::copy_nonoverlapping(pointer,target,0)
    }
    let distance = unsafe { pointer.add(3).offset_from(pointer) }
    let bytes = unsafe { pointer.add(3).byte_offset_from_unsigned(pointer) }
    if copied && output[0] == 0x2a2a2a2au32 &&
       distance == 3isize && bytes == 12usize { 0 } else { 1 }
}
""",
    "machine-raw-replacement-transmute-and-forget-preserve-ownership": """
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var value = Counted(counter,10)
        {
            let old = unsafe {
                core::ptr::replace(core::ptr::from_mut(value),Counted(counter,32))
            }
        }
        core::mem::forget(Counted(counter,1000))
    }
    let float: f32 = unsafe { core::mem::transmute(0x3f800000u32) }
    let bits = unsafe { core::mem::transmute::<u32>(float) }
    let zero: u64 = unsafe { core::mem::zeroed() }
    if count == 42 && float == 1.0f32 && bits == 0x3f800000u32 &&
       zero == 0u64 { 0 } else { 1 }
}
""",
    "machine-packed-fields-relocate-before-aligned-destruction": """
type Leaf {
    counter: ptr<mut i32>; amount: i32
    drop {
        let address = core::ptr::from_ref(self).addr()
        unsafe {
            if address % core::mem::align_of::<Leaf>() == 0usize {
                *self.counter += self.amount
            }
        }
    }
}
@packed(1)
type Packed { first: u8; leaf: Leaf; last: Leaf }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    { let value = Packed(1u8,Leaf(counter,10),Leaf(counter,32)) }
    if count == 42 { 0 } else { 1 }
}
""",
    "machine-atomic-orderings-rmw-and-boolean-storage": """
fn main() {
    let relaxed = core::sync::atomic::Ordering::Relaxed
    let acquire = core::sync::atomic::Ordering::Acquire
    let release = core::sync::atomic::Ordering::Release
    let sequential = core::sync::atomic::Ordering::SeqCst
    let value = core::sync::atomic::AtomicI32::new(40)
    let previous = value.fetch_add(2,sequential)
    let success_value = match value.compare_exchange(42,43,release,acquire) {
        success(old) => old, failure(old) => -100
    }
    let failure_value = match value.compare_exchange(0,1,relaxed,sequential) {
        success(old) => -100, failure(old) => old
    }
    var flag = core::sync::atomic::AtomicBool::new(true)
    let address = flag.as_ptr()
    let mutable = flag.get_mut()
    *mutable = false
    let changed = match flag.compare_exchange(false,true,sequential,acquire) {
        success(old) => !old, failure(old) => false
    }
    let old_flag = flag.fetch_nand(true,sequential)
    let bits = unsafe { address.cast::<u8>().`read`() }
    core::sync::atomic::fence(acquire)
    core::sync::atomic::compiler_fence(release)
    if previous == 40 && success_value == 42 && failure_value == 43 &&
       value.load(acquire) == 43 && changed && old_flag &&
       !flag.load(relaxed) && bits == 0u8 { 0 } else { 1 }
}
""",
    "machine-atomic-pointer-provenance-and-raw-access": """
fn main() {
    let relaxed = core::sync::atomic::Ordering::Relaxed
    let sequential = core::sync::atomic::Ordering::SeqCst
    var first = 41
    var second = 42
    let one = core::ptr::from_mut(first)
    let two = core::ptr::from_mut(second)
    let pointer = core::sync::atomic::AtomicPtr::<i32>::new(one)
    let old = pointer.fetch_ptr_add(0,relaxed)
    let previous = pointer.swap(two,sequential)
    let actual = pointer.load(sequential)
    unsafe {
        core::intrinsics::atomic_store(one,42,sequential)
        let value = core::intrinsics::atomic_load(one,sequential)
        if old == one && previous == one && actual == two && value == 42 { 0 } else { 1 }
    }
}
""",
    "machine-inline-pin-keeps-payload-and-destruction-address-stable": """
type Stable {
    marker: core::marker::PhantomPinned
    address: ptr<read Stable>
    counter: ptr<mut i32>
    drop {
        let actual = core::ptr::from_ref(self)
        unsafe {
            if self.address == actual { *self.counter += 1 }
            else { *self.counter += 100 }
        }
    }
}
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var handle = core::pin::pin(Stable(core::marker::PhantomPinned,
                                           core::ptr::null::<Stable>(),counter))
        let view = unsafe { handle.as_mut().get_unchecked_mut() }
        view.address = core::ptr::from_ref(view)
        let reference = handle.as_ref().get_ref()
        if reference.address != core::ptr::from_ref(reference) { return 1 }
    }
    if count == 1 { 0 } else { 2 }
}
""",
    "machine-unpin-payload-allows-safe-pinned-reborrowing": """
fn main() {
    var handle = core::pin::pin(40i32)
    let view = handle.as_mut().get_mut()
    *view += 2
    let reference = handle.as_ref().get_ref()
    if *reference == 42 { 0 } else { 1 }
}
""",
    "machine-explicit-destruction-keeps-the-original-address": """
type Guard {
    counter: ptr<mut i32>; address: ptr<read Guard>
    drop {
        let actual = core::ptr::from_ref(self)
        unsafe {
            if self.address == actual { *self.counter += 1 }
            else { *self.counter += 100 }
        }
    }
}
fn main() {
    var count = 0
    let pointer = core::ptr::from_mut(count)
    var first = core::mem::ManuallyDrop::new(Guard(pointer,core::ptr::null::<Guard>()))
    let one = first.get_mut()
    one.address = core::ptr::from_ref(one)
    unsafe { first.drop() }
    var second = core::mem::ManuallyDrop::new(Guard(pointer,core::ptr::null::<Guard>()))
    let two = second.get_mut()
    two.address = core::ptr::from_ref(two)
    let address = second.as_mut_ptr()
    unsafe { core::ptr::drop_in_place(address) }
    if count == 2 { 0 } else { 1 }
}
""",
    "machine-safe-storage-write-does-not-drop-raw-contents": """
type Guard {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let pointer = core::ptr::from_mut(count)
    {
        var storage = core::mem::MaybeUninit::<Guard>::uninit()
        let previous = storage.write(Guard(pointer,100))
        let current = storage.write(Guard(pointer,1))
        current.amount = 2
        let value = unsafe { storage.assume_init() }
    }
    if count == 2 { 0 } else { 1 }
}
""",
    "machine-manual-and-uninitialized-storage-ownership": """
type Guard {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let pointer = core::ptr::from_mut(count)
    { let value = core::mem::ManuallyDrop::new(Guard(pointer,10)) }
    if count != 0 { return 1 }
    {
        let value = core::mem::ManuallyDrop::new(Guard(pointer,1))
        let guard = value.into_inner()
    }
    { let value = core::mem::MaybeUninit::new(Guard(pointer,10)) }
    if count != 1 { return 2 }
    {
        let value = core::mem::MaybeUninit::new(Guard(pointer,2))
        let guard = unsafe { value.assume_init() }
    }
    {
        let cell = core::cell::UnsafeCell::new(Guard(pointer,3))
    }
    if count == 6 { 0 } else { 3 }
}
""",
    "machine-storage-references-and-interior-mutation": """
fn expose(value: read core::mem::MaybeUninit<i32>): read i32 from value {
    unsafe { value.assume_init_ref() }
}
fn main() {
    let zero = core::mem::MaybeUninit::<i64>::zeroed()
    let scalar = unsafe { zero.assume_init() }
    let storage = core::mem::MaybeUninit::new(42)
    let reference = expose(storage)
    let cell = core::cell::UnsafeCell::new(40i32)
    let pointer = cell.get()
    unsafe { pointer.write(42) }
    let inner = unsafe { cell.get_ref() }
    if scalar == 0i64 && *reference == 42 && *inner == 42 { 0 } else { 1 }
}
""",
    "machine-foreign-scalar-import-export-and-function-pointer": """
extern "C" {
    @link_name("abs")
    unsafe fn absolute(value: i32): i32;
    unsafe fn llabs(value: i64): i64;
}
@export_name("mettle_scalar_callback")
extern "C" fn callback(value: i8): i8 { value + 1 }
fn main() {
    let callback_pointer: extern "C" fn(i8): i8 = callback
    let magnitude = unsafe { absolute(-42) }
    let large = unsafe { llabs(-9223372036854775807i64) }
    if magnitude == 42 && callback_pointer(41) == 42i8 &&
       large == 9223372036854775807i64 { 0 } else { 1 }
}
""",
    "machine-profile-independent-numeric-operations": """
fn main() {
    let minimum = -128i8
    let (wrapped,overflow) = 127i8.overflowing_add(1)
    let checked = match 1u64.checked_sub(2) { none => 42, present(value) => 1 }
    let (negated,neg_overflow) = minimum.overflowing_neg()
    let (remainder,rem_overflow) = minimum.overflowing_rem(-1)
    let a = 1.0000000000000002f64
    let b = 0.9999999999999998f64
    let nan = f64::from_bits(0x7ff8000000000042u64)
    if wrapped == -128i8 && overflow && checked == 42 &&
       minimum.wrapping_neg() == minimum && minimum.saturating_neg() == 127i8 &&
       250u8.saturating_add(20) == 255u8 &&
       2u8.saturating_sub(20) == 0u8 &&
       negated == minimum && neg_overflow && remainder == 0i8 && rem_overflow &&
       1u8.wrapping_shl(9) == 2u8 &&
       1u8.rotate_left(9) == 2u8 &&
       0u128.leading_zeros() == 128u32 && 255u8.count_ones() == 8u32 &&
       0x1234u16.swap_bytes() == 0x3412u16 &&
       1u8.reverse_bits() == 128u8 &&
       nan.to_bits() == 0x7ff8000000000042u64 && nan.is_nan() &&
       (-0.0f32).is_sign_negative() && 1e-45f32.is_subnormal() &&
       2.5f64.round_ties_even() == 2.0f64 &&
       a.mul_add(b,-1.0f64) != a * b - 1.0f64 { 0 } else { 1 }
}
""",
    "machine-pointer-provenance-volatile-and-layout": """
fn main() {
    var value = 40i64
    let pointer = core::ptr::from_mut(value)
    let same = pointer.with_addr(pointer.addr()).wrapping_add(0)
    unsafe {
        pointer.write_volatile(41)
        same.write(same.read_volatile() + 1)
    }
    let null: ptr<read i64> = core::ptr::null()
    if value == 42i64 && pointer == same && null.is_null() &&
       core::mem::size_of::<u128>() == 16usize &&
       core::mem::align_of::<i64>() == 8usize &&
       !core::mem::needs_drop::<i64>() { 0 } else { 1 }
}
""",
    "machine-raw-pointers-and-unsafe-callable-capabilities": """
unsafe fn increment(value: ptr<mut i64>) { *value += 1 }
fn identity<T>(value: ptr<mut T>): ptr<mut T> { value }
fn main() {
    var value = 40i64
    let pointer = identity(mut value as ptr<mut i64>)
    unsafe {
        *pointer += 1
        let operation: unsafe fn(ptr<mut i64>): Unit = increment
        operation(pointer)
    }
    if value == 42i64 { 0 } else { 1 }
}
""",
    "machine-integer-widths-literals-and-conversions": """
fn accept(value: i64): i64 { value }
fn main() {
    let byte: u8 = 0xff
    let small: i8 = -128
    let word: u16 = 0xffff
    let signed: i16 = -32768
    let count: u32 = 0xffffffff
    let long: u64 = 18446744073709551615
    let minimum: i64 = -9223372036854775808
    let wide: u128 = 340282366920938463463374607431768211455
    let wide_min: i128 = -170141183460469231731687303715884105728
    let native: usize = 0b10_1010
    let offset: isize = -42
    let inferred = 42
    let values: [u16;2] = [20,22]
    let narrowed = 0x1234u32 as u8
    if byte == 255u8 && small as i64 == -128i64 &&
       word == 65535u16 && signed as i32 == -32768 &&
       count as i32 == -1 && long as i64 == -1 &&
       minimum as u64 == 9223372036854775808u64 &&
       wide >> 120u8 == 255u128 &&
       wide_min >> 127u16 == -1i128 &&
       native as i64 == 42 && offset as i32 == -42 &&
       accept(inferred) == 42 && narrowed == 52u8 &&
       values[0] + values[1] == 42u16 { 0 } else { 1 }
}
""",
    "machine-floating-ieee-rounding-and-saturating-casts": """
fn main() {
    let direct: f32 = 1.0000000596046448
    let through_double: f64 = 1.0000000596046448
    let zero: f64 = 0.0
    let infinity = 1.0f64 / zero
    let nan = zero / zero
    let negative_zero: f32 = -0.0
    let small: f32 = 1e-45
    let rounded = 16777217u32 as f32
    if direct == 1.00000011920928955078125f32 &&
       through_double as f32 == 1.0f32 &&
       1.0f32 / negative_zero < 0.0f32 &&
       infinity as i8 == 127i8 && (-infinity) as i8 == -128i8 &&
       nan as u64 == 0u64 && nan != nan &&
       3.9f64 as i16 == 3i16 && -3.9f64 as i16 == -3i16 &&
       small > 0.0f32 && rounded == 16777216.0f32 &&
       5.5f64 % 2.0f64 == 1.5f64 { 0 } else { 1 }
}
""",
    "receiver-form-priority-precedes-dereference": """
interface Choose { fn choose(): i32; }
type Value {
    value: i32
    mut fn choose(): i32 { self.value += 1; 1 }
}
impl Value implements Choose { fn choose(): i32 { 2 } }
type Native { fn choose(): i32 { 3 } }
impl read Native { fn choose(): i32 { 4 } }
fn main() {
    let value = Value(0)
    let native = Native()
    let view = read native
    if value.choose() == 2 && view.choose() == 4 { 0 } else { 1 }
}
""",
    "higher-ranked-interface-bound-retains-quantifier": """
interface Lifetime<region r> {}
type Universal {}
impl<region r> Universal implements Lifetime<region r> {}
fn accept<T: for<region r> Lifetime<region r>>(value: read T): i32 { 42 }
fn relay<T: for<region a> Lifetime<region a>>(value: read T): i32 { accept(value) }
fn main() {
    let value = Universal()
    if relay(value) == 42 { 0 } else { 1 }
}
""",
    "named-region-covariance-and-mutable-reborrow": """
copy type Ref<region r> { value: read i32 from r }
fn shorten<region a, region b>(
    value: take Ref<region a>
): Ref<region b> where region a: b { take value }
fn reborrow<region a, region b>(
    value: take (mut i32 from a)
): mut i32 from b where region a: b { take value }
fn main() {
    var value = 1
    let pointer = reborrow(mut value)
    *pointer = 42
    let wrapper = shorten(Ref(read value))
    if *wrapper.value == 42 { 0 } else { 1 }
}
""",
    "generic-lending-associated-region-call": """
interface Lending { type Item<region r>; }
type Owner {}
impl Owner implements Lending { type Item<region r> = read i32 from r; }
fn preserve<region r, T: Lending>(
    value: take <T implements Lending>::Item<region r>
): <T implements Lending>::Item<region r> { value }
fn main() {
    let value = 42
    if *preserve::<Owner>(read value) == 42 { 0 } else { 1 }
}
""",
    "opaque-associated-result-keeps-declared-interface": """
interface Readable { fn value(): i32; }
interface Factory { type Item: Readable; fn create(): Self::Item; }
copy type Number { value: i32 }
impl Number implements Readable { fn value(): i32 { self.value } }
type Maker {}
impl Maker implements Factory {
    type Item = Number
    fn create(): Number { Number(42) }
}
fn make(): some Factory { Maker() }
fn main() {
    let factory = make()
    let item = factory.create()
    if item.value() == 42 { 0 } else { 1 }
}
""",
    "mutable-erased-region-writeback": """
copy type Pair { first: i32; second: i32 }
interface Setter<region r> { mut fn set(value: read Pair from r): Unit; }
type Cell<region r> { value: read Pair from r }
impl<region r> Cell<region r> implements Setter<region r> {
    mut fn set(value: read Pair from r): Unit { self.value = read value }
}
fn set<region r>(cell: mut any Setter<region r>, value: read Pair from r) {
    cell.set(value)
}
fn main() {
    let original = Pair(0,0)
    let replacement = Pair(20,22)
    var cell = Cell(read original)
    set(cell,replacement)
    if cell.value.first + cell.value.second == 42 { 0 } else { 1 }
}
""",
    "erased-tail-retains-runtime-alignment": """
interface Readable { fn value(): i32; }
impl i32 implements Readable { fn value(): i32 { self } }
type Tail<T: unsized> { header: bool; value: T }
fn inspect(value: read Tail<any Readable>): i32 {
    if value.header { value.value.value() } else { 1 }
}
fn main() {
    let value = Tail(true,42)
    let erased: read Tail<any Readable> = read value
    if inspect(erased) == 42 { 0 } else { 1 }
}
""",
    "user-dereference-projections-evaluate-once": """
module core {
    pub module ops {
        pub interface Deref { type Target; fn deref(): read Self::Target; }
        pub interface DerefMut { type Target; mut fn deref_mut(): mut Self::Target; }
    }
}
type Inner {
    value: i32
    fn get(): i32 { self.value }
    mut fn increment(): Unit { self.value += 1 }
}
type Wrapper { inner: Inner; projections: i32 }
impl Wrapper implements core::ops::Deref {
    type Target = Inner
    fn deref(): read Inner { read self.inner }
}
impl Wrapper implements core::ops::DerefMut {
    type Target = Inner
    mut fn deref_mut(): mut Inner {
        self.projections += 1
        mut self.inner
    }
}
fn increment(value: mut Inner) { value.increment() }
fn main() {
    var wrapper = Wrapper(Inner(39),0)
    wrapper.increment()
    increment(wrapper)
    let operation: fn(mut Inner): Unit = increment
    operation(wrapper)
    if wrapper.get() == 42 && wrapper.projections == 3 { 0 } else { 1 }
}
""",
    "generic-declaration-spec": (Path(__file__).resolve().parents[1] / "examples/core/generics.mt").read_text(),
    "associated-families-and-typed-constants": """
interface Family {
    type Item<T: Copy>: Copy;
    const FLAG: bool;
}
type Number {}
impl Number implements Family {
    type Item<T: Copy> = (T, T)
    const FLAG = true
}
fn duplicate<T: Copy>(value: T): <Number implements Family>::Item<T> { (value,value) }
fn enabled<T: Family>(value: T): bool { T::FLAG }
fn main() {
    let pair = duplicate(21)
    if pair.0 + pair.1 == 42 && enabled(Number()) &&
        <Number implements Family>::FLAG { 0 } else { 1 }
}
""",
    "interface-disambiguation-and-shorthand": """
interface Readable { fn value(): i32; }
interface Alternate { fn value(): i32; }
type Number implements Readable {
    value: i32
    fn value(): i32 { self.value }
}
impl Number implements Alternate { fn value(): i32 { self.value + 1 } }
fn inspect<T: Readable>(value: T): i32 { value.value() }
fn main() {
    let value = Number(42)
    if inspect(value) == 42 &&
        <Number implements Alternate>::value(value) == 43 { 0 } else { 1 }
}
""",
    "borrowed-erased-mutation-and-superinterface-upcast": """
interface Readable { fn value(): i32; }
interface Counter: Readable { mut fn increment(): Unit; }
type Number { value: i32 }
impl Number implements Readable { fn value(): i32 { self.value } }
impl Number implements Counter { mut fn increment(): Unit { self.value += 1 } }
fn increment(value: mut any Counter) { value.increment() }
fn inspect(value: read any Readable): i32 { value.value() }
fn main() {
    var value = Number(41)
    increment(value)
    let child: read any Counter = read value
    let parent: read any Readable = child
    if inspect(child) == 42 && inspect(parent) == 42 { 0 } else { 1 }
}
""",
    "erased-returned-view-provenance": """
copy type Pair { first: i32; second: i32 }
interface Reader { fn pair(): read Pair from self; }
type Holder { value: Pair }
impl Holder implements Reader {
    fn pair(): read Pair from self { read self.value }
}
fn total(holder: read any Reader): i32 {
    let value = holder.pair()
    value.first + value.second
}
fn main() {
    let holder = Holder(Pair(20,22))
    let erased: read any Reader = read holder
    if total(Holder(Pair(20,22))) == 42 && erased.pair().first == 20 { 0 } else { 1 }
}
""",
    "opaque-self-results-and-generic-bound-dispatch": """
interface Doubled {
    fn value(): i32;
    fn doubled(): Self where Self: Sized;
}
type Number { value: i32 }
impl Number implements Doubled {
    fn value(): i32 { self.value }
    fn doubled(): Number { Number(self.value * 2) }
}
fn make(value: i32): some Doubled { Number(value) }
fn inspect<T: Doubled>(value: T): i32 { value.value() }
fn main() {
    let value = make(21)
    let doubled = value.doubled()
    if doubled.value() == 42 && inspect(doubled) == 42 { 0 } else { 1 }
}
""",
    "overloaded-compound-assignment-receiver-order": """
module core {
    pub module ops {
        pub interface AddAssign<Rhs> {
            mut fn add_assign(rhs: read Rhs): Unit;
        }
    }
}
type Number { value: i32 }
impl Number implements core::ops::AddAssign<Number> {
    mut fn add_assign(rhs: read Number): Unit { self.value += rhs.value }
}
fn select(values: mut [Number;1], trace: mut i32): mut Number from values {
    trace = trace * 10 + 1
    mut values[0]
}
fn argument(trace: mut i32): Number {
    trace = trace * 10 + 2
    Number(2)
}
fn main() {
    var trace = 0
    var values = [Number(1)]
    *select(values,trace) += argument(trace)
    if trace == 12 && values[0].value == 3 { 0 } else { 1 }
}
""",
    "slice-metadata-reborrowing-and-unsized-tails": """
type Tail<T: unsized> { header: i32; values: T }
fn total(values: read [i32]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn increment(values: mut [i32]) {
    for value in mut values { value += 1 }
}
fn tail_total(value: read Tail<[i32]>): i32 { value.header + total(value.values) }
fn main() {
    var values = [20,20]
    let exclusive: mut [i32] = mut values
    let borrowed: read [i32] = exclusive
    if total(borrowed) != 40 { return 1 }
    increment(exclusive)
    let tail = Tail(2,[20,20])
    let pointer: fn(read [i32]): i32 = total
    if pointer(exclusive) == 42 && tail_total(tail) == 42 &&
        total([20,22]) == 42 { 0 } else { 1 }
}
""",
    "erased-unsized-slice-metadata-survives-return": """
interface Total { fn value(): i32; }
impl [i32] implements Total {
    fn value(): i32 {
        var result = 0
        for value in self { result += value }
        result
    }
}
fn erase(values: read [i32]): read any Total from values { read values }
fn main() {
    let values = [20,22]
    let slice: read [i32] = read values
    let erased = erase(slice)
    if erased.value() == 42 { 0 } else { 1 }
}
""",
    "empty-repeat-contextual-injection": "fn main() { let values: [i32?;0] = [42;0]; 0 }\n",
    "unicode-scalar-and-byte-literals": r"""
copy type Scalars { character: char; byte: u8 }
fn inspect(character: char, byte: u8) {
    character == '\u{1f642}' && byte == b'\xff'
}
fn main() {
    let value = Scalars('🙂', b'\xff')
    let escaped = '\'' == '\u{27}' && '\\' == '\u{5c}' && '\0' == '\u{0}'
    let character = match value.character { '\0'..='\u{10ffff}' => true }
    let byte = match value.byte { b'\x00'..=b'\xff' => true }
    if inspect(value.character,value.byte) && escaped && character && byte { 0 } else { 1 }
}
""",
    "constant-array-lengths-are-profile-independent": """
fn main() {
    let values: [i32; 1 + 2] = [14; 6 / 2]
    let [first, second, third] = values
    if first + second + third == 42 { 0 } else { 1 }
}
""",
    "module-enum-and-associated-composition": """
module values {
    pub copy enum Choice { Empty; Value(i32) }
    pub copy type Counter {
        pub value: i32
        pub static fn make(value: i32 = 42): Self { Self(value) }
    }
}
import values::{Choice as Value, Counter}
fn main() {
    let item = Value::Value(Counter::make().value)
    match item { Value::Empty => 1, Value::Value(answer) => if answer == 42 { 0 } else { 1 } }
}
""",
    "fixed-array-rest-patterns-and-borrowed-subarrays": """
type Owned { value: i32 }
fn total(values: read [Owned; 2]) { values[0].value + values[1].value }
fn main() {
    let array = [Owned(1), Owned(20), Owned(22), Owned(2)]
    let answer = match array { [_, middle @ .., _] => total(middle) }
    let [first, rest @ ..] = [20, 10, 12]
    if answer == 42 && first + rest[0] + rest[1] == 42 { 0 } else { 1 }
}
""",
    "mutable-array-rest-is-field-disjoint": """
fn main() {
    var values = [20, 20, 0]
    match mut values {
        [first, middle @ ..] => { first += 1; middle[0] += 1 }
    }
    if values[0] + values[1] == 42 { 0 } else { 1 }
}
""",
    "product-rest-and-parameter-patterns": """
copy type Pair { first: i32; second: i32 }
fn sum((a,b): (i32,i32)) { a + b }
fn fields(Pair {first:a,second:b}: Pair) { a + b }
fn main() {
    let Pair { first, .. } = Pair(42,0)
    if first == 42 && sum((20,22)) == 42 && fields(Pair(20,22)) == 42 { 0 } else { 1 }
}
""",
    "uninhabited-payloads-and-inferred-failure": """
enum Empty {}
copy enum Result { Impossible(Never); Value(i32) }
fn impossible(value: Empty): i32 { match value {} }
fn fail() throws i32 { throw 7 }
fn main() {
    let failed = capture fail()
    let error = match failed { failure(error) => error }
    let value = match Result::Value(42) { Result::Value(value) => value }
    if error == 7 && value == 42 { 0 } else { 1 }
}
""",
    "optional-chaining-skips-arguments": """
copy type Counter {
    value: i32
    fn get(extra: i32) { self.value + extra }
    mut fn increment() { self.value += 1 }
}
fn mark(log: mut i32) { log += 1; 0 }
fn main() {
    var log = 0
    let absent: Counter? = none
    var present_counter: Counter? = present(Counter(41))
    let skipped = absent?.get(mark(log))
    let _ = present_counter?.increment()
    let answer = present_counter?.get(mark(log))
    if log == 1 && (answer ?? 0) == 42 && (skipped ?? 0) == 0 &&
       (present_counter?.value ?? 0) == 42 { 0 } else { 1 }
}
""",
    "optional-method-propagates-typed-failure": """
copy type Value {
    value: i32
    fn checked(): i32 throws i32 { if self.value < 0 { throw 7 }; self.value }
}
fn main() {
    let valid: Value? = present(Value(42))
    let invalid: Value? = present(Value(-1))
    let absent: Value? = none
    let good = capture valid?.checked()
    let bad = capture invalid?.checked()
    let empty = capture absent?.checked()
    let answer = match good { success(value) => value ?? 0, failure(_) => 0 }
    let failed = match bad { success(_) => false, failure(error) => error == 7 }
    let skipped = match empty { success(none) => true, success(present(_)) => false, failure(_) => false }
    if answer == 42 && failed && skipped { 0 } else { 1 }
}
""",
    "supplied-arguments-before-ordered-defaults": """
fn mark(log: mut i32, digit: i32) { log = log * 10 + digit; digit }
fn ordered(log: mut i32, a: i32, b: i32 = mark(log, 2), c: i32 = mark(log, 3)) { a + b + c }
fn main() {
    var log = 0
    let value = ordered(a: mark(mut log, 1), log: mut log)
    if log == 123 && value == 6 { 0 } else { 1 }
}
""",
    "defaults-read-earlier-parameters-and-receiver": """
fn sum(a: i32, b: i32 = a + 1, c: i32 = b + 1) { a + b + c }
type Counter { value: i32; mut fn increment(amount: i32 = self.value) { self.value += amount } }
fn main() {
    var counter = Counter(21)
    counter.increment()
    if sum(13) == 42 && sum(c: 20, a: 10, b: 12) == 42 && counter.value == 42 { 0 } else { 1 }
}
""",
    "borrowed-default-owners-and-results": """
type Value { value: i32 }
fn answer(a: read Value, b: read Value = a) { a.value + b.value }
fn temporary(a: read Value = Value(42)) { a.value }
fn main() {
    let value = Value(21)
    if answer(value) == 42 && temporary() == 42 { 0 } else { 1 }
}
""",
    "default-failure-cleans-pending-arguments": """
type Guard<region r> { count: mut i32 from r; drop { *self.count += 1 } }
fn fail(): i32 throws i32 { throw 7 }
fn consume(value: take Guard, answer: i32 = try fail()): i32 throws i32 { answer }
fn main() {
    var drops = 0
    let _ = capture consume(Guard(mut drops))
    if drops == 1 { 0 } else { 1 }
}
""",
    "custom-init-defaults-branches-and-early-return": """
copy type Point {
    x: i32
    y: i32
    init(x: i32, early: bool = true) {
        self.x = x
        if early { self.y = 42 - x; return }
        self.y = -x
    }
    fn sum() { self.x + self.y }
}
fn main() { if Point(20).sum() == 42 && Point(20, false).sum() == 0 { 0 } else { 1 } }
""",
    "failed-constructor-drops-fields-not-self": """
type Guard<region r> { count: mut i32 from r; drop { *self.count += 1 } }
type Holder<region r> {
    guard: Guard
    count: mut i32 from r
    init(guard: take Guard, count: take (mut i32)) throws i32 {
        self.guard = take guard
        self.count = take count
        throw 7
    }
    drop { *self.count += 100 }
}
fn main() {
    var fields = 0
    var whole = 0
    let _ = capture Holder(Guard(mut fields), mut whole)
    if fields == 1 && whole == 0 { 0 } else { 1 }
}
""",
    "capture-composes-across-expressions": """
copy enum Error { Bad }
fn value(input: i32): i32 throws Error { if input < 0 { throw Error::Bad }; input }
fn main() {
    let first = capture (value(20) + value(22))
    let second = capture { let first = try value(20); first + value(-1) }
    let answer = match first { success(answer) => answer, failure(_) => 0 }
    let failed = match second { success(_) => false, failure(Error::Bad) => true }
    if answer == 42 && failed { 0 } else { 1 }
}
""",
    "capture-failure-cleans-local-owners": """
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
fn fail(): i32 throws i32 { throw 7 }
fn main() {
    var log = 40
    let result = capture { let guard = Guard(mut log); fail() + 1 }
    { let guard = Guard(mut log) }
    match result { success(_) => 1, failure(error) => if error == 7 && log == 42 { 0 } else { 1 } }
}
""",
    "optional-injection-preserves-nesting": """
fn answer(): i32? { 42 }
fn inspect(value: i32?) { value ?? 0 }
fn main() {
    let nested: i32?? = 42
    let values: [i32?; 2] = [20, 22]
    let joined = if true { present(42) } else { 0 }
    let from_nested = match nested { none => 0, present(inner) => inner ?? 0 }
    if from_nested == 42 && inspect(42) == 42 && (answer() ?? 0) == 42 &&
       (values[0] ?? 0) + (values[1] ?? 0) == 42 && (joined ?? 0) == 42 { 0 } else { 1 }
}
""",
    "range-and-at-patterns-are-exhaustive": """
fn classify(value: i32) {
    match value {
        -2147483648..0 => 0,
        answer @ 0..=42 => answer,
        43..=2147483647 => 0
    }
}
fn main() { if classify(42) == 42 && classify(-1) == 0 && classify(43) == 0 { 0 } else { 1 } }
""",
    "while-let-and-array-mutable-iteration": """
fn next(index: mut i32): i32? {
    index += 1
    if index <= 3 { present(index) } else { none }
}
fn main() {
    var index = 0
    var sum = 0
    while let present(value) = next(index) { sum += value }
    var values = [20, 20]
    for value in mut values { value += 1 }
    if sum == 6 && values[0] + values[1] == 42 { 0 } else { 1 }
}
""",
    "array-loop-destructures-tuples": """
fn main() {
    var sum = 0
    for (first, second) in [(10, 11), (10, 11)] { sum += first + second }
    if sum == 42 { 0 } else { 1 }
}
""",
    "nested-optionals-spec": (Path(__file__).resolve().parents[1] / "examples/spec/nested-optionals.mt").read_text(),
    "typed-outcome-spec": (Path(__file__).resolve().parents[1] / "examples/spec/typed-outcome.mt").read_text(),
    "defaults-and-methods-spec": (Path(__file__).resolve().parents[1] / "examples/spec/defaults-and-methods.mt").read_text(),
    "enum-payloads-and-exhaustiveness": """
copy enum Number { Empty; Scalar(i32); Pair { first: i32; second: i32 } }
fn value(number: Number) {
    match number {
        Number::Empty => 0,
        Number::Scalar(value) => value,
        Number::Pair { second: b, first: a } => a + b
    }
}
fn main() {
    if value(Number::Pair(second: 22, first: 20)) == 42 &&
       value(Number::Scalar(42)) == 42 && value(Number::Empty) == 0 { 0 } else { 1 }
}
""",
    "sum-pattern-guards-do-not-consume": """
type Owned { value: i32 }
enum Result { Value(Owned); Empty }
fn extract(value: take Result) {
    match take value {
        Result::Value(item) if item.value < 0 => 1,
        Result::Value(item) => item.value,
        Result::Empty => 0
    }
}
fn main() { if extract(Result::Value(Owned(42))) == 42 { 0 } else { 1 } }
""",
    "sum-or-pattern-bindings": """
copy enum Value { First(i32); Second(i32); Empty }
fn extract(value: Value) {
    match value {
        Value::First(number) | Value::Second(number) => number,
        Value::Empty => 0
    }
}
fn main() {
    if extract(Value::First(42)) == 42 && extract(Value::Second(42)) == 42 { 0 } else { 1 }
}
""",
    "typed-propagation-preserves-failure-kind": """
copy enum Error { Bad; Missing }
fn validate(value: i32): i32 throws Error {
    if value < 0 { throw Error::Bad }
    value
}
fn twice(value: i32) throws Error { (try validate(value)) * 2 }
fn main() {
    let first = capture twice(21)
    let second = capture twice(-1)
    let answer = match first { success(value) => value, failure(_) => 0 }
    let failed = match second { success(_) => false, failure(Error::Bad) => true, failure(Error::Missing) => false }
    if answer == 42 && failed { 0 } else { 1 }
}
""",
    "owned-sum-cleanup-and-partial-move": """
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
enum Container { Held(Guard); Empty }
fn main() {
    var log = 40
    { let value = Container::Held(Guard(mut log)); match take value { Container::Held(guard) => { let moved = guard }, Container::Empty => {} } }
    { let empty = Container::Empty }
    { let value = present(Guard(mut log)); match take value { present(guard) => {}, none => {} } }
    if log == 42 { 0 } else { 1 }
}
""",
    "match-mut-retains-original-storage": """
copy enum Value { Number(i32); Empty }
fn main() {
    var value = Value::Number(40)
    match mut value { Value::Number(number) => { number += 2 }, Value::Empty => {} }
    match value { Value::Number(number) => if number == 42 { 0 } else { 1 }, Value::Empty => 1 }
}
""",
    "array-tuple-range-composition": """
fn main() {
    let tuple = (20, 22)
    var values: [i32; 3] = [tuple.0, tuple.1, 0]
    var sum = 0
    for index in 0..2 { sum += values[index] }
    values[2] = sum
    let [first, second, third] = values
    let (a, b) = tuple
    if a + b == 42 && first + second == third { 0 } else { 1 }
}
""",
    "array-owned-consuming-iteration": """
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
copy type Logs { first: i32; second: i32 }
fn main() {
    var logs = Logs(20, 20)
    { let array = [Guard(mut logs.first), Guard(mut logs.second)]; for guard in take array {} }
    if logs.first + logs.second == 42 { 0 } else { 1 }
}
""",
    "inclusive-range-end-does-not-overflow": """
fn main() {
    var count = 0
    for value in 2147483646..=2147483647 { count += 1 }
    for value in 4..2 { return 1 }
    if count == 2 { 0 } else { 1 }
}
""",
    "optional-coalesce-is-short-circuiting": """
fn fallback(value: mut i32) { value += 1; 42 }
fn main() {
    var calls = 0
    let first: i32? = present(42)
    let absent: i32? = none
    let a = first ?? fallback(calls)
    let b = absent ?? fallback(calls)
    if a == 42 && b == 42 && calls == 1 { 0 } else { 1 }
}
""",
    "conditional-and-irrefutable-patterns": """
fn inspect_presence(value: i32?) { let present(answer) = value else { return 0 }; answer }
fn main() {
    let pair = (20, 22)
    let (a, b) = pair
    let result = if let present(value) = present(a + b) { value } else { 0 }
    if result == 42 && inspect_presence(present(42)) == 42 && inspect_presence(none) == 0 { 0 } else { 1 }
}
""",
    "loop-is-a-function-tail": "fn main() { loop { break 0 } }\n",
    "loop-result-inference-and-joins": """
copy type Pair { first: i32; second: i32 }
fn choose(flag: bool) {
    loop {
        if flag { break Pair(20, 22) }
        break Pair(21, 21)
    }
}
fn truth() { loop { break true } }
fn main() {
    let first = choose(true)
    let second = choose(false)
    if truth() && first.first + first.second == 42 && second.first + second.second == 42 { 0 } else { 1 }
}
""",
    "labeled-break-crosses-inner-loop": """
fn answer() {
    label outer: loop {
        loop { break label outer 42 }
    }
}
fn main() { if answer() == 42 { 0 } else { 1 } }
""",
    "labeled-continue-cleans-each-exited-scope": """
type Guard<region r> { count: mut i32 from r; drop { *self.count += 1 } }
copy type Counts { outer: i32; inner: i32 }
fn main() {
    var counts = Counts(0, 0)
    var iterations = 0
    label again: while iterations < 3 {
        let outer = Guard(mut counts.outer)
        iterations += 1
        loop {
            let inner = Guard(mut counts.inner)
            continue label again
        }
    }
    if counts.outer == 3 && counts.inner == 3 { 0 } else { 1 }
}
""",
    "labeled-while-condition-transfers": """
fn main() {
    var count = 0
    label again: while {
        count += 1
        if count < 3 { continue label again }
        if count == 3 { break label again }
        true
    } { return 1 }
    if count == 3 { 0 } else { 1 }
}
""",
    "break-result-evaluates-before-cleanup": """
type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var value = 42
    let answer = loop {
        let guard = Guard(mut value)
        break *guard.value
    }
    if answer == 42 && value == 0 { 0 } else { 1 }
}
""",
    "owned-loop-result-and-discard": """
type Guard<region r> { value: mut i32 from r; drop { *self.value += 1 } }
fn choose(value: mut i32, flag: bool): Guard {
    loop {
        if flag { break Guard(mut value) }
        break Guard(mut value)
    }
}
fn main() {
    var value = 40
    { let result = choose(value, true); let moved = result }
    let _ = loop { break Guard(mut value) }
    if value == 42 { 0 } else { 1 }
}
""",
    "loop-result-view-parent-restoration": """
fn main() {
    var value = 40
    let parent = mut value
    let child = loop { break mut *parent }
    *child += 1
    *parent += 1
    if value == 42 { 0 } else { 1 }
}
""",
    "break-payload-can-transfer-to-another-target": """
fn answer() {
    label outer: loop {
        loop { break { break label outer 42 } }
    }
}
fn main() { if answer() == 42 { 0 } else { 1 } }
""",
    "label-shadowing-is-lexical": """
fn main() {
    let first = label target: loop {
        let inner = label target: loop { break label target 20 }
        break label target inner + 22
    }
    if first == 42 { 0 } else { 1 }
}
""",
    "nonlocal-break-establishes-initialization": """
fn main() {
    let answer: i32
    label outer: loop {
        loop { answer = 42; break label outer }
    }
    if answer == 42 { 0 } else { 1 }
}
""",
    "aliases-and-static-associated-functions": """
alias Position = Coordinate
alias Coordinate = Point
alias Number = i32
copy type Point {
    x: Number
    y: Number
    static fn origin(): Self { Self(0, 0) }
    static fn make(x: Number, y: Number): Self { Self(x, y) }
    static fn answer() { Self::make(20, 22).sum() }
    fn sum() { self.x + self.y }
}
fn same(value: Position): Point { value }
fn main() {
    let origin = Position::origin()
    let point: Coordinate = Position::make(y: 22, x: 20)
    if same(point).sum() == 42 && Point::answer() == 42 && origin.sum() == 0 { 0 } else { 1 }
}
""",
    "qualified-methods-retain-access-modes": """
alias RoomCounter = Counter
type Counter {
    value: i32
    fn get() { self.value }
    mut fn add(value: i32) { self.value += value }
    take fn finish() { self.value }
}
fn main() {
    var counter = Counter(20)
    RoomCounter::add(counter, 22)
    let observed = Counter::get(counter)
    if observed == 42 && RoomCounter::finish(counter) == 42 { 0 } else { 1 }
}
""",
    "associated-factory-preserves-drop-ownership": """
alias OwnedGuard = Guard
type Guard<region r> {
    counter: mut i32 from r
    static fn make(counter: mut i32): Guard { Guard(mut counter) }
    drop { *self.counter += 1 }
}
fn main() {
    var counter = 40
    {
        let first = OwnedGuard::make(counter)
        let moved = first
    }
    { let second = Guard::make(counter) }
    if counter == 42 { 0 } else { 1 }
}
""",
    "view-alias-preserves-reborrow-and-return": """
alias SharedInt = read i32
alias ExclusiveInt = mut i32
fn identity(value: read i32): SharedInt from value { read value }
fn inspect(value: read (ExclusiveInt)) { *value }
fn main() {
    var value = 40
    { let exclusive: ExclusiveInt = mut value; *exclusive += 2; let observed = inspect(exclusive) }
    let view: SharedInt = identity(value)
    if *view == 42 { 0 } else { 1 }
}
""",
    "associated-result-inference-and-divergence": """
alias Stop = Never
type Arithmetic {
    static fn twice(value: i32) { Self::add(value, value) }
    static fn add(first: i32, second: i32) { first + second }
    static fn forever(): Stop { loop {} }
    static fn inferred_forever() { Self::forever() }
}
fn main() { if Arithmetic::twice(21) == 42 { 0 } else { 1 } }
""",
    "borrowed-diverging-argument": """
fn observe(value: read i32) {}
fn early() { observe({ return 42 }); 0 }
fn main() { if early() == 42 { 0 } else { 1 } }
""",
    "borrowed-view-handle-parameter": """
fn observe(value: (mut i32)) { *value }
fn observe_read(value: read (read i32)) { *value }
fn main() {
    var value = 42
    {
        let exclusive = mut value
        if observe(exclusive) != 42 { return 1 }
    }
    let view = read value
    if observe_read(view) == 42 { 0 } else { 1 }
}
""",
    "nested-view-method-receivers": """
type Counter {
    value: i32
    fn get() { self.value }
    mut fn add(value: i32) { self.value += value }
}
fn main() {
    var counter = Counter(21)
    { let first = read counter; let second = read first; if second.get() != 21 { return 1 } }
    { var first = mut counter; let second = mut first; second.add(second.get()) }
    if counter.value == 42 { 0 } else { 1 }
}
""",
    "definite-view-writeback-releases-old-source": """
copy type Reader<region r> { value: read i32 from r }
fn set(reader: mut Reader, source: read i32, flag: bool) {
    if flag { reader.value = read source } else { reader.value = read source }
}
fn forward(reader: mut Reader, source: read i32) { set(reader, source, false) }
fn main() {
    var first = 40
    let second = 42
    var reader = Reader(read first)
    forward(reader, second)
    first = 0
    if *reader.value == 42 && first == 0 { 0 } else { 1 }
}
""",
    "nested-view-returned-origins": """
copy type Payload<region r> { value: read i32 from r }
copy type Reader<region r> { inner: read Payload from r }
fn get(reader: read Reader): read i32 from reader { reader.inner.value }
fn main() {
    let value = 42
    let payload = Payload(read value)
    let reader = Reader(read payload)
    if *get(reader) == 42 { 0 } else { 1 }
}
""",
    "owned-phi-and-loop-transfers": """
type Guard<region r> { counter: mut i32 from r; drop { *self.counter += 1 } }
fn route(value: take Guard, flag: bool): Guard from value {
    if flag { value } else { value }
}
fn main() {
    var counter = 0
    var index = 0
    while index < 2 {
        let owned = route(Guard(mut counter), index == 0)
        index += 1
    }
    if counter == 2 { 0 } else { 1 }
}
""",
    "destructor-writeback-through-owned-call": """
copy type Reader<region r> { value: read i32 from r }
type Writer<region a, region b> {
    target: mut Reader from a
    source: read i32 from b
    drop { self.target.value = self.source }
}
fn release(writer: take Writer) {}
fn main() {
    let first = 40
    let second = 42
    var reader = Reader(read first)
    release(Writer(mut reader, read second))
    if *reader.value == 42 { 0 } else { 1 }
}
""",
    "nested-returned-view-projection": """
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
fn whole(reader: read Reader): read Pair from reader { reader.value }
fn field(reader: read Reader): read i32 from reader { read reader.value.second }
fn main() {
    var pair = Pair(20, 22)
    let reader = Reader(read pair)
    let observed = whole(reader).first + *field(reader)
    pair.second = 0
    if observed == 42 && pair.second == 0 { 0 } else { 1 }
}
""",
    "drop-sibling-does-not-retain-view": """
copy type Reader<region r> { value: read i32 from r }
type Marker { drop {} }
type Bundle<region r> { reader: Reader<region r>; marker: Marker }
fn main() {
    var value = 40
    var bundle = Bundle(Reader(read value), Marker())
    let observed = *bundle.reader.value
    value = 42
    bundle = Bundle(Reader(read value), Marker())
    if observed == 40 { 0 } else { 1 }
}
""",
    "view-writeback-through-calls": """
copy type Reader<region r> { value: read i32 from r }
fn set(reader: mut Reader, source: read i32) { reader.value = read source }
fn forward(reader: mut Reader, source: read i32) { set(reader, source) }
fn main() {
    let first = 40
    let second = 42
    var reader = Reader(read first)
    forward(reader, second)
    if *reader.value == 42 { 0 } else { 1 }
}
""",
    "stored-read-last-use": """
fn main() {
    var value = 40
    let view = read value
    let copied = view
    let observed = *copied + *view
    value = 42
    if observed == 80 && value == 42 { 0 } else { 1 }
}
""",
    "exclusive-parent-restoration": """
fn main() {
    var value = 40
    let parent = mut value
    let child = mut *parent
    *child += 1
    *parent += 1
    if value == 42 { 0 } else { 1 }
}
""",
    "stored-view-fields": """
copy type Pair { first: i32; second: i32 }
fn main() {
    var pair = Pair(20, 20)
    let first = mut pair.first
    let second = mut pair.second
    *first += 1
    *second += 1
    if pair.first + pair.second == 42 { 0 } else { 1 }
}
""",
    "view-bearing-product": """
copy type Reader<region r> { value: read i32 from r }
fn main() {
    var value = 40
    let reader = Reader(read value)
    let copied = reader
    let observed = *copied.value
    value = 42
    if observed == 40 && value == 42 { 0 } else { 1 }
}
""",
    "returned-view-source": """
fn identity(value: read i32): read i32 from value { read value }
fn main() {
    var value = 40
    let view = identity(value)
    let observed = *view
    value = 42
    if observed == 40 && value == 42 { 0 } else { 1 }
}
""",
    "returned-view-multiple-sources": """
fn choose(first: read i32, second: read i32, flag: bool): read i32 from (first, second) {
    if flag { read first } else { read second }
}
fn main() {
    let first = 40
    let second = 42
    if *choose(first, second, false) == 42 && *choose(first, second, true) == 40 { 0 } else { 1 }
}
""",
    "direct-borrow-temporary-extension": """
type Counter { value: i32 }
fn main() {
    let view = read Counter(42)
    if view.value == 42 { 0 } else { 1 }
}
""",
    "two-phase-method-receiver": """
type Counter {
    value: i32
    fn get() { self.value }
    mut fn add(value: i32) { self.value += value }
}
fn main() {
    var counter = Counter(21)
    counter.add(counter.get())
    if counter.value == 42 { 0 } else { 1 }
}
""",
    "destructor-scope-and-temporary": """
type Guard<region r> {
    value: i32
    log: mut i32 from r
    drop { *self.log = self.value }
}
fn main() {
    var log = 0
    { let guard = Guard(40, mut log) }
    let first = log
    { let view = read Guard(42, mut log); let observed = view.value }
    if first == 40 && log == 42 { 0 } else { 1 }
}
""",
    "destructor-move-and-return": """
type Guard<region r> {
    log: mut i32 from r
    drop { *self.log += 1 }
}
fn move_out<region r>(log: mut i32 from r): Guard<region r> { Guard(mut log) }
fn consume<region r>(value: take Guard<region r>) { let other = value }
fn main() {
    var log = 40
    consume(move_out(log))
    if log == 41 { 0 } else { 1 }
}
""",
    "destructor-partial-initialization": """
type Guard<region r> {
    value: i32
    log: mut i32 from r
    drop { *self.log += self.value }
}
fn main() {
    var log = 40
    {
        let guard: Guard
        guard.value = 2
        guard.log = mut log
    }
    if log == 42 { 0 } else { 1 }
}
""",
    "destructor-early-return": """
type Guard<region r> {
    log: mut i32 from r
    drop { *self.log += 1 }
}
fn early(log: mut i32) { let guard = Guard(mut log); return }
fn main() {
    var log = 41
    early(log)
    if log == 42 { 0 } else { 1 }
}
""",
    "parameter-ownership": (Path(__file__).resolve().parents[1] / "examples/core/ownership.mt").read_text(),
    "borrow-disjoint-and-reborrow": """
type Counter { value: i32 }
type Pair { first: Counter; second: Counter }
fn increment(c: mut Counter) { c.value += 1 }
fn inspect(c: Counter) { c.value }
fn both(a: mut Counter, b: mut Counter) {
    increment(a)
    increment(b)
    inspect(a) + inspect(b)
}
fn main() {
    var pair = Pair(Counter(20), Counter(20))
    let result = both(pair.first, pair.second)
    if result == 42 && inspect(pair.first) == 21 { 0 } else { 1 }
}
""",
    "borrow-copy-snapshot": """
fn change(value: mut i32) { value = 100; 1 }
fn combine(first: i32, second: i32) { first + second }
fn main() {
    var value = 41
    let result = combine(value, change(value))
    if result == 42 && value == 100 { 0 } else { 1 }
}
""",
    "borrow-temporaries": """
type Counter { value: i32 }
fn inspect(c: Counter) { c.value }
fn increment(c: mut Counter) { c.value += 1; c.value }
fn main() {
    if inspect(Counter(42)) == 42 && increment(Counter(41)) == 42 { 0 } else { 1 }
}
""",
    "loan-control-flow": """
fn combine(value: read i32, extra: i32) { value + extra }
fn choose(flag: bool) {
    var value = 40
    combine(value, if flag { return 42 } else { 2 })
}
fn unused() {
    var value = 40
    combine(value, { value = 42; return value })
}
fn main() {
    if choose(true) == 42 && choose(false) == 42 && unused() == 42 { 0 } else { 1 }
}
""",
    "field-mutation": """
copy type Pair { x: i32; y: i32 }
fn main() {
    var p = Pair(1, 2)
    p.x += { p.x = 5; 1 }
    (p.y) = p.x * 7
    if p.x == 6 && p.y == 42 { 0 } else { 1 }
}
""",
    "field-initialization": """
copy type Empty {}
type Inner { value: i32 }
type Outer { inner: Inner; tag: Empty }
fn main() {
    let partial: Outer
    partial.inner.value = 42
    let completed: Outer
    completed.inner.value = 42
    completed.tag = Empty()
    let moved = completed
    if partial.inner.value == 42 && moved.inner.value == 42 { 0 } else { 1 }
}
""",
    "field-branch-join": """
copy type Pair { x: i32; y: i32 }
fn sum(p: Pair) { p.x + p.y }
fn choose(flag: bool) {
    let p: Pair
    if flag { p.x = 40 } else { p.x = 41 }
    p.y = 2
    sum(p)
}
fn main() { if choose(true) == 42 && choose(false) == 43 { 0 } else { 1 } }
""",
    "field-loop-bindings": """
copy type Pair { x: i32; y: i32 }
fn sum(p: Pair) { p.x + p.y }
fn main() {
    var n = 0
    var total = 0
    while n < 3 {
        let p: Pair
        p.x = n
        p.y = 1
        total += sum(p)
        n += 1
    }
    if total == 6 { 0 } else { 1 }
}
""",
    "owned-moves-and-take": """
type Counter { value: i32 }
fn finish(counter: take Counter) { counter.value }
fn main() {
    var first = Counter(40)
    let second = first
    first = Counter(42)
    let _ = second
    let _ = second.value
    let observed = second.value
    let result = finish(first)
    if observed == 40 && result == 42 { 0 } else { 1 }
}
""",
    "partial-moves-and-reinit": """
type Leaf { value: i32 }
type Pair { first: Leaf; second: Leaf }
fn main() {
    var p = Pair(Leaf(20), Leaf(22))
    let first = p.first
    let observed = p.second.value
    p.first = Leaf(20)
    let completed = p
    if first.value + completed.second.value == 42 &&
        completed.first.value == 20 && observed == 22 { 0 } else { 1 }
}
""",
    "take-copy-fields": """
copy type Pair { x: i32; y: i32 }
fn consume(value: take i32) { value }
fn main() {
    var p = Pair(20, 22)
    let x = take p.x
    p.x = x
    let _ = consume(p.y)
    p.y = 22
    if p.x + p.y == 42 { 0 } else { 1 }
}
""",
    "loop-move-reinit": """
type Counter { value: i32 }
fn main() {
    var counter = Counter(0)
    var n = 0
    while n < 3 {
        let previous = counter
        counter = Counter(previous.value + 1)
        n += 1
    }
    if counter.value == 3 { 0 } else { 1 }
}
""",
    "copy-values": (Path(__file__).resolve().parents[1] / "examples/core/values.mt").read_text(),
    "product-composition": """
copy type Outer { inner: Inner }
copy type Inner { value: i32 }
fn make() { Outer(Inner(42)) }
fn recursive(flag: bool) {
    if flag { make() } else { recursive(true) }
}
fn main() {
    let first = recursive(false)
    let second = first
    let chosen = if false { make() } else { second }
    if first.inner.
        value == 42 && chosen.inner.value == 42 { 0 } else { 1 }
}
""",
    "product-evaluation-order": """
copy type Pair {
    first: i32
    second: i32
}
fn main() {
    var state = 0
    let pair = Pair(second: { state = 2; state }, first: { state += 1; state })
    if pair.first == 3 && pair.second == 2 && state == 3 { 0 } else { 1 }
}
""",
    "product-unit-and-bool": """
copy type Empty {}
copy type Flag {
    tag: Empty
    completed: Unit
    enabled: bool
}
fn swap(flag: Flag) { Flag(flag.tag, flag.completed, !flag.enabled) }
fn Unit(value: i32) { value }
fn main() {
    let placeholder: Flag
    let _ = placeholder.enabled
    var flag = Flag(Empty(), (), true)
    let snapshot = flag
    flag = swap(flag)
    if snapshot.enabled && !flag.enabled && flag.completed == () && Unit(42) == 42 { 0 } else { 1 }
}
""",
    "control": """
fn total(limit: i32) {
    var sum = 0
    var current = 0
    while current < limit {
        current += 1
        if current == 2 {
            continue
        }
        sum += current
        if current == 6 {
            break
        }
    }
    sum
}
fn main(): i32 {
    let result: i32
    if total(10) == 19 {
        result = 0
    } else {
        result = 1
    }
    result
}
""",
    "recursive": """
fn odd(n: i32) {
    if n == 0 { false } else { even(n - 1) }
}
fn even(n: i32) {
    if n == 0 { true } else { odd(n - 1) }
}
fn main() { if even(10) && odd(9) { 0 } else { 1 } }
""",
    "recursive-operator-inference": """
fn negate(n: i32) { if n == 0 { true } else { !invert(n - 1) } }
fn invert(n: i32) { negate(n) }
fn bit(n: i32) { if n == 0 { true } else { both(n - 1) } }
fn both(n: i32) { bit(n) & bit(n) }
fn main() { if negate(2) && bit(3) { 0 } else { 1 } }
""",
    "short-circuit": """
fn bad(): bool {
    let _ = 1 / 0
    true
}
fn main() {
    if false && bad() { return 1 }
    if true || bad() { 0 } else { 2 }
}
""",
    "minimum": """
fn main() {
    let a = -2_147_483_648i32
    let b = -(2147483648)
    if a == b && (a >> 31) == -1 && !false && !0 == -1 { 0 } else { 1 }
}
""",
    "unit-never": """
fn stop(): Never { loop {} }
fn inferred_stop() { loop {} }
fn unit_value(): Unit { () }
fn ignored() { let _ = 42 }
fn choose(flag: bool) {
    if flag { 42 } else { inferred_stop() }
}
fn main() {
    let a: Unit = unit_value()
    let b: Unit = ignored()
    let _ = (a)
    if choose(true) == 42 && a == b { 0 } else { 1 }
}
""",
    "nested-values": """
fn main() {
    let x = if true {
        if false { 1 } else { 40 }
    } else { 2 }
    let y = { let a = 1; a + 1 }
    if x + y == 42 { 0 } else { 1 }
}
""",
    "labels-and-order": """
fn combine(first: i32, second: i32) { first * 10 + second }
fn main() {
    var state = 0
    let result = combine(
        second: { state = 2; state },
        first: { state += 1; state }
    )
    if result == 32 && state == 3 { 0 } else { 1 }
}
""",
    "compound-order": """
fn main() {
    var x = 1
    x += { x = 5; 1 }
    if x == 6 { 0 } else { 1 }
}
""",
    "loop-initialization": """
fn main() {
    let result: i32
    loop {
        result = 42
        break
    }
    var count = 0
    while count < 3 {
        let fresh = count
        count = fresh + 1
    }
    if result == 42 && count == 3 { 0 } else { 1 }
}
""",
    "dead-returns": """
fn value() {
    if false { return false }
    while false { return () }
    42
}
fn truth() {
    let _ = false && { return 123 }
    true
}
fn main() { if value() == 42 && truth() { 0 } else { 1 } }
""",
    "unreachable-operands": """
fn combine(x: i32, y: i32): i32 { x + y }
fn condition() {
    while { return 42 } { return false }
}
fn arguments() {
    combine({ return 42 }, { return false })
}
fn main() { if condition() == 42 && arguments() == 42 { 0 } else { 1 } }
""",
    "grouped-conditions": """
fn stop() {
    let _ = (false) && { return 7 }
    loop {}
}
fn choose() {
    if ((false)) { return false }
    while (false) { return () }
    if (true) { 42 } else { stop() }
}
fn main() { if choose() == 42 { 0 } else { 1 } }
""",
    "discard-and-shadow": """
fn main() {
    let uninitialized: i32
    let _ = uninitialized
    let x = 41
    let x = x + 1
    if x == 42 { 0 } else { 1 }
}
""",
    "bool-bits": """
fn main() {
    var value = true
    value &= false
    value |= true
    value ^= false
    if value && false < true && true >= false { 0 } else { 1 }
}
""",
    "separators": "fn add(x: i32, y: i32): i32 { x +\n y }\n"
                  "fn main(): i32 { let n = add(\n 20,\n 22,\n)\n"
                  "if n == 42\n{ 0 }\n/* outer\n/* inner */\n*/else\n{ 1 }\n}\n",
    "semicolon-unit": "fn ignored() { 42; }\nfn main() { let u: Unit = ignored(); 0 }\n",
    "callable-pointers-context-and-local-coercion": """
fn increment(value: i32): i32 { value + 1 }
fn apply(operation: fn(i32): i32, value: i32): i32 { operation(value) }
fn change(value: mut i32): Unit { value += 1 }
fn main(): i32 {
    let pointer: fn(i32): i32 = increment
    let contextual: fn(i32): i32 = fn(value) { value + 1 }
    let inferred = fn(value) { value }
    let local_closure = fn(value: i32): i32 { value + 1 }
    let optional: (fn(i32): i32)? = local_closure
    let update: fn(mut i32): Unit = change
    var value = 39
    update(value)
    let answer = match optional { present(operation) => operation(41), none => 0 }
    if apply(pointer,value) + contextual(0) == 42 &&
       inferred(42) == 42 && answer == 42 { 0 } else { 1 }
}
""",
    "closure-minimal-disjoint-captures-and-modes": """
copy type Pair { first: i32; second: i32 }
fn main(): i32 {
    var pair = Pair(20,1)
    let read_first = fn(): i32 { pair.first }
    pair.second += 1
    var mutate_second = fn(value: i32): i32 {
        pair.second += value
        pair.second
    }
    let owned = take fn(value: i32): i32 { read_first() + value }
    let first = mutate_second(18)
    let second = mutate_second(2)
    if first == 20 && second == 22 && owned(22) == 42 &&
       owned(0) == 20 { 0 } else { 1 }
}
""",
    "closure-owned-called-and-uncalled-cleanup": """
type Guard<region r> {
    log: mut i32 from r
    drop { *self.log += 1 }
}
fn inspect(guard: read Guard): Unit { let _ = read guard }
fn consume(guard: take Guard): Unit { let _ = read guard }
fn main(): i32 {
    var repeated_log = 0
    var once_log = 0
    var uncalled_log = 0
    {
        let repeated_guard = Guard(mut repeated_log)
        let repeated = take fn(): Unit { inspect(repeated_guard) }
        repeated()
        repeated()
        let once_guard = Guard(mut once_log)
        let once = take fn(): Unit { consume(once_guard) }
        once()
        let uncalled_guard = Guard(mut uncalled_log)
        let uncalled = take fn(): Unit { inspect(uncalled_guard) }
    }
    if repeated_log == 1 && once_log == 1 &&
       uncalled_log == 1 { 0 } else { 1 }
}
""",
    "generic-callable-bounds-and-concrete-environments": """
fn apply<F: fn(i32): i32>(operation: read F, value: i32): i32 {
    operation(value)
}
fn change<F: mut fn(i32): i32>(operation: mut F, value: i32): i32 {
    operation(value)
}
fn once<F: take fn(): i32>(operation: take F): i32 { operation() }
fn identity<T>(value: take T): T { value }
fn make<T>(value: take T) { take fn(): T { take value } }
type Item { value: i32 }
fn main(): i32 {
    let value = 20
    let reader = fn(extra: i32): i32 { value + extra }
    var count = 20
    var writer = fn(extra: i32): i32 { count += extra; count }
    let item = Item(42)
    let consumer = take fn(): i32 { let owned = take item; owned.value }
    let pointer: fn(take i32): i32 = identity::<i32>
    let returned = make(42)
    if apply(reader,22) == 42 && change(writer,22) == 42 &&
       once(consumer) == 42 && pointer(42) == 42 &&
       returned() == 42 { 0 } else { 1 }
}
""",
    "indirect-mut-calls-select-native-index-mut": """
module core {
    pub module ops {
        pub interface Index<Key> {
            type Output;
            fn index(key: take Key): read Self::Output;
        }
        pub interface IndexMut<Key> {
            type Output;
            mut fn index_mut(key: take Key): mut Self::Output;
        }
    }
}
type Slot<T> { value: T }
impl<T> Slot<T> implements core::ops::Index<i32> {
    type Output = T
    fn index(key: take i32): read T { read self.value }
}
impl<T> Slot<T> implements core::ops::IndexMut<i32> {
    type Output = T
    mut fn index_mut(key: take i32): mut T { mut self.value }
}
fn increment(value: mut i32): Unit { value += 1 }
fn answer(): i32 { 42 }
fn main(): i32 {
    var number = Slot(41)
    let update: fn(mut i32): Unit = increment
    update(number[0])
    let mutable_pointer: mut fn(): i32 = answer
    var callbacks = Slot(mutable_pointer)
    if callbacks[0]() == 42 && number.value == 42 { 0 } else { 1 }
}
""",
    "closure-inherits-generic-interface-associated-equalities": """
interface Add<Rhs> {
    type Output;
    fn add(rhs: read Rhs): Self::Output;
}
type Number { value: i32 }
impl Number implements Add<Number> {
    type Output = Number
    fn add(rhs: read Number): Number { Number(self.value + rhs.value) }
}
fn sum<T: Add<T, Output=T>>(left: T, right: T): T {
    let outer = fn(): T {
        let inner = fn(): T { left.add(right) }
        inner()
    }
    outer()
}
fn main(): i32 {
    let result = sum(Number(20),Number(22))
    if result.value == 42 { 0 } else { 1 }
}
""",
    "higher-ranked-function-pointers-closures-and-bounds": """
fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    operation: read F, value: read i32): read i32 from value {
    operation(value)
}
fn identity<region r>(value: read i32 from r): read i32 from r { read value }
fn main(): i32 {
    let pointer: for<region a> fn(read i32 from a): read i32 from a = identity
    let closure: for<region b> fn(read i32 from b): read i32 from b =
        fn(value) { read value }
    let value = 42
    if *apply(pointer,value) == 42 && *apply(closure,value) == 42 { 0 } else { 1 }
}
""",
    "indirect-call-typed-failure-and-returned-product-view": """
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
fn expose(reader: read Reader): read Pair from reader { reader.value }
fn checked(value: i32): i32 throws i32 {
    if value < 0 { throw 7 }
    value
}
fn main(): i32 {
    let pair = Pair(20,22)
    let reader = Reader(read pair)
    let view: fn(read Reader): read Pair = expose
    let checked_pointer: fn(i32): i32 throws i32 = checked
    let result = view(reader)
    let captured = capture checked_pointer(-1)
    let failed = match captured { success(_) => false, failure(error) => error == 7 }
    if result.first + result.second == 42 && failed { 0 } else { 1 }
}
""",
    "indirect-opaque-view-bearing-writeback": """
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
type Writer<region source, region storage> {
    value: mut Reader<region source> from storage
}
fn expose<region source, region storage>(
    writer: mut Writer<region source,region storage>): mut Reader<region source> from writer {
    mut *writer.value
}
fn main(): i32 {
    let original = Pair(0,0)
    let replacement = Pair(20,22)
    var reader = Reader(read original)
    var writer = Writer(mut reader)
    let pointer: for<region source,region storage> fn(mut Writer<region source,region storage>): mut Reader<region source> = expose
    let result = pointer(writer)
    result.value = read replacement
    if result.value.first + result.value.second == 42 { 0 } else { 1 }
}
""",
    "generic-declarations-forward-calls-and-const-defaults": """
type Owned { value: i32 }
fn identity<T>(value: take T): T { take value }
fn count<T: Copy>(value: T, remaining: i32): T {
    if remaining == 0 { value } else { count(value,remaining - 1) }
}
fn answer<const VALUE: i32 = 20 + 22>(): i32 { VALUE }
fn main(): i32 {
    let owned = identity(Owned(answer()))
    if owned.value == 42 && count(42,3) == 42 &&
       answer::<{20 + 22}>() == answer::<42>() { 0 } else { 1 }
}
""",
    "generic-products-enums-aliases-and-owner-methods": """
type Box<T: Copy> {
    value: T
    init(value: T) { self.value = value }
    fn get(): T { self.value }
}
alias PairBox<T: Copy> = Box<(T,i32)>
enum Choice<T: Copy> { Empty; Value(T) }
fn main(): i32 {
    let boxed = Box(42)
    let pair = PairBox::<i32>((42,0))
    let result = Choice::Value(boxed.get())
    let answer = match result {
        Choice::Empty => 0,
        Choice::Value(value) => value
    }
    if answer == 42 && pair.get().0 == 42 { 0 } else { 1 }
}
""",
    "generic-array-repeat-index-and-linear-iteration": """
type Owned { value: i32 }
fn make<const N: i32>(value: i32): [i32;N] { [value;N] }
fn sum<const N: i32>(values: read [i32;N]): i32 {
    var total = 0
    for value in values { total += value }
    total
}
fn increment<const N: i32>(values: mut [i32;N]): Unit {
    for value in mut values { value += 1 }
}
fn first<const N: i32>(values: take [Owned;N]): i32 {
    var answer = 0
    for value in take values { answer = value.value; break }
    answer
}
fn main(): i32 {
    var values = make::<2>(20)
    increment(values)
    if sum(values) == 42 && values[0] == 21 && sum::<0>([]) == 0 &&
       first([Owned(42),Owned(1)]) == 42 { 0 } else { 1 }
}
""",
    "generic-owned-type-transports-view-origins": """
fn identity<T>(value: take T): T { take value }
fn enabled<const VALUE: bool = true>(): bool { VALUE }
fn byte<const VALUE: u8 = 42>(): u8 { VALUE }
fn main(): i32 {
    let value = 42
    let borrowed = identity(read value)
    if *borrowed == 42 && enabled() && byte() == b'*' { 0 } else { 1 }
}
""",
    "generic-associated-type-and-const-binding-syntax": """
interface Bound { type Output; const COUNT: i32; }
fn inspect<const COUNT: i32,
           T: Bound<type Output=i32, const COUNT=COUNT>>(value: T): Unit { () }
fn inspect_bare<T: Bound<Output=i32, COUNT=42>>(value: T): Unit { () }
fn main(): i32 { 0 }
""",
    "interface-default-self-and-owner-generic-scope": """
interface Add<Rhs = Self> { fn add(rhs: read Rhs): i32; }
interface Pair<A = i32, B = A> { fn combine(value: read B): i32; }
type Number { value: i32 }
impl Number implements Add {
    fn add(rhs: read Number): i32 { self.value + rhs.value }
}
impl Number implements Pair {
    fn combine(value: read i32): i32 { self.value + value }
}
fn add<T: Add>(left: T, right: T): i32 { left.add(right) }
fn call<A: Pair>(value: A): i32 { value.combine(21) }
fn main(): i32 {
    let value = Number(21)
    if add(value,value) == 42 && call(value) == 42 { 0 } else { 1 }
}
""",
    "coherent-implementation-type-and-const-equality-selection": """
interface Code { fn code(): i32; }
type Box<T> { value: T }
type Tag<const N: i32> {}
impl<T> Box<T> implements Code where T = i32 {
    fn code(): i32 { self.value }
}
impl<T> Box<T> implements Code where T = bool {
    fn code(): i32 { if self.value { 42 } else { 0 } }
}
impl<const N: i32> Tag<N> implements Code where [i32;N] = [i32;3] {
    fn code(): i32 { N }
}
impl<const N: i32> Tag<N> implements Code where [i32;N] = [i32;4] {
    fn code(): i32 { N }
}
fn main(): i32 {
    let number = Box(42)
    let flag = Box(true)
    let three = Tag::<3>()
    let four = Tag::<4>()
    if number.code() == 42 && flag.code() == 42 &&
       three.code() == 3 && four.code() == 4 { 0 } else { 1 }
}
""",
    "inherent-equalities-determine-specialization-arguments": """
type Plain {}
impl<T> Plain where T = i32 { fn answer(): i32 { 42 } }
impl<const N:i32> Plain where [i32;N] = [i32;42] {
    fn count(): i32 { N }
}
fn main(): i32 {
    let value = Plain()
    if value.answer() == 42 && value.count() == 42 { 0 } else { 1 }
}
""",
    "copy-constrained-implementation-is-disjoint-from-noncopy-owner": """
interface Code { fn code(): i32; }
type Box<T> { value: T }
type Owned { value: i32 }
impl<T:Copy> Box<T> implements Code { fn code(): i32 { 42 } }
impl Box<Owned> implements Code { fn code(): i32 { self.value.value } }
fn main(): i32 {
    let copied = Box(0)
    let owned = Box(Owned(42))
    if copied.code() == 42 && owned.code() == 42 { 0 } else { 1 }
}
""",
}

for _numeric_type, _numeric_width, _numeric_signed in (
        ("i8", 8, True), ("i16", 16, True), ("i32", 32, True),
        ("i64", 64, True), ("i128", 128, True), ("isize", 64, True),
        ("u8", 8, False), ("u16", 16, False), ("u32", 32, False),
        ("u64", 64, False), ("u128", 128, False), ("usize", 64, False)):
    _numeric_min = -(1 << (_numeric_width - 1)) if _numeric_signed else 0
    _numeric_max = (1 << (_numeric_width - int(_numeric_signed))) - 1
    POSITIVE[f"machine-numeric-{_numeric_type}-composition-and-families"] = f"""
fn value<const N:{_numeric_type}={_numeric_max}>():{_numeric_type} {{ N }}
fn increment<const N:{_numeric_type}>():{_numeric_type} {{ value::<{{N+1}}>() }}
fn classify(input:{_numeric_type}):i32 {{
    match input {{ {_numeric_min}..={_numeric_max} => 42 }}
}}
fn main() {{
    let maximum:{_numeric_type} = {_numeric_max}
    let minimum:{_numeric_type} = {_numeric_min}
    var count = 0
    for element in {_numeric_max - 1}{_numeric_type}..=maximum {{ count += 1 }}
    let overflow = maximum.overflowing_add(1)
    let checked = match maximum.checked_add(1) {{
        none => true, present(item) => false
    }}
    let divide = match maximum.checked_div(0) {{
        none => true, present(item) => false
    }}
    let shift = match maximum.checked_shl({_numeric_width}u32) {{
        none => true, present(item) => false
    }}
    let converted = match maximum.checked_cast::<{_numeric_type}>() {{
        none => false, present(item) => item == maximum
    }}
    if value() == maximum && increment::<{{{_numeric_max - 1}}}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted {{ 0 }} else {{ 1 }}
}}
"""


NEGATIVE = {
    "machine-asm-const-rejects-runtime-local": ("""
fn main() {
    let amount = 42
    var result = 0
    unsafe {
        asm!(\"""" + ("add {value:w}, {value:w}, #{amount}" if ARM64 else
                       "add {value:e}, {amount}") + """\",
             value = inout(reg) result, amount = const amount)
    }
    0
}
""", "type", "required constant"),
    "machine-numeric-required-u128-overflow": ("""
fn value<const N:u128=340282366920938463463374607431768211455u128+1>():u128{N}
fn main(){0}
""", "type", "required integer constant overflows"),
    "machine-numeric-required-i128-division-overflow": ("""
fn value<const N:i128=-170141183460469231731687303715884105728i128 / -1>():i128{N}
fn main(){0}
""", "type", "required integer constant overflows"),
    "machine-numeric-required-u8-width-overflow": ("""
fn value<const N:u8=255u8+1>():u8{N}
fn main(){0}
""", "type", "required integer constant overflows"),
    "machine-numeric-required-u128-multiply-overflow": ("""
fn value<const N:u128=(1u128<<64)*(1u128<<64)>():u128{N}
fn main(){0}
""", "type", "required integer constant overflows"),
    "machine-numeric-required-u128-subtract-underflow": ("""
fn value<const N:u128=0u128-1>():u128{N}
fn main(){0}
""", "type", "required integer constant overflows"),
    "machine-numeric-required-i128-negate-overflow": ("""
fn value<const N:i128=-(-170141183460469231731687303715884105728i128)>():i128{N}
fn main(){0}
""", "type", "required integer constant overflows"),
    "machine-numeric-required-wide-invalid-shift": ("""
fn value<const N:u128=1u128<<128>():u128{N}
fn main(){0}
""", "type", "invalid shift"),
    "machine-numeric-required-wide-zero-divisor": ("""
fn value<const N:u128=1u128/0>():u128{N}
fn main(){0}
""", "type", "division by zero"),
    "machine-numeric-pattern-rejects-truncation": ("""
fn main(){match 1u64 { 18446744073709551616 => 0, _ => 1 }}
""", "type", "pattern literal is outside the u64 range"),
    "machine-numeric-wide-match-rejects-missing-maximum": ("""
fn main(){match 0u128 { 0..340282366920938463463374607431768211455 => 0 }}
""", "type", "non-exhaustive match"),
    "machine-numeric-wide-match-rejects-unreachable-maximum": ("""
fn main(){match 0u128 {
    0..=340282366920938463463374607431768211455 => 0,
    340282366920938463463374607431768211455 => 1
}}
""", "type", "unreachable match arm"),
    "machine-numeric-range-rejects-conflicting-widths": ("""
fn main(){for value in 1u64..2u128 {}
0}
""", "type", "expected u128, found u64"),
    "machine-numeric-index-retains-explicit-i32-contract": ("""
fn main(){let value=[0,1];value[1u64]}
""", "type", "expected i32, found u64"),
    "machine-numeric-large-length-retains-resource-limit": ("""
fn main(){let value:[u8;65537]=[0;65537];0}
""", "limit", "array length limit exceeded"),
    "machine-numeric-wide-count-cannot-truncate-into-a-small-array": (
        "fn main() { let values = [0;340282366920938463463374607431768211455u128]; 0 }",
        "limit","array length limit exceeded"),
    "machine-numeric-usize-constant-index-cannot-truncate": (
        "fn main() { let values = [42]; values[4294967296usize] }",
        "type","array index is out of bounds"),
    "machine-numeric-required-rejects-conflicting-suffix": ("""
fn value<const N:u64>():u64{N}
fn main(){let result=value::<42u128>();0}
""", "type", "const argument does not match its declared type"),
    "machine-numeric-rejects-unknown-floating-relaxation": ("""
@fast_math(fast)
fn main(){0}
""", "attribute", "unknown floating relaxation"),
    "machine-numeric-rejects-duplicate-floating-relaxation": ("""
@fast_math(contract,contract)
module numeric { pub fn value():i32{42} }
fn main(){0}
""", "attribute", "duplicate floating relaxation"),
    "machine-numeric-rejects-unlisted-floating-relaxation": ("""
@fast_math
fn main(){0}
""", "attribute", "requires a comma-separated list"),
    "machine-numeric-checked-conversion-rejects-nonnumeric-target": ("""
fn main(){let result=42i64.checked_cast::<bool>();0}
""", "type", "invalid primitive operation"),
    "machine-static-zero-count-repetition-cannot-execute-drop": (
        'type Owner { value: i32; drop {} }; '
        'static EMPTY: [Owner;0] = [Owner(42);0]; fn main() { 0 }',
        "constant", "element destructor"),
    "c-variadic-definition-rejects-native-fat-pointer": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<ptr<read [i32]>>(); 0 }; fn main() { 0 }',
        "type", "invalid primitive"),
    "c-variadic-definition-rejects-native-function-pointer": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<fn(): i32>(); 0 }; fn main() { 0 }',
        "type", "invalid primitive"),
    "machine-static-function-pointer-storage-is-not-a-function-symbol": (
        'extern "C" { @link_name("same") static ADDRESS: unsafe extern "C" fn(): i32; '
        '@link_name("same") unsafe fn imported(): i32; } fn main() { 0 }',
        "signature", "conflicting external"),
    "machine-static-unsafe-initializer-does-not-authorize-other-declarations": (
        'static mut VALUE: i32 = 1; static FIRST: ptr<mut i32> = unsafe { SECOND }; '
        'static SECOND: ptr<mut i32> = core::ptr::from_mut(VALUE); fn main() { 0 }',
        "unsafe", "requires an unsafe"),
    "machine-static-import-and-definition-share-one-loan-root": (
        '@export_name("counter") static mut COUNT: i32 = 1; '
        'extern "C" { @link_name("counter") static mut ALIAS: i32; } '
        'fn main() { let writer = unsafe { mut COUNT }; '
        'let reader = unsafe { read ALIAS }; *writer = 42; *reader }',
        "ownership"),
    "machine-static-unaligned-address-cannot-form-safe-view": (
        '@packed(1) copy type Packed { tag: u8; value: i32 }; '
        'static VALUE: Packed = Packed(0u8,42); '
        'static VIEW: read i32 from static = read VALUE.value; fn main() { 0 }',
        "constant", "unaligned"),
    "c-variadic-definition-native-cursor-storage-is-opaque": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.0; 0 }; fn main() { 0 }',
        "name", "unknown field"),
    "machine-static-symbol-conflict-with-function": (
        '@export_name("same") static VALUE: i32 = 42; '
        '@export_name("same") fn answer(): i32 { 42 }; fn main() { 0 }',
        "signature", "conflicting external"),
    "machine-static-duplicate-symbol-definition": (
        '@export_name("same") static FIRST: i32 = 42; '
        '@export_name("same") static SECOND: i32 = 42; fn main() { 0 }',
        "signature", "conflicting external"),
    "machine-static-required-initializer-overflow": (
        "static VALUE: i8 = 127 + 1; fn main() { 0 }",
        "constant", "overflows"),
    "c-variadic-definition-conditional-end-is-not-live": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'if count == 0 { args.end() }; args.arg::<i32>() }; fn main() { 0 }',
        "ownership", "may have been moved"),
    "c-variadic-definition-copy-after-end": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.end(); let copied = args.copy(); 0 }; fn main() { 0 }',
        "ownership", "may have been moved"),
    "c-variadic-definition-float-default-promotion-required": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<f32>(); 0 }; fn main() { 0 }',
        "type", "invalid primitive"),
    "c-variadic-definition-cursor-cannot-enter-generic-helper": (
        'fn forget<T>(value: take T) { core::mem::forget(take value) }; '
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'forget(take args); 0 }; fn main() { 0 }',
        "ownership", "cannot be passed"),
    "machine-static-mutable-access-requires-unsafe": (
        "static mut VALUE: i32 = 42; fn main() { VALUE; 0 }",
        "unsafe", "requires an unsafe"),
    "machine-static-no-owned-move": (
        "type Owner { value: i32 }; static VALUE: Owner = Owner(42); "
        "fn main() { let moved = take VALUE; 0 }",
        "ownership", "cannot move out of static"),
    "machine-static-required-initializer-no-host-execution": (
        "fn compute(): i32 { 42 }; static VALUE: i32 = compute(); fn main() { 0 }",
        "constant", "validated constant"),
    "machine-static-required-initializer-cycle": (
        "static FIRST: i32 = SECOND; static SECOND: i32 = FIRST; fn main() { 0 }",
        "constant", "cycle"),
    "machine-static-private-module-access": (
        "module storage { static VALUE: i32 = 42; } "
        "fn main() { storage::VALUE; 0 }", "name"),
    "machine-static-local-view-cannot-be-stored": (
        "static VALUE: i32 = 1; static mut VIEW: read i32 from static = read VALUE;"
        "fn main() { let value = 42; unsafe { VIEW = read value }; 0 }",
        "region"),
    "c-variadic-definition-use-after-end": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.end(); args.arg::<i32>() }; fn main() { 0 }',
        "ownership", "may have been moved"),
    "c-variadic-definition-requires-promoted-type": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<i8>() as i32 }; fn main() { 0 }',
        "type", "invalid primitive"),
    "c-variadic-definition-read-requires-unsafe": (
        'extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<i32>() }; fn main() { 0 }',
        "unsafe"),
    "c-variadic-definition-cursor-cannot-escape": (
        'unsafe extern "C" fn callback(count: i32,args: ...) { args }; fn main() { 0 }',
        "ownership", "cannot escape"),
    "machine-numeric-character-constants-cannot-use-integer-arithmetic": (
        "fn value<const C: char = 'a' + 'b'>(): char { C }\nfn main() { 0 }",
        "type","requires integer operands"),
    "machine-unpin-method-where-bound-is-required-even-with-empty-body": ("""
type Blocked { value: i32 }
impl Blocked not Unpin;
type Parent<T> {
    value: T
    fn demand(): Unit where T: Unpin {}
}
fn main() {
    let parent = Parent(Blocked(0))
    parent.demand()
    0
}
""", "type", "Unpin"),
    "machine-unpin-method-equality-cannot-mark-shared-parent-parameter": ("""
type Parent<T> {
    fn bounded<U: Unpin>(value: mut T): Unit where T = U {
        var handle = core::pin::Pin::new(mut value)
        let reference = handle.into_inner()
    }
    fn wrong(value: mut T): Unit {
        let handle = core::pin::Pin::new(mut value)
    }
}
fn main() { 0 }
""", "type"),
    "machine-cell-shared-cell-handle-cannot-grant-ordinary-mutable-view": ("""
fn wrong(cell: read core::cell::RefCell<i32>): Unit {
    let value = cell.get_mut()
}
fn main() { 0 }
""", "ownership"),
    "machine-unpin-contextual-bound-does-not-quantify-another-type": ("""
type Owned { marker: core::marker::PhantomPinned }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Copy> Wrapper<T> implements Unpin {}
fn wrong<T>(value: read Wrapper<T>): Unit where Wrapper<T>: Unpin {
    var handle = core::pin::pin(Wrapper(Owned(core::marker::PhantomPinned),core::marker::PhantomPinned))
    let wrong = handle.get_mut()
}
fn main() { 0 }
""", "type"),
    "machine-unpin-unresolved-region-condition-is-not-unconditional": ("""
interface Ready<region r> {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready<region static>> Wrapper<T> implements Unpin {}
fn wrong<region r, T: Ready<region r>>(value: mut Wrapper<T>) {
    let handle = core::pin::Pin::new(mut value)
}
fn main() { 0 }
""", "type"),
    "machine-unpin-associated-equation-must-be-proven": ("""
interface Family { type Item; }
type Source {}
impl Source implements Family { type Item = bool; }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Family> Wrapper<T> implements Unpin where <T implements Family>::Item = i32 {}
fn main() {
    var handle = core::pin::pin(Wrapper(Source(),core::marker::PhantomPinned))
    let wrong = handle.get_mut()
    0
}
""", "type"),
    "machine-cell-payload-view-cannot-outlive-local-guard": ("""
fn wrong(cell: read core::cell::RefCell<i32>): read i32 from cell {
    let guard = cell.borrow()
    guard.get_ref()
}
fn main() { 0 }
""", "ownership"),
    "machine-cell-returned-guard-prevents-cell-move": ("""
fn borrow<T>(cell: read core::cell::RefCell<T>): core::cell::Ref<T> from cell {
    cell.borrow()
}
fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = borrow(cell)
    let moved = cell
    0
}
""", "ownership"),
    "machine-unpin-false-contextual-bound-rejected-at-call": ("""
type Owned { marker: core::marker::PhantomPinned }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Copy> Wrapper<T> implements Unpin {}
fn access<T>(value: mut Wrapper<T>): mut Wrapper<T> from value where Wrapper<T>: Unpin {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(Owned(core::marker::PhantomPinned),core::marker::PhantomPinned)
    let wrong = access(value)
    0
}
""", "type", "Unpin"),
    "machine-unpin-recursive-condition-is-not-a-proof": ("""
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T> Wrapper<T> implements Unpin where Wrapper<T>: Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(42,core::marker::PhantomPinned))
    let wrong = handle.get_mut()
    0
}
""", "type"),
    "machine-cell-owner-cannot-move-before-later-guard-cleanup": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let moved = cell
    0
}
""", "ownership"),
    "machine-cell-owner-cannot-mutate-after-guard-last-use": ("""
fn main() {
    var cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let value = *guard.get_ref()
    *cell.get_mut() = 0
    value
}
""", "ownership"),
    "machine-cell-guard-cannot-escape-cell": ("""
fn main() {
    let guard = { let cell = core::cell::RefCell::new(42); cell.borrow() }
    *guard.get_ref()
}
""", "ownership"),
    "machine-cell-forget-cannot-invalidate-a-live-payload-reference": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let value = guard.get_ref()
    core::mem::forget(guard)
    *value
}
""", "ownership"),
    "machine-cell-refmut-reborrows-are-not-independent-aliases": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    var guard = cell.borrow_mut()
    let first = guard.get_mut()
    let second = guard.get_mut()
    *first += *second
    0
}
""", "ownership"),
    "machine-cell-shared-ref-does-not-grant-mutable-payload": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    var guard = cell.borrow()
    let wrong = guard.get_mut()
    0
}
""", "type"),
    "machine-cell-copy-get-rejects-owned-payload": ("""
type Owned { value: i32 }
fn main() { let cell = core::cell::Cell::new(Owned(42)); let value = cell.get(); 0 }
""", "type"),
    "machine-cell-exchange-writeback-retains-new-view-source": ("""
fn set<region a>(cell: read core::cell::Cell<read i32 from a>,
                 value: read i32 from a) { cell.set(read value) }
fn main() {
    let first = 1
    let cell = core::cell::Cell::new(read first)
    { let short = 42; set(cell,read short) }
    *cell.get()
}
""", "ownership"),
    "machine-cell-refmut-writeback-cannot-store-a-short-view": ("""
type Slot<region r> { value: read i32 from r }
fn set<region r>(cell: read core::cell::RefCell<Slot<region r>>,
                 value: read i32 from r) {
    var guard = cell.borrow_mut()
    guard.get_mut().value = read value
}
fn main() {
    let first = 1
    let cell = core::cell::RefCell::new(Slot(read first))
    { let short = 42; set(cell,read short) }
    let guard = cell.borrow()
    *guard.get_ref().value
}
""", "ownership"),
    "machine-unpin-condition-is-not-unconditional": ("""
interface Ready {}
impl i32 implements Ready {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(false,core::marker::PhantomPinned))
    let wrong = handle.get_mut()
    0
}
""", "type"),
    "machine-unpin-where-assumption-does-not-leak-to-other-functions": ("""
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Copy> Wrapper<T> implements Unpin {}
fn allowed<T>(value: mut Wrapper<T>): mut Wrapper<T> from value where Wrapper<T>: Unpin {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn wrong<T>(value: mut Wrapper<T>) {
    let handle = core::pin::Pin::new(mut value)
}
fn main() { 0 }
""", "type"),
    "machine-unpin-associated-equality-must-be-proven": ("""
interface Family { type Item; }
type Source {}
impl Source implements Family { type Item = bool; }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Family<Item=i32>> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(Source(),core::marker::PhantomPinned))
    let wrong = handle.get_mut()
    0
}
""", "type"),
    "machine-unpin-negative-declaration-remains-negative": ("""
type Blocked { value: i32 }
impl Blocked not Unpin;
type Outer { value: Blocked }
fn main() {
    var handle = core::pin::pin(Outer(Blocked(42)))
    let wrong = handle.get_mut()
    0
}
""", "type"),
    "machine-unpin-negative-declaration-cannot-have-bounds": ("""
type Wrapper<T> { value: T }
impl<T: Copy> Wrapper<T> not Unpin;
fn main() { 0 }
""", "type"),
    **MACHINE_NEGATIVE,
    "machine-transparent-enum-requires-one-variant": (
        "@layout(transparent) enum Invalid { First(i32); Second(i32) }\nfn main() { 0 }",
        "attribute"),
    "machine-combined-enum-layout-rejects-conflicting-tags": (
        "@layout(C,u8,i8) enum Invalid { First }\nfn main() { 0 }",
        "attribute"),
    "machine-transparent-enum-requires-one-storage-payload": (
        "@layout(transparent) enum Invalid { Only(i32,i32) }\nfn main() { 0 }",
        "attribute"),
    "machine-pinned-destructor-retains-written-view-origin": ("""
type Slot<region r> { value: read i32 from r }
type Writer<region a,region b> {
    @pinned marker: core::marker::PhantomPinned
    destination: mut Slot<region b> from a; value: read i32 from b
    drop { self.project_destination().value = self.get_ref().value }
}
fn main() {
    let first = 1
    var second = 42
    var slot = Slot(read first)
    { let handle = core::pin::pin(Writer(core::marker::PhantomPinned,mut slot,read second)) }
    second = 0
    *slot.value
}
""","ownership"),
    "machine-borrowed-pin-cannot-be-consumed-through-a-view": (
        "fn wrong(value: read pinned mut i32) { let result = unsafe { value.into_inner_unchecked() } }\nfn main() { 0 }",
        "ownership"),
    "machine-manual-unpin-condition-rejects-address-sensitive-argument": ("""
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Unpin> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(core::marker::PhantomPinned,core::marker::PhantomPinned))
    let value = handle.get_mut()
    0
}
""","type"),
    "machine-union-read-requires-unsafe": (
        "union Bits { integer: u32; real: f32 }\nfn main() { let value = Bits(integer: 42u32); let result = value.real; 0 }",
        "unsafe"),
    "machine-union-overlapping-field-loans-conflict": ("""
union Bits { integer: u32; real: f32 }
fn main() {
    var value = Bits(integer: 42u32)
    let borrowed = unsafe { read value.integer }
    value.real = 0.0f32
    if *borrowed == 42u32 { 0 } else { 1 }
}
""","ownership"),
    "machine-union-owned-field-requires-manual-drop": (
        "type Owned { drop {} }\nunion Wrong { value: Owned; bits: usize }\nfn main() { 0 }",
        "type"),
    "machine-explicit-receiver-must-wrap-self": (
        "type Payload { value: i32; fn wrong(receiver self: i32): i32 { self } }\nfn main() { 0 }",
        "signature"),
    "machine-explicit-receiver-must-be-first": (
        "type Payload { fn wrong(value: i32, receiver self: read Self): i32 { value } }\nfn main() { 0 }",
        "signature"),
    "machine-enum-discriminants-check-their-width": (
        "@layout(u8) copy enum Byte { First = 255; Overflow }\nfn main() { 0 }",
        "type"),
    "machine-enum-discriminants-must-be-distinct": (
        "@layout(i16) copy enum Number { First = -1; Second = -1 }\nfn main() { 0 }",
        "type"),
    "machine-negative-unpin-declaration-prevents-extraction": (
        "type Stable { value: i32 }\nimpl Stable not Unpin;\nfn main() { var handle = core::pin::pin(Stable(42)); let value = handle.get_mut(); 0 }",
        "type"),
    "machine-generic-pin-extraction-needs-unpin-bound": (
        "fn access<T>(value: mut pinned mut T): mut T from value { value.get_mut() }\nfn main() { 0 }",
        "type"),
    "machine-manual-unpin-requires-unsafe-implementation": (
        "type Stable { value: i32 }\nimpl Stable implements Unpin {}\nfn main() { 0 }",
        "unsafe"),
    "machine-pin-projection-retains-exclusive-parent-loan": ("""
type Child { value: i32; marker: core::marker::PhantomPinned }
type Parent { @pinned child: Child; other: i32 }
fn main() {
    var handle = core::pin::pin(Parent(Child(42,core::marker::PhantomPinned),0))
    let child = handle.project_child()
    let parent = unsafe { handle.get_unchecked_mut() }
    child.get_ref().value + parent.other
}
""","ownership"),
    "machine-structurally-pinned-destructor-cannot-move-field": ("""
type Child { value: i32; marker: core::marker::PhantomPinned }
type Parent {
    @pinned child: Child
    drop { let moved = self.get_ref().child }
}
fn main() { 0 }
""","ownership"),
    "machine-transmute-rejects-different-sizes": (
        "fn main() { let value = unsafe { core::mem::transmute::<u64>(1u32) }; 0 }",
        "type"),
    "machine-memory-copy-requires-unsafe": (
        "fn main() { var value = 0; let p = core::ptr::from_mut(value); core::ptr::`copy`(p,p,1); 0 }",
        "unsafe"),
    "machine-memory-copy-requires-mutable-destination": (
        "fn main() { let value = 0; let p = core::ptr::from_ref(value); unsafe { core::ptr::`copy`(p,p,1) }; 0 }",
        "type"),
    "machine-unaligned-packed-fields-cannot-be-pinned": (
        "@packed(1) type Packed { @pinned value: i64 }\nfn main() { 0 }",
        "attribute"),
    "machine-atomic-handles-are-not-implicitly-copy": (
        "fn main() { let first=core::sync::atomic::AtomicU32::new(42); let second=first; first.load(core::sync::atomic::Ordering::Relaxed) as i32 }",
        "ownership","moved"),
    "machine-atomic-unsupported-width-is-not-blocking-emulation": (
        "fn main() { let value=core::sync::atomic::AtomicU128::new(0); 0 }",
        "feature","lock-free alias"),
    "machine-address-sensitive-payload-requires-pinned-access": ("""
type Stable { marker: core::marker::PhantomPinned; value: i32 }
fn main() {
    var handle = core::pin::pin(Stable(core::marker::PhantomPinned,42))
    let reference = handle.get_mut()
    0
}
""","type","invalid primitive operation"),
    "machine-packed-fields-cannot-form-aligned-views": ("""
@layout(C)
@packed(1)
copy type Packed { tag: u8; value: i32 }
fn inspect(value: read i32): i32 { value }
fn main() { let value=Packed(0u8,42); inspect(value.value) }
""","alignment","unaligned storage"),
    "machine-unsafe-does-not-permit-unaligned-reference-construction": ("""
@layout(C)
@packed(1)
copy type Packed { tag: u8; value: i32 }
fn main() { let value=Packed(0u8,42); let reference=unsafe { read value.value }; *reference }
""","alignment","unaligned storage"),
    "machine-storage-write-needs-initialized-storage-handle": (
        "fn main() { var value: core::mem::MaybeUninit<i32>; let reference=value.write(42); *reference }",
        "type","storage handle may be uninitialized"),
    "machine-unsafe-cell-shared-reference-requires-unsafe": (
        "fn main() { let cell=core::cell::UnsafeCell::new(42); let value=cell.get_ref(); *value }",
        "unsafe", "requires an unsafe block"),
    "machine-uninitialized-owned-reference-preserves-original-loan": ("""
copy type Pair { first: i32; second: i32 }
fn main() {
    var value = Pair(20,22)
    let storage = core::mem::MaybeUninit::new(read value)
    let reference = unsafe { storage.assume_init() }
    value.first = 40
    reference.first + reference.second
}
""","ownership","live read loan"),
    "machine-foreign-reference-results-retain-source-loans": ("""
copy type Pair { first: i32; second: i32 }
extern "C" {
    unsafe fn forward(value: read Pair): read Pair from value;
}
fn main() {
    var value = Pair(20,22)
    let result = unsafe { forward(value) }
    value.first = 40
    result.first + result.second
}
""","ownership","live read loan"),
    "machine-c-callable-cannot-become-native-abi": (
        'extern "C" fn callback(value: i32): i32 { value }\nfn main() { let p: fn(i32): i32 = callback; p(0) }',
        "type"),
    "machine-foreign-typed-failure-needs-explicit-c-representation": (
        'extern "C" { unsafe fn operation(): i32 throws i32; }\nfn main() { 0 }',
        "signature", "native typed failure"),
    "machine-duplicate-symbol-attribute-is-rejected": (
        '@export_name("first") @export_name("second")\nextern "C" fn operation(): i32 { 42 }\nfn main() { 0 }',
        "attribute", "duplicate singleton"),
    "machine-raw-method-requires-unsafe": (
        "fn main() { let value = 42; let p = core::ptr::from_ref(value); p.`read`() }",
        "unsafe", "requires an unsafe block"),
    "machine-raw-write-requires-mutable-pointer": (
        "fn main() { let value = 42; let p = core::ptr::from_ref(value); unsafe { p.write(1) }; 0 }",
        "type", "invalid primitive operation"),
    "machine-explicit-overflow-operations-preserve-width": (
        "fn main() { let value = 1u8.wrapping_add(2u16); 0 }",
        "type", "expected"),
    "machine-raw-dereference-requires-unsafe": (
        "fn main() { let value = 42; let p = read value as ptr<read i32>; *p }",
        "unsafe", "requires an unsafe block"),
    "machine-unsafe-function-cannot-be-called-safely": (
        "unsafe fn operation(): i32 { 42 }\nfn main() { operation() }",
        "unsafe", "requires an unsafe block"),
    "machine-unsafe-function-pointer-cannot-become-safe": (
        "unsafe fn operation(): i32 { 42 }\nfn main() { let p: fn(): i32 = operation; p() }",
        "type"),
    "machine-unsafe-does-not-disable-initialization-checks": (
        "fn main() { let value: i32; unsafe { value } }",
        "type", "uninitialized"),
    "machine-unsafe-does-not-grant-mutable-pointer-access": (
        "fn main() { let value = 42; let p = read value as ptr<read i32>; unsafe { *p = 1 }; 0 }",
        "ownership"),
    "machine-integers-do-not-implicitly-widen": (
        "fn main() { let a = 1u8; let b = 2u16; let sum = a + b; 0 }",
        "type", "expected"),
    "machine-negative-unsigned-literal": (
        "fn main() { let value: u64 = -1; 0 }",
        "type", "outside the u64 range"),
    "machine-integer-literal-checks-contextual-width": (
        "fn main() { let value: i8 = 128; 0 }",
        "type", "outside the i8 range"),
    "machine-floats-have-no-bitwise-operators": (
        "fn main() { let value = 1.0f32 & 2.0f32; 0 }",
        "type", "integer"),
    "machine-integers-cannot-cast-to-bool": (
        "fn main() { let flag = 1 as bool; 0 }",
        "type", "invalid scalar conversion"),
    "receiver-move-failure-cannot-fall-back-to-read-interface": ("""
interface Choose { fn choose(): i32; }
type Value { take fn choose(): i32 { 1 } }
impl Value implements Choose { fn choose(): i32 { 2 } }
fn main() {
    let value = Value()
    let borrowed = read value
    borrowed.choose()
}
""", "ownership", "cannot move out of a borrowed place"),
    "mutable-projection-requires-deref-mut": ("""
module core {
    pub module ops {
        pub interface Deref { type Target; fn deref(): read Self::Target; }
    }
}
import core::ops::Deref
type Inner { mut fn increment(): Unit {} }
type Wrapper { inner: Inner }
impl Wrapper implements core::ops::Deref {
    type Target = Inner
    fn deref(): read Inner { read self.inner }
}
fn main() {
    var wrapper = Wrapper(Inner())
    wrapper.increment()
    0
}
""", "ownership", "requires matching DerefMut"),
    "higher-ranked-interface-rejects-static-only-implementation": ("""
interface Lifetime<region r> {}
type StaticOnly {}
impl StaticOnly implements Lifetime<region static> {}
fn accept<T: for<region r> Lifetime<region r>>(value: read T): i32 { 42 }
fn main() { let value = StaticOnly(); accept(value) }
""", "type", "interface obligation"),
    "mutable-stored-region-remains-invariant": ("""
type Ref<region r> { value: mut (read i32 from r) from r }
fn bad<region a, region b>(
    value: take Ref<region a>
): Ref<region b> where region a: b { take value }
fn main() { 0 }
""", "region", "invariant payload"),
    "named-region-binder-does-not-leak-between-declarations": ("""
fn first<region r>(value: read i32 from r): i32 { 0 }
fn second(value: read i32 from r): i32 { 0 }
fn main() { 0 }
""", "region", "unknown region"),
    "erased-generic-result-retains-borrowed-captures": ("""
copy type Pair { first: i32; second: i32 }
interface Readable<T: Copy> { fn value(): T; }
copy type Reader<region r> { value: read Pair from r }
impl<region r> Reader<region r> implements Readable<read Pair from r> {
    fn value(): read Pair from r { self.value }
}
fn main() {
    var original = Pair(20,22)
    let reader = Reader(read original)
    let erased: read any Readable<read Pair> = read reader
    let result = erased.value()
    original.first += 1
    result.first + result.second
}
""", "ownership", "live read loan"),
    "erased-mutable-writeback-keeps-short-source-live": ("""
copy type Pair { first: i32; second: i32 }
interface Setter<region r> { mut fn set(value: read Pair from r): Unit; }
type Cell<region r> { value: read Pair from r }
impl<region r> Cell<region r> implements Setter<region r> {
    mut fn set(value: read Pair from r): Unit { self.value = read value }
}
fn set<region r>(cell: mut any Setter<region r>, value: read Pair from r) {
    cell.set(value)
}
fn main() {
    let original = Pair(0,0)
    var cell = Cell(read original)
    {
        let replacement = Pair(20,22)
        set(cell,replacement)
    }
    cell.value.first + cell.value.second
}
""", "ownership", "live read loan"),
    "generic-owned-return-spec": ((Path(__file__).resolve().parents[1] / "examples/core/reject-generic-owned-return.mt").read_text(),
                                 "ownership", "borrowed"),
    "implementation-cannot-strengthen-generic-bounds": ("""
interface Accept { fn accept<T>(value: T): Unit; }
type Number {}
impl Number implements Accept {
    fn accept<T: Copy>(value: T): Unit { let first = value; let second = value }
}
fn main() { 0 }
""", "type", "strengthens"),
    "associated-output-must-satisfy-copy-bound": ("""
interface Family { type Item: Copy; }
type Owned { value: i32 }
type Number {}
impl Number implements Family { type Item = Owned }
fn main() { 0 }
""", "type", "Copy"),
    "erasure-cannot-expose-unbound-self-inputs": ("""
interface Equal { fn equal(other: Self): bool; }
type Number {}
impl Number implements Equal { fn equal(other: read Number): bool { true } }
fn main() {
    let value = Number()
    let erased: read any Equal = read value
    0
}
""", "type", "not dispatchable"),
    "erasure-rejects-caller-selected-method-types": ("""
interface Generic { fn accept<T>(value: T): Unit; }
type Number {}
impl Number implements Generic { fn accept<T>(value: T): Unit {} }
fn main() {
    let value = Number()
    let erased: read any Generic = read value
    0
}
""", "type", "not dispatchable"),
    "opaque-return-paths-share-one-hidden-type": ("""
interface Readable { fn value(): i32; }
type Number {}
type Other {}
impl Number implements Readable { fn value(): i32 { 42 } }
impl Other implements Readable { fn value(): i32 { 42 } }
fn make(flag: bool): some Readable {
    if flag { return Number() }
    return Other()
}
fn main() { 0 }
""", "type", "different hidden types"),
    "opaque-return-does-not-expose-hidden-fields": ("""
interface Readable { fn value(): i32; }
copy type Number { value: i32 }
impl Number implements Readable { fn value(): i32 { self.value } }
fn make(): some Readable { Number(42) }
fn main() { make().value }
""", "name", "field"),
    "slice-read-view-cannot-be-upgraded": ("""
fn increment(values: mut [i32]) { values[0] += 1 }
fn main() {
    var values = [41]
    let borrowed: read [i32] = read values
    increment(borrowed)
    0
}
""", "ownership", "mutable"),
    "projection-requires-an-implementation": ("""
interface Family { type Item; }
type Unrelated {}
fn invalid(value: <Unrelated implements Family>::Item): Unit {}
fn main() { 0 }
""", "type", "interface bound"),
    "pattern-local-limit-is-a-diagnostic": ("type Owned { value:i32 }\nfn main() {" +
        "".join(f"let a{i}=0;" for i in range(1023)) +
        "let items=[Owned(1)]; match items { [rest @ ..] => 0 } }\n",
        "limit", "local binding limit"),
    "guard-local-limit-is-a-diagnostic": ("type Owned { value:i32 }\nfn main() {" +
        "".join(f"let a{i}=0;" for i in range(1022)) +
        "let items=[Owned(1)]; match take items { [rest @ ..] if true => 0, _ => 0 } }\n",
        "limit", "local binding limit"),
    "parameter-local-limit-is-a-diagnostic": ("fn many("+
        ",".join(f"a{i}:i32" for i in range(1025))+
        "): Unit {}\nfn main() { 0 }\n", "limit", "local binding limit"),
    "mismatched-pattern-shape-is-a-source-error": ("fn main() { match true { present(value) => 0, _ => 1 } }\n", "type", "incompatible aggregate shape"),
    "mismatched-variant-payload-count-is-a-source-error": ("copy enum Value { Held(i32) }\nfn main() { match Value::Held(42) { Value::Held(first,second) => first } }\n",
                                                         "type", "pattern payload count"),
    "unicode-surrogate-is-not-scalar": (r"fn main() { let value = '\u{d800}'; 0 }"+"\n", "lex", "valid Unicode scalar"),
    "unicode-scalar-overflow": (r"fn main() { let value = '\u{110000}'; 0 }"+"\n", "lex", "valid Unicode scalar"),
    "character-needs-exactly-one-scalar": ("fn main() { let value = 'ab'; 0 }\n", "lex", "exactly one scalar"),
    "byte-literal-rejects-nonascii": ("fn main() { let value = b'é'; 0 }\n", "lex", "ASCII byte"),
    "byte-escape-requires-two-digits": (r"fn main() { let value = b'\x1'; 0 }"+"\n", "lex", "two hexadecimal digits"),
    "character-and-byte-remain-distinct": ("fn main() { let value: char = b'a'; 0 }\n", "type", "expected char, found u8"),
    "constant-array-length-overflow": ("fn main() { let values: [i32; 2147483647+1] = []; 0 }\n", "type", "constant overflows"),
    "array-length-cannot-use-runtime-binding": ("fn main() { let count=3; let values: [i32; count] = [1,2,3]; 0 }\n", "type", "constant integer"),
    "required-parameter-cannot-follow-default": ("fn bad(a:i32=0,b:i32) { a+b }\nfn main() { bad(0,0) }\n", "type", "required parameter"),
    "array-rest-borrow-cannot-escape-owner": ("type Owned { value:i32 }\nfn main() { let view: read [Owned;2]; { let values = [Owned(20),Owned(22),Owned(0)]; view = match values { [rest @ ..,_] => read rest } }; view[0].value }\n",
                                           "ownership", "live read loan"),
    "array-rest-does-not-permit-overlapping-mutation": ("fn main() { var values = [1,2,3]; match mut values { [first,rest @ ..] => { values[1] = 4; rest[0] += first } }; 0 }\n",
                                                      "ownership", "live exclusive loan"),
    "invalid-default-checked-when-supplied": ("fn bad(value: i32 = true) { value }\nfn main() { bad(42) }\n", "type", "expected i32, found bool"),
    "defaults-cannot-reference-later-parameters": ("fn bad(a: i32 = b, b: i32 = 42) { a + b }\nfn main() { bad(0,0) }\n", "name", "unresolved value 'b'"),
    "default-cannot-consume-earlier-owner": ("type Value { value: i32 }\nfn bad(a: take Value, b: take Value = a) { a.value + b.value }\nfn main() { bad(Value(20),Value(22)) }\n",
                                           "ownership"),
    "default-view-does-not-extend-argument": ("fn view(a: i32, b: (read i32) = read a): read i32 from b { b }\nfn main() { let result = view(42); *result }\n",
                                            "ownership", "live read loan"),
    "custom-init-must-establish-every-field": ("type Pair { first: i32; second: i32; init(value: i32) { self.first = value } }\nfn main() { let pair = Pair(42); 0 }\n",
                                             "type", "may be uninitialized"),
    "custom-init-method-needs-whole-self": ("type Pair { first: i32; second: i32; init() { self.first = 20; self.second = self.sum() }; fn sum() { self.first + self.second } }\nfn main() { let pair = Pair(); 0 }\n",
                                           "type", "may be uninitialized"),
    "custom-init-replaces-generated-construction": ("type Pair { first: i32; second: i32; init() { self.first = 20; self.second = 22 } }\nfn main() { let pair = Pair(first:20,second:22); 0 }\n",
                                                    "type", "argument"),
    "empty-range-pattern": ("fn main() { match 1 { 2..2 => 0, _ => 1 } }\n",
                            "type", "empty or reversed"),
    "range-pattern-overlap-is-unreachable": ("fn main() { match 1 { 0..=42 => 0, 1..=4 => 1, _ => 2 } }\n",
                                            "type", "unreachable match arm"),
    "or-patterns-bind-same-names": ("copy enum Value { First(i32); Second(i32) }\nfn main() { match Value::First(42) { Value::First(a) | Value::Second(b) => a } }\n",
                                   "type", "identical names"),
    "sum-match-must-be-exhaustive": ("copy enum Value { First; Second }\nfn main() { match Value::First { Value::First => 0 } }\n",
                                    "type", "non-exhaustive match"),
    "nested-optional-coverage": ("fn main() { let value: i32?? = present(none); match value { none => 0, present(present(_)) => 1 } }\n",
                                "type", "non-exhaustive match"),
    "guards-do-not-prove-coverage": ("fn main() { match true { true if true => 0, false => 1 } }\n",
                                     "type", "non-exhaustive match"),
    "duplicate-match-arm": ("fn main() { match true { true => 0, true => 1, false => 2 } }\n",
                            "type", "unreachable match arm"),
    "outcome-keeps-error-identity": ("copy enum First { Bad }\ncopy enum Second { Bad }\nfn fail(): i32 throws First { throw First::Bad }\nfn wrong(): i32 throws Second { try fail() }\nfn main() { 0 }\n",
                                    "effects", "propagated error"),
    "typed-call-needs-explicit-handling": ("copy enum Error { Bad }\nfn fail(): i32 throws Error { throw Error::Bad }\nfn main() { fail() }\n",
                                          "effects", "requires try or capture"),
    "capture-is-not-panic-catch": ("fn main() { let value = capture (1 / 0); 0 }\n",
                                  "effects", "requires a typed throwing"),
    "throw-needs-declared-effect": ("copy enum Error { Bad }\nfn bad() { throw Error::Bad }\nfn main() { 0 }\n",
                                    "effects", "explicit throws"),
    "read-match-cannot-move-owner": ("type Owned { value: i32 }\nenum Value { Held(Owned) }\nfn consume(value: take Owned) {}\nfn main() { let value = Value::Held(Owned(42)); match value { Value::Held(item) => consume(item) }; 0 }\n",
                                    "ownership", "cannot move out of a borrowed place"),
    "array-repetition-must-be-copy": ("type Owned { value: i32 }\nfn main() { let values = [Owned(42); 2]; 0 }\n",
                                      "ownership", "requires Copy"),
    "array-constant-index-bounds": ("fn main() { let values = [42]; values[1] }\n",
                                    "type", "out of bounds"),
    "refutable-binding-needs-else": ("fn main() { let value: i32? = none; let present(answer) = value; answer }\n",
                                     "type", "refutable pattern"),
    "let-else-must-diverge": ("fn main() { let value: i32? = none; let present(answer) = value else { 0 }; answer }\n",
                             "type", "must diverge"),
    "nonlocal-break-must-initialize-on-every-path": ("fn choose(flag: bool) { let answer: i32; label outer: loop { loop { if flag { break label outer }; answer = 42; break label outer } }; answer }\nfn main() { choose(false) }\n",
                                                    "type", "may be uninitialized"),
    "loop-break-values-must-agree": ("fn choose(flag: bool) { loop { if flag { break true }; break 42 } }\nfn main() { 0 }\n",
                                    "type", "expected bool, found i32"),
    "bare-break-is-unit": ("fn choose(flag: bool) { loop { if flag { break }; break 42 } }\nfn main() { 0 }\n",
                           "type", "expected Unit, found i32"),
    "while-loop-remains-unit": ("fn main() { while true { break 42 }; 0 }\n",
                                "type", "expected Unit, found i32"),
    "unknown-break-label": ("fn main() { loop { break label missing 42 } }\n",
                            "name", "unknown loop label 'missing'"),
    "unknown-continue-label": ("fn main() { loop { continue label missing } }\n",
                               "name", "unknown loop label 'missing'"),
    "label-does-not-escape-loop": ("fn main() { label done: loop { break }; break label done; 0 }\n",
                                  "name", "unknown loop label 'done'"),
    "continue-cannot-carry-value": ("fn main() { loop { continue 42 } }\n",
                                   "parse", "continue cannot carry a value"),
    "loop-result-does-not-inherit-callers-type": ("fn answer() { loop { break true } }\nfn main() { let answer: i32 = answer(); 0 }\n",
                                                 "type", "expected i32, found bool"),
    "break-view-cannot-escape-local": ("fn main() { let view = loop { let owned = 42; break read owned }; *view }\n",
                                      "ownership", "live read loan"),
    "owned-break-result-cannot-borrow-loop-local": ("type Guard<region r> { value: read i32 from r; drop { let observed = *self.value } }\nfn main() { let guard = loop { let owned = 42; break Guard(read owned) }; 0 }\n",
                                                   "ownership", "live read loan"),
    "break-still-moves-owned-value": ("type Value { value: i32 }\nfn main() { let first = Value(42); let second = loop { break first }; first.value }\n",
                                      "ownership", "moved"),
    "alias-cycle": ("alias First = Second\nalias Second = First\nfn main() { 0 }\n",
                    "type", "cyclic type alias"),
    "alias-view-cycle": ("alias First = read Second\nalias Second = First\nfn main() { 0 }\n",
                         "type", "cyclic type alias"),
    "alias-recursive-product-layout": ("alias Link = Node\ntype Node { next: Link }\nfn main() { 0 }\n",
                                       "type", "recursive by-value"),
    "alias-nested-unbound-region": ("alias View = (read i32 from missing)\nfn main() { 0 }\n",
                                    "name", "unknown region"),
    "alias-unknown-target": ("alias Missing = Unknown\nfn main() { 0 }\n",
                             "name", "type 'Unknown'"),
    "alias-duplicate-name": ("type Point {}\nalias Point = i32\nfn main() { 0 }\n",
                             "name", "duplicate type"),
    "alias-does-not-change-nominal-identity": ("copy type First { value: i32 }\ncopy type Second { value: i32 }\nalias Same = First\nfn consume(value: Same) {}\nfn main() { consume(Second(42)); 0 }\n",
                                             "type", "expected First, found Second"),
    "alias-does-not-grant-copy": ("type Owned { value: i32 }\nalias Same = Owned\ncopy type Wrapper { value: Same }\nfn main() { 0 }\n",
                                 "type", "not Copy"),
    "alias-view-field-needs-region": ("alias View = read i32\ntype Reader { value: View }\nfn main() { 0 }\n",
                                      "type", "declared region source"),
    "alias-preserves-read-permission": ("alias View = read i32\nfn main() { var x = 1; let view: View = read x; *view = 2; 0 }\n",
                                        "ownership", "cannot write through a read"),
    "static-function-has-no-self": ("type Point { static fn bad() { self.value } }\nfn main() { 0 }\n",
                                    "name", "unresolved value 'self'"),
    "static-function-not-object-method": ("copy type Point { static fn make() { 42 } }\nfn main() { let point = Point(); point.make() }\n",
                                          "type", "type-qualified call"),
    "qualified-consuming-method-still-moves": ("type Point { value: i32; take fn consume() {} }\nalias Same = Point\nfn main() { let p = Point(42); Same::consume(p); p.value }\n",
                                              "ownership", "moved"),
    "qualified-mut-method-not-two-phase": ("type Counter { value: i32; fn get() { self.value }; mut fn add(value: i32) { self.value += value } }\nfn main() { var counter = Counter(1); Counter::add(counter, counter.get()); 0 }\n",
                                           "ownership", "live exclusive loan"),
    "qualified-drop-not-directly-callable": ("type Guard { drop {} }\nfn main() { var guard = Guard(); Guard::drop(guard); 0 }\n",
                                            "ownership", "destructor directly"),
    "nested-view-take-receiver": ("""
type Counter { value: i32; take fn consume() {} }
fn main() {
    let counter = Counter(42)
    let first = read counter
    let second = read first
    second.consume()
    0
}
""", "ownership", "cannot move out of a borrowed place"),
    "conditional-writeback-retains-old-source": ("""
copy type Reader<region r> { value: read i32 from r }
fn set(reader: mut Reader, source: read i32, flag: bool) {
    if flag { reader.value = read source }
}
fn main() {
    var first = 40
    let second = 42
    var reader = Reader(read first)
    set(reader, second, false)
    first = 0
    *reader.value
}
""", "ownership", "live read loan"),
    "self-writeback-preserves-source": ("""
copy type Reader<region r> { value: read i32 from r }
fn echo(reader: mut Reader) { reader.value = reader.value }
fn main() {
    var reader: Reader
    { let short = 42; reader = Reader(read short); echo(reader) }
    *reader.value
}
""", "ownership", "live read loan"),
    "nested-returned-view-cannot-escape": ("""
copy type Payload<region r> { value: read i32 from r }
copy type Reader<region r> { inner: read Payload from r }
fn get(reader: read Reader): read i32 from reader { reader.inner.value }
fn main() {
    let child: read i32
    {
        let short = 42
        let payload = Payload(read short)
        let reader = Reader(read payload)
        child = read *get(reader)
    }
    *child
}
""", "ownership", "live read loan"),
    "owned-call-destructor-writeback-cannot-escape-source": ("""
copy type Reader<region r> { value: read i32 from r }
type Writer<region a, region b> {
    target: mut Reader from a
    source: read i32 from b
    drop { self.target.value = self.source }
}
fn release(writer: take Writer) {}
fn main() {
    let first = 42
    var reader = Reader(read first)
    { let short = 0; release(Writer(mut reader, read short)) }
    *reader.value
}
""", "ownership", "live read loan"),
    "destructor-writeback-cannot-escape-source": ("""
copy type Reader<region r> { value: read i32 from r }
type Writer<region a, region b> {
    target: mut Reader from a
    source: read i32 from b
    drop { self.target.value = self.source }
}
fn main() {
    let first = 42
    var reader = Reader(read first)
    { let short = 0; let writer = Writer(mut reader, read short) }
    *reader.value
}
""", "ownership", "live read loan"),
    "writeback-preserves-return-dependencies": ("""
copy type Reader<region r> { value: read i32 from r }
fn first(a: read i32, b: read i32): read i32 from (a, b) { read a }
fn set(target: mut Reader, a: read i32, b: read i32) {
    target.value = first(a, b)
}
fn main() {
    let value = 42
    var reader = Reader(read value)
    { let short = 0; set(reader, value, short) }
    *reader.value
}
""", "ownership", "live read loan"),
    "wrapper-preserves-return-sources": ("""
fn first(a: read i32, b: read i32): read i32 from (a, b) { read a }
fn wrapper(a: read i32, b: read i32): read i32 from a { first(a, b) }
fn main() { 0 }
""", "ownership", "declared input sources"),
    "destructor-conflicts-with-derived-view": ("""
type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var value = 42
    let child: read i32
    { let guard = Guard(mut value); child = read *guard.value }
    *child
}
""", "ownership", "live read loan"),
    "replacement-destructor-conflicts-with-derived-view": ("""
type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var first = 42
    var second = 0
    var guard = Guard(mut first)
    let child = read *guard.value
    guard = Guard(mut second)
    *child
}
""", "ownership", "live read loan"),
    "view-store-cannot-escape-local": ("copy type R<region r> { value: read i32 from r }\nfn bad(target: mut R) { let owned = 42; target.value = read owned }\nfn main() { 0 }\n",
                                      "ownership", "caller-owned storage"),
    "view-writeback-short-source": ("copy type R<region r> { value: read i32 from r }\nfn set(target: mut R, value: read i32) { target.value = read value }\nfn forward(target: mut R, value: read i32) { set(target,value) }\nfn main() { let first = 1; var target = R(read first); { let short = 2; forward(target,short) }; *target.value }\n",
                                    "ownership", "live read loan"),
    "call-view-content-alias": ("copy type R<region r> { value: read i32 from r }\nfn both(reader: read R, writer: mut i32) { writer = *reader.value }\nfn main() { var x = 1; let reader = R(read x); both(reader,x); 0 }\n",
                                "ownership", "live read loan"),
    "stored-read-mutation": ("fn main() { var x = 1; let v = read x; x = 2; *v }\n",
                             "ownership", "live read loan"),
    "copied-read-still-live": ("fn main() { var x = 1; let v = read x; let copied = v; x = 2; *copied }\n",
                              "ownership", "live read loan"),
    "exclusive-parent-suspended": ("fn main() { var x = 1; let p = mut x; let child = mut *p; *p = 2; *child }\n",
                                   "ownership", "live exclusive loan"),
    "exclusive-parent-moved": ("fn main() { var x = 1; let p = mut x; let child = read *p; let moved = p; *child }\n",
                               "ownership", "live read loan"),
    "read-view-not-writable": ("fn main() { var x = 1; let p = read x; *p = 2; 0 }\n",
                               "ownership", "write through a read"),
    "read-view-no-exclusive-upgrade": ("fn main() { var x = 1; let p = read x; let child = mut *p; 0 }\n",
                                      "ownership", "mutable place"),
    "view-pointee-cannot-be-moved": ("type C { value: i32 }\nfn main() { var c = C(1); let p = mut c; let moved = *p; 0 }\n",
                                    "ownership", "cannot move out of a borrowed place"),
    "returned-local-view": ("fn bad(source: read i32): read i32 from source { let owned = 1; read owned }\nfn main() { 0 }\n",
                            "ownership", "returned view escapes"),
    "returned-source-mismatch": ("fn bad(first: read i32, second: read i32): read i32 from first { read second }\nfn main() { 0 }\n",
                                 "ownership", "declared input sources"),
    "ambiguous-returned-view": ("fn bad(first: read i32, second: read i32): read i32 { read first }\nfn main() { 0 }\n",
                                "type", "ambiguous borrowed result"),
    "call-does-not-extend-temporary": ("type C { value: i32 }\nfn identity(c: C): read C from c { read c }\nfn main() { let v = identity(C(42)); v.value }\n",
                                      "ownership", "live read loan"),
    "returned-sources-both-live": ("fn first(a: read i32, b: read i32): read i32 from (a,b) { read a }\nfn main() { var a = 1; var b = 2; let v = first(a,b); b = 3; *v }\n",
                                   "ownership", "live read loan"),
    "reservation-forbids-mutation": ("type C { value: i32; mut fn add(n: i32) { self.value += n } }\nfn main() { var c = C(1); c.add({ c.value = 2; 1 }); 0 }\n",
                                     "ownership", "live exclusive loan"),
    "ordinary-mut-call-not-two-phase": ("type C { value: i32; fn get() { self.value } }\nfn add(c: mut C,n: i32) { c.value += n }\nfn main() { var c = C(1); add(c,c.get()); 0 }\n",
                                        "ownership", "live exclusive loan"),
    "activation-conflicts-with-read": ("type C { value: i32; fn view(): read i32 from self { read self.value }; mut fn add(n: read i32) { self.value += n } }\nfn main() { var c = C(1); c.add(c.view()); 0 }\n",
                                       "ownership", "live read loan"),
    "destructor-cannot-be-copy": ("copy type C { value: i32; drop {} }\nfn main() { 0 }\n",
                                  "type", "destructor"),
    "destructor-forbids-partial-move": ("type Leaf { value: i32 }\ntype C { leaf: Leaf; drop {} }\nfn main() { let c = C(Leaf(1)); let leaf = c.leaf; 0 }\n",
                                       "ownership", "partially move"),
    "destructor-retains-view": ("type Guard<region r> { view: read i32 from r; drop { let observed = *self.view } }\nfn main() { var x = 1; let guard = Guard(read x); x = 2; 0 }\n",
                                "ownership", "live read loan"),
    "destructor-not-directly-callable": ("type C { drop {} }\nfn main() { var c = C(); c.drop(); 0 }\n",
                                         "ownership", "destructor directly"),
    "exclusive-argument-alias": ("type C { value: i32 }\nfn both(a: mut C,b: mut C) {}\nfn main() { var c = C(1); both(c,c); 0 }\n",
                                "ownership", "live exclusive loan"),
    "read-exclusive-argument-alias": ("type C { value: i32 }\nfn both(a: C,b: mut C) {}\nfn main() { var c = C(1); both(c,c); 0 }\n",
                                     "ownership", "live read loan"),
    "mutation-during-read-argument": ("type C { value: i32 }\nfn outer(a: C,b: i32) {}\nfn change(c: mut C) { c.value += 1; 0 }\nfn main() { var c = C(1); outer(c,change(c)); 0 }\n",
                                     "ownership", "live read loan"),
    "parent-read-during-mut-argument": ("type C { value: i32 }\nfn outer(a: mut C,b: i32) {}\nfn main() { var c = C(1); outer(c,c.value); 0 }\n",
                                       "ownership", "live exclusive loan"),
    "immutable-exclusive-borrow": ("type C { value: i32 }\nfn change(c: mut C) { c.value += 1 }\nfn main() { let c = C(1); change(c); 0 }\n",
                                   "ownership", "mutable place"),
    "write-through-read-parameter": ("type C { value: i32 }\nfn bad(c: C) { c.value = 2 }\nfn main() { 0 }\n",
                                     "ownership", "write through a read parameter"),
    "borrowed-owned-return": ("type C { value: i32 }\nfn bad(c: C): C { c }\nfn main() { 0 }\n",
                              "ownership", "cannot move out of a borrowed place"),
    "take-borrowed-copy": ("fn bad(value: read i32) { let x = take value }\nfn main() { 0 }\n",
                           "ownership", "cannot move out of a borrowed place"),
    "read-to-mut-reborrow": ("type C { value: i32 }\nfn change(c: mut C) {}\nfn bad(c: C) { change(c) }\nfn main() { 0 }\n",
                             "ownership", "mutable place"),
    "use-after-move": ((Path(__file__).resolve().parents[1] / "examples/core/reject-use-after-move.mt").read_text(),
                       "ownership", "moved"),
    "take-copy-contract": ((Path(__file__).resolve().parents[1] / "examples/core/reject-take-copy.mt").read_text(),
                           "ownership", "moved"),
    "whole-partial-initialization": ("copy type P { x: i32; y: i32 }\nfn main() { let p: P; p.x = 1; let copied = p; 0 }\n",
                                      "type", "binding 'p' may be uninitialized"),
    "field-read-before-init": ("copy type P { x: i32 }\nfn main() { let p: P; p.x }\n",
                               "type", "binding 'p.x' may be uninitialized"),
    "field-double-initialization": ("copy type P { x: i32 }\nfn main() { let p: P; p.x = 1; p.x = 2; 0 }\n",
                                    "type", "immutable binding 'p.x'"),
    "zero-size-field-initialization": ("copy type E {}\ncopy type P { x: i32; tag: E }\nfn main() { let p: P; p.x = 0; let copied = p; 0 }\n",
                                       "type", "binding 'p' may be uninitialized"),
    "field-one-path-initialized": ("copy type P { x: i32 }\nfn choose(b: bool) { let p: P; if b { p.x = 42 }; p.x }\nfn main() { choose(true) }\n",
                                   "type", "binding 'p.x' may be uninitialized"),
    "field-loop-reassignment": ("copy type P { x: i32 }\nfn main() { let p: P; var n = 0; while n < 2 { p.x = n; n += 1 }; 0 }\n",
                                "type", "immutable binding 'p.x'"),
    "field-assignment-type": ("copy type P { x: i32 }\nfn main() { var p = P(0); p.x = true; 0 }\n",
                              "type", "expected i32, found bool"),
    "immutable-reinit-after-move": ("type P { x: i32 }\nfn main() { let p = P(1); let q = p; p = P(2); 0 }\n",
                                    "type", "immutable binding 'p'"),
    "loop-use-after-move": ("type P { x: i32 }\nfn main() { var p = P(1); var n = 0; while n < 2 { let q = p; n += 1 }; 0 }\n",
                            "ownership", "moved"),
    "conditional-use-after-move": ("type P { x: i32 }\nfn choose(flag: bool) { let p = P(42); if flag { let q = p }; p.x }\nfn main() { choose(false) }\n",
                                   "ownership", "moved"),
    "whole-use-after-field-take": ("copy type P { x: i32; y: i32 }\nfn main() { let p = P(20,22); let x = take p.x; let q = p; 0 }\n",
                                   "ownership", "moved"),
    "product-unknown-field": ("copy type P { x: i32 }\nfn main() { P(1).missing }\n", "name", "unknown field 'missing'"),
    "product-field-type": ("copy type P { x: i32 }\nfn main() { let p = P(true); 0 }\n", "type", "expected i32, found bool"),
    "product-missing-field": ("copy type P { x: i32 }\nfn main() { let p = P(); 0 }\n", "type", "argument count"),
    "product-duplicate-field": ("copy type P { x: i32; x: i32 }\nfn main() { 0 }\n", "name", "duplicate field"),
    "product-nominal-types": ("copy type A { x: i32 }\ncopy type B { x: i32 }\nfn main() { let x: A = B(1); 0 }\n", "type", "expected A, found B"),
    "product-recursive-layout": ("copy type A { b: B }\ncopy type B { a: A }\nfn main() { 0 }\n", "type", "no finite layout"),
    "product-noncopy-field": ("type Owner { x: i32 }\ncopy type Bad { owner: Owner }\nfn main() { 0 }\n", "type", "not Copy"),
    "product-implicit-comparison": ("copy type P { x: i32 }\nfn main() { if P(1) == P(1) { 0 } else { 1 } }\n", "type", "comparison interface"),
    "unknown-name": ("fn main(): i32 { missing }\n", "name"),
    "unknown-function": ("fn main(): i32 { missing() }\n", "name"),
    "unknown-type": ("fn main(): Missing { 0 }\n", "name"),
    "wrong-return": ("fn main(): i32 { true }\n", "type"),
    "conflicting-return": ("fn f(b: bool) { if b { return 1 }; false }\nfn main() { 0 }\n", "type"),
    "unanchored-cycle": ("fn f() { g() }\nfn g() { f() }\nfn main(): i32 { f() }\n", "type"),
    "wrong-call-type": ("fn f(x: i32) { x }\nfn main() { f(true) }\n", "type"),
    "wrong-arity": ("fn f(x: i32) { x }\nfn main() { f() }\n", "type"),
    "duplicate-label": ("fn f(x: i32, y: i32) { x }\nfn main() { f(x: 1, x: 2) }\n", "type"),
    "unknown-label": ("fn f(x: i32) { x }\nfn main() { f(y: 1) }\n", "type"),
    "positional-after-label": ("fn f(x: i32, y: i32) { x }\nfn main() { f(y: 1, 2) }\n", "type"),
    "uninitialized": ("fn main(): i32 { let x: i32; x }\n", "type"),
    "partial-initialization": ("fn f(b: bool) { let x: i32; if b { x = 1 }; x }\nfn main() { 0 }\n", "type"),
    "double-initialization": ("fn main() { let x = 1; x = 2; x }\n", "type"),
    "loop-double-initialization": ("fn main() { let x: i32; var n = 0; while n < 2 { x = n; n += 1 }; 0 }\n", "type"),
    "compound-uninitialized": ("fn main() { var x: i32; x += 1; x }\n", "type"),
    "loop-control": ("fn main() { break; 0 }\n", "type"),
    "duplicate-function": ("fn main() { 0 }\nfn main() { 0 }\n", "name"),
    "duplicate-parameter": ("fn f(x: i32, x: i32) { x }\nfn main() { 0 }\n", "name"),
    "wrong-entry": ("fn main(x: i32) { x }\n", "type"),
    "missing-entry": ("fn f() { 0 }\n", "name"),
    "literal-range": ("fn main() { 2147483648 }\n", "type"),
    "literal-separator": ("fn main() { 1__2 }\n", "lex"),
    "literal-suffix": ("fn main() { 42unknown }\n", "lex"),
    "negative-range": ("fn main() { -2147483649 }\n", "type"),
    "old-arrow": ("fn main() -> i32 { 0 }\n", "parse"),
    "old-unit-type": ("fn ignored(): () {}\nfn main() { 0 }\n", "parse"),
    "old-never-type": ("fn ignored(): never { loop {} }\nfn main() { 0 }\n", "name"),
    "missing-operand": ("fn main() { 1 + }\n", "parse"),
    "missing-brace": ("fn main() { 0\n", "parse"),
    "no-separator": ("fn main() { let x = 1 let y = 2; 0 }\n", "parse"),
    "comparison-chain": ("fn main() { if 1 < 2 < 3 { 0 } else { 1 } }\n", "parse"),
    "newline-before-call": ("fn f() { 1 }\nfn main() { f\n() }\n", "type", "entry function"),
    "unterminated-comment": ("fn main() { 0 } /* missing", "lex"),
    "invalid-character": ("fn main() { $ }\n", "lex"),
    "unused-generic-does-not-gain-copy": (
        "fn f<T>(x: T): T { x }\nfn main() { 0 }\n", "ownership"),
    "unknown-effect-type": ("fn f() throws Error { 0 }\nfn main() { 0 }\n", "name", "type 'Error'"),
    "capturing-closure-cannot-coerce-to-thin-pointer": ("""
fn main(): i32 {
    let value = 42
    let pointer: fn(): i32 = fn() { value }
    pointer()
}
""", "type", "expected fn()"),
    "borrowed-closure-cannot-move-captured-place": ("""
type Item { value: i32 }
fn consume(item: take Item): i32 { item.value }
fn main(): i32 {
    let item = Item(42)
    let closure = fn(): i32 { consume(item) }
    closure()
}
""", "ownership", "requires a take closure"),
    "copied-borrowed-closure-cannot-escape": ("""
fn main(): i32 {
    let escaped = {
        let value = 42
        let closure = fn(): i32 { value }
        let copied = closure
        copied
    }
    escaped()
}
""", "ownership", "live read loan"),
    "consume-callable-bound-is-not-repeatedly-callable": ("""
fn twice<F: take fn(): i32>(operation: take F): i32 {
    operation() + operation()
}
fn answer(): i32 { 42 }
fn main(): i32 { twice(answer) }
""", "ownership", "may have been moved"),
    "mutating-closure-requires-exclusive-binding": ("""
fn main(): i32 {
    var value = 0
    let closure = fn(): Unit { value += 1 }
    closure()
    value
}
""", "ownership", "mutable place"),
    "function-pointer-access-contract-is-not-erased": ("""
fn value(input: i32): i32 { input }
fn main(): i32 {
    let pointer: fn(read i32): i32 = value
    pointer(42)
}
""", "type", "expected fn(read i32)"),
    "indirect-returned-product-view-keeps-input-loans": ("""
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
fn expose(reader: read Reader): read Pair from reader { reader.value }
fn main(): i32 {
    var pair = Pair(20,22)
    let reader = Reader(read pair)
    let pointer: fn(read Reader): read Pair = expose
    let result = pointer(reader)
    pair.first += 1
    result.first + result.second
}
""", "ownership", "live read loan"),
    "higher-ranked-callable-bound-rejects-monomorphic-pointer": ("""
fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    operation: read F, value: read i32): read i32 from value {
    operation(value)
}
fn invalid<region outer>(
    operation: fn(read i32 from outer): read i32 from outer,
    value: read i32 from outer): read i32 from value {
    apply(operation,value)
}
fn main(): i32 { 0 }
""", "region", "declared relationship"),
    "callable-type-requires-result-annotation": ("""
fn main(): i32 {
    let closure: fn() = fn() { 42 }
    closure()
}
""", "parse", "expected ':'"),
    "unused-generic-body-is-checked": (
        "fn wrong<T>(value: T): i32 { value }\nfn main(): i32 { 0 }\n", "type"),
    "ordinary-copy-interface-grants-no-copy-rights": ("""
module fake { pub interface Copy {} }
fn wrong<T: fake::Copy>(value: T): T { value }
fn main(): i32 { 0 }
""", "ownership"),
    "unused-generic-const-default-overflow": (
        "fn answer<const N:i32=2147483647+1>():i32{N}\n"
        "fn main():i32{0}\n", "type", "overflows"),
    "generic-array-repeat-needs-declared-copy": (
        "fn wrong<T,const N:i32>(value:take T):[T;N]{[value;N]}\n"
        "fn main():i32{0}\n", "ownership", "requires Copy"),
    "generic-array-loop-cannot-reuse-moved-outer-value": ("""
type Owned { value: i32 }
fn wrong<const N:i32>(values:read [i32;N], owner:take Owned):Unit {
    for value in values { let moved = take owner }
}
fn main():i32{0}
""", "ownership"),
    "unused-generic-bound-must-resolve": (
        "fn wrong<T:Missing>(value:T):Unit{()}\nfn main():i32{0}\n",
        "type", "unknown interface bound"),
    "interface-default-self-does-not-grant-sized": ("""
fn require_sized<T>(value: read T): Unit { () }
interface Bound<Rhs = Self> {
    fn invalid(): Unit { require_sized(self) }
}
fn main(): i32 { 0 }
""", "type", "does not satisfy Sized"),
    "equal-implementation-constraints-still-overlap": ("""
interface Code { fn code(): i32; }
type Box<T> { value:T }
impl<T> Box<T> implements Code where T=i32 { fn code():i32{1} }
impl<U> Box<U> implements Code where U=i32 { fn code():i32{2} }
fn main():i32{0}
""", "type", "overlapping implementations"),
    "missing-current-implementations-do-not-prove-disjointness": ("""
interface A {}
interface B {}
interface Code { fn code():i32; }
type Box<T> { value:T }
impl<T:A> Box<T> implements Code { fn code():i32{1} }
impl<T:B> Box<T> implements Code { fn code():i32{2} }
fn main():i32{0}
""", "type", "overlapping implementations"),
    "inherent-implementation-requirements-are-not-assumed": ("""
type Box<T> { value:T }
type Owned { value:i32 }
impl<T:Copy> Box<T> { fn answer():i32{42} }
fn main():i32{let value=Box(Owned(0));value.answer()}
""", "name", "unresolved"),
    "unconstrained-implementation-type-parameter": (
        "type Plain{}\nimpl<T> Plain{fn answer():i32{42}}\nfn main():i32{0}\n",
        "type", "unconstrained implementation parameter"),
    "unconstrained-implementation-const-parameter": (
        "type Plain{}\nimpl<const N:i32> Plain{fn answer():i32{N}}\n"
        "fn main():i32{0}\n", "type", "unconstrained implementation parameter"),
}

ARITHMETIC = {
    "machine-cell-conflicting-exclusive-guard-panics": (
        "let cell=core::cell::RefCell::new(42); let first=cell.borrow(); let second=cell.borrow_mut(); 0",
        "trap", "trap"),
    "machine-cell-conflicting-shared-guard-panics": (
        "let cell=core::cell::RefCell::new(42); let first=cell.borrow_mut(); let second=cell.borrow(); 0",
        "trap", "trap"),
    "machine-cell-forgotten-exclusive-guard-stays-borrowed": (
        "let cell=core::cell::RefCell::new(42); let guard=cell.borrow_mut(); core::mem::forget(guard); let next=cell.borrow(); 0",
        "trap", "trap"),
    "machine-atomic-invalid-load-order": (
        "let value=core::sync::atomic::AtomicU32::new(42); value.load(core::sync::atomic::Ordering::Release) as i32",
        "trap", "trap"),
    "machine-atomic-invalid-store-order": (
        "let value=core::sync::atomic::AtomicU32::new(42); value.store(1,core::sync::atomic::Ordering::Acquire); 0",
        "trap", "trap"),
    "machine-atomic-invalid-cas-failure-order": (
        "let value=core::sync::atomic::AtomicU32::new(42); let outcome=value.compare_exchange(42,1,core::sync::atomic::Ordering::SeqCst,core::sync::atomic::Ordering::Release); 0",
        "trap", "trap"),
    "machine-u128-profile-overflow": (
        "let value=u128::MAX; if value+1 == 0u128 { 0 } else { 1 }", "trap", 0),
    "machine-unsigned-sub-profile-overflow": (
        "let value=0u8; if value-1 == 255u8 { 0 } else { 1 }", "trap", 0),
    "machine-cross-width-negative-shift": (
        "let count=-1i8; if 1u64 << count == 9223372036854775808u64 { 0 } else { 1 }", "trap", 0),
    "machine-i128-division-overflow": (
        "let value=i128::MIN; let divisor=-1i128; let result=value/divisor; 0", "trap", "trap"),
    "array-dynamic-upper-bound": ("let values=[42]; let index=1; values[index]", "trap", "trap"),
    "array-dynamic-negative-bound": ("let values=[42]; let index=-1; values[index]", "trap", "trap"),
    "overflow-add": ("let x = 2147483647; if x + 1 == -2147483648 { 0 } else { 1 }", "trap", 0),
    "overflow-sub": ("let x = -2147483648; if x - 1 == 2147483647 { 0 } else { 1 }", "trap", 0),
    "overflow-mul": ("let x = 1073741824; if x * 2 == -2147483648 { 0 } else { 1 }", "trap", 0),
    "overflow-neg": ("let x = -2147483648; if -x == x { 0 } else { 1 }", "trap", 0),
    "zero-div": ("1 / 0", "trap", "trap"),
    "zero-rem": ("1 % 0", "trap", "trap"),
    "division-overflow": ("-2147483648 / -1", "trap", "trap"),
    "remainder-overflow": ("-2147483648 % -1", "trap", "trap"),
    "shift-range": ("if (1 << 32) == 1 { 0 } else { 1 }", "trap", 0),
    "shift-negative": ("if (1 >> -1) == 0 { 0 } else { 1 }", "trap", 0),
    "valid-integer-ops": ("if (42 / 5) == 8 && (42 % 5) == 2 && "
                          "((1 << 31) >> 31) == -1 && (6 & 3) == 2 && "
                          "(4 | 1) == 5 && (7 ^ 3) == 4 { 0 } else { 1 }", 0, 0),
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_suite(mode, executable, directory):
    executable = str(Path(executable).resolve())
    directory = Path(directory) / mode
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"scope": "Source regressions through the initial I06 machine boundary; not full language or release qualification",
                "status": "in_progress", "mode": mode, "compiler_sha256": digest(executable),
                "host": platform.platform(), "commands": [], "cases": []}

    def run(arguments, expected=0):
        begin = time.perf_counter()
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=30)
        evidence["commands"].append({"command": list(map(str, arguments)),
                                    "exit_status": result.returncode,
                                    "elapsed_seconds": time.perf_counter() - begin,
                                    "stdout": result.stdout, "stderr": result.stderr})
        if (expected == "trap" and result.returncode >= 0) or (
                expected != "trap" and result.returncode != expected):
            raise AssertionError(f"{arguments!r}: expected {expected}, got {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")
        return result

    def source(name, text):
        path = directory / (name + ".mt")
        path.write_text(text)
        return path

    def compile_run(name, text, profile, expected, extra=()):
        path = source(name, text)
        program = directory / (name + "-" + profile)
        run([executable, "build", str(path), "-o", str(program),
             "--profile", profile, *extra])
        run([str(program)], expected)
        evidence["cases"].append({"file": str(path), "source_sha256": digest(path),
                                  "profile": profile, "expected": expected,
                                  "program_sha256": digest(program)})
        if name == "machine-numeric-explicit-function-and-module-relaxations" and profile == "debug":
            output = directory / (name + ".ll")
            run([executable, "build", str(path), "--emit", "llvm",
                 "--profile", profile, "-o", str(output)])
            bodies = {}
            for body in re.findall(r"^define [^\n]*\n.*?^}", output.read_text(), re.M | re.S):
                symbol = re.search(r'@(?:"([^"]+)"|([^ (]+))\(', body)
                bodies[symbol[1] or symbol[2]] = body
            flags = {"reassoc", "nnan", "ninf", "nsz", "arcp", "contract", "afn", "fast"}
            for owner, operations, selected in (
                    ("multiply_add", {"fmul", "fadd"}, {"contract"}),
                    ("<closure-", {"fmul", "fadd"}, {"contract"}),
                    ("defaulted.<default.", {"fmul", "fadd"}, {"contract"}),
                    ("relaxed::calculate", {"fadd"}, {"reassoc", "arcp", "afn"}),
                    ("separate", {"fmul", "fadd"}, set()),
                    ("checked", {"fcmp"}, set())):
                matches = [body for symbol, body in bodies.items()
                           if symbol == "mettle." + owner + ".body" or
                           (owner.endswith(("-", ".")) and symbol.startswith("mettle." + owner)
                            and symbol.endswith(".body"))]
                if len(matches) != 1:
                    raise AssertionError(f"{owner}: expected one lowered arithmetic body")
                body = matches[0]
                found = set()
                for operation, operands in re.findall(r"\b(fmul|fadd|fcmp)\s+([^\n]+)", body):
                    if operation in operations:
                        found.add(operation)
                        actual = set(operands.split()) & flags
                        if actual != selected:
                            raise AssertionError(f"{owner}: expected floating flags {selected}, got {actual}")
                if found != operations:
                    raise AssertionError(f"{owner}: missing floating operations {operations - found}")
            evidence["cases"][-1]["llvm_sha256"] = digest(output)
    def batch(cases, execute):
        failures = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(execute, case) for case in cases]
            for future in futures:
                try:
                    future.result()
                except Exception as error:
                    failures.append(str(error))
        if failures:
            raise AssertionError("\n\n".join(failures))

    try:
        if mode == "positive":
            def execute_positive(case):
                name, text = case
                for profile in ("debug", "release"):
                    compile_run(name, text, profile, 0)
            batch(POSITIVE.items(), execute_positive)
        elif mode == "negative":
            def execute_negative(item):
                name, case = item
                text, phase, *messages = case
                path = source(name, text)
                program = directory / (name + ".out")
                program.write_bytes(b"preserve existing artifact")
                profiles = ("debug", "release") if name.startswith("machine-numeric-required-") else ("debug",)
                for profile in profiles:
                    result = run([executable, "build", str(path), "-o", str(program),
                                  "--profile", profile], 1)
                    if f"error[{phase}]" not in result.stderr or not re.search(
                            re.escape(str(path)) + r":\d+:\d+: error", result.stderr):
                        raise AssertionError(f"{name}: wrong/missing phase or span:\n{result.stderr}")
                    if program.read_bytes() != b"preserve existing artifact":
                        raise AssertionError(f"{name}: failed compilation damaged existing output")
                    if messages and messages[0] not in result.stderr:
                        raise AssertionError(f"{name}: missing intended diagnostic {messages[0]!r}\n{result.stderr}")
                    evidence["cases"].append({"file": str(path), "phase": phase,
                                             "profile": profile,
                                             "source_sha256": digest(path)})
            batch(NEGATIVE.items(), execute_negative)
        elif mode == "arithmetic":
            for name, (body, debug, release) in ARITHMETIC.items():
                for profile, expected in (("debug", debug), ("release", release)):
                    compile_run(name, "fn main(): i32 { " + body + " }\n", profile, expected)
            compile_run("explicit-on", "fn main() { let x = 2147483647; x + 1 }\n",
                        "release", "trap", ("--overflow-checks", "on"))
            compile_run("explicit-off", "fn main() { let x = 2147483647; if x + 1 < 0 { 0 } else { 1 } }\n",
                        "debug", 0, ("--overflow-checks", "off"))
        elif mode == "syntax":
            text = "// UTF-8 comment: café\r\nfn main()\r\n{\r\n /* a\r\n /* b */ c */\r\n(0)\r\n}\r\n"
            path = source("lossless", text)
            for command in ("tokens", "syntax"):
                result = run([executable, command, str(path)])
                tree = json.loads(result.stdout)
                if "".join(token["text"] for token in tree["tokens"]) != text:
                    raise AssertionError("Tokens did not preserve source bytes/trivia")
                for token in tree["tokens"]:
                    if text.encode()[token["begin"]:token["end"]].decode() != token["text"]:
                        raise AssertionError("Token span does not select its original bytes")
            run([executable, "check", str(path)])
            for emit, marker in (("ir", "fn main: i32"), ("llvm", "define i32 @main")):
                output = directory / emit
                run([executable, "build", str(path), "--emit", emit, "-o", str(output)])
                if marker not in output.read_text():
                    raise AssertionError(f"Missing {emit} representation")
            bad = source("recovery", "fn main() {\nlet x =\n;\nlet y =\n;\n0\n}\n")
            result = run([executable, "check", str(bad)], 1)
            if result.stderr.count("error[parse]") < 2:
                raise AssertionError("Parser did not recover to report separate malformed statements")
            bad.write_bytes(b"// invalid UTF-8: \xff\nfn main() { 0 }\n")
            if "error[lex]" not in run([executable, "check", str(bad)], 1).stderr:
                raise AssertionError("Invalid UTF-8 was accepted")
            for text in ("fn main() { " + "!" * 1000 + "true }\n",
                         "fn main() { " + "(" * 1000 + "0" + ")" * 1000 + " }\n"):
                bad.write_text(text)
                if "error[limit]" not in run([executable, "check", str(bad)], 1).stderr:
                    raise AssertionError("Deep syntax did not produce a bounded limit diagnostic")
            bad.write_text("fn main() { 0 }\n")
            run([executable, "build", str(bad), "-o", str(bad)], 1)
            output = directory / "unknown-target.o"
            run([executable, "build", str(bad), "-o", str(output), "--emit", "object",
                 "--target", "unknown-mettle-target"], 1)
            if output.exists():
                raise AssertionError("Unknown target created a published output")
        else:
            raise ValueError(mode)
        evidence["status"] = "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        evidence["child_peak_rss_high_water"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        evidence["rss_units"] = "bytes" if platform.system() == "Darwin" else "KiB"
        evidence["rss_scope"] = "cumulative child high-water mark, not isolated per-command memory"
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"{mode}: passed; {len(evidence['cases'])} retained cases, {len(evidence['commands'])} commands")


if __name__ == "__main__":
    run_suite(*sys.argv[1:])
