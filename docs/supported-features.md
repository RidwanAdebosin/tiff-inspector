# Supported features

What version 0.1.0 can tell you, and where it stops. "Fixture" means there
is a regression fixture in `test/fixtures`.

## File structure

| Feature | Status |
|---|---|
| Classic TIFF, little and big endian | ✅ fixtures |
| BigTIFF | ✅ fixture |
| Multiple IFDs (main chain) | ✅ fixture. Loops are detected; stops at 1024 |
| SubIFDs, EXIF IFD, GPS IFD | ❌ not traversed (tags are listed with their offsets) |
| Strips | ✅ count, expected count, offsets, byte counts, bounds check |
| Tiles | ✅ fixture |

## Interpreted properties

| Property | Notes |
|---|---|
| Width, height | Required. A missing one is a warning. |
| SamplesPerPixel | Default 1 |
| BitsPerSample, per sample | Default 1 per sample. Multi-value inline values are decoded correctly, in classic TIFF and BigTIFF (fixtures). |
| SampleFormat, per sample | Default 1. Offset-stored values are supported (fixture). Mixed formats produce a warning. |
| Photometric interpretation | No default. Reported absent when missing. |
| Planar configuration | Default 1. Planes are derived (one per sample when separate). |
| Compression, predictor | Reported for any code. Unknown codes are shown as "Unknown (code n)". |
| Orientation, resolution and unit | Defaults 1 / – / inch |
| All tags | ID, name (≈70 known tags), field type, count, decoded value (64 values / 4096 ASCII bytes max) |

## Pixel data

Pixel decoding is **not** performed in v1. `pixel_decoding.library_support`
is a static assessment of whether ocaml-tiff's decoder would handle the
directory:

- strips with no compression, LZW or Deflate;
- tiles with no compression;
- predictor 1 or 2;
- 8/16/32/64-bit samples;
- a single sample format.

## Known limitations

- A directory with an entry of unknown field type cannot be parsed by
  ocaml-tiff; the inspection fails with `unsupported_feature`.
- ocaml-tiff's `Ifd.bits_per_sample` misreads multi-value inline entries;
  the inspector reports it as a `library_error` or `library_mismatch`
  warning (fixtures `gray_alpha.tif`, `bigtiff_rgb_inline.tif`) and uses its
  own decoding, which reads the value field directly.
- Classic TIFF files larger than 2 GiB: the inspector reads IFD and value
  offsets of 2 GiB and above correctly, but ocaml-tiff sign-extends them
  when it loads a directory. A directory whose StripOffsets/StripByteCounts
  arrays are stored out of line beyond 2 GiB therefore fails with
  `truncated` (`ifd_walk_failed`); files whose directories are within the
  first 2 GiB, or with a single strip, are fine.
