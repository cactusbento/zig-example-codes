const std = @import("std");

/// Almost PHP trait
///
/// Does not have:
/// * Regular Properties,
/// * Properties are global,
/// * Direct Abstract Trait Members, but...
///
/// https://www.php.net/manual/en/language.oop5.traits.php
pub const trait = opaque {
    /// Static property.
    ///
    /// Only accessable via getter and setters.
    ///
    /// Compile Error if accessed directly as field. [zls pls fix]
    pub var static_text: []const u8 = "What sorcery is this?";

    /// Kinda has Abstract Trait Members using anytype comptime polymorphism.
    ///
    /// Here, applied is checked if it has the text member.
    pub fn wtf_is_this(applied: anytype) []const u8 {
        return applied.text;
    }
};

pub const trait_user = struct {
    pub usingnamespace trait;

    text: []const u8 = "WTF?",
};

test "PHP Trait" {
    const php_man: trait_user = .{};

    try std.testing.expectEqualStrings("WTF?", php_man.wtf_is_this());
}

/// ----------
/// Interfaces
/// ----------
const Point = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn move(self: *Point, dx: i32, dy: i32) void {
        self.x += dx;
        self.y += dy;
    }
};

const Circle = struct {
    center: Point = .{},
    radius: u32 = 0,

    pub fn move(self: *Circle, dx: i32, dy: i32) void {
        self.center.move(dx, dy);
    }

    pub fn resize(self: *Circle, radius: u32) void {
        self.radius = radius;
    }
};

const Shape1 = union(enum) {
    point: Point,
    circle: Circle,

    pub fn move(self: *Shape1, dx: i32, dy: i32) void {
        switch (self.*) {
            inline else => |*s| s.move(dx, dy),
        }
    }
};

test "Interface: Tagged Union" {
    var shapes = [_]Shape1{
        .{ .point = Point{} },
        .{ .circle = Circle{} },
    };

    for (&shapes) |*s| {
        s.move(1, 0);

        try std.testing.expect(1 == switch (s.*) {
            .circle => |sh| sh.center.x,
            .point => |sh| sh.x,
        });

        try std.testing.expect(0 == switch (s.*) {
            .circle => |sh| sh.center.y,
            .point => |sh| sh.y,
        });
    }
}

const Shape2 = struct {
    ptr: *anyopaque,
    vtab: *const VTab,

    const VTab = struct {
        move: *const fn (ptr: *anyopaque, dx: i32, dy: i32) void,
    };

    pub fn init(obj: anytype) Shape2 {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);

        std.debug.assert(PtrInfo == .Pointer);
        std.debug.assert(PtrInfo.Pointer.size == .One);

        const impl = struct {
            fn move(ptr: *anyopaque, dx: i32, dy: i32) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                self.move(dx, dy);
            }
        };

        return .{
            .ptr = @constCast(@ptrCast(obj)),
            .vtab = &VTab{
                .move = impl.move,
            },
        };
    }

    pub fn move(self: *Shape2, dx: i32, dy: i32) void {
        self.vtab.move(self.ptr, dx, dy);
    }
};

test "Interface: VTab" {
    var p = Point{};
    var c = Circle{};
    var shapes = [_]Shape2{
        Shape2.init(&p),
        Shape2.init(&c),
    };

    for (&shapes) |*s| {
        s.move(1, 0);
    }
}

const Shape3 = struct {
    ptr: *anyopaque,
    moveFn: *const fn (*anyopaque, i32, i32) void,

    pub fn init(ptr: anytype) Shape3 {
        const Ptr = @TypeOf(ptr);
        const PtrInfo = @typeInfo(Ptr);

        std.debug.assert(PtrInfo == .Pointer);
        std.debug.assert(PtrInfo.Pointer.size == .One);

        const impl = struct {
            pub fn moveImpl(pointer: *anyopaque, dx: i32, dy: i32) void {
                const self: Ptr = @ptrCast(@alignCast(pointer));
                @call(
                    std.builtin.CallModifier.always_inline,
                    PtrInfo.Pointer.child.move,
                    .{ self, dx, dy },
                );
            }
        };

        return .{
            .ptr = ptr,
            .moveFn = impl.moveImpl,
        };
    }

    pub inline fn move(self: *Shape3, dx: i32, dy: i32) void {
        self.moveFn(self.ptr, dx, dy);
    }
};

test "Interface: Inline VTab" {
    var p = Point{};
    var c = Circle{};
    var shapes = [_]Shape3{
        Shape3.init(&p),
        Shape3.init(&c),
    };

    for (&shapes) |*s| {
        s.move(1, 0);
    }
}

const Shape4 = struct {
    moveFn: *const fn (ptr: *Shape4, dx: i32, dy: i32) void,

    pub fn move(self: *Shape4, dx: i32, dy: i32) void {
        self.moveFn(self, dx, dy);
    }
};

const Point4 = struct {
    x: i32 = 0,
    y: i32 = 0,
    shape: Shape4 = .{ .moveFn = move },

    pub fn move(ptr: *Shape4, dx: i32, dy: i32) void {
        const self = @fieldParentPtr(Point4, "shape", ptr);
        self.x += dx;
        self.y += dy;
    }
};

const Circle4 = struct {
    center: Point = .{},
    radius: u32 = 0,
    shape: Shape4 = .{ .moveFn = move },

    pub fn move(ptr: *Shape4, dx: i32, dy: i32) void {
        const self = @fieldParentPtr(Circle4, "shape", ptr);
        self.center.move(dx, dy);
    }

    pub fn resize(self: *Circle, radius: u32) void {
        self.radius = radius;
    }
};

test "Interface: Embedded VTab" {
    var p = Point4{};
    var c = Circle4{};
    var shapes = [_]*Shape4{
        &p.shape,
        &c.shape,
    };

    for (shapes) |s| {
        s.move(1, 0);
    }
}
