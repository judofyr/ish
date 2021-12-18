const std = @import("std");
const meta = std.meta;
const trait = meta.trait;
const autoHash = std.hash.autoHash;
const Wyhash = std.hash.Wyhash;

// This provides a variant of std.hash_map's Context which also supports a custom seed.

const hasAutoHasher = trait.hasFn("autoHash");

pub fn getAutoHashFn(comptime K: type, comptime Context: type) (fn (Context, K, usize) u64) {
    return struct {
        fn hash(ctx: Context, key: K, seed: usize) u64 {
            _ = ctx;
            if (comptime hasAutoHasher(K)) {
                var hasher = Wyhash.init(seed);
                key.autoHash(&hasher);
                return hasher.final();
            } else if (comptime trait.hasUniqueRepresentation(K)) {
                return Wyhash.hash(seed, std.mem.asBytes(&key));
            } else {
                var hasher = Wyhash.init(seed);
                autoHash(&hasher, key);
                return hasher.final();
            }
        }
    }.hash;
}

pub fn hashValue(value: anytype, seed: usize) u64 {
    const ctx = AutoContext(@TypeOf(value)){};
    return ctx.hash(value, seed);
}

pub fn AutoContext(comptime K: type) type {
    return struct {
        pub const hash = getAutoHashFn(K, @This());
        pub const eql = std.hash_map.getAutoEqlFn(K, @This());
    };
}
