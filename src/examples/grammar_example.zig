const std = @import("std");
const lib = @import("zig_stream_parse_lib");

const ByteStream = lib.ByteStream;
const Token = lib.Token;
const TokenMatcher = lib.TokenMatcher;
const Parser = lib.Parser;
const ParserContext = lib.ParserContext;
const Grammar = lib.Grammar;
const Position = lib.Position;
const EventHandler = lib.EventHandler;
const Event = lib.Event;

// Example token matchers
fn wordTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a letter
    if (!isAlpha(first_char.?)) return null;
    
    // Start of a word, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-alphabetic character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isAlpha(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 1, .name = "WORD" },
        start_pos,
        lexeme
    );
}

fn numberTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a digit
    if (!isDigit(first_char.?)) return null;
    
    // Start of a number, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-digit character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isDigit(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 2, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

fn whitespaceTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's whitespace
    if (!isWhitespace(first_char.?)) return null;
    
    // Start of whitespace, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-whitespace character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isWhitespace(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 3, .name = "WHITESPACE" },
        start_pos,
        lexeme
    );
}

// Helper functions for character classification
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// Action functions for the state machine
fn emitWord(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Word: {s}\n", .{token.lexeme});
}

fn emitNumber(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Number: {s}\n", .{token.lexeme});
}

// Event handler
fn handleEvent(event: Event, ctx: ?*anyopaque) !void {
    _ = ctx;
    switch (event.type) {
        .START_DOCUMENT => std.debug.print("Start Document\n", .{}),
        .END_DOCUMENT => std.debug.print("End Document\n", .{}),
        .VALUE => std.debug.print("Value: {s}\n", .{event.data.string_value}),
        .ERROR => std.debug.print("Error: {s}\n", .{event.data.error_info.message}),
        else => {},
    }
}

pub fn main() !void {
    // Setup allocator
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // Print welcome message
    std.debug.print("ZigParse Grammar Example\n", .{});

    // Create a grammar using the builder pattern
    var grammar_builder = Grammar.init();
    defer grammar_builder.deinit();

    // Define tokens
    try grammar_builder.token("WORD", TokenMatcher.init(wordTokenMatcher));
    try grammar_builder.token("NUMBER", TokenMatcher.init(numberTokenMatcher));
    try grammar_builder.token("WHITESPACE", TokenMatcher.init(whitespaceTokenMatcher));
    
    // Define which tokens to skip
    try grammar_builder.skipToken("WHITESPACE");
    
    // Define actions
    try grammar_builder.action("emitWord", emitWord);
    try grammar_builder.action("emitNumber", emitNumber);
    
    // Set the initial state
    try grammar_builder.initialState("INITIAL");
    
    // Define states with transitions
    var state_builder = try grammar_builder.state("INITIAL");
    try (try state_builder.on("WORD")).to("INITIAL").action("emitWord");
    try (try state_builder.on("NUMBER")).to("INITIAL").action("emitNumber");
    
    // Build the grammar into parser configuration
    const parser_config = try grammar_builder.build();
    
    // Create example input
    const input = "hello 123 world 456";
    
    // Create a parser with the grammar
    var parser = try Parser.init(
        allocator,
        input,
        parser_config.tokenizer_config,
        parser_config.state_machine_config,
        1024 // buffer size
    );
    defer parser.deinit();
    
    // Set event handler
    parser.setEventHandler(EventHandler.init(handleEvent, null));
    
    // Parse the input
    try parser.parse();
    
    // Notify user about successful parsing
    std.debug.print("\nParsing completed successfully using grammar builder!\n", .{});
}