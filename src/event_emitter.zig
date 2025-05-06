const std = @import("std");
const Position = @import("common.zig").Position;

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
    data: EventData,

    pub fn init(event_type: EventType, position: Position) Event {
        return .{
            .type = event_type,
            .position = position,
            .data = .{ .string_value = "" }, // Default initialization
        };
    }
};

pub const EventData = union {
    string_value: []const u8,
    error_info: struct {
        message: []const u8,
    },
    // Other event data types
};

pub const EventHandler = struct {
    handle_fn: *const fn(event: Event, ctx: ?*anyopaque) anyerror!void,
    context: ?*anyopaque,

    pub fn init(comptime handle_fn: anytype, ctx: ?*anyopaque) EventHandler {
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