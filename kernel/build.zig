const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define a freestanding x86_64 cross-compilation target
    var target: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Get the optimization option provided by -Doptimize
    const optimize = b.standardOptimizeOption(.{});

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    // Gett limine boot protocol utilities
    const limine = b.dependency("limine", .{});

    // Build the kernel itself
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    kernel.root_module.addImport("limine", limine.module("limine"));

    kernel.setLinkerScript(b.path("linker.ld"));

    // Disable LTO. This prevents issues with limine requests
    kernel.want_lto = false;

    b.installArtifact(kernel);

    const kernel_check = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    kernel_check.root_module.addImport("limine", limine.module("limine"));

    kernel_check.setLinkerScript(b.path("linker.ld"));

    const check_step = b.step("check", "Checks if the app can compile");
    check_step.dependOn(&kernel_check.step);
}
