/** Import-safe declared-name selection for context-aware domain commands. */

export type NameSelectionOptions = {
  explicit?: string
  invokedAs: string
  inferAlias: (invokedAs: string, declared: ReadonlySet<string>) => string | undefined
  environment?: string
  fallback: string
  declared: Iterable<string>
  label: string
}

function fail(message: string): never {
  throw new Error(message)
}

/**
 * Resolve one declared name. Alias parsing is deliberately lazy: an explicit
 * value completely bypasses it, allowing callers to escape stale aliases.
 */
export function resolveSelectedName(options: NameSelectionOptions): string {
  const declared = new Set(options.declared)
  const selected = options.explicit
    ?? options.inferAlias(options.invokedAs, declared)
    ?? options.environment
    ?? options.fallback
  if (!declared.has(selected)) fail(`unknown ${options.label}: ${selected}`)
  return selected
}
