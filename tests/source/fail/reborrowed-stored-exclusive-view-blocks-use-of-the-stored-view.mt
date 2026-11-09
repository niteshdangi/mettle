// expect-error: ownership 32:5 live exclusive loan

extern "C" {
    unsafe fn realloc(p: ptr<mut u8>, n: usize): ptr<mut u8>;
    unsafe fn free(p: ptr<mut u8>): Unit;
}
type List<T> { ptr: ptr<mut T>; len: usize; cap: usize
    drop { unsafe {
        var i = 0usize
        while i < self.len { core.ptr.drop_in_place(self.ptr.add(i)); i += 1usize }
        if self.cap != 0usize { free(self.ptr.cast<u8>()) }
    } }
}
extend<T> List<T> {
    mut fn push(v: take T): Unit {
        if self.len == self.cap {
            let nc = if self.cap == 0usize { 4usize } else { self.cap * 2usize }
            let np = unsafe { realloc(self.ptr.cast<u8>(), nc * core.mem.size_of<T>()) }
            self.ptr = np.cast<T>()
            self.cap = nc
        }
        unsafe { core.ptr.write(self.ptr.add(self.len), v) }
        self.len += 1usize
    }
}
fn new_vec<T>(): List<T> { List(core.ptr.null_mut<T>(), 0usize, 0usize) }
type Cursor<region r> { v: mut List<i32> from r }
fn main(): i32 {
    var v = new_vec<i32>()
    var cur = Cursor(mut v)
    let w = mut cur.v
    cur.v.push(1)
    w.push(2)
    0
}
