const std = @import("std");

// Position structure for tracking location in input
const Position = struct {
    offset: usize,
    line: usize,
    column: usize,
};

/// Statistics about the ByteStream
const ByteStreamStats = struct {
    total_bytes_read: usize = 0,
    append_count: usize = 0,
    grow_count: usize = 0,
    compact_count: usize = 0,
    current_buffer_size: usize = 0,
    current_buffer_used: usize = 0,
    peak_buffer_size: usize = 0,
};

/// An optimized ByteStream implementation with efficient buffer management for incremental parsing
const ByteStream = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    buffer_start: usize,
    buffer_end: usize,
    position: usize,
    line: usize,
    column: usize,
    stats: ByteStreamStats,
    exhausted: bool,
    
    // For memory sources
    memory_source: ?[]const u8,
    
    // Growth factor for buffer resizing
    buffer_growth_factor: f32 = 1.5,
    
    /// Create a ByteStream from a memory slice
    pub fn fromMemory(allocator: std.mem.Allocator, memory: []const u8, buffer_size: usize) !ByteStream {
        const buffer = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buffer);
        
        var stats = ByteStreamStats{
            .current_buffer_size = buffer.len,
            .peak_buffer_size = buffer.len,
        };
        
        // Pre-fill buffer if we have a non-empty memory source
        if (memory.len > 0) {
            const to_copy = @min(buffer.len, memory.len);
            @memcpy(buffer[0..to_copy], memory[0..to_copy]);
            stats.total_bytes_read += to_copy;
        }
        
        return ByteStream{
            .allocator = allocator,
            .buffer = buffer,
            .buffer_start = 0,
            .buffer_end = if (memory.len > 0) @min(buffer.len, memory.len) else 0,
            .position = 0,
            .line = 1,
            .column = 1,
            .exhausted = false,
            .memory_source = memory,
            .stats = stats,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *ByteStream) void {
        self.allocator.free(self.buffer);
    }
    
    /// Append new data to the stream (for incremental parsing)
    pub fn append(self: *ByteStream, new_data: []const u8) !void {
        // Update stats
        self.stats.append_count += 1;
        
        // If the buffer is empty, we can just copy the new data in
        if (self.buffer_start == self.buffer_end) {
            const to_copy = @min(self.buffer.len, new_data.len);
            @memcpy(self.buffer[0..to_copy], new_data[0..to_copy]);
            self.buffer_start = 0;
            self.buffer_end = to_copy;
            self.stats.total_bytes_read += to_copy;
            
            // If we have more data than fits in our buffer, we need to
            // resize the buffer to hold all the data
            if (to_copy < new_data.len) {
                try self.ensureCapacity(new_data.len - to_copy);
                @memcpy(self.buffer[self.buffer_end..], new_data[to_copy..]);
                self.buffer_end += (new_data.len - to_copy);
                self.stats.total_bytes_read += (new_data.len - to_copy);
            }
            return;
        }
        
        // Calculate how much space we need
        const used_space = self.buffer_end - self.buffer_start;
        const free_space = self.buffer.len - used_space;
        
        // If we have enough free space (after compacting), just copy the data in
        if (free_space >= new_data.len) {
            // Compact the buffer first to maximize available contiguous space
            self.compact();
            @memcpy(self.buffer[self.buffer_end..][0..new_data.len], new_data);
            self.buffer_end += new_data.len;
            self.stats.total_bytes_read += new_data.len;
            return;
        }
        
        // We need to resize the buffer
        try self.ensureCapacity(used_space + new_data.len);
        
        // Copy the new data after the existing data
        @memcpy(self.buffer[self.buffer_end..][0..new_data.len], new_data);
        self.buffer_end += new_data.len;
        self.stats.total_bytes_read += new_data.len;
    }
    
    /// Ensure the buffer has at least the specified capacity
    fn ensureCapacity(self: *ByteStream, needed_capacity: usize) !void {
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
        
        // Update stats
        self.stats.grow_count += 1;
        self.stats.current_buffer_size = new_capacity;
        self.stats.current_buffer_used = used_space;
        if (new_capacity > self.stats.peak_buffer_size) {
            self.stats.peak_buffer_size = new_capacity;
        }
    }
    
    /// Compact the buffer by moving all data to the beginning
    pub fn compact(self: *ByteStream) void {
        // If already compacted, nothing to do
        if (self.buffer_start == 0) return;
        
        // Move data to the beginning of the buffer
        const used_space = self.buffer_end - self.buffer_start;
        std.mem.copyForwards(u8, self.buffer[0..used_space], self.buffer[self.buffer_start..self.buffer_end]);
        self.buffer_end = used_space;
        self.buffer_start = 0;
        
        // Update stats
        self.stats.compact_count += 1;
        self.stats.current_buffer_used = used_space;
    }
    
    /// Fill the buffer with more data from the source
    pub fn fillBuffer(self: *ByteStream) !void {
        // First, compact the buffer to maximize available space
        self.compact();
        
        // If buffer is full, we need more space
        if (self.buffer_end == self.buffer.len) {
            try self.ensureCapacity(self.buffer.len + 1);
        }
        
        // For memory source, copy more data
        if (self.memory_source) |memory| {
            // Calculate where we are in the source data
            const pos = self.position + (self.buffer_end - self.buffer_start);
            if (pos < memory.len) {
                const remaining_buf_space = self.buffer.len - self.buffer_end;
                const remaining_data = memory.len - pos;
                const to_copy = @min(remaining_buf_space, remaining_data);
                
                @memcpy(self.buffer[self.buffer_end..self.buffer_end + to_copy], memory[pos..pos + to_copy]);
                self.buffer_end += to_copy;
                self.stats.total_bytes_read += to_copy;
            }
        }
        
        // If we read 0 bytes and the buffer is empty, we're at EOF
        if (self.buffer_start == self.buffer_end) {
            self.exhausted = true;
        }
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
    
    /// Get the current position information
    pub fn getPosition(self: *const ByteStream) Position {
        return .{
            .offset = self.position,
            .line = self.line,
            .column = self.column,
        };
    }
    
    /// Get statistics about the buffer
    pub fn getStats(self: *const ByteStream) struct {
        buffer_size: usize,
        used_space: usize,
        free_space: usize,
        total_consumed: usize,
        position: usize,
        stats: ByteStreamStats,
    } {
        const used_space = self.buffer_end - self.buffer_start;
        const free_space = self.buffer.len - used_space;
        
        return .{
            .buffer_size = self.buffer.len,
            .used_space = used_space,
            .free_space = free_space,
            .total_consumed = self.stats.total_bytes_read,
            .position = self.position,
            .stats = self.stats,
        };
    }
};

pub fn main() !void {
    // Setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create stdout for output
    const stdout = std.io.getStdOut().writer();
    try stdout.print("ByteStream Optimized Buffer Management Example\n", .{});
    try stdout.print("---------------------------------------------\n\n", .{});
    
    // Create a ByteStream with a small buffer to demonstrate buffer management
    const initial_buffer_size: usize = 64;
    var stream = try ByteStream.fromMemory(allocator, "", initial_buffer_size);
    defer stream.deinit();
    
    try stdout.print("Created ByteStream with initial buffer size: {d} bytes\n\n", .{initial_buffer_size});
    
    // Define test data chunks
    const chunks = [_][]const u8{
        "First chunk of data that will fit in the initial buffer",
        "Second chunk that will cause the buffer to grow",
        "Third chunk with more data to process",
        "Fourth chunk after consuming some data",
        "Fifth chunk with enough data to demonstrate buffer management capabilities and efficiency",
    };
    
    // Process each chunk with statistics tracking
    try stdout.print("Buffer Statistics:\n", .{});
    try stdout.print("| {s:^5} | {d:^15} | {d:^15} | {d:^15} | {d:^15} | {d:^15} |\n", 
        .{"Chunk", "Buffer Size", "Used Space", "Free Space", "Total Read", "Compactions"});
    try stdout.print("|{s}|\n", .{"-" ** 94});
    
    // Process each chunk
    for (chunks, 0..) |chunk, i| {
        // First show some data without appending
        const stats_before = stream.getStats();
        
        try stdout.print("| {s:^5} | {d:^15} | {d:^15} | {d:^15} | {d:^15} | {d:^15} |\n", 
            .{
                if (i == 0) "1" else if (i == 1) "2" else if (i == 2) "3" else if (i == 3) "4" else "5",
                stats_before.buffer_size, 
                stats_before.used_space, 
                stats_before.free_space,
                stats_before.total_consumed,
                stats_before.stats.compact_count,
            });
        
        // Append the chunk
        try stream.append(chunk);
        
        // If not the first chunk, consume some data
        if (i > 0) {
            const to_consume = chunk.len / 2; // Consume half of the chunk
            var consumed: usize = 0;
            while (consumed < to_consume) {
                _ = try stream.consume();
                consumed += 1;
            }
        }
        
        // If this is the third chunk, force a compaction to demonstrate
        if (i == 2) {
            stream.compact();
            try stdout.print("* Forced compaction after chunk 3 *\n", .{});
        }
        
        // Get stats after processing
        const stats_after = stream.getStats();
        try stdout.print("| {s:^5} | {d:^15} | {d:^15} | {d:^15} | {d:^15} | {d:^15} |\n", 
            .{
                "", // Empty chunk number 
                stats_after.buffer_size, 
                stats_after.used_space, 
                stats_after.free_space,
                stats_after.total_consumed,
                stats_after.stats.compact_count,
            });
            
        try stdout.print("|{s}|\n", .{"-" ** 94});
    }
    
    // Final buffer state
    const final_stats = stream.getStats();
    try stdout.print("\nFinal Buffer State:\n", .{});
    try stdout.print("- Buffer size: {d} bytes\n", .{final_stats.buffer_size});
    try stdout.print("- Used space: {d} bytes\n", .{final_stats.used_space});
    try stdout.print("- Free space: {d} bytes\n", .{final_stats.free_space});
    try stdout.print("- Total bytes read: {d} bytes\n", .{final_stats.total_consumed});
    try stdout.print("- Current position: {d}\n", .{final_stats.position});
    try stdout.print("- Buffer compactions: {d}\n", .{final_stats.stats.compact_count});
    try stdout.print("- Buffer growths: {d}\n", .{final_stats.stats.grow_count});
    try stdout.print("- Peak buffer size: {d} bytes\n", .{final_stats.stats.peak_buffer_size});
    
    // Demonstrate efficient peeking and consuming
    try stdout.print("\nPeeking and Consuming Demonstration:\n", .{});
    
    // Peek at the first 10 bytes
    var peek_buf = std.ArrayList(u8).init(allocator);
    defer peek_buf.deinit();
    
    for (0..10) |j| {
        if (try stream.peekOffset(j)) |byte| {
            try peek_buf.append(byte);
        } else {
            break;
        }
    }
    
    try stdout.print("- First 10 bytes by peeking: ", .{});
    for (peek_buf.items) |byte| {
        try stdout.print("{c}", .{byte});
    }
    try stdout.print("\n", .{});
    
    // Consume 20 bytes
    var consume_buf = std.ArrayList(u8).init(allocator);
    defer consume_buf.deinit();
    
    for (0..20) |_| {
        if (try stream.consume()) |byte| {
            try consume_buf.append(byte);
        } else {
            break;
        }
    }
    
    try stdout.print("- Next 20 bytes by consuming: ", .{});
    for (consume_buf.items) |byte| {
        try stdout.print("{c}", .{byte});
    }
    try stdout.print("\n", .{});
    
    // Check buffer stats after consuming
    const stats_after_consume = stream.getStats();
    try stdout.print("\nBuffer State After Consuming:\n", .{});
    try stdout.print("- Buffer size: {d} bytes\n", .{stats_after_consume.buffer_size});
    try stdout.print("- Used space: {d} bytes\n", .{stats_after_consume.used_space});
    try stdout.print("- Free space: {d} bytes\n", .{stats_after_consume.free_space});
    try stdout.print("- Total consumed position: {d}\n", .{stats_after_consume.position});
    
    try stdout.print("\nExample completed successfully.\n", .{});
}