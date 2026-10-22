/** TIFF files bundled with the playground (copies of test/fixtures). */
export const SAMPLES: { name: string; about: string }[] = [
  { name: "gray8.tif", about: "16×8 baseline grayscale, one strip" },
  { name: "rgb_contig.tif", about: "10×10 chunky RGB, two strips" },
  { name: "multi_ifd.tif", about: "three directories of different shapes" },
  { name: "deflate.tif", about: "8×8 grayscale, Adobe Deflate compression" },
  { name: "bigtiff.tif", about: "8×8 16-bit BigTIFF" },
  { name: "tiled.tif", about: "32×32 grayscale in 16×16 tiles" },
  { name: "bad_magic.tif", about: "not a TIFF: wrong signature" },
];
