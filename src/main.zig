const std = @import("std");
const Allocator = std.mem.Allocator;
const Arch = std.Target.Cpu.Arch;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var zs = try ZpackStream.init(&gpa.allocator);
    defer zs.deinit();

    _ = try zs.packNil();
    _ = try zs.packBool(true);
    _ = try zs.packBool(false);
    _ = try zs.packPosFixInt(0);
    _ = try zs.packPosFixInt(112);
    _ = try zs.packNegFixInt(23);
    _ = try zs.packNegFixInt(12);
    _ = try zs.packUint8(128);
    _ = try zs.packUint8(42);
    _ = try zs.packUint16(999);
    _ = try zs.packUint16(1337);
    _ = try zs.packUint32(0xDEADBEEF);
    _ = try zs.packFixStr("Memes");
    _ = try zs.packFixStr("school!");

    zs.dump();
    zs.hexDump();

    // std.log.info("Type of `noomba` is {s}", .{@typeName(@TypeOf(noomba))});
}
// Does a byte-swap on LE machines, an intCast on BE machines.
// !!! The programmer must make sure `dest_type` is large enough to hold the
// value of `n` without losing any information.  Use `beCastSafe` for an error-
// checked version that returns an UnsafeTypeNarrowing error  if the cast would discard
// bits.
fn beCast(comptime dest_type: type, n: anytype) !dest_type {
    var num = n;
    const num_ti = @typeInfo(@TypeOf(num));

    // If big endian, return the value as-is, just intCast() it.
    if (@import("builtin").target.cpu.arch.endian() == .Big)
        return @intCast(dest_type, num);

    return switch (num_ti) {
        .Int, .ComptimeInt => @byteSwap(dest_type, @intCast(dest_type, num)),
        .Float, .ComptimeFloat => @byteSwap(dest_type, @floatCast(dest_type, num)),
        .Bool => num,
        else => if (@TypeOf(n) == dest_type) n else error.IncompatibleTypes,
    };
}

// fn beCastSafe(dest_type: type, n: anytype) !dest_type {

// }

/// Writes a native int with BE byte ordering.
/// Returns: number of bytes written.
const ZpackStream = struct {
    ator: *Allocator = undefined,
    buf: []u8 = undefined,
    capacity: usize = undefined,
    // end: usize = 0,
    pos: usize = 0,
    /// Prints type and value of all objects in this stream.
    pub fn dump(zs: ZpackStream) void {
        var i: usize = 0;

        _ = std.log.info("ZpackStream dump:", .{});
        _ = std.log.info("Capacity: {d}", .{zs.capacity});
        _ = std.log.info("Pos: {d}", .{zs.pos});

        while (i < zs.pos) {
            var tag: u8 = zs.buf[i];
            i += 1;

            switch (tag) {
                0x00...0x7F => std.log.info("Positive Fixint: {d}", .{tag}),
                0xA0...0xBF => {
                    const len = tag & 0b0001_1111;
                    std.log.info("FixStr: len: {b}, \"{s}\"", .{ tag, zs.buf[i .. i + len] });
                    i += len;
                },
                0xC0 => std.log.info("nil", .{}),
                0xC2 => std.log.info("Bool: False", .{}),
                0xC3 => std.log.info("Bool: True", .{}),
                0xCC => {
                    std.log.info("Uint8: {d}", .{zs.buf[i]});
                    i += 1;
                },
                0xCD => {
                    std.log.info("Uint16: 0x{0x} ({0d})", .{beCast(u16, zs.buf[i] + (@intCast(u16, zs.buf[i + 1]) << 8))});
                    i += 2;
                },
                0xCE => {
                    std.log.info("Uint32: {d}", .{beCast(u32, zs.buf[i] + (@intCast(u32, zs.buf[i + 1]) << 8) + (@intCast(u32, zs.buf[i + 2]) << 16) + (@intCast(u32, zs.buf[i + 3]) << 24))});
                    i += 4;
                },
                0xE0...0xFF => std.log.info("Negative Fixint: -{d}", .{tag & 0b0001_1111}),
                else => std.log.info("Unknown tag: {X}", .{tag}),
            }
        }
    }

    pub fn hexDump(zs: *ZpackStream) void {
        const alph = "0123456789ABCDEF";
        var buf: [16 * 3]u8 = .{0} ** 48;
        _ = alph;
        _ = zs;

        var row: usize = 0;

        while (row < zs.pos) : (row += 16) {
            for (zs.buf[row .. row + 16]) |c, i| {
                buf[i * 3] = alph[c >> 4 & 0xF];
                buf[i * 3 + 1] = alph[c & 0xF];
                buf[i * 3 + 2] = ' ';
                // std.log.info("{d}: {c}{c}{c}", .{ i, alph[c >> 4 & 0xF], alph[c & 0xF], ' ' });
            }
            std.log.info("{d}: {s}", .{ row, buf });
        }
    }

    // fn checkFit(zs: ZpackStream, obj: anytype) {

    // }
    pub fn realloc(zs: *ZpackStream, new_capacity: usize) !void {
        var new_buf = try zs.ator.alloc(u8, new_capacity);
        std.mem.copy(u8, new_buf, zs.buf[0..zs.pos]);
        zs.ator.free(zs.buf);
        zs.buf = new_buf;
        zs.capacity = new_capacity;
    }

    pub fn reallocIfNeeded(zs: *ZpackStream, desired_capacity: usize) !void {
        if (desired_capacity > zs.capacity) {
            var new_cap = zs.capacity * 2;
            _ = try zs.realloc(new_cap);
            zs.capacity = new_cap;
        }
    }

    /// Writes a 1 byte nil to the object stream.
    /// Nil: 0xC0
    /// Returns number of bytes written (always 1)
    pub fn packNil(zs: *ZpackStream) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, NIL", .{ zs.pos, zs.capacity });

        zs.buf[zs.pos] = 0xC0;
        zs.pos += 1;
        return 1;
    }

    /// Writes a 1 byte bool to the object stream.
    /// False: 0xC2, True: 0xC3
    /// Returns number of bytes written (always 1)
    pub fn packBool(zs: *ZpackStream, b: bool) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, BOOL", .{ zs.pos, zs.capacity });

        zs.buf[zs.pos] = @as(u8, if (b) 0xC3 else 0xC2);
        zs.pos += 1;
        return 1;
    }
    /// Writes a 7 bit positive integer to the object stream.
    /// Returns number of bytes written (always 1).
    pub fn packPosFixInt(zs: *ZpackStream, n: u7) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, POSFIXINT", .{ zs.pos, zs.capacity });

        zs.buf[zs.pos] = @as(u8, n);
        zs.pos += 1;
        return 1;
    }
    /// Writes a 5 bit negative integer to the object stream.
    /// Returns number of bytes written (always 1).
    pub fn packNegFixInt(zs: *ZpackStream, n: u5) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, NEGFIXINT", .{ zs.pos, zs.capacity });

        zs.buf[zs.pos] = @as(u8, n) | @as(u8, 0b1110_0000);
        zs.pos += 1;
        return 1;
    }
    /// Writes an 8-bit unsigned integer to the object stream.
    /// Returns number of bytes written (always 2).
    pub fn packUint8(zs: *ZpackStream, n: u8) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 2);

        // std.log.info("pos: {d}, cap: {d}, UINT8", .{ zs.pos, zs.capacity });

        zs.buf[zs.pos] = 0xCC;
        zs.buf[zs.pos + 1] = n;
        zs.pos += 2;
        return 2;
    }

    pub fn packUint16(zs: *ZpackStream, n: u16) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 3);

        // std.log.info("pos: {d}, cap: {d}, UINT16", .{ zs.pos, zs.capacity });

        var n_be = try beCast(u16, n);

        zs.buf[zs.pos] = 0xCD;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8);
        zs.pos += 3;

        return 3;
    }

    pub fn packUint32(zs: *ZpackStream, n: u32) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 5);

        std.log.info("pos: {d}, cap: {d}, UINT32", .{ zs.pos, zs.capacity });

        var n_be = try beCast(u32, n);

        zs.buf[zs.pos] = 0xCE;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, n_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, n_be >> 24 & 0xFF);
        zs.pos += 5;

        return 5;
    }

    pub fn packFixStr(zs: *ZpackStream, s: []const u8) !usize {

        // std.log.info("pos: {d}, cap: {d}, FIXSTR", .{ zs.pos, zs.capacity });

        var tag: u8 = 0b1010_0000;

        if (s.len > 31) {
            return error.StringTooLong;
        } else {
            tag |= @intCast(u8, s.len);
        }

        _ = try zs.reallocIfNeeded(zs.pos + 1 + s.len);

        // std.log.info("!!! {d} {b} {s}", .{ tag, tag, s });

        zs.buf[zs.pos] = tag;
        std.mem.copy(u8, zs.buf[zs.pos + 1 ..], s);
        zs.buf[zs.pos + 1] = s[0];
        zs.buf[zs.pos + 2] = s[1];
        zs.pos += (1 + s.len);

        return s.len + 1;
    }

    pub fn init(alligator: *Allocator) !ZpackStream {
        var buff: []u8 = undefined;
        const cap: usize = 2;
        buff = try alligator.alloc(u8, cap); // XXX: magic

        return ZpackStream{
            .ator = alligator,
            .buf = buff,
            .capacity = cap,
            .pos = 0,
        };
    }
    // Free the buffer.
    pub fn deinit(zs: ZpackStream) void {
        zs.ator.free(zs.buf);
    }
};
