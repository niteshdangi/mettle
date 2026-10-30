import alloc.vec;

copy type Particle {
    x: i32
    y: i32
    vx: i32
    vy: i32
}

fn seed(): i32 { 12345 } // bench-edit-point

fn spawn(count: i32): vec.Vec<Particle> {
    var particles = vec.with_capacity<Particle>(count as usize)
    var state = seed()
    var index = 0
    while index < count {
        state = (state * 75 + 74) % 65537
        let x = state % 1000
        state = (state * 75 + 74) % 65537
        let y = state % 1000
        particles.push(Particle(x: x, y: y, vx: index % 7 - 3, vy: index % 5 - 2))
        index += 1
    }
    particles
}

fn step(particles: mut vec.Vec<Particle>) {
    var index = 0usize
    while index < particles.len() {
        let p = particles[index]
        var x = p.x + p.vx
        var y = p.y + p.vy
        var vx = p.vx
        var vy = p.vy
        if x < 0 || x >= 1000 { vx = -vx; x = p.x }
        if y < 0 || y >= 1000 { vy = -vy; y = p.y }
        particles[index] = Particle(x: x, y: y, vx: vx, vy: vy)
        index += 1usize
    }
}

fn main(): i32 {
    var particles = spawn(1000000)
    var round = 0
    while round < 200 {
        step(particles)
        round += 1
    }
    var total = 0i64
    var index = 0usize
    while index < particles.len() {
        let p = particles[index]
        total += (p.x + p.y) as i64
        index += 1usize
    }
    (total % 128i64) as i32
}
