import super.mutex;
import super.condvar;

type State {
    count: usize
    generation: usize
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
    Barrier(parties, mutex.new(State(0usize, 0usize)), condvar.new())
}

extend Barrier {
    // Returns true for exactly one thread per round (the last to arrive).
    pub fn wait(): bool {
        let locked = capture self.state.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let round = guard.get().generation
        let next = guard.get().count + 1usize
        if next >= self.parties {
            guard.get_mut().count = 0usize
            guard.get_mut().generation = round + 1usize
            self.arrived.notify_all()
            return true
        }
        guard.get_mut().count = next
        while guard.get().generation == round {
            guard = self.arrived.wait(guard)
        }
        false
    }
}
