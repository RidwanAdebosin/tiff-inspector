// JavaScript implementations of the C primitives used by bstr and checkseum.
// Only the bytecode variants are needed: js_of_ocaml compiles bytecode.
// Bigstrings are js_of_ocaml bigarrays; caml_ba_get_1/caml_ba_set_1 index
// them by element.

//Provides: bstr_bytecode_ptr
function bstr_bytecode_ptr(b) { return 0; }

//Provides: bstr_bytecode_memcmp
//Requires: caml_ba_get_1
function bstr_bytecode_memcmp(a, aoff, b, boff, len) {
  for (var i = 0; i < len; i++) {
    var x = caml_ba_get_1(a, aoff + i), y = caml_ba_get_1(b, boff + i);
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

//Provides: bstr_bytecode_memcpy
//Requires: caml_ba_get_1, caml_ba_set_1
function bstr_bytecode_memcpy(src, soff, dst, doff, len) {
  for (var i = 0; i < len; i++) caml_ba_set_1(dst, doff + i, caml_ba_get_1(src, soff + i));
  return 0;
}

//Provides: bstr_bytecode_memmove
//Requires: caml_ba_get_1, caml_ba_set_1
function bstr_bytecode_memmove(src, soff, dst, doff, len) {
  if (src === dst && soff < doff) {
    for (var i = len - 1; i >= 0; i--) caml_ba_set_1(dst, doff + i, caml_ba_get_1(src, soff + i));
  } else {
    for (var j = 0; j < len; j++) caml_ba_set_1(dst, doff + j, caml_ba_get_1(src, soff + j));
  }
  return 0;
}

//Provides: bstr_bytecode_memset
//Requires: caml_ba_set_1
function bstr_bytecode_memset(b, off, c, len) {
  for (var i = 0; i < len; i++) caml_ba_set_1(b, off + i, c & 0xff);
  return 0;
}

//Provides: bstr_bytecode_memchr
//Requires: caml_ba_get_1
function bstr_bytecode_memchr(b, off, c, len) {
  for (var i = 0; i < len; i++) if (caml_ba_get_1(b, off + i) === (c & 0xff)) return off + i;
  return -1;
}

//Provides: bstr_bytecode_get64u
//Requires: caml_ba_get_1, caml_int64_of_bytes
function bstr_bytecode_get64u(b, off) {
  // Little-endian on every platform js_of_ocaml runs on.
  var bytes = new Array(8);
  for (var i = 0; i < 8; i++) bytes[7 - i] = caml_ba_get_1(b, off + i);
  return caml_int64_of_bytes(bytes);
}

//Provides: bstr_bytecode_unsafe_sub
//Requires: caml_ba_sub
function bstr_bytecode_unsafe_sub(b, off, len) { return caml_ba_sub(b, off, len); }

//Provides: bstr_bytecode_unsafe_blit_to_bytes
//Requires: caml_ba_get_1, caml_bytes_unsafe_set
function bstr_bytecode_unsafe_blit_to_bytes(src, soff, dst, doff, len) {
  for (var i = 0; i < len; i++) caml_bytes_unsafe_set(dst, doff + i, caml_ba_get_1(src, soff + i));
  return 0;
}

//Provides: bstr_bytecode_unsafe_blit_from_bytes
//Requires: caml_ba_set_1, caml_bytes_unsafe_get
function bstr_bytecode_unsafe_blit_from_bytes(src, soff, dst, doff, len) {
  for (var i = 0; i < len; i++) caml_ba_set_1(dst, doff + i, caml_bytes_unsafe_get(src, soff + i));
  return 0;
}

//Provides: caml_checkseum_adler32_ba
//Requires: caml_ba_get_1
function caml_checkseum_adler32_ba(adler, ba, off, len) {
  var a = adler & 0xffff, b = (adler >>> 16) & 0xffff;
  for (var i = 0; i < len; i++) {
    a = (a + caml_ba_get_1(ba, off + i)) % 65521;
    b = (b + a) % 65521;
  }
  return ((b << 16) | a) | 0;
}
