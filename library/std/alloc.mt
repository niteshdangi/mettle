import core.fmt.{Debug, Error, Formatter}

pub import core.alloc.{GlobalAlloc, Layout, LayoutErr, LayoutError}
pub import alloc.alloc.{alloc, alloc_zeroed, dealloc, realloc}

import alloc.alloc.{alloc as system_alloc, dealloc as system_dealloc, realloc as system_realloc}

pub copy type System {}

extend System implements core.clone.Clone {
    fn clone(): System { System() }
}

extend System implements core.default.Default {
    static fn default(): System { System() }
}

extend System implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("System")
        try debug.finish()
    }
}

unsafe extend System implements GlobalAlloc {
    unsafe fn alloc(layout: Layout): ptr<mut u8> {
        unsafe { system_alloc(layout) }
    }

    unsafe fn dealloc(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe { system_dealloc(pointer, layout) }
    }

    unsafe fn realloc(pointer: ptr<mut u8>, layout: Layout, new_size: usize): ptr<mut u8> {
        unsafe { system_realloc(pointer, layout, new_size) }
    }
}
