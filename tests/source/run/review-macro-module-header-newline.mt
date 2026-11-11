pub module parent
{
    pub module `child_kind`
    {
        pub const VALUE: i32 = 7
        pub macro value { () => { VALUE }; }
    }
}
fn main(): i32 { parent.`child_kind`.value!() - 7 }
