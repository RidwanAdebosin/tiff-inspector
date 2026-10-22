# CLI reference

```
tiff-inspector inspect [OPTION]… FILE
```

| Option | Description |
|---|---|
| `-f`, `--format text\|json` | Output format (default `text`). |
| `-t`, `--tags` | Include the full tag table (text format). |
| `--ifd N` | Only show directory `N`. In text output only that directory's section is printed; in JSON output the `directories` array holds only that directory (`ifd_count` still counts all of them). `N` outside `0 .. ifd_count-1` is a usage error (exit 2). |
| `--max-ifds N` | Stop after `N` directories (default 1024, at least 1). |
| `--debug` | Print internal exception details to stderr. |
| `--version`, `--help` | |

## Output

- **Text** goes to stdout. Values not read directly from the file are marked:
  `(default, tag absent)`, `unknown (tag absent)`, `unsupported - <reason>`.
- **JSON** goes to stdout and follows
  [`schema/inspection-report.v1.json`](../schema/inspection-report.v1.json).
  It is written on failure too (`"ok": false` with `error.code`), so scripts
  can always parse stdout.
- Diagnostics go to stderr.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Inspection succeeded (warnings may be present) |
| 1 | Inspection failed (see `error.code`) |
| 2 | Invalid arguments or options (including `--ifd N` for a directory the file does not have, and `--max-ifds 0`) |

## Error codes

| Code | Meaning |
|---|---|
| `file_not_found` | The path does not exist. |
| `file_unreadable` | Permission denied, or not a regular file. |
| `not_a_tiff` | Empty file, or no `II*`/`MM*`/`II+`/`MM+` signature. |
| `truncated` | The file ends before data the header or an IFD refers to. |
| `malformed` | Structurally invalid: an offset outside the file, impossible counts, an IFD loop in the first directory. |
| `unsupported_feature` | Valid TIFF that ocaml-tiff cannot parse (for example an unknown field type). |
| `limit_exceeded` | Memory/time limit hit. |
| `internal` | Bug in tiff-inspector. Please report it with the file if you can. |

## Examples

```sh
tiff-inspector inspect image.tif
tiff-inspector inspect --tags --ifd 1 scan.tif
tiff-inspector inspect --format json image.tif | jq '.directories[].sample_format'
tiff-inspector inspect --format json --ifd 2 pyramid.tif | jq '.directories[0].layout'
for f in *.tif; do tiff-inspector inspect -f json "$f" > "$f.json" || echo "failed: $f"; done
```
