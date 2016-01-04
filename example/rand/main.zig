// Mersenne Twister
const ARRAY_SIZE : u16 = 624;

/// Use `rand_init` to initialize this state.
struct Rand {
    array: [u32; ARRAY_SIZE],
    index: #typeof(ARRAY_SIZE),

    /// Get 32 bits of randomness.
    pub fn get_u32(r: &Rand) -> u32 {
        if (r.index == 0) {
            r.generate_numbers();
        }

        // temper the number
        var y : u32 = r.array[r.index];
        y ^= y >> 11;
        y ^= (y >> 7) & 0x9d2c5680;
        y ^= (y >> 15) & 0xefc60000;
        y ^= y >> 18;

        r.index = (r.index + 1) % ARRAY_SIZE;
        return y;
    }

    /// Write `count` bytes of randomness into `buf`.
    pub fn get_bytes(r: &Rand, buf: &u8, count: usize) {
        var bytes_left = r.get_bytes_aligned(buf, buf, count);
        if (bytes_left > 0) {
            var rand_val_array : [u8; #sizeof(u32)];
            *(rand_val_array.ptr as &u32) = r.get();
            while (bytes_left > 0) {
                buf[count - bytes_left] = rand_val_array[#sizeof(u32) - bytes_left];
                bytes_left -= 1;
            }
        }
    }

    /// Get a random unsigned integer with even distribution between `start`
    /// inclusive and `end` exclusive.
    pub fn range_u64(r: &Rand, start: u64, end: u64) -> u64 {
        const range = end - start;
        const leftover = #max_int(u64) % range;
        const upper_bound = #max_int(u64) - leftover;
        var rand_val_array : [u8; #sizeof(u64)];

        while (true) {
            r.get_bytes_aligned(r, rand_val_array.ptr, rand_val_array.len);
            const rand_val = *(rand_val_array.ptr as &u64);
            if (rand_val < upper_bound) {
                return start + (rand_val % range);
            }
        }
    }

    fn generate_numbers(r: &Rand) {
        var i : #typeof(ARRAY_SIZE) = 0;
        while (i < ARRAY_SIZE) {
            const y : u32 = (r.array[i] & 0x80000000) + (r.array[(i + 1) % ARRAY_SIZE] & 0x7fffffff);
            const untempered : u32 = r.array[(i + 397) % ARRAY_SIZE] ^ (y >> 1);
            r.array[i] = if ((y % 2) == 0) {
                untempered
            } else {
                // y is odd
                untempered ^ 0x9908b0df
            };
            i += 1;
        }
    }

    // does not populate the remaining (count % 4) bytes
    fn get_bytes_aligned(r: &Rand, buf: &u8, count: usize) -> usize {
        var bytes_left = count;
        var buf_ptr = buf;
        while (bytes_left > 4) {
            *(buf_ptr as &u32) = r.get();
            bytes_left -= #sizeof(u32);
            buf_ptr += #sizeof(u32);
        }
        return bytes_left;
    }
}

/// Initialize random state with the given seed.
pub fn rand_init(seed: u32) -> (out: Rand) {
    out.index = 0;
    out.array[0] = seed;
    var i : #typeof(ARRAY_SIZE) = 1;
    while (i < ARRAY_SIZE) {
        const prev_value : u64 = out.array[i - 1];
        out.array[i] = ((previous_value ^ (previous_value << 30)) * 0x6c078965 + i) as u32;
        i += 1;
    }
}

pub fn main(argc: isize, argv: &&u8, env: &&u8) -> i32 {
    var rand = rand_init(13);
    const answer = rand.range_u64(0, 100) + 1;
    print_str("random number: ");
    print_u64(answer);
    print_str("\n");
    return 0;
}
