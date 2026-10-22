(* Names for tag IDs, field types and coded values. Each coded value has a
   stable snake_case name (used in JSON) and a human-readable label. *)

let tags =
  [
    (254, "NewSubfileType");
    (255, "SubfileType");
    (256, "ImageWidth");
    (257, "ImageLength");
    (258, "BitsPerSample");
    (259, "Compression");
    (262, "PhotometricInterpretation");
    (263, "Threshholding");
    (266, "FillOrder");
    (269, "DocumentName");
    (270, "ImageDescription");
    (271, "Make");
    (272, "Model");
    (273, "StripOffsets");
    (274, "Orientation");
    (277, "SamplesPerPixel");
    (278, "RowsPerStrip");
    (279, "StripByteCounts");
    (280, "MinSampleValue");
    (281, "MaxSampleValue");
    (282, "XResolution");
    (283, "YResolution");
    (284, "PlanarConfiguration");
    (285, "PageName");
    (286, "XPosition");
    (287, "YPosition");
    (296, "ResolutionUnit");
    (297, "PageNumber");
    (301, "TransferFunction");
    (305, "Software");
    (306, "DateTime");
    (315, "Artist");
    (316, "HostComputer");
    (317, "Predictor");
    (318, "WhitePoint");
    (319, "PrimaryChromaticities");
    (320, "ColorMap");
    (321, "HalftoneHints");
    (322, "TileWidth");
    (323, "TileLength");
    (324, "TileOffsets");
    (325, "TileByteCounts");
    (330, "SubIFDs");
    (332, "InkSet");
    (338, "ExtraSamples");
    (339, "SampleFormat");
    (340, "SMinSampleValue");
    (341, "SMaxSampleValue");
    (347, "JPEGTables");
    (530, "YCbCrSubSampling");
    (531, "YCbCrPositioning");
    (532, "ReferenceBlackWhite");
    (700, "XMP");
    (33432, "Copyright");
    (33550, "ModelPixelScale");
    (33723, "IPTC");
    (33922, "ModelTiepoint");
    (34264, "ModelTransformation");
    (34377, "Photoshop");
    (34665, "ExifIFD");
    (34675, "ICCProfile");
    (34735, "GeoKeyDirectory");
    (34736, "GeoDoubleParams");
    (34737, "GeoAsciiParams");
    (34853, "GPSIFD");
    (42112, "GDAL_METADATA");
    (42113, "GDAL_NODATA");
  ]

let tag_name id = List.assoc_opt id tags

(* Field types: code, name, size in bytes *)
let field_types =
  [
    (1, "byte", 1);
    (2, "ascii", 1);
    (3, "short", 2);
    (4, "long", 4);
    (5, "rational", 8);
    (6, "sbyte", 1);
    (7, "undefined", 1);
    (8, "sshort", 2);
    (9, "slong", 4);
    (10, "srational", 8);
    (11, "float", 4);
    (12, "double", 8);
    (13, "ifd", 4);
    (16, "long8", 8);
    (17, "slong8", 8);
    (18, "ifd8", 8);
  ]

let field_type_name code =
  List.find_map (fun (c, n, _) -> if c = code then Some n else None) field_types

let field_type_size code =
  List.find_map (fun (c, _, s) -> if c = code then Some s else None) field_types

type coded = (int * string * string) list

let compression : coded =
  [
    (1, "none", "None");
    (2, "ccitt_rle", "CCITT RLE");
    (3, "ccitt_t4", "CCITT T.4");
    (4, "ccitt_t6", "CCITT T.6");
    (5, "lzw", "LZW");
    (6, "ojpeg", "Old-style JPEG");
    (7, "jpeg", "JPEG");
    (8, "adobe_deflate", "Deflate (Adobe)");
    (32773, "packbits", "PackBits");
    (32946, "deflate", "Deflate");
    (34887, "lerc", "LERC");
    (34925, "lzma", "LZMA");
    (50000, "zstd", "Zstandard");
    (50001, "webp", "WebP");
  ]

let photometric : coded =
  [
    (0, "white_is_zero", "WhiteIsZero");
    (1, "black_is_zero", "BlackIsZero");
    (2, "rgb", "RGB");
    (3, "palette", "Palette");
    (4, "transparency_mask", "Transparency mask");
    (5, "separated", "Separated (CMYK)");
    (6, "ycbcr", "YCbCr");
    (8, "cielab", "CIE L*a*b*");
    (9, "icclab", "ICC L*a*b*");
    (10, "itulab", "ITU L*a*b*");
    (32844, "logl", "LogL");
    (32845, "logluv", "LogLuv");
  ]

let planar : coded =
  [ (1, "contiguous", "Contiguous (chunky)"); (2, "separate", "Separate") ]

let sample_format : coded =
  [
    (1, "unsigned_integer", "Unsigned integer");
    (2, "signed_integer", "Signed integer");
    (3, "ieee_float", "IEEE floating point");
    (4, "undefined", "Undefined");
    (5, "complex_integer", "Complex integer");
    (6, "complex_float", "Complex floating point");
  ]

let predictor : coded =
  [
    (1, "none", "None");
    (2, "horizontal_differencing", "Horizontal differencing");
    (3, "floating_point", "Floating point");
  ]

let orientation : coded =
  [
    (1, "top_left", "Top-left");
    (2, "top_right", "Top-right");
    (3, "bottom_right", "Bottom-right");
    (4, "bottom_left", "Bottom-left");
    (5, "left_top", "Left-top");
    (6, "right_top", "Right-top");
    (7, "right_bottom", "Right-bottom");
    (8, "left_bottom", "Left-bottom");
  ]

let resolution_unit : coded =
  [
    (1, "none", "No absolute unit");
    (2, "inch", "Inch");
    (3, "centimeter", "Centimeter");
  ]

let name (table : coded) code =
  List.find_map (fun (c, n, _) -> if c = code then Some n else None) table

let label (table : coded) code =
  List.find_map (fun (c, _, l) -> if c = code then Some l else None) table
