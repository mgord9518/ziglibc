const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");
const libcbuild = @import("ziglibcbuild.zig");
const luabuild = @import("luabuild.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const zig_start = libcbuild.addZigStart(b);
    zig_start.setTarget(target);
    zig_start.setBuildMode(mode);

    const zig_libc = libcbuild.addZigLibc(b, .{
        .link = .static,
    });
    zig_libc.setTarget(target);
    zig_libc.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");

    {
        const exe = b.addExecutable("hello", "test" ++ std.fs.path.sep_str ++ "hello.c");
        exe.addIncludePath("inc");
        exe.linkLibrary(zig_libc);
        exe.linkLibrary(zig_start);
        exe.setTarget(target);
        exe.setBuildMode(mode);

        const run_step = exe.run();
        run_step.stdout_action = .{
            .expect_exact = "Hello\n",
        };
        test_step.dependOn(&run_step.step);
    }

    _ = addLua(b, target, mode, zig_libc, zig_start);
}

fn addLua(
    b: *std.build.Builder,
    target: anytype,
    mode: anytype,
    zig_libc: *std.build.LibExeObjStep,
    zig_start: *std.build.LibExeObjStep,
) *std.build.LibExeObjStep {
    const lua_repo = GitRepoStep.create(b, .{
        .url = "https://github.com/lua/lua",
        .sha = "5d708c3f9cae12820e415d4f89c9eacbe2ab964b",
        .branch = "v5.4.4",
    });
    const lua_exe = b.addExecutable("lua", null);
    lua_exe.setTarget(target);
    lua_exe.setBuildMode(mode);
    lua_exe.step.dependOn(&lua_repo.step);
    const lua_repo_path = lua_repo.getPath(&lua_exe.step);
    var files = std.ArrayList([]const u8).init(b.allocator);
    files.append(b.pathJoin(&.{lua_repo_path, "lua.c"})) catch unreachable;
    inline for (luabuild.core_objects) |obj| {
        files.append(b.pathJoin(&.{lua_repo_path, obj ++ ".c"})) catch unreachable;
    }
    inline for (luabuild.aux_objects) |obj| {
        files.append(b.pathJoin(&.{lua_repo_path, obj ++ ".c"})) catch unreachable;
    }
    inline for (luabuild.lib_objects) |obj| {
        files.append(b.pathJoin(&.{lua_repo_path, obj ++ ".c"})) catch unreachable;
    }

    lua_exe.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
        "-std=c99",
    });

    lua_exe.addIncludePath("inc");
    lua_exe.linkLibrary(zig_libc);
    lua_exe.linkLibrary(zig_start);

    const step = b.step("lua", "build the LUA interpreter");
    step.dependOn(&lua_exe.step);

    return lua_exe;
}