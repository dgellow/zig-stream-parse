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
        // More defensive bounds checking
        if (self.exhausted or self.position >= self.content.len) {
            self.exhausted = true; // Mark as exhausted for safety
            return null;
        }
        
        // Double-check bounds before accessing
        if (self.position < self.content.len) {
            return self.content[self.position];
        } else {
            self.exhausted = true;
            return null;
        }
    }

    pub fn peekOffset(self: *ByteStream, offset: usize) !?u8 {
        // Avoid integer overflow when calculating position
        if (offset > std.math.maxInt(usize) - self.position) {
            self.exhausted = true;
            return null;
        }
        
        const pos = self.position + offset;
        if (self.exhausted or pos >= self.content.len) {
            return null;
        }
        
        // Double-check bounds for safety
        if (pos < self.content.len) {
            return self.content[pos];
        } else {
            return null;
        }
    }

    pub fn consume(self: *ByteStream) !?u8 {
        // Check if already exhausted or at end
        if (self.exhausted or self.position >= self.content.len) {
            self.exhausted = true;
            return null;
        }

        // Double-check position before accessing content
        if (self.position < self.content.len) {
            const byte = self.content[self.position];
            
            // Update position safely
            if (self.position < std.math.maxInt(usize)) {
                self.position += 1;
            } else {
                self.exhausted = true;
            }

            // Update line and column tracking
            if (byte == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }

            return byte;
        } else {
            self.exhausted = true;
            return null;
        }
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