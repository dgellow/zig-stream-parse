const std = @import("std");
const Position = @import("common.zig").Position;

/// Enhanced ByteStream that supports different source types
pub const ByteStream = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    buffer_start: usize,
    buffer_end: usize,
    position: usize,
    line: usize,
    column: usize,
    exhausted: bool,
    
    // Internal source storage
    memory_source: ?[]const u8,
    file_source: ?std.fs.File,
    
    /// Create a ByteStream from a memory slice
    pub fn fromMemory(allocator: std.mem.Allocator, memory: []const u8, buffer_size: usize) !ByteStream {
        const buffer = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buffer);
        
        return ByteStream{
            .allocator = allocator,
            .buffer = buffer,
            .buffer_start = 0,
            .buffer_end = 0,
            .position = 0,
            .line = 1,
            .column = 1,
            .exhausted = false,
            .memory_source = memory,
            .file_source = null,
        };
    }
    
    /// Create a ByteStream from a file
    pub fn fromFile(allocator: std.mem.Allocator, file: std.fs.File, buffer_size: usize) !ByteStream {
        const buffer = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buffer);
        
        return ByteStream{
            .allocator = allocator,
            .buffer = buffer,
            .buffer_start = 0,
            .buffer_end = 0,
            .position = 0,
            .line = 1,
            .column = 1,
            .exhausted = false,
            .memory_source = null,
            .file_source = file,
        };
    }
    
    /// Create a ByteStream from a file reader
    /// Note: This is a simplified implementation, for full generics support we would need more advanced type handling
    pub fn fromReader(allocator: std.mem.Allocator, reader_file: std.fs.File, buffer_size: usize) !ByteStream {
        // For now, we just use the file directly since the reader is backed by a file
        return fromFile(allocator, reader_file, buffer_size);
    }
    
    /// Backward compatibility
    pub fn init(allocator: std.mem.Allocator, content: []const u8, buffer_size: usize) !ByteStream {
        return fromMemory(allocator, content, buffer_size);
    }

    /// Clean up resources
    pub fn deinit(self: *ByteStream) void {
        self.allocator.free(self.buffer);
        // We don't own the file or memory source, so no need to free them
    }

    /// Fill the buffer with more data from the source
    pub fn fillBuffer(self: *ByteStream) !void {
        // If there's unprocessed data, move it to the beginning
        if (self.buffer_start > 0) {
            var i: usize = 0;
            while (i < self.buffer_end - self.buffer_start) : (i += 1) {
                self.buffer[i] = self.buffer[self.buffer_start + i];
            }
            self.buffer_end -= self.buffer_start;
            self.buffer_start = 0;
        }

        // If buffer is full, we can't read more
        if (self.buffer_end == self.buffer.len) return;

        // Read more data from the appropriate source
        var bytes_read: usize = 0;
        
        if (self.memory_source) |memory| {
            const pos = self.position - (self.buffer_end - self.buffer_start);
            if (pos < memory.len) {
                const remaining_buf_space = self.buffer.len - self.buffer_end;
                const remaining_data = memory.len - pos;
                const to_copy = @min(remaining_buf_space, remaining_data);
                
                var i: usize = 0;
                while (i < to_copy) : (i += 1) {
                    self.buffer[self.buffer_end + i] = memory[pos + i];
                }
                
                bytes_read = to_copy;
            }
        } else if (self.file_source) |file| {
            bytes_read = try file.read(self.buffer[self.buffer_end..]);
        }

        // If we read 0 bytes and the buffer is empty, we're at EOF
        if (bytes_read == 0 and self.buffer_start == self.buffer_end) {
            self.exhausted = true;
        }

        self.buffer_end += bytes_read;
    }

    /// Look at the next byte without consuming it
    pub fn peek(self: *ByteStream) !?u8 {
        return self.peekOffset(0);
    }

    /// Look at a byte at a given offset without consuming it
    pub fn peekOffset(self: *ByteStream, offset: usize) !?u8 {
        // Avoid integer overflow when calculating position
        if (offset > std.math.maxInt(usize) - self.buffer_start) {
            return null;
        }
        
        // If we're trying to peek beyond the buffer, fill it
        if (self.buffer_start + offset >= self.buffer_end) {
            try self.fillBuffer();
            // If we still can't peek that far, we're at EOF
            if (self.buffer_start + offset >= self.buffer_end) {
                return null;
            }
        }
        
        return self.buffer[self.buffer_start + offset];
    }

    /// Consume the next byte and return it
    pub fn consume(self: *ByteStream) !?u8 {
        const byte = try self.peek();
        if (byte == null) {
            self.exhausted = true;
            return null;
        }
        
        self.buffer_start += 1;
        self.position += 1;

        // Update line and column tracking
        if (byte.? == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }

        return byte;
    }

    /// Consume a byte only if it matches the expected value
    pub fn consumeIf(self: *ByteStream, expected: u8) !bool {
        const byte = try self.peek();
        if (byte != null and byte.? == expected) {
            _ = try self.consume();
            return true;
        }
        return false;
    }

    /// Consume up to count bytes
    pub fn consumeCount(self: *ByteStream, count: usize) !usize {
        var consumed: usize = 0;
        while (consumed < count) {
            if ((try self.consume()) == null) break;
            consumed += 1;
        }
        return consumed;
    }

    /// Get the current position information
    pub fn getPosition(self: *const ByteStream) Position {
        return .{
            .offset = self.position,
            .line = self.line,
            .column = self.column,
        };
    }
    
    /// Reset the stream to the beginning (only works for memory sources)
    pub fn reset(self: *ByteStream) !void {
        if (self.memory_source != null) {
            self.buffer_start = 0;
            self.buffer_end = 0;
            self.position = 0;
            self.line = 1;
            self.column = 1;
            self.exhausted = false;
        } else {
            return error.CannotResetNonMemorySource;
        }
    }
};