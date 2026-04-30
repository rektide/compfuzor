#!/usr/bin/env node
// surround-51-gen — Generate a PipeWire filter-chain config for virtual 5.1 surround.
//
// Produces a JSON pipewire.conf.d drop-in that creates a 6-channel virtual sink
// with configurable mixing gains and an optional highpass filter for the main speakers.
//
// Priority: CLI argument > environment variable > default

const args = process.argv.slice(2);

// Defaults — override via PW_SURROUND_* env vars or CLI args
const defaults = {
  frontMix: 0.7,
  centerMix: 0.4,
  highpass: 0,
  subLFE: 1.0,
  subMain: 0.0,
  subCenter: 0.0,
};

// Resolve: CLI arg > env var > default
function resolve(key, argName) {
  for (let i = 0; i < args.length - 1; i++) {
    if (args[i] === argName) return parseFloat(args[i + 1]);
  }
  const envKey = `PW_SURROUND_${key.replace(/([A-Z])/g, "_$1").toUpperCase()}`;
  if (process.env[envKey] !== undefined) return parseFloat(process.env[envKey]);
  return defaults[key];
}

const opts = {
  frontMix: resolve("frontMix", "--front-mix"),
  centerMix: resolve("centerMix", "--center-mix"),
  highpass: resolve("highpass", "--highpass"),
  subLFE: resolve("subLFE", "--sub-lfe"),
  subMain: resolve("subMain", "--sub-main"),
  subCenter: resolve("subCenter", "--sub-center"),
};

function usage() {
  console.error(`Usage: surround-51-gen [options]

Generate a PipeWire filter-chain config for virtual 5.1 surround sound.

Options (cli > env var > default):
  --front-mix <gain>   Front channel gain to virtual front speakers
                        env: PW_SURROUND_FRONT_MIX  default: ${defaults.frontMix}
  --center-mix <gain>  Center channel gain mixed into both virtual front speakers
                        env: PW_SURROUND_CENTER_MIX default: ${defaults.centerMix}
  --highpass <hz>      Highpass frequency for front+rear speakers (0 = disabled)
                        env: PW_SURROUND_HIGHPASS   default: ${defaults.highpass}
  --sub-lfe <gain>     LFE channel gain to subwoofer output
                        env: PW_SURROUND_SUB_LFE    default: ${defaults.subLFE}
  --sub-main <gain>    Main stereo (FL+FR) gain mixed into subwoofer
                        env: PW_SURROUND_SUB_MAIN   default: ${defaults.subMain}
  --sub-center <gain>  Center channel gain mixed into subwoofer
                        env: PW_SURROUND_SUB_CENTER default: ${defaults.subCenter}

Hardware routing (configured via surround-51-wire):
  Mpow HC5  L = rear left    R = front left   (FL + centerMix*FC)
  FiiO E10  L = front right  R = rear right   (FR + centerMix*FC)
  SB X-Fi   L+R = subwoofer                    (subLFE*LFE + subMain*(FL+FR) + subCenter*FC)

Filter graph signal flow:
  copy_FL ──→ mix_front_L (frontMix)  ──→ [hp_front_L?] ──→ output FL
  copy_FC ──→ mix_front_L (centerMix) ─╮
  copy_FR ──→ mix_front_R (frontMix)  ──→ [hp_front_R?] ──→ output FR
  copy_FC2 ─→ mix_front_R (centerMix) ─╯
  copy_RL  ──→ [hp_rear_L?] ──────────────→ output RL
  copy_RR  ──→ [hp_rear_R?] ──────────────→ output RR
  copy_FL ──→ mix_sub (subMain)   ─╮
  copy_FR ──→ mix_sub (subMain)   ─┤──→ output LFE
  copy_FC ──→ mix_sub (subCenter) ─┤
  copy_LFE ─→ mix_sub (subLFE)    ─╯

Examples:
  # defaults: 0.7 front, 0.4 center, LFE only to sub
  surround-51-gen > surround-51.conf

  # highpass mains at 80Hz, mix some main into sub
  surround-51-gen --highpass 80 --sub-main 0.5 > surround-51.conf

  # via env vars
  PW_SURROUND_HIGHPASS=80 PW_SURROUND_SUB_MAIN=0.5 surround-51-gen > surround-51.conf
`);
}

for (const arg of args) {
  if (arg === "-h" || arg === "--help") { usage(); process.exit(0); }
  if (arg.startsWith("--") && !arg.match(/^--(front-mix|center-mix|highpass|sub-lfe|sub-main|sub-center)$/)) {
    console.error(`Unknown option: ${arg}`);
    usage();
    process.exit(1);
  }
}

// --- Build filter graph ---

const hp = opts.highpass > 0;

// Input copy nodes — one per 5.1 channel, plus a second FC copy for the right front mixer
const nodes = [
  { name: "copy_FL", type: "builtin", label: "copy" },
  { name: "copy_FR", type: "builtin", label: "copy" },
  { name: "copy_FC", type: "builtin", label: "copy" },
  { name: "copy_LFE", type: "builtin", label: "copy" },
  { name: "copy_RL", type: "builtin", label: "copy" },
  { name: "copy_RR", type: "builtin", label: "copy" },
  { name: "copy_FC2", type: "builtin", label: "copy" },
];

// Front speaker mixers: frontMix*FL/FR + centerMix*FC
nodes.push({
  name: "mix_front_L", type: "builtin", label: "mixer",
  control: { "Gain 1": opts.frontMix, "Gain 2": opts.centerMix },
});
nodes.push({
  name: "mix_front_R", type: "builtin", label: "mixer",
  control: { "Gain 1": opts.frontMix, "Gain 2": opts.centerMix },
});

// Subwoofer mixer: subMain*(FL+FR) + subCenter*FC + subLFE*LFE
nodes.push({
  name: "mix_sub", type: "builtin", label: "mixer",
  control: {
    "Gain 1": opts.subMain,
    "Gain 2": opts.subMain,
    "Gain 3": opts.subCenter,
    "Gain 4": opts.subLFE,
  },
});

// Optional highpass filters for main speakers (front + rear)
// Removes low frequencies that the subwoofer handles, avoiding overlap
if (hp) {
  for (const id of ["front_L", "front_R", "rear_L", "rear_R"]) {
    nodes.push({
      name: `hp_${id}`, type: "builtin", label: "bq_highpass",
      control: { Freq: opts.highpass, Q: 0.707 },
    });
  }
}

// Links — signal routing between nodes
// Note: copy outputs can fan out to multiple inputs (e.g. copy_FL → mix_front_L AND mix_sub)
const links = [
  // Front left: FL + center
  { output: "copy_FL:Out", input: "mix_front_L:In 1" },
  { output: "copy_FC:Out", input: "mix_front_L:In 2" },
  // Front right: FR + center
  { output: "copy_FR:Out", input: "mix_front_R:In 1" },
  { output: "copy_FC2:Out", input: "mix_front_R:In 2" },
  // Subwoofer: main + center + LFE
  { output: "copy_FL:Out", input: "mix_sub:In 1" },
  { output: "copy_FR:Out", input: "mix_sub:In 2" },
  { output: "copy_FC:Out", input: "mix_sub:In 3" },
  { output: "copy_LFE:Out", input: "mix_sub:In 4" },
];

// Highpass links route the mixed front and raw rear through filters
if (hp) {
  links.push(
    { output: "mix_front_L:Out", input: "hp_front_L:In" },
    { output: "mix_front_R:Out", input: "hp_front_R:In" },
    { output: "copy_RL:Out", input: "hp_rear_L:In" },
    { output: "copy_RR:Out", input: "hp_rear_R:In" },
  );
}

// Graph input ports — one per 5.1 channel, maps to the 6-channel virtual sink
const inputs = [
  "copy_FL:In", "copy_FR:In", "copy_FC:In",
  "copy_LFE:In", "copy_RL:In", "copy_RR:In",
];

// Graph output ports — when highpass is active, rear channels go through hp nodes
const outputs = hp
  ? ["hp_front_L:Out", "hp_front_R:Out", "copy_FC:Out", "mix_sub:Out", "hp_rear_L:Out", "hp_rear_R:Out"]
  : ["mix_front_L:Out", "mix_front_R:Out", "copy_FC:Out", "mix_sub:Out", "copy_RL:Out", "copy_RR:Out"];

const desc = `5.1 Surround (front=${opts.frontMix} center=${opts.centerMix}${hp ? ` hp=${opts.highpass}` : ""} sub=lfe:${opts.subLFE},main:${opts.subMain},ctr:${opts.subCenter})`;

const config = {
  "context.modules": [{
    name: "libpipewire-module-filter-chain",
    args: {
      "node.description": desc,
      "media.name": "surround_51",
      "filter.graph": { nodes, links, inputs, outputs },
      "capture.props": {
        "node.name": "surround_51_input",
        "media.class": "Audio/Sink",
        "audio.channels": 6,
        "audio.position": ["FL", "FR", "FC", "LFE", "RL", "RR"],
      },
      "playback.props": {
        "node.name": "surround_51_output",
        "audio.channels": 6,
        "audio.position": ["FL", "FR", "FC", "LFE", "RL", "RR"],
        "stream.dont-remix": true,
        "node.passive": true,
      },
    },
  }],
};

console.log(JSON.stringify(config, null, 2));
