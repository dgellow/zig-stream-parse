# ZigParse Benchmark Documentation

## Current State of Benchmarks

The benchmark implementation in `src/benchmarks/benchmark.zig` has been updated to use the full parser implementation. It now provides realistic throughput measurements for the parsing pipeline.

### Fixed Issues

1. **Tokenizer Segfaults**: Fixed multiple issues in the ByteStream and tokenizer components that were causing segmentation faults.

2. **Error State Handling**: Added proper error transitions for all states in the state machine to handle unexpected tokens gracefully.

3. **Memory Management**: Improved memory handling in all token matchers and the parser to prevent leaks.

4. **Full Parser Usage**: Benchmarks now use the complete parser pipeline rather than the simplified fallback mode.

## Implementation Details

### Benchmark Modes

The benchmark offers two modes:

1. **Full Parser Mode (Default)**: 
   - Tests the complete parsing pipeline
   - Includes tokenization, state transitions, and events
   - Properly exercises all components
   - Generates accurate throughput metrics for real parsing scenarios

2. **Fallback Mode (Retained for Comparison)**:
   - Implemented in `runSafeBenchmark()`
   - Simpler character-by-character processing
   - Only counts characters and lines
   - Available by setting `use_fallback_benchmark = true`

### Modified Components

1. **ByteStream Improvements**:
   - Enhanced bounds checking in all stream operations
   - Added defensive coding to prevent out-of-bounds access
   - Improved exhaustion handling with consistent state tracking

2. **Tokenizer Enhancements**:
   - Fixed memory management for token lexemes
   - Improved error recovery in token matchers
   - Added proper position tracking and reset capabilities

3. **Parser Memory Management**:
   - Added proper deallocation of token lexemes 
   - Fixed potential memory leaks
   - Ensured consistent allocation/deallocation patterns

4. **Error Handling**:
   - Added error token state transitions to all states
   - Implemented graceful error reporting
   - Maintained parsing stability even with unexpected inputs

## Future Improvements

Although the benchmarks now use the full parser implementation, several improvements would make them even more representative:

1. **Realistic Format Parsers**: Add complete implementations for common formats (JSON, XML, CSV) to benchmark real-world use cases.

2. **Comparative Benchmarking**: Add comparisons against existing parsing libraries to demonstrate relative performance.

3. **Memory Usage Metrics**: Replace the dummy getCurrentMemoryUsage implementation with actual memory tracking.

4. **SIMD Acceleration**: Implement and benchmark the SIMD-accelerated token matching described in the documentation.

5. **Performance Profiles**: Add more detailed performance metrics like token processing rates, state transition costs, etc.

6. **Stress Testing**: Add benchmarks specifically designed to stress error recovery and edge case handling.

7. **Regression Testing**: Implement benchmark tracking to detect performance changes over time.

## Running Benchmarks

```bash
# Run standard benchmarks
zig build benchmark

# Alternative command (both work the same)
zig build run-benchmark
```

Current output includes:
- Processing metrics (characters and lines)
- Time taken (ms)
- Input size (bytes)
- Throughput (MB/s)

## Interpreting Results

The benchmark results now represent the full parsing pipeline performance, including tokenization, state transitions, and event generation. These metrics provide a realistic measure of the parser's capabilities for structured data processing.