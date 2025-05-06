const std = @import("std");
const Position = @import("common.zig").Position;
const Token = @import("tokenizer.zig").Token;

// Define ParserContext here to break the circular dependency
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

// Action function type
pub const ActionFn = *const fn(ctx: *ParserContext, token: Token) anyerror!void;