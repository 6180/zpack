const std = @import("std");
const Allocator = std.mem.Allocator;
const Arch = std.Target.Cpu.Arch;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var mps = try MsgpackStream.init(&gpa.allocator);
    defer mps.deinit();

    _ = try mps.packBool(true);
    _ = try mps.packPosFixInt(0);
    _ = try mps.packNegFixInt(23);
    _ = try mps.packNil();
    _ = try mps.packPosFixInt(112);
    _ = try mps.packNegFixInt(12);
    _ = try mps.packBool(false);
    _ = try mps.packBool(false);
    _ = try mps.packUint8(128);
    _ = try mps.packUint8(42);
    _ = try mps.packUint16(999);
    _ = try mps.packUint16(1337);
    _ = try mps.packFixStr("Memesdds");
    _ = try mps.packFixStr("school!");

    mps.dump();
    mps.hexDump();

    // std.log.info("Type of `noomba` is {s}", .{@typeName(@TypeOf(noomba))});
}

// !!! The programmer must make sure `dest_type` is large enough to hold the
// value of `n` without losing any information.  Use `beCastSafe` for an error-
// checked version that returns an UnsafeTypeNarrowing error  if the cast would discard
// bits.
fn beCast(comptime dest_type: type, n: anytype) !dest_type {
    var num = n;
    const num_ti = @typeInfo(@TypeOf(num));
    // If big endian,
    if (@import("builtin").target.cpu.arch.endian() == .Little)
        return @intCast(dest_type, num);

    return switch (num_ti) {
        .Int, .ComptimeInt => @byteSwap(dest_type, @intCast(dest_type, num)),
        .Float, .ComptimeFloat => @byteSwap(dest_type, @floatCast(dest_type, num)),
        .Bool => num,
        else => if (@TypeOf(n) == dest_type) n else error{IncompatibleTypes},
    };
}

// fn beCastSafe(dest_type: type, n: anytype) !dest_type {

// }

/// Writes a native int with BE byte ordering.
/// Returns: number of bytes written.
const MsgpackStream = struct {
    ator: *Allocator = undefined,
    buf: []u8 = undefined,
    capacity: usize = undefined,
    // end: usize = 0,
    pos: usize = 0,
    /// Prints type and value of all objects in this stream.
    pub fn dump(mps: MsgpackStream) void {
        var i: usize = 0;

        _ = std.log.info("MsgpackStream dump:", .{});
        _ = std.log.info("Capacity: {d}", .{mps.capacity});
        _ = std.log.info("Pos: {d}", .{mps.pos});

        while (i < mps.pos) {
            var tag: u8 = mps.buf[i];
            i += 1;

            switch (tag) {
                0x00...0x7F => std.log.info("Positive Fixint: {d}", .{tag}),
                0xA0...0xBF => {
                    const len = tag & 0b0001_1111;
                    std.log.info("FixStr: len: {b}, \"{s}\"", .{ tag, mps.buf[i .. i + len] });
                    i += len;
                },
                0xC0 => std.log.info("nil", .{}),
                0xC2 => std.log.info("Bool: False", .{}),
                0xC3 => std.log.info("Bool: True", .{}),
                0xCC => {
                    std.log.info("Uint8: {d}", .{mps.buf[i]});
                    i += 1;
                },
                0xCD => {
                    std.log.info("Uint16: {d}", .{beCast(u16, (@intCast(u16, mps.buf[i]) << 8) + mps.buf[i + 1])});
                    i += 2;
                },
                0xE0...0xFF => std.log.info("Negative Fixint: -{d}", .{tag & 0b0001_1111}),
                else => std.log.info("Unknown tag: {X}", .{tag}),
            }
        }
    }

    pub fn hexDump(mps: *MsgpackStream) void {
        const alph = "0123456789ABCDEF";
        var buf: [16 * 3]u8 = .{0} ** 48;
        _ = alph;
        _ = mps;

        var row: usize = 0;

        while (row < mps.pos) : (row += 16) {
            for (mps.buf[row .. row + 16]) |c, i| {
                buf[i * 3] = alph[c >> 4 & 0xF];
                buf[i * 3 + 1] = alph[c & 0xF];
                buf[i * 3 + 2] = ' ';
                // std.log.info("{d}: {c}{c}{c}", .{ i, alph[c >> 4 & 0xF], alph[c & 0xF], ' ' });
            }
            std.log.info("{d}: {s}", .{ row, buf });
        }
    }

    // fn checkFit(mps: MsgpackStream, obj: anytype) {

    // }
    pub fn realloc(mps: *MsgpackStream, new_capacity: usize) !void {
        var new_buf = try mps.ator.alloc(u8, new_capacity);
        std.mem.copy(u8, new_buf, mps.buf[0..mps.pos]);
        mps.ator.free(mps.buf);
        mps.buf = new_buf;
        mps.capacity = new_capacity;
    }

    pub fn reallocIfNeeded(mps: *MsgpackStream, desired_capacity: usize) !void {
        if (desired_capacity > mps.capacity) {
            var new_cap = mps.capacity * 2;
            _ = try mps.realloc(new_cap);
            mps.capacity = new_cap;
        }
    }

    /// Writes a 1 byte nil to the object stream.
    /// Nil: 0xC0
    /// Returns number of bytes written (always 1)
    pub fn packNil(mps: *MsgpackStream) !usize {
        _ = try mps.reallocIfNeeded(mps.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, NIL", .{ mps.pos, mps.capacity });

        mps.buf[mps.pos] = 0xC0;
        mps.pos += 1;
        return 1;
    }

    /// Writes a 1 byte bool to the object stream.
    /// False: 0xC2, True: 0xC3
    /// Returns number of bytes written (always 1)
    pub fn packBool(mps: *MsgpackStream, b: bool) !usize {
        _ = try mps.reallocIfNeeded(mps.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, BOOL", .{ mps.pos, mps.capacity });

        mps.buf[mps.pos] = @as(u8, if (b) 0xC3 else 0xC2);
        mps.pos += 1;
        return 1;
    }
    /// Writes a 7 bit positive integer to the object stream.
    /// Returns number of bytes written (always 1).
    pub fn packPosFixInt(mps: *MsgpackStream, n: u7) !usize {
        _ = try mps.reallocIfNeeded(mps.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, POSFIXINT", .{ mps.pos, mps.capacity });

        mps.buf[mps.pos] = @as(u8, n);
        mps.pos += 1;
        return 1;
    }
    /// Writes a 5 bit negative integer to the object stream.
    /// Returns number of bytes written (always 1).
    pub fn packNegFixInt(mps: *MsgpackStream, n: u5) !usize {
        _ = try mps.reallocIfNeeded(mps.pos + 1);

        // std.log.info("pos: {d}, cap: {d}, NEGFIXINT", .{ mps.pos, mps.capacity });

        mps.buf[mps.pos] = @as(u8, n) | @as(u8, 0b1110_0000);
        mps.pos += 1;
        return 1;
    }
    /// Writes an 8-bit unsigned integer to the object stream.
    /// Returns number of bytes written (always 2).
    pub fn packUint8(mps: *MsgpackStream, n: u8) !usize {
        _ = try mps.reallocIfNeeded(mps.pos + 2);

        // std.log.info("pos: {d}, cap: {d}, UINT8", .{ mps.pos, mps.capacity });

        mps.buf[mps.pos] = 0xCC;
        mps.buf[mps.pos + 1] = n;
        mps.pos += 2;
        return 2;
    }

    pub fn packUint16(mps: *MsgpackStream, n: u16) !usize {
        _ = try mps.reallocIfNeeded(mps.pos + 3);

        // std.log.info("pos: {d}, cap: {d}, UINT16", .{ mps.pos, mps.capacity });

        var n_be = try beCast(u16, n);

        mps.buf[mps.pos] = 0xCD;
        mps.buf[mps.pos + 1] = @intCast(u8, n_be >> 8);
        mps.buf[mps.pos + 2] = @intCast(u8, n_be & 0xFF);
        mps.pos += 3;
        return 3;
    }

    pub fn packFixStr(mps: *MsgpackStream, s: []const u8) !usize {

        // std.log.info("pos: {d}, cap: {d}, FIXSTR", .{ mps.pos, mps.capacity });

        var tag: u8 = 0b1010_0000;

        if (s.len > 31) {
            return error.StringTooLong;
        } else {
            tag |= @intCast(u8, s.len);
        }

        _ = try mps.reallocIfNeeded(mps.pos + 1 + s.len);

        // std.log.info("!!! {d} {b} {s}", .{ tag, tag, s });

        mps.buf[mps.pos] = tag;
        std.mem.copy(u8, mps.buf[mps.pos + 1 ..], s);
        mps.buf[mps.pos + 1] = s[0];
        mps.buf[mps.pos + 2] = s[1];
        mps.pos += (1 + s.len);

        return s.len + 1;
    }

    /// Writes a native int with BE byte ordering to the stream.
    /// Returns: number of bytes written.
    // pub fn PackUint(mps: MsgpackStream, n: anytype) !usize {
    //     var num = n;
    //     const num_ti = @typeInfo(num);
    //     const endianess = Arch.endian();

    //     // Make sure n is an int.
    //     if (num_ti != .Int)
    //         return error{TypeError};

    //     const is_signed: bool = (num_ti.signedness == .signed);

    //     // If arch is LE, swap byte order.
    //     if (endianess == .Little)
    //         num = @byteSwap(@TypeOf(n), num);

    //     // const bit_width = @bitSizeOf(num);

    //     if (is_signed and num < 0 and num >= -32) {
    //         // Negative fixint stores a 5 bit negative number. [ 111YYYYY ]
    //         mps.buf[mps.pos] = @intCast(u8, num) & @as(u8, 0b1110_0000);
    //         mps.pos += 1;
    //     }
    // }

    pub fn init(alligator: *Allocator) !MsgpackStream {
        var buff: []u8 = undefined;
        const cap: usize = 2;
        buff = try alligator.alloc(u8, cap); // XXX: magic

        return MsgpackStream{
            .ator = alligator,
            .buf = buff,
            .capacity = cap,
            .pos = 0,
        };
    }
    // Free the buffer.
    pub fn deinit(mps: MsgpackStream) void {
        mps.ator.free(mps.buf);
    }
};
