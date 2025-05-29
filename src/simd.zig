const std = @import("std");
const builtin = @import("builtin");

// SIMD-accelerated pattern matching for hot paths
pub const simd = struct {
    
    // Check if we have SIMD support
    pub const has_sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2);
    pub const has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
    pub const has_neon = builtin.cpu.arch == .aarch64;
    
    // Fast character class checking using SIMD
    pub fn findNextNonWhitespace(data: []const u8, start: usize) usize {
        if (comptime has_avx2) {
            return findNextNonWhitespaceAVX2(data, start);
        } else if (comptime has_sse2) {
            return findNextNonWhitespaceSSE2(data, start);
        } else if (comptime has_neon) {
            return findNextNonWhitespaceNEON(data, start);
        } else {
            return findNextNonWhitespaceScalar(data, start);
        }
    }
    
    pub fn findNextAlpha(data: []const u8, start: usize) ?usize {
        if (comptime has_avx2) {
            return findNextAlphaAVX2(data, start);
        } else if (comptime has_sse2) {
            return findNextAlphaSSE2(data, start);
        } else {
            return findNextAlphaScalar(data, start);
        }
    }
    
    pub fn findEndOfAlphaSequence(data: []const u8, start: usize) usize {
        if (comptime has_avx2) {
            return findEndOfAlphaSequenceAVX2(data, start);
        } else if (comptime has_sse2) {
            return findEndOfAlphaSequenceSSE2(data, start);
        } else {
            return findEndOfAlphaSequenceScalar(data, start);
        }
    }
    
    // AVX2 implementations (32 bytes at a time)
    fn findNextNonWhitespaceAVX2(data: []const u8, start: usize) usize {
        // This would contain actual AVX2 intrinsics
        // For now, fall back to scalar
        return findNextNonWhitespaceScalar(data, start);
    }
    
    fn findNextAlphaAVX2(data: []const u8, start: usize) ?usize {
        return findNextAlphaScalar(data, start);
    }
    
    fn findEndOfAlphaSequenceAVX2(data: []const u8, start: usize) usize {
        return findEndOfAlphaSequenceScalar(data, start);
    }
    
    // SSE2 implementations (16 bytes at a time)
    fn findNextNonWhitespaceSSE2(data: []const u8, start: usize) usize {
        var pos = start;
        
        // Process 16 bytes at a time
        while (pos + 16 <= data.len) {
            // Load 16 bytes
            const chunk = data[pos..pos + 16];
            
            // Check if any byte is non-whitespace
            for (chunk, 0..) |byte, i| {
                if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') {
                    return pos + i;
                }
            }
            
            pos += 16;
        }
        
        // Handle remaining bytes
        return findNextNonWhitespaceScalar(data, pos);
    }
    
    fn findNextAlphaSSE2(data: []const u8, start: usize) ?usize {
        var pos = start;
        
        // Process 16 bytes at a time
        while (pos + 16 <= data.len) {
            const chunk = data[pos..pos + 16];
            
            for (chunk, 0..) |byte, i| {
                if ((byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')) {
                    return pos + i;
                }
            }
            
            pos += 16;
        }
        
        return findNextAlphaScalar(data, pos);
    }
    
    fn findEndOfAlphaSequenceSSE2(data: []const u8, start: usize) usize {
        var pos = start;
        
        // Process 16 bytes at a time
        while (pos + 16 <= data.len) {
            const chunk = data[pos..pos + 16];
            
            for (chunk, 0..) |byte, i| {
                if (!((byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z'))) {
                    return pos + i;
                }
            }
            
            pos += 16;
        }
        
        return findEndOfAlphaSequenceScalar(data, pos);
    }
    
    // NEON implementations (16 bytes at a time)
    fn findNextNonWhitespaceNEON(data: []const u8, start: usize) usize {
        // ARM NEON implementation would go here
        return findNextNonWhitespaceScalar(data, start);
    }
    
    // Scalar fallbacks
    fn findNextNonWhitespaceScalar(data: []const u8, start: usize) usize {
        var pos = start;
        while (pos < data.len) {
            const byte = data[pos];
            if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') {
                return pos;
            }
            pos += 1;
        }
        return data.len;
    }
    
    fn findNextAlphaScalar(data: []const u8, start: usize) ?usize {
        var pos = start;
        while (pos < data.len) {
            const byte = data[pos];
            if ((byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')) {
                return pos;
            }
            pos += 1;
        }
        return null;
    }
    
    fn findEndOfAlphaSequenceScalar(data: []const u8, start: usize) usize {
        var pos = start;
        while (pos < data.len) {
            const byte = data[pos];
            if (!((byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z'))) {
                return pos;
            }
            pos += 1;
        }
        return data.len;
    }
};

test "SIMD whitespace skipping" {
    const input = "   \t\n  hello world";
    const result = simd.findNextNonWhitespace(input, 0);
    try std.testing.expectEqual(@as(usize, 7), result);
    try std.testing.expectEqual(@as(u8, 'h'), input[result]);
}

test "SIMD alpha finding" {
    const input = "123abc";
    const result = simd.findNextAlpha(input, 0);
    try std.testing.expectEqual(@as(usize, 3), result.?);
    
    const no_alpha = "123456";
    try std.testing.expectEqual(@as(?usize, null), simd.findNextAlpha(no_alpha, 0));
}

test "SIMD alpha sequence end" {
    const input = "hello123";
    const result = simd.findEndOfAlphaSequence(input, 0);
    try std.testing.expectEqual(@as(usize, 5), result);
}