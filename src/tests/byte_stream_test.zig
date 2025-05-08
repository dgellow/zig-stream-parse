const std = @import("std");
const ByteStream = @import("byte_stream_enhanced").ByteStream;
const testing = std.testing;

// Test ByteStream with memory source
test "ByteStream.memory" {
    const allocator = testing.allocator;
    const input = "Hello, World!\nThis is a test.";
    
    var stream = try ByteStream.fromMemory(allocator, input, 8); // Small buffer to test refilling
    defer stream.deinit();
    
    // Test peek
    const firstChar = try stream.peek();
    try testing.expectEqual(@as(?u8, 'H'), firstChar);
    
    // Test peekOffset
    const offsetChar = try stream.peekOffset(7);
    try testing.expectEqual(@as(?u8, 'W'), offsetChar);
    
    // Test consume
    const consumed = try stream.consume();
    try testing.expectEqual(@as(?u8, 'H'), consumed);
    try testing.expectEqual(@as(usize, 1), stream.position);
    
    // Test consumeIf (success)
    const didConsume = try stream.consumeIf('e');
    try testing.expectEqual(true, didConsume);
    try testing.expectEqual(@as(usize, 2), stream.position);
    
    // Test consumeIf (failure)
    const didNotConsume = try stream.consumeIf('X');
    try testing.expectEqual(false, didNotConsume);
    try testing.expectEqual(@as(usize, 2), stream.position);
    
    // Test consumeCount
    const countConsumed = try stream.consumeCount(4);
    try testing.expectEqual(@as(usize, 4), countConsumed);
    try testing.expectEqual(@as(usize, 6), stream.position);
    
    // Consume to newline to test line/column tracking
    _ = try stream.consumeCount(8); // "lo, World!\n"
    try testing.expectEqual(@as(usize, 14), stream.position);
    try testing.expectEqual(@as(usize, 2), stream.line);
    try testing.expectEqual(@as(usize, 1), stream.column);
    
    // Test consuming to end
    while ((try stream.consume()) != null) {}
    try testing.expect(stream.exhausted);
    
    // Test reset (only works on memory sources)
    try stream.reset();
    try testing.expectEqual(@as(usize, 0), stream.position);
    try testing.expectEqual(@as(usize, 1), stream.line);
    try testing.expectEqual(@as(usize, 1), stream.column);
    try testing.expectEqual(false, stream.exhausted);
    
    // Peek after reset
    const peekedAfterReset = try stream.peek();
    try testing.expectEqual(@as(?u8, 'H'), peekedAfterReset);
}

// Test ByteStream with file source
test "ByteStream.file" {
    const allocator = testing.allocator;
    const test_file_path = "test_file.txt";
    
    // Create a test file
    {
        var file = try std.fs.cwd().createFile(test_file_path, .{});
        defer file.close();
        
        try file.writeAll("File content\nSecond line");
    }
    defer std.fs.cwd().deleteFile(test_file_path) catch {};
    
    // Open the test file
    var file = try std.fs.cwd().openFile(test_file_path, .{});
    defer file.close();
    
    // Create a ByteStream from the file
    var stream = try ByteStream.fromFile(allocator, file, 16);
    defer stream.deinit();
    
    // Test reading from file
    const firstChar = try stream.peek();
    try testing.expectEqual(@as(?u8, 'F'), firstChar);
    
    // Read the first line
    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();
    
    while (true) {
        const byte = try stream.consume();
        if (byte == null or byte.? == '\n') break;
        try line.append(byte.?);
    }
    
    try testing.expectEqualStrings("File content", line.items);
    try testing.expectEqual(@as(usize, 2), stream.line);
    
    // Test that we can read the second line
    line.clearRetainingCapacity();
    while (true) {
        const byte = try stream.consume();
        if (byte == null) break;
        try line.append(byte.?);
    }
    
    try testing.expectEqualStrings("Second line", line.items);
    try testing.expect(stream.exhausted);
}

// Test ByteStream with a reader source
test "ByteStream.reader" {
    const allocator = testing.allocator;
    
    // Create a temporary file to read from
    const test_file_path = "test_reader_file.txt";
    {
        var file = try std.fs.cwd().createFile(test_file_path, .{});
        defer file.close();
        
        try file.writeAll("Reader test\nAnother line");
    }
    defer std.fs.cwd().deleteFile(test_file_path) catch {};
    
    // Open file for reading
    var file = try std.fs.cwd().openFile(test_file_path, .{});
    defer file.close();
    
    // Create a ByteStream from the file (simulating a reader)
    var stream = try ByteStream.fromReader(allocator, file, 8); // Small buffer to test refilling
    defer stream.deinit();
    
    // Test reading
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    while (true) {
        const byte = try stream.consume();
        if (byte == null) break;
        try content.append(byte.?);
    }
    
    try testing.expectEqualStrings("Reader test\nAnother line", content.items);
    try testing.expect(stream.exhausted);
    
    // Verify line/column tracking
    try testing.expectEqual(@as(usize, 2), stream.line);
}

// Test error handling
test "ByteStream.errors" {
    const allocator = testing.allocator;
    const input = "Test";
    
    var stream = try ByteStream.fromMemory(allocator, input, 8);
    defer stream.deinit();
    
    // Consume all content
    while ((try stream.consume()) != null) {}
    
    // Verify EOF behavior
    const atEof = try stream.peek();
    try testing.expectEqual(@as(?u8, null), atEof);
    try testing.expect(stream.exhausted);
    
    // Try reset on a memory source (should work)
    try stream.reset();
    try testing.expectEqual(false, stream.exhausted);
    
    // Create a file stream
    const test_file_path = "test_file2.txt";
    {
        var file = try std.fs.cwd().createFile(test_file_path, .{});
        defer file.close();
        try file.writeAll("test");
    }
    defer std.fs.cwd().deleteFile(test_file_path) catch {};
    
    var file = try std.fs.cwd().openFile(test_file_path, .{});
    defer file.close();
    
    var fileStream = try ByteStream.fromFile(allocator, file, 8);
    defer fileStream.deinit();
    
    // Try reset on a file source (should fail)
    const resetResult = fileStream.reset();
    try testing.expectError(error.CannotResetNonMemorySource, resetResult);
}

test "ByteStream.large_buffer" {
    const allocator = testing.allocator;
    
    // Test with a large input (larger than the buffer)
    var largeInput = std.ArrayList(u8).init(allocator);
    defer largeInput.deinit();
    
    const repeat_text = "This is a long string to test with. ";
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try largeInput.appendSlice(repeat_text);
        if (i % 10 == 0) {
            try largeInput.append('\n'); // Add some newlines for line tracking
        }
    }
    
    var stream = try ByteStream.fromMemory(allocator, largeInput.items, 128);
    defer stream.deinit();
    
    // Count bytes and lines
    var byteCount: usize = 0;
    var lineCount: usize = 1; // Start at 1 to match ByteStream.line
    
    while (true) {
        const byte = try stream.consume();
        if (byte == null) break;
        byteCount += 1;
        if (byte.? == '\n') lineCount += 1;
    }
    
    try testing.expectEqual(largeInput.items.len, byteCount);
    try testing.expectEqual(lineCount, stream.line);
}

// Test with various buffer sizes to ensure correct behavior
test "ByteStream.buffer_sizes" {
    const allocator = testing.allocator;
    const input = "Testing various buffer sizes";
    
    // Test with various buffer sizes
    const buffer_sizes = [_]usize{ 1, 2, 4, 7, 8, 10, 16, 32 };
    
    for (buffer_sizes) |buffer_size| {
        var stream = try ByteStream.fromMemory(allocator, input, buffer_size);
        defer stream.deinit();
        
        var readContent = std.ArrayList(u8).init(allocator);
        defer readContent.deinit();
        
        while (true) {
            const byte = try stream.consume();
            if (byte == null) break;
            try readContent.append(byte.?);
        }
        
        try testing.expectEqualStrings(input, readContent.items);
    }
}