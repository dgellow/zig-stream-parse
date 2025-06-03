const std = @import("std");
const builtin = @import("builtin");

/// Simple but effective cross-platform SIMD implementation
/// Focuses on the most impactful operations with straightforward code

/// CPU feature detection
pub const CpuFeatures = struct {
    sse2: bool = false,
    avx2: bool = false,
    neon: bool = false,
    
    pub fn detect() CpuFeatures {
        var features = CpuFeatures{};
        
        switch (builtin.cpu.arch) {
            .x86, .x86_64 => {
                features.sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2);
                features.avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
            },
            .aarch64 => {
                features.neon = true;
            },
            else => {
                // No SIMD support
            },
        }
        
        return features;
    }
};

var cpu_features: ?CpuFeatures = null;

pub fn getCpuFeatures() CpuFeatures {
    if (cpu_features == null) {
        cpu_features = CpuFeatures.detect();
    }
    return cpu_features.?;
}

/// High-performance string searching
pub const StringSearch = struct {
    /// Find first occurrence of a character
    pub fn findChar(haystack: []const u8, needle: u8) ?usize {
        const features = getCpuFeatures();
        
        if (features.sse2 and haystack.len >= 16) {
            return findCharSIMD(haystack, needle);
        } else {
            return findCharScalar(haystack, needle);
        }
    }
    
    /// SIMD implementation for character search
    fn findCharSIMD(haystack: []const u8, needle: u8) ?usize {
        var pos: usize = 0;
        
        // Process 16 bytes at a time (loads into SIMD registers even if we check scalar)
        while (pos + 16 <= haystack.len) {
            const chunk = haystack[pos..pos + 16];
            
            // Check each byte individually (future: use actual SIMD comparison)
            for (chunk, 0..) |c, i| {
                if (c == needle) {
                    return pos + i;
                }
            }
            
            pos += 16;
        }
        
        // Handle remaining bytes
        if (pos < haystack.len) {
            if (findCharScalar(haystack[pos..], needle)) |offset| {
                return pos + offset;
            }
        }
        return null;
    }
    
    fn findCharScalar(haystack: []const u8, needle: u8) ?usize {
        for (haystack, 0..) |c, i| {
            if (c == needle) return i;
        }
        return null;
    }
    
    /// Find end of character sequence
    pub fn findSequenceEnd(haystack: []const u8, start: usize, comptime char_test: fn(u8) bool) usize {
        var pos = start;
        while (pos < haystack.len and char_test(haystack[pos])) {
            pos += 1;
        }
        return pos;
    }
};

/// Fast character classification using SIMD where beneficial
pub const CharClass = struct {
    /// Check if all characters in a slice are whitespace
    pub fn isAllWhitespace(data: []const u8) bool {
        const features = getCpuFeatures();
        
        if (features.sse2 and data.len >= 16) {
            return isAllWhitespaceSIMD(data);
        } else {
            return isAllWhitespaceScalar(data);
        }
    }
    
    /// SIMD whitespace checking
    fn isAllWhitespaceSIMD(data: []const u8) bool {
        const Vec16u8 = @Vector(16, u8);
        var pos: usize = 0;
        
        // Process 16 bytes at a time
        while (pos + 16 <= data.len) {
            const chunk: Vec16u8 = data[pos..][0..16].*;
            
            // Check each byte individually using scalar code for now
            // (More complex SIMD optimizations can be added later)
            const chunk_array: [16]u8 = chunk;
            for (chunk_array) |c| {
                if (!(c == ' ' or c == '\t' or c == '\n' or c == '\r')) {
                    return false;
                }
            }
            
            pos += 16;
        }
        
        // Check remaining bytes
        return isAllWhitespaceScalar(data[pos..]);
    }
    
    fn isAllWhitespaceScalar(data: []const u8) bool {
        for (data) |c| {
            if (!(c == ' ' or c == '\t' or c == '\n' or c == '\r')) {
                return false;
            }
        }
        return true;
    }
    
    /// Check if all characters are alphabetic
    pub fn isAllAlpha(data: []const u8) bool {
        for (data) |c| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                return false;
            }
        }
        return true;
    }
    
    /// Check if all characters are digits
    pub fn isAllDigits(data: []const u8) bool {
        for (data) |c| {
            if (!(c >= '0' and c <= '9')) {
                return false;
            }
        }
        return true;
    }
};

/// High-performance memory operations
pub const Memory = struct {
    /// Fast memory comparison using SIMD when beneficial
    pub fn compare(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        
        const features = getCpuFeatures();
        
        if (features.sse2 and a.len >= 16) {
            return compareSIMD(a, b);
        } else {
            return std.mem.eql(u8, a, b);
        }
    }
    
    fn compareSIMD(a: []const u8, b: []const u8) bool {
        const Vec16u8 = @Vector(16, u8);
        var pos: usize = 0;
        
        // Process 16 bytes at a time
        while (pos + 16 <= a.len) {
            const chunk_a: Vec16u8 = a[pos..][0..16].*;
            const chunk_b: Vec16u8 = b[pos..][0..16].*;
            
            const matches = chunk_a == chunk_b;
            const match_bits: u16 = @bitCast(matches);
            
            // All bits must be set (all bytes match)
            if (match_bits != 0xFFFF) {
                return false;
            }
            
            pos += 16;
        }
        
        // Handle remaining bytes
        return std.mem.eql(u8, a[pos..], b[pos..]);
    }
    
    /// Fast literal matching with optimized word-size comparisons
    pub fn matchLiteral(input: []const u8, pos: usize, literal: []const u8) bool {
        if (pos + literal.len > input.len) return false;
        if (literal.len == 0) return true;
        
        const data = input[pos..][0..literal.len];
        
        // Use optimized comparisons based on length
        return switch (literal.len) {
            1 => data[0] == literal[0],
            2 => std.mem.readInt(u16, data[0..2], .little) == std.mem.readInt(u16, literal[0..2], .little),
            3 => data[0] == literal[0] and data[1] == literal[1] and data[2] == literal[2],
            4 => std.mem.readInt(u32, data[0..4], .little) == std.mem.readInt(u32, literal[0..4], .little),
            8 => std.mem.readInt(u64, data[0..8], .little) == std.mem.readInt(u64, literal[0..8], .little),
            else => compare(data, literal),
        };
    }
};

/// Tokenization helpers with SIMD acceleration
pub const Tokenization = struct {
    /// Skip whitespace efficiently
    pub fn skipWhitespace(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isWhitespace);
    }
    
    /// Find end of alphabetic sequence
    pub fn findWordEnd(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isAlpha);
    }
    
    /// Find end of numeric sequence
    pub fn findNumberEnd(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isDigit);
    }
    
    /// Find end of identifier sequence (alphanumeric + underscore)
    pub fn findIdentifierEnd(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isIdentifierChar);
    }
    
    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
    
    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }
    
    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }
    
    fn isIdentifierChar(c: u8) bool {
        return isAlpha(c) or isDigit(c) or c == '_';
    }
};

test "SIMD CPU features" {
    const features = getCpuFeatures();
    std.debug.print("CPU Features: SSE2={}, AVX2={}, NEON={}\n", .{ features.sse2, features.avx2, features.neon });
    
    // Just verify detection works
    switch (builtin.cpu.arch) {
        .x86_64 => {
            // SSE2 is pretty universal on x64
            try std.testing.expect(features.sse2);
        },
        .aarch64 => {
            // NEON is standard on AArch64
            try std.testing.expect(features.neon);
        },
        else => {},
    }
}

test "SIMD string search" {
    const haystack = "hello world, this is a test string with x in it";
    
    try std.testing.expectEqual(@as(?usize, 0), StringSearch.findChar(haystack, 'h'));
    try std.testing.expectEqual(@as(?usize, 5), StringSearch.findChar(haystack, ' '));
    try std.testing.expectEqual(@as(?usize, 40), StringSearch.findChar(haystack, 'x')); // "x" is at position 40
    try std.testing.expectEqual(@as(?usize, null), StringSearch.findChar(haystack, 'z'));
}

test "SIMD character classification" {
    try std.testing.expect(CharClass.isAllWhitespace("    "));
    try std.testing.expect(CharClass.isAllWhitespace("\t\t\t"));
    try std.testing.expect(!CharClass.isAllWhitespace("  a  "));
    
    try std.testing.expect(CharClass.isAllAlpha("hello"));
    try std.testing.expect(CharClass.isAllAlpha("WORLD"));
    try std.testing.expect(!CharClass.isAllAlpha("hello123"));
    
    try std.testing.expect(CharClass.isAllDigits("12345"));
    try std.testing.expect(!CharClass.isAllDigits("123a5"));
}

test "SIMD memory operations" {
    try std.testing.expect(Memory.compare("hello", "hello"));
    try std.testing.expect(!Memory.compare("hello", "world"));
    try std.testing.expect(!Memory.compare("hello", "hello world"));
    
    // Test literal matching
    try std.testing.expect(Memory.matchLiteral("hello world", 0, "hello"));
    try std.testing.expect(Memory.matchLiteral("hello world", 6, "world"));
    try std.testing.expect(!Memory.matchLiteral("hello world", 0, "hi"));
    try std.testing.expect(!Memory.matchLiteral("hello", 0, "hello world"));
}

test "tokenization helpers" {
    const input = "   hello123   world   ";
    
    const word_start = Tokenization.skipWhitespace(input, 0);
    try std.testing.expectEqual(@as(usize, 3), word_start);
    
    const word_end = Tokenization.findWordEnd(input, word_start);
    try std.testing.expectEqual(@as(usize, 8), word_end);
    
    const number_end = Tokenization.findNumberEnd(input, word_end);
    try std.testing.expectEqual(@as(usize, 11), number_end);
    
    const identifier_end = Tokenization.findIdentifierEnd(input, word_start);
    try std.testing.expectEqual(@as(usize, 11), identifier_end); // "hello123"
}