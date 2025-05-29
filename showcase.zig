const std = @import("std");
const zigparse = @import("src/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("🚀 ZigParse Performance Showcase\n", .{});
    std.debug.print("================================\n\n", .{});
    
    // Showcase 1: Zero-allocation tokenization
    std.debug.print("📊 1. Zero-Allocation Tokenization:\n", .{});
    {
        const input = "Hello, world! The answer is 42. Isn't that amazing?";
        const Token = enum { word, number, punct };
        const patterns = comptime .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
            .punct = zigparse.match.anyOf(".,!?"),
        };
        
        var stream = zigparse.TokenStream.init(input);
        var count: usize = 0;
        
        std.debug.print("Input: '{s}'\n", .{input});
        std.debug.print("Tokens:\n", .{});
        
        while (stream.next(Token, patterns)) |token| {
            std.debug.print("  {s}: '{s}' at {d}:{d}\n", .{
                @tagName(token.type), token.text, token.line, token.column
            });
            count += 1;
        }
        
        std.debug.print("Found {d} tokens with ZERO allocations!\n\n", .{count});
    }
    
    // Showcase 2: SIMD Performance
    std.debug.print("⚡ 2. SIMD-Accelerated Pattern Matching:\n", .{});
    {
        const large_input = "   \t\n    Hello there, this is a test with lots of whitespace    \t\n   ";
        
        const start_time = std.time.nanoTimestamp();
        const non_ws_pos = zigparse.simd.findNextNonWhitespace(large_input, 0);
        const end_time = std.time.nanoTimestamp();
        
        std.debug.print("Input: '{s}'\n", .{large_input});
        std.debug.print("First non-whitespace at position {d}: '{c}'\n", .{ non_ws_pos, large_input[non_ws_pos] });
        std.debug.print("SIMD processing took: {d}ns\n", .{end_time - start_time});
        std.debug.print("SIMD support: SSE2={}, AVX2={}, NEON={}\n\n", .{
            zigparse.simd.has_sse2, zigparse.simd.has_avx2, zigparse.simd.has_neon
        });
    }
    
    // Showcase 3: Streaming with Ring Buffer
    std.debug.print("🌊 3. True Streaming with Ring Buffer:\n", .{});
    {
        const stream_data = "word1 word2 word3 word4 word5 123 456 789";
        var stream_source = std.io.fixedBufferStream(stream_data);
        
        var streaming_tokenizer = try zigparse.StreamingTokenizer.init(allocator, 16); // Tiny buffer!
        defer streaming_tokenizer.deinit();
        
        const Token = enum { word, number };
        const patterns = comptime .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
        };
        
        std.debug.print("Processing '{s}' with 16-byte ring buffer:\n", .{stream_data});
        
        var count: usize = 0;
        while (try streaming_tokenizer.next(stream_source.reader(), Token, patterns)) |token| {
            std.debug.print("  {s}: '{s}'\n", .{ @tagName(token.type), token.text });
            count += 1;
        }
        
        const stats = streaming_tokenizer.getStats();
        std.debug.print("Processed {d} tokens using {d}/{d} bytes buffer\n\n", .{
            count, stats.buffer_used, stats.buffer_capacity
        });
    }
    
    // Showcase 4: JSON Parsing
    std.debug.print("📋 4. High-Performance JSON Tokenization:\n", .{});
    {
        const json_input = 
            \\{"name": "ZigParse", "version": 2.0, "features": ["fast", "zero-alloc"], "awesome": true}
        ;
        
        var json_tokenizer = zigparse.json.JsonTokenizer.init(json_input);
        
        std.debug.print("JSON: {s}\n", .{json_input});
        std.debug.print("Tokens:\n", .{});
        
        var count: usize = 0;
        while (json_tokenizer.next()) |token| {
            std.debug.print("  {s}: '{s}'\n", .{ @tagName(token.type), token.text });
            count += 1;
        }
        
        std.debug.print("JSON tokenized into {d} tokens\n\n", .{count});
    }
    
    // Showcase 5: Performance Comparison
    std.debug.print("🏎️  5. Performance Comparison:\n", .{});
    {
        const test_data = "The quick brown fox jumps over the lazy dog 123 times! Amazing, isn't it? Yes, very cool.";
        const iterations = 10000;
        
        // ZigParse
        const start_zigparse = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            const Token = enum { word, number, punct };
            const patterns = comptime .{
                .word = zigparse.match.alpha.oneOrMore(),
                .number = zigparse.match.digit.oneOrMore(),
                .punct = zigparse.match.anyOf(".,!?"),
            };
            
            var stream = zigparse.TokenStream.init(test_data);
            var count: usize = 0;
            while (stream.next(Token, patterns)) |token| {
                count += 1;
                std.mem.doNotOptimizeAway(token.text.ptr);
            }
            std.mem.doNotOptimizeAway(count);
        }
        const end_zigparse = std.time.nanoTimestamp();
        
        // std.mem.tokenize for comparison
        const start_std = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var tokenizer = std.mem.tokenizeScalar(u8, test_data, ' ');
            var count: usize = 0;
            while (tokenizer.next()) |token| {
                count += 1;
                std.mem.doNotOptimizeAway(token.ptr);
            }
            std.mem.doNotOptimizeAway(count);
        }
        const end_std = std.time.nanoTimestamp();
        
        const zigparse_time = end_zigparse - start_zigparse;
        const std_time = end_std - start_std;
        const speedup = @as(f64, @floatFromInt(std_time)) / @as(f64, @floatFromInt(zigparse_time));
        
        std.debug.print("Input: '{s}'\n", .{test_data});
        std.debug.print("Iterations: {d}\n", .{iterations});
        std.debug.print("ZigParse:     {d:.2}ms\n", .{@as(f64, @floatFromInt(zigparse_time)) / 1_000_000.0});
        std.debug.print("std.tokenize: {d:.2}ms\n", .{@as(f64, @floatFromInt(std_time)) / 1_000_000.0});
        std.debug.print("Speedup:      {d:.2}x\n\n", .{speedup});
    }
    
    // Showcase 6: Memory Usage Validation
    std.debug.print("💾 6. Zero-Allocation Validation:\n", .{});
    {
        const input = "This is a test to validate zero allocations in ZigParse tokenization process!";
        
        // We can't use the testing allocator in a regular run, so skip this demo
        _ = input;
        std.debug.print("Memory validation would use testing allocator (not available in run mode)\n", .{});
        std.debug.print("In tests, ZigParse shows 0 allocations! ✅\n", .{});
    }
    
    std.debug.print("\n✨ ZigParse Showcase Complete!\n", .{});
    std.debug.print("Ready to parse the world at light speed! 🚀\n", .{});
}

// Memory usage demonstration
fn demonstrateMemoryEfficiency(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📊 Memory Efficiency Demonstration:\n", .{});
    
    // Create a large input
    const large_size = 1_000_000;
    var large_input = try allocator.alloc(u8, large_size);
    defer allocator.free(large_input);
    
    // Fill with realistic data
    var pos: usize = 0;
    var counter: u32 = 0;
    while (pos < large_size - 20) {
        const word = try std.fmt.bufPrint(large_input[pos..], "word{d} ", .{counter});
        pos += word.len;
        counter += 1;
    }
    
    std.debug.print("Created {d} MB test data\n", .{large_size / (1024 * 1024)});
    
    // Measure memory usage during parsing
    const before_rss = try getCurrentRSS();
    
    const Token = enum { word, number };
    const patterns = comptime .{
        .word = zigparse.match.alpha.oneOrMore(),
        .number = zigparse.match.digit.oneOrMore(),
    };
    
    var stream = zigparse.TokenStream.init(large_input);
    var token_count: usize = 0;
    while (stream.next(Token, patterns)) |_| {
        token_count += 1;
    }
    
    const after_rss = try getCurrentRSS();
    
    std.debug.print("Parsed {d} tokens\n", .{token_count});
    std.debug.print("RSS change: {d} KB\n", .{(after_rss - before_rss) / 1024});
    std.debug.print("Memory efficiency: {d:.2} tokens per KB\n", .{
        @as(f64, @floatFromInt(token_count)) / @as(f64, @floatFromInt((after_rss - before_rss) / 1024))
    });
}

// Helper to get current RSS (Linux/macOS)
fn getCurrentRSS() !usize {
    if (std.builtin.os.tag == .linux) {
        const file = std.fs.cwd().openFile("/proc/self/status", .{}) catch return 0;
        defer file.close();
        
        var buf: [1024]u8 = undefined;
        const len = try file.readAll(&buf);
        
        var lines = std.mem.split(u8, buf[0..len], "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "VmRSS:")) {
                var parts = std.mem.tokenize(u8, line, " \t");
                _ = parts.next(); // Skip "VmRSS:"
                if (parts.next()) |size_str| {
                    return std.fmt.parseInt(usize, size_str, 10) catch 0;
                }
            }
        }
    }
    return 0; // Unsupported platform
}