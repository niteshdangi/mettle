// arch: x86_64

fn main() {
    unsafe {
        let left = core.arch.x86_64._mm_set1_epi32(20)
        let right = core.arch.x86_64._mm_set_epi32(22,22,22,22)
        let sum = core.arch.x86_64._mm_add_epi32(left,right)
        let lanes = core.mem.transmute::<[i32;4]>(sum)
        let original = core.mem.transmute::<[i32;4]>(left)
        if lanes[0] == 42 && lanes[3] == 42 && original[2] == 20 &&
           core.mem.size_of<core.arch.x86_64.__m128i>() == 16usize &&
           core.mem.align_of<core.arch.x86_64.__m128i>() == 16usize { 0 } else { 1 }
    }
}
