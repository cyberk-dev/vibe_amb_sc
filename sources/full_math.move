module lucky_survivor::full_math {
    public fun mul_div_u64(num1: u64, num2: u64, denom: u64): u64 {
        let r = mul_div_floor(num1 as u128, num2 as u128, denom as u128);
        (r as u64)
    }

    public fun mul_div_u64_ceil(num1: u64, num2: u64, denom: u64): u64 {
        let r = mul_div_ceil(num1 as u128, num2 as u128, denom as u128);
        (r as u64)
    }

    public fun mul_div_floor(num1: u128, num2: u128, denom: u128): u128 {
        let r = full_mul(num1, num2) / (denom as u256);
        (r as u128)
    }

    public fun mul_div_round(num1: u128, num2: u128, denom: u128): u128 {
        let r = (full_mul(num1, num2) + ((denom as u256) >> 1)) / (denom as u256);
        (r as u128)
    }

    public fun mul_div_ceil(num1: u128, num2: u128, denom: u128): u128 {
        let r = (full_mul(num1, num2) + ((denom as u256) - 1)) / (denom as u256);
        (r as u128)
    }

    public fun mul_shr(num1: u128, num2: u128, shift: u8): u128 {
        let product = full_mul(num1, num2) >> shift;
        (product as u128)
    }

    public fun mul_shl(num1: u128, num2: u128, shift: u8): u128 {
        let product = full_mul(num1, num2) << shift;
        (product as u128)
    }

    public fun full_mul(num1: u128, num2: u128): u256 {
        (num1 as u256) * (num2 as u256)
    }

    public fun pow_u64(base: u64, exp: u8): u64 {
        if (exp == 0) {
            return 1;
        };

        let result = 1u64;
        let i = 0u8;
        while (i < exp) {
            result *= base;
            i += 1;
        };
        result
    }
}
