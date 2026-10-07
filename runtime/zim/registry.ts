/** Exact channel offers; this registry does not choose hosts or activate Zim. */
import { isAbsolute } from "node:path";
import { Schema } from "effect";
import type { Domain } from "../registry/model.ts";

const OfferSchema = Schema.Struct({
  version: Schema.Literal(1),
  id: Schema.String,
  enabled: Schema.optional(Schema.Boolean),
  fragments: Schema.Array(
    Schema.Struct({
      channel: Schema.Literals(["zimrc", "zimenv"]),
      name: Schema.String,
      path: Schema.String,
      enabled: Schema.optional(Schema.Boolean),
    }),
  ),
});
export type ZimOffer = {
  version: 1;
  id: string;
  enabled?: boolean;
  fragments: readonly {
    channel: "zimrc" | "zimenv";
    name: string;
    path: string;
    enabled?: boolean;
  }[];
};
export const zimProviders: Domain<ZimOffer> = {
  collection: "zim/providers.d",
  decode(value) {
    const offer = Schema.decodeUnknownSync(OfferSchema)(value);
    const seen = new Set<string>();
    for (const fragment of offer.fragments) {
      const key = `${fragment.channel}/${fragment.name}`;
      if (
        !isAbsolute(fragment.path) ||
        !/^[A-Za-z0-9][A-Za-z0-9_.-]*\.conf$/.test(fragment.name) ||
        seen.has(key)
      ) {
        throw new Error(
          "Zim offer requires absolute exact paths and unique channel/fragment names",
        );
      }
      seen.add(key);
    }
    return offer;
  },
  identity: (value) => value.id,
  enabled: (value) => value.enabled !== false,
  scope: () => undefined,
};
