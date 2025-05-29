const std = @import("std");
const pattern = @import("pattern.zig");
const char_class = @import("char_class.zig");

pub const TokenStream = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    
    pub fn init(source: []const u8) TokenStream {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
        };
    }
    
    pub fn next(self: *TokenStream, comptime TokenType: type, comptime patterns: anytype) ?struct {
        type: TokenType,
        text: []const u8,
        line: usize,
        column: usize,
    } {
        if (self.pos >= self.source.len) return null;
        
        const start_line = self.line;
        const start_column = self.column;
        
        // Try each pattern in order
        const type_info = @typeInfo(@TypeOf(patterns));
        const fields = switch (type_info) {
            .@"struct" => |s| s.fields,
            .pointer => |p| switch (@typeInfo(p.child)) {
                .@"struct" => |s| s.fields,
                else => @compileError("Expected struct patterns"),
            },
            else => @compileError("Expected struct patterns"),
        };
        
        inline for (fields) |field| {
            const token_type = @field(TokenType, field.name);
            const pattern_value = @field(patterns, field.name);
            
            const result = pattern.matchPattern(pattern_value, self.source, self.pos);
            if (result.matched and result.len > 0) {
                const text = self.source[self.pos..][0..result.len];
                
                // Update position tracking
                for (text) |c| {
                    if (c == '\n') {
                        self.line += 1;
                        self.column = 1;
                    } else {
                        self.column += 1;
                    }
                }
                self.pos += result.len;
                
                return .{
                    .type = token_type,
                    .text = text,
                    .line = start_line,
                    .column = start_column,
                };
            }
        }
        
        // No pattern matched - return null
        return null;
    }
    
    fn skipWhitespace(self: *TokenStream) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (!char_class.isWhitespace(c) and !char_class.isNewline(c)) break;
            
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }
    
    pub fn peek(self: *const TokenStream, comptime TokenType: type, comptime patterns: anytype) ?struct {
        type: TokenType,
        text: []const u8,
        line: usize,
        column: usize,
    } {
        var copy = self.*;
        return copy.next(TokenType, patterns);
    }
    
    pub fn remaining(self: *const TokenStream) []const u8 {
        if (self.pos >= self.source.len) return "";
        return self.source[self.pos..];
    }
    
    pub fn isAtEnd(self: *const TokenStream) bool {
        return self.pos >= self.source.len;
    }
    
    pub fn getPosition(self: *const TokenStream) struct { line: usize, column: usize } {
        return .{ .line = self.line, .column = self.column };
    }
};

test "token stream" {
    const TokenType = enum { word, number, whitespace, unknown };
    const patterns = comptime .{
        .word = pattern.match.alpha.oneOrMore(),
        .number = pattern.match.digit.oneOrMore(),
        .whitespace = pattern.match.whitespace.oneOrMore(),
    };
    
    const input = "hello 123 world";
    var stream = TokenStream.init(input);
    
    // First token should be "hello"
    const token1 = stream.next(TokenType, patterns).?;
    try std.testing.expectEqual(TokenType.word, token1.type);
    try std.testing.expectEqualStrings("hello", token1.text);
    
    // Second token should be " " (whitespace)
    const token2 = stream.next(TokenType, patterns).?;
    try std.testing.expectEqual(TokenType.whitespace, token2.type);
    try std.testing.expectEqualStrings(" ", token2.text);
    
    // Third token should be "123"
    const token3 = stream.next(TokenType, patterns).?;
    try std.testing.expectEqual(TokenType.number, token3.type);
    try std.testing.expectEqualStrings("123", token3.text);
    
    // Fourth token should be " " (whitespace)
    const token4 = stream.next(TokenType, patterns).?;
    try std.testing.expectEqual(TokenType.whitespace, token4.type);
    
    // Fifth token should be "world"
    const token5 = stream.next(TokenType, patterns).?;
    try std.testing.expectEqual(TokenType.word, token5.type);
    try std.testing.expectEqualStrings("world", token5.text);
    
    // No more tokens
    try std.testing.expect(stream.next(TokenType, patterns) == null);
}