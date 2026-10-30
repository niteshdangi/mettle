type Grid {}
impl Grid {
    const SIDE: usize = 3usize
    const TWICE: usize = Grid::SIDE * 2usize
    static fn side(): usize { Self::SIDE }
}

type Container<T> {}
impl<T> Container<T> {
    const N: usize = 4usize
    static fn count(): usize { Self::N }
}

pub module exported {
    pub type Remote {}
    impl Remote {
        pub const SIDE: usize = 5usize
    }
}

fn main(): i32 {
    let direct: [u8; Grid::SIDE] = [1u8; Grid.SIDE]
    let second: [u8; Grid.SIDE] = [2u8; Grid::SIDE]
    if direct[2] == 1u8 && second[0] == 2u8 &&
       Grid::SIDE == 3usize && Grid::TWICE == 6usize &&
       Grid.side() == 3usize && Container::<i32>::N == 4usize &&
       Container::<u8>::count() == 4usize &&
       exported::Remote::SIDE == 5usize {
        0
    } else {
        1
    }
}
