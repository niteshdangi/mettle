import package.origin
import package.relay
import core.any
import core.any.Any

fn main(): i32 {
    if any.type_id<origin.Shared>() != any.type_id<relay.Shared>() {
        return 1
    }

    let owner: heap any Any = heap origin.Shared(42)
    if !any.is<relay.Shared>(owner.get()) { return 2 }
    match any.downcast_ref<relay.Shared>(owner.get()) {
        present(value) => { if value.number() != 42 { return 3 } },
        none => { return 4 }
    }
    0
}
