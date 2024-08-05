const std = @import("std");

pub fn build(b: *std.Build) !void {
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

    const optimize = b.standardOptimizeOption(.{});

    const limine = b.dependency("limine", .{});
    const limine_raw = b.dependency("limine_raw", .{});

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    {
        kernel.root_module.addImport("limine", limine.module("limine"));

        switch (target.result.cpu.arch) {
            .x86_64 => kernel.setLinkerScript(b.path("src/kernel/arch/x86_64/linker.ld")),

            else => @panic("Target CPU is not supported"),
        }

        // Disable LTO. This prevents issues with limine requests
        kernel.want_lto = false;

        b.installArtifact(kernel);
    }

    {
        const initrd_tree = b.addWriteFiles();

        const tar_compress = b.addSystemCommand(&.{ "tar", "-chRf" });

        const initrd_output = tar_compress.addOutputFileArg("initrd");

        tar_compress.addArg("-C");

        tar_compress.addDirectoryArg(initrd_tree.getDirectory());

        tar_compress.addArg(".");

        tar_compress.step.dependOn(&initrd_tree.step);

        const initrd_step = b.step("initrd", "Bundle the init ramdisk");
        initrd_step.dependOn(&b.addInstallFile(initrd_output, "initrd").step);

        const iso_tree = b.addWriteFiles();

        _ = iso_tree.addCopyFile(kernel.getEmittedBin(), "boot/kernel");

        _ = iso_tree.addCopyFile(initrd_output, "boot/initrd");

        _ = iso_tree.addCopyFile(b.path("limine.cfg"), "boot/limine/limine.cfg");

        _ = iso_tree.addCopyFile(limine_raw.path("limine-bios.sys"), "boot/limine/limine-bios.sys");

        _ = iso_tree.addCopyFile(limine_raw.path("limine-bios-cd.bin"), "boot/limine/limine-bios-cd.bin");
        _ = iso_tree.addCopyFile(limine_raw.path("limine-uefi-cd.bin"), "boot/limine/limine-uefi-cd.bin");

        _ = iso_tree.addCopyFile(limine_raw.path("BOOTX64.EFI"), "EFI/BOOT/BOOTX64.EFI");
        _ = iso_tree.addCopyFile(limine_raw.path("BOOTIA32.EFI"), "EFI/BOOT/BOOTIA32.EFI");

        iso_tree.step.dependOn(&tar_compress.step);

        const mkisofs = b.addSystemCommand(&.{ "xorriso", "-as", "mkisofs" });

        mkisofs.addArgs(&.{ "-b", "boot/limine/limine-bios-cd.bin" });
        mkisofs.addArgs(&.{ "-no-emul-boot", "-boot-load-size", "4", "-boot-info-table" });
        mkisofs.addArgs(&.{ "--efi-boot", "boot/limine/limine-uefi-cd.bin" });
        mkisofs.addArgs(&.{ "-efi-boot-part", "--efi-boot-image", "--protective-msdos-label" });
        mkisofs.addDirectoryArg(iso_tree.getDirectory());
        mkisofs.addArg("-o");

        const iso_output = mkisofs.addOutputFileArg("yos.iso");

        mkisofs.step.dependOn(&iso_tree.step);

        const limine_exe = b.addExecutable(.{
            .name = "limine",
            .target = b.host,
            .optimize = .ReleaseFast,
        });

        limine_exe.addCSourceFile(.{ .file = limine_raw.path("limine.c"), .flags = &.{"-std=c99"} });
        limine_exe.linkLibC();

        const limine_bios_install = b.addRunArtifact(limine_exe);

        limine_bios_install.addArg("bios-install");
        limine_bios_install.addFileArg(iso_output);

        limine_bios_install.step.dependOn(&mkisofs.step);

        const iso_step = b.step("iso", "Bundle into an ISO image");

        iso_step.dependOn(&limine_bios_install.step);

        switch (target.result.cpu.arch) {
            .x86_64 => {
                const core_count = b.option(u64, "core-count", "The amount of cores to use in QEMU (default is 1)") orelse 1;

                const qemu = b.addSystemCommand(&.{"qemu-system-x86_64"});

                qemu.addArgs(&.{ "-M", "q35" });
                qemu.addArgs(&.{ "-m", "256M" });
                qemu.addArgs(&.{"-cdrom"});
                qemu.addFileArg(iso_output);
                qemu.addArgs(&.{ "-boot", "d" });
                qemu.addArgs(&.{ "-smp", b.fmt("{}", .{core_count}) });

                qemu.step.dependOn(&limine_bios_install.step);

                const run_step = b.step("run", "Run the bundled ISO in QEMU");

                run_step.dependOn(&qemu.step);
            },

            else => @panic("Target CPU is not supported"),
        }
    }

    {
        const kernel_check = b.addExecutable(.{
            .name = "kernel",
            .root_source_file = b.path("src/kernel/main.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .kernel,
            .pic = true,
        });

        kernel_check.root_module.addImport("limine", limine.module("limine"));

        const check_step = b.step("check", "Checks if the kernel can compile");

        check_step.dependOn(&kernel_check.step);
    }
}
