type Callback<T, U, F: mut fn(take T): U> { callback: F }

extend<T, U, F: mut fn(take T): U> Callback<T, U, F> {
    mut fn apply(take input: T): U { self.callback(input) }
}

fn invoke<T, U, F: mut fn(take T): U>(take f: F, take input: T): U {
    var callback = f
    callback(input)
}

fn main(): i32 { 0 }
