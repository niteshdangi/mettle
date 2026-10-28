#!/usr/bin/env python3
"""Execute scalar, product and ownership cases with the existing runner."""

import hashlib
import json
import platform
import re
import resource
import subprocess
import sys
import time
from pathlib import Path


POSITIVE = {
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
}

NEGATIVE = {
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
    "newline-before-call": ("fn f() { 1 }\nfn main() { f\n() }\n", "feature"),
    "unterminated-comment": ("fn main() { 0 } /* missing", "lex"),
    "invalid-character": ("fn main() { $ }\n", "lex"),
    "unsupported-generic": ("fn f<T>(x: T): T { x }\nfn main() { 0 }\n", "feature"),
    "unsupported-function-value": ("fn f() { 1 }\nfn main() { let x = f; 0 }\n", "feature"),
    "unsupported-width": ("fn f(x: i64) {}\nfn main() { 0 }\n", "feature"),
    "unsupported-u32": ("fn f(x: u32) {}\nfn main() { 0 }\n", "feature"),
    "unsupported-optional": ("fn f(x: i32?) {}\nfn main() { 0 }\n", "feature"),
    "unsupported-errors": ("fn f() throws Error { 0 }\nfn main() { 0 }\n", "feature"),
    "unsupported-break-value": ("fn main() { loop { break 42 } }\n", "feature"),
}

ARITHMETIC = {
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
    evidence = {"scope": "Scalar, products, stored/returned views, receiver borrowing and resource cleanup regressions; not full language or release qualification",
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

    try:
        if mode == "positive":
            for name, text in POSITIVE.items():
                for profile in ("debug", "release"):
                    compile_run(name, text, profile, 0)
        elif mode == "negative":
            for name, case in NEGATIVE.items():
                text, phase, *messages = case
                path = source(name, text)
                program = directory / (name + ".out")
                program.write_bytes(b"preserve existing artifact")
                result = run([executable, "build", str(path), "-o", str(program)], 1)
                if f"error[{phase}]" not in result.stderr or not re.search(
                        re.escape(str(path)) + r":\d+:\d+: error", result.stderr):
                    raise AssertionError(f"{name}: wrong/missing phase or span:\n{result.stderr}")
                if program.read_bytes() != b"preserve existing artifact":
                    raise AssertionError(f"{name}: failed compilation damaged existing output")
                if messages and messages[0] not in result.stderr:
                    raise AssertionError(f"{name}: missing intended diagnostic {messages[0]!r}\n{result.stderr}")
                evidence["cases"].append({"file": str(path), "phase": phase,
                                          "source_sha256": digest(path)})
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
