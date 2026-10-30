// Borrowed lookup keys. `K: KeyView<Q>` says a stored key `K` can lend a
// `read Q` view of itself without allocating or retaining anything, so a
// collection keyed by `K` can be searched with a borrowed `Q` (for example a
// `String` key searched with a `Text`).
//
// Coherence contract: a `Q` view must hash and compare exactly like the `K`
// it came from. Whenever `k.key_view()` and `q` are equal under `Q: Eq`, they
// must feed identical bytes to every `Hasher` (`Q: Hash`); hash collections
// rely on this to find the stored key from the query's hash, and ordered
// collections rely on `Q: Ord` agreeing with `K: Ord`. A type relates to a
// given `Q` at most once; every type relates to itself.
import super.text.Text;

pub interface KeyView<Q: unsized> {
    fn key_view(): read Q from self;
}

// Identity: every key is its own view.
extend<T: unsized> T implements KeyView<T> {
    fn key_view(): read T from self { read self }
}
