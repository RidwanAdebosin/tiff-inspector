import type { Directory } from "../api/types";
import { planarCode } from "../lib/directory";
import { formatInteger } from "../lib/format";
import { FieldValue } from "./FieldValue";
import { Section } from "./Section";

function Explanation({ code }: { code: number | null }) {
  if (code === 1) {
    return (
      <p>
        <strong className="font-semibold">Contiguous (“chunky”)</strong>: all samples of a pixel are interleaved
        in a single plane, e.g. <span className="font-mono">RGBRGBRGB…</span>.
      </p>
    );
  }
  if (code === 2) {
    return (
      <p>
        <strong className="font-semibold">Separate (planar)</strong>: each sample is stored in its own plane with
        its own strips or tiles, e.g. <span className="font-mono">RRR… GGG… BBB…</span>.
      </p>
    );
  }
  return <p>The planar configuration could not be determined, so the plane layout is uncertain.</p>;
}

export function SamplesPlanes({ dir }: { dir: Directory }) {
  return (
    <Section title="Samples & planes">
      <div className="space-y-3 text-sm">
        <p>
          Planar configuration: <FieldValue field={dir.planar_configuration} />
        </p>
        <Explanation code={planarCode(dir)} />
        {dir.planes.length === 0 ? (
          <p className="text-zinc-600 dark:text-zinc-400">No plane information is available for this directory.</p>
        ) : (
          <ul className="divide-y divide-zinc-100 rounded-md border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {dir.planes.map((plane) => (
              <li key={plane.index} className="flex flex-wrap gap-x-4 gap-y-1 px-3 py-2">
                <span className="font-medium">Plane {plane.index}</span>
                <span>
                  {plane.samples.length === 1 ? "Sample " : "Samples "}
                  <span className="font-mono">{plane.samples.join(", ")}</span>
                </span>
                <span>
                  Bits <span className="font-mono">{plane.bits_per_sample.join(", ")}</span>
                </span>
                <span className="font-mono text-zinc-600 dark:text-zinc-400">
                  {formatInteger(plane.width)} × {formatInteger(plane.height)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </Section>
  );
}
