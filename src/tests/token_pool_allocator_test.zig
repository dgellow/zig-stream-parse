const std = @import("std");
const testing = std.testing;
const TokenPool = @import("token_pool").TokenPool;

fn poolAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = alignment;
    _ = ret_addr;
    
    const pool: *TokenPool = @ptrCast(@alignCast(ctx));
    
    if (pool.allocate(len)) |slice| {
        return slice.ptr;
    } else |_| {
        return null;
    }
}

fn poolResize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = new_len;
    _ = ret_addr;
    
    // We don't support resizing allocations in the pool
    return false;
}

fn poolFree(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = ret_addr;
    
    // We don't free individual allocations from the pool
    // They'll all be freed when the pool is reset or deinit is called
}

fn poolRemap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = new_len;
    _ = ret_addr;
    
    // We don't support remapping in the pool
    return null;
}

test "TokenPool as allocator" {
    const allocator = testing.allocator;
    
    // Create a pool with 1024 bytes
    var pool = try TokenPool.init(allocator, 1024);
    defer pool.deinit();
    
    // Create an allocator that uses the pool
    const pool_allocator = std.mem.Allocator{
        .ptr = &pool,
        .vtable = &.{
            .alloc = poolAlloc,
            .resize = poolResize,
            .free = poolFree,
            .remap = poolRemap,
        },
    };
    
    // Test basic allocation
    {
        const memory = try pool_allocator.alloc(u8, 10);
        defer pool_allocator.free(memory);
        
        try testing.expectEqual(@as(usize, 10), memory.len);
        try testing.expectEqual(@as(usize, 10), pool.used());
        
        // Write to memory to ensure it's usable
        for (memory, 0..) |*byte, i| {
            byte.* = @intCast(i);
        }
        
        // Verify values
        for (memory, 0..) |byte, i| {
            try testing.expectEqual(@as(u8, @intCast(i)), byte);
        }
    }
    
    // Test string duplication
    {
        const original = "Hello, World!";
        const copy = try pool_allocator.dupe(u8, original);
        
        try testing.expectEqualStrings(original, copy);
        try testing.expectEqual(@as(usize, 10 + original.len), pool.used());
        
        // We don't free the string, it stays in the pool
    }
    
    // Create a string list using the pool allocator
    {
        var list = std.ArrayList(u8).init(pool_allocator);
        defer list.deinit();
        
        try list.appendSlice("Testing");
        try list.appendSlice(" the ");
        try list.appendSlice("allocator");
        
        try testing.expectEqualStrings("Testing the allocator", list.items);
    }
    
    // Reset the pool and verify it's empty
    pool.reset();
    try testing.expectEqual(@as(usize, 0), pool.used());
    try testing.expectEqual(@as(usize, 1024), pool.available());
}