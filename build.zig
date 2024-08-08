const std = @import("std");

const Land = enum {
    kernel,
    user,
};

fn getTarget(b: *std.Build, cpu_arch: std.Target.Cpu.Arch, land: Land) !std.Build.ResolvedTarget {
    return b.resolveTargetQuery(.{
        .cpu_arch = cpu_arch,

        .os_tag = switch (land) {
            .kernel => .freestanding,
            .user => .other,
        },

        .abi = .none,

        .cpu_features_add = switch (cpu_arch) {
            .x86_64 => blk: {
                const Feature = std.Target.x86.Feature;

                break :blk std.Target.x86.featureSet(&.{
                    Feature.soft_float,
                });
            },

            else => return error.UnsupportedArch,
        },

        .cpu_features_sub = switch (cpu_arch) {
            .x86_64 => blk: {
                const Feature = std.Target.x86.Feature;

                break :blk std.Target.x86.featureSet(&.{
                    Feature.mmx,
                    Feature.sse,
                    Feature.sse2,
                    Feature.sse3,
                    Feature.avx,
                    Feature.avx2,
                });
            },

            else => return error.UnsupportedArch,
        },
    });
}

pub fn build(b: *std.Build) !void {
    const cpu_arch = b.option(std.Target.Cpu.Arch, "arch", "The target cpu architecture (default is x86_64)") orelse .x86_64;

    const kernel_target = try getTarget(b, cpu_arch, .kernel);

    const kernel_optimize = b.standardOptimizeOption(.{});

    const limine = b.dependency("limine", .{});
    const limine_raw = b.dependency("limine_raw", .{});

    const kernel_exe = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = kernel_target,
        .optimize = kernel_optimize,
        .code_model = .kernel,
        .pic = true,
    });

    {
        kernel_exe.root_module.addImport("limine", limine.module("limine"));

        switch (cpu_arch) {
            .x86_64 => kernel_exe.setLinkerScript(b.path("src/kernel/arch/x86_64/linker.ld")),

            else => return error.UnsupportedArch,
        }

        // Disable LTO. This prevents issues with limine requests
        kernel_exe.want_lto = false;

        b.installArtifact(kernel_exe);
    }

    {
        const initrd_tree = b.addWriteFiles();

        {
            const user_apps = try b.build_root.handle.openDir("src/user/apps", .{ .iterate = true });

            const user_apps_target = try getTarget(b, cpu_arch, .user);

            const yos_module = b.createModule(.{
                .root_source_file = b.path("src/user/yos.zig"),
                .target = user_apps_target,
                .optimize = .ReleaseSmall,
            });

            var user_app_iterator = user_apps.iterate();

            while (try user_app_iterator.next()) |user_app| {
                const user_app_exe = b.addExecutable(.{
                    .name = user_app.name,
                    .root_source_file = b.path(b.fmt("src/user/apps/{s}/main.zig", .{user_app.name})),
                    .target = user_apps_target,
                    .optimize = .ReleaseSmall,
                });

                user_app_exe.root_module.addImport("yos", yos_module);

                switch (cpu_arch) {
                    .x86_64 => user_app_exe.setLinkerScript(b.path("src/user/arch/x86_64/linker.ld")),

                    else => return error.UnsupportedArch,
                }

                _ = initrd_tree.addCopyFile(user_app_exe.getEmittedBin(), b.fmt("usr/bin/{s}", .{user_app.name}));
            }
        }

        const tar_compress = b.addSystemCommand(&.{ "tar", "-chRf" });

        const initrd_output = tar_compress.addOutputFileArg("initrd");

        tar_compress.addArg("-C");

        tar_compress.addDirectoryArg(initrd_tree.getDirectory());

        tar_compress.addArg(".");

        tar_compress.step.dependOn(&initrd_tree.step);

        const initrd_step = b.step("initrd", "Bundle the initial ramdisk");
        initrd_step.dependOn(&b.addInstallBinFile(initrd_output, "initrd").step);

        const iso_tree = b.addWriteFiles();

        _ = iso_tree.addCopyFile(kernel_exe.getEmittedBin(), "boot/kernel");

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

        switch (cpu_arch) {
            .x86_64 => {
                const core_count = b.option(u64, "core-count", "The amount of cores to use in QEMU (default is 1)") orelse 1;
                const wait_gdb = b.option(bool, "gdb", "Wait for GDB to connect to port :1234 (default is false)") orelse false;

                const qemu = b.addSystemCommand(&.{"qemu-system-x86_64"});

                qemu.addArgs(&.{ "-M", "q35" });
                qemu.addArgs(&.{ "-m", "256M" });
                qemu.addArgs(&.{"-cdrom"});
                qemu.addFileArg(iso_output);
                qemu.addArgs(&.{ "-boot", "d" });
                qemu.addArgs(&.{ "-smp", b.fmt("{}", .{core_count}) });
                if (wait_gdb) qemu.addArgs(&.{ "-s", "-S" });

                qemu.step.dependOn(&limine_bios_install.step);

                const run_step = b.step("run", "Run the bundled ISO in QEMU");

                run_step.dependOn(&qemu.step);
            },

            else => return error.UnsupportedArch,
        }
    }

    {
        const kernel_check = b.addExecutable(.{
            .name = "kernel",
            .root_source_file = b.path("src/kernel/main.zig"),
            .target = kernel_target,
            .optimize = kernel_optimize,
            .code_model = .kernel,
            .pic = true,
        });

        kernel_check.root_module.addImport("limine", limine.module("limine"));

        const check_step = b.step("check", "Checks if the kernel can compile");

        check_step.dependOn(&kernel_check.step);
    }
}
