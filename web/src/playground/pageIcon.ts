/**
 * Swaps the document title and tab icon while a page is shown, restoring the
 * previous ones on cleanup. Icons are <link rel="icon"> elements; the SVG is
 * preferred and the PNG covers browsers that ignore SVG icons.
 */
export function applyPageIcon(opts: {
  title: string;
  svg: string;
  png: string;
}): () => void {
  const head = document.head;
  const previousTitle = document.title;
  const previous = Array.from(
    head.querySelectorAll<HTMLLinkElement>('link[rel~="icon"]'),
  );
  for (const link of previous) link.remove();

  const svg = document.createElement("link");
  svg.rel = "icon";
  svg.type = "image/svg+xml";
  svg.href = opts.svg;
  const png = document.createElement("link");
  png.rel = "icon";
  png.type = "image/png";
  png.setAttribute("sizes", "32x32");
  png.href = opts.png;
  head.append(svg, png);
  document.title = opts.title;

  return () => {
    svg.remove();
    png.remove();
    head.append(...previous);
    document.title = previousTitle;
  };
}
