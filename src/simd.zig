const std = @import("std");
const builtin = @import("builtin");
const char_class = @import("char_class.zig");

/// Token pattern types for SIMD optimization
pub const TokenPatternType = enum {
    digit_sequence,
    alpha_sequence,
    whitespace_sequence,
    identifier_chars,
    number_chars,
};

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
    
    /// Find end of digit sequence starting at pos
    pub fn findEndOfDigitSequence(input: []const u8, start_pos: usize) usize {
        var pos = start_pos;
        while (pos < input.len and input[pos] >= '0' and input[pos] <= '9') {
            pos += 1;
        }
        return pos;
    }
    
    /// Find end of whitespace sequence starting at pos
    pub fn findEndOfWhitespaceSequence(input: []const u8, start_pos: usize) usize {
        var pos = start_pos;
        while (pos < input.len) {
            const c = input[pos];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
            pos += 1;
        }
        return pos;
    }
    
    /// Find a specific byte in input (SIMD accelerated when possible)
    pub fn findByte(input: []const u8, needle: u8) usize {
        // TODO: Implement SIMD version
        for (input, 0..) |c, i| {
            if (c == needle) return i;
        }
        return input.len; // Not found
    }
    
    /// Compare two byte arrays (SIMD accelerated when possible)
    pub fn compareBytes(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        // TODO: Implement SIMD version for larger arrays
        return std.mem.eql(u8, a, b);
    }
    
    /// SIMD-accelerated pattern matching for common token patterns
    pub fn findTokenPattern(input: []const u8, start: usize, comptime pattern_type: TokenPatternType) usize {
        const data = input[start..];
        
        if (has_sse2) {
            return switch (pattern_type) {
                .digit_sequence => findDigitSequenceSSE2(data) + start,
                .alpha_sequence => findAlphaSequenceSSE2(data) + start,
                .whitespace_sequence => findWhitespaceSequenceSSE2(data) + start,
                .identifier_chars => findIdentifierSequenceSSE2(data) + start,
                .number_chars => findNumberSequenceSSE2(data) + start,
            };
        }
        
        // Fallback to scalar implementation
        return switch (pattern_type) {
            .digit_sequence => findDigitSequenceScalar(data) + start,
            .alpha_sequence => findAlphaSequenceScalar(data) + start,
            .whitespace_sequence => findWhitespaceSequenceScalar(data) + start,
            .identifier_chars => findIdentifierSequenceScalar(data) + start,
            .number_chars => findNumberSequenceScalar(data) + start,
        };
    }
    
    /// Vectorized character classification for 16 bytes at once
    pub fn classifyChars16(bytes: *const [16]u8) [16]u8 {
        if (has_sse2) {
            return classifyChars16SSE2(bytes);
        }
        return classifyChars16Scalar(bytes);
    }
    
    /// Multiple pattern match result
    pub const MultiPatternResult = struct {
        pattern_index: u32,
        position: usize,
    };
    
    /// Find multiple patterns simultaneously using SIMD
    pub fn findMultiplePatterns(input: []const u8, start: usize, comptime patterns: []const []const u8) ?MultiPatternResult {
        if (patterns.len == 0) return null;
        
        if (has_sse2 and patterns.len <= 4) {
            return findMultiplePatternsSSE2(input, start, patterns);
        }
        
        // Fallback to sequential search
        for (patterns, 0..) |pattern, i| {
            if (std.mem.startsWith(u8, input[start..], pattern)) {
                return .{ .pattern_index = @intCast(i), .position = start };
            }
        }
        
        return null;
    }
    
    /// SIMD-accelerated string searching using Boyer-Moore-like algorithm
    pub fn findStringPattern(input: []const u8, pattern: []const u8) ?usize {
        if (pattern.len == 0) return 0;
        if (pattern.len > input.len) return null;
        
        if (has_sse2 and pattern.len <= 16) {
            return findStringPatternSSE2(input, pattern);
        }
        
        // Use std library for complex patterns
        return std.mem.indexOf(u8, input, pattern);
    }
    
    /// Advanced SIMD character set matching for up to 16 characters
    pub fn matchCharacterSet(c: u8, comptime charset: []const u8) bool {
        if (charset.len <= 16 and has_sse2) {
            return matchCharacterSetSSE2(c, charset);
        }
        
        // Fallback to lookup table or linear search
        for (charset) |char| {
            if (c == char) return true;
        }
        return false;
    }
    
    /// SIMD implementations (placeholders for now - would use actual intrinsics)
    
    fn findDigitSequenceSSE2(data: []const u8) usize {
        // Placeholder: Would use actual SSE2 intrinsics
        return findDigitSequenceScalar(data);
    }
    
    fn findAlphaSequenceSSE2(data: []const u8) usize {
        // Placeholder: Would use actual SSE2 intrinsics  
        return findAlphaSequenceScalar(data);
    }
    
    fn findWhitespaceSequenceSSE2(data: []const u8) usize {
        // Placeholder: Would use actual SSE2 intrinsics
        return findWhitespaceSequenceScalar(data);
    }
    
    fn findIdentifierSequenceSSE2(data: []const u8) usize {
        // Placeholder: Would match [a-zA-Z0-9_] using SIMD
        var pos: usize = 0;
        while (pos < data.len) {
            const c = data[pos];
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_')) {
                break;
            }
            pos += 1;
        }
        return pos;
    }
    
    fn findNumberSequenceSSE2(data: []const u8) usize {
        // Placeholder: Would match [0-9.-+eE] using SIMD for number parsing
        var pos: usize = 0;
        while (pos < data.len) {
            const c = data[pos];
            if (!((c >= '0' and c <= '9') or c == '.' or c == '-' or c == '+' or c == 'e' or c == 'E')) {
                break;
            }
            pos += 1;
        }
        return pos;
    }
    
    fn classifyChars16SSE2(bytes: *const [16]u8) [16]u8 {
        // Placeholder: Would classify 16 characters using SIMD
        var result: [16]u8 = undefined;
        for (bytes, 0..) |byte, i| {
            result[i] = @intFromEnum(char_class.char_table[byte]);
        }
        return result;
    }
    
    fn findMultiplePatternsSSE2(input: []const u8, start: usize, comptime patterns: []const []const u8) ?MultiPatternResult {
        // Placeholder: Would use SIMD to match multiple patterns simultaneously
        for (patterns, 0..) |pattern, i| {
            if (std.mem.startsWith(u8, input[start..], pattern)) {
                return .{ .pattern_index = @intCast(i), .position = start };
            }
        }
        return null;
    }
    
    fn findStringPatternSSE2(input: []const u8, pattern: []const u8) ?usize {
        // Placeholder: Would use SIMD string search
        return std.mem.indexOf(u8, input, pattern);
    }
    
    fn matchCharacterSetSSE2(c: u8, comptime charset: []const u8) bool {
        // Placeholder: Would use SIMD to match against character set
        for (charset) |char| {
            if (c == char) return true;
        }
        return false;
    }
    
    // Scalar fallback implementations
    
    fn findDigitSequenceScalar(data: []const u8) usize {
        var pos: usize = 0;
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            pos += 1;
        }
        return pos;
    }
    
    fn findAlphaSequenceScalar(data: []const u8) usize {
        var pos: usize = 0;
        while (pos < data.len) {
            const c = data[pos];
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                break;
            }
            pos += 1;
        }
        return pos;
    }
    
    fn findWhitespaceSequenceScalar(data: []const u8) usize {
        var pos: usize = 0;
        while (pos < data.len) {
            const c = data[pos];
            if (!(c == ' ' or c == '\t' or c == '\n' or c == '\r')) {
                break;
            }
            pos += 1;
        }
        return pos;
    }
    
    fn findIdentifierSequenceScalar(data: []const u8) usize {
        var pos: usize = 0;
        while (pos < data.len) {
            const c = data[pos];
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_')) {
                break;
            }
            pos += 1;
        }
        return pos;
    }
    
    fn findNumberSequenceScalar(data: []const u8) usize {
        var pos: usize = 0;
        while (pos < data.len) {
            const c = data[pos];
            if (!((c >= '0' and c <= '9') or c == '.' or c == '-' or c == '+' or c == 'e' or c == 'E')) {
                break;
            }
            pos += 1;
        }
        return pos;
    }
    
    fn classifyChars16Scalar(bytes: *const [16]u8) [16]u8 {
        var result: [16]u8 = undefined;
        for (bytes, 0..) |byte, i| {
            result[i] = @intFromEnum(char_class.char_table[byte]);
        }
        return result;
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

test "SIMD digit sequence end" {
    const input = "abc123def";
    const result = simd.findEndOfDigitSequence(input, 3);
    try std.testing.expectEqual(@as(usize, 6), result);
}

test "SIMD whitespace sequence end" {
    const input = "hello   world";
    const result = simd.findEndOfWhitespaceSequence(input, 5);
    try std.testing.expectEqual(@as(usize, 8), result);
}

test "SIMD token pattern matching" {
    // Test digit sequence detection
    const digit_input = "123abc";
    const digit_result = simd.findTokenPattern(digit_input, 0, .digit_sequence);
    try std.testing.expectEqual(@as(usize, 3), digit_result);
    
    // Test alpha sequence detection
    const alpha_input = "hello123";
    const alpha_result = simd.findTokenPattern(alpha_input, 0, .alpha_sequence);
    try std.testing.expectEqual(@as(usize, 5), alpha_result);
    
    // Test identifier sequence detection
    const id_input = "variable_name123 = value";
    const id_result = simd.findTokenPattern(id_input, 0, .identifier_chars);
    try std.testing.expectEqual(@as(usize, 16), id_result);
    
    // Test number sequence detection (including scientific notation)
    const num_input = "123.45e-6 + other";
    const num_result = simd.findTokenPattern(num_input, 0, .number_chars);
    try std.testing.expectEqual(@as(usize, 9), num_result);
}

test "SIMD character classification" {
    const test_string = "hello123 \t\n!@#$";
    var test_bytes: [16]u8 = undefined;
    @memcpy(test_bytes[0..test_string.len], test_string);
    test_bytes[test_string.len..].* = [_]u8{0} ** (16 - test_string.len);
    const result = simd.classifyChars16(&test_bytes);
    
    // Verify some expected classifications
    try std.testing.expectEqual(@intFromEnum(char_class.CharClass.alpha_lower), result[0]); // 'h'
    try std.testing.expectEqual(@intFromEnum(char_class.CharClass.digit), result[5]); // '1'
    try std.testing.expectEqual(@intFromEnum(char_class.CharClass.whitespace), result[8]); // ' '
}

test "SIMD string pattern finding" {
    const input = "hello world, hello universe";
    
    // Test finding a pattern
    const result1 = simd.findStringPattern(input, "world");
    try std.testing.expectEqual(@as(usize, 6), result1.?);
    
    // Test finding a pattern that doesn't exist
    const result2 = simd.findStringPattern(input, "galaxy");
    try std.testing.expect(result2 == null);
    
    // Test empty pattern
    const result3 = simd.findStringPattern(input, "");
    try std.testing.expectEqual(@as(usize, 0), result3.?);
}

test "SIMD multiple pattern matching" {
    const input = "function foo() { return 42; }";
    const patterns = [_][]const u8{ "function", "return", "if", "else" };
    
    // Should find "function" at position 0
    const result1 = simd.findMultiplePatterns(input, 0, &patterns);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqual(@as(u32, 0), result1.?.pattern_index);
    try std.testing.expectEqual(@as(usize, 0), result1.?.position);
    
    // Should find "return" at position 17
    const result2 = simd.findMultiplePatterns(input, 17, &patterns);
    try std.testing.expect(result2 != null);
    try std.testing.expectEqual(@as(u32, 1), result2.?.pattern_index);
    try std.testing.expectEqual(@as(usize, 17), result2.?.position);
}

test "SIMD character set matching" {
    // Test vowel matching
    try std.testing.expect(simd.matchCharacterSet('a', "aeiou"));
    try std.testing.expect(simd.matchCharacterSet('e', "aeiou"));
    try std.testing.expect(!simd.matchCharacterSet('b', "aeiou"));
    
    // Test operator matching
    try std.testing.expect(simd.matchCharacterSet('+', "+-*/%"));
    try std.testing.expect(simd.matchCharacterSet('*', "+-*/%"));
    try std.testing.expect(!simd.matchCharacterSet('=', "+-*/%"));
}