import { useId, type ReactNode } from "react";
import { card } from "./styles";

type SectionProps = {
  title: string;
  /** Heading level inside the page outline. */
  level?: 2 | 3;
  description?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
};

export function Section({
  title,
  level = 3,
  description,
  actions,
  children,
}: SectionProps) {
  const id = useId();
  const Heading = level === 2 ? "h2" : "h3";
  return (
    <section aria-labelledby={id} className={`${card} p-4 sm:p-5`}>
      <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
        <div>
          <Heading id={id} className="text-base font-semibold">
            {title}
          </Heading>
          {description && (
            <p className="mt-1 text-sm text-stone-600 dark:text-stone-400">
              {description}
            </p>
          )}
        </div>
        {actions}
      </div>
      {children}
    </section>
  );
}
