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
        const image_name = "yos";

        try std.fs.deleteTreeAbsolute(b.getInstallPath(.prefix, "iso_root/"));

        try std.fs.makeDirAbsolute(b.getInstallPath(.prefix, "iso_root/"));
        try std.fs.makeDirAbsolute(b.getInstallPath(.prefix, "iso_root/boot/"));
        try std.fs.makeDirAbsolute(b.getInstallPath(.prefix, "iso_root/boot/limine/"));
        try std.fs.makeDirAbsolute(b.getInstallPath(.prefix, "iso_root/EFI/"));
        try std.fs.makeDirAbsolute(b.getInstallPath(.prefix, "iso_root/EFI/BOOT/"));

        try std.fs.deleteTreeAbsolute(b.getInstallPath(.prefix, "iso/"));
        try std.fs.makeDirAbsolute(b.getInstallPath(.prefix, "iso/"));

        const copy_kernel = b.addInstallArtifact(kernel, .{ .dest_dir = .{ .override = .{ .custom = "iso_root/boot/" } } });

        const copy_limine_cfg = b.addInstallFile(b.path("limine.cfg"), "iso_root/boot/limine/limine.cfg");
        const copy_limine_bios_sys = b.addInstallFile(limine_raw.path("limine-bios.sys"), "iso_root/boot/limine/limine-bios.sys");
        const copy_limine_bios_cd_bin = b.addInstallFile(limine_raw.path("limine-bios-cd.bin"), "iso_root/boot/limine/limine-bios-cd.bin");
        const copy_limine_uefi_cd_bin = b.addInstallFile(limine_raw.path("limine-uefi-cd.bin"), "iso_root/boot/limine/limine-uefi-cd.bin");

        const copy_limine_boot_x64 = b.addInstallFile(limine_raw.path("BOOTX64.EFI"), "iso_root/EFI/BOOT/BOOTX64.EFI");
        const copy_limine_boot_ia32 = b.addInstallFile(limine_raw.path("BOOTIA32.EFI"), "iso_root/EFI/BOOT/BOOTIA32.EFI");

        const mkisofs = b.addSystemCommand(&.{ "xorriso", "-as", "mkisofs" });

        mkisofs.addArgs(&.{ "-b", "boot/limine/limine-bios-cd.bin" });
        mkisofs.addArgs(&.{ "-no-emul-boot", "-boot-load-size", "4", "-boot-info-table" });
        mkisofs.addArgs(&.{ "--efi-boot", "boot/limine/limine-uefi-cd.bin" });
        mkisofs.addArgs(&.{ "-efi-boot-part", "--efi-boot-image", "--protective-msdos-label" });
        mkisofs.addArg(b.getInstallPath(.prefix, "iso_root"));
        mkisofs.addArgs(&.{ "-o", b.getInstallPath(.prefix, b.fmt("iso/{s}.iso", .{image_name})) });

        mkisofs.step.dependOn(&copy_kernel.step);

        mkisofs.step.dependOn(&copy_limine_cfg.step);
        mkisofs.step.dependOn(&copy_limine_bios_sys.step);
        mkisofs.step.dependOn(&copy_limine_bios_cd_bin.step);
        mkisofs.step.dependOn(&copy_limine_uefi_cd_bin.step);

        mkisofs.step.dependOn(&copy_limine_boot_x64.step);
        mkisofs.step.dependOn(&copy_limine_boot_ia32.step);

        const limine_bin_build = b.addSystemCommand(&.{"make"});
        limine_bin_build.setCwd(limine_raw.path("."));

        const limine_bios_install = b.addSystemCommand(&.{ "./limine", "bios-install", b.getInstallPath(.prefix, b.fmt("iso/{s}.iso", .{image_name})) });
        limine_bios_install.setCwd(limine_raw.path("."));

        limine_bios_install.step.dependOn(&mkisofs.step);
        limine_bios_install.step.dependOn(&limine_bin_build.step);

        const iso_step = b.step("iso", "Bundle into an iso image");

        iso_step.dependOn(&limine_bios_install.step);

        switch (target.result.cpu.arch) {
            .x86_64 => {
                const qemu = b.addSystemCommand(&.{"qemu-system-x86_64"});

                qemu.addArgs(&.{ "-M", "q35" });
                qemu.addArgs(&.{ "-m", "256M" });
                qemu.addArgs(&.{ "-cdrom", b.getInstallPath(.prefix, b.fmt("iso/{s}.iso", .{image_name})) });
                qemu.addArgs(&.{ "-boot", "d" });

                qemu.step.dependOn(&limine_bios_install.step);

                const run_step = b.step("run", "Run the bundled iso in QEMU");

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
