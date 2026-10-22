import { useRef, type KeyboardEvent } from "react";
import type { Directory } from "../api/types";
import { directoryDimensions, panelId, tabId } from "../lib/directory";

type IfdTabsProps = {
  directories: Directory[];
  selected: number;
  onSelect: (position: number) => void;
  idPrefix: string;
};

/**
 * WAI-ARIA tabs with a roving tabindex: Arrow keys move between directories,
 * Home/End jump to the first/last; selection follows focus.
 */
export function IfdTabs({
  directories,
  selected,
  onSelect,
  idPrefix,
}: IfdTabsProps) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);

  const move = (to: number) => {
    const n = directories.length;
    const next = ((to % n) + n) % n;
    onSelect(next);
    refs.current[next]?.focus();
  };

  const onKeyDown = (e: KeyboardEvent) => {
    const keys: Record<string, () => void> = {
      ArrowRight: () => move(selected + 1),
      ArrowDown: () => move(selected + 1),
      ArrowLeft: () => move(selected - 1),
      ArrowUp: () => move(selected - 1),
      Home: () => move(0),
      End: () => move(directories.length - 1),
    };
    const action = keys[e.key];
    if (action) {
      e.preventDefault();
      action();
    }
  };

  return (
    <div
      role="tablist"
      aria-label="Image file directories"
      className="flex gap-2 overflow-x-auto pb-1"
      onKeyDown={onKeyDown}
    >
      {directories.map((dir, i) => {
        const active = i === selected;
        return (
          <button
            key={dir.index}
            ref={(el) => {
              refs.current[i] = el;
            }}
            id={tabId(idPrefix, i)}
            type="button"
            role="tab"
            aria-selected={active}
            aria-controls={panelId(idPrefix)}
            tabIndex={active ? 0 : -1}
            onClick={() => onSelect(i)}
            className={`shrink-0 rounded-md border px-3 py-2 text-left text-sm transition-colors ${
              active
                ? "border-stone-900 bg-stone-900 text-white dark:border-stone-100 dark:bg-stone-100 dark:text-stone-900"
                : "border-stone-300 bg-white text-stone-800 hover:bg-stone-100 dark:border-stone-700 dark:bg-stone-900 dark:text-stone-100 dark:hover:bg-stone-800"
            }`}
          >
            <span className="block font-medium">IFD {dir.index}</span>
            <span className="block font-mono text-xs">
              {directoryDimensions(dir)}
            </span>
          </button>
        );
      })}
    </div>
  );
}
