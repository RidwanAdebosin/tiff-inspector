import type { Directory, Enum } from "../api/types";
import { formatEnum } from "../lib/format";
import { FieldValue } from "./FieldValue";
import { KeyValueList } from "./KeyValueList";
import { Section } from "./Section";

const perSample = (formats: Enum[]) =>
  formats.map((e, i) => `#${i}: ${formatEnum(e)}`).join(", ");

export function ImageProperties({ dir }: { dir: Directory }) {
  return (
    <Section title="Image properties">
      <KeyValueList
        items={[
          { label: "Width", value: <FieldValue field={dir.width} unit="px" /> },
          {
            label: "Height",
            value: <FieldValue field={dir.height} unit="px" />,
          },
          {
            label: "Samples per pixel",
            value: <FieldValue field={dir.samples_per_pixel} />,
          },
          {
            label: "Bits per sample",
            value: <FieldValue field={dir.bits_per_sample} />,
          },
          {
            label: "Sample format (per sample)",
            value: <FieldValue field={dir.sample_format} format={perSample} />,
          },
          {
            label: "Photometric interpretation",
            value: <FieldValue field={dir.photometric_interpretation} />,
          },
          {
            label: "Planar configuration",
            value: <FieldValue field={dir.planar_configuration} />,
          },
          {
            label: "Compression",
            value: <FieldValue field={dir.compression} />,
          },
          { label: "Predictor", value: <FieldValue field={dir.predictor} /> },
          {
            label: "Orientation",
            value: <FieldValue field={dir.orientation} />,
          },
          {
            label: "X resolution",
            value: <FieldValue field={dir.resolution.x} />,
          },
          {
            label: "Y resolution",
            value: <FieldValue field={dir.resolution.y} />,
          },
          {
            label: "Resolution unit",
            value: <FieldValue field={dir.resolution.unit} />,
          },
        ]}
      />
    </Section>
  );
}
