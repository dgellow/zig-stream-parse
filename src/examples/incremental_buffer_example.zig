const std = @import("std");
const ByteStream = @import("byte_stream_optimized").ByteStream;

pub fn main() !void {
    // Setup standard output
    const stdout = std.io.getStdOut().writer();
    try stdout.print("ByteStream Optimized Buffer Management Example\n", .{});
    try stdout.print("---------------------------------------------\n\n", .{});

    // Create general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
                i + 1,
                stats_before.buffer_size, 
                stats_before.used_space, 
                stats_before.free_space,
                stats_before.total_consumed,
                0, // Don't have compact_count in the stats
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
                0, // Don't have compact_count in the stats
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
    
    try stdout.print("\nExample completed successfully.\n", .{});
}

