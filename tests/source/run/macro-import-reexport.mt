module original {
    pub macro value { () => { 42 }; }
}

module api {
    pub import original.value
}

import api.value

fn main(): i32 { value!() - 42 }
