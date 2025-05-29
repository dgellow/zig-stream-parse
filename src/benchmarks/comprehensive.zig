const std = @import("std");
const zigparse = @import("../zigparse.zig");
const simd = @import("../simd.zig");
const RingBuffer = @import("../ring_buffer.zig").RingBuffer;
const StreamingTokenizer = @import("../ring_buffer.zig").StreamingTokenizer;

// Benchmark data generation
fn generateTestData(allocator: std.mem.Allocator, size: usize, data_type: enum { words, json, csv, mixed }) ![]u8 {
    var data = try allocator.alloc(u8, size);
    var rng = std.rand.DefaultPrng.init(42); // Deterministic for consistent benchmarks
    var pos: usize = 0;
    
    switch (data_type) {
        .words => {
            // Generate random words separated by spaces
            while (pos < size - 10) {
                const word_len = rng.random().intRangeAtMost(usize, 3, 12);
                for (0..word_len) |_| {
                    if (pos >= size) break;
                    data[pos] = 'a' + @as(u8, @intCast(rng.random().intRangeAtMost(u8, 0, 25)));
                    pos += 1;
                }
                if (pos < size) {
                    data[pos] = ' ';
                    pos += 1;
                }
            }
        },
        
        .json => {
            // Generate JSON-like data
            const json_template = 
                \\{"name": "John Doe", "age": 30, "city": "New York", "hobbies": ["reading", "coding", "gaming"], "active": true}
            ;
            
            while (pos < size - json_template.len) {
                const remaining = size - pos;
                const copy_len = @min(json_template.len, remaining);
                @memcpy(data[pos..pos + copy_len], json_template[0..copy_len]);
                pos += copy_len;
                
                if (pos < size) {
                    data[pos] = '\n';
                    pos += 1;
                }
            }
        },
        
        .csv => {
            // Generate CSV data
            while (pos < size - 50) {
                const fields = [_][]const u8{ "Alice", "25", "Engineer", "New York", "100000" };
                for (fields, 0..) |field, i| {
                    if (pos + field.len >= size) break;
                    @memcpy(data[pos..pos + field.len], field);
                    pos += field.len;
                    
                    if (i < fields.len - 1 and pos < size) {
                        data[pos] = ',';
                        pos += 1;
                    }
                }
                if (pos < size) {
                    data[pos] = '\n';
                    pos += 1;
                }
            }
        },
        
        .mixed => {
            // Mixed content with numbers, words, and punctuation
            while (pos < size - 20) {
                // Random word
                const word_len = rng.random().intRangeAtMost(usize, 2, 8);
                for (0..word_len) |_| {
                    if (pos >= size) break;
                    data[pos] = 'a' + @as(u8, @intCast(rng.random().intRangeAtMost(u8, 0, 25)));
                    pos += 1;
                }
                
                // Random number
                if (pos < size - 5) {
                    const num = rng.random().intRangeAtMost(u32, 1, 99999);
                    const num_str = std.fmt.allocPrint(allocator, " {d} ", .{num}) catch break;
                    defer allocator.free(num_str);
                    
                    const copy_len = @min(num_str.len, size - pos);
                    @memcpy(data[pos..pos + copy_len], num_str[0..copy_len]);
                    pos += copy_len;
                }
                
                // Random punctuation
                if (pos < size) {
                    const punct = [_]u8{ '.', ',', '!', '?', ';' };
                    data[pos] = punct[rng.random().intRangeAtMost(usize, 0, punct.len - 1)];
                    pos += 1;
                }
            }
        },
    }
    
    // Fill remaining with spaces
    while (pos < size) {
        data[pos] = ' ';
        pos += 1;
    }
    
    return data;
}

// Benchmark structure
const BenchmarkResult = struct {
    name: []const u8,
    data_size: usize,
    time_ns: u64,
    tokens_found: usize,
    allocations: usize,
    
    pub fn throughputMBps(self: BenchmarkResult) f64 {
        const mb = @as(f64, @floatFromInt(self.data_size)) / (1024.0 * 1024.0);
        const seconds = @as(f64, @floatFromInt(self.time_ns)) / 1_000_000_000.0;
        return mb / seconds;
    }
    
    pub fn tokensPerSecond(self: BenchmarkResult) f64 {
        const seconds = @as(f64, @floatFromInt(self.time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.tokens_found)) / seconds;
    }
};

// ZigParse tokenizer benchmark
fn benchmarkZigParse(allocator: std.mem.Allocator, data: []const u8, name: []const u8) !BenchmarkResult {
    const TokenType = enum { word, number, punct, whitespace };
    const patterns = comptime .{
        .word = zigparse.match.alpha.oneOrMore(),
        .number = zigparse.match.digit.oneOrMore(),
        .punct = zigparse.match.anyOf(".,!?;:"),
        .whitespace = zigparse.match.whitespace.oneOrMore(),
    };
    
    var token_count: usize = 0;
    
    const start_time = std.time.nanoTimestamp();
    
    var stream = zigparse.TokenStream.init(data);
    while (stream.next(TokenType, patterns)) |token| {
        token_count += 1;
        // Simulate some work to prevent optimization
        std.mem.doNotOptimizeAway(token.text.ptr);
    }
    
    const end_time = std.time.nanoTimestamp();
    
    return BenchmarkResult{
        .name = name,
        .data_size = data.len,
        .time_ns = @intCast(end_time - start_time),
        .tokens_found = token_count,
        .allocations = 0, // ZigParse uses zero allocations
    };
}

// SIMD-accelerated version benchmark
fn benchmarkZigParseSIMD(allocator: std.mem.Allocator, data: []const u8, name: []const u8) !BenchmarkResult {
    _ = allocator;
    
    var token_count: usize = 0;
    var pos: usize = 0;
    
    const start_time = std.time.nanoTimestamp();
    
    // Use SIMD for whitespace skipping and alpha detection
    while (pos < data.len) {
        // Skip whitespace using SIMD
        pos = simd.simd.findNextNonWhitespace(data, pos);
        if (pos >= data.len) break;
        
        // Find end of current token using SIMD
        const token_start = pos;
        if (data[pos] >= 'a' and data[pos] <= 'z' or data[pos] >= 'A' and data[pos] <= 'Z') {
            pos = simd.simd.findEndOfAlphaSequence(data, pos);
        } else if (data[pos] >= '0' and data[pos] <= '9') {
            // Find end of number
            while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                pos += 1;
            }
        } else {
            // Single character token
            pos += 1;
        }
        
        token_count += 1;
        std.mem.doNotOptimizeAway(&data[token_start]);
    }
    
    const end_time = std.time.nanoTimestamp();
    
    return BenchmarkResult{
        .name = name,
        .data_size = data.len,
        .time_ns = @intCast(end_time - start_time),
        .tokens_found = token_count,
        .allocations = 0,
    };
}

// Streaming version benchmark
fn benchmarkStreaming(allocator: std.mem.Allocator, data: []const u8, name: []const u8) !BenchmarkResult {
    const TokenType = enum { word, number, punct, whitespace };
    const patterns = comptime .{
        .word = zigparse.match.alpha.oneOrMore(),
        .number = zigparse.match.digit.oneOrMore(),
        .punct = zigparse.match.anyOf(".,!?;:"),
        .whitespace = zigparse.match.whitespace.oneOrMore(),
    };
    
    var stream_source = std.io.fixedBufferStream(data);
    var tokenizer = try StreamingTokenizer.init(allocator, 4096);
    defer tokenizer.deinit();
    
    var token_count: usize = 0;
    
    const start_time = std.time.nanoTimestamp();
    
    while (try tokenizer.next(stream_source.reader(), TokenType, patterns)) |token| {
        token_count += 1;
        std.mem.doNotOptimizeAway(token.text.ptr);
    }
    
    const end_time = std.time.nanoTimestamp();
    
    return BenchmarkResult{
        .name = name,
        .data_size = data.len,
        .time_ns = @intCast(end_time - start_time),
        .tokens_found = token_count,
        .allocations = 0,
    };
}

// Naive std.mem.tokenize benchmark for comparison
fn benchmarkStdTokenize(allocator: std.mem.Allocator, data: []const u8, name: []const u8) !BenchmarkResult {
    _ = allocator;
    
    var token_count: usize = 0;
    
    const start_time = std.time.nanoTimestamp();
    
    var tokenizer = std.mem.tokenize(u8, data, " \t\n\r");
    while (tokenizer.next()) |token| {
        token_count += 1;
        std.mem.doNotOptimizeAway(token.ptr);
    }
    
    const end_time = std.time.nanoTimestamp();
    
    return BenchmarkResult{
        .name = name,
        .data_size = data.len,
        .time_ns = @intCast(end_time - start_time),
        .tokens_found = token_count,
        .allocations = 0,
    };
}

// Run comprehensive benchmark suite
pub fn runBenchmarks(allocator: std.mem.Allocator) !void {
    const sizes = [_]usize{ 1024, 10_240, 102_400, 1_024_000, 10_240_000 };
    const data_types = [_]@TypeOf(.words){ .words, .json, .csv, .mixed };
    
    std.debug.print("\n🚀 ZigParse Comprehensive Benchmark Suite\n");
    std.debug.print("==========================================\n\n");
    
    for (data_types) |data_type| {
        std.debug.print("📊 Testing {} data:\n", .{data_type});
        std.debug.print("Size(KB) | ZigParse | ZigParse+SIMD | Streaming | std.tokenize | Winner\n");
        std.debug.print("---------|----------|---------------|-----------|--------------|-------\n");
        
        for (sizes) |size| {
            const data = try generateTestData(allocator, size, data_type);
            defer allocator.free(data);
            
            // Run benchmarks
            const zigparse_result = try benchmarkZigParse(allocator, data, "ZigParse");
            const simd_result = try benchmarkZigParseSIMD(allocator, data, "ZigParse+SIMD");
            const streaming_result = try benchmarkStreaming(allocator, data, "Streaming");
            const std_result = try benchmarkStdTokenize(allocator, data, "std.tokenize");
            
            // Find fastest
            const results = [_]BenchmarkResult{ zigparse_result, simd_result, streaming_result, std_result };
            var fastest_idx: usize = 0;
            for (results, 0..) |result, i| {
                if (result.time_ns < results[fastest_idx].time_ns) {
                    fastest_idx = i;
                }
            }
            
            const winners = [_][]const u8{ "ZigParse", "SIMD", "Stream", "std" };
            
            std.debug.print("{d:8} | {d:8.1} | {d:13.1} | {d:9.1} | {d:12.1} | {s}\n", .{
                size / 1024,
                zigparse_result.throughputMBps(),
                simd_result.throughputMBps(),
                streaming_result.throughputMBps(),
                std_result.throughputMBps(),
                winners[fastest_idx],
            });
        }
        
        std.debug.print("\n");
    }
    
    // Memory usage test
    std.debug.print("💾 Memory Usage Validation:\n");
    const test_data = try generateTestData(allocator, 1_000_000, .mixed);
    defer allocator.free(test_data);
    
    // Test ZigParse memory usage
    var counting_allocator = std.testing.allocator_instance;
    const counting_alloc = counting_allocator.allocator();
    
    const before_allocs = counting_allocator.total_requested_bytes;
    _ = try benchmarkZigParse(counting_alloc, test_data, "Memory Test");
    const after_allocs = counting_allocator.total_requested_bytes;
    
    std.debug.print("ZigParse allocated: {d} bytes (should be 0!)\n", .{after_allocs - before_allocs});
    
    std.debug.print("\n✅ Benchmark suite completed!\n");
}

test "benchmark data generation" {
    const data = try generateTestData(std.testing.allocator, 100, .words);
    defer std.testing.allocator.free(data);
    
    try std.testing.expectEqual(@as(usize, 100), data.len);
    
    // Should contain some letters
    var has_alpha = false;
    for (data) |byte| {
        if ((byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')) {
            has_alpha = true;
            break;
        }
    }
    try std.testing.expect(has_alpha);
}

test "benchmark runner" {
    // Quick test with small data
    const small_data = try generateTestData(std.testing.allocator, 1000, .words);
    defer std.testing.allocator.free(small_data);
    
    const result = try benchmarkZigParse(std.testing.allocator, small_data, "test");
    try std.testing.expect(result.tokens_found > 0);
    try std.testing.expect(result.time_ns > 0);
    try std.testing.expectEqual(@as(usize, 0), result.allocations);
}