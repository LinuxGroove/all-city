"""Writes (and reads back) Godot 4's binary Variant format, the bytes
`bytes_to_var()` takes, so a tile decodes in the game straight into
Dictionaries and packed arrays with no parsing.

Python values map to Godot types like this:
- None, bool, int, float, str, dict, list: Nil, bool, int, float, String,
  Dictionary, Array
- bytes: PackedByteArray
- numpy arrays: float32 1-D PackedFloat32Array, (n, 2) PackedVector2Array,
  (n, 3) PackedVector3Array; int32 PackedInt32Array; int64 PackedInt64Array;
  float64 PackedFloat64Array; uint8 PackedByteArray
"""
import struct

import numpy as np

NIL, BOOL, INT, FLOAT, STRING = 0, 1, 2, 3, 4
VECTOR2, VECTOR3 = 5, 9
DICTIONARY, ARRAY = 27, 28
PACKED_BYTE, PACKED_INT32, PACKED_INT64 = 29, 30, 31
PACKED_FLOAT32, PACKED_FLOAT64 = 32, 33
PACKED_VECTOR2, PACKED_VECTOR3 = 35, 36
FLAG_64 = 1 << 16


def _pad(n):
    return b"\0" * ((4 - n % 4) % 4)


def encode(value) -> bytes:
    out = bytearray()
    _encode(value, out)
    return bytes(out)


def _encode(v, out: bytearray):
    if v is None:
        out += struct.pack("<I", NIL)
    elif isinstance(v, (bool, np.bool_)):
        out += struct.pack("<II", BOOL, 1 if v else 0)
    elif isinstance(v, (int, np.integer)):
        v = int(v)
        if -2**31 <= v < 2**31:
            out += struct.pack("<Ii", INT, v)
        else:
            out += struct.pack("<Iq", INT | FLAG_64, v)
    elif isinstance(v, (float, np.floating)):
        v = float(v)
        if float(np.float32(v)) == v:
            out += struct.pack("<If", FLOAT, v)
        else:
            out += struct.pack("<Id", FLOAT | FLAG_64, v)
    elif isinstance(v, str):
        b = v.encode("utf-8")
        out += struct.pack("<II", STRING, len(b)) + b + _pad(len(b))
    elif isinstance(v, (bytes, bytearray)):
        out += struct.pack("<II", PACKED_BYTE, len(v)) + bytes(v) + _pad(len(v))
    elif isinstance(v, dict):
        out += struct.pack("<II", DICTIONARY, len(v))
        for k, val in v.items():
            _encode(k, out)
            _encode(val, out)
    elif isinstance(v, (list, tuple)):
        out += struct.pack("<II", ARRAY, len(v))
        for item in v:
            _encode(item, out)
    elif isinstance(v, np.ndarray):
        _encode_array(v, out)
    else:
        raise TypeError("can't encode %r for Godot" % type(v))


def _encode_array(a: np.ndarray, out: bytearray):
    if a.dtype == np.float32:
        if a.ndim == 2 and a.shape[1] == 3:
            out += struct.pack("<II", PACKED_VECTOR3, a.shape[0])
        elif a.ndim == 2 and a.shape[1] == 2:
            out += struct.pack("<II", PACKED_VECTOR2, a.shape[0])
        elif a.ndim == 1:
            out += struct.pack("<II", PACKED_FLOAT32, a.shape[0])
        else:
            raise TypeError("float32 arrays must be 1-D, (n, 2) or (n, 3)")
        out += np.ascontiguousarray(a, dtype="<f4").tobytes()
    elif a.dtype == np.int32:
        out += struct.pack("<II", PACKED_INT32, a.size) + np.ascontiguousarray(a.ravel(), dtype="<i4").tobytes()
    elif a.dtype == np.int64:
        out += struct.pack("<II", PACKED_INT64, a.size) + np.ascontiguousarray(a.ravel(), dtype="<i8").tobytes()
    elif a.dtype == np.float64:
        out += struct.pack("<II", PACKED_FLOAT64, a.size) + np.ascontiguousarray(a.ravel(), dtype="<f8").tobytes()
    elif a.dtype == np.uint8:
        b = a.ravel().tobytes()
        out += struct.pack("<II", PACKED_BYTE, len(b)) + b + _pad(len(b))
    else:
        raise TypeError("can't encode numpy %s for Godot" % a.dtype)


def decode(data: bytes):
    """Reads what encode() writes (for tests and the info command)."""
    v, _ = _decode(memoryview(data), 0)
    return v


def _decode(m, i):
    (header,) = struct.unpack_from("<I", m, i)
    i += 4
    t = header & 0xFFFF
    wide = bool(header & FLAG_64)
    if t == NIL:
        return None, i
    if t == BOOL:
        return struct.unpack_from("<I", m, i)[0] != 0, i + 4
    if t == INT:
        if wide:
            return struct.unpack_from("<q", m, i)[0], i + 8
        return struct.unpack_from("<i", m, i)[0], i + 4
    if t == FLOAT:
        if wide:
            return struct.unpack_from("<d", m, i)[0], i + 8
        return struct.unpack_from("<f", m, i)[0], i + 4
    if t == STRING:
        (n,) = struct.unpack_from("<I", m, i)
        s = bytes(m[i + 4:i + 4 + n]).decode("utf-8")
        return s, i + 4 + n + (4 - n % 4) % 4
    if t == DICTIONARY:
        (n,) = struct.unpack_from("<I", m, i)
        i += 4
        d = {}
        for _ in range(n & 0x7FFFFFFF):
            k, i = _decode(m, i)
            v, i = _decode(m, i)
            d[k] = v
        return d, i
    if t == ARRAY:
        (n,) = struct.unpack_from("<I", m, i)
        i += 4
        a = []
        for _ in range(n & 0x7FFFFFFF):
            v, i = _decode(m, i)
            a.append(v)
        return a, i
    (n,) = struct.unpack_from("<I", m, i)
    i += 4
    if t == PACKED_BYTE:
        return bytes(m[i:i + n]), i + n + (4 - n % 4) % 4
    sizes = {PACKED_INT32: ("<i4", 1), PACKED_INT64: ("<i8", 1), PACKED_FLOAT32: ("<f4", 1),
             PACKED_FLOAT64: ("<f8", 1), PACKED_VECTOR2: ("<f4", 2), PACKED_VECTOR3: ("<f4", 3)}
    if t not in sizes:
        raise ValueError("unsupported Godot type %d" % t)
    dt, width = sizes[t]
    count = n * width
    a = np.frombuffer(m, dtype=dt, count=count, offset=i).copy()
    if width > 1:
        a = a.reshape(n, width)
    return a, i + count * np.dtype(dt).itemsize
