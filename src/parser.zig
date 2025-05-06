const std = @import("std");
const ByteStream = @import("byte_stream.zig").ByteStream;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const TokenMatcher = @import("tokenizer.zig").TokenMatcher;
const StateMachine = @import("state_machine.zig").StateMachine;
const State = @import("state_machine.zig").State;
const types = @import("types.zig");
pub const ParserContext = types.ParserContext;
const ActionFn = types.ActionFn;
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const Event = @import("event_emitter.zig").Event;
const EventType = @import("event_emitter.zig").EventType;
const EventHandler = @import("event_emitter.zig").EventHandler;

pub const TokenizerConfig = struct {
    matchers: []const TokenMatcher,
    skip_types: []const TokenType,
};

pub const StateMachineConfig = struct {
    states: []const State,
    actions: []const ActionFn,
    initial_state_id: u32,
};

// Internal data structure - not directly exposed to users
const ParserData = struct {
    allocator: std.mem.Allocator,
    stream: ?ByteStream,
    tokenizer: ?Tokenizer,
    state_machine: StateMachine,
    context: ParserContext,
    event_emitter: EventEmitter,
    error_message: ?[]u8,
    error_code: u32,

    fn init(allocator: std.mem.Allocator) !ParserData {
        return .{
            .allocator = allocator,
            .stream = null,
            .tokenizer = null,
            .state_machine = undefined, // Will be initialized later
            .context = try ParserContext.init(allocator),
            .event_emitter = EventEmitter.init(allocator),
            .error_message = null,
            .error_code = 0,
        };
    }

    fn deinit(self: *ParserData) void {
        if (self.stream) |*stream| stream.deinit();
        if (self.tokenizer) |*tokenizer| tokenizer.deinit();
        self.context.deinit();
        if (self.error_message) |msg| self.allocator.free(msg);
    }

    fn setError(self: *ParserData, code: u32, message: []const u8) !void {
        if (self.error_message) |old_msg| {
            self.allocator.free(old_msg);
        }

        self.error_code = code;
        self.error_message = try self.allocator.dupe(u8, message);
    }
};

// Internal handle-based structure for C API compatibility
const ParserHandle = struct {
    id: u64,
    data: *ParserData,

    fn create(allocator: std.mem.Allocator) !ParserHandle {
        const data = try allocator.create(ParserData);
        errdefer allocator.destroy(data);
        data.* = try ParserData.init(allocator);

        // In a real implementation, we would use a handle manager
        // to track and validate handles across API boundaries
        return ParserHandle{
            .id = generateUniqueId(),
            .data = data,
        };
    }

    fn destroy(self: *ParserHandle, allocator: std.mem.Allocator) void {
        self.data.deinit();
        allocator.destroy(self.data);
    }
};

// High-level Zig API with optimized interface
pub const Parser = struct {
    handle: ParserHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        source: anytype,
        tokenizer_config: TokenizerConfig,
        state_machine_config: StateMachineConfig,
        buffer_size: usize,
    ) !Parser {
        var handle = try ParserHandle.create(allocator);
        errdefer handle.destroy(allocator);

        // Initialize parser components
        try initParserComponents(
            &handle,
            allocator,
            source,
            tokenizer_config,
            state_machine_config,
            buffer_size
        );

        return .{
            .handle = handle,
        };
    }

    // Type-checked compile-time optimized version
    pub fn initWithGrammar(
        allocator: std.mem.Allocator,
        source: anytype,
        comptime grammar: anytype,
        buffer_size: usize,
    ) !Parser {
        // Convert compile-time grammar to runtime configuration
        const tokenizer_config = comptime grammar.tokenizerConfig();
        const state_machine_config = comptime grammar.stateMachineConfig();

        return init(
            allocator,
            source,
            tokenizer_config,
            state_machine_config,
            buffer_size
        );
    }

    pub fn deinit(self: *Parser) void {
        const allocator = self.handle.data.allocator;
        self.handle.destroy(allocator);
    }

    pub fn setEventHandler(self: *Parser, handler: EventHandler) void {
        self.handle.data.event_emitter.setHandler(handler);
    }

    pub fn parse(self: *Parser) !void {
        // Get internal data
        const data = self.handle.data;

        // Emit start document event
        try data.event_emitter.emit(Event.init(.START_DOCUMENT, data.stream.?.getPosition()));

        // Process tokens until EOF
        while (true) {
            const token = try data.tokenizer.?.nextToken();
            if (token == null) break; // EOF

            std.debug.print("Token: {s} (id: {d})\n", .{token.?.lexeme, token.?.type.id});
            try data.state_machine.transition(token.?, &data.context);
        }

        // Emit end document event
        try data.event_emitter.emit(Event.init(.END_DOCUMENT, data.stream.?.getPosition()));
    }

    // For incremental parsing
    pub fn process(self: *Parser, chunk: []const u8) !void {
        // Implementation for processing a chunk of data
        // Using internal handle-based design
        _ = self;
        _ = chunk;
        @compileError("Incremental parsing not yet implemented");
    }

    pub fn finish(self: *Parser) !void {
        // Implementation for finalizing parsing
        // Using internal handle-based design
        _ = self;
        @compileError("Incremental parsing not yet implemented");
    }
};

// Internal helper functions that will be reusable for C API
fn initParserComponents(
    handle: *ParserHandle,
    allocator: std.mem.Allocator,
    source: anytype,
    tokenizer_config: TokenizerConfig,
    state_machine_config: StateMachineConfig,
    buffer_size: usize,
) !void {
    var data = handle.data;

    // Initialize byte stream
    var stream = try ByteStream.init(allocator, source, buffer_size);
    errdefer stream.deinit();

    // Initialize tokenizer
    var tokenizer = try Tokenizer.init(
        allocator,
        &stream,
        tokenizer_config.matchers,
        tokenizer_config.skip_types,
    );
    errdefer tokenizer.deinit();

    // Initialize state machine
    const state_machine = StateMachine.init(
        state_machine_config.states,
        state_machine_config.actions,
        state_machine_config.initial_state_id,
    );

    // Store components in parser data
    data.stream = stream;
    data.tokenizer = tokenizer;
    data.state_machine = state_machine;
}

// Generate a unique ID for handles
fn generateUniqueId() u64 {
    // In a real implementation, this would use atomic operations
    // and proper handle management
    const static = struct {
        var next_id: u64 = 1;
    };

    return @atomicRmw(u64, &static.next_id, .Add, 1, .monotonic);
}