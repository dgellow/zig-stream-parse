const std = @import("std");
const Position = @import("common.zig").Position;

pub const ByteStream = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    position: usize,
    line: usize,
    column: usize,
    exhausted: bool,

    pub fn init(allocator: std.mem.Allocator, content: []const u8, buffer_size: usize) !ByteStream {
        _ = buffer_size; // Not needed for this implementation
        return .{
            .allocator = allocator,
            .content = content,
            .position = 0,
            .line = 1,
            .column = 1,
            .exhausted = false,
        };
    }

    pub fn deinit(self: *ByteStream) void {
        _ = self;
        // No need to free anything as we don't own the content
    }

    pub fn peek(self: *ByteStream) !?u8 {
        if (self.exhausted or self.position >= self.content.len) {
            return null;
        }
        
        return self.content[self.position];
    }

    pub fn peekOffset(self: *ByteStream, offset: usize) !?u8 {
        const pos = self.position + offset;
        if (self.exhausted or pos >= self.content.len) {
            return null;
        }
        
        return self.content[pos];
    }

    pub fn consume(self: *ByteStream) !?u8 {
        if (self.exhausted or self.position >= self.content.len) {
            self.exhausted = true;
            return null;
        }

        const byte = self.content[self.position];
        self.position += 1;

        if (byte == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
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

    pub fn getPosition(self: *const ByteStream) Position {
        return .{
            .offset = self.position,
            .line = self.line,
            .column = self.column,
        };
    }
};