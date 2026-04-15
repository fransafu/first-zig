const std = @import("std");

const Vec2D = struct {
    x: i32,
    y: i32,

    const Self = @This();

    fn init(x: i32, y: i32) Self {
        return .{ .x = x, .y = y };
    }

    fn add(self: Self, vector: Self) Self {
        return .{
            .x = self.x + vector.x,
            .y = self.y + vector.y,
        };
    }

    fn scale(self: Self, factor: i32) Self {
        return .{
            .x = self.x * factor,
            .y = self.y * factor,
        };
    }

    fn magnitude(self: Self) f64 {
        const x: f64 = @floatFromInt(self.x);
        const y: f64 = @floatFromInt(self.y);
        return @sqrt(x * x + y * y);
    }

    pub fn format(self: Self, writer: anytype) !void {
        try writer.print("Vec2D({}, {})", .{ self.x, self.y });
    }
};

/// Problem Statement
///
/// A Drone starts at the origin (0, 0) in a 2D plane
///
/// First, it moves according to the vector a = (3, -2)
/// Then, it moves according to the vector b = (-1, 4)
/// Finally, it moves in a direction oposite to a, but twice its magnitude
///
/// start at: (0, 0)
/// step 2: (0, 0) + a = (3, -2) => (3, -2)
/// step 3: (3, -2) + b = (-1, 4) => (2, 2)
/// step 4: (2, 2) + (-2a) = (2, 2) + (-6, 4) => (-4, 6)
/// final position: (-4, 6)
/// So the distance from the origin is: sqrt((-4)^2 + 6^2) = sqrt(16 + 36) = sqrt(52)

pub fn main() void {
    const a = Vec2D.init(3, -2);
    const b = Vec2D.init(-1, 4);

    const start = Vec2D.init(0, 0);
    std.debug.print("a = {f}\n", .{a});
    std.debug.print("b = {f}\n", .{b});
    std.debug.print("\n", .{});

    const step2 = start.add(a);
    std.debug.print("start = {f}\n", .{start});
    std.debug.print("start + a = {f}\n", .{step2});

    const step3 = step2.add(b);
    std.debug.print("step2 + b = {f}\n", .{step3});

    const neg2a = a.scale(-2);
    const step4 = step3.add(neg2a);
    std.debug.print("-2a = {f}\n", .{neg2a});
    std.debug.print("step3 + (-2a) = {f}\n", .{step4});
    std.debug.print("\n", .{});

    std.debug.print("final position = {f}\n", .{step4});
    std.debug.print("distance to origin = {d:.4}\n", .{step4.magnitude()});
}
