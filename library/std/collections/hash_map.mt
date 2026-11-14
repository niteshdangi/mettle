import core.clone.Clone
import core.default.Default
import core.hash.{BuildHasher, SipHasher, sip13}
import core.cell.Cell
import super.sync.tls

type ThreadSeed {
    next_k0: Cell<u64>
    k1: u64
}

fn seed_word(read bytes: [u8], offset: usize): u64 {
    var word = 0u64
    var index = 0usize
    while index < 8usize {
        let shift = (index as u32) * 8u32
        word = word | ((bytes[offset + index] as u64) << shift)
        index += 1usize
    }
    word
}

fn initialize_thread_seed(): ThreadSeed {
    var bytes = [0u8; 16]
    super.sys.fill_random_bytes(mut bytes)
    ThreadSeed(
        Cell.new(seed_word(read bytes, 0usize)),
        seed_word(read bytes, 8usize)
    )
}

fn next_thread_keys(read seed: ThreadSeed): (u64, u64) {
    let k0 = seed.next_k0.get()
    seed.next_k0.set(k0.wrapping_add(1u64))
    (k0, seed.k1)
}

static THREAD_SEED: tls.LocalKey<ThreadSeed> = tls.LocalKey(initialize_thread_seed)

pub type RandomState { k0: u64; k1: u64 }

extend RandomState {
    pub static fn new(): RandomState {
        match THREAD_SEED.with(take next_thread_keys) {
            present((k0, k1)) => RandomState(k0, k1),
            none => { core.intrinsics.abort() }
        }
    }
}

extend RandomState implements Clone {
    fn clone(): RandomState { RandomState(self.k0, self.k1) }
}

extend RandomState implements Default {
    static fn default(): RandomState { RandomState.new() }
}

extend RandomState implements BuildHasher {
    type Hasher = SipHasher
    fn build_hasher(): SipHasher { sip13(self.k0, self.k1) }
}
