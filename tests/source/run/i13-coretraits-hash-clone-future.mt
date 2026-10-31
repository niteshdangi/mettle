import core.clone.Clone
import core.future.Poll
import core.hash.{BuildHasher, Fnv1a, Hash, Hasher, fnv1a}

type FnvFactory {}
extend FnvFactory implements BuildHasher {
    type Hasher = Fnv1a
    fn build_hasher(): Fnv1a { fnv1a() }
}

fn main(): i32 {
    let original = 7i32
    var destination = 2i32
    destination.clone_from(read original)
    if destination != 7 { return 1 }

    var signed = fnv1a()
    signed.write_i16(-1i16)
    var bytes = fnv1a()
    let signed_bytes = [0xffu8, 0xffu8]
    bytes.write(read signed_bytes)
    if signed.finish() != bytes.finish() { return 2 }

    let values = [11i32, 12i32]
    var from_slice = FnvFactory().build_hasher()
    i32.(Hash).hash_slice(read values, mut from_slice)
    var direct = FnvFactory().build_hasher()
    values[0usize].hash(mut direct)
    values[1usize].hash(mut direct)
    if from_slice.finish() != direct.finish() { return 3 }

    let ready: Poll<(i32 throws i32)> = Poll.Ready(success(3i32))
    match take ready.map_ok(fn(value: take i32): i32 { value + 1 }) {
        Poll.Ready(result) => match result {
            success(value) => { if value != 4 { return 4 } },
            failure(error) => { return 4 }
        },
        Poll.Pending => { return 4 }
    }

    let pending: Poll<(i32 throws i32)> = Poll.Pending
    match take pending.map_err(fn(error: take i32): i32 { error + 1 }) {
        Poll.Pending => {},
        Poll.Ready(result) => { return 5 }
    }

    let ready_error: Poll<(i32 throws i32)> = Poll.Ready(failure(6i32))
    match take ready_error.map_err(fn(error: take i32): i32 { error + 1 }) {
        Poll.Ready(result) => match result {
            success(value) => { return 6 },
            failure(error) => { if error != 7 { return 6 } }
        },
        Poll.Pending => { return 6 }
    }
    0
}
