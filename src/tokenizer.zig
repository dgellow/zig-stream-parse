const std = @import("std");
const ByteStream = @import("byte_stream.zig").ByteStream;
const Position = @import("common.zig").Position;
const TokenPool = @import("token_pool.zig").TokenPool;

pub const TokenType = struct {
    id: u32,
    name: []const u8,
};

pub const Token = struct {
    type: TokenType,
    position: Position,
    lexeme: []const u8,

    pub fn init(token_type: TokenType, position: Position, lexeme: []const u8) Token {
        return .{
            .type = token_type,
            .position = position,
            .lexeme = lexeme,
        };
    }
};

pub const TokenMatcher = struct {
    match_fn: *const fn(stream: *ByteStream, allocator: std.mem.Allocator) anyerror!?Token,

    pub fn init(comptime matcher_fn: anytype) TokenMatcher {
        return .{
            .match_fn = matcher_fn,
        };
    }

    pub fn match(self: TokenMatcher, stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
        return self.match_fn(stream, allocator);
    }
    
    pub fn matchWithPool(
        self: TokenMatcher, 
        stream: *ByteStream, 
        pool: *TokenPool
    ) !?Token {
        // Create a simple allocator that uses the token pool
        const allocator = std.mem.Allocator{
            .ptr = pool,
            .vtable = &.{
                .alloc = poolAlloc,
                .resize = poolResize,
                .free = poolFree,
                .remap = poolRemap,
            },
        };
        
        return self.match_fn(stream, allocator);
    }
};

// Helper functions for pool-based allocator
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

pub const Tokenizer = struct {
    allocator: std.mem.Allocator,
    stream: *ByteStream,
    matchers: []const TokenMatcher,
    skip_types: []const TokenType,
    token_buffer: std.ArrayList(u8),
    token_pool: ?TokenPool,
    use_pool: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        stream: *ByteStream,
        matchers: []const TokenMatcher,
        skip_types: []const TokenType,
    ) !Tokenizer {
        return .{
            .allocator = allocator,
            .stream = stream,
            .matchers = matchers,
            .skip_types = skip_types,
            .token_buffer = std.ArrayList(u8).init(allocator),
            .token_pool = null,
            .use_pool = false,
        };
    }
    
    /// Initialize the tokenizer with a memory pool for tokens
    /// This can significantly reduce allocation overhead during parsing
    pub fn initWithPool(
        allocator: std.mem.Allocator,
        stream: *ByteStream,
        matchers: []const TokenMatcher,
        skip_types: []const TokenType,
        pool_size: usize,
    ) !Tokenizer {
        var token_pool = try TokenPool.init(allocator, pool_size);
        errdefer token_pool.deinit();
        
        return .{
            .allocator = allocator,
            .stream = stream,
            .matchers = matchers,
            .skip_types = skip_types,
            .token_buffer = std.ArrayList(u8).init(allocator),
            .token_pool = token_pool,
            .use_pool = true,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.token_buffer.deinit();
        if (self.token_pool) |*pool| {
            pool.deinit();
        }
    }
    
    /// Reset the token pool if it exists
    pub fn resetPool(self: *Tokenizer) void {
        if (self.token_pool) |*pool| {
            pool.reset();
        }
    }
    
    /// Get the amount of memory used by the token pool
    pub fn poolUsage(self: *Tokenizer) ?usize {
        if (self.token_pool) |pool| {
            return pool.used();
        }
        return null;
    }
    
    /// Get the amount of memory available in the token pool
    pub fn poolAvailable(self: *Tokenizer) ?usize {
        if (self.token_pool) |pool| {
            return pool.available();
        }
        return null;
    }

    pub fn nextToken(self: *Tokenizer) !?Token {
        while (true) {
            const position = self.stream.getPosition();

            // Try each matcher, using the token pool if available
            for (self.matchers) |matcher| {
                const token_opt = if (self.use_pool and self.token_pool != null)
                    try matcher.matchWithPool(self.stream, &self.token_pool.?)
                else
                    try matcher.match(self.stream, self.allocator);
                
                if (token_opt) |token| {
                    // Check if this token type should be skipped
                    var should_skip = false;
                    for (self.skip_types) |skip_type| {
                        if (token.type.id == skip_type.id) {
                            should_skip = true;
                            break;
                        }
                    }

                    if (!should_skip) {
                        return token;
                    } else {
                        // Skip this token and continue
                        break;
                    }
                }
            }

            // No matcher matched, check if at EOF
            const next_byte = try self.stream.peek();
            if (next_byte == null) {
                return null; // EOF
            }

            // No matcher matched but not at EOF - unrecognized character
            _ = try self.stream.consume();
            
            // Create a safe copy of the error character in the token buffer
            self.token_buffer.clearRetainingCapacity();
            try self.token_buffer.append(next_byte.?);
            
            // Create an error token with the copied character, using the token pool if available
            const error_lexeme = if (self.use_pool and self.token_pool != null)
                try self.token_pool.?.dupe(self.token_buffer.items)
            else
                try self.allocator.dupe(u8, self.token_buffer.items);
            
            return Token.init(
                .{ .id = std.math.maxInt(u32), .name = "ERROR" },
                position,
                error_lexeme
            );
        }
    }
};