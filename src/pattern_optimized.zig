const std = @import("std");
const char_class = @import("char_class.zig");
const Pattern = @import("pattern.zig").Pattern;
const MatchResult = @import("pattern.zig").MatchResult;
const simd = @import("simd.zig").simd;

/// Optimized pattern matching with specialized fast paths
pub fn matchPatternOptimized(pattern: Pattern, input: []const u8, pos: usize) MatchResult {
    if (pos >= input.len) return .{ .matched = false, .len = 0 };
    
    switch (pattern) {
        .literal => |lit| {
            // Optimized literal matching with length checks first
            if (lit.len == 0) return .{ .matched = true, .len = 0 };
            if (pos + lit.len > input.len) return .{ .matched = false, .len = 0 };
            
            // Fast path for single character literals
            if (lit.len == 1) {
                return .{ 
                    .matched = input[pos] == lit[0], 
                    .len = if (input[pos] == lit[0]) 1 else 0 
                };
            }
            
            // Fast path for common 2-character literals  
            if (lit.len == 2) {
                const slice = input[pos..][0..2];
                const match = slice[0] == lit[0] and slice[1] == lit[1];
                return .{ .matched = match, .len = if (match) 2 else 0 };
            }
            
            // Use SIMD for longer literals when possible
            if (lit.len >= 4 and simd.has_sse2) {
                return matchLiteralSIMD(lit, input[pos..]);
            }
            
            // Fallback to memcmp
            if (std.mem.eql(u8, input[pos..][0..lit.len], lit)) {
                return .{ .matched = true, .len = lit.len };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .char_class => |class| {
            // Optimized character class matching using lookup tables
            const c = input[pos];
            const matched = switch (class) {
                .alpha_lower => char_class.char_table[c] == .alpha_lower,
                .alpha_upper => char_class.char_table[c] == .alpha_upper,
                .whitespace => char_class.char_table[c] == .whitespace,
                .digit => char_class.char_table[c] == .digit,
                .newline => char_class.char_table[c] == .newline,
                .punct => char_class.char_table[c] == .punct,
                .quote => char_class.char_table[c] == .quote,
                .other => char_class.char_table[c] == .other,
            };
            return .{ .matched = matched, .len = if (matched) 1 else 0 };
        },
        
        .range => |r| {
            // Optimized range checking
            const c = input[pos];
            const matched = c >= r.min and c <= r.max;
            return .{ .matched = matched, .len = if (matched) 1 else 0 };
        },
        
        .any_of => |chars| {
            // Optimized any_of with different strategies based on length
            const c = input[pos];
            
            if (chars.len <= 4) {
                // Unrolled loop for small sets
                switch (chars.len) {
                    1 => return .{ .matched = c == chars[0], .len = if (c == chars[0]) 1 else 0 },
                    2 => {
                        const match = c == chars[0] or c == chars[1];
                        return .{ .matched = match, .len = if (match) 1 else 0 };
                    },
                    3 => {
                        const match = c == chars[0] or c == chars[1] or c == chars[2];
                        return .{ .matched = match, .len = if (match) 1 else 0 };
                    },
                    4 => {
                        const match = c == chars[0] or c == chars[1] or c == chars[2] or c == chars[3];
                        return .{ .matched = match, .len = if (match) 1 else 0 };
                    },
                    else => {},
                }
            }
            
            if (chars.len >= 8) {
                // Use lookup table for larger sets
                return matchAnyOfTable(chars, c);
            }
            
            // Linear search for medium sets
            for (chars) |valid| {
                if (c == valid) return .{ .matched = true, .len = 1 };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .one_or_more => |sub| {
            // Optimized one_or_more with specialized cases
            if (isSimpleCharClass(sub.*)) {
                return matchCharClassOneOrMore(sub.*, input, pos);
            }
            
            // SIMD fast path for digit/alpha sequences
            if (isSIMDOptimizable(sub.*)) {
                return matchSIMDOneOrMore(sub.*, input, pos);
            }
            
            // Fallback to regular matching
            return matchOneOrMoreGeneric(sub.*, input, pos);
        },
        
        .zero_or_more => |sub| {
            // Similar optimizations for zero_or_more
            if (isSimpleCharClass(sub.*)) {
                const result = matchCharClassOneOrMore(sub.*, input, pos);
                return .{ .matched = true, .len = result.len }; // zero_or_more always matches
            }
            
            return matchZeroOrMoreGeneric(sub.*, input, pos);
        },
        
        .optional_pattern => |sub| {
            const result = matchPatternOptimized(sub.*, input, pos);
            return .{ .matched = true, .len = result.len }; // optional always matches
        },
        
        .sequence => |seq| {
            return matchSequenceOptimized(seq, input, pos);
        },
        
        .any => {
            return .{ .matched = true, .len = 1 };
        },
        
        .until => |delimiter| {
            return matchUntilOptimized(delimiter.*, input, pos);
        },
    }
}

// Optimized sequence matching with early exit and bounds checking
fn matchSequenceOptimized(seq: []const Pattern, input: []const u8, pos: usize) MatchResult {
    var current_pos = pos;
    
    for (seq) |sub_pattern| {
        if (current_pos >= input.len) return .{ .matched = false, .len = 0 };
        
        const result = matchPatternOptimized(sub_pattern, input, current_pos);
        if (!result.matched) return .{ .matched = false, .len = 0 };
        current_pos += result.len;
    }
    
    return .{ .matched = true, .len = current_pos - pos };
}

// Check if pattern is a simple character class for optimization
fn isSimpleCharClass(pattern: Pattern) bool {
    return switch (pattern) {
        .char_class => true,
        .range => true,
        .any_of => |chars| chars.len <= 16, // Small sets are simple
        else => false,
    };
}

// Check if pattern can be SIMD optimized
fn isSIMDOptimizable(pattern: Pattern) bool {
    if (!simd.has_sse2) return false;
    
    return switch (pattern) {
        .char_class => |class| switch (class) {
            .digit, .alpha_lower, .alpha_upper, .whitespace => true,
            else => false,
        },
        else => false,
    };
}

// Optimized character class one_or_more using lookup table
fn matchCharClassOneOrMore(pattern: Pattern, input: []const u8, pos: usize) MatchResult {
    var current_pos = pos;
    var count: usize = 0;
    
    while (current_pos < input.len) {
        const c = input[current_pos];
        var matched = false;
        
        switch (pattern) {
            .char_class => |class| {
                matched = switch (class) {
                    .alpha_lower => char_class.char_table[c] == .alpha_lower,
                    .alpha_upper => char_class.char_table[c] == .alpha_upper,
                    .whitespace => char_class.char_table[c] == .whitespace,
                    .digit => char_class.char_table[c] == .digit,
                    .newline => char_class.char_table[c] == .newline,
                    .punct => char_class.char_table[c] == .punct,
                    .quote => char_class.char_table[c] == .quote,
                    .other => char_class.char_table[c] == .other,
                };
            },
            .range => |r| {
                matched = c >= r.min and c <= r.max;
            },
            .any_of => |chars| {
                for (chars) |valid| {
                    if (c == valid) {
                        matched = true;
                        break;
                    }
                }
            },
            else => unreachable,
        }
        
        if (!matched) break;
        current_pos += 1;
        count += 1;
    }
    
    if (count > 0) {
        return .{ .matched = true, .len = current_pos - pos };
    }
    return .{ .matched = false, .len = 0 };
}

// SIMD-accelerated one_or_more for specific patterns
fn matchSIMDOneOrMore(pattern: Pattern, input: []const u8, pos: usize) MatchResult {
    const remaining = input[pos..];
    if (remaining.len == 0) return .{ .matched = false, .len = 0 };
    
    switch (pattern) {
        .char_class => |class| {
            switch (class) {
                .digit => {
                    const end_pos = simd.findEndOfDigitSequence(input, pos);
                    const len = end_pos - pos;
                    return .{ .matched = len > 0, .len = len };
                },
                .alpha_lower, .alpha_upper => {
                    const end_pos = simd.findEndOfAlphaSequence(input, pos);
                    const len = end_pos - pos;
                    return .{ .matched = len > 0, .len = len };
                },
                .whitespace => {
                    const end_pos = simd.findEndOfWhitespaceSequence(input, pos);
                    const len = end_pos - pos;
                    return .{ .matched = len > 0, .len = len };
                },
                else => return matchCharClassOneOrMore(pattern, input, pos),
            }
        },
        else => return matchCharClassOneOrMore(pattern, input, pos),
    }
}

// Generic one_or_more fallback
fn matchOneOrMoreGeneric(pattern: Pattern, input: []const u8, pos: usize) MatchResult {
    var current_pos = pos;
    var count: usize = 0;
    
    while (current_pos < input.len) {
        const result = matchPatternOptimized(pattern, input, current_pos);
        if (!result.matched) break;
        current_pos += result.len;
        count += 1;
        
        // Prevent infinite loops on zero-length matches
        if (result.len == 0) break;
    }
    
    if (count > 0) {
        return .{ .matched = true, .len = current_pos - pos };
    }
    return .{ .matched = false, .len = 0 };
}

// Generic zero_or_more fallback
fn matchZeroOrMoreGeneric(pattern: Pattern, input: []const u8, pos: usize) MatchResult {
    var current_pos = pos;
    
    while (current_pos < input.len) {
        const result = matchPatternOptimized(pattern, input, current_pos);
        if (!result.matched) break;
        current_pos += result.len;
        
        // Prevent infinite loops on zero-length matches
        if (result.len == 0) break;
    }
    
    return .{ .matched = true, .len = current_pos - pos };
}

// Optimized until matching with SIMD search
fn matchUntilOptimized(delimiter: Pattern, input: []const u8, pos: usize) MatchResult {
    // For single character delimiters, use SIMD search
    if (delimiter == .literal and delimiter.literal.len == 1) {
        const needle = delimiter.literal[0];
        const remaining = input[pos..];
        
        // Use SIMD to find the delimiter
        if (simd.has_sse2 and remaining.len >= 16) {
            const found_pos = simd.findByte(remaining, needle);
            if (found_pos < remaining.len) {
                return .{ .matched = true, .len = found_pos };
            }
            return .{ .matched = true, .len = remaining.len };
        }
        
        // Fallback to std.mem.indexOfScalar
        if (std.mem.indexOfScalar(u8, remaining, needle)) |found| {
            return .{ .matched = true, .len = found };
        }
        return .{ .matched = true, .len = remaining.len };
    }
    
    // Generic until implementation
    var current_pos = pos;
    while (current_pos < input.len) {
        const result = matchPatternOptimized(delimiter, input, current_pos);
        if (result.matched) break;
        current_pos += 1;
    }
    
    return .{ .matched = true, .len = current_pos - pos };
}

// Optimized any_of using lookup table for large character sets
fn matchAnyOfTable(chars: []const u8, c: u8) MatchResult {
    // Build a lookup table for this character set
    var table = [_]bool{false} ** 256;
    for (chars) |char| {
        table[char] = true;
    }
    
    return .{ .matched = table[c], .len = if (table[c]) 1 else 0 };
}

// SIMD literal matching for longer strings
fn matchLiteralSIMD(literal: []const u8, input: []const u8) MatchResult {
    if (literal.len > input.len) return .{ .matched = false, .len = 0 };
    
    // Use SIMD comparison for aligned data
    if (simd.has_sse2 and literal.len >= 16) {
        const matches = simd.compareBytes(input[0..literal.len], literal);
        return .{ .matched = matches, .len = if (matches) literal.len else 0 };
    }
    
    // Fallback to regular comparison
    if (std.mem.eql(u8, input[0..literal.len], literal)) {
        return .{ .matched = true, .len = literal.len };
    }
    return .{ .matched = false, .len = 0 };
}

// Add these missing SIMD functions to simd.zig if they don't exist
// These would be implemented with actual SIMD instructions

test "optimized pattern matching" {
    const input = "hello123world";
    
    // Test optimized digit matching
    const digit_pattern = Pattern{ .char_class = .digit };
    const result = matchPatternOptimized(digit_pattern.oneOrMore(), input, 5);
    
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.len);
}

test "optimized literal matching" {
    const input = "hello world";
    
    // Test single character literal
    const space_pattern = Pattern{ .literal = " " };
    const result = matchPatternOptimized(space_pattern, input, 5);
    
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 1), result.len);
}

test "optimized any_of matching" {
    const input = "abc123";
    
    // Test small any_of set
    const vowel_pattern = Pattern{ .any_of = "aeiou" };
    const result = matchPatternOptimized(vowel_pattern, input, 0);
    
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 1), result.len);
}