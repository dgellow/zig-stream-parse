const std = @import("std");
const ByteStream = @import("../byte_stream_optimized.zig").ByteStream;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Buffer Management Demo\n", .{});
    try stdout.print("=====================\n\n", .{});
    
    // Create a new ByteStream with a small buffer
    try stdout.print("Creating ByteStream with initial buffer size of 16 bytes\n", .{});
    var stream = try ByteStream.fromMemory(allocator, "", 16);
    defer stream.deinit();
    
    // Print initial stats
    var stats = stream.getStats();
    try printStats(stdout, stats);
    
    // Append some data
    const data1 = "Hello, ";
    try stdout.print("\nAppending \"{s}\" (7 bytes)\n", .{data1});
    try stream.append(data1);
    
    // Print stats
    stats = stream.getStats();
    try printStats(stdout, stats);
    
    // Consume some data
    try stdout.print("\nConsuming first 3 bytes\n", .{});
    _ = try stream.consume(); // 'H'
    _ = try stream.consume(); // 'e'
    _ = try stream.consume(); // 'l'
    
    // Print stats
    stats = stream.getStats();
    try printStats(stdout, stats);
    
    // Append more data
    const data2 = "world!";
    try stdout.print("\nAppending \"{s}\" (6 bytes)\n", .{data2});
    try stream.append(data2);
    
    // Print stats
    stats = stream.getStats();
    try printStats(stdout, stats);
    
    // Append large data to demonstrate buffer growth
    const data3 = try allocator.alloc(u8, 32);
    defer allocator.free(data3);
    @memset(data3, 'A');
    
    try stdout.print("\nAppending 32 bytes of data (beyond current buffer capacity)\n", .{});
    try stream.append(data3);
    
    // Print stats
    stats = stream.getStats();
    try printStats(stdout, stats);
    
    // Read all the data to demonstrate it was stored correctly
    try stdout.print("\nReading all data:\n", .{});
    try stdout.print("\"", .{});
    
    while (try stream.consume()) |byte| {
        try stdout.print("{c}", .{byte});
    }
    
    try stdout.print("\"\n", .{});
    
    try stdout.print("\nDemo complete\n", .{});
}

fn printStats(writer: std.fs.File.Writer, stats: anytype) !void {
    try writer.print("Buffer Stats:\n", .{});
    try writer.print("  Total buffer size: {} bytes\n", .{stats.buffer_size});
    try writer.print("  Used space: {} bytes\n", .{stats.used_space});
    try writer.print("  Free space: {} bytes\n", .{stats.free_space});
    try writer.print("  Total consumed: {} bytes\n", .{stats.total_consumed});
    try writer.print("  Current position: {}\n", .{stats.position});
    
    // Calculate and print buffer utilization
    const utilization = if (stats.buffer_size > 0) 
        @as(f32, @floatFromInt(stats.used_space)) / @as(f32, @floatFromInt(stats.buffer_size)) * 100.0
    else
        0.0;
    
    try writer.print("  Buffer utilization: {d:.1}%\n", .{utilization});
}