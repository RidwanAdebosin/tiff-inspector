import type { PixelDecoding } from "../api/types";
import { Badge, type BadgeTone } from "./Badge";
import { KeyValueList } from "./KeyValueList";
import { Section } from "./Section";

const SUPPORT: Record<PixelDecoding["library_support"], { tone: BadgeTone; text: string }> = {
  supported: { tone: "success", text: "supported" },
  unsupported: { tone: "warn", text: "unsupported" },
  unknown: { tone: "neutral", text: "unknown" },
};

export function PixelDecodingInfo({ decoding }: { decoding: PixelDecoding }) {
  const support = SUPPORT[decoding.library_support];
  return (
    <Section
      title="Pixel decoding"
      description="This version inspects metadata only. Pixel data is not decoded and no preview is generated."
    >
      <KeyValueList
        items={[
          { label: "Status", value: <span className="font-mono text-[0.8125rem]">{decoding.status}</span> },
          {
            label: "Decoder support (static assessment)",
            value: <Badge tone={support.tone}>{support.text}</Badge>,
          },
          {
            label: "Reason",
            value: decoding.reason ?? <span className="text-zinc-600 italic dark:text-zinc-400">none given</span>,
          },
        ]}
      />
    </Section>
  );
}
