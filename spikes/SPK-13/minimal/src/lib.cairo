pub fn ping(n: u32) -> u32 {
    if n == 0 {
        return 0;
    }
    b::pong(n - 1)
}

pub mod b {
    pub fn pong(n: u32) -> u32 {
        if n == 0 {
            return 1;
        }
        super::ping(n - 1)
    }
}
