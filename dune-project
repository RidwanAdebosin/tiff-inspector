(lang dune 3.9)

(name tiff-inspector)

(generate_opam_files true)

(license MIT)

(authors "TIFF Inspector contributors")

(maintainers "TIFF Inspector contributors")

(source
 (github tiff-inspector/tiff-inspector))

(package
 (name tiff-inspector)
 (synopsis "Inspect TIFF metadata, directories, samples and planes")
 (description
  "A CLI and HTTP API for inspecting TIFF files, built on geocaml/ocaml-tiff (vendored).")
 (depends
  (ocaml
   (>= 5.1))
  (dune
   (>= 3.9))
  (cmdliner
   (>= 1.3))
  (yojson
   (>= 2.0))
  fmt
  cstruct
  optint
  bstr
  (decompress
   (>= 1.6.0))
  eio_main
  cohttp-eio
  (alcotest :with-test)
  (ocamlformat
   (and
    (= 0.29.0)
    :with-dev-setup))))
