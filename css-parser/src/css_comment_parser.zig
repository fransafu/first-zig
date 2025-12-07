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

/// Detect all line numbers that contain CSS comments
pub inline fn detectLinesWithComments(allocator: Allocator, css: []const u8) ![]usize {
    var lines: std.ArrayList(usize) = .{};
    errdefer lines.deinit(allocator);

    var pos: usize = 0;

    while (pos < css.len) {
        const start_opt = std.mem.indexOfPos(u8, css, pos, "/*");
        if (start_opt == null) break;
        const start = start_opt.?;

        const end_opt = std.mem.indexOfPos(u8, css, start + 2, "*/");
        if (end_opt == null) break;
        const end = end_opt.?;

        const start_line = getLineNumber(css, start);
        const end_line = getLineNumber(css, end + 2);

        var line = start_line;
        while (line <= end_line) : (line += 1) {
            // only if not in the list
            if (lines.items.len == 0 or lines.items[lines.items.len - 1] != line) {
                try lines.append(allocator, line);
            }
        }

        pos = end + 2;
    }

    return lines.toOwnedSlice(allocator);
}

/// Get all CSS comments with their location information
pub inline fn getAllComments(allocator: Allocator, css: []const u8) ![]Comment {
    var comments: std.ArrayList(Comment) = .{};
    errdefer {
        for (comments.items) |comment| {
            allocator.free(comment.content);
        }
        comments.deinit(allocator);
    }

    var pos: usize = 0;

    while (pos < css.len) {
        const start_opt = std.mem.indexOfPos(u8, css, pos, "/*");
        if (start_opt == null) break;
        const start = start_opt.?;

        const end_opt = std.mem.indexOfPos(u8, css, start + 2, "*/");
        if (end_opt == null) break;
        const end = end_opt.?;

        const comment_text = css[start .. end + 2];
        const comment_copy = try allocator.dupe(u8, comment_text);

        const line = getLineNumber(css, start);
        const column = getColumnNumber(css, start);

        try comments.append(allocator, Comment{
            .start = start,
            .end = end + 1, // Note: end + 1 to include the last '/'
            .line = line,
            .column = column,
            .content = comment_copy,
        });

        pos = end + 2;
    }

    return comments.toOwnedSlice(allocator);
}

/// Helper function to calculate line number
fn getLineNumber(text: []const u8, pos: usize) usize {
    var line: usize = 1;
    var i: usize = 0;
    while (i < pos and i < text.len) : (i += 1) {
        if (text[i] == '\n') line += 1;
    }
    return line;
}

/// Helper function to calculate column number
fn getColumnNumber(text: []const u8, pos: usize) usize {
    var column: usize = 1;
    var i: usize = pos;
    while (i > 0) {
        i -= 1;
        if (text[i] == '\n') break;
        column += 1;
    }
    return column;
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

test "detectLinesWithComments - no comments" {
    const allocator = std.testing.allocator;
    const css = "body { color: red; }";
    const lines = try detectLinesWithComments(allocator, css);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 0), lines.len);
}

test "detectLinesWithComments - single line comment" {
    const allocator = std.testing.allocator;
    const css =
        \\body { color: red; }
        \\/* comment on line 2 */
        \\div { margin: 0; }
    ;
    const lines = try detectLinesWithComments(allocator, css);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 1), lines.len);
    try std.testing.expectEqual(@as(usize, 2), lines[0]);
}

test "detectLinesWithComments - multiline comment" {
    const allocator = std.testing.allocator;
    const css =
        \\body { color: red; }
        \\/* This comment
        \\   spans multiple
        \\   lines */
        \\div { margin: 0; }
    ;
    const lines = try detectLinesWithComments(allocator, css);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqual(@as(usize, 2), lines[0]);
    try std.testing.expectEqual(@as(usize, 3), lines[1]);
    try std.testing.expectEqual(@as(usize, 4), lines[2]);
}

test "detectLinesWithComments - multiple comments on different lines" {
    const allocator = std.testing.allocator;
    const css =
        \\/* comment 1 */
        \\body { color: red; }
        \\/* comment 2 */
        \\div { margin: 0; }
    ;
    const lines = try detectLinesWithComments(allocator, css);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 2), lines.len);
    try std.testing.expectEqual(@as(usize, 1), lines[0]);
    try std.testing.expectEqual(@as(usize, 3), lines[1]);
}

test "getAllComments - no comments" {
    const allocator = std.testing.allocator;
    const css = "body { color: red; }";
    const comments = try getAllComments(allocator, css);
    defer {
        for (comments) |comment| {
            allocator.free(comment.content);
        }
        allocator.free(comments);
    }

    try std.testing.expectEqual(@as(usize, 0), comments.len);
}

test "getAllComments - single comment" {
    const allocator = std.testing.allocator;
    const css = "/* test comment */ body {}";
    const comments = try getAllComments(allocator, css);
    defer {
        for (comments) |comment| {
            allocator.free(comment.content);
        }
        allocator.free(comments);
    }

    try std.testing.expectEqual(@as(usize, 1), comments.len);
    try std.testing.expectEqualStrings("/* test comment */", comments[0].content);
    try std.testing.expectEqual(@as(usize, 0), comments[0].start);
    try std.testing.expectEqual(@as(usize, 17), comments[0].end);
    try std.testing.expectEqual(@as(usize, 1), comments[0].line);
    try std.testing.expectEqual(@as(usize, 1), comments[0].column);
}

test "getAllComments - multiple comments with positions" {
    const allocator = std.testing.allocator;
    const css =
        \\/* comment 1 */
        \\body { color: red; }
        \\/* comment 2 */
    ;
    const comments = try getAllComments(allocator, css);
    defer {
        for (comments) |comment| {
            allocator.free(comment.content);
        }
        allocator.free(comments);
    }

    try std.testing.expectEqual(@as(usize, 2), comments.len);

    // First comment
    try std.testing.expectEqualStrings("/* comment 1 */", comments[0].content);
    try std.testing.expectEqual(@as(usize, 1), comments[0].line);
    try std.testing.expectEqual(@as(usize, 1), comments[0].column);

    // Second comment
    try std.testing.expectEqualStrings("/* comment 2 */", comments[1].content);
    try std.testing.expectEqual(@as(usize, 3), comments[1].line);
    try std.testing.expectEqual(@as(usize, 1), comments[1].column);
}

test "getAllComments - comment with column offset" {
    const allocator = std.testing.allocator;
    const css = "body { /* inline comment */ color: red; }";
    const comments = try getAllComments(allocator, css);
    defer {
        for (comments) |comment| {
            allocator.free(comment.content);
        }
        allocator.free(comments);
    }

    try std.testing.expectEqual(@as(usize, 1), comments.len);
    try std.testing.expectEqualStrings("/* inline comment */", comments[0].content);
    try std.testing.expectEqual(@as(usize, 1), comments[0].line);
    try std.testing.expectEqual(@as(usize, 8), comments[0].column);
}

test "getLineNumber - first line" {
    const text = "hello world";
    try std.testing.expectEqual(@as(usize, 1), getLineNumber(text, 0));
    try std.testing.expectEqual(@as(usize, 1), getLineNumber(text, 5));
}

test "getLineNumber - multiple lines" {
    const text = "line 1\nline 2\nline 3";
    try std.testing.expectEqual(@as(usize, 1), getLineNumber(text, 0));
    try std.testing.expectEqual(@as(usize, 2), getLineNumber(text, 7));
    try std.testing.expectEqual(@as(usize, 3), getLineNumber(text, 14));
}

test "getColumnNumber - first position" {
    const text = "hello world";
    try std.testing.expectEqual(@as(usize, 1), getColumnNumber(text, 0));
}

test "getColumnNumber - middle of line" {
    const text = "hello world";
    try std.testing.expectEqual(@as(usize, 7), getColumnNumber(text, 6));
}

test "getColumnNumber - after newline" {
    const text = "line 1\nline 2";
    try std.testing.expectEqual(@as(usize, 1), getColumnNumber(text, 7));
    try std.testing.expectEqual(@as(usize, 3), getColumnNumber(text, 9));
}
