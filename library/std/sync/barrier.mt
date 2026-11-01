import super.mutex
import super.condvar
import package.core.panic.panic
import package.core.clone.Clone
import package.core.fmt.{Debug, Error, Formatter}

type State {
    count: usize
    generation: usize
}

pub copy type BarrierWaitResult { leader: bool }
extend BarrierWaitResult implements Clone {
    fn clone(): BarrierWaitResult { BarrierWaitResult(self.leader) }
}
extend BarrierWaitResult {
    pub fn is_leader(): bool { self.leader }
}
extend BarrierWaitResult implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        var debug = try f.debug_struct("BarrierWaitResult")
        try debug.field("is_leader", read self.leader)
        try debug.finish()
    }
}

// Blocks `parties` threads until all have arrived; reusable across rounds.
pub type Barrier {
    parties: usize
    state: mutex.Mutex<State>
    arrived: condvar.Condvar
}
unsafe extend Barrier implements Transferable {}
unsafe extend Barrier implements Shareable {}

pub fn new(parties: usize): Barrier {
    if parties == 0usize { panic("barrier requires at least one party") }
    Barrier(parties, mutex.new(State(0usize, 0usize)), condvar.new())
}

extend Barrier {
    // Marks exactly one thread per round (the last to arrive) as leader.
    pub fn wait(): BarrierWaitResult {
        let locked = capture self.state.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let round = guard.get().generation
        let next = guard.get().count + 1usize
        if next >= self.parties {
            guard.get_mut().count = 0usize
            guard.get_mut().generation = match round.checked_add(1usize) {
                present(next_round) => next_round,
                none => 0usize
            }
            self.arrived.notify_all()
            return BarrierWaitResult(true)
        }
        guard.get_mut().count = next
        while guard.get().generation == round {
            guard = self.arrived.wait(guard)
        }
        BarrierWaitResult(false)
    }
}
extend Barrier implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("Barrier { .. }")
    }
}
