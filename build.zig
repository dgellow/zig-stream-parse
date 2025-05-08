const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});


    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("zig_stream_parse_lib", lib_mod);

    // Create a module for our CSV example
    const csv_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/csv_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    csv_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    // Create a module for our simple example
    const simple_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/simple_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    // Create a module for our error handling example
    const error_example_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/error_handling_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_example_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    // Create a module for our error aggregation example
    const error_aggregation_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/error_aggregation_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_aggregation_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    // Create a module for our error visualization example
    const error_visualization_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/error_visualization_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_visualization_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    // Create a module for benchmarks
    const benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmarks/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark_mod.addImport("zig_stream_parse_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zig_stream_parse",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
    
    // Create a C ABI library module
    const c_api_mod = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_api_mod.addImport("parser", lib_mod);
    
    // Build the C ABI library
    const c_lib = b.addSharedLibrary(.{
        .name = "zigparse",
        .root_module = c_api_mod,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    
    // Install the C header file
    b.installFile("src/zigparse.h", "include/zigparse.h");
    
    // Install the C library
    b.installArtifact(c_lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "zig_stream_parse",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // Create the CSV parser example executable
    const csv_exe = b.addExecutable(.{
        .name = "csv_parser",
        .root_module = csv_mod,
    });
    b.installArtifact(csv_exe);
    
    // Create the simple example executable
    const simple_exe = b.addExecutable(.{
        .name = "simple_example",
        .root_module = simple_mod,
    });
    b.installArtifact(simple_exe);
    
    // Create the error handling example executable
    const error_example_exe = b.addExecutable(.{
        .name = "error_handling_example",
        .root_module = error_example_mod,
    });
    b.installArtifact(error_example_exe);
    
    // Create the error aggregation example executable
    const error_aggregation_exe = b.addExecutable(.{
        .name = "error_aggregation_example",
        .root_module = error_aggregation_mod,
    });
    b.installArtifact(error_aggregation_exe);
    
    // Create the error visualization example executable
    const error_visualization_exe = b.addExecutable(.{
        .name = "error_visualization_example",
        .root_module = error_visualization_mod,
    });
    b.installArtifact(error_visualization_exe);
    
    // Create the benchmark executable
    const benchmark_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = benchmark_mod,
    });
    b.installArtifact(benchmark_exe);
    
    // Create the C example executable
    const c_example = b.addExecutable(.{
        .name = "c_example",
        .target = target,
        .optimize = optimize,
    });
    c_example.addCSourceFile(.{
        .file = b.path("examples/c/example.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });
    c_example.linkLibC();
    c_example.linkLibrary(c_lib);
    c_example.addIncludePath(b.path("src"));
    b.installArtifact(c_example);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create a run step for the CSV parser example
    const run_csv_cmd = b.addRunArtifact(csv_exe);
    run_csv_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_csv_cmd.addArgs(args);
    }
    
    // Create a run step for the simple example
    const run_simple_cmd = b.addRunArtifact(simple_exe);
    run_simple_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_simple_cmd.addArgs(args);
    }
    
    // Create a run step for the error handling example
    const run_error_example_cmd = b.addRunArtifact(error_example_exe);
    run_error_example_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_error_example_cmd.addArgs(args);
    }
    
    // Create a run step for the error aggregation example
    const run_error_aggregation_cmd = b.addRunArtifact(error_aggregation_exe);
    run_error_aggregation_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_error_aggregation_cmd.addArgs(args);
    }
    
    // Create a run step for the error visualization example
    const run_error_visualization_cmd = b.addRunArtifact(error_visualization_exe);
    run_error_visualization_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_error_visualization_cmd.addArgs(args);
    }
    
    // This "run_incremental_parsing_example_cmd" will be defined later
    
    // Create a run step for the benchmark
    const run_benchmark_cmd = b.addRunArtifact(benchmark_exe);
    run_benchmark_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_benchmark_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Create a step to run the CSV parser example
    const run_csv_step = b.step("run-csv", "Run the CSV parser example");
    run_csv_step.dependOn(&run_csv_cmd.step);
    
    // Create a step to run the simple example
    const run_simple_step = b.step("run-simple", "Run the simple example");
    run_simple_step.dependOn(&run_simple_cmd.step);
    
    // Create a step to run the error handling example
    const run_error_example_step = b.step("run-error-example", "Run the error handling example");
    run_error_example_step.dependOn(&run_error_example_cmd.step);
    
    // Create a step to run the error aggregation example
    const run_error_aggregation_step = b.step("run-error-aggregation", "Run the error aggregation example");
    run_error_aggregation_step.dependOn(&run_error_aggregation_cmd.step);
    
    // Create a step to run the error visualization example
    const run_error_visualization_step = b.step("run-error-visualization", "Run the error visualization example");
    run_error_visualization_step.dependOn(&run_error_visualization_cmd.step);
    
    // This "run_incremental_parsing_example_step" will be defined later
    
    // Create a step to run the benchmark
    const run_benchmark_step = b.step("benchmark", "Run the benchmarks");
    run_benchmark_step.dependOn(&run_benchmark_cmd.step);
    
    // Create an alias for backward compatibility
    const run_benchmark_step_alt = b.step("run-benchmark", "Run the benchmarks (alias for 'benchmark')");
    run_benchmark_step_alt.dependOn(&run_benchmark_cmd.step);
    
    // Create a run step for the C example
    const run_c_example_cmd = b.addRunArtifact(c_example);
    run_c_example_cmd.step.dependOn(b.getInstallStep());
    const run_c_example_step = b.step("run-c-example", "Run the C API example");
    run_c_example_step.dependOn(&run_c_example_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    
    // Create a module for ByteStream enhanced
    const byte_stream_enhanced_mod = b.createModule(.{
        .root_source_file = b.path("src/byte_stream_enhanced.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create a module for ByteStream optimized
    const byte_stream_optimized_mod = b.createModule(.{
        .root_source_file = b.path("src/byte_stream_optimized.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create a module for Parser optimized
    const parser_optimized_mod = b.createModule(.{
        .root_source_file = b.path("src/parser_optimized.zig"),
        .target = target,
        .optimize = optimize,
    });
    parser_optimized_mod.addImport("byte_stream_optimized", byte_stream_optimized_mod);
    
    // Create a module for our simple incremental buffer example
    const incremental_buffer_example_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/incremental_buffer_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    incremental_buffer_example_mod.addImport("byte_stream_optimized", byte_stream_optimized_mod);
    
    // Create the incremental buffer example executable
    // Create a simplified version that doesn't depend on the main library
    const incremental_buffer_example_exe = b.addExecutable(.{
        .name = "incremental_buffer_example",
        .root_module = incremental_buffer_example_mod,
    });
    
    // Don't install this by default to avoid dependencies
    // b.installArtifact(incremental_buffer_example_exe);
    
    // Create a run step for the incremental buffer example
    const run_incremental_buffer_example_cmd = b.addRunArtifact(incremental_buffer_example_exe);
    run_incremental_buffer_example_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_incremental_buffer_example_cmd.addArgs(args);
    }
    
    // Create a step to run the incremental buffer example
    const run_incremental_buffer_example_step = b.step("run-buffer-example", "Run the incremental buffer example");
    run_incremental_buffer_example_step.dependOn(&run_incremental_buffer_example_cmd.step);
    
    // Create a module for our new buffer management demo
    const buffer_management_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/buffer_management_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    buffer_management_demo_mod.addImport("byte_stream_optimized", byte_stream_optimized_mod);
    
    // Create the buffer management demo executable
    const buffer_management_demo_exe = b.addExecutable(.{
        .name = "buffer_management_demo",
        .root_module = buffer_management_demo_mod,
    });
    
    b.installArtifact(buffer_management_demo_exe);
    
    // Create a run step for the buffer management demo
    const run_buffer_management_demo_cmd = b.addRunArtifact(buffer_management_demo_exe);
    run_buffer_management_demo_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_buffer_management_demo_cmd.addArgs(args);
    }
    
    // Create a step to run the buffer management demo
    const run_buffer_management_demo_step = b.step("run-buffer-demo", "Run the buffer management demo");
    run_buffer_management_demo_step.dependOn(&run_buffer_management_demo_cmd.step);
    
    // Create a test for the enhanced ByteStream
    const byte_stream_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/byte_stream_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    byte_stream_test_mod.addImport("byte_stream_enhanced", byte_stream_enhanced_mod);
    
    const byte_stream_tests = b.addTest(.{
        .root_module = byte_stream_test_mod,
    });
    
    const run_byte_stream_tests = b.addRunArtifact(byte_stream_tests);
    
    // Create a test for the optimized ByteStream
    const byte_stream_optimized_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/byte_stream_optimized_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    byte_stream_optimized_test_mod.addImport("byte_stream_optimized", byte_stream_optimized_mod);
    
    const byte_stream_optimized_tests = b.addTest(.{
        .root_module = byte_stream_optimized_test_mod,
    });
    
    const run_byte_stream_optimized_tests = b.addRunArtifact(byte_stream_optimized_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_byte_stream_tests.step);
    test_step.dependOn(&run_byte_stream_optimized_tests.step);
    
    // Add a specific step for ByteStream tests
    const byte_stream_test_step = b.step("test-bytestream", "Run ByteStream tests");
    byte_stream_test_step.dependOn(&run_byte_stream_tests.step);
    
    // Add a specific step for optimized ByteStream tests
    const byte_stream_optimized_test_step = b.step("test-bytestream-optimized", "Run optimized ByteStream tests");
    byte_stream_optimized_test_step.dependOn(&run_byte_stream_optimized_tests.step);
    
    // Create a test for incremental parsing
    const incremental_parsing_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/incremental_parsing_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    incremental_parsing_test_mod.addImport("parser", lib_mod);
    
    const incremental_parsing_tests = b.addTest(.{
        .root_module = incremental_parsing_test_mod,
    });
    
    const run_incremental_parsing_tests = b.addRunArtifact(incremental_parsing_tests);
    
    // Create a test for optimized incremental parsing
    const incremental_parsing_test_optimized_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/incremental_parsing_test_optimized.zig"),
        .target = target,
        .optimize = optimize,
    });
    incremental_parsing_test_optimized_mod.addImport("byte_stream_optimized", byte_stream_optimized_mod);
    incremental_parsing_test_optimized_mod.addImport("parser_optimized", parser_optimized_mod);
    
    const incremental_parsing_tests_optimized = b.addTest(.{
        .root_module = incremental_parsing_test_optimized_mod,
    });
    
    const run_incremental_parsing_tests_optimized = b.addRunArtifact(incremental_parsing_tests_optimized);
    
    // Add the tests to the main test step
    test_step.dependOn(&run_incremental_parsing_tests.step);
    test_step.dependOn(&run_incremental_parsing_tests_optimized.step);
    
    // Add specific steps for incremental parsing tests
    const incremental_parsing_test_step = b.step("test-incremental", "Run incremental parsing tests");
    incremental_parsing_test_step.dependOn(&run_incremental_parsing_tests.step);
    
    const incremental_parsing_test_optimized_step = b.step("test-incremental-optimized", "Run optimized incremental parsing tests");
    incremental_parsing_test_optimized_step.dependOn(&run_incremental_parsing_tests_optimized.step);
    
    // Create a simpler incremental test module
    const incremental_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/incremental_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    incremental_test_mod.addImport("parser", lib_mod);
    
    const incremental_tests = b.addTest(.{
        .root_module = incremental_test_mod,
    });
    
    const run_incremental_tests = b.addRunArtifact(incremental_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_incremental_tests.step);
    
    // Add a specific step for simple incremental tests
    const incremental_test_step = b.step("test-incremental-simple", "Run simple incremental tests");
    incremental_test_step.dependOn(&run_incremental_tests.step);
    
    
    // Create a test for token pool
    const token_pool_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/token_pool_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    token_pool_test_mod.addImport("token_pool", b.createModule(.{
        .root_source_file = b.path("src/token_pool.zig"),
        .target = target,
        .optimize = optimize,
    }));
    
    const token_pool_tests = b.addTest(.{
        .root_module = token_pool_test_mod,
    });
    
    const run_token_pool_tests = b.addRunArtifact(token_pool_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_token_pool_tests.step);
    
    // Add a specific step for token pool tests
    const token_pool_test_step = b.step("test-token-pool", "Run token pool tests");
    token_pool_test_step.dependOn(&run_token_pool_tests.step);
    
    // Create a test for tokenizer with token pool
    const tokenizer_pool_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/tokenizer_pool_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenizer_pool_test_mod.addImport("parser", lib_mod);
    
    const tokenizer_pool_tests = b.addTest(.{
        .root_module = tokenizer_pool_test_mod,
    });
    
    const run_tokenizer_pool_tests = b.addRunArtifact(tokenizer_pool_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_tokenizer_pool_tests.step);
    
    // Add a specific step for tokenizer pool tests
    const tokenizer_pool_test_step = b.step("test-tokenizer-pool", "Run tokenizer with pool tests");
    tokenizer_pool_test_step.dependOn(&run_tokenizer_pool_tests.step);
    
    // Create a test for token pool allocator
    const token_pool_allocator_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/token_pool_allocator_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    token_pool_allocator_test_mod.addImport("token_pool", b.createModule(.{
        .root_source_file = b.path("src/token_pool.zig"),
        .target = target,
        .optimize = optimize,
    }));
    
    const token_pool_allocator_tests = b.addTest(.{
        .root_module = token_pool_allocator_test_mod,
    });
    
    const run_token_pool_allocator_tests = b.addRunArtifact(token_pool_allocator_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_token_pool_allocator_tests.step);
    
    // Add a specific step for token pool allocator tests
    const token_pool_allocator_test_step = b.step("test-token-pool-allocator", "Run token pool allocator tests");
    token_pool_allocator_test_step.dependOn(&run_token_pool_allocator_tests.step);
    
    // Create a test for simplified tokenizer pool
    const simple_tokenizer_pool_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/simple_tokenizer_pool_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_tokenizer_pool_test_mod.addImport("parser", lib_mod);
    
    const simple_tokenizer_pool_tests = b.addTest(.{
        .root_module = simple_tokenizer_pool_test_mod,
    });
    
    const run_simple_tokenizer_pool_tests = b.addRunArtifact(simple_tokenizer_pool_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_simple_tokenizer_pool_tests.step);
    
    // Add a specific step for simplified tokenizer pool tests
    const simple_tokenizer_pool_test_step = b.step("test-simple-tokenizer-pool", "Run simplified tokenizer pool tests");
    simple_tokenizer_pool_test_step.dependOn(&run_simple_tokenizer_pool_tests.step);

    // Create a test for error handling
    const error_handling_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/error_handling_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_handling_test_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    const error_handling_tests = b.addTest(.{
        .root_module = error_handling_test_mod,
    });
    
    const run_error_handling_tests = b.addRunArtifact(error_handling_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_error_handling_tests.step);
    
    // Add a specific step for error handling tests
    const error_handling_test_step = b.step("test-error-handling", "Run error handling tests");
    error_handling_test_step.dependOn(&run_error_handling_tests.step);
    
    // Create a test for error aggregation
    const error_aggregator_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/error_aggregator_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_aggregator_test_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    const error_aggregator_tests = b.addTest(.{
        .root_module = error_aggregator_test_mod,
    });
    
    const run_error_aggregator_tests = b.addRunArtifact(error_aggregator_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_error_aggregator_tests.step);
    
    // Add a specific step for error aggregation tests
    const error_aggregator_test_step = b.step("test-error-aggregation", "Run error aggregation tests");
    error_aggregator_test_step.dependOn(&run_error_aggregator_tests.step);
    
    // Create a test for error visualization
    const error_visualizer_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/error_visualizer_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_visualizer_test_mod.addImport("zig_stream_parse_lib", lib_mod);
    
    const error_visualizer_tests = b.addTest(.{
        .root_module = error_visualizer_test_mod,
    });
    
    const run_error_visualizer_tests = b.addRunArtifact(error_visualizer_tests);
    
    // Add the test to the main test step
    test_step.dependOn(&run_error_visualizer_tests.step);
    
    // Add a specific step for error visualization tests
    const error_visualizer_test_step = b.step("test-error-visualization", "Run error visualization tests");
    error_visualizer_test_step.dependOn(&run_error_visualizer_tests.step);
}