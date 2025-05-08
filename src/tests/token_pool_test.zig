const std = @import("std");
const testing = std.testing;
const TokenPool = @import("token_pool").TokenPool;

test "TokenPool - basic functionality" {
    const allocator = testing.allocator;
    
    // Create a pool with 100 bytes
    var pool = try TokenPool.init(allocator, 100);
    defer pool.deinit();
    
    // Test initial state
    try testing.expectEqual(@as(usize, 0), pool.position);
    try testing.expectEqual(@as(usize, 100), pool.pool.len);
    try testing.expect(pool.isEmpty());
    try testing.expect(!pool.isFull());
    try testing.expectEqual(@as(usize, 100), pool.available());
    try testing.expectEqual(@as(usize, 0), pool.used());
    
    // Test allocation
    const memory1 = try pool.allocate(10);
    try testing.expectEqual(@as(usize, 10), memory1.len);
    try testing.expectEqual(@as(usize, 10), pool.position);
    try testing.expect(!pool.isEmpty());
    try testing.expect(!pool.isFull());
    try testing.expectEqual(@as(usize, 90), pool.available());
    try testing.expectEqual(@as(usize, 10), pool.used());
    
    // Test multiple allocations
    const memory2 = try pool.allocate(20);
    try testing.expectEqual(@as(usize, 20), memory2.len);
    try testing.expectEqual(@as(usize, 30), pool.position);
    
    const memory3 = try pool.allocate(30);
    try testing.expectEqual(@as(usize, 30), memory3.len);
    try testing.expectEqual(@as(usize, 60), pool.position);
    
    // Test reset
    pool.reset();
    try testing.expectEqual(@as(usize, 0), pool.position);
    try testing.expect(pool.isEmpty());
    
    // After reset, we should be able to allocate the full capacity again
    const memory4 = try pool.allocate(50);
    try testing.expectEqual(@as(usize, 50), memory4.len);
    try testing.expectEqual(@as(usize, 50), pool.position);
}

test "TokenPool - out of memory" {
    const allocator = testing.allocator;
    
    // Create a small pool
    var pool = try TokenPool.init(allocator, 20);
    defer pool.deinit();
    
    // Allocate almost all memory
    _ = try pool.allocate(15);
    try testing.expectEqual(@as(usize, 15), pool.position);
    
    // Try to allocate more than available
    const result = pool.allocate(10);
    try testing.expectError(error.OutOfMemory, result);
    
    // Position should not have changed
    try testing.expectEqual(@as(usize, 15), pool.position);
    
    // We can still allocate the remaining space
    _ = try pool.allocate(5);
    try testing.expectEqual(@as(usize, 20), pool.position);
    try testing.expect(pool.isFull());
}

test "TokenPool - string duplication" {
    const allocator = testing.allocator;
    
    var pool = try TokenPool.init(allocator, 100);
    defer pool.deinit();
    
    // Test string duplication
    const original = "Hello, World!";
    const copy = try pool.dupe(original);
    
    try testing.expectEqualStrings(original, copy);
    try testing.expectEqual(@as(usize, original.len), pool.position);
    
    // Verify that the copy is in the pool
    const pool_slice = pool.pool[0..pool.position];
    try testing.expectEqualStrings(original, pool_slice);
    
    // Verify that changing the copy doesn't affect the original
    // (though they should be separate memory regions anyway)
    var mutable_copy = copy;
    if (mutable_copy.len > 0) {
        mutable_copy[0] = 'h';
    }
    try testing.expectStringStartsWith(mutable_copy, "hello");
    try testing.expectStringStartsWith(original, "Hello");
}

test "TokenPool - multiple dupe operations" {
    const allocator = testing.allocator;
    
    var pool = try TokenPool.init(allocator, 100);
    defer pool.deinit();
    
    const strings = [_][]const u8{
        "First string",
        "Second, longer string",
        "Third string that is even longer",
        "Short",
    };
    
    var copies: [strings.len][]u8 = undefined;
    var total_len: usize = 0;
    
    // Copy all strings to the pool
    for (strings, 0..) |string, i| {
        copies[i] = try pool.dupe(string);
        total_len += string.len;
    }
    
    // Verify all copies
    for (strings, 0..) |string, i| {
        try testing.expectEqualStrings(string, copies[i]);
    }
    
    // Verify total position matches total string length
    try testing.expectEqual(total_len, pool.position);
    
    // Test reset and reuse
    pool.reset();
    try testing.expectEqual(@as(usize, 0), pool.position);
    
    // We should be able to dupe all strings again
    for (strings, 0..) |string, i| {
        copies[i] = try pool.dupe(string);
    }
    
    // Verify all copies again
    for (strings, 0..) |string, i| {
        try testing.expectEqualStrings(string, copies[i]);
    }
    
    // Verify total position matches total string length again
    try testing.expectEqual(total_len, pool.position);
}