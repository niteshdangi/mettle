pub fn base(): i32 { level() }

// Selected by widget's own resolved features, not the root package's.
@cfg(feature = "fancy")
fn level(): i32 { 1 }
@cfg(not(feature = "fancy"))
fn level(): i32 { 100 }
