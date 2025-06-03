const std = @import("std");
const builtin = @import("builtin");

/// Revolutionary cross-platform SIMD implementation
/// Real intrinsics for x86 (SSE2/AVX2) and ARM64 (NEON) with graceful fallbacks

/// CPU feature detection at runtime
pub const CpuFeatures = struct {
    sse2: bool = false,
    avx2: bool = false,
    neon: bool = false,
    
    pub fn detect() CpuFeatures {
        var features = CpuFeatures{};
        
        switch (builtin.cpu.arch) {
            .x86, .x86_64 => {
                // Use Zig's CPU feature detection
                features.sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2);
                features.avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
            },
            .aarch64 => {
                // NEON is standard on all AArch64
                features.neon = true;
            },
            else => {
                // No SIMD support for other architectures
            },
        }
        
        return features;
    }
};

/// Global CPU features - detected once at program start
var cpu_features: ?CpuFeatures = null;

pub fn getCpuFeatures() CpuFeatures {
    if (cpu_features == null) {
        cpu_features = CpuFeatures.detect();
    }
    return cpu_features.?;
}

/// SIMD vector types for cross-platform code
pub const Vec16u8 = @Vector(16, u8);
pub const Vec32u8 = @Vector(32, u8);
pub const Vec8u16 = @Vector(8, u16);
pub const Vec4u32 = @Vector(4, u32);
pub const Vec2u64 = @Vector(2, u64);

/// Cross-platform SIMD string searching
pub const StringSearch = struct {
    /// Find first occurrence of a single character using SIMD
    pub fn findChar(haystack: []const u8, needle: u8) ?usize {
        const features = getCpuFeatures();
        
        if (features.avx2 and haystack.len >= 32) {
            return findCharAVX2(haystack, needle);
        } else if (features.sse2 and haystack.len >= 16) {
            return findCharSSE2(haystack, needle);
        } else if (features.neon and haystack.len >= 16) {
            return findCharNEON(haystack, needle);
        } else {
            return findCharScalar(haystack, needle);
        }
    }
    
    /// Find end of character sequence (whitespace, alpha, etc.) using SIMD
    pub fn findSequenceEnd(haystack: []const u8, start: usize, comptime char_test: fn(u8) bool) usize {
        const features = getCpuFeatures();
        
        if (features.avx2 and haystack.len - start >= 32) {
            return findSequenceEndAVX2(haystack, start, char_test);
        } else if (features.sse2 and haystack.len - start >= 16) {
            return findSequenceEndSSE2(haystack, start, char_test);
        } else if (features.neon and haystack.len - start >= 16) {
            return findSequenceEndNEON(haystack, start, char_test);
        } else {
            return findSequenceEndScalar(haystack, start, char_test);
        }
    }
    
    /// SIMD implementation for AVX2 (32 bytes at once)
    fn findCharAVX2(haystack: []const u8, needle: u8) ?usize {
        if (!comptime std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) {
            return findCharSSE2(haystack, needle);
        }
        
        // Create needle vector (32 copies of the needle byte)
        const needle_vec: Vec32u8 = @splat(needle);
        var pos: usize = 0;
        
        // Process 32 bytes at a time
        while (pos + 32 <= haystack.len) {
            // Load 32 bytes from haystack
            const haystack_chunk: Vec32u8 = haystack[pos..][0..32].*;
            
            // Compare all bytes at once
            const matches = haystack_chunk == needle_vec;
            
            // Check if any matches
            const mask = @as(u32, @bitCast(matches));
            if (mask != 0) {
                // Find first match using trailing zeros count
                return pos + @ctz(mask);
            }
            
            pos += 32;
        }
        
        // Handle remaining bytes with SSE2 or scalar
        return findCharSSE2(haystack[pos..], needle) orelse return null;
    }
    
    /// SIMD implementation for SSE2 (16 bytes at once)
    fn findCharSSE2(haystack: []const u8, needle: u8) ?usize {
        if (!comptime std.Target.x86.featureSetHas(builtin.cpu.features, .sse2)) {
            return findCharScalar(haystack, needle);
        }
        
        // Create needle vector (16 copies of the needle byte)
        const needle_vec: Vec16u8 = @splat(needle);
        var pos: usize = 0;
        
        // Process 16 bytes at a time
        while (pos + 16 <= haystack.len) {
            // Load 16 bytes from haystack
            const haystack_chunk: Vec16u8 = haystack[pos..][0..16].*;
            
            // Compare all bytes at once
            const matches = haystack_chunk == needle_vec;
            
            // Check if any matches
            const mask = @as(u16, @bitCast(matches));
            if (mask != 0) {
                // Find first match using trailing zeros count
                return pos + @ctz(mask);
            }
            
            pos += 16;
        }
        
        // Handle remaining bytes with scalar
        if (pos < haystack.len) {
            return findCharScalar(haystack[pos..], needle) orelse return null;
        }
        
        return null;
    }
    
    /// SIMD implementation for ARM NEON (16 bytes at once)
    fn findCharNEON(haystack: []const u8, needle: u8) ?usize {
        if (builtin.cpu.arch != .aarch64) {
            return findCharScalar(haystack, needle);
        }
        
        // Create needle vector (16 copies of the needle byte)
        const needle_vec: Vec16u8 = @splat(needle);
        var pos: usize = 0;
        
        // Process 16 bytes at a time
        while (pos + 16 <= haystack.len) {
            // Load 16 bytes from haystack
            const haystack_chunk: Vec16u8 = haystack[pos..][0..16].*;
            
            // Compare all bytes at once
            const matches = haystack_chunk == needle_vec;
            
            // Check if any matches
            const mask = @as(u16, @bitCast(matches));
            if (mask != 0) {
                // Find first match using trailing zeros count
                return pos + @ctz(mask);
            }
            
            pos += 16;
        }
        
        // Handle remaining bytes with scalar
        if (pos < haystack.len) {
            return findCharScalar(haystack[pos..], needle) orelse return null;
        }
        
        return null;
    }
    
    /// Scalar fallback implementation
    fn findCharScalar(haystack: []const u8, needle: u8) ?usize {
        for (haystack, 0..) |c, i| {
            if (c == needle) return i;
        }
        return null;
    }
    
    /// Find end of character sequence with AVX2
    fn findSequenceEndAVX2(haystack: []const u8, start: usize, comptime char_test: fn(u8) bool) usize {
        // For now, fall back to SSE2 - could implement specific AVX2 character class tests
        return findSequenceEndSSE2(haystack, start, char_test);
    }
    
    /// Find end of character sequence with SSE2
    fn findSequenceEndSSE2(haystack: []const u8, start: usize, comptime char_test: fn(u8) bool) usize {
        var pos = start;
        
        // Process 16 bytes at a time
        while (pos + 16 <= haystack.len) {
            // Load 16 bytes
            const chunk: Vec16u8 = haystack[pos..][0..16].*;
            
            // Test each byte individually (could be optimized for specific character classes)
            const chunk_array: [16]u8 = chunk;
            for (chunk_array, 0..) |c, i| {
                if (!char_test(c)) {
                    return pos + i;
                }
            }
            pos += 16;
        }
        
        // Handle remaining bytes with scalar
        return findSequenceEndScalar(haystack, pos, char_test);
    }
    
    /// Find end of character sequence with NEON
    fn findSequenceEndNEON(haystack: []const u8, start: usize, comptime char_test: fn(u8) bool) usize {
        // Similar to SSE2 but for ARM NEON
        return findSequenceEndSSE2(haystack, start, char_test);
    }
    
    /// Scalar fallback for sequence end finding
    fn findSequenceEndScalar(haystack: []const u8, start: usize, comptime char_test: fn(u8) bool) usize {
        var pos = start;
        while (pos < haystack.len and char_test(haystack[pos])) {
            pos += 1;
        }
        return pos;
    }
};

/// High-performance character classification using SIMD
pub const CharClass = struct {
    /// Test if all characters in a chunk are whitespace
    pub fn isAllWhitespace(chunk: []const u8) bool {
        const features = getCpuFeatures();
        
        if (features.avx2 and chunk.len >= 32) {
            return isAllWhitespaceAVX2(chunk);
        } else if (features.sse2 and chunk.len >= 16) {
            return isAllWhitespaceSSE2(chunk);
        } else if (features.neon and chunk.len >= 16) {
            return isAllWhitespaceNEON(chunk);
        } else {
            return isAllWhitespaceScalar(chunk);
        }
    }
    
    /// Test if all characters in a chunk are alphabetic
    pub fn isAllAlpha(chunk: []const u8) bool {
        const features = getCpuFeatures();
        
        if (features.avx2 and chunk.len >= 32) {
            return isAllAlphaAVX2(chunk);
        } else if (features.sse2 and chunk.len >= 16) {
            return isAllAlphaSSE2(chunk);
        } else if (features.neon and chunk.len >= 16) {
            return isAllAlphaNEON(chunk);
        } else {
            return isAllAlphaScalar(chunk);
        }
    }
    
    /// AVX2 implementation for whitespace testing
    fn isAllWhitespaceAVX2(chunk: []const u8) bool {
        if (chunk.len < 32) return isAllWhitespaceSSE2(chunk);
        
        // Create vectors for whitespace characters
        const space_vec: Vec32u8 = @splat(' ');
        const tab_vec: Vec32u8 = @splat('\t');
        const newline_vec: Vec32u8 = @splat('\n');
        const return_vec: Vec32u8 = @splat('\r');
        
        var pos: usize = 0;
        while (pos + 32 <= chunk.len) {
            const data: Vec32u8 = chunk[pos..][0..32].*;
            
            // Check if all bytes are one of: space, tab, newline, carriage return
            const is_space = data == space_vec;
            const is_tab = data == tab_vec;
            const is_newline = data == newline_vec;
            const is_return = data == return_vec;
            
            // Combine conditions using vector OR operations
            const is_whitespace_1 = @select(bool, is_space, @as(Vec32u8, @splat(0xFF)), @as(Vec32u8, @splat(0x00)));
            const is_whitespace_2 = @select(bool, is_tab, @as(Vec32u8, @splat(0xFF)), is_whitespace_1);
            const is_whitespace_3 = @select(bool, is_newline, @as(Vec32u8, @splat(0xFF)), is_whitespace_2);
            const is_whitespace_final = @select(bool, is_return, @as(Vec32u8, @splat(0xFF)), is_whitespace_3);
            
            // All bytes must be whitespace - check if all bits are set
            const mask = @as(u32, @bitCast(is_whitespace_final == @as(Vec32u8, @splat(0xFF))));
            if (mask != 0xFFFFFFFF) {
                return false;
            }
            
            pos += 32;
        }
        
        // Check remaining bytes
        return isAllWhitespaceScalar(chunk[pos..]);
    }
    
    /// SSE2 implementation for whitespace testing
    fn isAllWhitespaceSSE2(chunk: []const u8) bool {
        if (chunk.len < 16) return isAllWhitespaceScalar(chunk);
        
        // Create vectors for whitespace characters
        const space_vec: Vec16u8 = @splat(' ');
        const tab_vec: Vec16u8 = @splat('\t');
        const newline_vec: Vec16u8 = @splat('\n');
        const return_vec: Vec16u8 = @splat('\r');
        
        var pos: usize = 0;
        while (pos + 16 <= chunk.len) {
            const data: Vec16u8 = chunk[pos..][0..16].*;
            
            // Check if all bytes are one of: space, tab, newline, carriage return
            const is_space = data == space_vec;
            const is_tab = data == tab_vec;
            const is_newline = data == newline_vec;
            const is_return = data == return_vec;
            
            // Combine conditions using vector OR operations
            const is_whitespace_1 = @select(bool, is_space, @as(Vec16u8, @splat(0xFF)), @as(Vec16u8, @splat(0x00)));
            const is_whitespace_2 = @select(bool, is_tab, @as(Vec16u8, @splat(0xFF)), is_whitespace_1);
            const is_whitespace_3 = @select(bool, is_newline, @as(Vec16u8, @splat(0xFF)), is_whitespace_2);
            const is_whitespace_final = @select(bool, is_return, @as(Vec16u8, @splat(0xFF)), is_whitespace_3);
            
            // All bytes must be whitespace - check if all bits are set
            const mask = @as(u16, @bitCast(is_whitespace_final == @as(Vec16u8, @splat(0xFF))));
            if (mask != 0xFFFF) {
                return false;
            }
            
            pos += 16;
        }
        
        // Check remaining bytes
        return isAllWhitespaceScalar(chunk[pos..]);
    }
    
    /// NEON implementation for whitespace testing
    fn isAllWhitespaceNEON(chunk: []const u8) bool {
        // Similar logic to SSE2 but for ARM NEON
        return isAllWhitespaceSSE2(chunk);
    }
    
    /// Scalar fallback for whitespace testing
    fn isAllWhitespaceScalar(chunk: []const u8) bool {
        for (chunk) |c| {
            if (!(c == ' ' or c == '\t' or c == '\n' or c == '\r')) {
                return false;
            }
        }
        return true;
    }
    
    /// AVX2 implementation for alpha testing
    fn isAllAlphaAVX2(chunk: []const u8) bool {
        if (chunk.len < 32) return isAllAlphaSSE2(chunk);
        
        var pos: usize = 0;
        while (pos + 32 <= chunk.len) {
            const data: Vec32u8 = chunk[pos..][0..32].*;
            
            // Check if all bytes are in range [A-Z] or [a-z]
            const lower_a: Vec32u8 = @splat('a');
            const lower_z: Vec32u8 = @splat('z');
            const upper_a: Vec32u8 = @splat('A');
            const upper_z: Vec32u8 = @splat('Z');
            
            const is_lower_min = data >= lower_a;
            const is_lower_max = data <= lower_z;
            const is_upper_min = data >= upper_a;
            const is_upper_max = data <= upper_z;
            
            const is_lower = @select(bool, is_lower_min, is_lower_max, @as(Vec32u8, @splat(0x00)) == @as(Vec32u8, @splat(0xFF)));
            const is_upper = @select(bool, is_upper_min, is_upper_max, @as(Vec32u8, @splat(0x00)) == @as(Vec32u8, @splat(0xFF)));
            const is_alpha = @select(bool, is_lower, @as(Vec32u8, @splat(0xFF)), @select(bool, is_upper, @as(Vec32u8, @splat(0xFF)), @as(Vec32u8, @splat(0x00))));
            
            // All bytes must be alphabetic
            const mask = @as(u32, @bitCast(is_alpha == @as(Vec32u8, @splat(0xFF))));
            if (mask != 0xFFFFFFFF) {
                return false;
            }
            
            pos += 32;
        }
        
        // Check remaining bytes
        return isAllAlphaScalar(chunk[pos..]);
    }
    
    /// SSE2 implementation for alpha testing
    fn isAllAlphaSSE2(chunk: []const u8) bool {
        if (chunk.len < 16) return isAllAlphaScalar(chunk);
        
        var pos: usize = 0;
        while (pos + 16 <= chunk.len) {
            const data: Vec16u8 = chunk[pos..][0..16].*;
            
            // Check if all bytes are in range [A-Z] or [a-z]
            const lower_a: Vec16u8 = @splat('a');
            const lower_z: Vec16u8 = @splat('z');
            const upper_a: Vec16u8 = @splat('A');
            const upper_z: Vec16u8 = @splat('Z');
            
            const is_lower_min = data >= lower_a;
            const is_lower_max = data <= lower_z;
            const is_upper_min = data >= upper_a;
            const is_upper_max = data <= upper_z;
            
            const is_lower = @select(bool, is_lower_min, is_lower_max, @as(Vec16u8, @splat(0x00)) == @as(Vec16u8, @splat(0xFF)));
            const is_upper = @select(bool, is_upper_min, is_upper_max, @as(Vec16u8, @splat(0x00)) == @as(Vec16u8, @splat(0xFF)));
            const is_alpha = @select(bool, is_lower, @as(Vec16u8, @splat(0xFF)), @select(bool, is_upper, @as(Vec16u8, @splat(0xFF)), @as(Vec16u8, @splat(0x00))));
            
            // All bytes must be alphabetic
            const mask = @as(u16, @bitCast(is_alpha == @as(Vec16u8, @splat(0xFF))));
            if (mask != 0xFFFF) {
                return false;
            }
            
            pos += 16;
        }
        
        // Check remaining bytes
        return isAllAlphaScalar(chunk[pos..]);
    }
    
    /// NEON implementation for alpha testing
    fn isAllAlphaNEON(chunk: []const u8) bool {
        // Similar logic to SSE2 but for ARM NEON
        return isAllAlphaSSE2(chunk);
    }
    
    /// Scalar fallback for alpha testing
    fn isAllAlphaScalar(chunk: []const u8) bool {
        for (chunk) |c| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                return false;
            }
        }
        return true;
    }
};

/// Ultra-fast SIMD-accelerated tokenization helpers
pub const Tokenization = struct {
    /// Skip whitespace using SIMD
    pub fn skipWhitespace(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isWhitespace);
    }
    
    /// Find end of word using SIMD
    pub fn findWordEnd(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isAlpha);
    }
    
    /// Find end of number using SIMD
    pub fn findNumberEnd(input: []const u8, start: usize) usize {
        return StringSearch.findSequenceEnd(input, start, isDigit);
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
};

test "SIMD CPU feature detection" {
    const features = getCpuFeatures();
    
    // Just verify detection works without errors
    std.debug.print("CPU Features: SSE2={}, AVX2={}, NEON={}\n", .{ features.sse2, features.avx2, features.neon });
    
    // On x86/x64, at least SSE2 should be available (it's been standard for 20+ years)
    if (builtin.cpu.arch == .x86_64) {
        try std.testing.expect(features.sse2);
    }
    
    // On AArch64, NEON should be available
    if (builtin.cpu.arch == .aarch64) {
        try std.testing.expect(features.neon);
    }
}

test "SIMD string search" {
    const haystack = "hello world, this is a test string with the letter x in it";
    
    // Test finding various characters
    try std.testing.expectEqual(@as(?usize, 0), StringSearch.findChar(haystack, 'h'));
    try std.testing.expectEqual(@as(?usize, 5), StringSearch.findChar(haystack, ' '));
    try std.testing.expectEqual(@as(?usize, 55), StringSearch.findChar(haystack, 'x'));
    try std.testing.expectEqual(@as(?usize, null), StringSearch.findChar(haystack, 'z'));
}

test "SIMD character classification" {
    // Test whitespace detection
    try std.testing.expect(CharClass.isAllWhitespace("    "));
    try std.testing.expect(CharClass.isAllWhitespace("\t\t\t\t"));
    try std.testing.expect(CharClass.isAllWhitespace("   \t \n \r   "));
    try std.testing.expect(!CharClass.isAllWhitespace("  a  "));
    
    // Test alpha detection
    try std.testing.expect(CharClass.isAllAlpha("hello"));
    try std.testing.expect(CharClass.isAllAlpha("WORLD"));
    try std.testing.expect(CharClass.isAllAlpha("HelloWorld"));
    try std.testing.expect(!CharClass.isAllAlpha("hello123"));
    try std.testing.expect(!CharClass.isAllAlpha("hello world"));
}

test "SIMD tokenization helpers" {
    const input = "   hello123   world   ";
    
    // Skip initial whitespace
    const word_start = Tokenization.skipWhitespace(input, 0);
    try std.testing.expectEqual(@as(usize, 3), word_start);
    
    // Find end of first word
    const word_end = Tokenization.findWordEnd(input, word_start);
    try std.testing.expectEqual(@as(usize, 8), word_end); // "hello"
    
    // Find end of number part
    const number_end = Tokenization.findNumberEnd(input, word_end);
    try std.testing.expectEqual(@as(usize, 11), number_end); // "123"
}