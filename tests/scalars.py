#!/usr/bin/env python3
"""Execute scalar, product and ownership cases with the existing runner."""

import argparse
import hashlib
import concurrent.futures
import json
import platform
import re
import resource
import signal
import subprocess
import sys
import time
from pathlib import Path


ARM64 = globals().get("TARGET_ARCH", platform.machine()).lower() in ("arm64", "aarch64")
ASM_ADD = "add {out:w}, {left:w}, {right:w}" if ARM64 else "mov {out:e}, {left:e}; add {out:e}, {right:e}"
ASM_MOVE = "mov {out:w}, {input:w}" if ARM64 else "mov {out:e}, {input:e}"
MACHINE_POSITIVE = {
    "concurrency-properties-are-structural-with-unsafe-opt-in": r"""
type Plain { a: i32; b: bool }
type Raw { p: ptr<mut u8> }
type Handle<T> { p: ptr<mut T> }
unsafe impl Raw implements Transferable {}
unsafe impl<T: Transferable> Handle<T> implements Transferable {}
unsafe impl<T: Shareable> Handle<T> implements Shareable {}
type Holder<T> { value: T }
type Cellular { c: core::cell::Cell<i32> }
fn send<T: Transferable>(value: take T): Unit {}
fn share<T: Shareable>(value: read T): Unit {}
fn owned<T: Transferable + Static>(value: take T): Unit {}
fn forward<T: Transferable>(value: take T): Unit { send(value) }
fn main(): i32 {
    send(Plain(1, true))
    send(Holder(Plain(1, true)))
    send(Raw(core::ptr::null_mut::<u8>()))
    send(Holder(Handle(core::ptr::null_mut::<i32>())))
    share(Plain(1, true))
    send(Cellular(core::cell::Cell::new(1)))
    forward(Holder(4))
    let k = 4
    owned(take fn(): i32 { k })
    0
}
""",
    "optional-view-unwrap-keeps-its-region": r"""
import core::text::Text;
fn word_free(w: read Text): Unit {}
fn first(t: read Text): (read Text from t)? { present(read t) }
fn b(text: read Text): Unit { let x = first(text).unwrap(); word_free(x) }
fn main(): i32 { b("x"); 0 }
""",
    "take-argument-from-copied-indexed-element": r"""
fn sink(value: take u8): u8 { value }
fn pick(digits: read [u8], i: usize): u8 { let d = digits[i]; sink(d) }
fn main(): i32 { let a = [7u8, 8u8]; if pick(a, 1usize) != 8u8 { return 1 }; 0 }
""",
    "const-items-in-expressions-lengths-and-patterns": r"""
const BASE: i32 = 5;
const LIMIT: i32 = BASE * 2 + 1;
const ALIAS: i32 = LIMIT;
const ENABLED: bool = true;
interface Width { const BITS: i32 = 8; }
type Narrow {}
impl Narrow implements Width { const BITS: i32 = 4; }
const NARROW_BITS: i32 = <Narrow implements Width>::BITS + 1;
pub module limits { pub const TOP: u8 = 200; }
fn classify(value: i32): i32 {
    match value { BASE => 1, ALIAS => 2, 0..=3 => 3, _ => 4 }
}
fn main(): i32 {
    let cells: [i32; 11] = [BASE; LIMIT]
    if classify(5) == 1 && classify(11) == 2 && classify(2) == 3 && classify(7) == 4 &&
       cells[10] == BASE && limits::TOP == 200 && NARROW_BITS == 5 && ENABLED { 0 } else { 1 }
}
""",
    "blanket-iterator-into-iterator-coexists-with-concrete-impl": r"""
module core {
    pub module iter {
        pub interface Iterator { type Item; mut fn next(): Self::Item?; }
        pub interface IntoIterator: Sized { type Item; type IntoIter: Iterator; fn into_iter(receiver self: take Self): Self::IntoIter; }
        impl<I: Iterator> I implements IntoIterator {
            type Item = I::Item
            type IntoIter = I
            fn into_iter(receiver self: take Self): I { self }
        }
    }
}
type Counter { n: i32; max: i32 }
impl Counter implements core::iter::Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
type Bag { max: i32 }
impl Bag implements core::iter::IntoIterator {
    type Item = i32
    type IntoIter = Counter
    fn into_iter(receiver self: take Self): Counter { Counter(0, self.max) }
}
fn main(): i32 { 0 }""",
    "generic-interface-impl-on-pointer-to-generic-type": r"""
import core::cmp::PartialEq;
type Cell2<T> { v: T }
type R<T> { p: ptr<mut Cell2<T>> }
impl<T> R<T> { fn get(): read T from self { unsafe { read (*self.p).v } } }
impl<T: PartialEq> R<T> implements PartialEq { fn eq(other: read R<T>): bool { self.get().eq(other.get()) } }
type Node<T> { v: T; next: ptr<mut Node<T>> }
type L<T> { head: ptr<mut Node<T>> }
impl<T> L<T> { fn first(): (read T from self)? { if self.head == core::ptr::null_mut::<Node<T>>() { none } else { present(unsafe { read (*self.head).v }) } } }
fn main(): i32 { 0 }
""",
    "range-indexing-user-protocol-read-and-mut": r"""
module core { pub module ops {
    pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: usize): read Self::Output from self; }
    pub interface IndexRangeMut { type Output: unsized; mut fn index_range_mut(start: usize, end: usize): mut Self::Output from self; }
} }
type Buf { cells: [i32; 4] }
impl Buf implements core::ops::IndexRange {
    type Output = [i32]
    fn index_range(start: usize, end: usize): read [i32] from self {
        let stop = if end > 4usize { 4usize } else { end }
        read self.cells[start..stop]
    }
}
impl Buf implements core::ops::IndexRangeMut {
    type Output = [i32]
    mut fn index_range_mut(start: usize, end: usize): mut [i32] from self {
        let stop = if end > 4usize { 4usize } else { end }
        mut self.cells[start..stop]
    }
}
fn main(): i32 {
    var b = Buf([1, 2, 3, 4])
    let mid: read [i32] = read b[1..3]
    let tail: read [i32] = read b[2..]
    let head: read [i32] = read b[..=0]
    if mid.len() != 2 || tail.len() != 2 || head.len() != 1 { return 1 }
    let w: mut [i32] = mut b[1..]
    w[0] = 20
    if b.cells[1] != 20 { return 2 }
    0
}
""",
    "closure-argument-takes-generic-result-from-explicit-type-argument": r"""
fn apply<B>(f: take fn(i32): B): B { f(1) }
type Holder<P> { p: P }
fn main(): i32 {
    let a = apply::<i32>(fn(x: i32): i32 { x + 41 })
    let h = Holder::<fn(i32): bool>(fn(x: i32): bool { x % 2 == 0 })
    if a != 42 || !h.p(4) || h.p(3) { return 1 }
    0
}
""",
    "generic-parameter-inferred-from-associated-binding-bound": """
module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self::Item?; } } }
import core::iter::Iterator;
type Counter { n: i32; max: i32 }
impl Counter implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
fn sum<T, I: Iterator<Item = T>>(it: take I, first: take T): T {
    var iter = it
    var acc = first
    while true { match take iter.next() { present(x) => { acc = x }, none => { break } } }
    acc
}
fn main(): i32 {
    let last = sum(Counter(0, 4), 0)
    if last != 3 { return 1 }
    0
}
""",
    "byte-text-literals-are-static-byte-arrays": r"""
fn sum(v: read [u8]): i32 { var t = 0; for x in v { t += x as i32 }; t }
fn main(): i32 {
    let a: read [u8; 3] from static = b"abc"
    let r: read [u8] = br"x\y"
    let e = b"\x00\xff\n"
    let s: read [u8] = a
    if sum(s) != 97 + 98 + 99 || r.len() != 3usize || e[1] != 255u8 { return 1 }
    0
}
""",
    "range-slicing-arrays-slices-and-mut-views": """
fn total(v: read [i32]): i32 { var t = 0; for x in v { t += x }; t }
fn main(): i32 {
    var a: [i32; 5] = [1, 2, 3, 4, 5]
    let s: read [i32] = read a[1..4]
    let whole: read [i32] = read a[..]
    let head: read [i32] = read a[..=1]
    let tail: read [i32] = read a[3..]
    if total(s) != 9 || whole.len() != 5 || head.len() != 2 || tail.len() != 2 { return 1 }
    let m: mut [i32] = mut a[1..3]
    m[0] = 20
    let inner: read [i32] = read m[1..]
    if inner.len() != 1 || a[1] != 20 { return 2 }
    0
}
""",
    "owners-generic-holder-of-view-infers-shared-region-for-exclusive-call": """
type Holder<T> { item: T? }
impl<T> Holder<T> {
    mut fn put(value: take T) { self.item = present(value) }
}
fn fill<region a>(h: mut Holder<read i32 from a>, v: read i32 from a) {
    h.put(read v)
}
fn main() {
    var x = 1
    let y = 2
    var h = Holder(item: present(read x))
    fill(mut h, read y)
    match h.item { present(v) => *v - 2, none => 1 }
}
""",
    "owners-external-mut-receiver-accepts-local-index-argument": """
module core { pub module ops {
    pub interface Index<I> { type Output; fn index(i: read I): read Self::Output from self; }
    pub interface IndexMut<I> { type Output; mut fn index_mut(i: read I): mut Self::Output from self; }
} }
type Cells { p: ptr<mut i32> }
impl Cells implements core::ops::Index<usize> {
    type Output = i32
    fn index(i: read usize): read i32 from self { unsafe { read *self.p.add(i) } }
}
impl Cells implements core::ops::IndexMut<usize> {
    type Output = i32
    mut fn index_mut(i: read usize): mut i32 from self { unsafe { mut *self.p.add(i) } }
}
type Holder<K, V> { cells: Cells; k: K; v: V }
impl<K, V> Holder<K, V> {
    mut fn store(i: usize, k: take K, v: take V, x: i32): Unit {
        self.cells[i] = x
        self.k = k
        self.v = v
    }
}
fn set(c: mut Cells, i: usize, x: i32): Unit { c[i] = x }
fn main() {
    var a = [0, 0, 0]
    var c = Cells(core::ptr::from_mut(a).cast::<i32>())
    set(c, 1usize, 5)
    var h = Holder(c, 1, 2)
    h.store(2usize, 3, 4, 9)
    if a[1] != 5 || a[2] != 9 || h.k != 3 || h.v != 4 { return 1 }
    0
}
""",
    "owners-optional-view-results-name-their-source": """
type Table<K, V> { vs: ptr<mut V>; n: usize; k: Option2<K> }
type Option2<K> { k: K }
impl<K, V> Table<K, V> {
    fn get(k: read K, i: usize): (read V from self)? {
        if i < self.n { present(unsafe { read *self.vs.add(i) }) } else { none }
    }
    mut fn get_mut(k: read K, i: usize): (mut V from self)? {
        if i < self.n { present(unsafe { mut *self.vs.add(i) }) } else { none }
    }
    fn pair(k: read K): ((read V from self), usize) { (unsafe { read *self.vs }, 1usize) }
}
fn main() {
    var a = [10, 20]
    var t = Table(core::ptr::from_mut(a).cast::<i32>(), 2usize, Option2(1u8))
    match t.get(1u8, 1usize) { present(v) => { if *v != 20 { return 1 } }, none => { return 2 } }
    match t.get(1u8, 2usize) { present(v) => { return 3 }, none => {} }
    match t.get_mut(1u8, 0usize) { present(v) => { if *v != 10 { return 4 } }, none => { return 5 } }
    match t.pair(1u8) { (v, n) => { if *v != 10 || n != 1usize { return 6 } } }
    0
}
""",
    "owners-mem-replace-swap-size-of-val-and-abort": """
type P { a: i32; b: i64 }
type H<T> { v: T }
fn exchange(dest: mut i32, v: i32): i32 { core::mem::replace(dest, v) }
fn keep(slot: mut H<read i32>, v: take H<read i32>): H<read i32> from (slot, v) {
    core::mem::replace(slot, v)
}
fn die(): Never { core::intrinsics::abort() }
fn main() {
    var x = 5
    var y = 7
    let old = core::mem::replace(x, 9)
    core::mem::swap(x, y)
    var p = P(1, 2)
    var q = P(3, 4)
    core::mem::swap(p, q)
    let old2 = core::mem::replace(p, P(10, 20))
    var z = 1
    let r = exchange(z, 2)
    let words = [1u32, 2u32, 3u32]
    let a = 1
    let b = 2
    var first = H(read a)
    let second = H(read b)
    let previous = keep(first, second)
    if old != 5 { return 1 }
    if x != 7 || y != 9 { return 2 }
    if p.a != 10 || q.a != 1 || old2.a != 3 { return 3 }
    if z != 2 || r != 1 { return 4 }
    if core::mem::size_of_val(words) != 12usize { return 5 }
    if core::mem::align_of_val(p) != 8usize { return 6 }
    if *previous.v != 1 || *first.v != 2 { return 7 }
    if x == 0 { die() }
    0
}
""",
    "copy-through-view-copies": r"""
type Bag { n: i32 }
impl Bag {
    mut fn add(item: take i32) { self.n += item }
}
fn gen<T>(x: take T): T { x }
fn first(v: read [i32; 3]): read i32 from v { read v[0] }
fn main(): i32 {
    let arr = [1, 2, 3]
    let r = first(read arr)
    var b = Bag(0)
    b.add(*r)
    let g = gen(*r)
    b.n + g - 2
}
""",
    "generic-statics-and-inferred-turbofish": r"""
type Vec<T> { len: usize
  static fn empty(): Vec<T> { Self(0usize) }
  fn n(): usize { self.len } }
impl<T> Vec<T> {
    static fn new(): Vec<T> { Vec(0usize) }
    static fn two(): Vec<T> { Self(2usize) }
    static fn viaself(): Vec<T> { Self::new() }
    fn bump(): usize { self.n() + 1usize }
}
fn main(): i32 {
    let a: Vec<i32> = Vec::new()
    let b = Vec::<i32>::new()
    let c: Vec<i32> = Vec::two()
    let e: Vec<u8> = Vec::viaself()
    let f = Vec::<i32>::two()
    if a.n() == 0usize && b.n() == 0usize && c.n() == 2usize && f.bump() == 3usize && e.n() == 0usize { 0 } else { 1 }
}
""",
    "generic-inference-from-expected-type": r"""
type Vec<T> { a: T; n: usize }
enum Opt<T> { Some(T), Nothing }
fn nothing<T>(): Opt<T> { Opt::Nothing }
type Slot<K> { v: K? }
impl<K> Slot<K> {
    static fn empty(): Slot<K> { Slot(none) }
}
fn main(): i32 {
    let s: Opt<i32> = nothing()
    let t: Opt<i32> = Opt::<i32>::Nothing
    let e: Slot<i32> = Slot::empty()
    match s { Opt::Nothing => 0, Opt::Some(_) => 1 }
}
""",
    "projection-callable-and-closure-inference": r"""
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self::Item?; } } }
import core::iter::Iterator;
type Counter { n: i32; max: i32 }
impl Counter implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
type Box<T> { v: T }
type Map<I, F> { iter: I; f: F }
impl<B, I: Iterator, F: fn(<I implements Iterator>::Item): B> Map<I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match self.iter.next() { present(x) => present(self.f(x)), none => none }
    }
}
fn map<B, I: Iterator, F: fn(<I implements Iterator>::Item): B>(it: take I, f: take F): Map<I, F> { Map(it, f) }
type Take<I> { iter: I; n: usize }
impl<T, I: Iterator<Item = T>> Take<I> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.n == 0usize { return none }
        self.n -= 1usize
        self.iter.next()
    }
}
fn wrap<I: Iterator>(it: take I, w: take Box<<I implements Iterator>::Item>): Box<<I implements Iterator>::Item> { w }
fn apply<B, F: fn(i32): B>(f: take F): B { f(1) }
fn apply_ptr<B>(f: fn(i32): B, x: i32): B { f(x) }
fn plus(x: i32): i32 { x + 1 }
fn main(): i32 {
    let w = wrap(Counter(0, 1), Box(5))
    var m = map(Take(Counter(0, 10), 4usize), fn(x: i32): i32 { x * 10 })
    var total = 0
    for x in mut m { total += x }
    let a = apply(fn(x: i32): i32 { x + 1 })
    let b = apply_ptr(plus, 1)
    let c = apply(fn(x: i32) { x * 3 })
    if w.v == 5 && total == 60 && a == 2 && b == 2 && c == 3 { 0 } else { 1 }
}
""",
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
VEC_ITER_PREFIX = """
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self::Item?; }
  pub interface Iterable { type Item; type Iter<region r>; fn iter<region r>(receiver self: read Self from r): Self::Iter<region r>; }
  pub interface IterableMut { type Item; type IterMut<region r>; fn iter_mut<region r>(receiver self: mut Self from r): Self::IterMut<region r>; }
} }
extern "C" {
    unsafe fn realloc(p: ptr<mut u8>, n: usize): ptr<mut u8>;
    unsafe fn free(p: ptr<mut u8>): Unit;
}
import core::iter::{Iterator, Iterable, IterableMut};
type Vec<T> { ptr: ptr<mut T>; len: usize; cap: usize
    drop { unsafe {
        var i = 0usize
        while i < self.len { core::ptr::drop_in_place(self.ptr.add(i)); i += 1usize }
        if self.cap != 0usize { free(self.ptr.cast::<u8>()) }
    } }
}
impl<T> Vec<T> {
    mut fn push(v: take T): Unit {
        if self.len == self.cap {
            let nc = if self.cap == 0usize { 4usize } else { self.cap * 2usize }
            let np = unsafe { realloc(self.ptr.cast::<u8>(), nc * core::mem::size_of::<T>()) }
            self.ptr = np.cast::<T>()
            self.cap = nc
        }
        unsafe { core::ptr::write(self.ptr.add(self.len), v) }
        self.len += 1usize
    }
}
fn new_vec<T>(): Vec<T> { Vec(core::ptr::null_mut::<T>(), 0usize, 0usize) }
type VecIter<T, region r> { v: read Vec<T> from r; i: usize }
impl<T, region r> VecIter<T, region r> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.i < self.v.len {
            let x = unsafe { read *self.v.ptr.add(self.i) }
            self.i += 1usize
            present(x)
        } else { none }
    }
}
impl<T> Vec<T> implements Iterable {
    type Item = T
    type Iter<region r> = VecIter<T, region r>
    fn iter<region r>(receiver self: read Self from r): VecIter<T, region r> { VecIter(read self, 0usize) }
}

type VecIterMut<T, region r> { v: mut Vec<T> from r; i: usize }
impl<T, region r> VecIterMut<T, region r> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.i < self.v.len {
            let x = unsafe { mut *self.v.ptr.add(self.i) }
            self.i += 1usize
            present(x)
        } else { none }
    }
}
impl<T> Vec<T> implements IterableMut {
    type Item = T
    type IterMut<region r> = VecIterMut<T, region r>
    fn iter_mut<region r>(receiver self: mut Self from r): VecIterMut<T, region r> { VecIterMut(mut self, 0usize) }
}
"""
VEC_ITER_LINES = 65
VEC_ITER_BOUNDED_PREFIX = VEC_ITER_PREFIX.replace(
    "type Iter<region r>;", "type Iter<region r>: Iterator<Item = read Self::Item from r>;"
).replace(
    "type IterMut<region r>;", "type IterMut<region r>: Iterator<Item = mut Self::Item from r>;")
MACHINE_POSITIVE.update({
    "local-iterator-result-returned-from-collection": VEC_ITER_PREFIX + """
fn first<T>(c: read Vec<T>): (read T from c)? {
    var it = c.iter()
    it.next()
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(4)
    match first(read v) { present(x) => *x - 4, none => 1 }
}
""",
    "stored-exclusive-view-read-result-used-before-mutation": VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    let b = cur.peek()
    let sum = *a + *b
    cur.v.push(2)
    cur.grow(3)
    sum - 2
}
""",
    "stored-exclusive-view-read-result-per-loop-iteration": VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    var sum = 0
    var i = 0
    while i < 3 { let a = cur.peek(); sum += *a; cur.grow(i + 0); i += 1 }
    sum - 3
}
""",
    "stored-shared-view-read-results-coexist-with-reads": VEC_ITER_PREFIX + """type Cursor<region r> { v: read Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    let cur = Cursor(read v)
    let a = cur.peek()
    let b = cur.peek()
    *a + *b - 2 + (cur.v.len as i32) - 1
}
""",
    "shared-reborrows-of-stored-exclusive-view-coexist": VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
fn main(): i32 {
    var v = new_vec::<i32>()
    var cur = Cursor(mut v)
    let x = read cur.v
    let y = read cur.v
    (x.len + y.len) as i32
}
""",
    "nested-cursor-read-result-used-before-mutation": VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
type Wrap<region q, region r> { c: mut Cursor<region r> from q }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var c = Cursor(mut v)
    var w = Wrap(mut c)
    let a = w.c.peek()
    let x = *a
    w.c.v.push(2)
    x - 1
}
""",
    "generic-iteration-through-family-bounded-protocols": VEC_ITER_BOUNDED_PREFIX + """
fn sum<C: Iterable<Item = i32>>(c: read C): i32 { var s = 0; for x in c { s += *x }; s }
fn bump<C: IterableMut<Item = i32>>(c: mut C): Unit { for x in mut c { *x += 1 } }
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    v.push(2)
    bump(mut v)
    sum(v) - 5
}
""",
    "index-implementation-with-explicit-regions": """
module core { pub module ops {
 pub interface Index<I> { type Output; fn index(i: read I): read Self::Output from self; }
} }
type Arr { a: i32; b: i32 }
impl Arr implements core::ops::Index<usize> {
    type Output = i32
    fn index<region r>(receiver self: read Self from r, i: read usize): read i32 from r {
        if i == 0usize { read self.a } else { read self.b }
    }
}
fn main(): i32 { let x = Arr(1, 2); if x[1usize] == 2 { 0 } else { 1 } }
""",
    "generic-impl-matches-generic-enum-field": """
enum Slot<K, V> { Empty, Full(K, V) }
type M<K, V> { slots: Slot<K, V> }
impl<K, V> M<K, V> {
    fn full(): i32 { match self.slots { Slot::Full(_, v) => 1, _ => 0 } }
}
fn main(): i32 { 0 }
""",
})


BAG_ITER_MUT = """
type Bag { a: i32; b: i32 }
type Cursor<region r> { bag: mut Bag from r; at: i32 }
impl<region r> Cursor<region r> {
    mut fn next(): (mut i32 from r)? {
        let i = self.at
        self.at += 1
        if i == 0 { present(mut self.bag.a) } else if i == 1 { present(mut self.bag.b) } else { none }
    }
}
"""
BAG_ITER_MUT_LINES = BAG_ITER_MUT.count("\n")

MACHINE_NEGATIVE = {
    "transferable-rejects-raw-pointer-structures": (
        'type Plain { a: i32; b: bool }\ntype Raw { p: ptr<mut u8> }\ntype Cellular { c: core::cell::Cell<i32> }\ntype Blocked { a: i32 }\nimpl Blocked not Transferable;\nfn send<T: Transferable>(value: take T): Unit {}\nfn share<T: Shareable>(value: read T): Unit {}\nfn owned<T: Transferable + Static>(value: take T): Unit {}\nfn main(): i32 {\n  send(Raw(core::ptr::null_mut::<u8>()))\n  0\n}\n',
        "type", "unsatisfied interface bound 'Transferable'", (10, 3)),
    "shareable-rejects-cells": (
        'type Plain { a: i32; b: bool }\ntype Raw { p: ptr<mut u8> }\ntype Cellular { c: core::cell::Cell<i32> }\ntype Blocked { a: i32 }\nimpl Blocked not Transferable;\nfn send<T: Transferable>(value: take T): Unit {}\nfn share<T: Shareable>(value: read T): Unit {}\nfn owned<T: Transferable + Static>(value: take T): Unit {}\nfn main(): i32 {\n  share(Cellular(core::cell::Cell::new(1)))\n  0\n}\n',
        "type", "unsatisfied interface bound 'Shareable'", (10, 3)),
    "transferable-honours-negative-implementations": (
        'type Plain { a: i32; b: bool }\ntype Raw { p: ptr<mut u8> }\ntype Cellular { c: core::cell::Cell<i32> }\ntype Blocked { a: i32 }\nimpl Blocked not Transferable;\nfn send<T: Transferable>(value: take T): Unit {}\nfn share<T: Shareable>(value: read T): Unit {}\nfn owned<T: Transferable + Static>(value: take T): Unit {}\nfn main(): i32 {\n  send(Blocked(1))\n  0\n}\n',
        "type", "unsatisfied interface bound 'Transferable'", (10, 3)),
    "static-rejects-closures-borrowing-locals": (
        'type Plain { a: i32; b: bool }\ntype Raw { p: ptr<mut u8> }\ntype Cellular { c: core::cell::Cell<i32> }\ntype Blocked { a: i32 }\nimpl Blocked not Transferable;\nfn send<T: Transferable>(value: take T): Unit {}\nfn share<T: Shareable>(value: read T): Unit {}\nfn owned<T: Transferable + Static>(value: take T): Unit {}\nfn main(): i32 {\n  let k = 4; let f = fn(): i32 { k }; owned(f)\n  0\n}\n',
        "type", "unsatisfied interface bound 'Static'", (10, 39)),
    "static-rejects-views-of-locals": (
        'type Plain { a: i32; b: bool }\ntype Raw { p: ptr<mut u8> }\ntype Cellular { c: core::cell::Cell<i32> }\ntype Blocked { a: i32 }\nimpl Blocked not Transferable;\nfn send<T: Transferable>(value: take T): Unit {}\nfn share<T: Shareable>(value: read T): Unit {}\nfn owned<T: Transferable + Static>(value: take T): Unit {}\nfn main(): i32 {\n  let k = 4; owned(read k)\n  0\n}\n',
        "type", "unsatisfied interface bound 'Static'", (10, 14)),
    "transferable-generic-without-bound-is-rejected": (
        "fn send<T: Transferable>(value: take T): Unit {}\nfn forward<T>(value: take T): Unit { send(value) }\nfn main(): i32 { 0 }\n",
        "type", "unsatisfied interface bound 'Transferable'", (2, 38)),
    "manual-transferable-requires-unsafe": (
        "type Raw { p: ptr<mut u8> }\nimpl Raw implements Transferable {}\nfn main(): i32 { 0 }\n",
        "unsafe", "manual Transferable implementation requires unsafe impl", (2, 1)),
    "exclusive-iterator-items-cannot-both-be-live": (
        BAG_ITER_MUT + """
fn bad(c: mut Bag): Unit {
    var it = Cursor(mut c, 0)
    let x = it.next()
    let y = it.next()
    match take x { present(p) => { *p += 1 }, none => {} }
}
fn main(): i32 { 0 }
""",
        "ownership", "live exclusive loan", (BAG_ITER_MUT_LINES + 5, 13)),
    "exclusive-iterator-item-blocks-source-write": (
        BAG_ITER_MUT + """
fn bad(c: mut Bag): Unit {
    var it = Cursor(mut c, 0)
    let x = it.next()
    c.a = 5
    match take x { present(p) => { *p += 1 }, none => {} }
}
fn main(): i32 { 0 }
""",
        "ownership", "live exclusive loan", (BAG_ITER_MUT_LINES + 5, 5)),
    "exclusive-iterator-item-cannot-borrow-local-source": (
        BAG_ITER_MUT + """
fn bad(c: mut Bag): (mut i32 from c)? {
    var own = Bag(1, 2)
    var it = Cursor(mut own, 0)
    it.next()
}
fn main(): i32 { 0 }
""",
        "ownership", "returned view escapes local storage", (BAG_ITER_MUT_LINES + 5, 5)),
    "exclusive-iterator-held-item-blocks-next": (
        BAG_ITER_MUT + """
fn bad(c: mut Bag): Unit {
    var it = Cursor(mut c, 0)
    var held: (mut i32 from c)? = it.next()
    let y = it.next()
    match take held { present(p) => { *p += 1 }, none => {} }
}
fn main(): i32 { 0 }
""",
        "ownership", "live exclusive loan", (BAG_ITER_MUT_LINES + 5, 13)),
    "take-argument-indexed-from-borrowed-copy-element-suggests-copy": (
        "fn sink(value: take u8): u8 { value }\nfn pick(digits: read [u8], i: usize): u8 { sink(digits[i]) }\nfn main(): i32 { 0 }\n",
        "ownership", "consumes its value, so copy it into a binding first", (2, 49)),
    "local-iterator-result-keeps-collection-borrowed": (
        VEC_ITER_PREFIX + """
fn first<T>(c: read Vec<T>): (read T from c)? {
    var it = c.iter()
    it.next()
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    let f = first(read v)
    v.push(2)
    match f { present(x) => *x, none => 0 }
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 9, 5)),
    "local-iterator-result-cannot-borrow-local-collection": (
        VEC_ITER_PREFIX + """
fn bad(c: read Vec<i32>): (read i32 from c)? {
    var own = new_vec::<i32>()
    own.push(1)
    var it = own.iter()
    it.next()
}
fn main(): i32 { 0 }
""",
        "ownership", "returned view escapes local storage", (VEC_ITER_LINES + 5, 5)),
    "exclusive-view-result-keeps-its-cursor-borrowed": (
        VEC_ITER_PREFIX + """
type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    mut fn pick(): mut i32 from r { unsafe { mut *self.v.ptr } }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.pick()
    let b = cur.pick()
    *a = 1
    *b = 2
    0
}
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 10, 13)),
    "stored-exclusive-view-read-result-blocks-push-through-cursor": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    cur.v.push(2)
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 10, 5)),
    "stored-exclusive-view-read-result-blocks-field-write-through-cursor": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    cur.v.len = 0usize
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 10, 5)),
    "stored-exclusive-view-read-result-blocks-mutating-method": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    cur.grow(2)
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 10, 5)),
    "stored-exclusive-view-read-result-blocks-reborrow-of-stored-view": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    let w = mut cur.v
    w.push(2)
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 11, 5)),
    "stored-exclusive-view-read-result-blocks-owner-mutation": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    v.push(2)
    *a
}
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 10, 5)),
    "stored-exclusive-view-read-result-survives-moving-the-cursor": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    var moved = take cur
    moved.v.push(2)
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 11, 5)),
    "stored-exclusive-view-read-result-through-optional-wrapper": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn maybe(): (read i32 from r)? { unsafe { present(read *self.v.ptr) } }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.maybe()
    cur.v.push(2)
    match a { present(x) => *x, none => 0 }
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 9, 5)),
    "stored-exclusive-view-read-result-through-raw-pointer-local": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { let p = self.v.ptr
        unsafe { read *p } }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    cur.v.push(2)
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 10, 5)),
    "stored-exclusive-view-read-result-generic-payload": (
        VEC_ITER_PREFIX + """type Cursor<T, region r> { v: mut T from r }
impl<T, region r> Cursor<T, region r> {
    fn peek(): read T from r { let p = core::ptr::from_ref(read *self.v)
        unsafe { read *p } }
}
fn main(): i32 {
    var n = 1
    var cur = Cursor(mut n)
    let a = cur.peek()
    *cur.v = 7
    *a
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 9, 5)),
    "stored-exclusive-view-read-result-through-callee-with-cursor-parameter": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
fn grab<region r>(c: mut Cursor<region r>): read i32 from r { c.peek() }
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = grab(mut cur)
    cur.v.push(2)
    *a
}
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 11, 5)),
    "stored-exclusive-view-exclusive-result-blocks-push-through-cursor": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
impl<region r> Cursor<region r> {
    mut fn pick(): mut i32 from r { unsafe { mut *self.v.ptr } }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.pick()
    cur.v.push(2)
    *a = 1
    0
}
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 9, 5)),
    "reborrowed-stored-exclusive-view-blocks-use-of-the-stored-view": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
fn main(): i32 {
    var v = new_vec::<i32>()
    var cur = Cursor(mut v)
    let w = mut cur.v
    cur.v.push(1)
    w.push(2)
    0
}
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 5, 5)),
    "shared-reborrow-of-stored-exclusive-view-blocks-writes-through-the-stored-view": (
        VEC_ITER_PREFIX + """type Cursor<region r> { v: mut Vec<i32> from r }
fn main(): i32 {
    var v = new_vec::<i32>()
    var cur = Cursor(mut v)
    let r = read cur.v
    cur.v.push(1)
    r.len as i32
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 5, 5)),
    "erased-call-still-retains-views-stored-from-other-arguments": (
        """
type Hold<region r> { x: read i32 from r }
interface Put { fn put<region r>(h: mut Hold<region r>, v: read i32 from r): Unit; }
type A {}
impl A implements Put { fn put<region r>(h: mut Hold<region r>, v: read i32 from r): Unit { h.x = read v } }
fn run<P: Put>(p: read P): i32 {
    var a = 1
    var h = Hold(read a)
    var b = 2
    p.put(mut h, read b)
    b = 3
    *h.x
}
fn main(): i32 { run(read A()) }
""",
        "ownership", "live read loan", (11, 5)),
    "const-initializer-must-be-constant": (
        "fn f(): i32 { 3 }\nconst X: i32 = f();\nfn main(): i32 { X }",
        "constant", "validated constant expression", (2, 16)),
    "const-initializer-cycle": (
        "const A: i32 = B;\nconst B: i32 = A;\nfn main(): i32 { A }",
        "constant", "cycle in required static initialization", (1, 1)),
    "const-initializer-type-mismatch": (
        "const A: i32 = true;\nfn main(): i32 { A }",
        "constant", "validated constant expression", (1, 16)),
    "const-initializer-overflow": (
        "const A: i8 = 100 + 100;\nfn main(): i32 { 0 }",
        "constant", "overflows", (1, 15)),
    "const-cannot-be-assigned": (
        "const A: i32 = 1;\nfn main(): i32 { A = 2; 0 }",
        "type", "cannot assign immutable binding", (2, 18)),
    "const-requires-initializer": (
        "const A: i32;\nfn main(): i32 { 0 }",
        "parse", "expected '='", (1, 13)),
    "const-pattern-requires-scalar": (
        "const A: (i32, i32) = (1, 2);\nfn main(): i32 { match (1, 2) { A => 0 } }",
        "type", "only integer and bool constants", (2, 33)),
    "overlapping-blanket-and-concrete-implementation-is-rejected": (
        'module core {\n    pub module iter {\n        pub interface Iterator { type Item; mut fn next(): Self::Item?; }\n        pub interface IntoIterator: Sized { type Item; type IntoIter: Iterator; fn into_iter(receiver self: take Self): Self::IntoIter; }\n        impl<I: Iterator> I implements IntoIterator {\n            type Item = I::Item\n            type IntoIter = I\n            fn into_iter(receiver self: take Self): I { self }\n        }\n    }\n}\ntype Counter { n: i32; max: i32 }\nimpl Counter implements core::iter::Iterator {\n    type Item = i32\n    mut fn next(): i32? {\n        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }\n    }\n}\ntype Bag { max: i32 }\nimpl Bag implements core::iter::IntoIterator {\n    type Item = i32\n    type IntoIter = Counter\n    fn into_iter(receiver self: take Self): Counter { Counter(0, self.max) }\n}\nimpl Counter implements core::iter::IntoIterator {\n    type Item = i32\n    type IntoIter = Counter\n    fn into_iter(receiver self: take Self): Counter { self }\n}\nfn main(): i32 { 0 }\n',
        "type", "overlapping implementations cannot be selected by order", (25, 1)),
    "interface-method-without-body-called-through-interface-name": (
        "interface Plain { fn plain(): i32; }\nimpl i32 implements Plain { fn plain(): i32 { self } }\nfn main(): i32 {\n    let x: i32 = 5\n    Plain::plain(x) - 5\n}\n",
        "type", "cannot be called through the interface name", (5, 5)),
    "iteration-body-cannot-grow-the-iterated-collection": (
        VEC_ITER_PREFIX + """
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    for x in v { v.push(*x) }
    0
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 4, 18)),
    "iterator-item-cannot-outlive-collection-mutation": (
        VEC_ITER_PREFIX + """
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    var it = v.iter()
    let first = it.next()
    v.push(2)
    match first { present(x) => *x, none => 0 }
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 6, 5)),
    "mutable-iteration-cannot-nest-inside-read-iteration": (
        VEC_ITER_PREFIX + """
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    for x in v { for y in mut v { *y += *x } }
    0
}
""",
        "ownership", "live read loan", (VEC_ITER_LINES + 4, 18)),
    "read-iteration-item-is-not-writable": (
        VEC_ITER_PREFIX + """
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1)
    for x in v { *x = 5 }
    0
}
""",
        "ownership", "cannot write through a read parameter", (VEC_ITER_LINES + 4, 18)),
    "iterator-item-of-local-collection-cannot-escape": (
        VEC_ITER_PREFIX + """
fn leak(): (read i32 from static)? {
    var v = new_vec::<i32>()
    v.push(1)
    var it = v.iter()
    it.next()
}
fn main(): i32 { 0 }
""",
        "region", "view region or invariant payload", (VEC_ITER_LINES + 1, 36)),
    "matched-view-of-local-collection-cannot-escape": (
        VEC_ITER_PREFIX + """
fn bad(): (read i32 from static)? {
    let v = new_vec::<i32>()
    match v.iter().next() { present(x) => present(x), none => none }
}
fn main(): i32 { 0 }
""",
        "region", "view region or invariant payload", (VEC_ITER_LINES + 1, 35)),
    "generic-iteration-body-cannot-nest-mutable-iteration": (
        VEC_ITER_BOUNDED_PREFIX + """
fn nest<C: IterableMut<Item = i32>>(c: mut C): Unit { for x in mut c { for y in mut c { *y += *x } } }
fn main(): i32 { var v = new_vec::<i32>(); nest(mut v); 0 }
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 1, 72)),
    "generic-iterator-item-cannot-outlive-collection-mutation": (
        VEC_ITER_BOUNDED_PREFIX + """
fn stale<C: IterableMut<Item = i32>>(c: mut C): i32 {
    var it = c.iter_mut()
    let a = it.next()
    let b = c.iter_mut()
    match a { present(x) => *x, none => 0 }
}
fn main(): i32 { var v = new_vec::<i32>(); stale(mut v) }
""",
        "ownership", "live exclusive loan", (VEC_ITER_LINES + 4, 13)),
    "generic-read-iteration-item-is-not-writable": (
        VEC_ITER_BOUNDED_PREFIX + """
fn poke<C: Iterable<Item = i32>>(c: read C): Unit { for x in c { *x = 5 } }
fn main(): i32 { 0 }
""",
        "ownership", "cannot write through a read parameter", (VEC_ITER_LINES + 1, 66)),
    "generic-iterator-item-cannot-escape-the-collection": (
        VEC_ITER_BOUNDED_PREFIX + """
fn leak<C: Iterable<Item = i32>>(c: read C): (read i32 from static)? { var it = c.iter(); it.next() }
fn main(): i32 { 0 }
""",
        "region", "view region or invariant payload", (VEC_ITER_LINES + 1, 70)),
    "family-bound-rejects-implementation-with-wrong-item": (
        VEC_ITER_BOUNDED_PREFIX + """
type Bad { n: i32 }
impl Bad implements core::iter::Iterator { type Item = i32; mut fn next(): i32? { none } }
type Box { n: i32 }
impl Box implements core::iter::Iterable {
    type Item = i32
    type Iter<region r> = Bad
    fn iter<region r>(receiver self: read Self from r): Bad { Bad(0) }
}
fn main(): i32 { 0 }
""",
        "type", "associated item does not satisfy its interface bounds", (VEC_ITER_LINES + 4, 1)),
    "generic-impl-field-match-checks-substituted-payload": (
        """
enum Slot<K, V> { Empty, Full(K, V) }
type M<K, V> { slots: Slot<K, V> }
impl<K, V> M<K, V> {
    fn bad(): i32 { match self.slots { Slot::Full(_, v) => v, _ => 0 } }
}
fn main(): i32 { 0 }
""",
        "type", "expected i32, found V", (5, 40)),
    "index-implementation-region-must-derive-from-self": (
        """
module core { pub module ops {
 pub interface Index<I> { type Output; fn index(i: read I): read Self::Output from self; }
} }
type Arr { a: i32; b: i32 }
impl Arr implements core::ops::Index<usize> {
    type Output = i32
    fn index<region r>(i: read usize): read i32 from r { read self.a }
}
fn main(): i32 { 0 }
""",
        "region", "view region or invariant payload does not satisfy", (8, 56)),
    "byte-text-rejects-unicode-escape": (
        'fn main(): i32 { let a = b"\\u{41}"; 0 }',
        "lex", "invalid text escape", (1, 26), 1),
    "byte-text-rejects-non-ascii": (
        'fn main(): i32 { let a = b"\u00e9"; 0 }',
        "lex", "byte text must contain only ASCII characters", (1, 26), 1),
    "byte-text-bad-hex-escape": (
        'fn main(): i32 { let a = b"\\xzz"; 0 }',
        "lex", "byte escape requires two hexadecimal digits", (1, 26), 1),
    "raw-byte-text-unterminated-fence": (
        'fn main(): i32 { let a = br#"abc"; 0 }',
        "lex", "unterminated raw text literal", (1, 26), 1),
    "range-index-on-scalar": (
        "fn main(): i32 { let x = 5; let y = read x[1..2]; 0 }",
        "type", "range indexing requires an array, slice or a type", (1, 42), 1),
    "range-index-on-product-without-protocol": (
        "type T { x: i32 }\nfn main(): i32 { let a = T(1); let y = read a[1..2]; 0 }",
        "type", "range indexing requires an array, slice or a type", (2, 45), 1),
    "range-index-bound-must-be-usize": (
        "fn main(): i32 { let a = [1, 2, 3]; let y = read a[1i32..2]; 0 }",
        "type", "expected usize, found i32", (1, 52), 1),
    "range-index-mut-requires-mutable-place": (
        "fn main(): i32 { let a = [1, 2, 3]; let y = mut a[1..2]; 0 }",
        "ownership", "exclusive borrow requires a mutable place", (1, 49)),
    "range-index-unsized-subslice-needs-borrow": (
        "fn main(): i32 { let a = [1, 2, 3]; let y = a[1..2]; 0 }",
        "type", "unsized value requires a view", (1, 37)),
    "range-index-inclusive-needs-upper-bound": (
        "fn main(): i32 { let a = [1, 2, 3]; let y = read a[1..=]; 0 }",
        "parse", "an inclusive range requires an upper bound", (1, 56)),
    "range-index-ranges-do-not-chain": (
        "fn main(): i32 { let a = [1, 2, 3]; let y = read a[3..1..2]; 0 }",
        "parse", "ranges do not chain", (1, 56)),
    "open-ended-range-value-is-not-implemented": (
        "fn main(): i32 { let r = 1..; 0 }",
        "feature", "open-ended range values are not implemented yet", (1, 26)),
    "owners-exclusive-region-mismatch-reported-at-the-violation-only": ("""
type Holder<T> { item: T? }
impl<T> Holder<T> {
    mut fn put(value: take T) { self.item = present(value) }
}
fn fill<region a>(h: mut Holder<read i32 from a>) {
    let loc = 5
    h.put(read loc)
}
fn main() { var x = 1; var h = Holder(item: present(read x)); fill(mut h); 0 }
""", "region", 'invariant payload does not satisfy', (8, 5)),
    "owners-generic-holder-view-cannot-outlive-inner-scope": ("""
type Holder<T> { item: T? }
impl<T> Holder<T> {
    mut fn put(value: take T) { self.item = present(value) }
}
fn fill<region a>(h: mut Holder<read i32 from a>, v: read i32 from a) { h.put(read v) }
fn main(): i32 {
    var x = 1
    var h = Holder(item: present(read x))
    {
        let y = 2
        fill(mut h, read y)
    }
    match h.item { present(v) => *v, none => 0 }
}
""", "ownership", 'live read loan', (13, 5)),
    "owners-raw-pointer-store-of-view-cannot-escape-into-receiver": ("""
type V<T> { p: ptr<mut T>; n: usize }
impl<T> V<T> {
    mut fn push(value: take T) { unsafe { core::ptr::write(self.p.add(self.n), value) }; self.n = self.n + 1usize }
}
fn leak(v: mut V<read i32>) {
    let y = 2
    v.push(read y)
}
fn main() { 0 }
""", "ownership", 'cannot store a view of local storage into caller-owned storage', (8, 5)),
    "owners-mem-replace-cannot-store-local-view-into-caller-storage": ("""
type H<T> { v: T }
fn bad(slot: mut H<read i32>): Unit {
    let x = 5
    let old = core::mem::replace(slot, H(read x))
}
fn main() { 0 }
""", "ownership", 'cannot store a view of local storage into caller-owned storage', (5, 15)),
    "owners-generic-take-view-instantiation-cannot-escape-into-caller-storage": ("""
type H<T> { v: T }
fn put<T>(h: mut H<T>, x: take T): Unit { h.v = x }
fn bad(h: mut H<read i32>): Unit {
    let x = 5
    put(h, read x)
}
fn main() { 0 }
""", "ownership", 'cannot store a view of local storage into caller-owned storage', (6, 5)),
    "owners-interface-by-value-self-requires-sized": ("""
interface Consume { take fn consume(): i32; }
fn main() { 0 }
""", "type", "interface's 'Self' is unsized unless declared 'interface Name: Sized'", (2, 26)),
    "turbofish-excess-generic-arguments": (
        "fn id<T>(x: take T): T { x }\nfn main(): i32 { id::<i32, i32>(1) }",
        "type", "excess explicit generic arguments", (2, 18)),
    "generic-static-inferred-argument-mismatch": (
        "type Vec<T> { len: usize\n  static fn empty(): Vec<T> { Self(0usize) } }\n"
        "fn main(): i32 { let a: Vec<i32> = Vec::empty(); let b: Vec<u8> = a; 0 }",
        "type", "expected Vec<u8>, found Vec<i32>", (3, 50)),
    "generic-unit-variant-context-mismatch": (
        "enum Opt<T> { Some(T), Nothing }\n"
        "fn main(): i32 { let s: Opt<i32> = Opt::Nothing; let t: Opt<u8> = s; 0 }",
        "type", "expected Opt<u8>, found Opt<i32>", (2, 50)),
    "for-exclusive-iterator-loan-conflict": (
        "module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self::Item?; } } }\n"
        "type C { n: i32 }\nimpl C implements core::iter::Iterator { type Item = i32\n"
        " mut fn next(): i32? { none } }\n"
        "fn main(): i32 { var c = C(0); for x in mut c { c.n = 1 }; 0 }",
        "ownership", "live exclusive loan", (5, 49)),
    "machine-target-rejects-strengthened-interface-feature-contract": (
        'interface Ready { fn answer():i32; }\n'
        'copy type Value implements Ready { @target_feature("' +
        ("aes" if ARM64 else "avx2") +
        '") fn answer():i32 { 42 } }\nfn main() { 0 }',
        "type", "contract does not match interface", (2, 59)),
    "machine-target-rejects-implicit-nonbaseline-destructor": (
        'type Value { @target_feature("' + ("aes" if ARM64 else "avx2") +
        '") drop {} }\nfn main() { let value=Value(); 0 }',
        "feature", "implicit destructor dispatch", (1, 37)),
    "machine-asm-naked-rejects-owned-cleanup-root": (
        '@layout(C) type Owned { value:i32; drop {} }\n'
        '@naked unsafe extern "C" fn invalid(value: take Owned) { naked_asm!("ret") }\n'
        'fn main() { 0 }', "attribute", "requiring cleanup", (2, 37)),
    **({
        "machine-target-rejects-out-of-bounds-native-lane": (
            'fn main() { unsafe { let vector=core::arch::aarch64::vdupq_n_s32(42);'
            'core::arch::aarch64::vgetq_lane_s32(vector,4) }; 0 }',
            "type", "lane is outside", (1, 113)),
        "machine-target-rejects-dynamic-native-lane": (
            'fn main() { let lane=1; unsafe { '
            'let vector=core::arch::aarch64::vdupq_n_s32(42);'
            'core::arch::aarch64::vgetq_lane_s32(vector,lane) }; 0 }',
            "type", "constant integer", (1, 125)),
    } if ARM64 else {}),
    **({
        "machine-asm-rejects-unavailable-register-feature": (
            'fn main() { unsafe { asm!("/* {value} */",'
            'value = out(ymm_reg) _,options(nomem)) }; 0 }',
            "assembly", "required feature", (1, 22)),
    } if not ARM64 else {
        "machine-target-core-rejects-hosted-optional-detector": (
            'fn main() { if is_aarch64_feature_detected!("aes") { 0 } else { 1 } }',
            "feature", "unsupported core feature detection", (1, 16)),
    }),
    "machine-asm-rejects-impossible-register-pressure": (
        'fn main() { unsafe { asm!("/* ' +
        ' '.join('{v' + str(i) + '}' for i in range(17 if ARM64 else 5)) +
        ' */",' + ','.join('v' + str(i) + '= in(' +
            ('vreg_low16' if ARM64 else 'reg_abcd') + ') ' + str(i + 1) + 'i64'
            for i in range(17 if ARM64 else 5)) +
        ') }; 0 }', "assembly", "available register inventory", (1, 22)),
    "machine-target-rejects-vector-element-shape-mismatch": (
        'fn main() { unsafe { ' + (
            'let value=core::arch::aarch64::vdupq_n_f32(1.0f32);'
            'core::arch::aarch64::vaddq_s32(value,value)' if ARM64 else
            'let value=core::arch::x86_64::_mm_set1_ps(1.0f32);'
            'core::arch::x86_64::_mm_add_epi32(value,value)') +
        ' }; 0 }', "type", 'expected core::arch::', (1, 104)),
    "machine-asm-rejects-register-class-used-as-clobber-only": (
        'fn main() { unsafe { asm!("nop",out(' + ("preg" if ARM64 else "x87_reg") +
        ') _) }; 0 }', "assembly", "explicit register", (1, 22)),
    "machine-asm-global-rejects-runtime-constant": (
        'global_asm!("/* {value} */",value = const unknown)\nfn main() { 0 }',
        "type", "unsupported operation in required constant", (1, 43), 1),
    "machine-asm-rejects-raw-nul-template": (
        'fn main() { unsafe { asm!("nop\\0",options(raw)) }; 0 }',
        "assembly", "NUL", (1, 22)),
    "machine-asm-naked-rejects-unwind-without-metadata": (
        '@naked unsafe extern "C-unwind" fn invalid() { naked_asm!("ret") }\n'
        'fn main() { 0 }', "feature", "unwind metadata", (1, 1)),
    "machine-asm-naked-rejects-hidden-defaults": (
        '@naked unsafe extern "C" fn invalid(value:i32=42):i32 { naked_asm!("ret") }\n'
        'fn main() { 0 }', "attribute", "defaults", (1, 37)),
    "machine-asm-rejects-uninitialized-input": (
        'fn main() { var value:i32; unsafe { asm!("/* {input} */",'
        'input = in(reg) value) }; 0 }', "type", "uninitialized", (1, 74)),
    "machine-asm-rejects-noreturn-output": (
        'fn main() { var value=0; unsafe { asm!("/* {out} */",'
        'out = out(reg) value, options(noreturn)) } }',
        "assembly", "noreturn", (1, 35)),
    "machine-target-rejects-dispatch-proof-after-join": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") unsafe fn accelerated(): i32 { 42 }\n'
        'fn main() { if ' + ('is_aarch64_feature_detected!("neon")' if ARM64 else
                             'is_x86_feature_detected!("avx2")') +
        ' { }; unsafe { accelerated() }; 0 }', "feature", 'target operation/call requires established target feature availability', (2, 67)),
    "machine-target-rejects-nonbaseline-hosted-entry": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") fn main() { 0 }', "feature", "hosted entry", (1, 24)),
    "machine-asm-rejects-conflicting-options": (
        'fn main() { unsafe { asm!("nop",options(nomem,readonly)) }; 0 }',
        "assembly", "nomem and readonly", (1, 22)),
    "machine-asm-rejects-pure-without-output": (
        'fn main() { unsafe { asm!("nop",options(pure,nomem)) }; 0 }',
        "assembly", "observable output", (1, 22)),
    "machine-asm-requires-unsafe": (
        'fn main() { asm!("nop"); 0 }', "unsafe", 'operation requires an unsafe block or unsafe function', (1, 13)),
    "machine-asm-rejects-reserved-register": (
        'fn main() { unsafe { asm!("nop",out("' + ("x18" if ARM64 else "rsp") +
        '") _) }; 0 }', "assembly", "reserved", (1, 22)),
    "machine-asm-rejects-register-alias-conflict": (
        'fn main() { unsafe { asm!("nop",in("' + ("x0" if ARM64 else "rax") +
        '") 1i64,out("' + ("w0" if ARM64 else "eax") +
        '") _) }; 0 }', "assembly", "conflicting", (1, 22)),
    "machine-asm-rejects-managed-type": (
        'copy type Pair { first: i32; second: i32 }\n'
        'fn main() { let pair = Pair(1,2); unsafe { asm!("/* {value} */",'
        'value = in(reg) pair) }; 0 }', "assembly", "operand type", (2, 44)),
    "machine-asm-rejects-invalid-modifier": (
        'fn main() { unsafe { asm!("/* {value:z} */",value = in(reg) 1) }; 0 }',
        "assembly", "modifier", (1, 22)),
    "machine-asm-rejects-unwind-option": (
        'fn main() { unsafe { asm!("nop",options(may_unwind)) }; 0 }',
        "assembly", "unsupported assembly option", (1, 22)),
    "machine-asm-naked-rejects-ordinary-body": (
        '@naked unsafe extern "C" fn invalid(value: i32): i32 { value }\n'
        'fn main() { 0 }', "attribute", "exactly naked_asm", (1, 26)),
    "machine-target-rejects-unknown-feature": (
        '@target_feature("imaginary") fn invalid() {}\nfn main() { 0 }',
        "feature", "unknown target feature", (1, 17)),
    "machine-target-rejects-unguarded-feature-call": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") unsafe fn accelerated(): i32 { 42 }\n'
        'fn main() { unsafe { accelerated() }; 0 }',
        "feature", "established target feature", (2, 22)),
    "machine-target-rejects-feature-erasure": (
        '@target_feature("' + ("aes" if ARM64 else "avx2") +
        '") unsafe fn accelerated(): i32 { 42 }\n'
        'fn main() { let callback: unsafe fn(): i32 = accelerated; 0 }',
        "type", 'found unsafe fn', (2, 13)),
    "machine-target-rejects-wrong-architecture-operation": (
        'fn main() { unsafe { ' + (
            'core::arch::x86_64::_mm_set1_epi32(42)' if ARM64 else
            'core::arch::aarch64::vdupq_n_s32(42)') + ' }; 0 }', "feature", 'architecture operation is unavailable on this target', (1, 22), 1),
    "machine-target-rejects-known-unimplemented-operation": (
        'fn main() { unsafe { core::arch::' +
        ('aarch64::vaeseq_u8' if ARM64 else 'x86_64::_mm_aesenc_si128') +
        '() }; 0 }', "feature", "unsupported architecture operation", (1, 22)),
}


def stress_program(functions, products, instances, locals_):
    lines = [f"copy type P{i} {{ a: i32; b: i64 }}" for i in range(products)]
    lines.append("copy type Box<T: Copy> { value: T }")
    lines += [f"fn g{i}(x: i32): Box<P{i % products}> {{ return Box(P{i % products}(x, 1)) }}"
              for i in range(instances)]
    lines += [f"fn f{i}(x: i32): i32 {{ return x + {i % 7} }}" for i in range(functions)]
    lines += ["fn many(): i32 {", "    var s = 0"]
    for i in range(locals_):
        lines += [f"    let v{i} = {i}", f"    s = s + v{i} % 3"]
    lines += ["    return s", "}", "fn main(): i32 {", "    var t = many()"]
    lines += [f"    t = t + f{i}(1)" for i in range(0, functions, 50)]
    lines += [f"    t = t + g{i}(1).value.a" for i in range(instances)]
    lines += ["    if t < 0 { return 1 }", "    return 0", "}"]
    return "\n".join(lines) + "\n"


POSITIVE = {
    "closure-over-exclusive-views-releases-after-last-call": """
type Cur<region r> { p: mut i32 from r }
fn main(): i32 {
    var v = 1
    var cur = Cur(mut v)
    var slot = fn(): mut i32 { mut *cur.p }
    let a = slot()
    *a = 5
    let b = slot()
    *b += 1
    v += 1
    if v == 7 { 0 } else { 1 }
}
""",
    "local-iterator-of-exclusive-view-item-returns-as-input-view": BAG_ITER_MUT + """
fn first_mut(c: mut Bag): (mut i32 from c)? {
    var it = Cursor(mut c, 0)
    it.next()
}
fn main(): i32 {
    var bag = Bag(1, 2)
    match take first_mut(mut bag) { present(x) => { *x += 5 }, none => { return 1 } }
    if bag.a == 6 && bag.b == 2 { 0 } else { 2 }
}
""",
    "raw-dereference-view-binds-generic-self-to-payload": r"""
interface Less { fn less(other: read Self): bool; }
impl i32 implements Less { fn less(other: read i32): bool { self < other } }
unsafe fn ordered<T: Less>(p: ptr<mut T>, q: ptr<mut T>): bool {
    unsafe { read *p }.less(unsafe { read *q })
}
fn main(): i32 {
    var a = 1
    var b = 2
    let p = mut a as ptr<mut i32>
    let q = mut b as ptr<mut i32>
    if unsafe { ordered(p, q) } && !unsafe { ordered(q, p) } { 0 } else { 1 }
}
""",
    "integer-and-char-range-matches-are-exhaustive": r"""
fn bucket(x: u8): i32 { match x { 0..=100 => 1, 101..200 => 2, 200..=255 => 3 } }
fn sign(x: i8): i32 { match x { -128..0 => -1, 0 => 0, 1..=127 => 1 } }
fn plane(c: char): i32 { match c { '\u{0}'..='\u{d7ff}' => 1, '\u{e000}'..='\u{10ffff}' => 2 } }
fn main(): i32 {
    if bucket(0u8) != 1 || bucket(150u8) != 2 || bucket(255u8) != 3 { return 1 }
    if sign(-128i8) != -1 || sign(0i8) != 0 || sign(127i8) != 1 { return 2 }
    if plane('a') != 1 || plane('\u{10ffff}') != 2 { return 3 }
    0
}
""",
    "for-user-iterators-by-mode": r"""
module core {
    pub module iter {
        pub interface Iterator { type Item; mut fn next(): Self::Item?; }
        pub interface IntoIterator: Sized { type Item; type IntoIter: Iterator; fn into_iter(receiver self: take Self): Self::IntoIter; }
    }
}
type Counter { n: i32; max: i32 }
impl Counter implements core::iter::Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
type Bag { max: i32 }
impl Bag implements core::iter::IntoIterator {
    type Item = i32
    type IntoIter = Counter
    fn into_iter(receiver self: take Self): Counter { Counter(0, self.max) }
}
fn main(): i32 {
    var total = 0
    for x in Counter(0, 5) { total += x }
    for x in take Bag(4) { total += x }
    var c = Counter(0, 3)
    for x in mut c { total += x * 100 }
    total - 316
}
""",
    "generic-enum-unit-variant-from-context": """
enum Opt<T> { Nothing, Just(T) }
fn nothing<T>(): Opt<T> { Opt::Nothing }
fn main(): i32 {
    let a: Opt<i32> = Opt::Nothing
    let b = Opt::<i32>::Nothing
    let c: Opt<i32> = nothing::<i32>()
    match a { Opt::Nothing => 0, Opt::Just(x) => x }
}
""",
    "limits-stress-thousands-of-declarations-and-locals":
        stress_program(5000, 2000, 500, 3000),
    "limits-more-than-1024-locals-and-parameters": (
        "type Owned { value:i32 }\n"
        "fn many(" + ",".join(f"a{i}:i32" for i in range(1500)) + "): i32 { a1499 }\n"
        "fn main(): i32 {\n" + "".join(f"let a{i}={i};" for i in range(1500)) +
        "\n let items=[Owned(1)]; match take items { [rest @ ..] => 0 } }\n"),
    "array-million-elements-copy-pass-return-loop": """
static TABLE: [u8; 1_000_000] = [5; 1_000_000];
static ZEROS: [i32; 300_000] = [0; 300_000];
fn sum(v: read [u8; 1_000_000]): i32 {
    var total = 0
    for x in read v { total += x as i32 }
    total
}
fn byvalue(v: take [u8; 1_000_000]): i32 {
    var total = 0
    for x in take v { total += x as i32 }
    total
}
fn make(): [u8; 1_000_000] { [3; 1_000_000] }
fn bump(v: mut [u8; 1_000_000]) { for x in mut v { x += 1 } }
fn main(): i32 {
    var a = make()
    var b = a
    b[10] = 9
    if a[10] != 3 { return 1 }
    if b[10] != 9 { return 2 }
    bump(mut a)
    if a[999_999] != 4 { return 3 }
    if sum(a) != 4_000_000 { return 4 }
    var c = b
    if byvalue(c) != 3_000_000 + 6 { return 5 }
    if TABLE[999_999] != 5 || ZEROS[299_999] != 0 { return 6 }
    var i = 0
    while i < 1_000_000 { b[i] = (i % 251) as u8; i += 1 }
    if b[250] != 250 || b[251] != 0 { return 7 }
    var same = true
    i = 0
    while i < 1_000_000 { if a[i] != 4 { same = false }; i += 1 }
    if !same { return 8 }
    0
}
""",
    "array-large-struct-repeat-and-nested": """
copy type Pt { x: i32; y: u8 }
fn main(): i32 {
    var pts = [Pt(7, 8); 100_000]
    pts[99_999].x = 1
    if pts[5].x != 7 || pts[99_999].x != 1 || pts[99_999].y != 8 { return 1 }
    var grid = [[1i32; 1000]; 500]
    grid[499][999] = 5
    var s = 0
    for row in read grid { for v in read row { s += v } }
    if s != 500 * 1000 + 4 { return 2 }
    var k = 0
    var pattern = [0x5Au8; 500_000]
    pattern[1] = 1
    if pattern[0] != 0x5A || pattern[499_999] != 0x5A || pattern[1] != 1 { return 3 }
    0
}
""",
    "array-large-droppable-literal-drops-each-element": """
type G { counter: ptr<mut i32>; drop { unsafe { *self.counter += 1 } } }
fn main(): i32 {
    var count = 0
    let c = core::ptr::from_mut(count)
    {
        let a = [G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c)]
    }
    if count == 100 { 0 } else { 1 }
}
""",
    "limits-array-beyond-65536-elements": """
static TABLE: [u8;70000] = [3;70000];
fn main(): i32 {
    var big = [1u8; 100000]
    big[99999] = 7
    if big[99999] != 7 { return 1 }
    if big[0] != 1 { return 2 }
    if TABLE[69999] != 3 { return 3 }
    0
}
""",
    "review-independent-implementation-budget": (
        "interface Code { fn code():i32; }\n" +
        "".join(f"type T{i} {{}}\nimpl T{i} implements Code {{ fn code():i32 {{ {i} }} }}\n"
                for i in range(92)) +
        "fn main() { T91().code() - 91 }\n"),
    "array-dynamic-index-large-bounded-cfg": """
fn get(v: read [i32;3000], i: i32): i32 { v[i] }
fn put(v: mut [i32;3000], i: i32, x: i32) { v[i] = x }
fn main(): i32 {
    var values = [0; 3000]
    var i = 0
    while i < 3000 { put(mut values, i, i * 2); i = i + 1 }
    var sum = 0
    i = 0
    while i < 3000 { sum = sum + get(values, i) - i; i = i + 1 }
    if sum == 4498500 && get(values, 2999) == 5998 { 0 } else { 1 }
}
""",
    "array-dynamic-index-nested-and-products": """
copy type Cell { left: i32; right: u8 }
fn main(): i32 {
    var grid = [[0u8; 300]; 300]
    var r = 0
    while r < 300 {
        var c = 0
        while c < 300 { grid[r][c] = (r + c) as u8; c = c + 1 }
        r = r + 1
    }
    var cells = [Cell(1, 2u8); 4]
    var k = 3
    cells[k].left = 40
    cells[k - 3].right = 7u8
    if grid[299][299] == 86u8 && grid[10][20] == 30u8 && cells[3].left + cells[0].left == 41 &&
       cells[0].right == 7u8 && cells[3].right == 2u8 { 0 } else { 1 }
}
""",
    "array-dynamic-index-mut-borrow-and-usize": """
fn bump(value: mut i32) { value = value + 1 }
fn main(): i32 {
    var values = [10, 20, 30]
    var index = 2usize
    bump(mut values[index])
    let offset = 1
    bump(mut values[offset])
    if values[2usize] == 31 && values[1] == 21 && values[0] == 10 { 0 } else { 1 }
}
""",
    "review-destructuring-shadows-after-initializer": """
fn main() { let a = 1; let (a,b) = (a - 1,2); a }
""",
    "review-recursive-generic-permutation": """
copy type Pair<A:Copy,B:Copy> { first:A; second:B }
fn recurse<T:Copy,U:Copy>(p:Pair<T,U>,q:Pair<U,T>,n:i32):T {
    if n == 0 { p.first } else {
        let other = recurse::<U,T>(q,p,n-1)
        p.first
    }
}
fn main() { recurse(Pair(0,2u8),Pair(3u8,4),1) }
""",
    "review-symbolic-array-region-outlives": """
fn put<region a,region b,const N:i32>(
    dst:mut [read i32 from b;N],src:take [read i32 from a;N]):Unit where region a:b {
    dst = src
}
fn main() { 0 }
""",
    "review-always-returning-machine-argument": """
fn early():i32 {
    let pointer = core::ptr::from_ref({ return 7; 5i64 })
    0
}
fn main() { early() - 7 }
""",
    "review-generic-array-capture-try-edges": """
fn checked(value:i32):i32 throws i32 {
    if value > 5 { throw value }
    value
}
fn scan<const N:i32>(values:read [i32;N]):i32 {
    let outcome = capture {
        var total = 0
        for value in values { total += try checked(value) }
        total
    }
    match outcome { success(total) => total, failure(value) => value }
}
fn main() {
    let first = [1,2,3]
    let second = [1,7,3]
    if scan(first) == 6 && scan(second) == 7 { 0 } else { 1 }
}
""",
    "review-associated-where-selects-after-self-match": """
interface Bound { type Output; }
interface Code { fn code():i32; }
type Value {}
impl Value implements Bound { type Output = i32; }
type Box<T> { value:T }
impl<T:Bound> Box<T> implements Code where <T implements Bound>::Output = i32 {
    fn code():i32 { 7 }
}
fn main() { Box(Value()).code() - 7 }
""",
    "review-generic-transparent-zero-sized-field": """
@layout(transparent)
copy type Wrapper<T:Copy> { value:T; other:u32 }
fn main() {
    let value = Wrapper((),42u32)
    if value.other == 42u32 && core::mem::size_of::<Wrapper<Unit>>() == 4usize { 0 } else { 1 }
}
""",
    "review-tuple-member-chain": """
fn main():i32 { let value = (1,(2,3)); value.1.0 - 2 }
""",
    "review-match-newlines-inside-call": """
fn identity(value:i32):i32 { value }
fn main():i32 {
    identity(match 1 {
        1 => 0
        _ => 3
    })
}
""",
    "review-quoted-identifiers": """
fn `match`(`type`:i32):i32 { `type` }
fn main():i32 { `match`(0) }
""",
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
    "slice-length-uses-view-metadata": """
fn length<T>(values: read [T]): usize { values.len() }
fn identity(values: read [i32]): read [i32] from values { read values }
fn counted(values: read [i32], count: mut i32): read [i32] from values {
    count += 1
    read values
}
fn main() {
    var values = [20, 22]
    var count = 0
    let empty: [i32; 0] = []
    let zero: read [i32] = read empty
    let slice: mut [i32] = mut values
    let n = counted(slice, count).len()
    slice[0] += 1
    if length::<i32>(slice) == 2usize && identity(slice).len() == 2usize &&
       zero.len() == 0usize && n == 2usize && count == 1 &&
       slice[0] == 21 { 0 } else { 1 }
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
    "borrowing-iteration-over-user-collection": """
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self::Item?; }
  pub interface Iterable { type Item; type Iter<region r>; fn iter<region r>(receiver self: read Self from r): Self::Iter<region r>; }
  pub interface IterableMut { type Item; type IterMut<region r>; fn iter_mut<region r>(receiver self: mut Self from r): Self::IterMut<region r>; }
} }
extern "C" {
    unsafe fn realloc(p: ptr<mut u8>, n: usize): ptr<mut u8>;
    unsafe fn free(p: ptr<mut u8>): Unit;
}
import core::iter::{Iterator, Iterable, IterableMut};
type Vec<T> { ptr: ptr<mut T>; len: usize; cap: usize
    drop { unsafe {
        var i = 0usize
        while i < self.len { core::ptr::drop_in_place(self.ptr.add(i)); i += 1usize }
        if self.cap != 0usize { free(self.ptr.cast::<u8>()) }
    } }
}
impl<T> Vec<T> {
    mut fn push(v: take T): Unit {
        if self.len == self.cap {
            let nc = if self.cap == 0usize { 4usize } else { self.cap * 2usize }
            let np = unsafe { realloc(self.ptr.cast::<u8>(), nc * core::mem::size_of::<T>()) }
            self.ptr = np.cast::<T>()
            self.cap = nc
        }
        unsafe { core::ptr::write(self.ptr.add(self.len), v) }
        self.len += 1usize
    }
}
fn new_vec<T>(): Vec<T> { Vec(core::ptr::null_mut::<T>(), 0usize, 0usize) }
type VecIter<T, region r> { v: read Vec<T> from r; i: usize }
impl<T, region r> VecIter<T, region r> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.i < self.v.len {
            let x = unsafe { read *self.v.ptr.add(self.i) }
            self.i += 1usize
            present(x)
        } else { none }
    }
}
impl<T> Vec<T> implements Iterable {
    type Item = T
    type Iter<region r> = VecIter<T, region r>
    fn iter<region r>(receiver self: read Self from r): VecIter<T, region r> { VecIter(read self, 0usize) }
}

type VecIterMut<T, region r> { v: mut Vec<T> from r; i: usize }
impl<T, region r> VecIterMut<T, region r> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.i < self.v.len {
            let x = unsafe { mut *self.v.ptr.add(self.i) }
            self.i += 1usize
            present(x)
        } else { none }
    }
}
impl<T> Vec<T> implements IterableMut {
    type Item = T
    type IterMut<region r> = VecIterMut<T, region r>
    fn iter_mut<region r>(receiver self: mut Self from r): VecIterMut<T, region r> { VecIterMut(mut self, 0usize) }
}
fn main(): i32 {
    var v = new_vec::<i32>()
    v.push(1); v.push(2); v.push(3)
    var t = 0
    for x in v { t += *x }
    for x in mut v { *x += 10 }
    for x in v { t += *x }
    t - 6 - 36
}
""",
    "region-family-associated-product-iteration": """
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self::Item?; }
  pub interface Iterable { type Iter<region r>; fn iter<region r>(receiver self: read Self from r): Self::Iter<region r>; }
} }
import core::iter::Iterator;
import core::iter::Iterable;
type Bag { a: i32; b: i32 }
type BagIter<region r> { bag: read Bag from r; i: i32 }
impl<region r> BagIter<region r> implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        let i = self.i
        self.i += 1
        if i == 0 { present(self.bag.a) } else if i == 1 { present(self.bag.b) } else { none }
    }
}
impl Bag implements Iterable {
    type Iter<region r> = BagIter<region r>
    fn iter<region r>(receiver self: read Self from r): BagIter<region r> { BagIter(read self, 0) }
}
fn main(): i32 {
    let bag = Bag(3, 4)
    var t = 0
    for x in bag { t += x }
    t - 7
}
""",
    "optional-and-mutable-view-results-reborrow-matched-views": """
enum Slot<K, V> { Empty, Full(K, V) }
fn value_of<K, V>(s: read Slot<K, V>): (read V from s)? {
    match s { Slot::Full(_, v) => present(read v), _ => none }
}
fn value_mut<K, V>(s: mut Slot<K, V>): (mut V from s)? {
    match mut s { Slot::Full(_, v) => present(mut v), _ => none }
}
type Cell { slot: Slot<i32, i32> }
impl Cell {
    fn get<region q>(k: read i32 from q): (read i32 from self)? { value_of(read self.slot) }
}
fn main(): i32 {
    var s = Slot::Full(1, 10)
    match take value_mut(mut s) { present(v) => { *v += 5 }, none => {} }
    let c = Cell(s)
    let k = 1
    match c.get(read k) { present(v) => *v - 15, none => 1 }
}
""",
    "closure-passed-to-generic-function-pointer-parameter": """
fn apply<B>(f: take fn(i32): B): B { f(1) }
fn main(): i32 { apply::<i32>(fn(x: i32): i32 { x + 1 }) - 2 }
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
    "defaulted-bounded-generic-in-signature": """
interface Tag { fn tag(): i32; }
copy type Plain {}
impl Plain implements Tag { fn tag(): i32 { 7 } }
type Holder<A: Tag = Plain> { a: A }
fn peek(h: read Holder): i32 { h.a.tag() }
fn main(): i32 {
    let h = Holder(Plain())
    peek(h) - 7
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
    "closure-result-views-of-captured-exclusive-view-cannot-coexist": ("""
type Cur<region r> { p: mut i32 from r }
fn main(): i32 {
    var v = 1
    var cur = Cur(mut v)
    var f = fn(): mut i32 { mut *cur.p }
    let a = f()
    let b = f()
    *a = 1
    *b = 2
    0
}
""", "ownership", "live exclusive loan", (9, 5)),
    "closure-capturing-exclusive-view-blocks-source-write": ("""
fn main(): i32 {
    var v = 1
    let m = mut v
    var f = fn(): Unit { *m += 1 }
    f()
    v = 3
    f()
    0
}
""", "ownership", "live exclusive loan", (7, 5)),
    "stored-closure-blocks-captured-source-use": ("""
type Holder<F: mut fn(): Unit> { f: F }
fn main(): i32 {
    var v = 1
    var h = Holder(fn(): Unit { v += 1 })
    v = 5
    h.f()
    v
}
""", "ownership", "live exclusive loan", (6, 5)),
    "closure-view-result-cannot-escape-captured-local": ("""
fn main(): i32 {
    var f = {
        var l = 1
        fn(): mut i32 { mut l }
    }
    let a = f()
    *a = 1
    0
}
""", "ownership", "live exclusive loan", (6, 5)),
    "result-mixing-safe-and-raw-views-stays-backed-by-every-source": ("""
fn pick(c: mut i32, d: mut i32, p: ptr<mut i32>, flag: bool): mut i32 from (c, d) {
    let r = if flag { mut c } else { unsafe { mut *p } }
    r
}
fn main(): i32 {
    var a = 1
    var b = 2
    let p = mut b as ptr<mut i32>
    let x = pick(mut a, mut b, p, false)
    b = 5
    *x = 3
    0
}
""", "ownership", "live exclusive loan", (11, 5)),
    "for-over-non-iterator": (
        "fn main(): i32 { var t = 0; for x in 5 { t += 1 }; t }",
        "type", "for requires", (1, 29)),
    "review-reserved-where-is-not-an-identifier": (
        "fn where() { 0 }\nfn main(){0}",
        "parse", "expected an identifier", (1, 4)),
    "review-reserved-macro-is-not-an-identifier": (
        "fn main() { let macro=1; macro }",
        "parse", "expected an identifier", (1, 17)),
    "review-text-literal-must-close": (
        'fn main() { unsafe { asm!("unterminated)\n} }',
        "lex", "unterminated text literal", (1, 27)),
    "review-backtick-must-contain-an-identifier": (
        "fn `bad-name`() { 0 }\nfn main(){0}",
        "lex", "backtick contents must be an identifier", (1, 4)),
    "text-escape-rejects-unknown-escape": (
        'fn main() { unsafe { asm!("a\\q") }; 0 }',
        "lex", "unsupported constant text escape", (1, 27)),
    "text-escape-rejects-non-ascii-byte": (
        'fn main() { unsafe { asm!("a\\x80b") }; 0 }',
        "lex", "text byte escape requires an ASCII value", (1, 27)),
    "text-escape-rejects-non-hexadecimal-byte": (
        'fn main() { unsafe { asm!("a\\xZZb") }; 0 }',
        "lex", "text byte escape requires an ASCII value", (1, 27)),
    "text-escape-rejects-truncated-byte": (
        'fn main() { unsafe { asm!("a\\x4") }; 0 }',
        "lex", "incomplete byte escape", (1, 27)),
    "text-escaped-closing-quote-is-unterminated": (
        'fn main() { unsafe { asm!("a\\") }; 0 }',
        "lex", "unterminated text literal", (1, 27)),
    "backtick-rejects-empty-identifier": (
        "fn ``() { 0 }\nfn main() { 0 }",
        "lex", "backtick contents must be an identifier", (1, 4)),
    "backtick-rejects-leading-digit": (
        "fn `9x`() { 0 }\nfn main() { 0 }",
        "lex", "backtick contents must be an identifier", (1, 4)),
    "backtick-must-close-on-its-line": (
        "fn `unterminated\nfn main() { 0 }",
        "lex", "unterminated backtick identifier", (1, 4)),
    "review-growing-copy-specialization-is-bounded": ("""
copy type Wrapper<T:Copy> { value:T }
fn expand<T:Copy>(value:T,n:i32):i32 {
    if n == 0 { 0 } else { expand(Wrapper(value),n-1) }
}
fn main() { expand(1,2) }
""", "limit", "specialization nesting limit", (4, 28)),
    "review-recursive-generic-permutation-preserves-type": ("""
copy type Pair<A:Copy,B:Copy> { first:A; second:B }
fn swap<T:Copy,U:Copy>(p:Pair<T,U>,q:Pair<U,T>,n:i32):T {
    if n == 0 { p.first } else {
        let other = swap::<U,T>(q,p,n-1)
        q.first
    }
}
fn main() { 0 }
""", "type", "expected U, found T", (6, 9)),
    "review-local-never-name-does-not-inherit-divergence": (
        "fn stop():Never { loop {} }\nfn done():Unit {}\n"
        "fn invoke(stop:fn():Unit):i32 { stop() }\nfn main(){ invoke(done) }",
        "type", "expected i32", (3, 31)),
    "review-views-require-explicit-comparison": (
        "fn main() { let a=1; let b=2; if read a == read b {1} else {0} }",
        "type", "view comparisons require explicitly comparing", (1, 34)),
    "review-unreachable-or-alternative": (
        "fn main() { match 1 { 1 | 1 => 0, _ => 1 } }",
        "type", "unreachable or-pattern alternative", (1, 27)),
    "review-symbolic-array-region-escape": ("""
fn put<region a,region b,const N:i32>(
    dst:mut [read i32 from b;N],src:take [read i32 from a;N]):Unit {
    dst = src
}
fn main() { 0 }
""", "region", "declared relationship", (4,5)),
    "review-concrete-generic-transparent-layout": ("""
@layout(transparent)
copy type Wrapper<T:Copy> { value:T; other:u32 }
fn main() { let value = Wrapper(1u8,2u32); 0 }
""", "attribute", "object layout cannot be established", (4, 25)),
    "array-size-exceeds-address-space": (
        "fn f(a:[[u64;2_000_000_000];2_000_000_000]) {}\nfn main() { 0 }",
        "limit", "array size exceeds target address space", (1, 6)),
    "review-cleanup-array-expansion-limit-owned-by-checker": (
        "type Owner { drop {} }\nfn main() { let value:[[Owner;3000];3000]; 0 }",
        "limit", "array length exceeds compiler resource limit", (1, 1)),
    "review-truncated-negative-pattern": (
        "fn f(x:i32):i32 {\n    match x {\n        -",
        "parse", "expected an integer literal after '-'", (3,10), 1),
    "review-negative-identifier-pattern": (
        "fn f(x:i32):i32 { match x { -x => 1, _ => 0 } }\nfn main(){0}",
        "parse", "expected an integer literal after '-'", (1, 30)),
    "review-truncated-assembly-operand": (
        'fn main() { unsafe { asm!("nop", value =',
        "parse", "expected an assembly operand mode", (1, 41), 1),
    "review-recursive-optional-layout": (
        "type A { value: A? }\nfn main(){0}",
        "type", "recursive by-value product has no finite layout", (1, 10), 1),
    "review-recursive-tuple-layout": (
        "type A { value: (i32,A) }\nfn main(){0}",
        "type", "recursive by-value product has no finite layout", (1, 10), 1),
    "review-recursive-array-layout": (
        "type A { value: [A;2] }\nfn main(){0}",
        "type", "recursive by-value product has no finite layout", (1, 10), 1),
    "recursive-enum-payload-layout": (
        "enum E { X(E), Y }\nfn main(){0}",
        "type", "recursive by-value product has no finite layout", (1, 10), 1),
    "recursive-field-reports-the-field": (
        "fn main(){0}\ntype A {\n  x: i32\n  b: [A; 2]\n}\n",
        "type", "recursive by-value product has no finite layout", (4, 3), 1),
    "mutual-recursion-reports-the-closing-field": (
        "enum E { X(i32), Y(A) }\ntype A { e: E }\nfn main(){0}",
        "type", "recursive by-value product has no finite layout", (2, 10), 1),
    "review-packed-indirect-borrow": ("""
@packed(1)
copy type Packed { tag:u8; value:i32 }
fn inspect(value:read i32):i32 { value }
fn main() {
    let value = Packed(0u8,42)
    let pointer:fn(read i32):i32 = inspect
    pointer(value.value) - 42
}
""", "alignment", "unaligned storage cannot form an ordinary view", (8,13)),
    "review-pin-optional-projection": ("""
fn main() {
    var value:i32? = none
    var handle = core::pin::Pin::new(mut value)
    let inner = handle.project_value()
    0
}
""", "feature", "pin projection of sum variants", (5, 17)),
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
""", "type", "required constant", (7, 56)),
    "machine-numeric-required-u128-overflow": ("""
fn value<const N:u128=340282366920938463463374607431768211455u128+1>():u128{N}
fn main(){0}
""", "type", "required integer constant overflows", (2, 23)),
    "machine-numeric-required-i128-division-overflow": ("""
fn value<const N:i128=-170141183460469231731687303715884105728i128 / -1>():i128{N}
fn main(){0}
""", "type", "required integer constant overflows", (2, 23)),
    "machine-numeric-required-u8-width-overflow": ("""
fn value<const N:u8=255u8+1>():u8{N}
fn main(){0}
""", "type", "required integer constant overflows", (2, 21)),
    "machine-numeric-required-u128-multiply-overflow": ("""
fn value<const N:u128=(1u128<<64)*(1u128<<64)>():u128{N}
fn main(){0}
""", "type", "required integer constant overflows", (2, 23)),
    "machine-numeric-required-u128-subtract-underflow": ("""
fn value<const N:u128=0u128-1>():u128{N}
fn main(){0}
""", "type", "required integer constant overflows", (2, 23)),
    "machine-numeric-required-i128-negate-overflow": ("""
fn value<const N:i128=-(-170141183460469231731687303715884105728i128)>():i128{N}
fn main(){0}
""", "type", "required integer constant overflows", (2, 23)),
    "machine-numeric-required-wide-invalid-shift": ("""
fn value<const N:u128=1u128<<128>():u128{N}
fn main(){0}
""", "type", "invalid shift", (2, 23)),
    "machine-numeric-required-wide-zero-divisor": ("""
fn value<const N:u128=1u128/0>():u128{N}
fn main(){0}
""", "type", "division by zero", (2, 23)),
    "machine-numeric-pattern-rejects-truncation": ("""
fn main(){match 1u64 { 18446744073709551616 => 0, _ => 1 }}
""", "type", "pattern literal is outside the u64 range", (2, 24)),
    "machine-numeric-wide-match-rejects-missing-maximum": ("""
fn main(){match 0u128 { 0..340282366920938463463374607431768211455 => 0 }}
""", "type", "non-exhaustive match", (2, 11)),
    "machine-numeric-wide-match-rejects-unreachable-maximum": ("""
fn main(){match 0u128 {
    0..=340282366920938463463374607431768211455 => 0,
    340282366920938463463374607431768211455 => 1
}}
""", "type", "unreachable match arm", (4, 5)),
    "machine-numeric-range-rejects-conflicting-widths": ("""
fn main(){for value in 1u64..2u128 {}
0}
""", "type", "expected u128, found u64", (2, 24)),
    "machine-numeric-index-retains-explicit-i32-contract": ("""
fn main(){let value=[0,1];value[1u64]}
""", "type", "expected i32, found u64", (2, 33)),
    "machine-numeric-wide-count-cannot-truncate-into-a-small-array": (
        "fn main() { let values = [0;340282366920938463463374607431768211455u128]; 0 }",
        "limit","array length limit exceeded", (1, 26)),
    "machine-numeric-usize-constant-index-cannot-truncate": (
        "fn main() { let values = [42]; values[4294967296usize] }",
        "type","array index is out of bounds", (1, 39)),
    "machine-numeric-required-rejects-conflicting-suffix": ("""
fn value<const N:u64>():u64{N}
fn main(){let result=value::<42u128>();0}
""", "type", "const argument does not match its declared type", (3, 22)),
    "machine-numeric-rejects-unknown-floating-relaxation": ("""
@fast_math(fast)
fn main(){0}
""", "attribute", "unknown floating relaxation", (2, 12)),
    "machine-numeric-rejects-duplicate-floating-relaxation": ("""
@fast_math(contract,contract)
module numeric { pub fn value():i32{42} }
fn main(){0}
""", "attribute", "duplicate floating relaxation", (2, 21)),
    "machine-numeric-rejects-unlisted-floating-relaxation": ("""
@fast_math
fn main(){0}
""", "attribute", "requires a comma-separated list", (2, 1)),
    "machine-numeric-checked-conversion-rejects-nonnumeric-target": ("""
fn main(){let result=42i64.checked_cast::<bool>();0}
""", "type", "invalid primitive operation", (2, 22)),
    "machine-static-zero-count-repetition-cannot-execute-drop": (
        'type Owner { value: i32; drop {} }; '
        'static EMPTY: [Owner;0] = [Owner(42);0]; fn main() { 0 }',
        "constant", "element destructor", (1, 63)),
    "c-variadic-definition-rejects-native-fat-pointer": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<ptr<read [i32]>>(); 0 }; fn main() { 0 }',
        "type", "invalid primitive", (1, 60)),
    "c-variadic-definition-rejects-native-function-pointer": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<fn(): i32>(); 0 }; fn main() { 0 }',
        "type", "invalid primitive", (1, 60)),
    "machine-static-function-pointer-storage-is-not-a-function-symbol": (
        'extern "C" { @link_name("same") static ADDRESS: unsafe extern "C" fn(): i32; '
        '@link_name("same") unsafe fn imported(): i32; } fn main() { 0 }',
        "signature", "conflicting external", (1, 33)),
    "machine-static-unsafe-initializer-does-not-authorize-other-declarations": (
        'static mut VALUE: i32 = 1; static FIRST: ptr<mut i32> = unsafe { SECOND }; '
        'static SECOND: ptr<mut i32> = core::ptr::from_mut(VALUE); fn main() { 0 }',
        "unsafe", "requires an unsafe", (1, 106)),
    "machine-static-import-and-definition-share-one-loan-root": (
        '@export_name("counter") static mut COUNT: i32 = 1; '
        'extern "C" { @link_name("counter") static mut ALIAS: i32; } '
        'fn main() { let writer = unsafe { mut COUNT }; '
        'let reader = unsafe { read ALIAS }; *writer = 42; *reader }',
        "ownership", 'access or storage lifetime conflicts with a live read loan', (1, 195)),
    "machine-static-unaligned-address-cannot-form-safe-view": (
        '@packed(1) copy type Packed { tag: u8; value: i32 }; '
        'static VALUE: Packed = Packed(0u8,42); '
        'static VIEW: read i32 from static = read VALUE.value; fn main() { 0 }',
        "constant", "unaligned", (1, 129)),
    "c-variadic-definition-native-cursor-storage-is-opaque": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.0; 0 }; fn main() { 0 }',
        "name", "unknown field", (1, 60)),
    "machine-static-symbol-conflict-with-function": (
        '@export_name("same") static VALUE: i32 = 42; '
        '@export_name("same") fn answer(): i32 { 42 }; fn main() { 0 }',
        "signature", "conflicting external", (1, 22), 1),
    "machine-static-duplicate-symbol-definition": (
        '@export_name("same") static FIRST: i32 = 42; '
        '@export_name("same") static SECOND: i32 = 42; fn main() { 0 }',
        "signature", "conflicting external", (1, 67)),
    "machine-static-required-initializer-overflow": (
        "static VALUE: i8 = 127 + 1; fn main() { 0 }",
        "constant", "overflows", (1, 20)),
    "c-variadic-definition-conditional-end-is-not-live": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'if count == 0 { args.end() }; args.arg::<i32>() }; fn main() { 0 }',
        "ownership", "may have been moved", (1, 90)),
    "c-variadic-definition-copy-after-end": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.end(); let copied = args.copy(); 0 }; fn main() { 0 }',
        "ownership", "may have been moved", (1, 85)),
    "c-variadic-definition-float-default-promotion-required": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<f32>(); 0 }; fn main() { 0 }',
        "type", "invalid primitive", (1, 60)),
    "c-variadic-definition-cursor-cannot-enter-generic-helper": (
        'fn forget<T>(value: take T) { core::mem::forget(take value) }; '
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'forget(take args); 0 }; fn main() { 0 }',
        "ownership", "cannot be passed", (1, 130)),
    "machine-static-mutable-access-requires-unsafe": (
        "static mut VALUE: i32 = 42; fn main() { VALUE; 0 }",
        "unsafe", "requires an unsafe", (1, 41)),
    "machine-static-immutable-requires-shareable": (
        "static CELL: core::cell::Cell<i32> = core::cell::Cell::new(0); fn main() { 0 }",
        "type", "requires a Shareable type", (1, 1)),
    "machine-static-no-owned-move": (
        "type Owner { value: i32 }; static VALUE: Owner = Owner(42); "
        "fn main() { let moved = take VALUE; 0 }",
        "ownership", "cannot move out of static", (1, 90)),
    "machine-static-required-initializer-no-host-execution": (
        "fn compute(): i32 { 42 }; static VALUE: i32 = compute(); fn main() { 0 }",
        "constant", "validated constant", (1, 47)),
    "machine-static-required-initializer-cycle": (
        "static FIRST: i32 = SECOND; static SECOND: i32 = FIRST; fn main() { 0 }",
        "constant", "cycle", (1, 1)),
    "machine-static-private-module-access": (
        "module storage { static VALUE: i32 = 42; } "
        "fn main() { storage::VALUE; 0 }", "name", "unresolved value 'storage::VALUE'", (1, 56)),
    "machine-static-local-view-cannot-be-stored": (
        "static VALUE: i32 = 1; static mut VIEW: read i32 from static = read VALUE;"
        "fn main() { let value = 42; unsafe { VIEW = read value }; 0 }",
        "region", 'view region or invariant payload does not satisfy its declared relationship', (1, 112)),
    "c-variadic-definition-use-after-end": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.end(); args.arg::<i32>() }; fn main() { 0 }',
        "ownership", "may have been moved", (1, 72)),
    "c-variadic-definition-requires-promoted-type": (
        'unsafe extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<i8>() as i32 }; fn main() { 0 }',
        "type", "invalid primitive", (1, 60), 1),
    "c-variadic-definition-read-requires-unsafe": (
        'extern "C" fn callback(count: i32,args: ...): i32 { '
        'args.arg::<i32>() }; fn main() { 0 }',
        "unsafe", 'operation requires an unsafe block or unsafe function', (1, 53)),
    "c-variadic-definition-cursor-cannot-escape": (
        'unsafe extern "C" fn callback(count: i32,args: ...) { args }; fn main() { 0 }',
        "ownership", "cannot escape", (1, 19), 1),
    "machine-numeric-character-constants-cannot-use-integer-arithmetic": (
        "fn value<const C: char = 'a' + 'b'>(): char { C }\nfn main() { 0 }",
        "type","requires integer operands", (1, 26)),
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
""", "type", "Unpin", (10, 5)),
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
""", "type", 'invalid primitive operation or operand types', (8, 22)),
    "machine-cell-shared-cell-handle-cannot-grant-ordinary-mutable-view": ("""
fn wrong(cell: read core::cell::RefCell<i32>): Unit {
    let value = cell.get_mut()
}
fn main() { 0 }
""", "ownership", 'exclusive borrow requires a mutable place', (3, 17)),
    "machine-unpin-contextual-bound-does-not-quantify-another-type": ("""
type Owned { marker: core::marker::PhantomPinned }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Copy> Wrapper<T> implements Unpin {}
fn wrong<T>(value: read Wrapper<T>): Unit where Wrapper<T>: Unpin {
    var handle = core::pin::pin(Wrapper(Owned(core::marker::PhantomPinned),core::marker::PhantomPinned))
    let wrong = handle.get_mut()
}
fn main() { 0 }
""", "type", 'unsatisfied Unpin condition', (7, 17)),
    "machine-unpin-unresolved-region-condition-is-not-unconditional": ("""
interface Ready<region r> {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready<region static>> Wrapper<T> implements Unpin {}
fn wrong<region r, T: Ready<region r>>(value: mut Wrapper<T>) {
    let handle = core::pin::Pin::new(mut value)
}
fn main() { 0 }
""", "type", 'unsatisfied Unpin condition', (6, 18)),
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
""", "type", 'unsatisfied Unpin condition', (9, 17)),
    "machine-cell-payload-view-cannot-outlive-local-guard": ("""
fn wrong(cell: read core::cell::RefCell<i32>): read i32 from cell {
    let guard = cell.borrow()
    guard.get_ref()
}
fn main() { 0 }
""", "ownership", 'returned view escapes local storage', (4,5)),
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
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (8, 17)),
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
""", "type", "Unpin", (11, 17)),
    "machine-unpin-recursive-condition-is-not-a-proof": ("""
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T> Wrapper<T> implements Unpin where Wrapper<T>: Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(42,core::marker::PhantomPinned))
    let wrong = handle.get_mut()
    0
}
""", "type", 'unsatisfied Unpin condition', (6, 17)),
    "machine-cell-owner-cannot-move-before-later-guard-cleanup": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let moved = cell
    0
}
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (5, 17)),
    "machine-cell-owner-cannot-mutate-after-guard-last-use": ("""
fn main() {
    var cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let value = *guard.get_ref()
    *cell.get_mut() = 0
    value
}
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (6, 5)),
    "machine-cell-guard-cannot-escape-cell": ("""
fn main() {
    let guard = { let cell = core::cell::RefCell::new(42); cell.borrow() }
    *guard.get_ref()
}
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (3,74)),
    "machine-cell-forget-cannot-invalidate-a-live-payload-reference": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let value = guard.get_ref()
    core::mem::forget(guard)
    *value
}
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (6, 23)),
    "machine-cell-refmut-reborrows-are-not-independent-aliases": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    var guard = cell.borrow_mut()
    let first = guard.get_mut()
    let second = guard.get_mut()
    *first += *second
    0
}
""", "ownership", 'access or storage lifetime conflicts with a live exclusive loan', (7, 15)),
    "machine-cell-shared-ref-does-not-grant-mutable-payload": ("""
fn main() {
    let cell = core::cell::RefCell::new(42)
    var guard = cell.borrow()
    let wrong = guard.get_mut()
    0
}
""", "type", 'invalid primitive operation or operand types', (5, 17)),
    "machine-cell-copy-get-rejects-owned-payload": ("""
type Owned { value: i32 }
fn main() { let cell = core::cell::Cell::new(Owned(42)); let value = cell.get(); 0 }
""", "type", 'invalid primitive operation or operand types', (3, 70)),
    "machine-cell-exchange-writeback-retains-new-view-source": ("""
fn set<region a>(cell: read core::cell::Cell<read i32 from a>,
                 value: read i32 from a) { cell.set(read value) }
fn main() {
    let first = 1
    let cell = core::cell::Cell::new(read first)
    { let short = 42; set(cell,read short) }
    *cell.get()
}
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (7, 44)),
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
""", "ownership", 'access or storage lifetime conflicts with a live read loan', (11, 44)),
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
""", "type", 'unsatisfied Unpin condition', (8, 17)),
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
""", "type", 'unsatisfied Unpin condition', (9, 18)),
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
""", "type", 'unsatisfied Unpin condition', (9, 17)),
    "machine-unpin-negative-declaration-remains-negative": ("""
type Blocked { value: i32 }
impl Blocked not Unpin;
type Outer { value: Blocked }
fn main() {
    var handle = core::pin::pin(Outer(Blocked(42)))
    let wrong = handle.get_mut()
    0
}
""", "type", 'invalid primitive operation or operand types', (7, 17)),
    "machine-unpin-negative-declaration-cannot-have-bounds": ("""
type Wrapper<T> { value: T }
impl<T: Copy> Wrapper<T> not Unpin;
fn main() { 0 }
""", "type", 'negative Unpin declarations cannot specialize bounds', (3, 1)),
    **MACHINE_NEGATIVE,
    "machine-transparent-enum-requires-one-variant": (
        "@layout(transparent) enum Invalid { First(i32); Second(i32) }\nfn main() { 0 }",
        "attribute", 'transparent enum representation requires exactly one variant', (1, 22)),
    "machine-combined-enum-layout-rejects-conflicting-tags": (
        "@layout(C,u8,i8) enum Invalid { First }\nfn main() { 0 }",
        "attribute", 'an enum cannot have multiple integer representations', (1, 14)),
    "machine-transparent-enum-requires-one-storage-payload": (
        "@layout(transparent) enum Invalid { Only(i32,i32) }\nfn main() { 0 }",
        "attribute", 'object layout cannot be established for this representation', (1, 22)),
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
""","ownership", 'access or storage lifetime conflicts with a live read loan', (13, 5)),
    "machine-borrowed-pin-cannot-be-consumed-through-a-view": (
        "fn wrong(value: read pinned mut i32) { let result = unsafe { value.into_inner_unchecked() } }\nfn main() { 0 }",
        "ownership", 'cannot move out of a borrowed place', (1, 62)),
    "machine-manual-unpin-condition-rejects-address-sensitive-argument": ("""
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Unpin> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(core::marker::PhantomPinned,core::marker::PhantomPinned))
    let value = handle.get_mut()
    0
}
""","type", 'unsatisfied Unpin condition', (6, 17)),
    "machine-union-read-requires-unsafe": (
        "union Bits { integer: u32; real: f32 }\nfn main() { let value = Bits(integer: 42u32); let result = value.real; 0 }",
        "unsafe", 'reading a union field requires unsafe', (2, 60)),
    "machine-union-overlapping-field-loans-conflict": ("""
union Bits { integer: u32; real: f32 }
fn main() {
    var value = Bits(integer: 42u32)
    let borrowed = unsafe { read value.integer }
    value.real = 0.0f32
    if *borrowed == 42u32 { 0 } else { 1 }
}
""","ownership", 'access or storage lifetime conflicts with a live read loan', (6, 5)),
    "machine-union-owned-field-requires-manual-drop": (
        "type Owned { drop {} }\nunion Wrong { value: Owned; bits: usize }\nfn main() { 0 }",
        "type", 'union fields requiring destruction must use ManuallyDrop storage', (2, 1)),
    "machine-explicit-receiver-must-wrap-self": (
        "type Payload { value: i32; fn wrong(receiver self: i32): i32 { self } }\nfn main() { 0 }",
        "signature", 'explicit receiver must wrap Self', (1, 28)),
    "machine-explicit-receiver-must-be-first": (
        "type Payload { fn wrong(value: i32, receiver self: read Self): i32 { value } }\nfn main() { 0 }",
        "signature", 'explicit receiver must be first and bind self', (1, 50)),
    "machine-enum-discriminants-check-their-width": (
        "@layout(u8) copy enum Byte { First = 255; Overflow }\nfn main() { 0 }",
        "type", 'enum discriminant is outside its representation', (1, 43)),
    "machine-enum-discriminants-must-be-distinct": (
        "@layout(i16) copy enum Number { First = -1; Second = -1 }\nfn main() { 0 }",
        "type", 'duplicate enum discriminant', (1, 45)),
    "machine-negative-unpin-declaration-prevents-extraction": (
        "type Stable { value: i32 }\nimpl Stable not Unpin;\nfn main() { var handle = core::pin::pin(Stable(42)); let value = handle.get_mut(); 0 }",
        "type", 'invalid primitive operation or operand types', (3, 66)),
    "machine-generic-pin-extraction-needs-unpin-bound": (
        "fn access<T>(value: mut pinned mut T): mut T from value { value.get_mut() }\nfn main() { 0 }",
        "type", 'invalid primitive operation or operand types', (1, 59)),
    "machine-manual-unpin-requires-unsafe-implementation": (
        "type Stable { value: i32 }\nimpl Stable implements Unpin {}\nfn main() { 0 }",
        "unsafe", 'manual Unpin implementation requires unsafe impl', (2, 1)),
    "machine-pin-projection-retains-exclusive-parent-loan": ("""
type Child { value: i32; marker: core::marker::PhantomPinned }
type Parent { @pinned child: Child; other: i32 }
fn main() {
    var handle = core::pin::pin(Parent(Child(42,core::marker::PhantomPinned),0))
    let child = handle.project_child()
    let parent = unsafe { handle.get_unchecked_mut() }
    child.get_ref().value + parent.other
}
""","ownership", 'access or storage lifetime conflicts with a live exclusive loan', (8, 5)),
    "machine-structurally-pinned-destructor-cannot-move-field": ("""
type Child { value: i32; marker: core::marker::PhantomPinned }
type Parent {
    @pinned child: Child
    drop { let moved = self.get_ref().child }
}
fn main() { 0 }
""","ownership", 'cannot move out of a borrowed place', (5, 24), 1),
    "machine-transmute-rejects-different-sizes": (
        "fn main() { let value = unsafe { core::mem::transmute::<u64>(1u32) }; 0 }",
        "type", 'invalid primitive operation or operand types', (1, 34)),
    "machine-memory-copy-requires-unsafe": (
        "fn main() { var value = 0; let p = core::ptr::from_mut(value); core::ptr::`copy`(p,p,1); 0 }",
        "unsafe", 'operation requires an unsafe block or unsafe function', (1, 64)),
    "machine-memory-copy-requires-mutable-destination": (
        "fn main() { let value = 0; let p = core::ptr::from_ref(value); unsafe { core::ptr::`copy`(p,p,1) }; 0 }",
        "type", 'invalid primitive operation or operand types', (1, 73)),
    "machine-unaligned-packed-fields-cannot-be-pinned": (
        "@packed(1) type Packed { @pinned value: i64 }\nfn main() { 0 }",
        "attribute", 'an unaligned packed field cannot be structurally pinned', (1, 12)),
    "machine-atomic-handles-are-not-implicitly-copy": (
        "fn main() { let first=core::sync::atomic::AtomicU32::new(42); let second=first; first.load(core::sync::atomic::Ordering::Relaxed) as i32 }",
        "ownership","moved", (1, 81)),
    "machine-atomic-unsupported-width-is-not-blocking-emulation": (
        "fn main() { let value=core::sync::atomic::AtomicU128::new(0); 0 }",
        "feature","lock-free alias", (1, 23)),
    "machine-address-sensitive-payload-requires-pinned-access": ("""
type Stable { marker: core::marker::PhantomPinned; value: i32 }
fn main() {
    var handle = core::pin::pin(Stable(core::marker::PhantomPinned,42))
    let reference = handle.get_mut()
    0
}
""","type","invalid primitive operation", (5, 21)),
    "machine-packed-fields-cannot-form-aligned-views": ("""
@layout(C)
@packed(1)
copy type Packed { tag: u8; value: i32 }
fn inspect(value: read i32): i32 { value }
fn main() { let value=Packed(0u8,42); inspect(value.value) }
""","alignment","unaligned storage", (6, 47)),
    "machine-unsafe-does-not-permit-unaligned-reference-construction": ("""
@layout(C)
@packed(1)
copy type Packed { tag: u8; value: i32 }
fn main() { let value=Packed(0u8,42); let reference=unsafe { read value.value }; *reference }
""","alignment","unaligned storage", (5, 67)),
    "machine-storage-write-needs-initialized-storage-handle": (
        "fn main() { var value: core::mem::MaybeUninit<i32>; let reference=value.write(42); *reference }",
        "type","storage handle may be uninitialized", (1, 67)),
    "machine-unsafe-cell-shared-reference-requires-unsafe": (
        "fn main() { let cell=core::cell::UnsafeCell::new(42); let value=cell.get_ref(); *value }",
        "unsafe", "requires an unsafe block", (1, 65)),
    "machine-uninitialized-owned-reference-preserves-original-loan": ("""
copy type Pair { first: i32; second: i32 }
fn main() {
    var value = Pair(20,22)
    let storage = core::mem::MaybeUninit::new(read value)
    let reference = unsafe { storage.assume_init() }
    value.first = 40
    reference.first + reference.second
}
""","ownership","live read loan", (7, 5)),
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
""","ownership","live read loan", (9, 5)),
    "machine-c-callable-cannot-become-native-abi": (
        'extern "C" fn callback(value: i32): i32 { value }\nfn main() { let p: fn(i32): i32 = callback; p(0) }',
        "type", 'found extern "C" fn', (2, 13)),
    "machine-foreign-typed-failure-needs-explicit-c-representation": (
        'extern "C" { unsafe fn operation(): i32 throws i32; }\nfn main() { 0 }',
        "signature", "native typed failure", (1, 21)),
    "machine-duplicate-symbol-attribute-is-rejected": (
        '@export_name("first") @export_name("second")\nextern "C" fn operation(): i32 { 42 }\nfn main() { 0 }',
        "attribute", "duplicate singleton", (1, 23)),
    "machine-raw-method-requires-unsafe": (
        "fn main() { let value = 42; let p = core::ptr::from_ref(value); p.`read`() }",
        "unsafe", "requires an unsafe block", (1, 65)),
    "machine-raw-write-requires-mutable-pointer": (
        "fn main() { let value = 42; let p = core::ptr::from_ref(value); unsafe { p.write(1) }; 0 }",
        "type", "invalid primitive operation", (1, 74)),
    "machine-explicit-overflow-operations-preserve-width": (
        "fn main() { let value = 1u8.wrapping_add(2u16); 0 }",
        "type", "expected", (1, 42), 1),
    "machine-raw-dereference-requires-unsafe": (
        "fn main() { let value = 42; let p = read value as ptr<read i32>; *p }",
        "unsafe", "requires an unsafe block", (1, 66)),
    "machine-unsafe-function-cannot-be-called-safely": (
        "unsafe fn operation(): i32 { 42 }\nfn main() { operation() }",
        "unsafe", "requires an unsafe block", (2, 13)),
    "machine-unsafe-function-pointer-cannot-become-safe": (
        "unsafe fn operation(): i32 { 42 }\nfn main() { let p: fn(): i32 = operation; p() }",
        "type", 'found unsafe fn', (2, 13)),
    "machine-unsafe-does-not-disable-initialization-checks": (
        "fn main() { let value: i32; unsafe { value } }",
        "type", "uninitialized", (1, 38)),
    "machine-unsafe-does-not-grant-mutable-pointer-access": (
        "fn main() { let value = 42; let p = read value as ptr<read i32>; unsafe { *p = 1 }; 0 }",
        "ownership", 'cannot write through a read parameter', (1, 75), 1),
    "machine-integers-do-not-implicitly-widen": (
        "fn main() { let a = 1u8; let b = 2u16; let sum = a + b; 0 }",
        "type", "expected", (1, 50)),
    "machine-negative-unsigned-literal": (
        "fn main() { let value: u64 = -1; 0 }",
        "type", "outside the u64 range", (1, 31)),
    "machine-integer-literal-checks-contextual-width": (
        "fn main() { let value: i8 = 128; 0 }",
        "type", "outside the i8 range", (1, 29)),
    "machine-floats-have-no-bitwise-operators": (
        "fn main() { let value = 1.0f32 & 2.0f32; 0 }",
        "type", "integer", (1, 25)),
    "self-path-outside-type-or-impl": (
        "type V { n: usize\n  static fn make(): V { V(0usize) } }\nfn main(): i32 { let v: V = Self::make(); 0 }",
        "name", "'Self' is only available inside a type or impl body", (3, 29), 1),
    "u32-cannot-cast-to-char": (
        "fn main(): i32 { let c = 233u32 as char; let d = c; 0 }",
        "type", "invalid scalar conversion", (1, 26), 1),
    "static-method-without-generics-rejects-turbofish": (
        "type V<T> { n: usize\n  static fn make(): V<T> { V(0usize) } }\nfn main(): i32 { let v: V<i32> = V::make::<i32>(); 0 }",
        "type", "excess explicit generic arguments", (3, 34), 1),
    "machine-integers-cannot-cast-to-bool": (
        "fn main() { let flag = 1 as bool; 0 }",
        "type", "invalid scalar conversion", (1, 24)),
    "receiver-move-failure-cannot-fall-back-to-read-interface": ("""
interface Choose { fn choose(): i32; }
type Value { take fn choose(): i32 { 1 } }
impl Value implements Choose { fn choose(): i32 { 2 } }
fn main() {
    let value = Value()
    let borrowed = read value
    borrowed.choose()
}
""", "ownership", "cannot move out of a borrowed place", (8, 5)),
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
""", "ownership", "requires matching DerefMut", (16, 5)),
    "higher-ranked-interface-rejects-static-only-implementation": ("""
interface Lifetime<region r> {}
type StaticOnly {}
impl StaticOnly implements Lifetime<region static> {}
fn accept<T: for<region r> Lifetime<region r>>(value: read T): i32 { 42 }
fn main() { let value = StaticOnly(); accept(value) }
""", "type", "interface obligation", (6, 39)),
    "mutable-stored-region-remains-invariant": ("""
type Ref<region r> { value: mut (read i32 from r) from r }
fn bad<region a, region b>(
    value: take Ref<region a>
): Ref<region b> where region a: b { take value }
fn main() { 0 }
""", "region", "invariant payload", (5, 36)),
    "named-region-binder-does-not-leak-between-declarations": ("""
fn first<region r>(value: read i32 from r): i32 { 0 }
fn second(value: read i32 from r): i32 { 0 }
fn main() { 0 }
""", "region", "unknown region", (3, 11), 1),
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
""", "ownership", "live read loan", (13, 5)),
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
""", "ownership", "live read loan", (17, 5)),
    "generic-owned-return-spec": ((Path(__file__).resolve().parents[1] / "examples/core/reject-generic-owned-return.mt").read_text(),
                                 "ownership", "borrowed", (2, 5)),
    "implementation-cannot-strengthen-generic-bounds": ("""
interface Accept { fn accept<T>(value: T): Unit; }
type Number {}
impl Number implements Accept {
    fn accept<T: Copy>(value: T): Unit { let first = value; let second = value }
}
fn main() { 0 }
""", "type", "strengthens", (5, 5), 1),
    "associated-output-must-satisfy-copy-bound": ("""
interface Family { type Item: Copy; }
type Owned { value: i32 }
type Number {}
impl Number implements Family { type Item = Owned }
fn main() { 0 }
""", "type", "Copy", (5, 33)),
    "erasure-cannot-expose-unbound-self-inputs": ("""
interface Equal { fn equal(other: Self): bool; }
type Number {}
impl Number implements Equal { fn equal(other: read Number): bool { true } }
fn main() {
    let value = Number()
    let erased: read any Equal = read value
    0
}
""", "type", "not dispatchable", (7, 5)),
    "erasure-rejects-caller-selected-method-types": ("""
interface Generic { fn accept<T>(value: T): Unit; }
type Number {}
impl Number implements Generic { fn accept<T>(value: T): Unit {} }
fn main() {
    let value = Number()
    let erased: read any Generic = read value
    0
}
""", "type", "not dispatchable", (7, 5)),
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
""", "type", "different hidden types", (9, 5)),
    "opaque-return-does-not-expose-hidden-fields": ("""
interface Readable { fn value(): i32; }
copy type Number { value: i32 }
impl Number implements Readable { fn value(): i32 { self.value } }
fn make(): some Readable { Number(42) }
fn main() { make().value }
""", "name", "field", (6, 13)),
    "slice-length-rejects-arguments": (
        "fn f(s: read [i32]): usize { s.len(1) }\nfn main() { 0 }\n",
        "type", "slice len requires no arguments", (1, 30)),
    "slice-read-view-cannot-be-upgraded": ("""
fn increment(values: mut [i32]) { values[0] += 1 }
fn main() {
    var values = [41]
    let borrowed: read [i32] = read values
    increment(borrowed)
    0
}
""", "ownership", "mutable", (6, 15)),
    "projection-requires-an-implementation": ("""
interface Family { type Item; }
type Unrelated {}
fn invalid(value: <Unrelated implements Family>::Item): Unit {}
fn main() { 0 }
""", "type", "interface bound", (4, 12), 1),
    "mismatched-pattern-shape-is-a-source-error": ("fn main() { match true { present(value) => 0, _ => 1 } }\n", "type", "incompatible aggregate shape", (1, 26), 1),
    "mismatched-variant-payload-count-is-a-source-error": ("copy enum Value { Held(i32) }\nfn main() { match Value::Held(42) { Value::Held(first,second) => first } }\n",
                                                         "type", "pattern payload count", (2, 37), 1),
    "unicode-surrogate-is-not-scalar": (r"fn main() { let value = '\u{d800}'; 0 }"+"\n", "lex", "valid Unicode scalar", (1, 25)),
    "unicode-scalar-overflow": (r"fn main() { let value = '\u{110000}'; 0 }"+"\n", "lex", "valid Unicode scalar", (1, 25)),
    "character-needs-exactly-one-scalar": ("fn main() { let value = 'ab'; 0 }\n", "lex", "exactly one scalar", (1, 25)),
    "byte-literal-rejects-nonascii": ("fn main() { let value = b'é'; 0 }\n", "lex", "ASCII byte", (1, 25)),
    "byte-escape-requires-two-digits": (r"fn main() { let value = b'\x1'; 0 }"+"\n", "lex", "two hexadecimal digits", (1, 25)),
    "character-and-byte-remain-distinct": ("fn main() { let value: char = b'a'; 0 }\n", "type", "expected char, found u8", (1, 13)),
    "constant-array-length-overflow": ("fn main() { let values: [i32; 2147483647+1] = []; 0 }\n", "type", "constant overflows", (1, 31), 1),
    "array-length-cannot-use-runtime-binding": ("fn main() { let count=3; let values: [i32; count] = [1,2,3]; 0 }\n", "type", "constant integer", (1, 44), 1),
    "required-parameter-cannot-follow-default": ("fn bad(a:i32=0,b:i32) { a+b }\nfn main() { bad(0,0) }\n", "type", "required parameter", (1, 16)),
    "array-rest-borrow-cannot-escape-owner": ("type Owned { value:i32 }\nfn main() { let view: read [Owned;2]; { let values = [Owned(20),Owned(22),Owned(0)]; view = match values { [rest @ ..,_] => read rest } }; view[0].value }\n",
                                           "ownership", "live read loan", (2, 137)),
    "array-rest-does-not-permit-overlapping-mutation": ("fn main() { var values = [1,2,3]; match mut values { [first,rest @ ..] => { values[1] = 4; rest[0] += first } }; 0 }\n",
                                                      "ownership", "live exclusive loan", (1, 77)),
    "invalid-default-checked-when-supplied": ("fn bad(value: i32 = true) { value }\nfn main() { bad(42) }\n", "type", "expected i32, found bool", (1, 8)),
    "defaults-cannot-reference-later-parameters": ("fn bad(a: i32 = b, b: i32 = 42) { a + b }\nfn main() { bad(0,0) }\n", "name", "unresolved value 'b'", (1, 17)),
    "default-cannot-consume-earlier-owner": ("type Value { value: i32 }\nfn bad(a: take Value, b: take Value = a) { a.value + b.value }\nfn main() { bad(Value(20),Value(22)) }\n",
                                           "ownership", 'cannot move out of a borrowed place', (2, 39)),
    "default-view-does-not-extend-argument": ("fn view(a: i32, b: (read i32) = read a): read i32 from b { b }\nfn main() { let result = view(42); *result }\n",
                                            "ownership", "live read loan", (2, 13)),
    "custom-init-must-establish-every-field": ("type Pair { first: i32; second: i32; init(value: i32) { self.first = value } }\nfn main() { let pair = Pair(42); 0 }\n",
                                             "type", "may be uninitialized", (1, 57)),
    "custom-init-method-needs-whole-self": ("type Pair { first: i32; second: i32; init() { self.first = 20; self.second = self.sum() }; fn sum() { self.first + self.second } }\nfn main() { let pair = Pair(); 0 }\n",
                                           "type", "may be uninitialized", (1, 78)),
    "custom-init-replaces-generated-construction": ("type Pair { first: i32; second: i32; init() { self.first = 20; self.second = 22 } }\nfn main() { let pair = Pair(first:20,second:22); 0 }\n",
                                                    "type", "argument", (2, 35)),
    "empty-range-pattern": ("fn main() { match 1 { 2..2 => 0, _ => 1 } }\n",
                            "type", "empty or reversed", (1, 23)),
    "range-pattern-overlap-is-unreachable": ("fn main() { match 1 { 0..=42 => 0, 1..=4 => 1, _ => 2 } }\n",
                                            "type", "unreachable match arm", (1, 36)),
    "or-patterns-bind-same-names": ("copy enum Value { First(i32); Second(i32) }\nfn main() { match Value::First(42) { Value::First(a) | Value::Second(b) => a } }\n",
                                   "type", "identical names", (2, 38)),
    "sum-match-must-be-exhaustive": ("copy enum Value { First; Second }\nfn main() { match Value::First { Value::First => 0 } }\n",
                                    "type", "non-exhaustive match", (2, 13)),
    "nested-optional-coverage": ("fn main() { let value: i32?? = present(none); match value { none => 0, present(present(_)) => 1 } }\n",
                                "type", "non-exhaustive match", (1, 47)),
    "guards-do-not-prove-coverage": ("fn main() { match true { true if true => 0, false => 1 } }\n",
                                     "type", "non-exhaustive match", (1, 13)),
    "duplicate-match-arm": ("fn main() { match true { true => 0, true => 1, false => 2 } }\n",
                            "type", "unreachable match arm", (1, 37)),
    "integer-match-gap-between-ranges": ("fn f(x: u8): i32 { match x { 0..=100 => 1, 102..=255 => 2 } }\nfn main() { 0 }\n",
                                         "type", "non-exhaustive match", (1, 20), 1),
    "adjacent-ranges-cover-later-literal": ("fn f(x: i8): i32 { match x { -128..0 => 1, 0 => 2, 1..=127 => 3, -7 => 4 } }\nfn main() { 0 }\n",
                                            "type", "unreachable match arm", (1, 66), 1),
    "guarded-integer-arm-does-not-cover": ("fn f(x: u8): i32 { match x { 0..=255 if x > 3 => 1, 7 => 2 } }\nfn main() { 0 }\n",
                                           "type", "non-exhaustive match", (1, 20), 1),
    "char-match-must-cover-both-sides-of-surrogates": ("fn f(x: char): i32 { match x { '\\u{0}'..='\\u{d7ff}' => 1, '\\u{e000}'..'\\u{10ffff}' => 2 } }\nfn main() { 0 }\n",
                                                       "type", "non-exhaustive match", (1, 22), 1),
    "outcome-keeps-error-identity": ("copy enum First { Bad }\ncopy enum Second { Bad }\nfn fail(): i32 throws First { throw First::Bad }\nfn wrong(): i32 throws Second { try fail() }\nfn main() { 0 }\n",
                                    "effects", "propagated error", (4, 33)),
    "typed-call-needs-explicit-handling": ("copy enum Error { Bad }\nfn fail(): i32 throws Error { throw Error::Bad }\nfn main() { fail() }\n",
                                          "effects", "requires try or capture", (3, 13)),
    "capture-is-not-panic-catch": ("fn main() { let value = capture (1 / 0); 0 }\n",
                                  "effects", "requires a typed throwing", (1, 25)),
    "throw-needs-declared-effect": ("copy enum Error { Bad }\nfn bad() { throw Error::Bad }\nfn main() { 0 }\n",
                                    "effects", "explicit throws", (2, 12)),
    "read-match-cannot-move-owner": ("type Owned { value: i32 }\nenum Value { Held(Owned) }\nfn consume(value: take Owned) {}\nfn main() { let value = Value::Held(Owned(42)); match value { Value::Held(item) => consume(item) }; 0 }\n",
                                    "ownership", "cannot move out of a borrowed place", (4, 92)),
    "array-repetition-must-be-copy": ("type Owned { value: i32 }\nfn main() { let values = [Owned(42); 2]; 0 }\n",
                                      "ownership", "requires Copy", (2, 26)),
    "array-constant-index-bounds": ("fn main() { let values = [42]; values[1] }\n",
                                    "type", "out of bounds", (1, 39)),
    "refutable-binding-needs-else": ("fn main() { let value: i32? = none; let present(answer) = value; answer }\n",
                                     "type", "refutable pattern", (1, 41)),
    "let-else-must-diverge": ("fn main() { let value: i32? = none; let present(answer) = value else { 0 }; answer }\n",
                             "type", "must diverge", (1, 70)),
    "nonlocal-break-must-initialize-on-every-path": ("fn choose(flag: bool) { let answer: i32; label outer: loop { loop { if flag { break label outer }; answer = 42; break label outer } }; answer }\nfn main() { choose(false) }\n",
                                                    "type", "may be uninitialized", (1, 136)),
    "loop-break-values-must-agree": ("fn choose(flag: bool) { loop { if flag { break true }; break 42 } }\nfn main() { 0 }\n",
                                    "type", "expected bool, found i32", (1, 56)),
    "bare-break-is-unit": ("fn choose(flag: bool) { loop { if flag { break }; break 42 } }\nfn main() { 0 }\n",
                           "type", "expected Unit, found i32", (1, 51)),
    "while-loop-remains-unit": ("fn main() { while true { break 42 }; 0 }\n",
                                "type", "expected Unit, found i32", (1, 26)),
    "unknown-break-label": ("fn main() { loop { break label missing 42 } }\n",
                            "name", "unknown loop label 'missing'", (1, 20)),
    "unknown-continue-label": ("fn main() { loop { continue label missing } }\n",
                               "name", "unknown loop label 'missing'", (1, 20)),
    "label-does-not-escape-loop": ("fn main() { label done: loop { break }; break label done; 0 }\n",
                                  "name", "unknown loop label 'done'", (1, 41)),
    "continue-cannot-carry-value": ("fn main() { loop { continue 42 } }\n",
                                   "parse", "continue cannot carry a value", (1, 29)),
    "loop-result-does-not-inherit-callers-type": ("fn answer() { loop { break true } }\nfn main() { let answer: i32 = answer(); 0 }\n",
                                                 "type", "expected i32, found bool", (2, 13)),
    "break-view-cannot-escape-local": ("fn main() { let view = loop { let owned = 42; break read owned }; *view }\n",
                                      "ownership", "live read loan", (1, 47)),
    "owned-break-result-cannot-borrow-loop-local": ("type Guard<region r> { value: read i32 from r; drop { let observed = *self.value } }\nfn main() { let guard = loop { let owned = 42; break Guard(read owned) }; 0 }\n",
                                                   "ownership", "live read loan", (2, 48)),
    "break-still-moves-owned-value": ("type Value { value: i32 }\nfn main() { let first = Value(42); let second = loop { break first }; first.value }\n",
                                      "ownership", "moved", (2, 71)),
    "alias-cycle": ("alias First = Second\nalias Second = First\nfn main() { 0 }\n",
                    "type", "cyclic type alias", (1, 1), 1),
    "alias-view-cycle": ("alias First = read Second\nalias Second = First\nfn main() { 0 }\n",
                         "type", "cyclic type alias", (1, 1), 1),
    "alias-recursive-product-layout": ("alias Link = Node\ntype Node { next: Link }\nfn main() { 0 }\n",
                                       "type", "recursive by-value", (2, 13), 1),
    "alias-nested-unbound-region": ("alias View = (read i32 from missing)\nfn main() { 0 }\n",
                                    "name", "unknown region", (1, 1)),
    "alias-unknown-target": ("alias Missing = Unknown\nfn main() { 0 }\n",
                             "name", "type 'Unknown'", (1, 1)),
    "alias-duplicate-name": ("type Point {}\nalias Point = i32\nfn main() { 0 }\n",
                             "name", "duplicate type", (2, 1)),
    "alias-does-not-change-nominal-identity": ("copy type First { value: i32 }\ncopy type Second { value: i32 }\nalias Same = First\nfn consume(value: Same) {}\nfn main() { consume(Second(42)); 0 }\n",
                                             "type", "expected First, found Second", (5, 21)),
    "alias-does-not-grant-copy": ("type Owned { value: i32 }\nalias Same = Owned\ncopy type Wrapper { value: Same }\nfn main() { 0 }\n",
                                 "type", "not Copy", (3, 1)),
    "alias-view-field-needs-region": ("alias View = read i32\ntype Reader { value: View }\nfn main() { 0 }\n",
                                      "type", "declared region source", (2, 15)),
    "alias-preserves-read-permission": ("alias View = read i32\nfn main() { var x = 1; let view: View = read x; *view = 2; 0 }\n",
                                        "ownership", "cannot write through a read", (2, 49), 1),
    "static-function-has-no-self": ("type Point { static fn bad() { self.value } }\nfn main() { 0 }\n",
                                    "name", "unresolved value 'self'", (1, 32), 1),
    "static-function-not-object-method": ("copy type Point { static fn make() { 42 } }\nfn main() { let point = Point(); point.make() }\n",
                                          "type", "type-qualified call", (2, 34)),
    "qualified-consuming-method-still-moves": ("type Point { value: i32; take fn consume() {} }\nalias Same = Point\nfn main() { let p = Point(42); Same::consume(p); p.value }\n",
                                              "ownership", "moved", (3, 50)),
    "qualified-mut-method-not-two-phase": ("type Counter { value: i32; fn get() { self.value }; mut fn add(value: i32) { self.value += value } }\nfn main() { var counter = Counter(1); Counter::add(counter, counter.get()); 0 }\n",
                                           "ownership", "live exclusive loan", (2, 61)),
    "qualified-drop-not-directly-callable": ("type Guard { drop {} }\nfn main() { var guard = Guard(); Guard::drop(guard); 0 }\n",
                                            "ownership", "destructor directly", (2, 34)),
    "nested-view-take-receiver": ("""
type Counter { value: i32; take fn consume() {} }
fn main() {
    let counter = Counter(42)
    let first = read counter
    let second = read first
    second.consume()
    0
}
""", "ownership", "cannot move out of a borrowed place", (7, 5)),
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
""", "ownership", "live read loan", (11, 5)),
    "self-writeback-preserves-source": ("""
copy type Reader<region r> { value: read i32 from r }
fn echo(reader: mut Reader) { reader.value = reader.value }
fn main() {
    var reader: Reader
    { let short = 42; reader = Reader(read short); echo(reader) }
    *reader.value
}
""", "ownership", "live read loan", (6, 65)),
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
""", "ownership", "live read loan", (12, 5)),
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
""", "ownership", "live read loan", (12, 62)),
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
""", "ownership", "live read loan", (11, 66)),
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
""", "ownership", "live read loan", (10, 48)),
    "wrapper-preserves-return-sources": ("""
fn first(a: read i32, b: read i32): read i32 from (a, b) { read a }
fn wrapper(a: read i32, b: read i32): read i32 from a { first(a, b) }
fn main() { 0 }
""", "ownership", "declared input sources", (3, 57)),
    "destructor-conflicts-with-derived-view": ("""
type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var value = 42
    let child: read i32
    { let guard = Guard(mut value); child = read *guard.value }
    *child
}
""", "ownership", "live read loan", (6, 63)),
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
""", "ownership", "live read loan", (8, 5)),
    "view-store-cannot-escape-local": ("copy type R<region r> { value: read i32 from r }\nfn bad(target: mut R) { let owned = 42; target.value = read owned }\nfn main() { 0 }\n",
                                      "ownership", "caller-owned storage", (2, 41), 1),
    "view-writeback-short-source": ("copy type R<region r> { value: read i32 from r }\nfn set(target: mut R, value: read i32) { target.value = read value }\nfn forward(target: mut R, value: read i32) { set(target,value) }\nfn main() { let first = 1; var target = R(read first); { let short = 2; forward(target,short) }; *target.value }\n",
                                    "ownership", "live read loan", (4, 95)),
    "call-view-content-alias": ("copy type R<region r> { value: read i32 from r }\nfn both(reader: read R, writer: mut i32) { writer = *reader.value }\nfn main() { var x = 1; let reader = R(read x); both(reader,x); 0 }\n",
                                "ownership", "live read loan", (3, 60)),
    "stored-read-mutation": ("fn main() { var x = 1; let v = read x; x = 2; *v }\n",
                             "ownership", "live read loan", (1, 40)),
    "copied-read-still-live": ("fn main() { var x = 1; let v = read x; let copied = v; x = 2; *copied }\n",
                              "ownership", "live read loan", (1, 56)),
    "exclusive-parent-suspended": ("fn main() { var x = 1; let p = mut x; let child = mut *p; *p = 2; *child }\n",
                                   "ownership", "live exclusive loan", (1, 59)),
    "exclusive-parent-moved": ("fn main() { var x = 1; let p = mut x; let child = read *p; let moved = p; *child }\n",
                               "ownership", "live read loan", (1, 72)),
    "read-view-not-writable": ("fn main() { var x = 1; let p = read x; *p = 2; 0 }\n",
                               "ownership", "write through a read", (1, 40), 1),
    "read-view-no-exclusive-upgrade": ("fn main() { var x = 1; let p = read x; let child = mut *p; 0 }\n",
                                      "ownership", "mutable place", (1, 56)),
    "view-pointee-cannot-be-moved": ("type C { value: i32 }\nfn main() { var c = C(1); let p = mut c; let moved = *p; 0 }\n",
                                    "ownership", "cannot move out of a borrowed place", (2, 54)),
    "returned-local-view": ("fn bad(source: read i32): read i32 from source { let owned = 1; read owned }\nfn main() { 0 }\n",
                            "ownership", "returned view escapes", (1, 65)),
    "returned-source-mismatch": ("fn bad(first: read i32, second: read i32): read i32 from first { read second }\nfn main() { 0 }\n",
                                 "ownership", "declared input sources", (1, 66)),
    "ambiguous-returned-view": ("fn bad(first: read i32, second: read i32): read i32 { read first }\nfn main() { 0 }\n",
                                "type", "ambiguous borrowed result", (1, 1)),
    "call-does-not-extend-temporary": ("type C { value: i32 }\nfn identity(c: C): read C from c { read c }\nfn main() { let v = identity(C(42)); v.value }\n",
                                      "ownership", "live read loan", (3, 13)),
    "returned-sources-both-live": ("fn first(a: read i32, b: read i32): read i32 from (a,b) { read a }\nfn main() { var a = 1; var b = 2; let v = first(a,b); b = 3; *v }\n",
                                   "ownership", "live read loan", (2, 55)),
    "reservation-forbids-mutation": ("type C { value: i32; mut fn add(n: i32) { self.value += n } }\nfn main() { var c = C(1); c.add({ c.value = 2; 1 }); 0 }\n",
                                     "ownership", "live exclusive loan", (2, 35)),
    "ordinary-mut-call-not-two-phase": ("type C { value: i32; fn get() { self.value } }\nfn add(c: mut C,n: i32) { c.value += n }\nfn main() { var c = C(1); add(c,c.get()); 0 }\n",
                                        "ownership", "live exclusive loan", (3, 33)),
    "activation-conflicts-with-read": ("type C { value: i32; fn view(): read i32 from self { read self.value }; mut fn add(n: read i32) { self.value += n } }\nfn main() { var c = C(1); c.add(c.view()); 0 }\n",
                                       "ownership", "live read loan", (2, 27)),
    "destructor-cannot-be-copy": ("copy type C { value: i32; drop {} }\nfn main() { 0 }\n",
                                  "type", "destructor", (1, 1)),
    "destructor-forbids-partial-move": ("type Leaf { value: i32 }\ntype C { leaf: Leaf; drop {} }\nfn main() { let c = C(Leaf(1)); let leaf = c.leaf; 0 }\n",
                                       "ownership", "partially move", (3, 44)),
    "destructor-retains-view": ("type Guard<region r> { view: read i32 from r; drop { let observed = *self.view } }\nfn main() { var x = 1; let guard = Guard(read x); x = 2; 0 }\n",
                                "ownership", "live read loan", (2, 51)),
    "destructor-not-directly-callable": ("type C { drop {} }\nfn main() { var c = C(); c.drop(); 0 }\n",
                                         "ownership", "destructor directly", (2, 26)),
    "exclusive-argument-alias": ("type C { value: i32 }\nfn both(a: mut C,b: mut C) {}\nfn main() { var c = C(1); both(c,c); 0 }\n",
                                "ownership", "live exclusive loan", (3, 34)),
    "read-exclusive-argument-alias": ("type C { value: i32 }\nfn both(a: C,b: mut C) {}\nfn main() { var c = C(1); both(c,c); 0 }\n",
                                     "ownership", "live read loan", (3, 34)),
    "mutation-during-read-argument": ("type C { value: i32 }\nfn outer(a: C,b: i32) {}\nfn change(c: mut C) { c.value += 1; 0 }\nfn main() { var c = C(1); outer(c,change(c)); 0 }\n",
                                     "ownership", "live read loan", (4, 42)),
    "parent-read-during-mut-argument": ("type C { value: i32 }\nfn outer(a: mut C,b: i32) {}\nfn main() { var c = C(1); outer(c,c.value); 0 }\n",
                                       "ownership", "live exclusive loan", (3, 35)),
    "immutable-exclusive-borrow": ("type C { value: i32 }\nfn change(c: mut C) { c.value += 1 }\nfn main() { let c = C(1); change(c); 0 }\n",
                                   "ownership", "mutable place", (3, 34)),
    "write-through-read-parameter": ("type C { value: i32 }\nfn bad(c: C) { c.value = 2 }\nfn main() { 0 }\n",
                                     "ownership", "write through a read parameter", (2, 16), 1),
    "borrowed-owned-return": ("type C { value: i32 }\nfn bad(c: C): C { c }\nfn main() { 0 }\n",
                              "ownership", "cannot move out of a borrowed place", (2, 19)),
    "take-borrowed-copy": ("fn bad(value: read i32) { let x = take value }\nfn main() { 0 }\n",
                           "ownership", "cannot move out of a borrowed place", (1, 40)),
    "read-to-mut-reborrow": ("type C { value: i32 }\nfn change(c: mut C) {}\nfn bad(c: C) { change(c) }\nfn main() { 0 }\n",
                             "ownership", "mutable place", (3, 23)),
    "use-after-move": ((Path(__file__).resolve().parents[1] / "examples/core/reject-use-after-move.mt").read_text(),
                       "ownership", "moved", (8, 5)),
    "take-copy-contract": ((Path(__file__).resolve().parents[1] / "examples/core/reject-take-copy.mt").read_text(),
                           "ownership", "moved", (7, 5)),
    "whole-partial-initialization": ("copy type P { x: i32; y: i32 }\nfn main() { let p: P; p.x = 1; let copied = p; 0 }\n",
                                      "type", "binding 'p' may be uninitialized", (2, 45)),
    "field-read-before-init": ("copy type P { x: i32 }\nfn main() { let p: P; p.x }\n",
                               "type", "binding 'p.x' may be uninitialized", (2, 23)),
    "field-double-initialization": ("copy type P { x: i32 }\nfn main() { let p: P; p.x = 1; p.x = 2; 0 }\n",
                                    "type", "immutable binding 'p.x'", (2, 32)),
    "zero-size-field-initialization": ("copy type E {}\ncopy type P { x: i32; tag: E }\nfn main() { let p: P; p.x = 0; let copied = p; 0 }\n",
                                       "type", "binding 'p' may be uninitialized", (3, 45)),
    "field-one-path-initialized": ("copy type P { x: i32 }\nfn choose(b: bool) { let p: P; if b { p.x = 42 }; p.x }\nfn main() { choose(true) }\n",
                                   "type", "binding 'p.x' may be uninitialized", (2, 51)),
    "field-loop-reassignment": ("copy type P { x: i32 }\nfn main() { let p: P; var n = 0; while n < 2 { p.x = n; n += 1 }; 0 }\n",
                                "type", "immutable binding 'p.x'", (2, 48)),
    "field-assignment-type": ("copy type P { x: i32 }\nfn main() { var p = P(0); p.x = true; 0 }\n",
                              "type", "expected i32, found bool", (2, 27)),
    "immutable-reinit-after-move": ("type P { x: i32 }\nfn main() { let p = P(1); let q = p; p = P(2); 0 }\n",
                                    "type", "immutable binding 'p'", (2, 38)),
    "loop-use-after-move": ("type P { x: i32 }\nfn main() { var p = P(1); var n = 0; while n < 2 { let q = p; n += 1 }; 0 }\n",
                            "ownership", "moved", (2, 60)),
    "conditional-use-after-move": ("type P { x: i32 }\nfn choose(flag: bool) { let p = P(42); if flag { let q = p }; p.x }\nfn main() { choose(false) }\n",
                                   "ownership", "moved", (2, 63)),
    "whole-use-after-field-take": ("copy type P { x: i32; y: i32 }\nfn main() { let p = P(20,22); let x = take p.x; let q = p; 0 }\n",
                                   "ownership", "moved", (2, 57)),
    "product-unknown-field": ("copy type P { x: i32 }\nfn main() { P(1).missing }\n", "name", "unknown field 'missing'", (2, 13)),
    "product-field-type": ("copy type P { x: i32 }\nfn main() { let p = P(true); 0 }\n", "type", "expected i32, found bool", (2, 23)),
    "product-missing-field": ("copy type P { x: i32 }\nfn main() { let p = P(); 0 }\n", "type", "argument count", (2, 21)),
    "product-duplicate-field": ("copy type P { x: i32; x: i32 }\nfn main() { 0 }\n", "name", "duplicate field", (1, 23)),
    "product-nominal-types": ("copy type A { x: i32 }\ncopy type B { x: i32 }\nfn main() { let x: A = B(1); 0 }\n", "type", "expected A, found B", (3, 13)),
    "product-recursive-layout": ("copy type A { b: B }\ncopy type B { a: A }\nfn main() { 0 }\n", "type", "no finite layout", (2, 15), 1),
    "product-noncopy-field": ("type Owner { x: i32 }\ncopy type Bad { owner: Owner }\nfn main() { 0 }\n", "type", "not Copy", (2, 1)),
    "product-implicit-comparison": ("copy type P { x: i32 }\nfn main() { if P(1) == P(1) { 0 } else { 1 } }\n", "type", "comparison interface", (2, 16)),
    "unknown-name": ("fn main(): i32 { missing }\n", "name", "unresolved value 'missing'", (1, 18)),
    "unknown-function": ("fn main(): i32 { missing() }\n", "name", "unresolved or inaccessible function 'missing'", (1, 18)),
    "unknown-type": ("fn main(): Missing { 0 }\n", "name", "unresolved or inaccessible type 'Missing'", (1, 1)),
    "wrong-return": ("fn main(): i32 { true }\n", "type", 'expected i32, found bool', (1, 16)),
    "conflicting-return": ("fn f(b: bool) { if b { return 1 }; false }\nfn main() { 0 }\n", "type", 'expected i32, found bool', (1, 15)),
    "unanchored-cycle": ("fn f() { g() }\nfn g() { f() }\nfn main(): i32 { f() }\n", "type", 'cannot infer recursive result', (2, 1)),
    "wrong-call-type": ("fn f(x: i32) { x }\nfn main() { f(true) }\n", "type", 'expected i32, found bool', (2, 15)),
    "wrong-arity": ("fn f(x: i32) { x }\nfn main() { f() }\n", "type", "missing required argument 'x'", (2, 13)),
    "duplicate-label": ("fn f(x: i32, y: i32) { x }\nfn main() { f(x: 1, x: 2) }\n", "type", 'duplicate argument', (2, 24), 1),
    "unknown-label": ("fn f(x: i32) { x }\nfn main() { f(y: 1) }\n", "type", 'unknown or excess argument', (2, 18), 1),
    "positional-after-label": ("fn f(x: i32, y: i32) { x }\nfn main() { f(y: 1, 2) }\n", "type", 'positional arguments must precede named arguments', (2, 21), 1),
    "uninitialized": ("fn main(): i32 { let x: i32; x }\n", "type", "binding 'x' may be uninitialized", (1, 30)),
    "partial-initialization": ("fn f(b: bool) { let x: i32; if b { x = 1 }; x }\nfn main() { 0 }\n", "type", "binding 'x' may be uninitialized", (1, 45)),
    "double-initialization": ("fn main() { let x = 1; x = 2; x }\n", "type", "cannot assign immutable binding 'x' more than once", (1, 24)),
    "loop-double-initialization": ("fn main() { let x: i32; var n = 0; while n < 2 { x = n; n += 1 }; 0 }\n", "type", "cannot assign immutable binding 'x' more than once", (1, 50)),
    "compound-uninitialized": ("fn main() { var x: i32; x += 1; x }\n", "type", "binding 'x' may be uninitialized", (1, 25)),
    "loop-control": ("fn main() { break; 0 }\n", "type", 'loop control outside a loop', (1, 13)),
    "duplicate-function": ("fn main() { 0 }\nfn main() { 0 }\n", "name", "duplicate function or value binding 'main'", (2, 1)),
    "duplicate-parameter": ("fn f(x: i32, x: i32) { x }\nfn main() { 0 }\n", "name", "duplicate parameter 'x'", (1, 14)),
    "wrong-entry": ("fn main(x: i32) { x }\n", "type", 'entry function must have no parameters and return i32', (1, 1)),
    "missing-entry": ("fn f() { 0 }\n", "name", "missing entry function 'main'", (1, 1)),
    "literal-range": ("fn main() { 2147483648 }\n", "type", 'integer literal is outside the i32 range', (1, 13)),
    "literal-separator": ("fn main() { 1__2 }\n", "lex", 'numeric separators must occur between digits', (1, 13)),
    "literal-suffix": ("fn main() { 42unknown }\n", "lex", 'malformed integer literal', (1, 13)),
    "negative-range": ("fn main() { -2147483649 }\n", "type", 'integer literal is outside the i32 range', (1, 14)),
    "old-arrow": ("fn main() -> i32 { 0 }\n", "parse", "function results use ': Type', not '->'", (1, 14)),
    "old-unit-type": ("fn ignored(): () {}\nfn main() { 0 }\n", "parse", 'use Unit in type positions', (1, 15)),
    "old-never-type": ("fn ignored(): never { loop {} }\nfn main() { 0 }\n", "name", "unresolved or inaccessible type 'never'", (1, 1)),
    "missing-operand": ("fn main() { 1 + }\n", "parse", 'expected an expression', (1, 17), 1),
    "missing-brace": ("fn main() { 0\n", "parse", "expected '}'", (2, 1)),
    "no-separator": ("fn main() { let x = 1 let y = 2; 0 }\n", "parse", "expected a newline or ';' between statements", (1, 23)),
    "comparison-chain": ("fn main() { if 1 < 2 < 3 { 0 } else { 1 } }\n", "parse", 'comparisons do not chain', (1, 22)),
    "newline-before-call": ("fn f() { 1 }\nfn main() { f\n() }\n", "type", "entry function", (2, 1)),
    "unterminated-comment": ("fn main() { 0 } /* missing", "lex", 'unterminated block comment', (1, 17)),
    "invalid-character": ("fn main() { $ }\n", "lex", 'unsupported character or literal', (1, 13)),
    "unused-generic-does-not-gain-copy": (
        "fn f<T>(x: T): T { x }\nfn main() { 0 }\n", "ownership", 'cannot move out of a borrowed place', (1, 20)),
    "unknown-effect-type": ("fn f() throws Error { 0 }\nfn main() { 0 }\n", "name", "type 'Error'", (1, 1)),
    "capturing-closure-cannot-coerce-to-thin-pointer": ("""
fn main(): i32 {
    let value = 42
    let pointer: fn(): i32 = fn() { value }
    pointer()
}
""", "type", "expected fn()", (4, 5)),
    "borrowed-closure-cannot-move-captured-place": ("""
type Item { value: i32 }
fn consume(item: take Item): i32 { item.value }
fn main(): i32 {
    let item = Item(42)
    let closure = fn(): i32 { consume(item) }
    closure()
}
""", "ownership", "requires a take closure", (6, 39)),
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
""", "ownership", "live read loan", (8, 5)),
    "consume-callable-bound-is-not-repeatedly-callable": ("""
fn twice<F: take fn(): i32>(operation: take F): i32 {
    operation() + operation()
}
fn answer(): i32 { 42 }
fn main(): i32 { twice(answer) }
""", "ownership", "may have been moved", (3, 19)),
    "mutating-closure-requires-exclusive-binding": ("""
fn main(): i32 {
    var value = 0
    let closure = fn(): Unit { value += 1 }
    closure()
    value
}
""", "ownership", "mutable place", (5, 5)),
    "function-pointer-access-contract-is-not-erased": ("""
fn value(input: i32): i32 { input }
fn main(): i32 {
    let pointer: fn(read i32): i32 = value
    pointer(42)
}
""", "type", "expected fn(read i32)", (4, 5)),
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
""", "ownership", "live read loan", (10, 5)),
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
""", "region", "declared relationship", (9, 5)),
    "callable-type-requires-result-annotation": ("""
fn main(): i32 {
    let closure: fn() = fn() { 42 }
    closure()
}
""", "parse", "expected ':'", (3, 23)),
    "unused-generic-body-is-checked": (
        "fn wrong<T>(value: T): i32 { value }\nfn main(): i32 { 0 }\n", "type", 'expected i32, found T', (1, 28)),
    "ordinary-copy-interface-grants-no-copy-rights": ("""
module fake { pub interface Copy {} }
fn wrong<T: fake::Copy>(value: T): T { value }
fn main(): i32 { 0 }
""", "ownership", 'cannot move out of a borrowed place', (3, 40)),
    "unused-generic-const-default-overflow": (
        "fn answer<const N:i32=2147483647+1>():i32{N}\n"
        "fn main():i32{0}\n", "type", "overflows", (1, 23)),
    "generic-array-repeat-needs-declared-copy": (
        "fn wrong<T,const N:i32>(value:take T):[T;N]{[value;N]}\n"
        "fn main():i32{0}\n", "ownership", "requires Copy", (1, 45)),
    "generic-array-loop-cannot-reuse-moved-outer-value": ("""
type Owned { value: i32 }
fn wrong<const N:i32>(values:read [i32;N], owner:take Owned):Unit {
    for value in values { let moved = take owner }
}
fn main():i32{0}
""", "ownership", "binding 'owner' may have been moved", (4, 44)),
    "unused-generic-bound-must-resolve": (
        "fn wrong<T:Missing>(value:T):Unit{()}\nfn main():i32{0}\n",
        "type", "unknown interface bound", (1, 1)),
    "interface-default-self-does-not-grant-sized": ("""
fn require_sized<T>(value: read T): Unit { () }
interface Bound<Rhs = Self> {
    fn invalid(): Unit { require_sized(self) }
}
fn main(): i32 { 0 }
""", "type", "does not satisfy Sized", (4, 26)),
    "equal-implementation-constraints-still-overlap": ("""
interface Code { fn code(): i32; }
type Box<T> { value:T }
impl<T> Box<T> implements Code where T=i32 { fn code():i32{1} }
impl<U> Box<U> implements Code where U=i32 { fn code():i32{2} }
fn main():i32{0}
""", "type", "overlapping implementations", (5, 1)),
    "missing-current-implementations-do-not-prove-disjointness": ("""
interface A {}
interface B {}
interface Code { fn code():i32; }
type Box<T> { value:T }
impl<T:A> Box<T> implements Code { fn code():i32{1} }
impl<T:B> Box<T> implements Code { fn code():i32{2} }
fn main():i32{0}
""", "type", "overlapping implementations", (7, 1)),
    "inherent-implementation-requirements-are-not-assumed": ("""
type Box<T> { value:T }
type Owned { value:i32 }
impl<T:Copy> Box<T> { fn answer():i32{42} }
fn main():i32{let value=Box(Owned(0));value.answer()}
""", "name", "unresolved", (5, 39)),
    "unconstrained-implementation-type-parameter": (
        "type Plain{}\nimpl<T> Plain{fn answer():i32{42}}\nfn main():i32{0}\n",
        "type", "unconstrained implementation parameter", (2, 1)),
    "unconstrained-implementation-const-parameter": (
        "type Plain{}\nimpl<const N:i32> Plain{fn answer():i32{N}}\n"
        "fn main():i32{0}\n", "type", "unconstrained implementation parameter", (2, 1)),
    "generic-specialization-nesting-reports-call-site": (
        "type Wrap<T>{value:T}\n"
        "fn deep<T>(value: take T, n: i32): i32 { if n == 0 {0} else { deep(Wrap(value), n - 1) } }\n"
        "fn main(): i32 { deep(1, 2) }\n",
        "limit", "generic specialization nesting limit exceeded while instantiating 'deep'", (2, 63), 1),
    "recovery-bad-pattern-leaves-no-stray-declaration": (
        "fn f(x: i32): i32 { let y = 1; match x { -y => 1, _ => 0 } }\n"
        "fn main(): i32 { f(1) }\n",
        "parse", "expected an integer literal after '-' in a pattern", (1, 43), 1),
    "recovery-reserved-binding-does-not-report-feature-use": (
        "fn main(): i32 { let macro = 1; return macro }\n",
        "parse", "expected an identifier", (1, 22), 1),
    "unsupported-pin-projection-does-not-cascade-inference": (
        "fn main(): i32 { var value: (u64)? = none; var handle = core::pin::Pin::new(mut value); "
        "let inner = handle.project_value(); 0 }\n",
        "feature", "pin projection of sum variants requires active-variant support", (1, 101), 1),
    "unrelated-inference-error-in-other-function-still-reported": (
        "fn a(): i32 { let x = nosuch(); 0 }\n"
        "fn b(): i32 { let y = none; 0 }\n"
        "fn main(): i32 { 0 }\n",
        "type", "cannot infer local type; add ': Type'", (2, 15), 2),
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
    "array-dynamic-upper-bound-large": (
        "var values=[0; 3000]; let index=3000; values[index]", "trap", "trap"),
    "array-dynamic-zero-length-bound": (
        "let values:[i32;0]=[]; let index=0; values[index]", "trap", "trap"),
    "array-dynamic-nested-inner-bound": (
        "var grid=[[0u8;300];300]; let row=299; let column=300; grid[row][column]=1u8; 0", "trap", "trap"),
    "array-dynamic-usize-negative-wrap": (
        "let values=[42]; let index=0usize-1usize; values[index]", "trap", "trap"),
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


def run_suite(mode, executable, directory, shard_index=0, shard_count=1):
    executable = str(Path(executable).resolve())
    directory = Path(directory) / mode
    if shard_count > 1:
        directory /= f"shard-{shard_index}"
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"scope": "Source regressions through the initial I06 machine boundary; not full language or release qualification",
                "status": "in_progress", "mode": mode, "compiler_sha256": digest(executable),
                "host": platform.platform(), "commands": [], "cases": []}
    if shard_count > 1:
        evidence["shard"] = {"index": shard_index, "count": shard_count}

    def run(arguments, expected=0, timeout=30):
        begin = time.perf_counter()
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=timeout)
        evidence["commands"].append({"command": list(map(str, arguments)),
                                    "exit_status": result.returncode,
                                    "elapsed_seconds": time.perf_counter() - begin,
                                    "stdout": result.stdout, "stderr": result.stderr})
        if (expected == "trap" and result.returncode != -signal.SIGABRT) or (
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
             "--profile", profile, *extra],
            timeout=180 if name.startswith("limits-stress") else 30)
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
            cases = sorted(POSITIVE.items())
            batch((case for i, case in enumerate(cases)
                   if i % shard_count == shard_index), execute_positive)
        elif mode == "negative":
            def execute_negative(item):
                name, case = item
                try:
                    text, phase, message, (line, column), *rest = case
                    count, = rest or (None,)
                except ValueError:
                    raise AssertionError(f"{name}: negative case requires (source, phase, message, "
                                         "(line, column)[, exact diagnostic count])")
                if not message:
                    raise AssertionError(f"{name}: negative case requires an intended diagnostic message")
                path = source(name, text)
                program = directory / (name + ".out")
                program.write_bytes(b"preserve existing artifact")
                profiles = ("debug", "release") if name.startswith("machine-numeric-required-") else ("debug",)
                for profile in profiles:
                    result = run([executable, "build", str(path), "-o", str(program),
                                  "--profile", profile], 1)
                    if program.read_bytes() != b"preserve existing artifact":
                        raise AssertionError(f"{name}: failed compilation damaged existing output")
                    # The phase, message and location must belong to one diagnostic.
                    intended = (re.escape(str(path)) + f":{line}:{column}: error\\[" +
                                re.escape(phase) + r"\]:[^\n]*" + re.escape(message))
                    if not re.search(intended, result.stderr):
                        raise AssertionError(
                            f"{name}: expected error[{phase}] containing {message!r} at "
                            f"{line}:{column}:\n{result.stderr}")
                    if count is not None and len(re.findall(r": error\[", result.stderr)) != count:
                        raise AssertionError(
                            f"{name}: expected exactly {count} diagnostic(s):\n{result.stderr}")
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
            for profile in ("debug", "release"):
                compile_run("generic-array-literal-index-out-of-instantiated-bound",
                            "fn pick<const N: i32>(v: read [i32;N]): i32 { v[5] }\n"
                            "fn main(): i32 { let values = [1, 2, 3]; pick(values) }\n",
                            profile, "trap")
        elif mode == "syntax":
            pure = source("no-cleanup-trampoline",
                          "fn add(a:i32,b:i32):i32 {a+b}\nfn main(){add(20,22)-42}\n")
            pure_ir = directory / "no-cleanup-trampoline.ll"
            run([executable, "build", str(pure), "--emit", "llvm", "-o", str(pure_ir)])
            if "@mettle_rt_run(" in pure_ir.read_text():
                raise AssertionError("A function without cleanup still uses the unwind trampoline")
            prefix_path = source("try-prefix-precedence",
                                 "fn f():i32 throws i32 {1}\n"
                                 "fn g():i32 throws i32 { try f() + 1 }\nfn main(){0}\n")
            prefix = json.loads(run([executable, "syntax", str(prefix_path)]).stdout)
            body = next(item for item in prefix["functions"] if item["name"] == "g")["body"]
            if body["children"][0]["text"] != "+":
                raise AssertionError("try consumed a lower-precedence binary expression")
            recovery = source("recovery-state",
                              "fn f():i32 {\n" + "let x = -------------------;\n" * 14 +
                              "let valid=1\nreturn valid\n}\nfn main(){0}\n")
            recovered = run([executable, "syntax", str(recovery)], 1)
            if "nesting limit" in recovered.stderr or recovered.stderr.count("error[") != 14:
                raise AssertionError("Parser recovery leaked nesting state")
            cascade = source("no-inference-cascade", "fn f(){1+true}\nfn main(){0}\n")
            result = run([executable, "check", str(cascade)], 1)
            if result.stderr.count("error[") != 1 or "cannot infer recursive" in result.stderr:
                raise AssertionError("An independent type error poisoned later result inference")
            pattern_cascade = source(
                "no-generic-pattern-cascade",
                "enum Slot<K, V> { Empty, Full(K, V) }\n"
                "type M<K, V> { s: Slot<K, V> }\n"
                "impl<K, V> M<K, V> {\n"
                "    fn a(): (read V from self)? {\n"
                "        let s = self.s.missing(1)\n"
                "        match s { Slot::Full(_, v) => present(read v), _ => none }\n"
                "    }\n"
                "}\nfn main(){0}\n")
            result = run([executable, "check", str(pattern_cascade)], 1)
            if result.stderr.count("error[") != 1:
                raise AssertionError("A failed scrutinee cascaded into its generic pattern")
            capped = source("reported-diagnostic-cap",
                            "".join(f"fn f{i}() {{ 1+true }}\n" for i in range(140)) +
                            "fn main(){0}\n")
            result = run([executable, "check", str(capped)], 1)
            if result.stderr.count("error[") != 100 or "40 additional diagnostics suppressed (limit 100)" not in result.stderr:
                raise AssertionError("Diagnostic cap silently discarded failures")
            visibility = source("one-visibility-diagnostic",
                                "pub(nowhere) fn f(){}\nfn main(){0}\n")
            result = run([executable, "check", str(visibility)], 1)
            if result.stderr.count("restricted visibility must name an enclosing module") != 1:
                raise AssertionError("One visibility restriction was diagnosed repeatedly")
            independent = source(
                "independent-exhaustiveness-budgets",
                "".join(f"fn f{i}(x:i32):i32 {{ match x {{\n" +
                        "".join(f"{j} => {j},\n" for j in range(128)) +
                        "_ => 0\n} }\n" for i in range(200)) + "fn main(){0}\n")
            run([executable, "check", str(independent)])
            unsupported = source("unsupported-target", "fn main(){0}\n")
            for target in ("wasm32-unknown-unknown", "armv7-unknown-linux-gnueabihf"):
                for emission in ("ir", "llvm"):
                    destination = directory / "unsupported.out"
                    destination.write_bytes(b"preserve unsupported output")
                    result = run([executable, "build", str(unsupported), "--target",
                                  target, "--emit", emission, "-o", str(destination)], 1)
                    if "error[feature]" not in result.stderr or destination.read_bytes() != b"preserve unsupported output":
                        raise AssertionError("Unsupported target escaped source admission")
            lexical = ('extern "C" { unsafe fn `type`():Unit; }\n'
                       'fn main() { unsafe { asm!("/* quoted \\"text\\" */") }; 0 }\n')
            lexical_path = source("text-and-quoted-identifiers", lexical)
            for command in ("tokens", "syntax"):
                result = run([executable, command, str(lexical_path)])
                tokens = json.loads(result.stdout)["tokens"]
                if "".join(token["text"] for token in tokens) != lexical:
                    raise AssertionError("Text/backtick tokens lost source bytes")
                for token in tokens:
                    if lexical.encode()[token["begin"]:token["end"]].decode() != token["text"]:
                        raise AssertionError("Text/backtick token has wrong byte span")
                quoted = next(token for token in tokens if token["text"] == "`type`")
                word = next(token for token in tokens if token["text"] == "extern")
                literal = next(token for token in tokens if token["text"] == '"C"')
                if len({quoted["kind"], word["kind"], literal["kind"]}) != 3:
                    raise AssertionError("Quoted identifiers/text were classified as ordinary words")
            literals = ('fn main() { let a = \'x\'; let b = \'\\u{41}\'; let c = b\'a\'; let d = b\'\\x41\';\n'
                        'let e = 1.5e+3; let f = 2f32; let g = 3.25; let h = 42; let i = 0x2a; let `type` = 1;\n'
                        'unsafe { asm!("a\\"b\\\\n\\x41", "") }; 0 }\n')
            literal_path = source("literal-token-kinds", literals)
            for command in ("tokens", "syntax"):
                tokens = json.loads(run([executable, command, str(literal_path)]).stdout)["tokens"]
                if "".join(token["text"] for token in tokens) != literals:
                    raise AssertionError("Literal tokens lost source bytes")
                kinds = {}
                for category, spellings in (
                        ("word", ("fn", "main", "let")), ("symbol", ("{", "=", ";")),
                        ("character", ("'x'", "'\\u{41}'")), ("byte", ("b'a'", "b'\\x41'")),
                        ("floating", ("1.5e+3", "2f32", "3.25")), ("integer", ("42", "0x2a")),
                        ("quoted", ("`type`",)), ("text", ('"a\\"b\\\\n\\x41"', '""'))):
                    found = {token["kind"] for token in tokens if token["text"] in spellings}
                    if len(found) != 1:
                        raise AssertionError(f"{category} tokens have inconsistent kinds {found}")
                    kinds[category] = found.pop()
                if len(set(kinds.values())) != len(kinds):
                    raise AssertionError(f"Distinct literal categories share a token kind: {kinds}")
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("positive", "negative", "arithmetic", "syntax"))
    parser.add_argument("executable")
    parser.add_argument("directory")
    parser.add_argument("--shard", default="0/1")
    args = parser.parse_args()
    try:
        index, count = map(int, args.shard.split("/"))
        if count < 1 or not 0 <= index < count or (count > 1 and args.mode != "positive"):
            raise ValueError()
    except ValueError:
        parser.error("--shard requires index/count with 0 <= index < count, for positive cases")
    run_suite(args.mode, args.executable, args.directory, index, count)
