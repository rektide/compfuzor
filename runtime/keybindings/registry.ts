/** Domain decoders: manifest ownership stays with the producer, profile/policy with the consumer. */
import { isAbsolute } from "node:path";
import { Schema } from "effect";
import type { Domain, Scope } from "../registry/model.ts";

const ProducerSchema = Schema.Struct({
  version: Schema.Literal(1),
  producer: Schema.String,
  order: Schema.Number,
  resources: Schema.Array(Schema.Struct({ path: Schema.String })),
  // Legacy eligibility lists native adapter formats, never arbitrary receiver IDs.
  targets: Schema.Array(Schema.Literals(["niri", "umbriel"])),
  enabled: Schema.optional(Schema.Boolean),
});
export type Provider = {
  version: 1;
  producer: string;
  order: number;
  resources: readonly { path: string }[];
  targets: readonly ("niri" | "umbriel")[];
  enabled?: boolean;
};
export const keybindingProviders: Domain<Provider> = {
  collection: "keybindings/providers.d",
  decode(value) {
    const manifest = Schema.decodeUnknownSync(ProducerSchema)(value);
    if (
      !Number.isFinite(manifest.order) ||
      manifest.resources.some((entry) => !isAbsolute(entry.path))
    ) {
      throw new Error("producer requires finite order and absolute exact resource paths");
    }
    return manifest;
  },
  identity: (value) => value.producer,
  enabled: (value) => value.enabled !== false,
  scope: () => undefined,
};

const ProfileSelector = Schema.Union([
  Schema.Struct({ path: Schema.String }),
  Schema.Struct({ env: Schema.String, default: Schema.Struct({ path: Schema.String }) }),
]);
const ConsumerSchema = Schema.Struct({
  version: Schema.Literal(1),
  id: Schema.String,
  adapter: Schema.String,
  audience: Schema.Literals(["user", "system"]),
  enabled: Schema.optional(Schema.Boolean),
  profile: ProfileSelector,
  contexts: Schema.Array(Schema.String),
  defaultContext: Schema.String,
});
export type Consumer = {
  version: 1;
  id: string;
  adapter: string;
  audience: Scope;
  enabled?: boolean;
  profile: { path: string } | { env: string; default: { path: string } };
  contexts: readonly string[];
  defaultContext: string;
};
export const keybindingConsumers: Domain<Consumer> = {
  collection: "keybindings/consumers.d",
  decode(value) {
    const consumer = Schema.decodeUnknownSync(ConsumerSchema)(value);
    const path = "path" in consumer.profile ? consumer.profile.path : consumer.profile.default.path;
    if (
      !isAbsolute(path) ||
      !consumer.adapter ||
      !consumer.contexts.includes(consumer.defaultContext) ||
      new Set(consumer.contexts).size !== consumer.contexts.length
    ) {
      throw new Error(
        "consumer requires absolute profile, adapter and unique contexts containing defaultContext",
      );
    }
    return consumer;
  },
  identity: (value) => value.id,
  enabled: (value) => value.enabled !== false,
  scope: (value): Scope => value.audience,
};
