#!/usr/bin/env node
// pw-eq-gen — Generate a PipeWire filter-chain config for a parametric EQ sink.
//
// Produces a JSON pipewire.conf.d drop-in that creates a stereo virtual sink
// routed through a chain of biquad filters (default: treble roll-off shelves),
// with output delivered to a target sink (default: combine_sink).
//
// Priority: CLI argument > environment variable > default
//
// This is the codified baseline that replaces EasyEffects in the live path.
// Background (2026-10-18 session): EasyEffects on this graph exhibited four
// failure modes — combine_sink fanning into its virtual sink (feedback), its
// process-all-outputs stream-moving destroying module-combine-stream fan
// streams, zombie disconnection across PipeWire restarts, and an intermittently
// self-unwiring player. A graph-native filter-chain has none of those moving
// parts. EE stays installed for occasional GUI experiments; if it runs:
// keep its process-all-outputs OFF (it kills the combine fan streams) and
// expect to restart it after any PipeWire restart.

const args = process.argv.slice(2)

// Defaults — override via PW_EQ_* env vars or CLI args
const defaults = {
	node: "eq_sink",
	target: "combine_sink",
	bands: "3500:-3:0.7:highshelf,11000:-4:0.7:highshelf",
}

function resolveString(key, argName) {
	for (let i = 0; i < args.length - 1; i++) {
		if (args[i] === argName) return args[i + 1]
	}
	const envKey = `PW_EQ_${key.toUpperCase()}`
	if (process.env[envKey] !== undefined) return process.env[envKey]
	return defaults[key]
}

const opts = {
	node: resolveString("node", "--node"),
	target: resolveString("target", "--target"),
	bands: resolveString("bands", "--bands"),
}

function usage() {
	console.error(`Usage: pw-eq-gen [options]

Generate a PipeWire filter-chain config for a parametric EQ virtual sink.
Output is JSON on stdout, suitable for a pipewire.conf.d drop-in.

Options (cli > env var > default):
  --node <name>    Virtual sink node.name            env: PW_EQ_NODE    default: ${defaults.node}
  --target <name>  Playback target sink node.name    env: PW_EQ_TARGET  default: ${defaults.target}
  --bands <spec>    Comma-separated band list        env: PW_EQ_BANDS   default: ${defaults.bands}

Band spec: freqHz:gaindB[:Q[:type]]
  freqHz  center/corner frequency
  gaindB  shelf gain or peaking boost/cut (0 disables the band)
  Q       filter Q (default 0.7)
  type    bq_ label suffix, one of:
          highshelf (default), lowshelf, peaking, highpass, lowpass,
          bandpass, notch, allpass

The band chain is applied identically to FL and FR. Examples:
  # default treble roll-off (two high shelves)
  pw-eq-gen > pw-eq.conf

  # gentler roll-off plus a low-shelf tilt
  pw-eq-gen --bands "4000:-2:0.7,12000:-3:0.7,120:+2:0.7:lowshelf"

  # via env vars
  PW_EQ_BANDS="3000:-4:0.7" pw-eq-gen > pw-eq.conf
`)
}

for (const arg of args) {
	if (arg === "-h" || arg === "--help") {
		usage()
		process.exit(0)
	}
	if (
		arg.startsWith("--") &&
		!arg.match(/^(--node|--target|--bands)$/)
	) {
		console.error(`Unknown option: ${arg}`)
		usage()
		process.exit(1)
	}
}

// --- Parse bands ---

const allowedTypes = new Set([
	"highshelf",
	"lowshelf",
	"peaking",
	"highpass",
	"lowpass",
	"bandpass",
	"notch",
	"allpass",
])

const bands = []
for (const raw of opts.bands.split(",")) {
	const spec = raw.trim()
	if (!spec) continue
	const parts = spec.split(":")
	if (parts.length < 2) {
		console.error(`Bad band "${spec}" — need at least freq:gain`)
		process.exit(1)
	}
	const freq = parseFloat(parts[0])
	const gain = parseFloat(parts[1])
	const q = parts.length > 2 ? parseFloat(parts[2]) : 0.7
	const type = parts.length > 3 ? parts[3] : "highshelf"
	if (!(freq > 0)) {
		console.error(`Bad band "${spec}" — frequency must be > 0`)
		process.exit(1)
	}
	if (!allowedTypes.has(type)) {
		console.error(`Bad band "${spec}" — unknown type "${type}"`)
		process.exit(1)
	}
	if (gain === 0 && (type === "highshelf" || type === "lowshelf" || type === "peaking")) {
		continue // gain 0 shelf is a no-op; omit the node
	}
	bands.push({ freq, gain, q, type })
}

if (bands.length === 0) {
	console.error("No active bands in spec — refusing to emit a no-op chain")
	process.exit(1)
}

// --- Build filter graph ---

// One biquad node per band per channel; FL and FR get identical chains.
// Named band nodes follow the pattern bq_<ch>_<n> so links stay stable.
const nodes = []
const links = []
for (const ch of ["FL", "FR"]) {
	bands.forEach((band, i) => {
		nodes.push({
			name: `bq_${ch}_${i}`,
			type: "builtin",
			label: `bq_${band.type}`,
			control: { Freq: band.freq, Q: band.q, Gain: band.gain },
		})
		if (i > 0) {
			links.push({
				output: `bq_${ch}_${i - 1}:Out`,
				input: `bq_${ch}_${i}:In`,
			})
		}
	})
}

const last = bands.length - 1
const inputs = ["bq_FL_0:In", "bq_FR_0:In"]
const outputs = [`bq_FL_${last}:Out`, `bq_FR_${last}:Out`]

const desc =
	"Parametric EQ (" +
	bands
		.map((b) => `${b.type} ${b.freq}Hz ${b.gain > 0 ? "+" : ""}${b.gain}dB Q${b.q}`)
		.join(", ") +
	`) -> ${opts.target}`

const config = {
	"context.modules": [
		{
			name: "libpipewire-module-filter-chain",
			args: {
				"node.description": desc,
				"media.name": opts.node,
				"filter.graph": { nodes, links, inputs, outputs },
				"capture.props": {
					"node.name": opts.node,
					"media.class": "Audio/Sink",
					"audio.channels": 2,
					"audio.position": ["FL", "FR"],
				},
				"playback.props": {
					"node.name": `${opts.node}_output`,
					"target.object": opts.target,
					"audio.channels": 2,
					"audio.position": ["FL", "FR"],
					"node.passive": true,
				},
			},
		},
	],
}

console.log(JSON.stringify(config, null, 2))
