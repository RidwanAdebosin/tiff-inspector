// Web worker hosting the OCaml toplevel. Plain JavaScript (not bundled by
// Vite) so that it can importScripts the toplevel bundle. Messages:
//   in : {type:"init", bundle, samples:[{name, bytes}]} | {type:"run", id, code}
//   out: {type:"ready", version} | {type:"result", id, chunks, locations, passed, failed}
//        | {type:"fatal", message}
var chunks = [];
var locations = [];
var breakNext = false;

function sink(kind, text) {
  if (kind === "location") {
    locations.push({ loc: text, chunkIndex: chunks.length });
    breakNext = true;
    return;
  }
  var last = chunks[chunks.length - 1];
  if (last && last.kind === kind && !breakNext) last.text += text;
  else chunks.push({ kind: kind, text: text });
  breakNext = false;
}

self.onmessage = function (e) {
  var msg = e.data;
  if (msg.type === "init") {
    try {
      importScripts(msg.bundle);
    } catch (err) {
      postMessage({ type: "fatal", message: "Could not load " + msg.bundle + ": " + (err && err.message ? err.message : String(err)) });
      return;
    }
    var P = self.ocamlPlayground;
    if (!P) {
      postMessage({ type: "fatal", message: "The toplevel bundle did not register ocamlPlayground" });
      return;
    }
    P.setSink(sink);
    for (var i = 0; i < msg.samples.length; i++) P.registerSample(msg.samples[i].name, new Uint8Array(msg.samples[i].bytes));
    postMessage({ type: "ready", version: P.version });
  } else if (msg.type === "run") {
    chunks = [];
    locations = [];
    breakNext = false;
    var counts = { passed: 0, failed: 0 };
    try {
      counts = self.ocamlPlayground.execute(msg.code);
    } catch (err) {
      sink("stderr", "Fatal error: " + (err && err.message ? err.message : String(err)) + "\n");
    }
    postMessage({ type: "result", id: msg.id, chunks: chunks, locations: locations, passed: counts.passed, failed: counts.failed });
  }
};
