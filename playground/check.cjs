// End-to-end check of the playground bundle through the real worker script,
// run under Node with a fake worker global. Usage:
//   node check.cjs <top.bc.js> <worker.js> <fixtures-dir>
const fs = require("fs");
const path = require("path");

const [bundle, workerJs, fixtures] = process.argv.slice(2).map((p) => path.resolve(p));
const posted = [];
globalThis.self = globalThis;
globalThis.postMessage = (m) => posted.push(m);
globalThis.importScripts = (url) => {
  if (url !== "bundle") throw new Error("unexpected importScripts " + url);
  const m = require(bundle);
  globalThis.ocamlPlayground = m.ocamlPlayground || globalThis.ocamlPlayground;
};
new Function(fs.readFileSync(workerJs, "utf8"))();

let failures = 0;
const assert = (cond, what) => {
  if (!cond) {
    failures++;
    console.error("FAIL " + what);
  } else console.log("ok   " + what);
};
const send = (data) => self.onmessage({ data });
const run = (code) => {
  posted.length = 0;
  send({ type: "run", id: 1, code });
  return posted[0];
};
const text = (r, kind) => r.chunks.filter((c) => c.kind === kind).map((c) => c.text).join("");

const sample = (name) => ({ name, bytes: new Uint8Array(fs.readFileSync(path.join(fixtures, name))).buffer });
send({ type: "init", bundle: "bundle", samples: [sample("gray8.tif"), sample("deflate.tif"), sample("bad_magic.tif")] });
assert(posted[0] && posted[0].type === "ready", "worker becomes ready: " + JSON.stringify(posted[0]));

let r = run('let x = 1 + 1;;\nprint_string "hello";;\nlet y : int = "oops";;');
assert(r.type === "result", "run returns a result");
assert(/val x : int = 2/.test(text(r, "answer")), "answers are coalesced: " + JSON.stringify(text(r, "answer")));
assert(text(r, "stdout") === "hello", "stdout is captured");
assert(/Error: This constant has type string/.test(text(r, "stderr")), "type errors go to stderr");
assert(r.locations.length === 1 && r.locations[0].loc === "3:14:3:20", "error location is reported: " + JSON.stringify(r.locations));
assert(r.chunks[r.locations[0].chunkIndex].kind === "stderr", "location points at its error chunk");

r = run('Test.int "width" ~expected:16 (Tiff.Ifd.width (Tiff.ifd (Tiff.from_file (Tiff.as_kind Tiff.Uint8) (Sample.reader "gray8.tif"))));;\nTest.check "wrong" false;;');
assert(r.passed === 1 && r.failed === 1, "test counts: " + JSON.stringify([r.passed, r.failed]));
assert(/PASS width\nFAIL wrong\n/.test(text(r, "stdout")), "check lines are printed");

r = run('match Sample.inspect "deflate.tif" with Ok rep -> rep.ifd_count | Error _ -> -1;;');
assert(/= 1\n/.test(text(r, "answer")), "the inspector core runs on a sample");

r = run('match Sample.inspect "bad_magic.tif" with Ok _ -> "ok" | Error f -> f.error.message;;');
assert(/TIFF signature/.test(text(r, "answer")), "malformed samples report an error");

r = run('Sample.get "nope";;');
assert(/Exception:[\s\S]*no sample named/.test(text(r, "answer")), "runtime exceptions are shown");

r = run(`(* no ;; anywhere, like the examples *)
let greet name = Printf.sprintf "Hello, %s!" name

let () = print_endline (greet "world")

let squares = List.init 6 (fun i -> i * i)
let total = List.fold_left ( + ) 0 squares
`);
assert(r.locations.length === 0 && text(r, "stderr") === "", "code without ;; runs: " + JSON.stringify(text(r, "stderr")));
assert(text(r, "stdout") === "Hello, world!\n", "its prints arrive");
assert(/val total : int = 55/.test(text(r, "answer")), "and every definition is echoed");

r = run("let before = 1\nlet broken : int = \"no\"\nlet after = 2;;");
assert(r.locations.length === 1 && r.locations[0].loc === "2:19:2:23", "error located without ;;: " + JSON.stringify(r.locations));
assert(/val before : int = 1/.test(text(r, "answer")) && !/after/.test(text(r, "answer")), "runs up to the error, then stops");
r = run("before + 1;;");
assert(/= 2/.test(text(r, "answer")), "definitions before the error survive");

r = run("let z = x + 40;;");
assert(/val z : int = 42/.test(text(r, "answer")), "definitions persist between runs");

if (failures) {
  console.error(failures + " check(s) failed");
  process.exit(1);
}
console.log("all playground checks passed");
