const std = @import("std");
const ByteStream = @import("byte_stream_optimized.zig").ByteStream;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const Token = @import("tokenizer.zig").Token;
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

// Import error handling
const error_mod = @import("error.zig");
const ErrorReporter = error_mod.ErrorReporter;
const ErrorContext = error_mod.ErrorContext;
const ErrorCode = error_mod.ErrorCode;

pub const TokenizerConfig = struct {
    matchers: []const TokenMatcher,
    skip_types: []const TokenType,
};

pub const StateMachineConfig = struct {
    states: []const State,
    actions: []const ActionFn,
    initial_state_id: u32,
};

pub const ParseMode = enum {
    normal,
    strict,
    lenient,
    validation,
};

/// Options for incremental parsing
pub const IncrementalOptions = struct {
    /// Initial buffer size for the input stream
    initial_buffer_size: usize = 4096,
    
    /// Maximum buffer size before starting to compact
    max_buffer_size: usize = 1024 * 1024, // 1MB
    
    /// Whether to automatically compact the buffer when needed
    auto_compact: bool = true,
    
    /// Threshold ratio to trigger compaction (0.0-1.0)
    /// When (used_space / buffer_size) < compact_threshold, compaction is triggered
    compact_threshold: f32 = 0.25,
};

// Internal data structure - not directly exposed to users
const ParserData = struct {
    allocator: std.mem.Allocator,
    stream: ?ByteStream,
    tokenizer: ?Tokenizer,
    state_machine: StateMachine,
    context: ParserContext,
    event_emitter: EventEmitter,
    error_reporter: ErrorReporter,
    
    // Parsing configuration
    parse_mode: ParseMode,
    incremental_options: IncrementalOptions,
    
    // Configuration storage for resets and re-initialization
    tokenizer_config: TokenizerConfig = undefined,
    state_machine_config: StateMachineConfig = undefined,
    
    fn init(allocator: std.mem.Allocator, parse_mode: ParseMode, incremental_options: IncrementalOptions) !ParserData {
        return .{
            .allocator = allocator,
            .stream = null,
            .tokenizer = null,
            .state_machine = undefined, // Will be initialized later
            .context = try ParserContext.init(allocator),
            .event_emitter = EventEmitter.init(allocator),
            .error_reporter = ErrorReporter.init(allocator),
            .parse_mode = parse_mode,
            .incremental_options = incremental_options,
        };
    }

    fn deinit(self: *ParserData) void {
        if (self.stream) |*stream| stream.deinit();
        if (self.tokenizer) |*tokenizer| tokenizer.deinit();
        self.context.deinit();
        self.error_reporter.deinit();
    }
    
    // Report an error through both the error reporter and event system
    fn reportError(self: *ParserData, error_ctx: ErrorContext) !void {
        // Report through the error reporter
        try self.error_reporter.report(error_ctx);
        
        // Also emit an error event
        var error_event = Event.init(.ERROR, error_ctx.position);
        error_event.data = .{
            .error_info = .{
                .message = error_ctx.message,
            }
        };
        try self.event_emitter.emit(error_event);
    }
    
    // Check if buffer compaction should be performed
    fn shouldCompact(self: *ParserData) bool {
        if (!self.incremental_options.auto_compact) return false;
        if (self.stream == null) return false;
        
        // Get stream stats
        const stats = self.stream.?.getStats();
        
        // Check if total size is large enough to bother compacting
        if (stats.buffer_size < self.incremental_options.max_buffer_size) return false;
        
        // Check if the ratio of used space to buffer size is below the threshold
        return @as(f32, @floatFromInt(stats.used_space)) / @as(f32, @floatFromInt(stats.buffer_size)) < self.incremental_options.compact_threshold;
    }
};

// Internal handle-based structure for C API compatibility
const ParserHandle = struct {
    id: u64,
    data: *ParserData,

    fn create(allocator: std.mem.Allocator, parse_mode: ParseMode, incremental_options: IncrementalOptions) !ParserHandle {
        const data = try allocator.create(ParserData);
        errdefer allocator.destroy(data);
        data.* = try ParserData.init(allocator, parse_mode, incremental_options);

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

// High-level Zig API with optimized interface and enhanced error handling
pub const Parser = struct {
    handle: ParserHandle,

    /// Initialize a parser with specified options
    pub fn init(
        allocator: std.mem.Allocator,
        source: anytype,
        tokenizer_config: TokenizerConfig,
        state_machine_config: StateMachineConfig,
        buffer_size: usize,
        parse_mode: ParseMode,
    ) !Parser {
        const incremental_options = IncrementalOptions{
            .initial_buffer_size = buffer_size,
        };
        
        var handle = try ParserHandle.create(allocator, parse_mode, incremental_options);
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
    
    /// Initialize a parser specifically configured for incremental parsing
    pub fn initIncrementalParser(
        allocator: std.mem.Allocator,
        tokenizer_config: TokenizerConfig,
        state_machine_config: StateMachineConfig,
        incremental_options: IncrementalOptions,
        parse_mode: ParseMode,
    ) !Parser {
        var handle = try ParserHandle.create(allocator, parse_mode, incremental_options);
        errdefer handle.destroy(allocator);
        
        // Create a ByteStream with a preallocated buffer
        var buffer = try allocator.alloc(u8, incremental_options.initial_buffer_size);
        errdefer allocator.free(buffer);
        
        var stream = ByteStream.withBuffer(allocator, buffer);
        
        // Initialize tokenizer with the stream
        var tokenizer = try Tokenizer.init(
            allocator,
            &stream,
            tokenizer_config.matchers,
            tokenizer_config.skip_types,
        );
        
        // Initialize state machine
        var state_machine = StateMachine.init(
            state_machine_config.states,
            state_machine_config.actions,
            state_machine_config.initial_state_id,
        );
        
        // Store components in parser data
        handle.data.stream = stream;
        handle.data.tokenizer = tokenizer;
        handle.data.state_machine = state_machine;
        
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
        parse_mode: ParseMode,
    ) !Parser {
        // Convert compile-time grammar to runtime configuration
        const tokenizer_config = comptime grammar.tokenizerConfig();
        const state_machine_config = comptime grammar.stateMachineConfig();

        return init(
            allocator,
            source,
            tokenizer_config,
            state_machine_config,
            buffer_size,
            parse_mode
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

        // Process tokens until EOF or fatal error
        while (true) {
            const token = try data.tokenizer.?.nextToken();
            if (token == null) break; // EOF

            // Process the token based on parse mode
            try self.processToken(token.?);
            
            // Free the token's lexeme memory
            data.allocator.free(token.?.lexeme);
        }

        // Emit end document event
        try data.event_emitter.emit(Event.init(.END_DOCUMENT, data.stream.?.getPosition()));
        
        // If we're in strict mode or validation mode, throw on any errors
        switch (data.parse_mode) {
            .strict, .validation => {
                try data.error_reporter.throwIfErrors();
            },
            else => {},
        }
    }
    
    // Process a token with error handling
    fn processToken(self: *Parser, token: Token) !void {
        // Get internal data
        const data = self.handle.data;
        
        // Try to process the token through the state machine
        data.state_machine.transition(token, &data.context) catch |err| {
            // Handle different error types based on parse mode
            switch (err) {
                error.UnexpectedToken => {
                    // The state machine already reported this error via the error reporter
                    if (data.parse_mode == .strict) {
                        return err;
                    } else if (data.parse_mode == .validation) {
                        // In validation mode, we just record errors and continue
                        return;
                    } else {
                        // In normal or lenient mode, we attempt recovery
                        try self.recoverFromError(token);
                    }
                },
                error.NeedSynchronization => {
                    // State machine needs synchronization
                    try self.synchronizeAfterError(token);
                },
                error.TooManyErrors => {
                    // Too many errors, we should stop
                    return err;
                },
                else => {
                    // Other errors are passed through
                    return err;
                },
            }
        };
    }
    
    // Error recovery for unexpected tokens
    fn recoverFromError(self: *Parser, token: Token) !void {
        // Get internal data
        const data = self.handle.data;
        
        // Recovery depends on the parse mode
        switch (data.parse_mode) {
            .normal => {
                // In normal mode, we just try to skip to a sync point
                try self.synchronizeAfterError(token);
            },
            .lenient => {
                // In lenient mode, we try harder to recover
                // First, see if we can find a valid transition from the current state
                // to any other state, potentially skipping tokens
                if (data.state_machine.tryTransition(token, &data.context)) {
                    // We found a valid transition, just continue
                    return;
                } else {
                    // No valid transition, just skip to a sync point
                    try self.synchronizeAfterError(token);
                }
            },
            else => {},
        }
    }
    
    // Synchronize after an error by skipping tokens until we find a sync point
    fn synchronizeAfterError(self: *Parser, current_token: Token) !void {
        // Get internal data
        const data = self.handle.data;
        
        // For now, implement a simple synchronization strategy
        // Just skip tokens until we find a token that we know how to handle
        // from the current state or until EOF
        
        // First check if the current token is usable
        const current_state = data.state_machine.currentState();
        if (current_state.findTransition(current_token.type.id) != null) {
            // We can use this token
            return;
        }
        
        // Skip tokens until we find one we can use or EOF
        while (true) {
            const token = try data.tokenizer.?.nextToken();
            if (token == null) break; // EOF
            
            // Check if this token can be handled
            if (current_state.findTransition(token.?.type.id) != null) {
                // We found a usable token, process it and return
                try self.processToken(token.?);
                break;
            }
            
            // Free the skipped token
            data.allocator.free(token.?.lexeme);
        }
    }

    /// Process a chunk of data incrementally
    pub fn processChunk(self: *Parser, chunk: []const u8) !void {
        // Get internal data
        const data = self.handle.data;
        
        // Check if this is the first chunk
        const first_chunk = data.stream == null;
        
        if (first_chunk) {
            // First chunk can't be empty
            if (chunk.len == 0) {
                return error.EmptyChunk;
            }
            
            // Create a new ByteStream with a preallocated buffer
            var buffer = try data.allocator.alloc(u8, data.incremental_options.initial_buffer_size);
            var stream = ByteStream.withBuffer(data.allocator, buffer);
            
            // Append the chunk to the stream
            try stream.append(chunk);
            
            // Initialize tokenizer
            var tokenizer = try Tokenizer.init(
                data.allocator,
                &stream,
                data.tokenizer_config.matchers,
                data.tokenizer_config.skip_types,
            );
            
            // Store components
            data.stream = stream;
            data.tokenizer = tokenizer;
            
            // Emit start document event
            try data.event_emitter.emit(Event.init(.START_DOCUMENT, data.stream.?.getPosition()));
        } else {
            // Check if we should compact the buffer
            if (data.shouldCompact()) {
                data.stream.?.compact();
            }
            
            // Append the new chunk to the stream
            try data.stream.?.append(chunk);
        }
        
        // Process tokens until we run out of input
        // Note: In incremental parsing, we don't expect to reach EOF until finish() is called
        while (true) {
            const token = try data.tokenizer.?.nextToken();
            if (token == null) break; // No more tokens in this chunk
            
            // Process the token
            try self.processToken(token.?);
            
            // Free the token's lexeme memory
            data.allocator.free(token.?.lexeme);
        }
    }

    /// Finish parsing after all chunks have been processed
    pub fn finishChunks(self: *Parser) !void {
        // Get internal data
        const data = self.handle.data;
        
        // Check if parsing was started
        if (data.stream == null) {
            return error.ParsingNotStarted;
        }
        if (data.tokenizer == null) {
            return error.ParsingNotStarted;
        }
        
        // Process any remaining tokens
        while (true) {
            const token = try data.tokenizer.?.nextToken();
            if (token == null) break; // EOF
            
            // Process the token
            try self.processToken(token.?);
            
            // Free the token's lexeme memory
            data.allocator.free(token.?.lexeme);
        }
        
        // Emit end document event
        try data.event_emitter.emit(Event.init(.END_DOCUMENT, data.stream.?.getPosition()));
        
        // If we're in strict mode or validation mode, throw on any errors
        switch (data.parse_mode) {
            .strict, .validation => {
                try data.error_reporter.throwIfErrors();
            },
            else => {},
        }
    }
    
    /// Reset the parser to parse new content
    pub fn reset(self: *Parser) !void {
        // Get internal data
        const data = self.handle.data;
        
        // Check if we have a stream to reset
        if (data.stream) |*stream| {
            try stream.reset();
        }
        
        // Reset the state machine
        data.state_machine.reset(data.state_machine_config.initial_state_id);
        
        // Reset the context
        data.context.reset();
        
        // Clear any errors
        data.error_reporter.clear();
    }
    
    /// Get buffer statistics for monitoring
    pub fn getBufferStats(self: *Parser) ?struct {
        buffer_size: usize,
        used_space: usize,
        free_space: usize,
        total_consumed: usize,
    } {
        // Get internal data
        const data = self.handle.data;
        
        if (data.stream == null) {
            return null;
        }
        
        const stats = data.stream.?.getStats();
        return .{
            .buffer_size = stats.buffer_size,
            .used_space = stats.used_space,
            .free_space = stats.free_space,
            .total_consumed = stats.total_consumed,
        };
    }
    
    /// Get access to the errors
    pub fn getErrors(self: Parser) []ErrorContext {
        return self.handle.data.error_reporter.getErrors();
    }
    
    /// Get access to the warnings
    pub fn getWarnings(self: Parser) []ErrorContext {
        return self.handle.data.error_reporter.getWarnings();
    }
    
    /// Check if there are any errors
    pub fn hasErrors(self: Parser) bool {
        return self.handle.data.error_reporter.hasErrors();
    }
    
    /// Print all errors and warnings
    pub fn printErrors(self: Parser) !void {
        try self.handle.data.error_reporter.printAll();
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
    
    // Save config for potential reuse
    data.tokenizer_config = tokenizer_config;
    data.state_machine_config = state_machine_config;
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