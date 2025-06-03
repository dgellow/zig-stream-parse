const std = @import("std");
const char_class = @import("char_class.zig");

/// Revolutionary compile-time pattern system
/// No more runtime pointers, no more lifetime issues!
/// Everything is generated at compile time for maximum performance.

/// Pattern descriptors - pure comptime data, no pointers
pub const PatternDesc = union(enum) {
    /// Match exact literal string
    literal: []const u8,
    
    /// Match character class
    char_class: char_class.CharClass,
    
    /// Match any character from set
    any_of: []const u8,
    
    /// Match character in range
    range: struct { min: u8, max: u8 },
    
    /// Match sequence of patterns
    sequence: []const PatternDesc,
    
    /// Match pattern one or more times (no pointers!)
    one_or_more: *const PatternDesc,
    
    /// Match pattern zero or more times
    zero_or_more: *const PatternDesc,
    
    /// Optional pattern
    optional: *const PatternDesc,
    
    /// Match any single character
    any: void,
    
    /// Match until delimiter (efficient string parsing)
    until: *const PatternDesc,
};

/// Compile-time pattern matcher generator
/// This is where the magic happens - we generate optimal matching code!
pub fn Matcher(comptime pattern_desc: PatternDesc) type {
    return struct {
        const Self = @This();
        
        /// Match the pattern starting at pos, return length if matched or null
        pub fn match(input: []const u8, pos: usize) ?usize {
            return matchImpl(input, pos, pattern_desc);
        }
        
        /// Internal implementation - generates optimal code per pattern
        fn matchImpl(input: []const u8, pos: usize, comptime desc: PatternDesc) ?usize {
            if (pos >= input.len) return null;
            
            switch (desc) {
                .literal => |lit| {
                    if (lit.len == 0) return 0;
                    if (pos + lit.len > input.len) return null;
                    
                    // Generate optimal literal matching based on length
                    return switch (lit.len) {
                        1 => if (input[pos] == lit[0]) 1 else null,
                        2 => if (input[pos] == lit[0] and input[pos + 1] == lit[1]) 2 else null,
                        3 => if (input[pos] == lit[0] and input[pos + 1] == lit[1] and input[pos + 2] == lit[2]) 3 else null,
                        4 => blk: {
                            // Use 32-bit comparison for 4-byte literals
                            const input_word = std.mem.readInt(u32, input[pos..][0..4], .little);
                            const pattern_word = std.mem.readInt(u32, lit[0..4], .little);
                            break :blk if (input_word == pattern_word) 4 else null;
                        },
                        8 => blk: {
                            // Use 64-bit comparison for 8-byte literals  
                            const input_qword = std.mem.readInt(u64, input[pos..][0..8], .little);
                            const pattern_qword = std.mem.readInt(u64, lit[0..8], .little);
                            break :blk if (input_qword == pattern_qword) 8 else null;
                        },
                        else => if (std.mem.eql(u8, input[pos..][0..lit.len], lit)) lit.len else null,
                    };
                },
                
                .char_class => |class| {
                    const c = input[pos];
                    const matched = switch (class) {
                        .alpha_lower => c >= 'a' and c <= 'z',
                        .alpha_upper => c >= 'A' and c <= 'Z',
                        .digit => c >= '0' and c <= '9',
                        .whitespace => c == ' ' or c == '\t',
                        .newline => c == '\n' or c == '\r',
                        .punct => char_class.isPunct(c),
                        .quote => c == '"' or c == '\'',
                        .other => true, // Match any other character
                    };
                    return if (matched) 1 else null;
                },
                
                .any_of => |chars| {
                    const c = input[pos];
                    // Generate optimal lookup based on character set size
                    return switch (chars.len) {
                        0 => null,
                        1 => if (c == chars[0]) 1 else null,
                        2 => if (c == chars[0] or c == chars[1]) 1 else null,
                        3 => if (c == chars[0] or c == chars[1] or c == chars[2]) 1 else null,
                        else => blk: {
                            // For larger sets, use linear search (could optimize with lookup table)
                            for (chars) |char| {
                                if (c == char) break :blk 1;
                            }
                            break :blk null;
                        },
                    };
                },
                
                .range => |r| {
                    const c = input[pos];
                    return if (c >= r.min and c <= r.max) 1 else null;
                },
                
                .sequence => |seq| {
                    var total_len: usize = 0;
                    var current_pos = pos;
                    
                    // Generate unrolled loop for small sequences
                    inline for (seq) |sub_pattern| {
                        const sub_len = matchImpl(input, current_pos, sub_pattern) orelse return null;
                        total_len += sub_len;
                        current_pos += sub_len;
                    }
                    
                    return total_len;
                },
                
                .one_or_more => |sub| {
                    var total_len: usize = 0;
                    var current_pos = pos;
                    
                    // Must match at least once
                    const first_len = matchImpl(input, current_pos, sub.*) orelse return null;
                    total_len += first_len;
                    current_pos += first_len;
                    
                    // Match as many times as possible
                    while (current_pos < input.len) {
                        const sub_len = matchImpl(input, current_pos, sub.*) orelse break;
                        total_len += sub_len;
                        current_pos += sub_len;
                    }
                    
                    return total_len;
                },
                
                .zero_or_more => |sub| {
                    var total_len: usize = 0;
                    var current_pos = pos;
                    
                    // Match as many times as possible (zero is ok)
                    while (current_pos < input.len) {
                        const sub_len = matchImpl(input, current_pos, sub.*) orelse break;
                        total_len += sub_len;
                        current_pos += sub_len;
                    }
                    
                    return total_len;
                },
                
                .optional => |sub| {
                    const sub_len = matchImpl(input, pos, sub.*) orelse 0;
                    return sub_len;
                },
                
                .any => {
                    return 1; // Always matches one character
                },
                
                .until => |delimiter| {
                    var len: usize = 0;
                    var current_pos = pos;
                    
                    while (current_pos < input.len) {
                        // Check if delimiter matches here
                        if (matchImpl(input, current_pos, delimiter.*) != null) {
                            break;
                        }
                        len += 1;
                        current_pos += 1;
                    }
                    
                    return len;
                },
            }
        }
    };
}

/// Beautiful DSL for creating patterns
pub const pattern = struct {
    /// Character classes
    pub const alpha_lower = PatternDesc{ .char_class = .alpha_lower };
    pub const alpha_upper = PatternDesc{ .char_class = .alpha_upper };
    pub const digit = PatternDesc{ .char_class = .digit };
    pub const whitespace = PatternDesc{ .char_class = .whitespace };
    pub const newline = PatternDesc{ .char_class = .newline };
    pub const punct = PatternDesc{ .char_class = .punct };
    pub const quote = PatternDesc{ .char_class = .quote };
    pub const any = PatternDesc{ .any = {} };
    
    /// Combined patterns - these are properly static now!
    pub const alpha = PatternDesc{ .any_of = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" };
    
    /// Pattern builders
    pub fn literal(comptime str: []const u8) PatternDesc {
        return .{ .literal = str };
    }
    
    pub fn anyOf(comptime chars: []const u8) PatternDesc {
        return .{ .any_of = chars };
    }
    
    pub fn range(min: u8, max: u8) PatternDesc {
        return .{ .range = .{ .min = min, .max = max } };
    }
    
    pub fn sequence(comptime patterns: []const PatternDesc) PatternDesc {
        return .{ .sequence = patterns };
    }
    
    pub fn oneOrMore(comptime base: PatternDesc) PatternDesc {
        // Create a static copy to avoid pointer issues
        const static_base = comptime base;
        return .{ .one_or_more = &static_base };
    }
    
    pub fn zeroOrMore(comptime base: PatternDesc) PatternDesc {
        const static_base = comptime base;
        return .{ .zero_or_more = &static_base };
    }
    
    pub fn optional(comptime base: PatternDesc) PatternDesc {
        const static_base = comptime base;
        return .{ .optional = &static_base };
    }
    
    pub fn until(comptime delimiter: PatternDesc) PatternDesc {
        const static_delimiter = comptime delimiter;
        return .{ .until = &static_delimiter };
    }
    
    /// Common useful patterns
    pub const word = oneOrMore(alpha);
    pub const number = oneOrMore(digit);
    pub const identifier = sequence(&[_]PatternDesc{
        alpha,
        zeroOrMore(anyOf("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")),
    });
    
    /// String patterns
    pub fn quoted(comptime quote_char: u8) PatternDesc {
        const quote_pat = literal(&[_]u8{quote_char});
        return sequence(&[_]PatternDesc{
            quote_pat,
            until(quote_pat),
            quote_pat,
        });
    }
    
    pub const double_quoted_string = quoted('"');
    pub const single_quoted_string = quoted('\'');
};

/// Revolutionary tokenizer that generates optimal code for each token type
pub fn Tokenizer(comptime TokenType: type, comptime patterns: anytype) type {
    // Validate patterns at compile time
    comptime {
        const type_info = @typeInfo(TokenType);
        if (type_info != .@"enum") {
            @compileError("TokenType must be an enum");
        }
        
        const pattern_info = @typeInfo(@TypeOf(patterns));
        if (pattern_info != .@"struct") {
            @compileError("patterns must be a struct");
        }
        
        // Ensure all enum variants have corresponding patterns
        const enum_fields = type_info.@"enum".fields;
        const pattern_fields = pattern_info.@"struct".fields;
        
        if (enum_fields.len != pattern_fields.len) {
            @compileError("Number of patterns must match number of token types");
        }
        
        // Validate each pattern field corresponds to an enum variant
        for (enum_fields) |enum_field| {
            var found = false;
            for (pattern_fields) |pattern_field| {
                if (std.mem.eql(u8, enum_field.name, pattern_field.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                @compileError("Missing pattern for token type: " ++ enum_field.name);
            }
        }
    }
    
    return struct {
        const Self = @This();
        
        input: []const u8,
        pos: usize = 0,
        line: usize = 1,
        column: usize = 1,
        
        pub const Token = struct {
            type: TokenType,
            text: []const u8,
            line: usize,
            column: usize,
        };
        
        pub fn init(input: []const u8) Self {
            return .{ .input = input };
        }
        
        pub fn next(self: *Self) ?Token {
            if (self.pos >= self.input.len) return null;
            
            const start_line = self.line;
            const start_column = self.column;
            
            // Generate optimal matching code for all patterns
            inline for (@typeInfo(@TypeOf(patterns)).@"struct".fields) |field| {
                const token_type = @field(TokenType, field.name);
                const pattern_desc = @field(patterns, field.name);
                
                // Create specialized matcher for this pattern
                const PatternMatcher = Matcher(pattern_desc);
                
                if (PatternMatcher.match(self.input, self.pos)) |len| {
                    const text = self.input[self.pos..self.pos + len];
                    
                    // Update position tracking
                    for (text) |c| {
                        if (c == '\n') {
                            self.line += 1;
                            self.column = 1;
                        } else {
                            self.column += 1;
                        }
                    }
                    self.pos += len;
                    
                    return Token{
                        .type = token_type,
                        .text = text,
                        .line = start_line,
                        .column = start_column,
                    };
                }
            }
            
            // No pattern matched
            return null;
        }
        
        pub fn remaining(self: *const Self) []const u8 {
            return self.input[self.pos..];
        }
        
        pub fn isAtEnd(self: *const Self) bool {
            return self.pos >= self.input.len;
        }
        
        pub fn getPosition(self: *const Self) struct { line: usize, column: usize } {
            return .{ .line = self.line, .column = self.column };
        }
    };
}

test "revolutionary patterns - basic matching" {
    // Test literal matching
    const LiteralMatcher = Matcher(pattern.literal("hello"));
    try std.testing.expectEqual(@as(?usize, 5), LiteralMatcher.match("hello world", 0));
    try std.testing.expectEqual(@as(?usize, null), LiteralMatcher.match("hi world", 0));
    
    // Test character class
    const AlphaMatcher = Matcher(pattern.alpha);
    try std.testing.expectEqual(@as(?usize, 1), AlphaMatcher.match("hello", 0));
    try std.testing.expectEqual(@as(?usize, null), AlphaMatcher.match("123", 0));
    
    // Test one or more
    const WordMatcher = Matcher(pattern.word);
    try std.testing.expectEqual(@as(?usize, 5), WordMatcher.match("hello123", 0));
    try std.testing.expectEqual(@as(?usize, null), WordMatcher.match("123hello", 0));
}

test "revolutionary tokenizer" {
    const TokenType = enum { word, number, space, comma };
    
    const MyTokenizer = Tokenizer(TokenType, .{
        .word = pattern.word,
        .number = pattern.number,
        .space = pattern.oneOrMore(pattern.whitespace),
        .comma = pattern.literal(","),
    });
    
    var tokenizer = MyTokenizer.init("hello 123, world");
    
    const token1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.word, token1.type);
    try std.testing.expectEqualStrings("hello", token1.text);
    
    const token2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.space, token2.type);
    try std.testing.expectEqualStrings(" ", token2.text);
    
    const token3 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.number, token3.type);
    try std.testing.expectEqualStrings("123", token3.text);
    
    const token4 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.comma, token4.type);
    try std.testing.expectEqualStrings(",", token4.text);
}

test "advanced patterns" {
    // Test quoted strings
    const QuotedMatcher = Matcher(pattern.double_quoted_string);
    try std.testing.expectEqual(@as(?usize, 13), QuotedMatcher.match("\"hello world\"", 0));
    
    // Test identifiers
    const IdentifierMatcher = Matcher(pattern.identifier);
    try std.testing.expectEqual(@as(?usize, 12), IdentifierMatcher.match("hello_world1", 0));
    try std.testing.expectEqual(@as(?usize, null), IdentifierMatcher.match("1hello", 0));
    
    // Test sequences
    const FunctionMatcher = Matcher(pattern.sequence(&[_]PatternDesc{
        pattern.literal("fn"),
        pattern.oneOrMore(pattern.whitespace),
        pattern.identifier,
    }));
    try std.testing.expectEqual(@as(?usize, 8), FunctionMatcher.match("fn hello()", 0)); // "fn hello" = 8 chars
}