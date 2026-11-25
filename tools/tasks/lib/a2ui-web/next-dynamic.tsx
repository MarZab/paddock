// next/dynamic for the playground's map component, outside Next.js: React.lazy.
import { Suspense, lazy } from "react";
import type { ComponentType, ReactNode } from "react";

type Loaded<P> = ComponentType<P> | { default: ComponentType<P> };

export default function dynamic<P extends object>(loader: () => Promise<Loaded<P>>, options?: { loading?: () => ReactNode; ssr?: boolean }) {
  const Lazy = lazy(async () => {
    const loaded = await loader();
    return "default" in loaded ? loaded : { default: loaded };
  });
  return function Dynamic(props: P) {
    return (
      <Suspense fallback={options?.loading ? options.loading() : null}>
        <Lazy {...props} />
      </Suspense>
    );
  };
}
