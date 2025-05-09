const std = @import("std");

pub fn main() anyerror!void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("found memory leaks");
    const allocator = gpa.allocator();

    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();
    _ = it.next() orelse unreachable; // skip binary name
    const child_exe_path = it.next() orelse unreachable;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer tmp.parent_dir.setAsCwd() catch {};

    var buf = try std.ArrayList(u8).initCapacity(allocator, 128);
    defer buf.deinit();
    try buf.appendSlice("@echo off\n");
    try buf.append('"');
    try buf.appendSlice(child_exe_path);
    try buf.append('"');
    const preamble_len = buf.items.len;

    try buf.appendSlice(" %*");
    try tmp.dir.writeFile(.{ .sub_path = "args1.bat", .data = buf.items });
    buf.shrinkRetainingCapacity(preamble_len);

    try buf.appendSlice(" %1 %2 %3 %4 %5 %6 %7 %8 %9");
    try tmp.dir.writeFile(.{ .sub_path = "args2.bat", .data = buf.items });
    buf.shrinkRetainingCapacity(preamble_len);

    try buf.appendSlice(" \"%~1\" \"%~2\" \"%~3\" \"%~4\" \"%~5\" \"%~6\" \"%~7\" \"%~8\" \"%~9\"");
    try tmp.dir.writeFile(.{ .sub_path = "args3.bat", .data = buf.items });
    buf.shrinkRetainingCapacity(preamble_len);

    // Test cases are from https://github.com/rust-lang/rust/blob/master/tests/ui/std/windows-bat-args.rs
    try testExecError(error.InvalidBatchScriptArg, allocator, &.{"\x00"});
    try testExecError(error.InvalidBatchScriptArg, allocator, &.{"\n"});
    try testExecError(error.InvalidBatchScriptArg, allocator, &.{"\r"});
    try testExec(allocator, &.{ "a", "b" }, null);
    try testExec(allocator, &.{ "c is for cat", "d is for dog" }, null);
    try testExec(allocator, &.{ "\"", " \"" }, null);
    try testExec(allocator, &.{ "\\", "\\" }, null);
    try testExec(allocator, &.{">file.txt"}, null);
    try testExec(allocator, &.{"whoami.exe"}, null);
    try testExec(allocator, &.{"&a.exe"}, null);
    try testExec(allocator, &.{"&echo hello "}, null);
    try testExec(allocator, &.{ "&echo hello", "&whoami", ">file.txt" }, null);
    try testExec(allocator, &.{"!TMP!"}, null);
    try testExec(allocator, &.{"key=value"}, null);
    try testExec(allocator, &.{"\"key=value\""}, null);
    try testExec(allocator, &.{"key = value"}, null);
    try testExec(allocator, &.{"key=[\"value\"]"}, null);
    try testExec(allocator, &.{ "", "a=b" }, null);
    try testExec(allocator, &.{"key=\"foo bar\""}, null);
    try testExec(allocator, &.{"key=[\"my_value]"}, null);
    try testExec(allocator, &.{"key=[\"my_value\",\"other-value\"]"}, null);
    try testExec(allocator, &.{"key\\=value"}, null);
    try testExec(allocator, &.{"key=\"&whoami\""}, null);
    try testExec(allocator, &.{"key=\"value\"=5"}, null);
    try testExec(allocator, &.{"key=[\">file.txt\"]"}, null);
    try testExec(allocator, &.{"%hello"}, null);
    try testExec(allocator, &.{"%PATH%"}, null);
    try testExec(allocator, &.{"%%cd:~,%"}, null);
    try testExec(allocator, &.{"%PATH%PATH%"}, null);
    try testExec(allocator, &.{"\">file.txt"}, null);
    try testExec(allocator, &.{"abc\"&echo hello"}, null);
    try testExec(allocator, &.{"123\">file.txt"}, null);
    try testExec(allocator, &.{"\"&echo hello&whoami.exe"}, null);
    try testExec(allocator, &.{ "\"hello^\"world\"", "hello &echo oh no >file.txt" }, null);
    try testExec(allocator, &.{"&whoami.exe"}, null);

    // Ensure that trailing space and . characters can't lead to unexpected bat/cmd script execution.
    // In many Windows APIs (including CreateProcess), trailing space and . characters are stripped
    // from paths, so if a path with trailing . and space character(s) is passed directly to
    // CreateProcess, then it could end up executing a batch/cmd script that naive extension detection
    // would not flag as .bat/.cmd.
    //
    // Note that we expect an error here, though, which *is* a valid mitigation, but also an implementation detail.
    // This error is caused by the use of a wildcard with NtQueryDirectoryFile to optimize PATHEXT searching. That is,
    // the trailing characters in the app name will lead to a FileNotFound error as the wildcard-appended path will not
    // match any real paths on the filesystem (e.g. `foo.bat .. *` will not match `foo.bat`; only `foo.bat*` will).
    //
    // This being an error matches the behavior of running a command via the command line of cmd.exe, too:
    //
    //     > "args1.bat .. "
    //     '"args1.bat .. "' is not recognized as an internal or external command,
    //     operable program or batch file.
    try std.testing.expectError(error.FileNotFound, testExecBat(allocator, "args1.bat .. ", &.{"abc"}, null));
    const absolute_with_trailing = blk: {
        const absolute_path = try std.fs.realpathAlloc(allocator, "args1.bat");
        defer allocator.free(absolute_path);
        break :blk try std.mem.concat(allocator, u8, &.{ absolute_path, " .. " });
    };
    defer allocator.free(absolute_with_trailing);
    try std.testing.expectError(error.FileNotFound, testExecBat(allocator, absolute_with_trailing, &.{"abc"}, null));

    var env = env: {
        var env = try std.process.getEnvMap(allocator);
        errdefer env.deinit();
        // No escaping
        try env.put("FOO", "123");
        // Some possible escaping of %FOO% that could be expanded
        // when escaping cmd.exe meta characters with ^
        try env.put("FOO^", "123"); // only escaping %
        try env.put("^F^O^O^", "123"); // escaping every char
        break :env env;
    };
    defer env.deinit();
    try testExec(allocator, &.{"%FOO%"}, &env);

    // Ensure that none of the `>file.txt`s have caused file.txt to be created
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("file.txt", .{}));
}

fn testExecError(err: anyerror, allocator: std.mem.Allocator, args: []const []const u8) !void {
    return std.testing.expectError(err, testExec(allocator, args, null));
}

fn testExec(allocator: std.mem.Allocator, args: []const []const u8, env: ?*std.process.EnvMap) !void {
    try testExecBat(allocator, "args1.bat", args, env);
    try testExecBat(allocator, "args2.bat", args, env);
    try testExecBat(allocator, "args3.bat", args, env);
}

fn testExecBat(allocator: std.mem.Allocator, bat: []const u8, args: []const []const u8, env: ?*std.process.EnvMap) !void {
    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 1 + args.len);
    defer argv.deinit();
    argv.appendAssumeCapacity(bat);
    argv.appendSliceAssumeCapacity(args);

    const can_have_trailing_empty_args = std.mem.eql(u8, bat, "args3.bat");

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .env_map = env,
        .argv = argv.items,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqualStrings("", result.stderr);
    var it = std.mem.splitScalar(u8, result.stdout, '\x00');
    var i: usize = 0;
    while (it.next()) |actual_arg| {
        if (i >= args.len and can_have_trailing_empty_args) {
            try std.testing.expectEqualStrings("", actual_arg);
            continue;
        }
        const expected_arg = args[i];
        try std.testing.expectEqualStrings(expected_arg, actual_arg);
        i += 1;
    }
}
