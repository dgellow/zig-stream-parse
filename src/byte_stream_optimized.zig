const std = @import("std");
const Position = @import("common.zig").Position;

/// An efficient ByteStream implementation with optimized buffer management for incremental parsing
pub const ByteStream = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    buffer_start: usize,
    buffer_end: usize,
    position: usize,
    line: usize,
    column: usize,
    exhausted: bool,
    
    // Internal source tracking
    source_type: SourceType,
    memory_source: ?[]const u8,
    file_source: ?std.fs.File,
    reader_source: ?std.io.AnyReader,
    owns_buffer: bool,  // Whether we need to free the buffer on deinit
    
    // Total bytes consumed from the beginning
    total_consumed: usize,
    
    // Growth factor for buffer resizing
    buffer_growth_factor: f32 = 1.5,
    
    // Statistics for optimization tracking
    grow_count: usize = 0,
    compact_count: usize = 0,
    
    pub const SourceType = enum {
        memory,
        file,
        reader,
        custom,
    };
    
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
            .source_type = .memory,
            .memory_source = memory,
            .file_source = null,
            .reader_source = null,
            .owns_buffer = true,
            .total_consumed = 0,
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
            .source_type = .file,
            .memory_source = null,
            .file_source = file,
            .reader_source = null,
            .owns_buffer = true,
            .total_consumed = 0,
        };
    }
    
    /// Create a ByteStream from a reader
    pub fn fromReader(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !ByteStream {
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
            .source_type = .reader,
            .memory_source = null,
            .file_source = null,
            .reader_source = reader,
            .owns_buffer = true,
            .total_consumed = 0,
        };
    }
    
    /// Create a ByteStream with a preallocated buffer
    pub fn withBuffer(allocator: std.mem.Allocator, buffer: []u8) ByteStream {
        return ByteStream{
            .allocator = allocator,
            .buffer = buffer,
            .buffer_start = 0,
            .buffer_end = 0,
            .position = 0,
            .line = 1,
            .column = 1,
            .exhausted = false,
            .source_type = .custom,
            .memory_source = null,
            .file_source = null,
            .reader_source = null,
            .owns_buffer = false,  // We don't own this buffer
            .total_consumed = 0,
        };
    }
    
    /// Backward compatibility
    pub fn init(allocator: std.mem.Allocator, content: []const u8, buffer_size: usize) !ByteStream {
        return fromMemory(allocator, content, buffer_size);
    }

    /// Clean up resources
    pub fn deinit(self: *ByteStream) void {
        if (self.owns_buffer) {
            self.allocator.free(self.buffer);
        }
        // We don't own the sources, so no need to free them
    }
    
    /// Append new data to the stream (for incremental parsing)
    pub fn append(self: *ByteStream, new_data: []const u8) !void {
        // Early return for empty data
        if (new_data.len == 0) return;
        
        // First compact the buffer to maximize available space
        self.compact();
        
        // Calculate if we have enough space
        const used_space = self.buffer_end;  // buffer_start is now 0 after compact
        const free_space = self.buffer.len - used_space;
        
        // If the new data won't fit, resize the buffer
        if (free_space < new_data.len) {
            // Create a new larger buffer
            const needed_capacity = used_space + new_data.len;
            var new_capacity = self.buffer.len;
            
            while (new_capacity < needed_capacity) {
                const next_capacity = @as(usize, @intFromFloat(@as(f32, @floatFromInt(new_capacity)) * self.buffer_growth_factor));
                new_capacity = if (next_capacity > new_capacity) next_capacity else new_capacity + 1;
            }
            
            var new_buffer = try self.allocator.alloc(u8, new_capacity);
            
            // Copy existing data to the new buffer
            if (used_space > 0) {
                @memcpy(new_buffer[0..used_space], self.buffer[0..used_space]);
            }
            
            // Free old buffer and update references
            self.allocator.free(self.buffer);
            self.buffer = new_buffer;
            self.grow_count += 1;
        }
        
        // Now copy the new data to the end of the buffer
        @memcpy(self.buffer[self.buffer_end..][0..new_data.len], new_data);
        self.buffer_end += new_data.len;
    }
    
    /// Ensure the buffer has at least the specified capacity
    fn ensureCapacity(self: *ByteStream, needed_capacity: usize) !void {
        if (!self.owns_buffer) {
            return error.CannotResizeExternalBuffer;
        }
        
        // Current capacity after compacting
        const current_capacity = self.buffer.len;
        if (current_capacity >= needed_capacity) {
            // We already have enough space after compacting
            self.compact();
            return;
        }
        
        // Calculate the new capacity - grow by a factor to avoid frequent resizing
        var new_capacity = current_capacity;
        while (new_capacity < needed_capacity) {
            const next_capacity = @as(usize, @intFromFloat(@as(f32, @floatFromInt(new_capacity)) * self.buffer_growth_factor));
            new_capacity = if (next_capacity > new_capacity) next_capacity else new_capacity + 1;
        }
        
        // Allocate a new buffer
        var new_buffer = try self.allocator.alloc(u8, new_capacity);
        errdefer self.allocator.free(new_buffer);
        
        // Copy existing data to the new buffer
        const used_space = self.buffer_end - self.buffer_start;
        @memcpy(new_buffer[0..used_space], self.buffer[self.buffer_start..self.buffer_end]);
        
        // Free the old buffer and update
        self.allocator.free(self.buffer);
        self.buffer = new_buffer;
        self.buffer_end = used_space;
        self.buffer_start = 0;
        self.grow_count += 1;
    }
    
    /// Compact the buffer by moving all data to the beginning
    pub fn compact(self: *ByteStream) void {
        // If already compacted, nothing to do
        if (self.buffer_start == 0) return;
        
        // Move data to the beginning of the buffer
        const used_space = self.buffer_end - self.buffer_start;
        
        // Use std.mem.copyBackwards to handle overlapping memory regions
        if (used_space > 0) {
            std.mem.copyBackwards(u8, self.buffer[0..used_space], self.buffer[self.buffer_start..self.buffer_end]);
        }
        
        self.buffer_end = used_space;
        self.buffer_start = 0;
        self.compact_count += 1;
    }

    /// Fill the buffer with more data from the source
    pub fn fillBuffer(self: *ByteStream) !void {
        // First, compact the buffer to maximize available space
        self.compact();

        // If buffer is full, we need more space
        if (self.buffer_end == self.buffer.len) {
            try self.ensureCapacity(self.buffer.len + 1);
        }

        // Read more data from the appropriate source
        var bytes_read: usize = 0;
        
        switch (self.source_type) {
            .memory => {
                if (self.memory_source) |memory| {
                    // Calculate where we are in the source data
                    const pos = self.total_consumed + (self.buffer_end - self.buffer_start);
                    if (pos < memory.len) {
                        const remaining_buf_space = self.buffer.len - self.buffer_end;
                        const remaining_data = memory.len - pos;
                        const to_copy = @min(remaining_buf_space, remaining_data);
                        
                        @memcpy(self.buffer[self.buffer_end..self.buffer_end + to_copy], memory[pos..pos + to_copy]);
                        bytes_read = to_copy;
                    }
                }
            },
            .file => {
                if (self.file_source) |file| {
                    bytes_read = try file.read(self.buffer[self.buffer_end..]);
                }
            },
            .reader => {
                if (self.reader_source) |reader| {
                    bytes_read = try reader.read(self.buffer[self.buffer_end..]);
                }
            },
            .custom => {
                // Custom source type doesn't have a reader, so we can't fill the buffer
                // For custom sources, the user is expected to use append()
            },
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
        self.total_consumed += 1;

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
    
    /// Set the position (only works for memory sources)
    pub fn setPosition(self: *ByteStream, position: Position) !void {
        if (self.source_type != .memory) {
            return error.CannotRepositionNonMemorySource;
        }
        
        // Reset the stream and read up to the position
        try self.reset();
        
        // Skip forward to the desired position
        var current_offset: usize = 0;
        while (current_offset < position.offset) : (current_offset += 1) {
            _ = try self.consume() orelse return error.InvalidPosition;
        }
        
        // Override the line and column values
        self.line = position.line;
        self.column = position.column;
    }
    
    /// Reset the stream to the beginning
    pub fn reset(self: *ByteStream) !void {
        switch (self.source_type) {
            .memory => {
                // For memory sources, we can just reset the counters
                self.buffer_start = 0;
                self.buffer_end = 0;
                self.position = 0;
                self.line = 1;
                self.column = 1;
                self.exhausted = false;
                self.total_consumed = 0;
            },
            .file => {
                // For files, seek to the beginning
                if (self.file_source) |file| {
                    try file.seekTo(0);
                    self.buffer_start = 0;
                    self.buffer_end = 0;
                    self.position = 0;
                    self.line = 1;
                    self.column = 1;
                    self.exhausted = false;
                    self.total_consumed = 0;
                } else {
                    return error.MissingFileSource;
                }
            },
            else => {
                return error.CannotResetSource;
            },
        }
    }
    
    /// Get statistics about the buffer
    pub fn getStats(self: *const ByteStream) struct {
        buffer_size: usize,
        used_space: usize,
        free_space: usize,
        total_consumed: usize,
        position: usize,
    } {
        const used_space = self.buffer_end - self.buffer_start;
        const free_space = self.buffer.len - used_space;
        
        return .{
            .buffer_size = self.buffer.len,
            .used_space = used_space,
            .free_space = free_space,
            .total_consumed = self.total_consumed,
            .position = self.position,
        };
    }
    
    /// Return a readable slice of available data
    pub fn availableData(self: *const ByteStream) []const u8 {
        return self.buffer[self.buffer_start..self.buffer_end];
    }
};