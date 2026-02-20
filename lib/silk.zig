const std = @import("std");

pub const UserHandler = *const fn (ctx: *anyopaque, args: std.json.Value) anyerror!std.json.Value;

pub const RegisterFn = *const fn (ctx: *anyopaque, cmd: []const u8, handler: UserHandler) anyerror!void;

pub const Host = struct {
    ctx: *anyopaque,
    register_fn: RegisterFn,

    pub fn init(ctx: *anyopaque, register_fn: RegisterFn) Host {
        return .{
            .ctx = ctx,
            .register_fn = register_fn,
        };
    }

    pub fn register(self: *Host, cmd: []const u8, handler: UserHandler) !void {
        try self.register_fn(self.ctx, cmd, handler);
    }
};

pub fn registerUserModule(host: *Host, comptime UserModule: type) !void {
    comptime validateUserModule(UserModule);
    try UserModule.register(host);
}

pub fn expectObject(args: std.json.Value) !std.json.ObjectMap {
    return switch (args) {
        .object => |obj| obj,
        else => error.InvalidArgs,
    };
}

pub fn getString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = obj.get(key) orelse return error.MissingArg;
    return switch (value) {
        .string => |s| s,
        else => error.InvalidArgType,
    };
}

pub fn getOptionalString(obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .null => null,
        .string => |s| s,
        else => error.InvalidArgType,
    };
}

fn validateUserModule(comptime UserModule: type) void {
    if (!@hasDecl(UserModule, "register")) {
        @compileError("User module must define `pub fn register(host: *silk.Host) !void`.");
    }

    const fn_info = switch (@typeInfo(@TypeOf(UserModule.register))) {
        .@"fn" => |info| info,
        else => @compileError("User module `register` must be a function."),
    };

    if (fn_info.params.len != 1) {
        @compileError("User module `register` must take exactly one parameter: `*silk.Host`.");
    }

    if (fn_info.params[0].type != *Host) {
        @compileError("User module `register` parameter must be `*silk.Host`.");
    }

    const return_type = fn_info.return_type orelse {
        @compileError("User module `register` must return `!void`.");
    };

    const ret_info = @typeInfo(return_type);
    if (ret_info != .error_union or ret_info.error_union.payload != void) {
        @compileError("User module `register` must return `!void`.");
    }
}
