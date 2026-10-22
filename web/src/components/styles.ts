/** Shared Tailwind class strings, kept in one place for a consistent look. */

export const card = "rounded-lg border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900";

const buttonBase =
  "inline-flex items-center justify-center gap-2 rounded-md px-3.5 py-2 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60";

export const primaryButton = `${buttonBase} bg-zinc-900 text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300`;

export const secondaryButton = `${buttonBase} border border-zinc-300 bg-white text-zinc-800 hover:bg-zinc-100 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100 dark:hover:bg-zinc-800`;

export const linkButton =
  "rounded text-sm font-medium text-blue-700 underline-offset-2 hover:underline dark:text-blue-300";

export const muted = "text-zinc-600 dark:text-zinc-400";

export const mono = "font-mono text-[0.8125rem]";
