#!/usr/bin/env python3
"""Generate the TIFF Inspector regression fixtures.

Standard library only (Python 3.9+). The TIFF writer below is deliberately
small, hand-written and independent of the OCaml parser under test.

Usage:
    python3 scripts/gen-fixtures/gen_fixtures.py [OUT_DIR] [--verify]

OUT_DIR defaults to ``test/fixtures``. Output is deterministic: re-running the
script produces byte-identical files. ``--verify`` re-parses every fixture in
OUT_DIR with an independent minimal reader (also in this file, sharing no code
with the writer) and asserts the documented properties.

Layout written by the writer, per file:
    header | for each IFD: [pixel chunks][IFD][out-of-line values] ...
Every chunk, IFD and out-of-line value starts on a 4-byte (classic) or 8-byte
(BigTIFF) boundary; padding bytes are zero. IFD entries are sorted by tag.
Values that fit in the 4-byte (classic) / 8-byte (BigTIFF) value field are
stored inline, left-justified, zero-padded.
"""

import hashlib
import os
import struct
import sys
import zlib

# --------------------------------------------------------------------------
# Writer
# --------------------------------------------------------------------------

BYTE, ASCII, SHORT, LONG, RATIONAL = 1, 2, 3, 4, 5
SBYTE, UNDEFINED, SSHORT, SLONG, SRATIONAL = 6, 7, 8, 9, 10
FLOAT, DOUBLE, LONG8, SLONG8, IFD8 = 11, 12, 16, 17, 18

TYPE_FMT = {
    BYTE: "B", ASCII: "B", SHORT: "H", LONG: "I", RATIONAL: "II",
    SBYTE: "b", UNDEFINED: "B", SSHORT: "h", SLONG: "i", SRATIONAL: "ii",
    FLOAT: "f", DOUBLE: "d", LONG8: "Q", SLONG8: "q", IFD8: "Q",
}

# Placeholders replaced by chunk offsets / byte counts once data is placed.
OFFSETS = "<chunk offsets>"
COUNTS = "<chunk byte counts>"


class Tag:
    """A normal tag: values is a list of numbers (pairs for RATIONAL),
    bytes for ASCII/BYTE/UNDEFINED, a str for ASCII (NUL appended), or one
    of the OFFSETS/COUNTS placeholders."""

    def __init__(self, tag, typ, values):
        self.tag, self.typ, self.values = tag, typ, values


class RawTag:
    """An entry written verbatim: arbitrary type code and count, and the raw
    value-field bytes (padded/truncated to the field size). Used for
    malformed fixtures."""

    def __init__(self, tag, typ, count, field):
        self.tag, self.typ, self.count, self.field = tag, typ, count, field


class Page:
    def __init__(self, tags, chunks, next_override=None):
        self.tags = tags            # list of Tag / RawTag
        self.chunks = chunks        # list of bytes (strips or tiles)
        self.next_override = next_override  # "self" or int, for malformed files


def _encode(bo, typ, values):
    """Return (count, payload bytes) for a Tag."""
    if isinstance(values, str):
        b = values.encode("ascii") + b"\x00"
        return len(b), b
    if isinstance(values, (bytes, bytearray)):
        return len(values), bytes(values)
    fmt = TYPE_FMT[typ]
    out = b""
    for v in values:
        if typ in (RATIONAL, SRATIONAL):
            out += struct.pack(bo + fmt, v[0], v[1])
        else:
            out += struct.pack(bo + fmt, v)
    return len(values), out


def _align(buf, n):
    while len(buf) % n:
        buf.append(0)


def write_tiff(pages, little_endian=True, bigtiff=False):
    """Serialise pages. Returns (bytes, info) where info has ifd_offsets."""
    bo = "<" if little_endian else ">"
    field = 8 if bigtiff else 4
    align = 8 if bigtiff else 4
    buf = bytearray()
    buf += b"II" if little_endian else b"MM"
    if bigtiff:
        buf += struct.pack(bo + "HHHQ", 43, 8, 0, 0)
        first_ptr_pos = 8
    else:
        buf += struct.pack(bo + "HI", 42, 0)
        first_ptr_pos = 4
    ptr_pos = first_ptr_pos      # where to patch the pointer to the next IFD
    ptr_fmt = bo + ("Q" if bigtiff else "I")
    ifd_offsets = []

    for page in pages:
        # 1. pixel chunks
        offs, counts = [], []
        for ch in page.chunks:
            _align(buf, align)
            offs.append(len(buf))
            counts.append(len(ch))
            buf += ch
        # 2. resolve entries
        entries = []
        for t in sorted(page.tags, key=lambda t: t.tag):
            if isinstance(t, RawTag):
                entries.append((t.tag, t.typ, t.count, None, t.field))
                continue
            vals = t.values
            if vals is OFFSETS:
                vals = offs
            elif vals is COUNTS:
                vals = counts
            count, payload = _encode(bo, t.typ, vals)
            entries.append((t.tag, t.typ, count, payload, None))
        # 3. IFD position and size
        _align(buf, align)
        ifd_off = len(buf)
        ifd_offsets.append(ifd_off)
        struct.pack_into(ptr_fmt, buf, ptr_pos, ifd_off)
        n = len(entries)
        if bigtiff:
            ifd_size = 8 + 20 * n + 8
        else:
            ifd_size = 2 + 12 * n + 4
        ext_pos = ifd_off + ifd_size
        # 4. out-of-line values go right after the IFD
        ext = bytearray()
        fields = []
        for tag, typ, count, payload, raw in entries:
            if raw is not None:
                f = bytes(raw[:field]).ljust(field, b"\x00")
            elif len(payload) <= field:
                f = payload.ljust(field, b"\x00")   # left-justified inline
            else:
                while (ext_pos + len(ext)) % align:
                    ext.append(0)
                f = struct.pack(ptr_fmt, ext_pos + len(ext))
                ext += payload
            fields.append((tag, typ, count, f))
        ifd = bytearray()
        if bigtiff:
            ifd += struct.pack(bo + "Q", n)
            for tag, typ, count, f in fields:
                ifd += struct.pack(bo + "HHQ", tag, typ, count) + f
        else:
            ifd += struct.pack(bo + "H", n)
            for tag, typ, count, f in fields:
                ifd += struct.pack(bo + "HHI", tag, typ, count) + f
        ptr_pos = ifd_off + len(ifd)
        ifd += struct.pack(ptr_fmt, 0)
        assert len(ifd) == ifd_size
        buf += ifd + ext
        if page.next_override is not None:
            target = ifd_off if page.next_override == "self" else page.next_override
            struct.pack_into(ptr_fmt, buf, ptr_pos, target)
            ptr_pos = None
    return bytes(buf), {"ifd_offsets": ifd_offsets}


# --------------------------------------------------------------------------
# Fixture definitions
# --------------------------------------------------------------------------

def pattern(n, seed=0):
    return bytes(((i * 13 + seed * 31 + (i // 7) * 5) & 0xFF) for i in range(n))


def gray_tags(w, h, rows_per_strip=None, extra=()):
    tags = [
        Tag(256, SHORT, [w]),
        Tag(257, SHORT, [h]),
        Tag(258, SHORT, [8]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [1]),
        Tag(273, LONG, OFFSETS),
        Tag(277, SHORT, [1]),
        Tag(278, SHORT, [rows_per_strip or h]),
        Tag(279, LONG, COUNTS),
    ]
    return tags + list(extra)


def gray8_page(extra=(), override_tags=None, next_override=None):
    tags = gray_tags(16, 8, extra=[
        Tag(270, ASCII, "gray8 fixture"),
        Tag(282, RATIONAL, [(72, 1)]),
        Tag(283, RATIONAL, [(72, 1)]),
        Tag(296, SHORT, [2]),
    ] + list(extra))
    if override_tags:
        tags = [t for t in tags if t.tag not in {o.tag for o in override_tags}]
        tags += override_tags
    return Page(tags, [pattern(16 * 8, 1)], next_override)


def rgb_tags(w, h, rows_per_strip, planar=None, sample_format=True):
    tags = [
        Tag(256, SHORT, [w]),
        Tag(257, SHORT, [h]),
        Tag(258, SHORT, [8, 8, 8]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [2]),
        Tag(273, LONG, OFFSETS),
        Tag(277, SHORT, [3]),
        Tag(278, SHORT, [rows_per_strip]),
        Tag(279, LONG, COUNTS),
    ]
    if planar is not None:
        tags.append(Tag(284, SHORT, [planar]))
    if sample_format:
        tags.append(Tag(339, SHORT, [1, 1, 1]))
    return tags


def build_fixtures():
    fx = {}

    gray8, gray8_info = write_tiff([gray8_page()])
    fx["gray8.tif"] = gray8

    # rgb_contig: 10x10 RGB chunky, 2 strips of 5 rows
    px = pattern(10 * 10 * 3, 2)
    fx["rgb_contig.tif"] = write_tiff([Page(rgb_tags(10, 10, 5, planar=1),
                                            [px[:150], px[150:]])])[0]

    # rgb_planar: big-endian, separate planes, one strip per plane
    planes = [pattern(100, 3 + i) for i in range(3)]
    fx["rgb_planar.tif"] = write_tiff([Page(rgb_tags(10, 10, 10, planar=2), planes)],
                                      little_endian=False)[0]

    # float32 RGB with SampleFormat=[3,3,3] at an offset
    fl = b"".join(struct.pack("<f", (i % 17) * 0.25 - 1.0) for i in range(4 * 4 * 3))
    fx["float32_sampleformat_offset.tif"] = write_tiff([Page([
        Tag(256, SHORT, [4]),
        Tag(257, SHORT, [4]),
        Tag(258, SHORT, [32, 32, 32]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [2]),
        Tag(273, LONG, OFFSETS),
        Tag(277, SHORT, [3]),
        Tag(278, SHORT, [4]),
        Tag(279, LONG, COUNTS),
        Tag(284, SHORT, [1]),
        Tag(339, SHORT, [3, 3, 3]),
    ], [fl])])[0]

    # multi_ifd: 8x8 gray8, 4x4 gray8, 2x2 RGB
    fx["multi_ifd.tif"] = write_tiff([
        Page(gray_tags(8, 8), [pattern(64, 4)]),
        Page(gray_tags(4, 4), [pattern(16, 5)]),
        Page(rgb_tags(2, 2, 2, planar=1, sample_format=False), [pattern(12, 6)]),
    ])[0]

    # deflate
    raw = pattern(64, 7)
    comp = zlib.compress(raw, 9)
    tags = [t for t in gray_tags(8, 8) if t.tag != 259]
    tags += [Tag(259, SHORT, [8]), Tag(317, SHORT, [1])]
    fx["deflate.tif"] = write_tiff([Page(tags, [comp])])[0]

    # bigtiff: 8x8 uint16
    data16 = b"".join(struct.pack("<H", (i * 1031) & 0xFFFF) for i in range(64))
    fx["bigtiff.tif"] = write_tiff([Page([
        Tag(256, SHORT, [8]),
        Tag(257, SHORT, [8]),
        Tag(258, SHORT, [16]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [1]),
        Tag(273, LONG8, OFFSETS),
        Tag(277, SHORT, [1]),
        Tag(278, SHORT, [8]),
        Tag(279, LONG8, COUNTS),
        Tag(339, SHORT, [1]),
    ], [data16])], bigtiff=True)[0]

    # bigtiff_rgb_inline: BigTIFF RGB with BitsPerSample=[8,8,8] and
    # SampleFormat=[1,1,1] (3 SHORTs = 6 bytes) inline in the 8-byte field,
    # as GDAL writes them
    fx["bigtiff_rgb_inline.tif"] = write_tiff([Page([
        Tag(256, SHORT, [4]),
        Tag(257, SHORT, [4]),
        Tag(258, SHORT, [8, 8, 8]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [2]),
        Tag(273, LONG8, OFFSETS),
        Tag(277, SHORT, [3]),
        Tag(278, SHORT, [4]),
        Tag(279, LONG8, COUNTS),
        Tag(284, SHORT, [1]),
        Tag(339, SHORT, [1, 1, 1]),
    ], [pattern(4 * 4 * 3, 12)])], bigtiff=True)[0]

    # tiled: 32x32 gray8, 16x16 tiles
    tiles = [pattern(256, 10 + i) for i in range(4)]
    fx["tiled.tif"] = write_tiff([Page([
        Tag(256, SHORT, [32]),
        Tag(257, SHORT, [32]),
        Tag(258, SHORT, [8]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [1]),
        Tag(277, SHORT, [1]),
        Tag(322, SHORT, [16]),
        Tag(323, SHORT, [16]),
        Tag(324, LONG, OFFSETS),
        Tag(325, LONG, COUNTS),
    ], tiles)])[0]

    # gray_alpha: BitsPerSample [8,8] inline
    fx["gray_alpha.tif"] = write_tiff([Page([
        Tag(256, SHORT, [4]),
        Tag(257, SHORT, [4]),
        Tag(258, SHORT, [8, 8]),
        Tag(259, SHORT, [1]),
        Tag(262, SHORT, [1]),
        Tag(273, LONG, OFFSETS),
        Tag(277, SHORT, [2]),
        Tag(278, SHORT, [4]),
        Tag(279, LONG, COUNTS),
        Tag(338, SHORT, [2]),
    ], [pattern(32, 11)])])[0]

    # unknown_tag
    fx["unknown_tag.tif"] = write_tiff([gray8_page(extra=[
        Tag(65000, ASCII, "hello private tag"),
        Tag(65001, LONG, list(range(100))),
    ])])[0]

    # ---- malformed ----
    fx["empty.tif"] = b""
    fx["not_a_tiff.tif"] = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + bytes(8)
    fx["bad_magic.tif"] = b"II" + struct.pack("<HI", 99, 8) + bytes(8)
    fx["truncated_header.tif"] = gray8[:5]
    fx["ifd_offset_out_of_range.tif"] = b"II" + struct.pack("<HI", 42, 0x7FFFFFF0) + bytes(8)
    ifd = gray8_info["ifd_offsets"][0]
    fx["truncated_ifd.tif"] = gray8[:ifd + 2 + 12 * 3 + 6]   # mid 4th entry
    fx["strip_out_of_bounds.tif"] = write_tiff([gray8_page(
        override_tags=[Tag(279, LONG, [0x10000])])])[0]
    fx["ifd_loop.tif"] = write_tiff([gray8_page(next_override="self")])[0]
    fx["unknown_field_type.tif"] = write_tiff([gray8_page(
        extra=[RawTag(65002, 99, 1, b"\x01\x02\x03\x04")])])[0]
    fx["huge_strip_count.tif"] = write_tiff([gray8_page(
        override_tags=[RawTag(273, LONG, 0x3FFFFFFF, struct.pack("<I", 8))])])[0]
    return fx


# --------------------------------------------------------------------------
# Independent minimal reader used by --verify (shares no code with writer)
# --------------------------------------------------------------------------

_SZ = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8,
       11: 4, 12: 8, 16: 8, 17: 8, 18: 8}
_UF = {1: "B", 3: "H", 4: "I", 16: "Q", 12: "d"}


class ReadError(Exception):
    pass


def read_tiff(data, max_ifds=16):
    if len(data) < 8:
        raise ReadError("truncated")
    if data[:2] == b"II":
        e = "<"
    elif data[:2] == b"MM":
        e = ">"
    else:
        raise ReadError("not_a_tiff")
    magic = struct.unpack_from(e + "H", data, 2)[0]
    if magic == 42:
        big = False
        nxt = struct.unpack_from(e + "I", data, 4)[0]
    elif magic == 43:
        big = True
        if len(data) < 16:
            raise ReadError("truncated")
        bsz, zero, nxt = struct.unpack_from(e + "HHQ", data, 4)
        if bsz != 8 or zero != 0:
            raise ReadError("malformed")
    else:
        raise ReadError("not_a_tiff")
    ifds, seen = [], set()
    while nxt:
        if nxt in seen:
            return e, big, ifds, "ifd_loop"
        seen.add(nxt)
        if len(ifds) >= max_ifds:
            raise ReadError("limit_exceeded")
        hdr = 8 if big else 2
        if nxt >= len(data):
            raise ReadError("malformed")   # IFD offset points past EOF
        if nxt + hdr > len(data):
            raise ReadError("truncated")
        n = struct.unpack_from(e + ("Q" if big else "H"), data, nxt)[0]
        esz = 20 if big else 12
        end = nxt + hdr + n * esz + (8 if big else 4)
        if end > len(data):
            raise ReadError("truncated")
        tags = {}
        last = -1
        for i in range(n):
            p = nxt + hdr + i * esz
            if big:
                tag, typ, cnt = struct.unpack_from(e + "HHQ", data, p)
                vf, fs = p + 12, 8
            else:
                tag, typ, cnt = struct.unpack_from(e + "HHI", data, p)
                vf, fs = p + 8, 4
            assert tag > last, "entries not sorted"
            last = tag
            if typ not in _SZ:
                tags[tag] = ("unknown_type", typ, cnt)
                continue
            size = _SZ[typ] * cnt
            if size > len(data):
                raise ReadError("limit_exceeded")
            if size <= fs:
                off = vf
            else:
                off = struct.unpack_from(e + ("Q" if big else "I"), data, vf)[0]
                assert off % 2 == 0, "value not word aligned"
                if off + size > len(data):
                    raise ReadError("truncated")
            raw = data[off:off + size]
            if typ == 2:
                val = raw.rstrip(b"\x00").decode("ascii")
            elif typ == 5:
                val = [struct.unpack_from(e + "II", raw, 8 * k) for k in range(cnt)]
            else:
                val = list(struct.unpack(e + _UF[typ] * cnt, raw))
            tags[tag] = (typ, val)
        ifds.append(tags)
        nxt = struct.unpack_from(e + ("Q" if big else "I"), data, end - (8 if big else 4))[0]
    return e, big, ifds, None


def v(tags, tag, default=None):
    if tag not in tags:
        return default
    return tags[tag][1]


# Expected properties (mirrors test/fixtures/FIXTURES.md).
# per IFD: (w, h, spp, bits, sampleformat-or-None, photometric, planar-or-None,
#           compression, layout, n_chunks)
EXPECTED = {
    "gray8.tif": ("<", False, [(16, 8, 1, [8], None, 1, None, 1, "strips", 1)]),
    "rgb_contig.tif": ("<", False, [(10, 10, 3, [8, 8, 8], [1, 1, 1], 2, 1, 1, "strips", 2)]),
    "rgb_planar.tif": (">", False, [(10, 10, 3, [8, 8, 8], [1, 1, 1], 2, 2, 1, "strips", 3)]),
    "float32_sampleformat_offset.tif": ("<", False, [(4, 4, 3, [32, 32, 32], [3, 3, 3], 2, 1, 1, "strips", 1)]),
    "multi_ifd.tif": ("<", False, [
        (8, 8, 1, [8], None, 1, None, 1, "strips", 1),
        (4, 4, 1, [8], None, 1, None, 1, "strips", 1),
        (2, 2, 3, [8, 8, 8], None, 2, 1, 1, "strips", 1)]),
    "deflate.tif": ("<", False, [(8, 8, 1, [8], None, 1, None, 8, "strips", 1)]),
    "bigtiff.tif": ("<", True, [(8, 8, 1, [16], [1], 1, None, 1, "strips", 1)]),
    "bigtiff_rgb_inline.tif": ("<", True, [(4, 4, 3, [8, 8, 8], [1, 1, 1], 2, 1, 1, "strips", 1)]),
    "tiled.tif": ("<", False, [(32, 32, 1, [8], None, 1, None, 1, "tiles", 4)]),
    "gray_alpha.tif": ("<", False, [(4, 4, 2, [8, 8], None, 1, None, 1, "strips", 1)]),
    "unknown_tag.tif": ("<", False, [(16, 8, 1, [8], None, 1, None, 1, "strips", 1)]),
}

EXPECTED_ERRORS = {
    "empty.tif": "truncated",
    "not_a_tiff.tif": "not_a_tiff",
    "bad_magic.tif": "not_a_tiff",
    "truncated_header.tif": "truncated",
    "ifd_offset_out_of_range.tif": "malformed",
    "truncated_ifd.tif": "truncated",
    "huge_strip_count.tif": "limit_exceeded",
}


def verify(out_dir):
    fails = 0

    def check(cond, msg):
        nonlocal fails
        if not cond:
            fails += 1
            print("  FAIL:", msg)

    for name, (bo, big, pages) in EXPECTED.items():
        data = open(os.path.join(out_dir, name), "rb").read()
        e, isbig, ifds, warn = read_tiff(data)
        print("%-34s %5d bytes  %s %s  %d IFD(s)" % (
            name, len(data), "II" if e == "<" else "MM", "BigTIFF" if isbig else "classic", len(ifds)))
        check(e == bo and isbig == big and warn is None, name + ": header")
        check(len(ifds) == len(pages), name + ": ifd count")
        for t, (w, h, spp, bits, sf, phot, planar, comp, layout, nch) in zip(ifds, pages):
            check(v(t, 256) == [w] and v(t, 257) == [h], name + ": dims")
            check(v(t, 277) == [spp], name + ": spp")
            check(v(t, 258) == bits, name + ": bits")
            check(v(t, 339) == sf, name + ": sampleformat")
            check(v(t, 262) == [phot], name + ": photometric")
            check(v(t, 284) == ([planar] if planar else None), name + ": planar")
            check(v(t, 259) == [comp], name + ": compression")
            otag, ctag = (324, 325) if layout == "tiles" else (273, 279)
            check((322 in t) == (layout == "tiles"), name + ": layout tags")
            check((273 in t) == (layout == "strips"), name + ": layout tags")
            offs, cnts = v(t, otag), v(t, ctag)
            check(len(offs) == nch and len(cnts) == nch, name + ": chunk count")
            for o, c in zip(offs, cnts):
                check(o + c <= len(data), name + ": chunk in bounds")
            bps = sum(bits) // 8 if planar != 2 else bits[0] // 8
            if layout == "tiles":
                expect_px = v(t, 322)[0] * v(t, 323)[0] * bps * nch
            elif planar == 2:
                expect_px = w * h * bps * spp
            else:
                expect_px = w * h * bps
            if comp == 1:
                check(sum(cnts) == expect_px, name + ": uncompressed byte count")
            else:
                dec = zlib.decompress(data[offs[0]:offs[0] + cnts[0]])
                check(len(dec) == expect_px, name + ": deflate decodes to w*h")
        t0 = ifds[0]
        if name in ("gray8.tif", "unknown_tag.tif"):
            check(v(t0, 270) == "gray8 fixture", name + ": description")
            check(v(t0, 282) == [(72, 1)] and v(t0, 283) == [(72, 1)], name + ": resolution")
            check(v(t0, 296) == [2], name + ": resunit")
        if name == "unknown_tag.tif":
            check(v(t0, 65000) == "hello private tag", name + ": tag 65000")
            check(v(t0, 65001) == list(range(100)), name + ": tag 65001")
        if name == "gray_alpha.tif":
            check(v(t0, 338) == [2], name + ": extrasamples")
            # BitsPerSample must be inline: value field == 08 00 08 00
            check(b"\x02\x01\x03\x00\x02\x00\x00\x00\x08\x00\x08\x00" in data, name + ": bps inline")
        if name == "bigtiff.tif":
            check(data[2:4] == b"\x2b\x00", name + ": magic 43")
            # StripOffsets entry type must be LONG8 (16)
            check(struct.pack("<HHQ", 273, 16, 1) in data, name + ": LONG8 offsets")
        if name == "bigtiff_rgb_inline.tif":
            check(data[2:4] == b"\x2b\x00", name + ": magic 43")
            # BitsPerSample and SampleFormat must be inline in the 8-byte field
            check(struct.pack("<HHQ", 258, 3, 3) + b"\x08\x00\x08\x00\x08\x00\x00\x00" in data,
                  name + ": bps inline")
            check(struct.pack("<HHQ", 339, 3, 3) + b"\x01\x00\x01\x00\x01\x00\x00\x00" in data,
                  name + ": sampleformat inline")

    for name, cat in EXPECTED_ERRORS.items():
        data = open(os.path.join(out_dir, name), "rb").read()
        try:
            read_tiff(data)
            got = "ok"
        except ReadError as ex:
            got = str(ex)
        print("%-34s %5d bytes  -> %s" % (name, len(data), got))
        check(got == cat, "%s: expected %s got %s" % (name, cat, got))

    # malformed-but-parsable cases
    data = open(os.path.join(out_dir, "strip_out_of_bounds.tif"), "rb").read()
    _, _, ifds, _ = read_tiff(data)
    o, c = v(ifds[0], 273)[0], v(ifds[0], 279)[0]
    print("%-34s %5d bytes  -> strip %d+%d > %d" % ("strip_out_of_bounds.tif", len(data), o, c, len(data)))
    check(o + c > len(data) and o < len(data), "strip_out_of_bounds: strip should overrun EOF")

    data = open(os.path.join(out_dir, "ifd_loop.tif"), "rb").read()
    _, _, ifds, warn = read_tiff(data)
    print("%-34s %5d bytes  -> %d IFD, %s" % ("ifd_loop.tif", len(data), len(ifds), warn))
    check(len(ifds) == 1 and warn == "ifd_loop", "ifd_loop: expected 1 IFD + loop")

    data = open(os.path.join(out_dir, "unknown_field_type.tif"), "rb").read()
    _, _, ifds, warn = read_tiff(data)
    print("%-34s %5d bytes  -> tag 65002 %s" % ("unknown_field_type.tif", len(data), ifds[0].get(65002)))
    check(ifds[0].get(65002) == ("unknown_type", 99, 1), "unknown_field_type: tag 65002 type 99")
    check(v(ifds[0], 256) == [16], "unknown_field_type: rest of IFD parses")

    print("verify: %s (%d failure(s))" % ("OK" if fails == 0 else "FAILED", fails))
    return fails == 0


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    out_dir = args[0] if args else "test/fixtures"
    os.makedirs(out_dir, exist_ok=True)
    fx = build_fixtures()
    for name in sorted(fx):
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(fx[name])
        print("%-34s %5d bytes  sha256 %s" % (
            name, len(fx[name]), hashlib.sha256(fx[name]).hexdigest()[:16]))
    if "--verify" in argv:
        return 0 if verify(out_dir) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
