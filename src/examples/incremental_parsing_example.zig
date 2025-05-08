const std = @import("std");
const ByteStream = @import("../byte_stream_optimized.zig").ByteStream;
const Tokenizer = @import("../tokenizer.zig").Tokenizer;
const Token = @import("../tokenizer.zig").Token;
const TokenType = @import("../tokenizer.zig").TokenType;
const TokenMatcher = @import("../tokenizer.zig").TokenMatcher;
const Parser = @import("../parser_optimized.zig").Parser;
const IncrementalOptions = @import("../parser_optimized.zig").IncrementalOptions;
const ParseMode = @import("../parser_optimized.zig").ParseMode;
const StateMachine = @import("../state_machine.zig").StateMachine;
const State = @import("../state_machine.zig").State;
const StateTransition = @import("../state_machine.zig").StateTransition;
const types = @import("../types.zig");
const ParserContext = types.ParserContext;
const ActionFn = types.ActionFn;
const Event = @import("../event_emitter.zig").Event;
const EventType = @import("../event_emitter.zig").EventType;
const EventHandler = @import("../event_emitter.zig").EventHandler;
const Position = @import("../common.zig").Position;

// CSV token types
const TokenTypes = struct {
    pub const TEXT = TokenType{ .id = 1, .name = "TEXT" };
    pub const COMMA = TokenType{ .id = 2, .name = "COMMA" };
    pub const NEWLINE = TokenType{ .id = 3, .name = "NEWLINE" };
    pub const QUOTED_TEXT = TokenType{ .id = 4, .name = "QUOTED_TEXT" };
    pub const WHITESPACE = TokenType{ .id = 5, .name = "WHITESPACE" };
};

// CSV states
const States = struct {
    pub const FIELD = 1;
    pub const AFTER_FIELD = 2;
};

// Action IDs
const ActionIDs = struct {
    pub const EMIT_FIELD = 0;
    pub const EMIT_ROW = 1;
};

// Context for CSV parsing
const CSVContext = struct {
    fields: std.ArrayList([]const u8),
    rows: std.ArrayList([]const []const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) CSVContext {
        return .{
            .fields = std.ArrayList([]const u8).init(allocator),
            .rows = std.ArrayList([]const []const u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CSVContext) void {
        // Free all the fields in current row
        for (self.fields.items) |field| {
            self.allocator.free(field);
        }
        self.fields.deinit();
        
        // Free all rows and their fields
        for (self.rows.items) |row| {
            for (row) |field| {
                self.allocator.free(field);
            }
            self.allocator.free(row);
        }
        self.rows.deinit();
    }
    
    // Handle an event
    pub fn handleEvent(event: Event, ctx: ?*anyopaque) !void {
        const csv_ctx = @as(*CSVContext, @ptrCast(ctx.?));
        
        switch (event.type) {
            .VALUE => {
                // Add field to current row
                try csv_ctx.fields.append(try csv_ctx.allocator.dupe(u8, event.data.string_value));
            },
            .START_ELEMENT => {
                // Start of a new row, clear fields
                for (csv_ctx.fields.items) |field| {
                    csv_ctx.allocator.free(field);
                }
                csv_ctx.fields.clearRetainingCapacity();
            },
            .END_ELEMENT => {
                // End of a row, store fields
                const row = try csv_ctx.allocator.alloc([]const u8, csv_ctx.fields.items.len);
                std.mem.copy([]const u8, row, csv_ctx.fields.items);
                try csv_ctx.rows.append(row);
                
                // Clear fields for next row
                csv_ctx.fields.clearRetainingCapacity();
            },
            else => {},
        }
    }
};

// CSV token matchers
fn matchText(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    
    // Check first character
    const first = try stream.peek();
    if (first == null) return null;
    
    // Skip if it's a special character
    if (first.? == ',' or first.? == '\n' or first.? == '\r' or first.? == '"' or std.ascii.isWhitespace(first.?)) {
        return null;
    }
    
    // Consume until special character or EOF
    while (true) {
        const byte = try stream.peek();
        if (byte == null or byte.? == ',' or byte.? == '\n' or byte.? == '\r' or byte.? == '"' or std.ascii.isWhitespace(byte.?)) {
            break;
        }
        
        const char = (try stream.consume()).?;
        try text.append(char);
    }
    
    if (text.items.len == 0) return null;
    
    const lexeme = try allocator.dupe(u8, text.items);
    return Token.init(TokenTypes.TEXT, start_pos, lexeme);
}

fn matchQuotedText(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    
    // Check for opening quote
    const first = try stream.peek();
    if (first == null or first.? != '"') return null;
    
    // Consume opening quote
    _ = try stream.consume();
    
    // Consume until closing quote
    var in_escape = false;
    while (true) {
        const byte = try stream.peek();
        if (byte == null) {
            return error.UnterminatedQuote;
        }
        
        _ = try stream.consume();
        
        if (in_escape) {
            in_escape = false;
            try text.append(byte.?);
        } else if (byte.? == '"') {
            // Check for escaped quote (double quotes)
            const next = try stream.peek();
            if (next != null and next.? == '"') {
                in_escape = true;
            } else {
                break; // End of quoted text
            }
        } else {
            try text.append(byte.?);
        }
    }
    
    const lexeme = try allocator.dupe(u8, text.items);
    return Token.init(TokenTypes.QUOTED_TEXT, start_pos, lexeme);
}

fn matchComma(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    if (try stream.consumeIf(',')) {
        const lexeme = try allocator.dupe(u8, ",");
        return Token.init(TokenTypes.COMMA, start_pos, lexeme);
    }
    
    return null;
}

fn matchNewline(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Check for \n or \r\n
    const first = try stream.peek();
    if (first == null) return null;
    
    if (first.? == '\r') {
        _ = try stream.consume();
        _ = try stream.consumeIf('\n');
        const lexeme = try allocator.dupe(u8, "\r\n");
        return Token.init(TokenTypes.NEWLINE, start_pos, lexeme);
    } else if (first.? == '\n') {
        _ = try stream.consume();
        const lexeme = try allocator.dupe(u8, "\n");
        return Token.init(TokenTypes.NEWLINE, start_pos, lexeme);
    }
    
    return null;
}

fn matchWhitespace(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var whitespace = std.ArrayList(u8).init(allocator);
    defer whitespace.deinit();
    
    var matched = false;
    while (true) {
        const byte = try stream.peek();
        if (byte == null or !std.ascii.isWhitespace(byte.?) or byte.? == '\n' or byte.? == '\r') {
            break;
        }
        
        matched = true;
        const char = (try stream.consume()).?;
        try whitespace.append(char);
    }
    
    if (!matched) return null;
    
    const lexeme = try allocator.dupe(u8, whitespace.items);
    return Token.init(TokenTypes.WHITESPACE, start_pos, lexeme);
}

// CSV actions
fn emitFieldAction(ctx: *ParserContext, token: Token) !void {
    // Create value event
    var event = Event.init(.VALUE, token.position);
    event.data.string_value = token.lexeme;
    
    // Emit the event
    try ctx.emit(event);
}

fn emitRowAction(ctx: *ParserContext, token: Token) !void {
    _ = token;
    
    // Emit end element event to signal end of row
    var event = Event.init(.END_ELEMENT, .{ .offset = 0, .line = 0, .column = 0 });
    try ctx.emit(event);
    
    // Emit start element event to signal start of new row
    event = Event.init(.START_ELEMENT, .{ .offset = 0, .line = 0, .column = 0 });
    try ctx.emit(event);
}

// Function to create CSV parser
fn createCSVParser(allocator: std.mem.Allocator, incremental_options: IncrementalOptions) !Parser {
    // Token matchers
    var matchers = [_]TokenMatcher{
        TokenMatcher.init(matchQuotedText),
        TokenMatcher.init(matchText),
        TokenMatcher.init(matchComma),
        TokenMatcher.init(matchNewline),
        TokenMatcher.init(matchWhitespace),
    };
    
    // Skip whitespace
    var skip_types = [_]TokenType{
        TokenTypes.WHITESPACE,
    };
    
    // State transitions
    const state_field = State.init(
        States.FIELD,
        "FIELD",
        &[_]StateTransition{
            StateTransition.init(TokenTypes.TEXT.id, States.AFTER_FIELD, ActionIDs.EMIT_FIELD),
            StateTransition.init(TokenTypes.QUOTED_TEXT.id, States.AFTER_FIELD, ActionIDs.EMIT_FIELD),
            StateTransition.init(TokenTypes.COMMA.id, States.FIELD, null), // Empty field
            StateTransition.init(TokenTypes.NEWLINE.id, States.FIELD, ActionIDs.EMIT_ROW), // Empty field + row end
        }
    );
    
    const state_after_field = State.init(
        States.AFTER_FIELD,
        "AFTER_FIELD",
        &[_]StateTransition{
            StateTransition.init(TokenTypes.COMMA.id, States.FIELD, null),
            StateTransition.init(TokenTypes.NEWLINE.id, States.FIELD, ActionIDs.EMIT_ROW),
        }
    );
    
    var states = [_]State{ state_field, state_after_field };
    
    // Actions
    var actions = [_]ActionFn{
        emitFieldAction,
        emitRowAction,
    };
    
    // Set up configs
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = States.FIELD,
    };
    
    // Create the parser
    return Parser.initIncrementalParser(
        allocator,
        tokenizer_config,
        state_machine_config,
        incremental_options,
        .normal
    );
}

// Example: Generate large CSV data and parse it incrementally
fn generateCSVData(allocator: std.mem.Allocator, rows: usize, cols: usize) ![]u8 {
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    
    var prng = std.Random.DefaultPrng.init(42); // Deterministic seed
    const random = prng.random();
    
    // Generate rows of CSV data
    for (0..rows) |i| {
        for (0..cols) |j| {
            // Randomly decide if this field should be quoted
            const should_quote = random.boolean();
            
            if (should_quote) {
                try data.append('"');
                
                // Generate some text with possible commas and quotes
                const text_len = random.intRangeAtMost(usize, 5, 20);
                for (0..text_len) |_| {
                    const char_type = random.intRangeAtMost(u8, 0, 2);
                    switch (char_type) {
                        0 => try data.append(random.intRangeAtMost(u8, 'a', 'z')),
                        1 => try data.append(random.intRangeAtMost(u8, 'A', 'Z')),
                        2 => {
                            // Occasionally add a comma or quote (needs escaping)
                            const special = random.intRangeAtMost(u8, 0, 9);
                            if (special == 0) {
                                try data.append(',');
                            } else if (special == 1) {
                                try data.append('"');
                                try data.append('"'); // Escape the quote
                            } else {
                                try data.append(random.intRangeAtMost(u8, '0', '9'));
                            }
                        },
                    }
                }
                
                try data.append('"');
            } else {
                // Generate simple text
                const text_len = random.intRangeAtMost(usize, 3, 15);
                for (0..text_len) |_| {
                    const char_type = random.intRangeAtMost(u8, 0, 1);
                    if (char_type == 0) {
                        try data.append(random.intRangeAtMost(u8, 'a', 'z'));
                    } else {
                        try data.append(random.intRangeAtMost(u8, '0', '9'));
                    }
                }
            }
            
            // Add comma between fields (except last field)
            if (j < cols - 1) {
                try data.append(',');
            }
        }
        
        // Add newline between rows (except last row)
        if (i < rows - 1) {
            // Randomly use \n or \r\n
            if (random.boolean()) {
                try data.append('\r');
            }
            try data.append('\n');
        }
    }
    
    return data.toOwnedSlice();
}

// Main function demonstrating incremental parsing
pub fn main() !void {
    // Setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create stdout for output
    const stdout = std.io.getStdOut().writer();
    try stdout.print("ZigStream Parse - Incremental Parsing Example\n", .{});
    try stdout.print("------------------------------------------------\n", .{});
    
    // Generate large CSV data
    try stdout.print("Generating CSV data...\n", .{});
    const rows = 5000;
    const cols = 10;
    const csv_data = try generateCSVData(allocator, rows, cols);
    defer allocator.free(csv_data);
    
    try stdout.print("Generated {d} rows with {d} columns each ({d} bytes)\n", .{
        rows, cols, csv_data.len
    });
    
    // Initialize CSV context
    var csv_context = CSVContext.init(allocator);
    defer csv_context.deinit();
    
    // Create event handler
    const event_handler = EventHandler{
        .handle_fn = CSVContext.handleEvent,
        .context = &csv_context,
    };
    
    // Test with different buffer sizes to demonstrate performance difference
    const buffer_sizes = [_]usize{ 64, 1024, 8192 };
    
    for (buffer_sizes) |buffer_size| {
        try stdout.print("\nTesting with buffer size: {d} bytes\n", .{buffer_size});
        
        // Create incremental options
        const incremental_options = IncrementalOptions{
            .initial_buffer_size = buffer_size,
            .max_buffer_size = 64 * 1024, // 64KB max
            .auto_compact = true,
            .compact_threshold = 0.25,
        };
        
        // Create CSV parser
        var parser = try createCSVParser(allocator, incremental_options);
        defer parser.deinit();
        
        // Set event handler
        parser.setEventHandler(event_handler);
        
        // Start measuring time
        const start_time = std.time.milliTimestamp();
        
        // Parse in chunks of different sizes
        const chunk_size = 1024;
        var offset: usize = 0;
        
        // Emit start event for first row
        const start_event = Event.init(.START_ELEMENT, .{ .offset = 0, .line = 0, .column = 0 });
        try parser.handle.data.event_emitter.emit(start_event);
        
        // Process in chunks
        var buffer_stats_points = std.ArrayList(struct {
            chunk_num: usize,
            buffer_size: usize,
            used_space: usize,
            total_consumed: usize,
        }).init(allocator);
        defer buffer_stats_points.deinit();
        
        while (offset < csv_data.len) {
            const remaining = csv_data.len - offset;
            const size = @min(chunk_size, remaining);
            const chunk = csv_data[offset..offset+size];
            
            try parser.processChunk(chunk);
            offset += size;
            
            // Record buffer stats periodically
            if (offset % (chunk_size * 10) == 0) {
                const stats = parser.getBufferStats().?;
                try buffer_stats_points.append(.{
                    .chunk_num = offset / chunk_size,
                    .buffer_size = stats.buffer_size,
                    .used_space = stats.used_space,
                    .total_consumed = stats.total_consumed,
                });
            }
        }
        
        // Finish parsing
        try parser.finishChunks();
        
        // Calculate parsing time
        const end_time = std.time.milliTimestamp();
        const elapsed_ms = end_time - start_time;
        
        // Get final stats
        const final_stats = parser.getBufferStats().?;
        
        // Print results
        try stdout.print("  Parsed {d} rows in {d}ms\n", .{csv_context.rows.items.len, elapsed_ms});
        try stdout.print("  Final buffer size: {d} bytes\n", .{final_stats.buffer_size});
        try stdout.print("  Total consumed: {d} bytes\n", .{final_stats.total_consumed});
        try stdout.print("  Peak memory usage: {d} bytes\n", .{parser.handle.data.stream.?.stats.peak_buffer_size});
        
        // Print buffer stats over time
        try stdout.print("\n  Buffer usage over time:\n", .{});
        try stdout.print("  Chunk | Buffer Size | Used Space | Total Consumed\n", .{});
        try stdout.print("  ------------------------------------------\n", .{});
        
        for (buffer_stats_points.items) |point| {
            try stdout.print("  {d:4} | {d:10} | {d:10} | {d:14}\n", .{
                point.chunk_num,
                point.buffer_size,
                point.used_space,
                point.total_consumed,
            });
        }
        
        // Reset rows for next test
        for (csv_context.rows.items) |row| {
            for (row) |field| {
                allocator.free(field);
            }
            allocator.free(row);
        }
        csv_context.rows.clearRetainingCapacity();
    }
    
    try stdout.print("\nExample completed successfully.\n", .{});
}