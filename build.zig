const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_cpu = b.addStaticLibrary(.{
        .name = "cpu_features",
        .target = target,
        .optimize = optimize,
    });
    lib_cpu.addIncludePath("include");
    lib_cpu.addIncludePath("incude/internal");
    lib_cpu.addCSourceFiles(&.{
        "src/filesystem.c",
        "src/stack_line_reader.c",
        "src/string_view.c",
        switch (target.getCpuArch()) {
            .aarch64_32 => "src/impl_arm_linux_or_android.c",
            .aarch64 => switch (target.getOsTag()) {
                .windows => "src/impl_aarch64_windows.c",
                .macos => @panic("unavaliable"),
                else => "src/impl_aarch64_linux_or_android.c",
            },
            .x86, .x86_64 => switch (target.getOsTag()) {
                .windows => "src/impl_x86_windows.c",
                .macos => "src/impl_x86_macos.c",
                .linux => "src/impl_x86_linux_or_android.c",
                else => "src/impl_x86_freebsd.c",
            },
            .mips, .mipsel => "src/impl_mips_linux_or_android.c",
            .powerpc, .powerpc64 => "src/impl_ppc_linux.c",
            .riscv64 => "src/impl_riscv_linux.c",
            else => @panic("Unknown archtecture"),
        },
    }, cflags);
    if (target.isLinux()) {
        lib_cpu.addCSourceFile("src/hwcaps.c", cflags);
        lib_cpu.defineCMacro("HAVE_STRONG_GETAUXVAL", null);
    }
    if (target.isDarwin()) lib_cpu.defineCMacro("HAVE_SYSCTLBYNAME", null);

    lib_cpu.linkLibC();
    lib_cpu.pie = b.option(bool, "pie", "Build library with Position Independent Executable") orelse true;
    lib_cpu.bundle_compiler_rt = b.option(bool, "compiler_rt", "Build Library with Compiler_rt") orelse true;

    lib_cpu.installHeadersDirectory("include", "");
    b.installArtifact(lib_cpu);

    buildExe(b, .{
        .path = "src/utils/list_cpu_features.c",
        .lib = lib_cpu,
    });
}
fn buildExe(b: *std.Build, properties: BuildInfo) void {
    const exe = b.addExecutable(.{
        .name = properties.filename(),
        .target = properties.lib.target,
        .optimize = properties.lib.optimize,
    });
    for (properties.lib.include_dirs.items) |dir| {
        exe.include_dirs.append(dir) catch {};
    }
    exe.addCSourceFile(properties.path, cflags);
    exe.linkLibrary(properties.lib);
    exe.linkLibC();

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step(properties.filename(), b.fmt("Run the {s} app", .{properties.filename()}));
    run_step.dependOn(&run_cmd.step);
}

const BuildInfo = struct {
    lib: *std.Build.Step.Compile,
    path: []const u8,

    fn filename(self: BuildInfo) []const u8 {
        var split = std.mem.split(u8, std.fs.path.basename(self.path), ".");
        return split.first();
    }
};

const cflags = &.{
    "-std=gnu99",
    "-Wall",
    "-Wextra",
    "-Wmissing-declarations",
    "-Wmissing-prototypes",
    "-Wno-implicit-fallthrough",
    "-Wno-unused-function",
    "-Wold-style-definition",
    "-Wshadow",
    "-Wsign-compare",
    "-Wstrict-prototypes",
    "-fno-sanitize=all",
    "-DSTACK_LINE_READER_BUFFER_SIZE=1024",
};
