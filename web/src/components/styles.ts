/** Shared Tailwind class strings, kept in one place for a consistent look. */

export const card =
  "rounded-xl border border-stone-200 bg-white shadow-sm shadow-stone-900/5 dark:border-stone-800 dark:bg-stone-900 dark:shadow-none";

const buttonBase =
  "inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60";

export const primaryButton = `${buttonBase} bg-amber-700 text-white hover:bg-amber-800 dark:bg-amber-400 dark:text-stone-950 dark:hover:bg-amber-300`;

export const secondaryButton = `${buttonBase} border border-stone-300 bg-white text-stone-800 hover:bg-stone-100 dark:border-stone-700 dark:bg-stone-900 dark:text-stone-100 dark:hover:bg-stone-800`;

export const linkButton =
  "rounded text-sm font-medium text-blue-700 underline-offset-2 hover:underline dark:text-blue-300";

export const muted = "text-stone-600 dark:text-stone-400";

export const mono = "font-mono text-[0.8125rem]";
