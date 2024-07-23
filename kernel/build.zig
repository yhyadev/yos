const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define a freestanding x86_64 cross-compilation target
    var target_query: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature
    const Features = std.Target.x86.Feature;
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target_query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    const target = b.resolveTargetQuery(target_query);

    // Get the optimization option provided by -Doptimize
    const optimize = b.standardOptimizeOption(.{});

    // Get limine boot protocol utilities
    const limine = b.dependency("limine", .{});

    // Build the kernel itself
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    kernel.root_module.addImport("limine", limine.module("limine"));

    switch (target.result.cpu.arch) {
        .x86_64 => kernel.setLinkerScript(b.path("src/arch/x86_64/linker.ld")),
        else => @panic("Target CPU is not supported"),
    }

    // Disable LTO. This prevents issues with limine requests
    kernel.want_lto = false;

    b.installArtifact(kernel);

    const kernel_check = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    kernel_check.root_module.addImport("limine", limine.module("limine"));

    const check_step = b.step("check", "Checks if the app can compile");
    check_step.dependOn(&kernel_check.step);
}
