/** Sets the document title while a view is shown; the cleanup restores the previous one. */
export function applyPageTitle(title: string): () => void {
  const previous = document.title;
  document.title = title;
  return () => {
    document.title = previous;
  };
}
