/**
 * apt-src-model.ts - the canonical JSON model shared by the apt-srctools
 * bins, plus parse/emit for both apt sources formats.
 *
 * Canonical JSON shape (every key always present; null when absent):
 *
 *   {
 *     "sources": [
 *       {
 *         "types": ["deb"],                  // "deb" | "deb-src"
 *         "uris": ["https://..."],           // one classic line / one URIs row
 *         "suites": ["forky"],               // ["./"] or ["/"] for flat repos
 *         "components": ["main"],
 *         "signedBy": "/usr/share/keyrings/x.gpg",  // path, fingerprints, or
 *                                                    // verbatim PGP keyblock
 *         "architectures": ["amd64"],        // null when unset
 *         "trusted": false,
 *         "enabled": true,                   // false: "#deb" / "Enabled: no"
 *         "options": {},                     // classic-only bracket remainder
 *         "fields": {}                       // deb822 passthrough (By-Hash, ...)
 *       }
 *     ]
 *   }
 *
 * Fidelity map (see design/apt-srctools/ for the full discussion):
 *   classic -> json -> classic    exact modulo whitespace, bracket spacing and
 *                                option order; comments are dropped.
 *   deb822  -> json -> deb822    exact modulo field order and comments; values
 *                                normalize to space-joined multi-values.
 *   classic -> json -> deb822    semantically lossless: one classic line stays
 *                                one stanza (no deb/deb-src merging), unknown
 *                                bracket options alias-map where possible.
 *   deb822  -> json -> classic   semantically lossless: one stanza expands to
 *                                the types x uris x suites cartesian lines;
 *                                keyblock Signed-By and un-aliasable fields
 *                                warn and drop (classic cannot hold them).
 */

export interface AptSourceEntry {
  types: string[];
  uris: string[];
  suites: string[];
  components: string[];
  signedBy: string | null;
  architectures: string[] | null;
  trusted: boolean;
  enabled: boolean;
  options: Record<string, string>;
  fields: Record<string, string>;
}

export interface AptSourcesJson {
  sources: AptSourceEntry[];
}

export class AptParseError extends Error {
  readonly line: number;
  constructor(message: string, line: number) {
    super(`${message} (line ${line})`);
    this.name = "AptParseError";
    this.line = line;
  }
}

/** classic bracket options that alias into deb822 fields (and back) */
export const OPTION_ALIASES: Record<string, string> = {
  lang: "Languages",
  target: "Targets",
  pdiffs: "PDiffs",
  "by-hash": "By-Hash",
};

const ALIAS_TO_OPTION = Object.fromEntries(
  Object.entries(OPTION_ALIASES).map(([opt, field]) => [field.toLowerCase(), opt]),
);

const DEB822_KNOWN = new Set([
  "types",
  "uris",
  "suites",
  "components",
  "signed-by",
  "architectures",
  "trusted",
  "enabled",
]);

/** reorder into canonical key order and default absent keys */
export function canonicalEntry(e: AptSourceEntry): AptSourceEntry {
  return {
    types: [...(e.types ?? [])],
    uris: [...(e.uris ?? [])],
    suites: [...(e.suites ?? [])],
    components: [...(e.components ?? [])],
    signedBy: e.signedBy ?? null,
    architectures: e.architectures ? [...e.architectures] : null,
    trusted: e.trusted === true,
    enabled: e.enabled !== false,
    options: e.options ? { ...e.options } : {},
    fields: e.fields ? { ...e.fields } : {},
  };
}

export function canonical(json: AptSourcesJson): AptSourcesJson {
  return { sources: (json.sources ?? []).map(canonicalEntry) };
}

/** assert the minimum a source needs to be emitted in either format */
export function validateEntry(e: AptSourceEntry, index: number): void {
  if (!e.types?.length) throw new Error(`entry ${index}: types is empty`);
  if (!e.uris?.length) throw new Error(`entry ${index}: uris is empty`);
  if (!e.suites?.length) throw new Error(`entry ${index}: suites is empty`);
  for (const t of e.types)
    if (t !== "deb" && t !== "deb-src")
      throw new Error(`entry ${index}: unsupported type '${t}'`);
}

// ---------------------------------------------------------------------------
// classic (one-line) format
// ---------------------------------------------------------------------------

export interface ClassicToken {
  text: string;
  start: number;
  end: number;
}

function tokenizeClassic(line: string, lineNo: number): ClassicToken[] {
  const toks: ClassicToken[] = [];
  let i = 0;
  while (i < line.length) {
    while (i < line.length && /\s/.test(line[i]!)) i++;
    if (i >= line.length) break;
    const start = i;
    if (line[i] === "[") {
      while (i < line.length && line[i] !== "]") i++;
      if (i >= line.length)
        throw new AptParseError("unterminated [ options ] bracket", lineNo);
      i++;
    } else {
      while (i < line.length && !/\s/.test(line[i]!)) i++;
    }
    toks.push({ text: line.slice(start, i), start, end: i });
  }
  return toks;
}

/**
 * Locate the URI token of a classic source line (active or commented out),
 * with its byte offsets so callers can rewrite just that span. Returns null
 * for blank lines and pure comments.
 */
export function findClassicUri(raw: string): ClassicToken | null {
  let i = 0;
  // skip leading whitespace and at most one leading '#'
  while (i < raw.length && /\s/.test(raw[i]!)) i++;
  if (raw[i] === "#") {
    if (raw[i + 1] === "#") return null; // '##' is a plain comment
    i++;
    while (i < raw.length && /\s/.test(raw[i]!)) i++;
  }
  if (i >= raw.length) return null;
  let end = i;
  while (end < raw.length && !/\s/.test(raw[end]!)) end++;
  const first = raw.slice(i, end);
  if (first !== "deb" && first !== "deb-src") return null;
  let k = end;
  while (k < raw.length && /\s/.test(raw[k]!)) k++;
  if (k >= raw.length) return null;
  if (raw[k] === "[") {
    while (k < raw.length && raw[k] !== "]") k++;
    if (k >= raw.length) return null; // unterminated: leave to the parser
    k++;
    while (k < raw.length && /\s/.test(raw[k]!)) k++;
    if (k >= raw.length) return null;
  }
  let uriEnd = k;
  while (uriEnd < raw.length && !/\s/.test(raw[uriEnd]!)) uriEnd++;
  return { text: raw.slice(k, uriEnd), start: k, end: uriEnd };
}

export function parseClassic(text: string): AptSourcesJson {
  const sources: AptSourceEntry[] = [];
  const lines = text.split("\n");
  for (let idx = 0; idx < lines.length; idx++) {
    const lineNo = idx + 1;
    const raw = lines[idx]!;
    const trimmed = raw.trimStart();
    if (trimmed === "") continue;
    let work = trimmed;
    let enabled = true;
    if (work.startsWith("#")) {
      enabled = false;
      work = work.slice(1);
    }
    const toks = tokenizeClassic(work, lineNo);
    const cut = toks.findIndex((t) => t.text.startsWith("#"));
    const active = cut === -1 ? toks : toks.slice(0, cut);
    if (active.length === 0) continue; // pure comment
    const type = active[0]!.text;
    if (type !== "deb" && type !== "deb-src") {
      // a '#' followed by anything but a source line is just a comment
      if (!enabled) continue;
      throw new AptParseError(`unsupported source type '${type}'`, lineNo);
    }
    let i = 1;
    const options: Record<string, string> = {};
    let signedBy: string | null = null;
    let architectures: string[] | null = null;
    let trusted = false;
    if (active[i]?.text.startsWith("[")) {
      const inner = active[i]!.text.slice(1, -1);
      i++;
      // apt separates bracket options on whitespace only; commas stay inside
      // values ("arch=amd64,i386" is one option, and "trusted=yes,arch=amd64"
      // is a single trusted option whose trailing junk apt ignores).
      for (const part of inner.split(/\s+/).filter(Boolean)) {
        const eq = part.indexOf("=");
        if (eq === -1)
          throw new AptParseError(`bracket option '${part}' lacks '='`, lineNo);
        const key = part.slice(0, eq);
        const value = part.slice(eq + 1);
        if (key === "signed-by") signedBy = value;
        else if (key === "arch") architectures = value.split(",").filter(Boolean);
        else if (key === "trusted") {
          if (value === "yes" || value === "true" || value === "1") trusted = true;
          else if (value === "no" || value === "false" || value === "0") trusted = false;
          else options[key] = value; // keep apt's lenient prefix-bool blobs verbatim
        } else options[key] = value;
      }
    }
    const uri = active[i]?.text;
    if (!uri) throw new AptParseError("missing URI", lineNo);
    i++;
    const suite = active[i]?.text;
    if (!suite) throw new AptParseError("missing suite", lineNo);
    i++;
    const components = active.slice(i).map((t) => t.text);
    sources.push(
      canonicalEntry({
        types: [type],
        uris: [uri],
        suites: [suite],
        components,
        signedBy,
        architectures,
        trusted,
        enabled,
        options,
        fields: {},
      }),
    );
  }
  return { sources };
}

/** split a signed-by value (path, fingerprints) into comma-joinable parts */
function splitList(s: string): string[] {
  return s.split(/[\s,]+/).filter(Boolean);
}

export function classicBracket(e: AptSourceEntry): string {
  const parts: string[] = [];
  if (e.signedBy != null && !e.signedBy.includes("\n"))
    parts.push(`signed-by=${splitList(e.signedBy).join(",")}`);
  if (e.architectures) parts.push(`arch=${e.architectures.join(",")}`);
  if (e.trusted) parts.push("trusted=yes");
  for (const [k, v] of Object.entries(e.options)) parts.push(`${k}=${v}`);
  return parts.length ? `[ ${parts.join(" ")} ]` : "";
}

export function emitClassic(json: AptSourcesJson): string {
  const out: string[] = [];
  json.sources.forEach((raw, index) => {
    const e = canonicalEntry(raw);
    validateEntry(e, index);
    const bracket = classicBracket(e);
    for (const type of e.types)
      for (const uri of e.uris)
        for (const suite of e.suites) {
          const line = [type, bracket, uri, suite, ...e.components]
            .filter(Boolean)
            .join(" ");
          out.push(e.enabled ? line : `#${line}`);
        }
  });
  return out.length ? out.join("\n") + "\n" : "";
}

// ---------------------------------------------------------------------------
// deb822 (.sources) format
// ---------------------------------------------------------------------------

interface Deb822Field {
  key: string;
  first: string;
  conts: string[]; // raw continuation lines, leading whitespace still attached
}

/** deb822 continuation line -> content line (one leading ws stripped, dot-unstuffed) */
function unstuff(raw: string): string {
  const body = raw.replace(/^[ \t]/, "");
  return body === "." ? "" : body;
}

/** multi-value deb822 fields separate on whitespace and commas */
export function splitDeb822Values(value: string): string[] {
  return value.split(/[\s,]+/).filter(Boolean);
}

function stanzaToEntry(fields: Deb822Field[], lineNo: number): AptSourceEntry {
  const map = new Map<string, Deb822Field>();
  for (const f of fields) {
    if (map.has(f.key))
      throw new AptParseError(`duplicate field '${f.key}:'`, lineNo);
    map.set(f.key, f);
  }
  const get = (key: string): Deb822Field | undefined =>
    map.get(key) ?? map.get(key.toLowerCase());

  const typesF = get("Types");
  const urisF = get("URIs");
  const suitesF = get("Suites");
  if (!typesF || typesF.conts.length)
    throw new AptParseError(
      !typesF ? "stanza lacks Types:" : "Types: uses a continuation line",
      lineNo,
    );
  if (!urisF || urisF.conts.length)
    throw new AptParseError(
      !urisF ? "stanza lacks URIs:" : "URIs: uses a continuation line",
      lineNo,
    );
  if (!suitesF || suitesF.conts.length)
    throw new AptParseError(
      !suitesF ? "stanza lacks Suites:" : "Suites: uses a continuation line",
      lineNo,
    );

  const componentsF = get("Components");
  const archF = get("Architectures");
  const trustedF = get("Trusted");
  const enabledF = get("Enabled");
  const sbF = get("Signed-By");

  let signedBy: string | null = null;
  if (sbF) {
    const conts = sbF.conts.map(unstuff);
    if (sbF.first.trim() === "" && conts.length) signedBy = conts.join("\n");
    else if (sbF.first.startsWith("-----BEGIN") && conts.length)
      signedBy = [sbF.first, ...conts].join("\n");
    else signedBy = sbF.first.trim();
  }

  const options: Record<string, string> = {};
  const passthrough: Record<string, string> = {};
  for (const f of fields) {
    if (DEB822_KNOWN.has(f.key.toLowerCase())) continue;
    const value = [f.first, ...f.conts.map(unstuff)].join("\n");
    const opt = ALIAS_TO_OPTION[f.key.toLowerCase()];
    if (opt) options[opt] = value;
    else passthrough[f.key] = value;
  }

  return canonicalEntry({
    types: splitDeb822Values(typesF.first),
    uris: splitDeb822Values(urisF.first),
    suites: splitDeb822Values(suitesF.first),
    components: componentsF ? splitDeb822Values(componentsF.first) : [],
    signedBy,
    architectures: archF ? splitDeb822Values(archF.first) : null,
    trusted: trustedF ? trustedF.first.trim() === "yes" || trustedF.first.trim() === "true" : false,
    enabled: enabledF ? !(enabledF.first.trim() === "no" || enabledF.first.trim() === "false") : true,
    options,
    fields: passthrough,
  });
}

export function parseDeb822(text: string): AptSourcesJson {
  const sources: AptSourceEntry[] = [];
  const lines = text.split("\n");
  let cur: Deb822Field[] = [];
  let curLine = 0;
  const flush = () => {
    if (cur.length) {
      sources.push(stanzaToEntry(cur, curLine));
      cur = [];
    }
  };
  for (let idx = 0; idx < lines.length; idx++) {
    const raw = lines[idx]!;
    const lineNo = idx + 1;
    if (raw.trim() === "") {
      flush();
      continue;
    }
    if (raw.startsWith("#")) continue; // whole-line comment (legal mid-stanza)
    if (raw.startsWith(" ") || raw.startsWith("\t")) {
      if (!cur.length)
        throw new AptParseError("continuation line before any field", lineNo);
      cur[cur.length - 1]!.conts.push(raw);
      continue;
    }
    const m = raw.match(/^([-A-Za-z0-9]+):[ \t]?(.*)$/);
    if (!m)
      throw new AptParseError(
        `malformed deb822 line '${raw.slice(0, 40)}'`,
        lineNo,
      );
    if (!cur.length) curLine = lineNo;
    cur.push({ key: m[1]!, first: m[2]!, conts: [] });
  }
  flush();
  return { sources };
}

export function emitDeb822(json: AptSourcesJson): string {
  const stanzas: string[] = [];
  json.sources.forEach((raw, index) => {
    const e = canonicalEntry(raw);
    validateEntry(e, index);
    const L: string[] = [];
    L.push(`Types: ${e.types.join(" ")}`);
    L.push(`URIs: ${e.uris.join(" ")}`);
    L.push(`Suites: ${e.suites.join(" ")}`);
    if (e.components.length) L.push(`Components: ${e.components.join(" ")}`);
    if (e.architectures) L.push(`Architectures: ${e.architectures.join(" ")}`);
    if (!e.enabled) L.push("Enabled: no");
    if (e.trusted) L.push("Trusted: yes");
    if (e.signedBy != null) {
      const kl = e.signedBy.split("\n");
      if (kl.length === 1) L.push(`Signed-By: ${e.signedBy}`);
      else {
        L.push("Signed-By:");
        for (const l of kl) L.push(" " + (l === "" ? "." : l));
      }
    }
    // classic-only bracket options alias back into deb822 fields where known
    for (const [k, v] of Object.entries(e.options)) {
      const field = OPTION_ALIASES[k];
      if (!field) continue; // caller warns about the un-aliasable remainder
      L.push(`${field}: ${v}`);
    }
    for (const [k, v] of Object.entries(e.fields)) {
      const vl = v.split("\n");
      L.push(`${k}: ${vl[0]}`);
      for (const c of vl.slice(1)) L.push(" " + (c === "" ? "." : c));
    }
    stanzas.push(L.join("\n"));
  });
  return stanzas.length ? stanzas.join("\n\n") + "\n" : "";
}

/** what json2deb822 must warn about: options with no deb822 spelling */
export function unaliasableOptions(json: AptSourcesJson): string[] {
  const out: string[] = [];
  json.sources.forEach((e, i) => {
    for (const k of Object.keys(e.options ?? {}))
      if (!OPTION_ALIASES[k]) out.push(`entry ${i}: option '${k}'`);
  });
  return out;
}

/** what json2classic must warn about: fields/options with no classic spelling */
export function unclassicable(json: AptSourcesJson): string[] {
  const out: string[] = [];
  json.sources.forEach((e, i) => {
    if (e.signedBy?.includes("\n"))
      out.push(`entry ${i}: inline Signed-By keyblock`);
    for (const k of Object.keys(e.fields ?? {}))
      out.push(`entry ${i}: field '${k}'`);
  });
  return out;
}
