const std = @import("std");

/// TokenPool provides memory pooling for token lexemes
/// to minimize individual allocations during tokenization.
/// This improves performance by reducing memory management overhead.
pub const TokenPool = struct {
    allocator: std.mem.Allocator,
    pool: []u8,
    position: usize,

    /// Initialize a new token pool with the given size
    pub fn init(allocator: std.mem.Allocator, size: usize) !TokenPool {
        return .{
            .allocator = allocator,
            .pool = try allocator.alloc(u8, size),
            .position = 0,
        };
    }

    /// Free resources used by the token pool
    pub fn deinit(self: *TokenPool) void {
        self.allocator.free(self.pool);
    }

    /// Allocate memory from the pool
    /// Returns error.OutOfMemory if the pool is exhausted
    pub fn allocate(self: *TokenPool, size: usize) ![]u8 {
        if (self.position + size > self.pool.len) {
            return error.OutOfMemory;
        }

        const result = self.pool[self.position..self.position+size];
        self.position += size;
        return result;
    }

    /// Reset the pool to reuse memory
    /// Note: This doesn't clear memory, just resets the position pointer
    pub fn reset(self: *TokenPool) void {
        self.position = 0;
    }
    
    /// Allocate a string from the pool, copying the content
    pub fn dupe(self: *TokenPool, value: []const u8) ![]u8 {
        const memory = try self.allocate(value.len);
        @memcpy(memory, value);
        return memory;
    }
    
    /// Get available space in the pool
    pub fn available(self: TokenPool) usize {
        return self.pool.len - self.position;
    }
    
    /// Get used space in the pool
    pub fn used(self: TokenPool) usize {
        return self.position;
    }
    
    /// Check if the pool is empty (no allocations made)
    pub fn isEmpty(self: TokenPool) bool {
        return self.position == 0;
    }
    
    /// Check if the pool is full (no space left)
    pub fn isFull(self: TokenPool) bool {
        return self.position == self.pool.len;
    }
};