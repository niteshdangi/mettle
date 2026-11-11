module inside {
    //! ```
    //! if answer() != 42 { panic("bad") }
    //! ```
    fn answer(): i32 { 42 }

    module nested {
        //! ```
        //! if answer() != 7 { panic("nested") }
        //! ```
        fn answer(): i32 { 7 }
    }
}
