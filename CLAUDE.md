# ZigParse: Universal Streaming Parser Framework

## Project Tracking

All bugs, issues, ongoing work, and resolved items MUST be tracked in ISSUES.md. When fixing issues:
1. Document what was fixed
2. Add any new issues discovered
3. Update status of in-progress work
4. Add date of completion for resolved items

## Design Goals

1. **Incremental processing** without intermediate trees
2. **Memory efficiency** through careful buffer management
3. **Compile-time optimization** using Zig features
4. **Clean API** for defining and using parsers
5. **High performance** with safety guarantees
6. **Cross-language support** via C API

## Core Components

1. **ByteStream**: Input management from various sources
2. **Tokenizer**: Byte-to-token conversion
3. **StateMachine**: Context tracking and state transitions
4. **EventEmitter**: Event generation from parsed content
5. **Parser**: Orchestration layer

## Implementation Details

### ByteStream

```zig
pub const ByteStream = struct {
    allocator: std.mem.Allocator,
    source: union(enum) {
        file: std.fs.File,
        memory: []const u8,
        reader: std.io.Reader,
    },
    buffer: []u8,
    buffer_start: usize,
    buffer_end: usize,
    position: usize,
    line: usize,
    column: usize,

    pub fn init(allocator: std.mem.Allocator, source: anytype, buffer_size: usize) !ByteStream {
        // Initialize the byte stream with the given source
        var buffer = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buffer);

        return ByteStream{
            .allocator = allocator,
            .source = initSource(source),
            .buffer = buffer,
            .buffer_start = 0,
            .buffer_end = 0,
            .position = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn deinit(self: *ByteStream) void {
        self.allocator.free(self.buffer);
        // Handle source-specific cleanup
    }

    pub fn peek(self: *ByteStream) !?u8 {
        return self.peekOffset(0);
    }

    pub fn peekOffset(self: *ByteStream, offset: usize) !?u8 {
        if (self.buffer_start + offset >= self.buffer_end) {
            try self.fillBuffer();
            if (self.buffer_start + offset >= self.buffer_end) {
                return null; // EOF
            }
        }
        return self.buffer[self.buffer_start + offset];
    }

    pub fn consume(self: *ByteStream) !?u8 {
        const byte = try self.peek();
        if (byte) |b| {
            self.buffer_start += 1;
            self.position += 1;

            if (b == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
        }
        return byte;
    }

    pub fn consumeIf(self: *ByteStream, expected: u8) !bool {
        const byte = try self.peek();
        if (byte != null and byte.? == expected) {
            _ = try self.consume();
            return true;
        }
        return false;
    }

    pub fn consumeCount(self: *ByteStream, count: usize) !usize {
        var consumed: usize = 0;
        while (consumed < count) {
            if ((try self.consume()) == null) break;
            consumed += 1;
        }
        return consumed;
    }

    pub fn fillBuffer(self: *ByteStream) !void {
        // If there's unprocessed data, move it to the beginning
        if (self.buffer_start > 0) {
            std.mem.copy(
                u8,
                self.buffer,
                self.buffer[self.buffer_start..self.buffer_end]
            );
            self.buffer_end -= self.buffer_start;
            self.buffer_start = 0;
        }

        // If buffer is full, we can't read more
        if (self.buffer_end == self.buffer.len) return;

        // Read more data from the source
        const bytes_read = switch (self.source) {
            .file => |file| try file.read(self.buffer[self.buffer_end..]),
            .memory => |memory| blk: {
                const pos = self.position - (self.buffer_end - self.buffer_start);
                if (pos >= memory.len) break :blk 0;
                const to_copy = std.math.min(
                    self.buffer.len - self.buffer_end,
                    memory.len - pos
                );
                std.mem.copy(u8, self.buffer[self.buffer_end..], memory[pos..pos+to_copy]);
                break :blk to_copy;
            },
            .reader => |reader| try reader.read(self.buffer[self.buffer_end..]),
        };

        self.buffer_end += bytes_read;
    }

    pub fn getPosition(self: *const ByteStream) Position {
        return .{
            .offset = self.position,
            .line = self.line,
            .column = self.column,
        };
    }
};
```

### Token and Tokenizer

```zig
pub const TokenType = struct {
    id: u32,
    name: []const u8,
};

pub const Token = struct {
    type: TokenType,
    position: Position,
    lexeme: []const u8,

    pub fn init(token_type: TokenType, position: Position, lexeme: []const u8) Token {
        return .{
            .type = token_type,
            .position = position,
            .lexeme = lexeme,
        };
    }
};

pub const TokenMatcher = struct {
    match_fn: *const fn(stream: *ByteStream, allocator: std.mem.Allocator) anyerror!?Token,

    pub fn init(comptime matcher_fn: anytype) TokenMatcher {
        return .{
            .match_fn = matcher_fn,
        };
    }

    pub fn match(self: TokenMatcher, stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
        return self.match_fn(stream, allocator);
    }
};

pub const Tokenizer = struct {
    allocator: std.mem.Allocator,
    stream: *ByteStream,
    matchers: []const TokenMatcher,
    skip_types: []const TokenType,
    token_buffer: std.ArrayList(u8),

    pub fn init(
        allocator: std.mem.Allocator,
        stream: *ByteStream,
        matchers: []const TokenMatcher,
        skip_types: []const TokenType,
    ) !Tokenizer {
        return .{
            .allocator = allocator,
            .stream = stream,
            .matchers = matchers,
            .skip_types = skip_types,
            .token_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.token_buffer.deinit();
    }

    pub fn nextToken(self: *Tokenizer) !?Token {
        while (true) {
            const position = self.stream.getPosition();

            // Try each matcher
            for (self.matchers) |matcher| {
                if (try matcher.match(self.stream, self.allocator)) |token| {
                    // Check if this token type should be skipped
                    var should_skip = false;
                    for (self.skip_types) |skip_type| {
                        if (token.type.id == skip_type.id) {
                            should_skip = true;
                            break;
                        }
                    }

                    if (!should_skip) {
                        return token;
                    } else {
                        // Skip this token and continue
                        break;
                    }
                }
            }

            // No matcher matched, check if at EOF
            const next_byte = try self.stream.peek();
            if (next_byte == null) {
                return null; // EOF
            }

            // No matcher matched but not at EOF - unrecognized character
            _ = try self.stream.consume();
            return Token.init(
                .{ .id = std.math.maxInt(u32), .name = "ERROR" },
                position,
                &[_]u8{next_byte.?}
            );
        }
    }
};
```

### State Machine

```zig
pub const StateTransition = struct {
    token_id: u32,
    next_state: u32,
    action_id: ?u32,

    pub fn init(token_id: u32, next_state: u32, action_id: ?u32) StateTransition {
        return .{
            .token_id = token_id,
            .next_state = next_state,
            .action_id = action_id,
        };
    }
};

pub const State = struct {
    id: u32,
    name: []const u8,
    transitions: []const StateTransition,

    pub fn init(id: u32, name: []const u8, transitions: []const StateTransition) State {
        return .{
            .id = id,
            .name = name,
            .transitions = transitions,
        };
    }

    pub fn findTransition(self: State, token_id: u32) ?StateTransition {
        for (self.transitions) |transition| {
            if (transition.token_id == token_id) {
                return transition;
            }
        }
        return null;
    }
};

pub const ActionFn = *const fn(ctx: *ParserContext, token: Token) anyerror!void;

pub const StateMachine = struct {
    states: []const State,
    actions: []const ActionFn,
    current_state_id: u32,

    pub fn init(states: []const State, actions: []const ActionFn, initial_state_id: u32) StateMachine {
        return .{
            .states = states,
            .actions = actions,
            .current_state_id = initial_state_id,
        };
    }

    pub fn currentState(self: StateMachine) State {
        for (self.states) |state| {
            if (state.id == self.current_state_id) {
                return state;
            }
        }
        unreachable; // Should never happen if state IDs are valid
    }

    pub fn transition(self: *StateMachine, token: Token, ctx: *ParserContext) !void {
        const state = self.currentState();

        if (state.findTransition(token.type.id)) |t| {
            // Execute action if present
            if (t.action_id) |action_id| {
                if (action_id < self.actions.len) {
                    try self.actions[action_id](ctx, token);
                }
            }

            // Update state
            self.current_state_id = t.next_state;
        } else {
            // No transition found for this token
            return error.UnexpectedToken;
        }
    }

    pub fn reset(self: *StateMachine, initial_state_id: u32) void {
        self.current_state_id = initial_state_id;
    }
};
```

### Event Emitter and Handler

```zig
pub const EventType = enum {
    START_DOCUMENT,
    END_DOCUMENT,
    START_ELEMENT,
    END_ELEMENT,
    VALUE,
    ERROR,
    // Generic event types, not tied to specific formats
};

pub const Event = struct {
    type: EventType,
    position: Position,
    data: union {
        string_value: []const u8,
        error_info: struct {
            message: []const u8,
        },
        // Other event data types
    },

    pub fn init(event_type: EventType, position: Position) Event {
        return .{
            .type = event_type,
            .position = position,
            .data = undefined, // Must be set based on event type
        };
    }
};

pub const EventHandler = struct {
    handle_fn: *const fn(event: Event, ctx: ?*anyopaque) anyerror!void,
    context: ?*anyopaque,

    pub fn init(handle_fn: anytype, ctx: ?*anyopaque) EventHandler {
        return .{
            .handle_fn = handle_fn,
            .context = ctx,
        };
    }

    pub fn handle(self: EventHandler, event: Event) !void {
        return self.handle_fn(event, self.context);
    }
};

pub const EventEmitter = struct {
    allocator: std.mem.Allocator,
    handler: ?EventHandler,

    pub fn init(allocator: std.mem.Allocator) EventEmitter {
        return .{
            .allocator = allocator,
            .handler = null,
        };
    }

    pub fn setHandler(self: *EventEmitter, handler: EventHandler) void {
        self.handler = handler;
    }

    pub fn emit(self: *EventEmitter, event: Event) !void {
        if (self.handler) |handler| {
            try handler.handle(event);
        }
    }
};
```

### Parser Context and Main Parser

```zig
// Internal handle-based structure for C API compatibility
const ParserHandle = struct {
    id: u64,
    data: *ParserData,

    fn create(allocator: std.mem.Allocator) !ParserHandle {
        const data = try allocator.create(ParserData);
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

pub const ParserContext = struct {
    allocator: std.mem.Allocator,
    attributes: std.StringHashMap([]const u8),
    value_stack: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) !ParserContext {
        return .{
            .allocator = allocator,
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .value_stack = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ParserContext) void {
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.attributes.deinit();

        for (self.value_stack.items) |value| {
            self.allocator.free(value);
        }
        self.value_stack.deinit();
    }

    pub fn setAttribute(self: *ParserContext, key: []const u8, value: []const u8) !void {
        const key_owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_owned);

        const value_owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_owned);

        // Remove old entry if it exists
        if (self.attributes.get(key)) |old_value| {
            const old_key = self.attributes.getKey(key).?;
            self.allocator.free(old_value);
            _ = self.attributes.remove(old_key);
            self.allocator.free(old_key);
        }

        try self.attributes.put(key_owned, value_owned);
    }

    pub fn getAttribute(self: *ParserContext, key: []const u8) ?[]const u8 {
        return self.attributes.get(key);
    }

    pub fn pushValue(self: *ParserContext, value: []const u8) !void {
        const value_owned = try self.allocator.dupe(u8, value);
        try self.value_stack.append(value_owned);
    }

    pub fn popValue(self: *ParserContext) ?[]const u8 {
        if (self.value_stack.items.len == 0) return null;
        return self.value_stack.pop();
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
        comptime grammar: Grammar,
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

            try data.state_machine.transition(token.?, &data.context);
        }

        // Emit end document event
        try data.event_emitter.emit(Event.init(.END_DOCUMENT, data.stream.?.getPosition()));
    }

    // For incremental parsing
    pub fn process(self: *Parser, chunk: []const u8) !void {
        // Implementation for processing a chunk of data
        // Using internal handle-based design
    }

    pub fn finish(self: *Parser) !void {
        // Implementation for finalizing parsing
        // Using internal handle-based design
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
    var state_machine = StateMachine.init(
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

    return @atomicRmw(u64, &static.next_id, .Add, 1, .Monotonic);
}
```

## Grammar Definition

To make the library truly universal, we need a way to define grammars at compile time. Here's how this might look:

```zig
pub const Grammar = struct {
    // Builder pattern for defining grammars
    pub fn init() GrammarBuilder {
        return GrammarBuilder.init();
    }
};

pub const GrammarBuilder = struct {
    token_defs: std.ArrayList(TokenDef),
    state_defs: std.ArrayList(StateDef),

    pub fn init() GrammarBuilder {
        return .{
            .token_defs = std.ArrayList(TokenDef).init(std.testing.allocator),
            .state_defs = std.ArrayList(StateDef).init(std.testing.allocator),
        };
    }

    pub fn token(self: *GrammarBuilder, name: []const u8, matcher: anytype) !*GrammarBuilder {
        // Define a token with a matcher function or regex
        try self.token_defs.append(.{
            .name = name,
            .matcher = toTokenMatcher(matcher),
        });
        return self;
    }

    pub fn state(self: *GrammarBuilder, name: []const u8) !StateBuilder {
        // Start defining a state
        const state_id = @intCast(u32, self.state_defs.items.len);
        try self.state_defs.append(.{
            .id = state_id,
            .name = name,
            .transitions = std.ArrayList(TransitionDef).init(std.testing.allocator),
        });

        return StateBuilder{
            .grammar_builder = self,
            .state_id = state_id,
        };
    }

    pub fn build(self: *GrammarBuilder) !ParserConfig {
        // Build the final parser configuration
        // This will compile the grammar into an efficient representation

        // Create token matchers
        var matchers = try std.ArrayList(TokenMatcher).initCapacity(
            self.allocator,
            self.token_defs.items.len
        );

        for (self.token_defs.items) |token_def| {
            try matchers.append(token_def.matcher);
        }

        // Create states and transitions
        var states = try std.ArrayList(State).initCapacity(
            self.allocator,
            self.state_defs.items.len
        );

        for (self.state_defs.items) |state_def| {
            var transitions = try std.ArrayList(StateTransition).initCapacity(
                self.allocator,
                state_def.transitions.items.len
            );

            for (state_def.transitions.items) |transition_def| {
                try transitions.append(.{
                    .token_id = transition_def.token_id,
                    .next_state = transition_def.next_state,
                    .action_id = transition_def.action_id,
                });
            }

            try states.append(.{
                .id = state_def.id,
                .name = state_def.name,
                .transitions = transitions.toOwnedSlice(),
            });
        }

        return ParserConfig{
            .tokenizer_config = .{
                .matchers = matchers.toOwnedSlice(),
                .skip_types = skipTypes,
            },
            .state_machine_config = .{
                .states = states.toOwnedSlice(),
                .actions = actions,
                .initial_state_id = initial_state_id,
            },
        };
    }
};

pub const StateBuilder = struct {
    grammar_builder: *GrammarBuilder,
    state_id: u32,

    pub fn on(self: StateBuilder, token_name: []const u8) TransitionBuilder {
        return TransitionBuilder{
            .state_builder = self,
            .token_name = token_name,
        };
    }

    pub fn end(self: StateBuilder) *GrammarBuilder {
        return self.grammar_builder;
    }
};

pub const TransitionBuilder = struct {
    state_builder: StateBuilder,
    token_name: []const u8,

    pub fn to(self: TransitionBuilder, next_state_name: []const u8) ActionBuilder {
        // Find the token ID
        var token_id: ?u32 = null;
        for (self.state_builder.grammar_builder.token_defs.items, 0..) |token_def, i| {
            if (std.mem.eql(u8, token_def.name, self.token_name)) {
                token_id = @intCast(u32, i);
                break;
            }
        }

        if (token_id == null) {
            @panic("Token not found: " ++ self.token_name);
        }

        // Find the next state ID
        var next_state_id: ?u32 = null;
        for (self.state_builder.grammar_builder.state_defs.items) |state_def| {
            if (std.mem.eql(u8, state_def.name, next_state_name)) {
                next_state_id = state_def.id;
                break;
            }
        }

        if (next_state_id == null) {
            @panic("State not found: " ++ next_state_name);
        }

        return ActionBuilder{
            .transition_builder = self,
            .next_state_id = next_state_id.?,
        };
    }
};

pub const ActionBuilder = struct {
    transition_builder: TransitionBuilder,
    next_state_id: u32,

    pub fn action(self: ActionBuilder, action_name: []const u8) *StateBuilder {
        // Find the action ID
        var action_id: ?u32 = null;
        // [Logic to find action ID by name]

        const state_def = &self.transition_builder.state_builder.grammar_builder.state_defs.items[self.transition_builder.state_builder.state_id];

        // Add the transition
        state_def.transitions.append(.{
            .token_id = token_id.?,
            .next_state = self.next_state_id,
            .action_id = action_id,
        }) catch @panic("Failed to add transition");

        return &self.transition_builder.state_builder;
    }

    pub fn noAction(self: ActionBuilder) *StateBuilder {
        const state_def = &self.transition_builder.state_builder.grammar_builder.state_defs.items[self.transition_builder.state_builder.state_id];

        // Add the transition without an action
        state_def.transitions.append(.{
            .token_id = token_id.?,
            .next_state = self.next_state_id,
            .action_id = null,
        }) catch @panic("Failed to add transition");

        return &self.transition_builder.state_builder;
    }
};
```

## Compile-Time Grammar Definition Example

```zig
// Define a grammar at compile time
const example_grammar = comptime blk: {
    var builder = Grammar.init();

    // Define tokens
    try builder.token("WORD", "[a-zA-Z]+");
    try builder.token("NUMBER", "[0-9]+");
    try builder.token("WHITESPACE", "\\s+");
    try builder.token("PUNCT", "[.,;:!?]");

    // Define states and transitions
    const state_builder = try builder.state("INITIAL");
    try state_builder
        .on("WORD").to("INITIAL").action("emitWord")
        .on("NUMBER").to("INITIAL").action("emitNumber")
        .on("PUNCT").to("INITIAL").action("emitPunct")
        .on("WHITESPACE").to("INITIAL").noAction()
        .end();

    // Build the grammar
    const parser_config = try builder.build();
    break :blk parser_config;
};

// Use the grammar to create a parser
pub fn createExampleParser(allocator: std.mem.Allocator, source: anytype) !Parser {
    return Parser.init(
        allocator,
        source,
        example_grammar.tokenizer_config,
        example_grammar.state_machine_config,
        4096 // buffer size
    );
}
```

## Optimizations

### 1. Compile-Time Token Tables

```zig
// Character classification table generated at compile time
const is_alpha = comptime blk: {
    var table: [256]bool = [_]bool{false} ** 256;
    var i: u8 = 'a';
    while (i <= 'z') : (i += 1) {
        table[i] = true;
    }
    i = 'A';
    while (i <= 'Z') : (i += 1) {
        table[i] = true;
    }
    break :blk table;
};

// Fast character classification
fn isAlpha(c: u8) bool {
    return is_alpha[c];
}
```

### 2. SIMD-Accelerated Token Matching

```zig
fn findStringEndSIMD(data: []const u8, start: usize) usize {
    // SIMD implementation for platforms that support it
    if (comptime std.Target.current.cpu.features.isEnabled(.sse4_2)) {
        return findStringEndSSE42(data, start);
    } else if (comptime std.Target.current.cpu.features.isEnabled(.neon)) {
        return findStringEndNeon(data, start);
    } else {
        return findStringEndScalar(data, start);
    }
}
```

### 3. Memory Pool for Tokens

```zig
pub const TokenPool = struct {
    allocator: std.mem.Allocator,
    pool: []u8,
    position: usize,

    pub fn init(allocator: std.mem.Allocator, size: usize) !TokenPool {
        return .{
            .allocator = allocator,
            .pool = try allocator.alloc(u8, size),
            .position = 0,
        };
    }

    pub fn deinit(self: *TokenPool) void {
        self.allocator.free(self.pool);
    }

    pub fn allocate(self: *TokenPool, size: usize) ![]u8 {
        if (self.position + size > self.pool.len) {
            return error.OutOfMemory;
        }

        const result = self.pool[self.position..self.position+size];
        self.position += size;
        return result;
    }

    pub fn reset(self: *TokenPool) void {
        self.position = 0;
    }
};
```

## Extension Points

The framework provides several extension points for customizing behavior:

### 1. Custom Token Matchers

```zig
fn customTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    // Custom token matching logic
    const start_pos = stream.getPosition();

    // Try to match a specific pattern
    // ...

    if (matched) {
        return Token.init(
            .{ .id = MY_TOKEN_ID, .name = "MY_TOKEN" },
            start_pos,
            lexeme
        );
    }

    return null; // No match
}

// Use it in a grammar
try grammar_builder.token("CUSTOM", customTokenMatcher);
```

### 2. Custom State Machine Actions

```zig
fn customAction(ctx: *ParserContext, token: Token) !void {
    // Custom action implementation
    try ctx.setAttribute("lastToken", token.lexeme);
    try ctx.pushValue(token.lexeme);

    // ...
}

// Register the action
try grammar_builder.action("customAction", customAction);
```

### 3. Custom Event Handlers

```zig
fn customEventHandler(event: Event, ctx: ?*anyopaque) !void {
    const my_context = @ptrCast(*MyContext, @alignCast(@alignOf(MyContext), ctx.?));

    switch (event.type) {
        .START_DOCUMENT => try my_context.startDocument(),
        .END_DOCUMENT => try my_context.endDocument(),
        .VALUE => {
            const value = event.data.string_value;
            try my_context.processValue(value);
        },
        // Handle other events...
        else => {},
    }
}

// Use the handler
var my_context = MyContext{};
parser.setEventHandler(EventHandler.init(customEventHandler, &my_context));
```

## Performance Considerations

1. **Buffer Management**:

   - Use reasonably sized buffers (4-16KB) to minimize memory usage while maintaining throughput
   - Consider using memory mapping for very large files

2. **Memory Allocation**:

   - Minimize allocations during parsing
   - Use arena allocators or memory pools for tokens and temporary data
   - Provide options for zero-copy operation where possible

3. **SIMD Acceleration**:

   - Use SIMD instructions for common operations like searching for delimiters
   - Provide fallbacks for platforms without SIMD support

4. **Parsing Strategies**:

   - Enable different parsing strategies based on input characteristics
   - Offer specialized fast paths for common patterns

5. **Benchmarking**:
   - Include comprehensive benchmarks for different input types and sizes
   - Compare against other parsing libraries

## Cross-Language Integration Design

ZigParse is designed with eventual cross-language adoption in mind. While the initial implementation focuses on Zig's strengths for maximum performance, the architecture includes considerations for future C API compatibility that would enable bindings for many programming languages.

### Future C API Compatibility

The internal design follows these principles to ensure straightforward C API development later:

1. **Handle-Based Resource Management**

   - Parser and related objects use internal handle identifiers
   - Clear ownership and lifecycle patterns
   - Explicit resource creation and destruction

2. **C-Compatible Core Data Structures**

   - Internal representation avoids Zig-only features where possible
   - Data is structured to allow efficient boundary crossing
   - Memory ownership patterns are compatible with C expectations

3. **Error Handling for Cross-Language Use**
   - Error codes designed for extraction into C error reporting
   - Detailed error messages stored in a cross-language compatible format
   - Recovery mechanisms that work across language boundaries

### Cross-Language Architecture Pattern

```
┌─────────────────────────┐      ┌───────────────────┐
│ Zig API (comptime)      │      │ Future C API      │
│ - Grammar builder       │      │ - String config   │
│ - Optimized interfaces  │      │ - Handle based    │
└─────────┬───────────────┘      └────────┬──────────┘
          │                                │
          ▼                                ▼
┌─────────────────────────────────────────────────────┐
│ Internal Implementation                             │
│ - Handle-based resource tracking                    │
│ - C-compatible core algorithms                      │
│ - Clean separation of concerns                      │
│ - Both runtime and compile-time optimization paths  │
└─────────────────────────────────────────────────────┘
```

### Future C API Sketch

```c
// Parser creation and destruction
ZP_Parser* zp_create_parser(const char* grammar_json, size_t len);
void zp_destroy_parser(ZP_Parser* parser);

// Parsing operations
ZP_Result zp_parse_chunk(ZP_Parser* parser, const char* data, size_t len);
ZP_Result zp_finish_parsing(ZP_Parser* parser);

// Event handling
typedef void (*ZP_EventCallback)(int event_type, const char* data,
                                 size_t data_len, void* user_data);
ZP_Result zp_set_event_handler(ZP_Parser* parser, ZP_EventCallback callback,
                              void* user_data);

// Error handling
const char* zp_get_error(ZP_Parser* parser);
int zp_get_error_code(ZP_Parser* parser);
```

## Implementation Strategy

To make progress incrementally:

1. **Phase 1: Core Infrastructure**

   - Implement ByteStream with efficient buffering
   - Basic Tokenizer with simple matchers
   - Simple StateMachine implementation
   - Event emission system
   - Handle-based internal design for future C compatibility

2. **Phase 2: Grammar Definition**

   - Compile-time grammar builder
   - Token matcher generators
   - State and transition compilation
   - Internal representation with C API in mind

3. **Phase 3: Optimizations**

   - Memory management improvements
   - SIMD acceleration where applicable
   - Performance tuning
   - Benchmark against other parsing libraries

4. **Phase 4: Zig-Specific Features**

   - Advanced compile-time optimizations
   - Specialized interfaces for Zig users
   - Integration with Zig ecosystem

5. **Phase 5: C API and Cross-Language Support**

   - C API implementation
   - API documentation for C users
   - Example bindings for popular languages
   - Cross-language testing framework

6. **Phase 6: Examples and Documentation**
   - Create examples for common formats (JSON, XML, CSV)
   - Comprehensive documentation and usage guides
   - Benchmarking suite
   - Cross-language examples

## Usage Example

```zig
// Define a grammar (or use a predefined one)
const my_grammar = blk: {
    var builder = Grammar.init();

    // Define tokens and states
    // ...

    break :blk try builder.build();
};

// Create a parser
var parser = try Parser.init(
    allocator,
    my_file,
    my_grammar.tokenizer_config,
    my_grammar.state_machine_config,
    8192 // buffer size
);
defer parser.deinit();

// Set up event handling
var my_handler = MyHandler{};
parser.setEventHandler(EventHandler.init(myEventHandler, &my_handler));

// Parse the input
try parser.parse();

// Or process incrementally
var buffer: [4096]u8 = undefined;
while (true) {
    const bytes_read = try file.read(&buffer);
    if (bytes_read == 0) break;
    try parser.process(buffer[0..bytes_read]);
}
try parser.finish();
```

## Conclusion

ZigParse provides a foundation for building high-performance, memory-efficient streaming parsers for any grammar or format. By leveraging Zig's compile-time features and focusing on performance without sacrificing safety, it enables developers to create parsers that can handle large inputs with minimal resource usage.

The framework follows the Zig philosophy by providing clear, precise tools with well-defined behavior, making edge cases explicit, and focusing on correctness and performance.

With its handle-based internal design and focus on C API compatibility, ZigParse is positioned to become not just a Zig library but a universal parsing solution that can be used across many programming languages. The initial focus on Zig-specific optimizations ensures we don't compromise on performance, while the forward-looking architecture ensures we can expand to serve a wider developer community in the future.
