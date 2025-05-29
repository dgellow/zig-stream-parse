const std = @import("std");

pub const CharClass = enum(u4) {
    other = 0,
    whitespace = 1,
    alpha_lower = 2,
    alpha_upper = 3,
    digit = 4,
    punct = 5,
    quote = 6,
    newline = 7,
};

// Compile-time character classification table for O(1) lookups
pub const char_table = blk: {
    var table = [_]CharClass{.other} ** 256;
    
    // Whitespace (space, tab)
    table[' '] = .whitespace;
    table['\t'] = .whitespace;
    
    // Newlines get their own class for line tracking
    table['\n'] = .newline;
    table['\r'] = .newline;
    
    // Digits
    var i: u8 = '0';
    while (i <= '9') : (i += 1) {
        table[i] = .digit;
    }
    
    // Lowercase letters
    i = 'a';
    while (i <= 'z') : (i += 1) {
        table[i] = .alpha_lower;
    }
    
    // Uppercase letters
    i = 'A';
    while (i <= 'Z') : (i += 1) {
        table[i] = .alpha_upper;
    }
    
    // Common punctuation
    const punct_chars = ".,;:!?-_/\\|@#$%^&*()[]{}+=~`";
    for (punct_chars) |c| {
        table[c] = .punct;
    }
    
    // Quotes
    table['"'] = .quote;
    table['\''] = .quote;
    
    break :blk table;
};

// Fast inline character classification functions
pub inline fn isWhitespace(c: u8) bool {
    return char_table[c] == .whitespace;
}

pub inline fn isNewline(c: u8) bool {
    return char_table[c] == .newline;
}

pub inline fn isAlpha(c: u8) bool {
    const class = char_table[c];
    return class == .alpha_lower or class == .alpha_upper;
}

pub inline fn isAlphaLower(c: u8) bool {
    return char_table[c] == .alpha_lower;
}

pub inline fn isAlphaUpper(c: u8) bool {
    return char_table[c] == .alpha_upper;
}

pub inline fn isDigit(c: u8) bool {
    return char_table[c] == .digit;
}

pub inline fn isAlphaNumeric(c: u8) bool {
    const class = char_table[c];
    return class == .alpha_lower or class == .alpha_upper or class == .digit;
}

pub inline fn isPunct(c: u8) bool {
    return char_table[c] == .punct;
}

pub inline fn isQuote(c: u8) bool {
    return char_table[c] == .quote;
}

// Compile-time tests to ensure our table is correct
test "char classification" {
    try std.testing.expect(isWhitespace(' '));
    try std.testing.expect(isWhitespace('\t'));
    try std.testing.expect(!isWhitespace('a'));
    
    try std.testing.expect(isNewline('\n'));
    try std.testing.expect(isNewline('\r'));
    try std.testing.expect(!isNewline(' '));
    
    try std.testing.expect(isAlpha('a'));
    try std.testing.expect(isAlpha('Z'));
    try std.testing.expect(!isAlpha('1'));
    
    try std.testing.expect(isDigit('0'));
    try std.testing.expect(isDigit('9'));
    try std.testing.expect(!isDigit('a'));
    
    try std.testing.expect(isAlphaNumeric('a'));
    try std.testing.expect(isAlphaNumeric('Z'));
    try std.testing.expect(isAlphaNumeric('5'));
    try std.testing.expect(!isAlphaNumeric(' '));
}