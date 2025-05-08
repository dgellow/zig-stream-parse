const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const types = @import("types.zig");
const error_mod = @import("error.zig");
const ParserContext = types.ParserContext;
pub const ActionFn = types.ActionFn;

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
    
    // Get a list of expected token IDs from this state's transitions
    pub fn getExpectedTokenTypes(self: State, allocator: std.mem.Allocator) ![]u32 {
        var result = std.ArrayList(u32).init(allocator);
        errdefer result.deinit();
        
        for (self.transitions) |transition| {
            try result.append(transition.token_id);
        }
        
        return result.toOwnedSlice();
    }
};

// Configuration for error recovery
pub const ErrorRecoveryConfig = struct {
    strategy: error_mod.ErrorRecoveryStrategy = .stop_on_first_error,
    sync_token_types: []const u32 = &[_]u32{},
    max_errors: usize = 10,
};

pub const StateMachine = struct {
    allocator: std.mem.Allocator,
    states: []const State,
    actions: []const ActionFn,
    current_state_id: u32,
    
    // Error handling enhancements
    error_reporter: error_mod.ErrorReporter,
    recovery_config: ErrorRecoveryConfig,
    recovery: error_mod.ErrorRecovery,
    
    // Statistics for diagnostics
    error_count: usize = 0,
    warning_count: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        states: []const State, 
        actions: []const ActionFn, 
        initial_state_id: u32,
        recovery_config: ErrorRecoveryConfig,
    ) StateMachine {
        return .{
            .allocator = allocator,
            .states = states,
            .actions = actions,
            .current_state_id = initial_state_id,
            .error_reporter = error_mod.ErrorReporter.init(allocator),
            .recovery_config = recovery_config,
            .recovery = error_mod.ErrorRecovery.init(recovery_config.sync_token_types),
        };
    }
    
    pub fn deinit(self: *StateMachine) void {
        self.error_reporter.deinit();
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
        std.debug.print("Current state: {s} (id: {d})\n", .{state.name, state.id});

        if (state.findTransition(token.type.id)) |t| {
            // Execute action if present
            if (t.action_id) |action_id| {
                if (action_id < self.actions.len) {
                    std.debug.print("Executing action: {d}\n", .{action_id});
                    try self.actions[action_id](ctx, token);
                }
            }

            // Update state
            std.debug.print("Transitioning to state: {d}\n", .{t.next_state});
            self.current_state_id = t.next_state;
        } else {
            // No transition found for this token - this is an error situation
            std.debug.print("No transition found for token type: {d}\n", .{token.type.id});
            
            // Create error context with detailed information
            var error_ctx = try error_mod.ErrorContext.init(
                self.allocator,
                error_mod.ErrorCode.unexpected_token,
                token.position,
                "Unexpected token"
            );
            error_ctx.setToken(token);
            
            // Add state machine context
            try error_ctx.setStateContext(self.allocator, state.id, state.name);
            
            // Add expected token types
            const expected_tokens = try state.getExpectedTokenTypes(self.allocator);
            defer self.allocator.free(expected_tokens);
            try error_ctx.setExpectedTokenTypes(self.allocator, expected_tokens);
            
            // Generate recovery hint
            try self.recovery.generateHint(self.allocator, &error_ctx);
            
            // Report the error
            try self.error_reporter.report(error_ctx);
            self.error_count += 1;
            
            // Handle error based on recovery strategy
            switch (self.recovery_config.strategy) {
                .stop_on_first_error => {
                    return error.UnexpectedToken;
                },
                .continue_after_error => {
                    // Just continue without changing state
                    if (self.error_count >= self.recovery_config.max_errors) {
                        return error.TooManyErrors;
                    }
                },
                .synchronize => {
                    // We'll skip tokens until we find a synchronization point
                    // But this requires the caller to continue processing
                    if (self.error_count >= self.recovery_config.max_errors) {
                        return error.TooManyErrors;
                    }
                    return error.NeedSynchronization;
                },
                .repair_and_continue => {
                    // Advanced recovery - we could try to insert a token or skip this one
                    // This is complex and would need grammar-specific knowledge
                    if (self.error_count >= self.recovery_config.max_errors) {
                        return error.TooManyErrors;
                    }
                },
            }
        }
    }
    
    // Special transition function that doesn't generate errors
    // Useful during error recovery
    pub fn tryTransition(self: *StateMachine, token: Token, ctx: *ParserContext) bool {
        const state = self.currentState();
        if (state.findTransition(token.type.id)) |t| {
            // Execute action if present
            if (t.action_id) |action_id| {
                if (action_id < self.actions.len) {
                    self.actions[action_id](ctx, token) catch {
                        return false;
                    };
                }
            }
            
            // Update state
            self.current_state_id = t.next_state;
            return true;
        }
        return false;
    }
    
    // Check if a token is a synchronization point
    pub fn isSyncPoint(self: StateMachine, token_type: u32) bool {
        return self.recovery.isSyncPoint(token_type);
    }
    
    // Get all reported errors
    pub fn getErrors(self: StateMachine) []error_mod.ErrorContext {
        return self.error_reporter.getErrors();
    }
    
    // Get all reported warnings
    pub fn getWarnings(self: StateMachine) []error_mod.ErrorContext {
        return self.error_reporter.getWarnings();
    }
    
    // Print all errors and warnings
    pub fn printErrors(self: StateMachine) !void {
        try self.error_reporter.printAll();
    }

    pub fn reset(self: *StateMachine, initial_state_id: u32) void {
        self.current_state_id = initial_state_id;
    }
};