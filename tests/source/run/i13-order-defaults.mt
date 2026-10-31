import core.cmp
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}

// Equal keys retain distinct identities so tie selection is observable.
type Ranked { key: i32; identity: i32 }
extend Ranked implements PartialEq {
    fn eq(other: read Ranked): bool { self.key == other.key }
}
extend Ranked implements Eq {}
extend Ranked implements PartialOrd {
    fn partial_cmp(other: read Ranked): Ordering? { present(self.cmp(other)) }
}
extend Ranked implements Ord {
    fn cmp(other: read Ranked): Ordering { self.key.cmp(read other.key) }
}

fn main(): i32 {
    if Ranked(2, 1).min(Ranked(2, 2)).identity != 1 { return 1 }
    if Ranked(2, 1).max(Ranked(2, 2)).identity != 2 { return 2 }
    if Ranked(1, 1).clamp(Ranked(2, 2), Ranked(4, 3)).identity != 2 { return 3 }
    if Ranked(5, 1).clamp(Ranked(2, 2), Ranked(4, 3)).identity != 3 { return 4 }
    if Ranked(2, 1).clamp(Ranked(2, 2), Ranked(2, 3)).identity != 1 { return 5 }
    if cmp.clamp(Ranked(3, 1), Ranked(2, 2), Ranked(4, 3)).identity != 1 { return 6 }
    0
}
