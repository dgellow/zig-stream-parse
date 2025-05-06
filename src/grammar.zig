const std = @import("std");
const TokenType = @import("tokenizer.zig").TokenType;
const TokenMatcher = @import("tokenizer.zig").TokenMatcher;
const State = @import("state_machine.zig").State;
const StateTransition = @import("state_machine.zig").StateTransition;
const types = @import("types.zig");
const ActionFn = types.ActionFn;

// Define these locally to avoid circular dependencies
pub const TokenizerConfig = struct {
    matchers: []const TokenMatcher,
    skip_types: []const TokenType,
};

pub const StateMachineConfig = struct {
    states: []const State,
    actions: []const ActionFn,
    initial_state_id: u32,
};

pub const TokenDef = struct {
    name: []const u8,
    matcher: TokenMatcher,
};

pub const TransitionDef = struct {
    token_id: u32,
    next_state: u32,
    action_id: ?u32,
};

pub const StateDef = struct {
    id: u32,
    name: []const u8,
    transitions: std.ArrayList(TransitionDef),
};

pub const Grammar = struct {
    // Builder pattern for defining grammars
    pub fn init() GrammarBuilder {
        return GrammarBuilder.init();
    }
};

pub const GrammarBuilder = struct {
    token_defs: std.ArrayList(TokenDef),
    state_defs: std.ArrayList(StateDef),
    action_defs: std.ArrayList(struct { name: []const u8, fn_ptr: ActionFn }),
    initial_state_name: ?[]const u8,
    skip_token_names: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init() GrammarBuilder {
        return .{
            .token_defs = std.ArrayList(TokenDef).init(std.testing.allocator),
            .state_defs = std.ArrayList(StateDef).init(std.testing.allocator),
            .action_defs = std.ArrayList(struct { name: []const u8, fn_ptr: ActionFn }).init(std.testing.allocator),
            .initial_state_name = null,
            .skip_token_names = std.ArrayList([]const u8).init(std.testing.allocator),
            .allocator = std.testing.allocator,
        };
    }

    pub fn deinit(self: *GrammarBuilder) void {
        self.token_defs.deinit();
        
        for (self.state_defs.items) |*state_def| {
            state_def.transitions.deinit();
        }
        self.state_defs.deinit();
        
        self.action_defs.deinit();
        self.skip_token_names.deinit();
    }

    pub fn token(self: *GrammarBuilder, name: []const u8, matcher: TokenMatcher) !*GrammarBuilder {
        // Define a token with a matcher function
        try self.token_defs.append(.{
            .name = name,
            .matcher = matcher,
        });
        return self;
    }

    pub fn skipToken(self: *GrammarBuilder, name: []const u8) !*GrammarBuilder {
        // Define a token that should be skipped during tokenization
        try self.skip_token_names.append(name);
        return self;
    }

    pub fn action(self: *GrammarBuilder, name: []const u8, fn_ptr: ActionFn) !*GrammarBuilder {
        // Define an action function
        try self.action_defs.append(.{
            .name = name,
            .fn_ptr = fn_ptr,
        });
        return self;
    }

    pub fn initialState(self: *GrammarBuilder, name: []const u8) !*GrammarBuilder {
        // Set the initial state
        self.initial_state_name = name;
        return self;
    }

    pub fn state(self: *GrammarBuilder, name: []const u8) !StateBuilder {
        // Start defining a state
        const state_id = @as(u32, @intCast(self.state_defs.items.len));
        try self.state_defs.append(.{
            .id = state_id,
            .name = name,
            .transitions = std.ArrayList(TransitionDef).init(self.allocator),
        });

        return StateBuilder{
            .grammar_builder = self,
            .state_id = state_id,
        };
    }

    fn findTokenId(self: *GrammarBuilder, name: []const u8) ?u32 {
        for (self.token_defs.items, 0..) |token_def, i| {
            if (std.mem.eql(u8, token_def.name, name)) {
                return @as(u32, @intCast(i));
            }
        }
        return null;
    }

    fn findStateId(self: *GrammarBuilder, name: []const u8) ?u32 {
        for (self.state_defs.items) |state_def| {
            if (std.mem.eql(u8, state_def.name, name)) {
                return state_def.id;
            }
        }
        return null;
    }

    fn findActionId(self: *GrammarBuilder, name: []const u8) ?u32 {
        for (self.action_defs.items, 0..) |action_def, i| {
            if (std.mem.eql(u8, action_def.name, name)) {
                return @as(u32, @intCast(i));
            }
        }
        return null;
    }

    pub fn build(self: *GrammarBuilder) !struct {
        tokenizer_config: TokenizerConfig,
        state_machine_config: StateMachineConfig,
    } {
        // Check for initial state
        if (self.initial_state_name == null) {
            return error.NoInitialStateSpecified;
        }

        // Build token types and matchers
        var token_types = try self.allocator.alloc(TokenType, self.token_defs.items.len);
        var matchers = try self.allocator.alloc(TokenMatcher, self.token_defs.items.len);

        for (self.token_defs.items, 0..) |token_def, i| {
            token_types[i] = .{
                .id = @as(u32, @intCast(i)),
                .name = token_def.name,
            };
            matchers[i] = token_def.matcher;
        }

        // Build skip token types
        var skip_types = std.ArrayList(TokenType).init(self.allocator);
        defer skip_types.deinit();

        for (self.skip_token_names.items) |name| {
            if (self.findTokenId(name)) |token_id| {
                try skip_types.append(.{
                    .id = token_id,
                    .name = name,
                });
            }
        }

        // Build states and transitions
        var states = try self.allocator.alloc(State, self.state_defs.items.len);

        for (self.state_defs.items, 0..) |state_def, i| {
            var transitions = try self.allocator.alloc(StateTransition, state_def.transitions.items.len);

            for (state_def.transitions.items, 0..) |transition_def, j| {
                transitions[j] = .{
                    .token_id = transition_def.token_id,
                    .next_state = transition_def.next_state,
                    .action_id = transition_def.action_id,
                };
            }

            states[i] = .{
                .id = state_def.id,
                .name = state_def.name,
                .transitions = transitions,
            };
        }

        // Build actions
        var actions = try self.allocator.alloc(ActionFn, self.action_defs.items.len);

        for (self.action_defs.items, 0..) |action_def, i| {
            actions[i] = action_def.fn_ptr;
        }

        // Find initial state ID
        const initial_state_id = self.findStateId(self.initial_state_name.?) orelse
            return error.InitialStateNotFound;

        return .{
            .tokenizer_config = .{
                .matchers = matchers,
                .skip_types = skip_types.toOwnedSlice(),
            },
            .state_machine_config = .{
                .states = states,
                .actions = actions,
                .initial_state_id = initial_state_id,
            },
        };
    }
};

pub const StateBuilder = struct {
    grammar_builder: *GrammarBuilder,
    state_id: u32,

    pub fn on(self: StateBuilder, token_name: []const u8) !TransitionBuilder {
        // Find the token ID
        const token_id = self.grammar_builder.findTokenId(token_name) orelse
            return error.TokenNotFound;

        return TransitionBuilder{
            .state_builder = self,
            .token_id = token_id,
        };
    }

    pub fn end(self: StateBuilder) *GrammarBuilder {
        return self.grammar_builder;
    }
};

pub const TransitionBuilder = struct {
    state_builder: StateBuilder,
    token_id: u32,

    pub fn to(self: TransitionBuilder, next_state_name: []const u8) !ActionBuilder {
        // Find the next state ID
        const next_state_id = self.state_builder.grammar_builder.findStateId(next_state_name) orelse
            return error.StateNotFound;

        return ActionBuilder{
            .transition_builder = self,
            .next_state_id = next_state_id,
        };
    }
};

pub const ActionBuilder = struct {
    transition_builder: TransitionBuilder,
    next_state_id: u32,

    pub fn action(self: ActionBuilder, action_name: []const u8) !StateBuilder {
        // Find the action ID
        const action_id = self.transition_builder.state_builder.grammar_builder.findActionId(action_name) orelse
            return error.ActionNotFound;

        const state_id = self.transition_builder.state_builder.state_id;
        var state_def = &self.transition_builder.state_builder.grammar_builder.state_defs.items[state_id];

        // Add the transition
        try state_def.transitions.append(.{
            .token_id = self.transition_builder.token_id,
            .next_state = self.next_state_id,
            .action_id = action_id,
        });

        return self.transition_builder.state_builder;
    }

    pub fn noAction(self: ActionBuilder) !StateBuilder {
        const state_id = self.transition_builder.state_builder.state_id;
        var state_def = &self.transition_builder.state_builder.grammar_builder.state_defs.items[state_id];

        // Add the transition without an action
        try state_def.transitions.append(.{
            .token_id = self.transition_builder.token_id,
            .next_state = self.next_state_id,
            .action_id = null,
        });

        return self.transition_builder.state_builder;
    }
};