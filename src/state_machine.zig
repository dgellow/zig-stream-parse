const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const types = @import("types.zig");
const ParserContext = types.ParserContext;
const ActionFn = types.ActionFn;

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
            // No transition found for this token
            std.debug.print("No transition found for token type: {d}\n", .{token.type.id});
            return error.UnexpectedToken;
        }
    }

    pub fn reset(self: *StateMachine, initial_state_id: u32) void {
        self.current_state_id = initial_state_id;
    }
};