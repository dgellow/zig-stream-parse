const std = @import("std");
const char_class = @import("char_class.zig");

pub const PatternType = enum {
    literal,
    char_class,
    range,
    any_of,
    sequence,
    one_or_more,
    zero_or_more,
    optional_pattern,
    until,
    any,
};

pub const Pattern = union(PatternType) {
    literal: []const u8,
    char_class: char_class.CharClass,
    range: struct { min: u8, max: u8 },
    any_of: []const u8,
    sequence: []const Pattern,
    one_or_more: *const Pattern,
    zero_or_more: *const Pattern,
    optional_pattern: *const Pattern,
    until: *const Pattern,
    any: void,
    
    pub fn oneOrMore(self: Pattern) Pattern {
        const ptr = &self;
        return .{ .one_or_more = ptr };
    }
    
    pub fn zeroOrMore(self: Pattern) Pattern {
        const ptr = &self;
        return .{ .zero_or_more = ptr };
    }
    
    pub fn optional(self: Pattern) Pattern {
        const ptr = &self;
        return .{ .optional_pattern = ptr };
    }
    
    pub fn then(self: Pattern, other: Pattern) Pattern {
        return .{ .sequence = &[_]Pattern{ self, other } };
    }
};

// Static patterns to avoid pointer issues
const alpha_pattern = Pattern{ .any_of = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" };
const digit_pattern = Pattern{ .char_class = .digit };
const whitespace_pattern = Pattern{ .char_class = .whitespace };

const alpha_one_or_more = Pattern{ .one_or_more = &alpha_pattern };
const digit_one_or_more = Pattern{ .one_or_more = &digit_pattern };
const whitespace_one_or_more = Pattern{ .one_or_more = &whitespace_pattern };

// Pre-defined patterns for common use cases
pub const match = struct {
    pub const alpha_lower = Pattern{ .char_class = .alpha_lower };
    pub const alpha_upper = Pattern{ .char_class = .alpha_upper };
    pub const alpha = alpha_pattern;
    pub const digit = digit_pattern;
    pub const whitespace = whitespace_pattern;
    pub const newline = Pattern{ .char_class = .newline };
    pub const punct = Pattern{ .char_class = .punct };
    pub const quote = Pattern{ .char_class = .quote };
    pub const any = Pattern{ .any = {} };
    
    pub const alphanumeric = Pattern{ 
        .any_of = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" 
    };
    
    // Common patterns
    pub const word = alpha_one_or_more;
    pub const number = digit_one_or_more;
    
    // Helper functions for building patterns
    pub fn alphaOneOrMore() Pattern {
        return alpha_one_or_more;
    }
    
    pub fn digitOneOrMore() Pattern {
        return digit_one_or_more;
    }
    
    pub fn whitespaceOneOrMore() Pattern {
        return whitespace_one_or_more;
    }
    
    pub fn literal(comptime str: []const u8) Pattern {
        return .{ .literal = str };
    }
    
    pub fn range(min: u8, max: u8) Pattern {
        return .{ .range = .{ .min = min, .max = max } };
    }
    
    pub fn anyOf(chars: []const u8) Pattern {
        return .{ .any_of = chars };
    }
    
    pub fn until(delimiter: Pattern) Pattern {
        return .{ .until = &delimiter };
    }
    
    pub fn quoted(quote_char: u8) Pattern {
        const quote_pattern = literal(&[_]u8{quote_char});
        return .{
            .sequence = &[_]Pattern{
                quote_pattern,
                until(quote_pattern),
                quote_pattern,
            },
        };
    }
};

// Pattern matching result
pub const MatchResult = struct {
    matched: bool,
    len: usize,
};

// Match a pattern against input starting at position
pub fn matchPattern(pattern: Pattern, input: []const u8, pos: usize) MatchResult {
    if (pos >= input.len) return .{ .matched = false, .len = 0 };
    
    switch (pattern) {
        .literal => |lit| {
            if (pos + lit.len > input.len) return .{ .matched = false, .len = 0 };
            if (std.mem.eql(u8, input[pos..][0..lit.len], lit)) {
                return .{ .matched = true, .len = lit.len };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .char_class => |class| {
            const c = input[pos];
            const matched = switch (class) {
                .alpha_lower => char_class.isAlphaLower(c),
                .alpha_upper => char_class.isAlphaUpper(c),
                .whitespace => char_class.isWhitespace(c),
                .digit => char_class.isDigit(c),
                .newline => char_class.isNewline(c),
                .punct => char_class.isPunct(c),
                .quote => char_class.isQuote(c),
                .other => char_class.char_table[c] == .other,
            };
            if (matched) {
                return .{ .matched = true, .len = 1 };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .range => |r| {
            const c = input[pos];
            if (c >= r.min and c <= r.max) {
                return .{ .matched = true, .len = 1 };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .any_of => |chars| {
            const c = input[pos];
            for (chars) |valid| {
                if (c == valid) return .{ .matched = true, .len = 1 };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .sequence => |seq| {
            var current_pos = pos;
            for (seq) |sub_pattern| {
                const result = matchPattern(sub_pattern, input, current_pos);
                if (!result.matched) return .{ .matched = false, .len = 0 };
                current_pos += result.len;
            }
            return .{ .matched = true, .len = current_pos - pos };
        },
        
        .one_or_more => |sub| {
            var current_pos = pos;
            var count: usize = 0;
            
            while (current_pos < input.len) {
                const result = matchPattern(sub.*, input, current_pos);
                if (!result.matched) break;
                current_pos += result.len;
                count += 1;
            }
            
            if (count > 0) {
                return .{ .matched = true, .len = current_pos - pos };
            }
            return .{ .matched = false, .len = 0 };
        },
        
        .zero_or_more => |sub| {
            var current_pos = pos;
            
            while (current_pos < input.len) {
                const result = matchPattern(sub.*, input, current_pos);
                if (!result.matched) break;
                current_pos += result.len;
            }
            
            return .{ .matched = true, .len = current_pos - pos };
        },
        
        .optional_pattern => |sub| {
            const result = matchPattern(sub.*, input, pos);
            if (result.matched) {
                return result;
            }
            return .{ .matched = true, .len = 0 };
        },
        
        .until => |delimiter| {
            var current_pos = pos;
            
            while (current_pos < input.len) {
                const delim_result = matchPattern(delimiter.*, input, current_pos);
                if (delim_result.matched) {
                    return .{ .matched = true, .len = current_pos - pos };
                }
                current_pos += 1;
            }
            
            // Reached end without finding delimiter
            return .{ .matched = true, .len = input.len - pos };
        },
        
        .any => {
            if (pos < input.len) {
                return .{ .matched = true, .len = 1 };
            }
            return .{ .matched = false, .len = 0 };
        },
    }
}

test "pattern matching" {
    const input = "hello123 world";
    
    // Test literal
    const hello_result = matchPattern(match.literal("hello"), input, 0);
    try std.testing.expect(hello_result.matched);
    try std.testing.expectEqual(@as(usize, 5), hello_result.len);
    
    // Test char class
    const alpha_result = matchPattern(match.alpha, input, 0);
    try std.testing.expect(alpha_result.matched);
    try std.testing.expectEqual(@as(usize, 1), alpha_result.len);
    
    // Test one or more
    const word_result = matchPattern(match.alpha.oneOrMore(), input, 0);
    try std.testing.expect(word_result.matched);
    try std.testing.expectEqual(@as(usize, 5), word_result.len);
    
    // Test digit
    const digit_result = matchPattern(match.digit.oneOrMore(), input, 5);
    try std.testing.expect(digit_result.matched);
    try std.testing.expectEqual(@as(usize, 3), digit_result.len);
}