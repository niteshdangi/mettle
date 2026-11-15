interface Clone: Sized { fn clone(): Self; }
interface Iterator { type Item; }
interface OwnedIterable { type IntoIter: Iterator; }

extend<T: Clone> T? implements Clone {
    fn clone(): T? {
        match self {
            present(value) => present(value.clone()),
            none => none
        }
    }
}

type Holder<U: OwnedIterable, O: Iterator<Item = U>> {
    outer: O;
    front: U.IntoIter?;
    back: U.IntoIter?;
}

type ItemHolder<I: Iterator> { item: I.Item?; }

extend<U: OwnedIterable, O: Iterator<Item = U> + Clone> Holder<U, O>
implements Clone where U.IntoIter: Clone {
    fn clone(): Holder<U, O> {
        Holder(self.outer.clone(), self.front.clone(), self.back.clone())
    }
}

extend<I: Iterator> ItemHolder<I> implements Clone where I.Item: Clone {
    fn clone(): ItemHolder<I> { ItemHolder(self.item.clone()) }
}

fn invoke_one<F: take fn(i32): i32>(take callback: F, value: i32): i32 {
    callback(value)
}

fn invoke_zero<F: take fn(): i32>(take callback: F): i32 {
    callback()
}

fn main(): i32 { 0 }
