const std = @import("std");
const Allocator = std.mem.Allocator;
const Arch = std.Target.Cpu.Arch;
const meta = std.meta;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var zs = try ZpackStream.init(gpa.allocator());
    defer zs.deinit();

    _ = try zs.packNil();
    _ = try zs.packBool(true);
    _ = try zs.packBool(false);
    _ = try zs.packPosFixInt(112);
    _ = try zs.packNegFixInt(23);
    _ = try zs.packUint8(42);
    _ = try zs.packUint16(1337);
    _ = try zs.packUint32(0xDEADBEEF);
    _ = try zs.packUint64(0xCAFEB00BDEADBEEF);
    _ = try zs.packInt8(42);
    _ = try zs.packInt16(420);
    _ = try zs.packInt32(0x1CED1337);
    _ = try zs.packInt64(0x1ECA1BABEFECA1BA);
    _ = try zs.packFloat32(3.14);
    _ = try zs.packFloat64(133769420.69420);
    _ = try zs.packFixStr("Memes");
    _ = try zs.packFixStr("school!");
    _ = try zs.packStr8("I wish, I wish, I wish I was a fish. This string is 71 characters long.");
    _ = try zs.packStr16("I hate the way that one race does that one thing.  Terrible.  This string is 133 characters long and it better fucking stay that way.");
    _ = try zs.packStr32("saldkjfhasldkjfhal;skdjhflsakjdhfkajdshflaksjdfhlaiusjhdfoashcdnakjsdfliasjdnpakjsdnvcoaisjefnposidjfp asdfjaskdfjn a;sodkfj;aslkdjf;alkdjf;alskdjf alskdjfasld;jfa; sldkjfapoiehfjpwoingfpe9ifj;a'slkdfuapsl;kfjaoioigjhkrga;nfnrepoaserfkjahsdfa dfask;d.  I hate the way that one race does that one thing.  Terrible.  This string is 386 characters long and it better fucking stay that way.");
    _ = try zs.packBin8("I wish, I wish, I wish I was a fish. This string is 71 characters long.");
    _ = try zs.packBin16("I hate the way that one race does that one thing.  Terrible.  This string is 133 characters long and it better fucking stay that way.");
    _ = try zs.packBin32("saldkjfhasldkjfhal;skdjhflsakjdhfkajdshflaksjdfhlaiusjhdfoashcdnakjsdfliasjdnpakjsdnvcoaisjefnposidjfp asdfjaskdfjn a;sodkfj;aslkdjf;alkdjf;alskdjf alskdjfasld;jfa; sldkjfapoiehfjpwoingfpe9ifj;a'slkdfuapsl;kfjaoioigjhkrga;nfnrepoaserfkjahsdfa dfask;d.  I hate the way that one race does that one thing.  Terrible.  This string is 386 characters long and it better fucking stay that way.");
    _ = try zs.packStruct(.{ @as(u8, 27), "cock", true, @as(f16, 3.14), 6942069, @as(f64, 133769420.0539) });

    zs.dump();
    // zs.hexDump();
}
// Does a byte-swap on LE machines, an intCast on BE machines.
// !!! The programmer must make sure `dest_type` is large enough to hold the
// value of `n` without losing any information.  Use `beCastSafe` for an error-
// checked version that returns an UnsafeTypeNarrowing error  if the cast would discard
// bits.
fn beCast(n: anytype) @TypeOf(n) {
    var num = n;
    const num_ti = @typeInfo(@TypeOf(num));

    // TODO: write our own endianness detection, this is too bloaty to pull in to detect endianess.
    // If big endian, return the value as-is
    if (@import("builtin").target.cpu.arch.endian() == .Big)
        return num;

    // On LE machines byte-swap
    return switch (num_ti) {
        .Int, .ComptimeInt => @byteSwap(@TypeOf(num), @intCast(@TypeOf(num), num)),
        .Float => |f_ti| blk: {
            if (f_ti.bits == 32) {
                break :blk @byteSwap(u32, @bitCast(u32, num));
            } else if (f_ti.bits == 64) {
                break :blk @byteSwap(u64, @bitCast(u64, num));
            }
        },
        else => num,
    };
}

/// Writes a native int with BE byte ordering.
/// Returns: number of bytes written.
const ZpackStream = struct {
    ator: Allocator = undefined,
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
                    std.log.info("FixStr: len: {d}, \"{s}\"", .{ len, zs.buf[i .. i + len] });
                    i += len;
                },
                0xC0 => std.log.info("nil", .{}),
                0xC2 => std.log.info("Bool: False", .{}),
                0xC3 => std.log.info("Bool: True", .{}),
                0xC4 => {
                    const len: u8 = zs.buf[i];
                    std.log.info("Bin8: len: {d}, \"{s}\"", .{ len, zs.buf[i + 1 .. i + 1 + len] });
                    i += len + 1;
                },
                0xC5 => {
                    var len: u16 = @as(u16, zs.buf[i]) << 8;
                    len |= zs.buf[i + 1];
                    std.log.info("Bin16: len: {d}, \"{s}\"", .{ len, zs.buf[i + 2 .. i + 2 + len] });
                    i += len + 2;
                },
                0xC6 => {
                    var len: u32 = @as(u32, zs.buf[i]) << 24;
                    len |= @as(u32, zs.buf[i + 1]) << 16;
                    len |= @as(u32, zs.buf[i + 2]) << 8;
                    len |= zs.buf[i + 3];
                    std.log.info("Bin32: len: {d}, \"{s}\"", .{ len, zs.buf[i + 4 .. i + 4 + len] });
                    i += len + 4;
                },
                0xCA => {
                    std.log.info("Float32: {e}", .{@bitCast(f32, beCast(zs.buf[i] + (@intCast(u32, zs.buf[i + 1]) << 8) + (@intCast(u32, zs.buf[i + 2]) << 16) + (@intCast(u32, zs.buf[i + 3]) << 24)))});
                    i += 4;
                },
                0xCB => {
                    std.log.info("Float64: {e}", .{@bitCast(f64, beCast(zs.buf[i] + (@intCast(u64, zs.buf[i + 1]) << 8) + (@intCast(u64, zs.buf[i + 2]) << 16) + (@intCast(u64, zs.buf[i + 3]) << 24) + (@intCast(u64, zs.buf[i + 4]) << 32) + (@intCast(u64, zs.buf[i + 5]) << 40) + (@intCast(u64, zs.buf[i + 6]) << 48) + (@intCast(u64, zs.buf[i + 7]) << 56)))});
                    i += 8;
                },
                0xCC => {
                    std.log.info("Uint8: {d}", .{zs.buf[i]});
                    i += 1;
                },
                0xCD => {
                    std.log.info("Uint16: 0x{0X} ({0d})", .{beCast(zs.buf[i] + (@intCast(u16, zs.buf[i + 1]) << 8))});
                    i += 2;
                },
                0xCE => {
                    std.log.info("Uint32: 0x{0X} ({0d})", .{beCast(zs.buf[i] + (@intCast(u32, zs.buf[i + 1]) << 8) + (@intCast(u32, zs.buf[i + 2]) << 16) + (@intCast(u32, zs.buf[i + 3]) << 24))});
                    i += 4;
                },
                0xCF => {
                    std.log.info("Uint64: 0x{0X} ({0d})", .{beCast(zs.buf[i] + (@intCast(u64, zs.buf[i + 1]) << 8) + (@intCast(u64, zs.buf[i + 2]) << 16) + (@intCast(u64, zs.buf[i + 3]) << 24) + (@intCast(u64, zs.buf[i + 4]) << 32) + (@intCast(u64, zs.buf[i + 5]) << 40) + (@intCast(u64, zs.buf[i + 6]) << 48) + (@intCast(u64, zs.buf[i + 7]) << 56))});
                    i += 8;
                },
                0xD0 => {
                    std.log.info("Int8: {d}", .{zs.buf[i]});
                    i += 1;
                },
                0xD1 => {
                    std.log.info("Int16: 0x{0X} ({0d})", .{beCast(zs.buf[i] + (@intCast(i16, zs.buf[i + 1]) << 8))});
                    i += 2;
                },
                0xD2 => {
                    std.log.info("Int32: 0x{0X} ({0d})", .{beCast(zs.buf[i] + (@intCast(i32, zs.buf[i + 1]) << 8) + (@intCast(i32, zs.buf[i + 2]) << 16) + (@intCast(i32, zs.buf[i + 3]) << 24))});
                    i += 4;
                },
                0xD3 => {
                    std.log.info("Int64: 0x{0X} ({0d})", .{beCast(zs.buf[i] + (@intCast(i64, zs.buf[i + 1]) << 8) + (@intCast(i64, zs.buf[i + 2]) << 16) + (@intCast(i64, zs.buf[i + 3]) << 24) + (@intCast(i64, zs.buf[i + 4]) << 32) + (@intCast(i64, zs.buf[i + 5]) << 40) + (@intCast(i64, zs.buf[i + 6]) << 48) + (@intCast(i64, zs.buf[i + 7]) << 56))});
                    i += 8;
                },
                0xD9 => {
                    const len: u8 = zs.buf[i];
                    std.log.info("Str8: len: {d}, \"{s}\"", .{ len, zs.buf[i + 1 .. i + 1 + len] });
                    i += len + 1;
                },
                0xDA => {
                    var len: u16 = @as(u16, zs.buf[i]) << 8;
                    len |= zs.buf[i + 1];
                    std.log.info("Str16: len: {d}, \"{s}\"", .{ len, zs.buf[i + 2 .. i + 2 + len] });
                    i += len + 2;
                },
                0xDB => {
                    var len: u32 = @as(u32, zs.buf[i]) << 24;
                    len |= @as(u32, zs.buf[i + 1]) << 16;
                    len |= @as(u32, zs.buf[i + 2]) << 8;
                    len |= zs.buf[i + 3];
                    std.log.info("Str32: len: {d}, \"{s}\"", .{ len, zs.buf[i + 4 .. i + 4 + len] });
                    i += len + 4;
                },
                0xE0...0xFF => std.log.info("Negative Fixint: -{d}", .{tag & 0b0001_1111}),
                else => std.log.info("Unknown tag: {X}", .{tag}),
            }
        }
    }
    // TODO: redo this, hex formatting still works apparently, was getting deprecated errors when I wrote this.
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
    /// Reallocates the buffer with the given capacity.
    pub fn realloc(zs: *ZpackStream, new_capacity: usize) !void {
        var new_buf = try zs.ator.alloc(u8, new_capacity);
        std.mem.copy(u8, new_buf, zs.buf[0..zs.pos]);
        zs.ator.free(zs.buf);
        zs.buf = new_buf;
        zs.capacity = new_capacity;
    }
    /// If desired_capacity is > zs.capacity, double the buffer size and reallocate.
    pub fn reallocIfNeeded(zs: *ZpackStream, desired_capacity: usize) !void {
        if (desired_capacity > zs.capacity) {
            var new_cap = zs.capacity * 2;
            _ = try zs.realloc(new_cap);
            zs.capacity = new_cap;
        }
    }

    /// Writes a 1 byte nil to the object stream.
    /// Returns number of bytes written (always 1)
    pub fn packNil(zs: *ZpackStream) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        zs.buf[zs.pos] = 0xC0;
        zs.pos += 1;
        return 1;
    }

    /// Writes a 1 byte bool to the object stream.
    /// Returns number of bytes written (always 1)
    pub fn packBool(zs: *ZpackStream, b: bool) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        zs.buf[zs.pos] = @as(u8, if (b) 0xC3 else 0xC2);
        zs.pos += 1;
        return 1;
    }

    /// Writes a 7 bit positive integer to the object stream.
    /// Returns number of bytes written (always 1).
    pub fn packPosFixInt(zs: *ZpackStream, n: u7) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        zs.buf[zs.pos] = @as(u8, n);
        zs.pos += 1;
        return 1;
    }
    /// Writes a 5 bit negative integer to the object stream.
    /// Returns number of bytes written (always 1).
    pub fn packNegFixInt(zs: *ZpackStream, n: u5) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 1);

        zs.buf[zs.pos] = @as(u8, n) | @as(u8, 0b1110_0000);
        zs.pos += 1;
        return 1;
    }

    /// Writes an 8-bit unsigned integer to the object stream.
    /// Returns number of bytes written (always 2).
    pub fn packUint8(zs: *ZpackStream, n: u8) !usize {
        _ = try zs.reallocIfNeeded(zs.pos + 2);

        zs.buf[zs.pos] = 0xCC;
        zs.buf[zs.pos + 1] = n;
        zs.pos += 2;

        return 2;
    }
    /// Writes a 16-bit unsigned integer to the object stream.
    /// Returns number of bytes written (always 3).
    pub fn packUint16(zs: *ZpackStream, n: u16) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 3);

        zs.buf[zs.pos] = 0xCD;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8);
        zs.pos += 3;

        return 3;
    }
    /// Writes a 32-bit unsigned integer to the object stream.
    /// Returns number of bytes written (always 5).
    pub fn packUint32(zs: *ZpackStream, n: u32) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 5);

        zs.buf[zs.pos] = 0xCE;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, n_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, n_be >> 24 & 0xFF);
        zs.pos += 5;

        return 5;
    }
    /// Writes a 64-bit unsigned integer to the object stream.
    /// Returns number of bytes written (always 9).
    pub fn packUint64(zs: *ZpackStream, n: u64) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 9);

        zs.buf[zs.pos] = 0xCF;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, n_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, n_be >> 24 & 0xFF);
        zs.buf[zs.pos + 5] = @intCast(u8, n_be >> 32 & 0xFF);
        zs.buf[zs.pos + 6] = @intCast(u8, n_be >> 40 & 0xFF);
        zs.buf[zs.pos + 7] = @intCast(u8, n_be >> 48 & 0xFF);
        zs.buf[zs.pos + 8] = @intCast(u8, n_be >> 56 & 0xFF);
        zs.pos += 9;

        return 9;
    }
    /// Writes an 8-bit signed integer to the object stream.
    /// Returns number of bytes written (always 2).
    pub fn packInt8(zs: *ZpackStream, n: i8) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 2);

        zs.buf[zs.pos] = 0xD0;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0x7F);
        zs.pos += 2;

        return 2;
    }
    /// Writes a 16-bit signed integer to the object stream.
    /// Returns number of bytes written (always 3).
    pub fn packInt16(zs: *ZpackStream, n: i16) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 3);

        zs.buf[zs.pos] = 0xD1;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0x7F);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8 & 0xFF);
        zs.pos += 3;

        return 3;
    }
    /// Writes a 32-bit signed integer to the object stream.
    /// Returns number of bytes written (always 5).
    pub fn packInt32(zs: *ZpackStream, n: i32) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 5);

        zs.buf[zs.pos] = 0xD2;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0x7F);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, n_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, n_be >> 24 & 0xFF);
        zs.pos += 5;

        return 5;
    }
    /// Writes a 64-bit signed integer to the object stream.
    /// Returns number of bytes written (always 9).
    pub fn packInt64(zs: *ZpackStream, n: i64) !usize {
        var n_be = beCast(n);
        _ = try zs.reallocIfNeeded(zs.pos + 9);

        zs.buf[zs.pos] = 0xD3;
        zs.buf[zs.pos + 1] = @intCast(u8, n_be & 0x7F);
        zs.buf[zs.pos + 2] = @intCast(u8, n_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, n_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, n_be >> 24 & 0xFF);
        zs.buf[zs.pos + 5] = @intCast(u8, n_be >> 32 & 0xFF);
        zs.buf[zs.pos + 6] = @intCast(u8, n_be >> 40 & 0xFF);
        zs.buf[zs.pos + 7] = @intCast(u8, n_be >> 48 & 0xFF);
        zs.buf[zs.pos + 8] = @intCast(u8, n_be >> 56 & 0xFF);
        zs.pos += 9;

        return 9;
    }
    /// Writes a 32-bit floating point number to the object stream.
    /// Returns the number of bytes written (always 5).
    pub fn packFloat32(zs: *ZpackStream, f: f32) !usize {
        var fu_be: u32 = beCast(@bitCast(u32, f));
        _ = try zs.reallocIfNeeded(zs.pos + 5);

        zs.buf[zs.pos] = 0xCA;
        zs.buf[zs.pos + 1] = @intCast(u8, fu_be & 0x7F);
        zs.buf[zs.pos + 2] = @intCast(u8, fu_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, fu_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, fu_be >> 24 & 0xFF);
        zs.pos += 5;

        return 5;
    }
    /// Writes a 64-bit floating point number to the object stream.
    /// Returns the number of bytes written (always 9).
    pub fn packFloat64(zs: *ZpackStream, f: f64) !usize {
        var fu_be: u64 = beCast(@bitCast(u64, f));
        _ = try zs.reallocIfNeeded(zs.pos + 9);

        zs.buf[zs.pos] = 0xCB;
        zs.buf[zs.pos + 1] = @intCast(u8, fu_be & 0x7F);
        zs.buf[zs.pos + 2] = @intCast(u8, fu_be >> 8 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, fu_be >> 16 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, fu_be >> 24 & 0xFF);
        zs.buf[zs.pos + 5] = @intCast(u8, fu_be >> 32 & 0xFF);
        zs.buf[zs.pos + 6] = @intCast(u8, fu_be >> 40 & 0xFF);
        zs.buf[zs.pos + 7] = @intCast(u8, fu_be >> 48 & 0xFF);
        zs.buf[zs.pos + 8] = @intCast(u8, fu_be >> 56 & 0xFF);
        zs.pos += 9;

        return 9;
    }
    /// Writes a byte array with a max len of 31 to the object stream.
    /// Returns number of bytes written (s.len + 1).
    pub fn packFixStr(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0b1010_0000;

        if (s.len > 31)
            return error.StringTooLong;

        tag |= @intCast(u8, s.len);

        _ = try zs.reallocIfNeeded(zs.pos + 1 + s.len);

        zs.buf[zs.pos] = tag;
        std.mem.copy(u8, zs.buf[zs.pos + 1 ..], s);
        zs.pos += (1 + s.len);

        return s.len + 1;
    }

    pub fn packStr8(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0xD9;

        if (s.len > 255)
            return error.StringTooLong;

        _ = try zs.reallocIfNeeded(zs.pos + 2 + s.len);

        zs.buf[zs.pos] = tag;
        zs.buf[zs.pos + 1] = @intCast(u8, s.len);
        std.mem.copy(u8, zs.buf[zs.pos + 2 ..], s);
        zs.pos += (2 + s.len);

        return s.len + 2;
    }

    pub fn packStr16(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0xDA;

        if (s.len > 65535)
            return error.StringTooLong;

        _ = try zs.reallocIfNeeded(zs.pos + 3 + s.len);

        zs.buf[zs.pos] = tag;
        zs.buf[zs.pos + 1] = @intCast(u8, s.len >> 8 & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, s.len & 0xFF);
        std.mem.copy(u8, zs.buf[zs.pos + 3 ..], s);
        zs.pos += (3 + s.len);

        return s.len + 3;
    }

    pub fn packStr32(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0xDB;

        if (s.len > 4294967295)
            return error.StringTooLong;

        _ = try zs.reallocIfNeeded(zs.pos + 5 + s.len);

        zs.buf[zs.pos] = tag;
        zs.buf[zs.pos + 1] = @intCast(u8, s.len >> 24 & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, s.len >> 16 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, s.len >> 8 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, s.len & 0xFF);
        std.mem.copy(u8, zs.buf[zs.pos + 5 ..], s);
        zs.pos += (5 + s.len);

        return s.len + 5;
    }

    pub fn packBin8(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0xC4;

        if (s.len > 255)
            return error.StringTooLong;

        _ = try zs.reallocIfNeeded(zs.pos + 2 + s.len);

        zs.buf[zs.pos] = tag;
        zs.buf[zs.pos + 1] = @intCast(u8, s.len);
        std.mem.copy(u8, zs.buf[zs.pos + 2 ..], s);
        zs.pos += (2 + s.len);

        return s.len + 2;
    }

    pub fn packBin16(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0xC5;

        if (s.len > 65535)
            return error.StringTooLong;

        _ = try zs.reallocIfNeeded(zs.pos + 3 + s.len);

        zs.buf[zs.pos] = tag;
        zs.buf[zs.pos + 1] = @intCast(u8, s.len >> 8 & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, s.len & 0xFF);
        std.mem.copy(u8, zs.buf[zs.pos + 3 ..], s);
        zs.pos += (3 + s.len);

        return s.len + 3;
    }

    pub fn packBin32(zs: *ZpackStream, s: []const u8) !usize {
        var tag: u8 = 0xC6;

        if (s.len > 4294967295)
            return error.StringTooLong;

        _ = try zs.reallocIfNeeded(zs.pos + 5 + s.len);

        zs.buf[zs.pos] = tag;
        zs.buf[zs.pos + 1] = @intCast(u8, s.len >> 24 & 0xFF);
        zs.buf[zs.pos + 2] = @intCast(u8, s.len >> 16 & 0xFF);
        zs.buf[zs.pos + 3] = @intCast(u8, s.len >> 8 & 0xFF);
        zs.buf[zs.pos + 4] = @intCast(u8, s.len & 0xFF);
        std.mem.copy(u8, zs.buf[zs.pos + 5 ..], s);
        zs.pos += (5 + s.len);

        return s.len + 5;
    }

    pub fn packStruct(zs: *ZpackStream, _struct: anytype) !usize {
        var bytes_written: usize = 0;

        // Loop over the fields and pack them
        inline for (_struct) |v, i| {
            bytes_written += switch (@typeInfo(@TypeOf(v))) {
                .Int => |ti| blk: {
                    std.log.info("Field {d}, Int {d}", .{ i, v });
                    if (ti.signedness == .unsigned) {
                        break :blk switch (v) {
                            0x00...0xFF => try zs.packUint8(v),
                            0x100...0xFFFF => try zs.packUint16(v),
                            0x1_0000...0xFFFF_FFFF => try zs.packUint32(v),
                            0x1_0000_0000...0xFFFF_FFFF_FFFF_FFFF => try zs.packUint64(v),
                            else => return error.InvalidArgument, // TODO: u128 ext
                        };
                    } else { // ti.signedness == .signed
                        break :blk switch (v.bits) {
                            -0x80...0x7F => try zs.packInt8(v),
                            -0x8000...0x7FFF => try zs.packInt16(v),
                            -0x8000_0000...0x7FFF_FFFF => try zs.packInt32(v),
                            -0x8000_0000_0000_0000...0x7FFF_FFFF_FFFF_FFFF => try zs.packInt64(v),
                            else => return error.InvalidArgument, // TODO: u128 ext
                        };
                    }
                },
                .ComptimeInt => blk: {
                    std.log.info("Field {d}, ComptimeInt {d}", .{ i, v });

                    if (v >= 0) { // Treat as unsigned.
                        break :blk switch (v) {
                            0x00...0xFF => try zs.packUint8(v),
                            0x100...0xFFFF => try zs.packUint16(v),
                            0x1_0000...0xFFFF_FFFF => try zs.packUint32(v),
                            0x1_0000_0000...0xFFFF_FFFF_FFFF_FFFF => try zs.packUint64(v),
                            else => return error.InvalidArgument, // TODO: u128 ext
                        };
                    } else { // Treat as signed.
                        break :blk switch (v.bits) {
                            -0x80...0x7F => try zs.packInt8(v),
                            -0x8000...0x7FFF => try zs.packInt16(v),
                            -0x8000_0000...0x7FFF_FFFF => try zs.packInt32(v),
                            -0x8000_0000_0000_0000...0x7FFF_FFFF_FFFF_FFFF => try zs.packInt64(v),
                            else => return error.InvalidArgument, // TODO: i128 ext
                        };
                    }
                },
                .Float => |fti| blk: {
                    std.log.info("Field {d}, Float {d}", .{ i, v });

                    break :blk switch (fti.bits) {
                        16, 32 => try zs.packFloat32(v),
                        64 => try zs.packFloat64(v),
                        else => return error.InvalidArgument, // TODO: f128 ext
                    };
                },
                .ComptimeFloat => @compileError("Comptime Floats not supported."), // TODO: f128 ext
                .Bool => try zs.packBool(v),
                .Struct => std.log.info("Field {d}, Struct {any}", .{ i, v }),
                else => blk: {
                    // if (@TypeOf(v) == @TypeOf(null)) {
                    //     break :blk try zs.packNil();
                    // } else 
                    if (meta.trait.isZigString(@TypeOf(v))) {
                        std.log.info("Field {d}, String ({d}) {s}", .{ i, v.len, v });
                        break :blk switch (v.len) {
                            0...31 => try zs.packFixStr(v),
                            32...255 => try zs.packStr8(v),
                            256...65535 => try zs.packStr16(v),
                            65536...4294967295 => try zs.packStr32(v),
                            else => return error.StringTooLong,
                        };
                    } else {
                        std.log.info("Field {d}, Unsupported type {s}", .{ i, @typeName(@TypeOf(v)) });
                    }
                    return error.UnsupportedType;
                },
            }; // switch
        } // inline for

        _ = zs;
        return bytes_written;
    }

    // pub fn packFixArray(zs: *ZpackStream, args: anytype) !usize {

// }

    pub fn init(alligator: Allocator) !ZpackStream {
        var buff: []u8 = undefined;
        const cap: usize = 2;
        buff = try alligator.alloc(u8, cap); // TODO: magic

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
