#[derive(Clone, Copy)]
struct Particle {
    x: i32,
    y: i32,
    vx: i32,
    vy: i32,
}

fn seed() -> i32 { 12345 } // bench-edit-point

fn spawn(count: i32) -> Vec<Particle> {
    let mut particles = Vec::with_capacity(count as usize);
    let mut state = seed();
    let mut index = 0;
    while index < count {
        state = (state * 75 + 74) % 65537;
        let x = state % 1000;
        state = (state * 75 + 74) % 65537;
        let y = state % 1000;
        particles.push(Particle { x, y, vx: index % 7 - 3, vy: index % 5 - 2 });
        index += 1;
    }
    particles
}

fn step(particles: &mut Vec<Particle>) {
    let mut index = 0usize;
    while index < particles.len() {
        let p = particles[index];
        let mut x = p.x + p.vx;
        let mut y = p.y + p.vy;
        let mut vx = p.vx;
        let mut vy = p.vy;
        if x < 0 || x >= 1000 {
            vx = -vx;
            x = p.x;
        }
        if y < 0 || y >= 1000 {
            vy = -vy;
            y = p.y;
        }
        particles[index] = Particle { x, y, vx, vy };
        index += 1usize;
    }
}

fn main() {
    let mut particles = spawn(1000000);
    let mut round = 0;
    while round < 200 {
        step(&mut particles);
        round += 1;
    }
    let mut total = 0i64;
    let mut index = 0usize;
    while index < particles.len() {
        let p = particles[index];
        total += (p.x + p.y) as i64;
        index += 1usize;
    }
    std::process::exit((total % 128i64) as i32);
}
