const std = @import("std");
const Pattern = @import("pattern.zig").Pattern;
const char_class = @import("char_class.zig");

/// Compile-time DFA (Deterministic Finite Automaton) generator
/// Converts patterns into optimized state machines for ultra-fast matching
pub fn DFAGenerator(comptime patterns: anytype) type {
    const TokenType = @TypeOf(patterns);
    const num_patterns = @typeInfo(TokenType).@"struct".fields.len;
    
    // Compile-time DFA construction
    const dfa_table = comptime buildDFATable(patterns);
    const max_states = dfa_table.len;
    
    return struct {
        const Self = @This();
        
        /// Pre-compiled transition table for ultra-fast lookups
        /// [current_state][character] -> next_state
        pub const transition_table = dfa_table;
        
        /// Pattern matching result
        pub const MatchResult = struct {
            pattern_id: ?u32,
            length: usize,
        };
        
        /// Match patterns against input using DFA
        pub fn match(input: []const u8, start_pos: usize) MatchResult {
            if (start_pos >= input.len) return .{ .pattern_id = null, .length = 0 };
            
            var state: u32 = 0; // Start state
            var pos = start_pos;
            var last_accepting_state: ?u32 = null;
            var last_accepting_pos: usize = start_pos;
            
            // Run the DFA
            while (pos < input.len and state < max_states) {
                const c = input[pos];
                const next_state = transition_table[state][c];
                
                if (next_state == DEAD_STATE) break;
                
                state = next_state;
                pos += 1;
                
                // Check if this is an accepting state
                if (isAcceptingState(state)) {
                    last_accepting_state = state;
                    last_accepting_pos = pos;
                }
            }
            
            if (last_accepting_state) |accepting_state| {
                const pattern_id = getPatternId(accepting_state);
                const length = last_accepting_pos - start_pos;
                return .{ .pattern_id = pattern_id, .length = length };
            }
            
            return .{ .pattern_id = null, .length = 0 };
        }
        
        /// Get the longest matching pattern at position
        pub fn matchLongest(input: []const u8, start_pos: usize) MatchResult {
            return match(input, start_pos);
        }
        
        /// Match all patterns and return the first (highest priority) match
        pub fn matchFirst(input: []const u8, start_pos: usize) MatchResult {
            // For now, same as matchLongest since we build priority into the DFA
            return match(input, start_pos);
        }
    };
}

// Compile-time constants
const DEAD_STATE: u32 = std.math.maxInt(u32);
const MAX_STATES: u32 = 1024;

/// Build DFA transition table at compile time
fn buildDFATable(comptime patterns: anytype) [MAX_STATES][256]u32 {
    var table = [_][256]u32{[_]u32{DEAD_STATE} ** 256} ** MAX_STATES;
    
    // Start with simple state machine construction
    // State 0 is the initial state
    var next_state_id: u32 = 1;
    
    // For each pattern, create a path through the DFA
    inline for (@typeInfo(@TypeOf(patterns)).@"struct".fields, 0..) |field, pattern_idx| {
        const pattern = @field(patterns, field.name);
        
        // Build states for this pattern
        const states_built = comptime buildPatternStates(pattern, pattern_idx);
        
        // Add transitions to the main table
        var state_id = next_state_id;
        for (states_built.transitions, 0..) |transition_set, state_offset| {
            const current_state = state_id + state_offset;
            if (current_state >= MAX_STATES) break;
            
            for (transition_set, 0..) |next_state, char_index| {
                if (next_state != DEAD_STATE) {
                    table[current_state][char_index] = state_id + next_state;
                }
            }
        }
        
        next_state_id += states_built.num_states;
        if (next_state_id >= MAX_STATES) break;
    }
    
    return table;
}

/// Result of building states for a pattern
const PatternStates = struct {
    transitions: []const [256]u32,
    num_states: u32,
    accepting_state: u32,
};

/// Build DFA states for a single pattern
fn buildPatternStates(comptime pattern: Pattern, comptime pattern_id: u32) PatternStates {
    _ = pattern_id;
    
    // Simplified DFA construction for basic patterns
    switch (pattern) {
        .literal => |lit| {
            return buildLiteralStates(lit);
        },
        .char_class => |class| {
            return buildCharClassStates(class);
        },
        .one_or_more => |sub| {
            return buildOneOrMoreStates(sub.*);
        },
        .any_of => |chars| {
            return buildAnyOfStates(chars);
        },
        else => {
            // Fallback to simple single-state matcher
            return buildSimpleStates();
        },
    }
}

/// Build states for literal patterns
fn buildLiteralStates(comptime literal: []const u8) PatternStates {
    var transitions = [_][256]u32{[_]u32{DEAD_STATE} ** 256} ** (literal.len + 1);
    
    // Create a linear chain of states for each character
    for (literal, 0..) |char, i| {
        transitions[i][char] = @intCast(i + 1);
    }
    
    return .{
        .transitions = &transitions,
        .num_states = @intCast(literal.len + 1),
        .accepting_state = @intCast(literal.len),
    };
}

/// Build states for character class patterns
fn buildCharClassStates(comptime class: @TypeOf(.digit)) PatternStates {
    var transitions = [_][256]u32{[_]u32{DEAD_STATE} ** 256} ** 2;
    
    // State 0 -> State 1 on matching character
    for (0..256) |i| {
        const c: u8 = @intCast(i);
        const matches = switch (class) {
            .digit => char_class.char_table[c] == .digit,
            .alpha_lower => char_class.char_table[c] == .alpha_lower,
            .alpha_upper => char_class.char_table[c] == .alpha_upper,
            .whitespace => char_class.char_table[c] == .whitespace,
            .newline => char_class.char_table[c] == .newline,
            .punct => char_class.char_table[c] == .punct,
            .quote => char_class.char_table[c] == .quote,
            else => false,
        };
        
        if (matches) {
            transitions[0][i] = 1;
        }
    }
    
    return .{
        .transitions = &transitions,
        .num_states = 2,
        .accepting_state = 1,
    };
}

/// Build states for one-or-more patterns
fn buildOneOrMoreStates(comptime sub_pattern: Pattern) PatternStates {
    // For now, handle simple character classes
    if (sub_pattern == .char_class) {
        var transitions = [_][256]u32{[_]u32{DEAD_STATE} ** 256} ** 2;
        
        const class = sub_pattern.char_class;
        
        // State 0 -> State 1 on first match
        // State 1 -> State 1 on subsequent matches (loop)
        for (0..256) |i| {
            const c: u8 = @intCast(i);
            const matches = switch (class) {
                .digit => char_class.char_table[c] == .digit,
                .alpha_lower => char_class.char_table[c] == .alpha_lower,
                .alpha_upper => char_class.char_table[c] == .alpha_upper,
                .whitespace => char_class.char_table[c] == .whitespace,
                else => false,
            };
            
            if (matches) {
                transitions[0][i] = 1; // First character
                transitions[1][i] = 1; // Continue matching
            }
        }
        
        return .{
            .transitions = &transitions,
            .num_states = 2,
            .accepting_state = 1,
        };
    }
    
    // Fallback for complex patterns
    return buildSimpleStates();
}

/// Build states for any-of patterns
fn buildAnyOfStates(comptime chars: []const u8) PatternStates {
    var transitions = [_][256]u8{[_]u8{DEAD_STATE} ** 256} ** 2;
    
    // State 0 -> State 1 on any matching character
    for (chars) |char| {
        transitions[0][char] = 1;
    }
    
    return .{
        .transitions = @ptrCast(&transitions),
        .num_states = 2,
        .accepting_state = 1,
    };
}

/// Fallback simple state builder
fn buildSimpleStates() PatternStates {
    const transitions = [_][256]u32{[_]u32{DEAD_STATE} ** 256} ** 1;
    
    return .{
        .transitions = &transitions,
        .num_states = 1,
        .accepting_state = 0,
    };
}

/// Check if a state is accepting (matches a pattern)
fn isAcceptingState(state: u32) bool {
    // For now, simplified: odd states are accepting
    return state > 0 and state % 2 == 1;
}

/// Get pattern ID from accepting state
fn getPatternId(state: u32) u32 {
    // Simplified mapping
    return (state - 1) / 2;
}

/// Ultra-fast DFA-based tokenizer
pub fn DFATokenizer(comptime TokenType: type, comptime patterns: anytype) type {
    const DFA = DFAGenerator(patterns);
    
    return struct {
        input: []const u8,
        pos: usize = 0,
        line: usize = 1,
        column: usize = 1,
        
        const Self = @This();
        
        pub fn init(input: []const u8) Self {
            return .{ .input = input };
        }
        
        pub fn next(self: *Self) ?struct {
            type: TokenType,
            text: []const u8,
            line: usize,
            column: usize,
        } {
            while (self.pos < self.input.len) {
                const start_pos = self.pos;
                const start_line = self.line;
                const start_column = self.column;
                
                // Use DFA to find the longest match
                const result = DFA.matchLongest(self.input, start_pos);
                
                if (result.pattern_id) |pattern_id| {
                    // Map pattern ID back to token type
                    const token_type = getTokenTypeFromPatternId(TokenType, pattern_id);
                    const token_text = self.input[start_pos..start_pos + result.length];
                    
                    self.pos = start_pos + result.length;
                    self.updatePosition(token_text);
                    
                    return .{
                        .type = token_type,
                        .text = token_text,
                        .line = start_line,
                        .column = start_column,
                    };
                }
                
                // No pattern matched - skip character
                self.pos += 1;
                if (self.input[start_pos] == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
            }
            
            return null;
        }
        
        fn updatePosition(self: *Self, text: []const u8) void {
            for (text) |c| {
                if (c == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
            }
        }
        
        pub fn remaining(self: *const Self) []const u8 {
            return self.input[self.pos..];
        }
        
        pub fn isAtEnd(self: *const Self) bool {
            return self.pos >= self.input.len;
        }
    };
}

/// Map pattern ID back to token type
fn getTokenTypeFromPatternId(comptime TokenType: type, pattern_id: u32) TokenType {
    const fields = @typeInfo(TokenType).@"enum".fields;
    if (pattern_id < fields.len) {
        return @enumFromInt(pattern_id);
    }
    return @enumFromInt(0); // Default to first enum value
}

test "DFA literal matching" {
    const patterns = .{
        .hello = Pattern{ .literal = "hello" },
        .world = Pattern{ .literal = "world" },
    };
    
    const DFA = DFAGenerator(patterns);
    
    const input = "hello world";
    
    // Test matching "hello"
    const result1 = DFA.match(input, 0);
    try std.testing.expect(result1.pattern_id != null);
    try std.testing.expectEqual(@as(usize, 5), result1.length);
    
    // Test matching "world"  
    const result2 = DFA.match(input, 6);
    try std.testing.expect(result2.pattern_id != null);
    try std.testing.expectEqual(@as(usize, 5), result2.length);
}

test "DFA character class matching" {
    const patterns = .{
        .digit = Pattern{ .char_class = .digit },
        .alpha = Pattern{ .char_class = .alpha_lower },
    };
    
    const DFA = DFAGenerator(patterns);
    
    // Test digit matching
    const result1 = DFA.match("123abc", 0);
    try std.testing.expect(result1.pattern_id != null);
    try std.testing.expectEqual(@as(usize, 1), result1.length);
    
    // Test alpha matching
    const result2 = DFA.match("abc123", 0);
    try std.testing.expect(result2.pattern_id != null);
    try std.testing.expectEqual(@as(usize, 1), result2.length);
}

test "DFA tokenizer" {
    const TokenType = enum { word, number };
    const word_pattern = Pattern{ .char_class = .alpha_lower };
    const number_pattern = Pattern{ .char_class = .digit };
    const patterns = .{
        .word = word_pattern.oneOrMore(),
        .number = number_pattern.oneOrMore(),
    };
    
    const Tokenizer = DFATokenizer(TokenType, patterns);
    
    const input = "hello123";
    var tokenizer = Tokenizer.init(input);
    
    // Should find word token
    const token1 = tokenizer.next();
    try std.testing.expect(token1 != null);
    try std.testing.expectEqual(TokenType.word, token1.?.type);
    
    // Should find number token
    const token2 = tokenizer.next();
    try std.testing.expect(token2 != null);
    try std.testing.expectEqual(TokenType.number, token2.?.type);
    
    // Should be at end
    try std.testing.expect(tokenizer.next() == null);
}