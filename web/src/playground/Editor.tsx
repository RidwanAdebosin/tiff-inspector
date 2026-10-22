import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "@codemirror/commands";
import {
  StreamLanguage,
  bracketMatching,
  indentOnInput,
} from "@codemirror/language";
import { oCaml } from "@codemirror/legacy-modes/mode/mllike";
import { lintGutter, setDiagnostics, type Diagnostic } from "@codemirror/lint";
import { Compartment, EditorState } from "@codemirror/state";
import { oneDark } from "@codemirror/theme-one-dark";
import {
  EditorView,
  highlightActiveLine,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { useEffect, useRef } from "react";
import type { Problem } from "./protocol";

type EditorProps = {
  value: string;
  onChange: (value: string) => void;
  onRun: () => void;
  problems: Problem[];
  label: string;
  /** id of an element describing the editor, e.g. how to leave it with the keyboard. */
  describedBy?: string;
};

const darkQuery = "(prefers-color-scheme: dark)";

const baseTheme = EditorView.theme({
  "&": { fontSize: "0.8125rem", height: "100%" },
  ".cm-scroller": {
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
    lineHeight: "1.5",
  },
  ".cm-content": { padding: "0.75rem 0" },
});

const lightTheme = EditorView.theme(
  { "&": { backgroundColor: "white" } },
  { dark: false },
);

function toDiagnostics(state: EditorState, problems: Problem[]): Diagnostic[] {
  const out: Diagnostic[] = [];
  for (const p of problems) {
    if (p.line > state.doc.lines) continue;
    const start = state.doc.line(p.line);
    const end = state.doc.line(Math.min(p.endLine, state.doc.lines));
    const from = Math.min(start.from + p.col, start.to);
    const to = Math.max(from, Math.min(end.from + p.endCol, end.to));
    out.push({ from, to, severity: "error", message: p.message });
  }
  return out;
}

/** A CodeMirror editor with OCaml highlighting; Mod-Enter runs the code. */
export function Editor({
  value,
  onChange,
  onRun,
  problems,
  label,
  describedBy,
}: EditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const onChangeRef = useRef(onChange);
  const onRunRef = useRef(onRun);
  useEffect(() => {
    onChangeRef.current = onChange;
    onRunRef.current = onRun;
  });

  useEffect(() => {
    if (!host.current) return;
    const theme = new Compartment();
    const media = window.matchMedia(darkQuery);
    const pick = (dark: boolean) => (dark ? oneDark : lightTheme);
    const v = new EditorView({
      parent: host.current,
      state: EditorState.create({
        doc: value,
        extensions: [
          lineNumbers(),
          history(),
          highlightActiveLine(),
          bracketMatching(),
          indentOnInput(),
          lintGutter(),
          StreamLanguage.define(oCaml),
          keymap.of([
            { key: "Mod-Enter", run: () => (onRunRef.current(), true) },
            indentWithTab,
            ...defaultKeymap,
            ...historyKeymap,
          ]),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onChangeRef.current(u.state.doc.toString());
          }),
          EditorView.contentAttributes.of({
            "aria-label": label,
            ...(describedBy ? { "aria-describedby": describedBy } : {}),
          }),
          baseTheme,
          theme.of(pick(media.matches)),
        ],
      }),
    });
    const onMedia = (e: MediaQueryListEvent) =>
      v.dispatch({ effects: theme.reconfigure(pick(e.matches)) });
    media.addEventListener("change", onMedia);
    view.current = v;
    return () => {
      media.removeEventListener("change", onMedia);
      v.destroy();
      view.current = null;
    };
    // The editor owns the document after mount; `value` changes arrive below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const v = view.current;
    if (!v) return;
    const current = v.state.doc.toString();
    if (current !== value) {
      v.dispatch({ changes: { from: 0, to: current.length, insert: value } });
    }
  }, [value]);

  useEffect(() => {
    const v = view.current;
    if (!v) return;
    v.dispatch(setDiagnostics(v.state, toDiagnostics(v.state, problems)));
  }, [problems]);

  return <div ref={host} className="h-full min-h-[20rem] overflow-hidden" />;
}
