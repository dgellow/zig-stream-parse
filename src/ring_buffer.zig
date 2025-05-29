const std = @import("std");

/// High-performance ring buffer for true streaming parsing
/// Allows parsing gigabyte files with fixed memory usage
pub const RingBuffer = struct {
    buffer: []u8,
    read_pos: usize = 0,
    write_pos: usize = 0,
    filled: usize = 0,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, size: usize) !RingBuffer {
        // Ensure size is power of 2 for fast modulo with bitwise AND
        const actual_size = std.math.ceilPowerOfTwo(usize, size) catch size;
        
        return .{
            .buffer = try allocator.alloc(u8, actual_size),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *RingBuffer) void {
        self.allocator.free(self.buffer);
    }
    
    pub fn capacity(self: *const RingBuffer) usize {
        return self.buffer.len;
    }
    
    pub fn available(self: *const RingBuffer) usize {
        return self.filled;
    }
    
    pub fn freeSpace(self: *const RingBuffer) usize {
        return self.buffer.len - self.filled;
    }
    
    /// Fill buffer from a reader
    pub fn fill(self: *RingBuffer, reader: anytype) !usize {
        const free_space = self.freeSpace();
        if (free_space == 0) return 0;
        
        // Calculate how much we can write in one contiguous chunk
        const end_space = self.buffer.len - self.write_pos;
        const write_size = @min(free_space, end_space);
        
        const bytes_read = try reader.read(self.buffer[self.write_pos..][0..write_size]);
        
        self.write_pos = (self.write_pos + bytes_read) & (self.buffer.len - 1);
        self.filled += bytes_read;
        
        return bytes_read;
    }
    
    /// Get a slice of available data for parsing
    /// Returns up to `max_len` bytes of contiguous data
    pub fn peek(self: *const RingBuffer, max_len: usize) []const u8 {
        if (self.filled == 0) return &[_]u8{};
        
        const end_space = self.buffer.len - self.read_pos;
        const available_contiguous = @min(self.filled, end_space);
        const peek_len = @min(max_len, available_contiguous);
        
        return self.buffer[self.read_pos..][0..peek_len];
    }
    
    /// Consume `len` bytes from the buffer
    pub fn consume(self: *RingBuffer, len: usize) void {
        const consume_len = @min(len, self.filled);
        self.read_pos = (self.read_pos + consume_len) & (self.buffer.len - 1);
        self.filled -= consume_len;
    }
    
    /// Get a byte at offset from current read position
    pub fn peekAt(self: *const RingBuffer, offset: usize) ?u8 {
        if (offset >= self.filled) return null;
        
        const pos = (self.read_pos + offset) & (self.buffer.len - 1);
        return self.buffer[pos];
    }
    
    /// Check if we need more data for pattern matching
    pub fn needsRefill(self: *const RingBuffer, min_lookahead: usize) bool {
        return self.filled < min_lookahead and self.freeSpace() > 0;
    }
    
    /// Compact buffer by moving unconsumed data to the beginning
    /// This is rarely needed with ring buffers but can help with very long tokens
    pub fn compact(self: *RingBuffer) void {
        if (self.read_pos == 0) return; // Already at start
        
        // Move remaining data to start of buffer
        if (self.filled > 0) {
            // Use a temporary buffer to handle overlapping moves
            var temp_buf: [1024]u8 = undefined;
            var remaining = self.filled;
            var src_pos = self.read_pos;
            var dst_pos: usize = 0;
            
            while (remaining > 0) {
                const chunk_size = @min(remaining, temp_buf.len);
                const end_space = self.buffer.len - src_pos;
                const contiguous = @min(chunk_size, end_space);
                
                // Copy to temp buffer
                @memcpy(temp_buf[0..contiguous], self.buffer[src_pos..src_pos + contiguous]);
                
                // Copy from temp buffer to destination
                @memcpy(self.buffer[dst_pos..dst_pos + contiguous], temp_buf[0..contiguous]);
                
                src_pos = (src_pos + contiguous) & (self.buffer.len - 1);
                dst_pos += contiguous;
                remaining -= contiguous;
            }
        }
        
        self.read_pos = 0;
        self.write_pos = self.filled;
    }
};

/// Streaming tokenizer that uses ring buffer for memory efficiency
pub const StreamingTokenizer = struct {
    ring_buffer: RingBuffer,
    line: usize = 1,
    column: usize = 1,
    total_consumed: usize = 0,
    
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !StreamingTokenizer {
        return .{
            .ring_buffer = try RingBuffer.init(allocator, buffer_size),
        };
    }
    
    pub fn deinit(self: *StreamingTokenizer) void {
        self.ring_buffer.deinit();
    }
    
    /// Fill buffer from reader and return if more data is available
    pub fn refill(self: *StreamingTokenizer, reader: anytype) !bool {
        const bytes_read = try self.ring_buffer.fill(reader);
        return bytes_read > 0;
    }
    
    /// Get next token, automatically refilling buffer if needed
    pub fn next(
        self: *StreamingTokenizer, 
        reader: anytype,
        comptime TokenType: type, 
        comptime patterns: anytype
    ) !?struct {
        type: TokenType,
        text: []const u8,
        line: usize,
        column: usize,
    } {
        while (true) {
            // Skip whitespace
            self.skipWhitespace();
            
            // Check if we need more data
            if (self.ring_buffer.needsRefill(64)) { // 64 byte lookahead
                const got_data = try self.refill(reader);
                if (!got_data and self.ring_buffer.available() == 0) {
                    return null; // EOF
                }
            }
            
            const data = self.ring_buffer.peek(1024); // Get up to 1KB for matching
            if (data.len == 0) return null;
            
            const start_line = self.line;
            const start_column = self.column;
            
            // Try to match patterns (similar to TokenStream.next)
            const type_info = @typeInfo(@TypeOf(patterns));
            const fields = switch (type_info) {
                .@"struct" => |s| s.fields,
                else => @compileError("Expected struct patterns"),
            };
            
            inline for (fields) |field| {
                const token_type = @field(TokenType, field.name);
                const pattern_value = @field(patterns, field.name);
                
                // Use pattern matching on ring buffer data
                const match_result = @import("pattern.zig").matchPattern(pattern_value, data, 0);
                if (match_result.matched and match_result.len > 0) {
                    const text = data[0..match_result.len];
                    
                    // Update position tracking
                    for (text) |c| {
                        if (c == '\n') {
                            self.line += 1;
                            self.column = 1;
                        } else {
                            self.column += 1;
                        }
                    }
                    
                    // Consume from ring buffer
                    self.ring_buffer.consume(match_result.len);
                    self.total_consumed += match_result.len;
                    
                    return .{
                        .type = token_type,
                        .text = text, // This is valid until next consume()
                        .line = start_line,
                        .column = start_column,
                    };
                }
            }
            
            // No pattern matched - might need more data or error
            if (self.ring_buffer.freeSpace() > 0) {
                // Try to get more data
                const got_data = try self.refill(reader);
                if (!got_data) {
                    // EOF with unmatched data - consume one byte and continue
                    self.ring_buffer.consume(1);
                    self.total_consumed += 1;
                    self.column += 1;
                }
            } else {
                // Buffer full with no match - consume one byte to make progress
                self.ring_buffer.consume(1);
                self.total_consumed += 1;
                self.column += 1;
            }
        }
    }
    
    fn skipWhitespace(self: *StreamingTokenizer) void {
        while (true) {
            const byte = self.ring_buffer.peekAt(0) orelse break;
            if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') break;
            
            if (byte == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            
            self.ring_buffer.consume(1);
            self.total_consumed += 1;
        }
    }
    
    pub fn getStats(self: *const StreamingTokenizer) struct {
        buffer_used: usize,
        buffer_capacity: usize,
        total_processed: usize,
        line: usize,
        column: usize,
    } {
        return .{
            .buffer_used = self.ring_buffer.available(),
            .buffer_capacity = self.ring_buffer.capacity(),
            .total_processed = self.total_consumed,
            .line = self.line,
            .column = self.column,
        };
    }
};

test "ring buffer basic operations" {
    var ring = try RingBuffer.init(std.testing.allocator, 8);
    defer ring.deinit();
    
    // Test capacity (should be power of 2)
    try std.testing.expectEqual(@as(usize, 8), ring.capacity());
    try std.testing.expectEqual(@as(usize, 0), ring.available());
    try std.testing.expectEqual(@as(usize, 8), ring.freeSpace());
    
    // Simulate filling from a string
    const data = "hello world";
    var stream = std.io.fixedBufferStream(data);
    
    const bytes_read = try ring.fill(stream.reader());
    try std.testing.expectEqual(@as(usize, 8), bytes_read); // Buffer size limited
    
    // Test peek
    const peeked = ring.peek(5);
    try std.testing.expectEqualStrings("hello", peeked);
    
    // Test consume
    ring.consume(6); // "hello "
    const peeked2 = ring.peek(2);
    try std.testing.expectEqualStrings("wo", peeked2);
}