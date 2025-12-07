// NOTE: This CSS detector was built following the spec at https://www.w3.org/TR/CSS22/syndata.html#comments

const std = @import("std");
const Allocator = std.mem.Allocator;

/// CSS comment with its location information
pub const Comment = struct {
    start: usize, // Start position in the source text
    end: usize, // End position in the source text (inclusive)
    line: usize, // Line number where comment starts
    column: usize, // Column number where comment starts
    content: []const u8, // The full comment text including /* */
};

/// Count the total number of CSS comments in the text
pub inline fn countComments(css: []const u8) usize {
    var pos: usize = 0;
    var count: usize = 0;

    while (pos < css.len) {
        const start_opt = std.mem.indexOfPos(u8, css, pos, "/*");
        if (start_opt == null) break;
        const start = start_opt.?;

        const end_opt = std.mem.indexOfPos(u8, css, start + 2, "*/");
        if (end_opt == null) break;
        const end = end_opt.?;

        count += 1;
        pos = end + 2;
    }

    return count;
}

/// Remove all CSS comments from the input text
pub inline fn removeComments(allocator: Allocator, css: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var pos: usize = 0;

    while (pos < css.len) {
        const start_opt = std.mem.indexOfPos(u8, css, pos, "/*");

        if (start_opt) |start| {
            try result.appendSlice(allocator, css[pos..start]);

            const end_opt = std.mem.indexOfPos(u8, css, start + 2, "*/");
            if (end_opt) |end| {
                pos = end + 2;
            } else {
                break;
            }
        } else {
            try result.appendSlice(allocator, css[pos..]);
            break;
        }
    }

    return result.toOwnedSlice(allocator);
}

test "countComments - no comments" {
    const css = "body { color: red; }";
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "countComments - single comment" {
    const css = "/* comment */ body { color: red; }";
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "countComments - multiple comments" {
    const css =
        \\/* comment 1 */
        \\body { color: red; }
        \\/* comment 2 */
        \\div { margin: 0; }
        \\/* comment 3 */
    ;
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "countComments - multiline comment" {
    const css =
        \\/* This is a
        \\   multiline
        \\   comment */
        \\body { color: red; }
    ;
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "countComments - adjacent comments" {
    const css = "/* comment 1 *//* comment 2 *//* comment 3 */";
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "countComments - comment with special characters" {
    const css = "/* Comment with / and * inside */ body {}";
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "countComments - comment before semicolon" {
    const css = "content: var(--bs-breadcrumb-div, " / ") /* rtl: var(--bs-breadcrumb-div, " / ") */;";
    const count = countComments(css);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "removeComments - no comments" {
    const allocator = std.testing.allocator;
    const css = "body { color: red; }";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(css, result);
}

test "removeComments - single comment at start" {
    const allocator = std.testing.allocator;
    const css = "/* header comment */body { color: red; }";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("body { color: red; }", result);
}

test "removeComments - single comment at end" {
    const allocator = std.testing.allocator;
    const css = "body { color: red; }/* footer comment */";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("body { color: red; }", result);
}

test "removeComments - single comment in middle" {
    const allocator = std.testing.allocator;
    const css = "body { /* inline comment */ color: red; }";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("body {  color: red; }", result);
}

test "removeComments - multiple comments" {
    const allocator = std.testing.allocator;
    const css =
        \\/* comment 1 */
        \\body { color: red; }
        \\/* comment 2 */
        \\div { margin: 0; }
        \\/* comment 3 */
    ;
    const expected =
        \\
        \\body { color: red; }
        \\
        \\div { margin: 0; }
        \\
    ;
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "removeComments - adjacent comments" {
    const allocator = std.testing.allocator;
    const css = "/* comment 1 *//* comment 2 *//* comment 3 */body {}";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("body {}", result);
}

test "removeComments - multiline comment" {
    const allocator = std.testing.allocator;
    const css =
        \\/* This is a
        \\   multiline
        \\   comment */
        \\body { color: red; }
    ;
    const expected =
        \\
        \\body { color: red; }
    ;
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "removeComments - comment with special characters" {
    const allocator = std.testing.allocator;
    const css = "/* Comment with / and * inside */ body {}";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(" body {}", result);
}

test "removeComments - preserves content between comments" {
    const allocator = std.testing.allocator;
    const css = "a/* c1 */b/* c2 */c/* c3 */d";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("abcd", result);
}

test "removeComments - real world example" {
    const allocator = std.testing.allocator;
    const css =
        \\/* Open Sans Font */
        \\@font-face {
        \\  font-family: 'Open Sans';
        \\  /* This is a comment inside */
        \\  src: url('../fonts/open-sans.woff2') format('woff2');
        \\}
        \\/* End of file */
    ;
    const expected =
        \\
        \\@font-face {
        \\  font-family: 'Open Sans';
        \\
        \\  src: url('../fonts/open-sans.woff2') format('woff2');
        \\}
        \\
    ;
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "removeComments - unclosed comment" {
    const allocator = std.testing.allocator;
    const css = "body { color: red; } /* unclosed comment";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("body { color: red; } ", result);
}

test "removeComments - empty input" {
    const allocator = std.testing.allocator;
    const css = "";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "removeComments - only comment" {
    const allocator = std.testing.allocator;
    const css = "/* just a comment */";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "removeComments - comment before semicolon" {
    const allocator = std.testing.allocator;
    const css = "content: var(--bs-breadcrumb-div, " / ") /* rtl: var(--bs-breadcrumb-div, " / ") */;";
    const expected = "content: var(--bs-breadcrumb-div, " / ") ;";
    const result = try removeComments(allocator, css);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}
