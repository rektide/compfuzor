#!/usr/bin/env -S node --strip-types
/**
 * btrfs-resize.ts - Shrink a btrfs partition and create a swap partition in freed space
 *
 * Usage:
 *   btrfs-resize.ts /dev/sda 6 --shrink 64GiB            # dry run: shrink by 64GiB
 *   btrfs-resize.ts /dev/sda 6 --target 400GiB -x         # execute: resize to 400GiB
 *   btrfs-resize.ts /dev/nvme0n1 p3                        # match partition to already-resized btrfs
 *
 * Steps:
 *   1. swapoff -a
 *   2. btrfs filesystem resize (if --shrink or --target given)
 *   3. sgdisk: shrink partition to match btrfs size
 *   4. sgdisk: create swap partition in freed space
 *   5. partprobe
 *   6. mkswap
 */

import { execSync } from "node:child_process"
import { parseArgs } from "node:util"

const SECTOR = 512
const SWAP_HEX = "8200"

interface BtrfsInfo {
	deviceSize: number
	minSize: number
}

interface PartInfo {
	startSector: number
	endSector: number
	typeGuid: string
	uniqueGuid: string
}

interface Plan {
	device: string
	mountPoint: string
	disk: string
	partStr: string
	partition: number
	btrfsCurrentBytes: number
	btrfsMinBytes: number
	btrfsTargetBytes: number
	doBtrfsResize: boolean
	partStartSector: number
	partCurrentEndSector: number
	partNewEndSector: number
	swapPartNumber: number
	swapStartSector: number
	swapEndSector: number
}

function q(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`
}

function sh(cmd: string, dryRun: boolean): string {
  if (dryRun) {
    console.log(`  [DRY] ${cmd}`)
    return ""
  }
  console.log(`  [RUN] ${cmd}`)
  return execSync(cmd, { encoding: "utf-8" }).trim()
}

function partPath(disk: string, partStr: string): string {
	return `${disk}${partStr}`
}

function partNumber(partStr: string): number {
	return Number(partStr.replace(/^p/, ""))
}

function swapPartStr(partStr: string, swapNum: number): string {
	const prefix = partStr.replace(/\d+$/, "")
	return `${prefix}${swapNum}`
}

function parseSize(input: string): number {
	const m = input.match(/^(\d+(?:\.\d+)?)\s*([KMGT]i?B?)?$/i)
	if (!m) throw new Error(`Invalid size: ${input}`)
	const val = parseFloat(m[1])
	const unit = (m[2] ?? "").toUpperCase()
	const table: Record<string, number> = {
		"": 1,
		B: 1,
		K: 1e3,
		KB: 1e3,
		KI: 1024,
		KIB: 1024,
		M: 1e6,
		MB: 1e6,
		MI: 1048576,
		MIB: 1048576,
		G: 1e9,
		GB: 1e9,
		GI: 1073741824,
		GIB: 1073741824,
		T: 1e12,
		TB: 1e12,
		TI: 1099511627776,
		TIB: 1099511627776,
	}
	const mult = table[unit]
	if (!mult) throw new Error(`Unknown size unit: ${unit}`)
	return Math.ceil(val * mult)
}

function fmtBytes(bytes: number): string {
	const units = ["B", "KiB", "MiB", "GiB", "TiB"]
	let size = bytes
	let i = 0
	while (size >= 1024 && i < units.length - 1) {
		size /= 1024
		i++
	}
	return `${i === 0 ? size : size.toFixed(2)} ${units[i]}`
}

function toSectors(bytes: number): number {
	return Math.ceil(bytes / SECTOR)
}

function toBytes(sectors: number): number {
	return sectors * SECTOR
}

function getMountPoint(device: string): string {
	const out = execSync(`findmnt -n -o TARGET ${q(device)}`, {
		encoding: "utf-8",
	}).trim()
	return out.split("\n")[0]
}

function getBtrfsInfo(device: string, mount: string): BtrfsInfo {
	const showOut = execSync(`sudo btrfs filesystem show --raw ${q(device)}`, {
		encoding: "utf-8",
	})
	const deviceSize = Number(/devid\s+\d+\s+size\s+(\d+)/.exec(showOut)![1])
	const minOut = execSync(`sudo btrfs inspect-internal min-dev-size ${q(mount)}`, {
		encoding: "utf-8",
	}).trim()
	const minSize = Number(minOut)
	return { deviceSize, minSize }
}

function getPartInfo(disk: string, part: number): PartInfo {
	const out = execSync(`sudo sgdisk -i ${part} ${q(disk)}`, {
		encoding: "utf-8",
	})
	const typeGuid = /Partition GUID code:\s+([\w-]+)/.exec(out)![1]
	const uniqueGuid = /Partition unique GUID:\s+([\w-]+)/.exec(out)![1]
	const startSector = Number(/First sector:\s+(\d+)/.exec(out)![1])
	const endSector = Number(/Last sector:\s+(\d+)/.exec(out)![1])
	return { startSector, endSector, typeGuid, uniqueGuid }
}

function getLastPartNumber(disk: string): number {
	const out = execSync(`sudo sgdisk -p ${q(disk)}`, { encoding: "utf-8" })
	const lines = out
		.trim()
		.split("\n")
		.filter((l) => /^\s*\d+/.test(l))
	return Number(lines[lines.length - 1].trim().split(/\s+/)[0])
}

function stepSwapoff(dryRun: boolean): void {
	sh("sudo swapoff -a", dryRun)
}

function stepBtrfsResize(
	targetBytes: number,
	mount: string,
	dryRun: boolean,
): void {
	sh(`sudo btrfs filesystem resize ${targetBytes} ${q(mount)}`, dryRun)
}

function stepShrinkPartition(
	disk: string,
	part: number,
	info: PartInfo,
	newEnd: number,
	dryRun: boolean,
): void {
	sh(
		`sudo sgdisk -d ${part} ` +
			`-n ${part}:${info.startSector}:${newEnd} ` +
			`-t ${part}:${info.typeGuid} ` +
			`-u ${part}:${info.uniqueGuid} ${q(disk)}`,
		dryRun,
	)
}

function stepCreateSwapPartition(
	disk: string,
	partNum: number,
	startSector: number,
	endSector: number,
	dryRun: boolean,
): void {
	sh(
		`sudo sgdisk -n ${partNum}:${startSector}:${endSector} -t ${partNum}:${SWAP_HEX} ${q(disk)}`,
		dryRun,
	)
}

function stepPartprobe(disk: string, dryRun: boolean): void {
	sh(`sudo partprobe ${q(disk)}`, dryRun)
}

function stepMkswap(device: string, dryRun: boolean): void {
	sh(`sudo mkswap ${q(device)}`, dryRun)
}

function makePlan(
	disk: string,
	partStr: string,
	mode: "shrink" | "target" | "match",
	sizeBytes?: number,
): Plan {
	const device = partPath(disk, partStr)
	const partition = partNumber(partStr)
	const mountPoint = getMountPoint(device)
	const btrfs = getBtrfsInfo(device, mountPoint)
	const partInfo = getPartInfo(disk, partition)
	const lastPart = getLastPartNumber(disk)

	let targetBytes: number
	let doResize: boolean

	if (mode === "shrink") {
		targetBytes = btrfs.deviceSize - sizeBytes!
		doResize = true
	} else if (mode === "target") {
		targetBytes = sizeBytes!
		doResize = true
	} else {
		targetBytes = btrfs.deviceSize
		doResize = false
	}

	if (targetBytes < btrfs.minSize) {
		throw new Error(
			`Target ${targetBytes} bytes (${fmtBytes(targetBytes)}) below minimum ${btrfs.minSize} bytes (${fmtBytes(btrfs.minSize)}). ` +
				`Max shrink: ${btrfs.deviceSize - btrfs.minSize} bytes`,
		)
	}

	const partSizeBytes = toBytes(partInfo.endSector - partInfo.startSector + 1)
	if (targetBytes >= partSizeBytes) {
		throw new Error(
			`Btrfs device size ${targetBytes} bytes (${fmtBytes(targetBytes)}) >= partition size ${partSizeBytes} bytes (${fmtBytes(partSizeBytes)}). Nothing to do.`,
		)
	}

	const newEndSector = partInfo.startSector + toSectors(targetBytes) - 1
	const swapStartSector = newEndSector + 1

	if (swapStartSector >= partInfo.endSector) {
		throw new Error("No space freed for swap partition")
	}

	return {
		device,
		mountPoint,
		disk,
		partStr,
		partition,
		btrfsCurrentBytes: btrfs.deviceSize,
		btrfsMinBytes: btrfs.minSize,
		btrfsTargetBytes: targetBytes,
		doBtrfsResize: doResize,
		partStartSector: partInfo.startSector,
		partCurrentEndSector: partInfo.endSector,
		partNewEndSector: newEndSector,
		swapPartNumber: lastPart + 1,
		swapStartSector,
		swapEndSector: partInfo.endSector,
	}
}

function displayPlan(p: Plan): void {
	const swapPStr = swapPartStr(p.partStr, p.swapPartNumber)
	const swapDev = partPath(p.disk, swapPStr)
	const swapSectors = p.swapEndSector - p.swapStartSector + 1

	console.log()
	console.log("=== Btrfs Resize Plan ===")
	console.log()
	console.log(`Device:          ${p.device}`)
	console.log(`Mount:           ${p.mountPoint}`)
	console.log(`Disk:            ${p.disk}`)
	console.log()
	console.log("--- Btrfs ---")
	console.log(`Current size:    ${p.btrfsCurrentBytes} bytes (${fmtBytes(p.btrfsCurrentBytes)})`)
	console.log(`Minimum size:    ${p.btrfsMinBytes} bytes (${fmtBytes(p.btrfsMinBytes)})`)
	console.log(`Target size:     ${p.btrfsTargetBytes} bytes (${fmtBytes(p.btrfsTargetBytes)})`)
	console.log(`Resize btrfs:    ${p.doBtrfsResize}`)
	console.log()
	console.log("--- Partition Layout (sector size: ${SECTOR} bytes) ---")
	console.log(`Partition ${p.partition}:`)
	console.log(`  Start sector:  ${p.partStartSector}`)
	console.log(
		`  Current end:   ${p.partCurrentEndSector}  (${fmtBytes(
			toBytes(p.partCurrentEndSector - p.partStartSector + 1),
		)})`,
	)
	console.log(
		`  New end:       ${p.partNewEndSector}  (${fmtBytes(
			toBytes(p.partNewEndSector - p.partStartSector + 1),
		)})`,
	)
	console.log(`Partition ${p.swapPartNumber} (swap):`)
	console.log(`  Start sector:  ${p.swapStartSector}`)
	console.log(`  End sector:    ${p.swapEndSector}`)
	console.log(`  Size:          ${fmtBytes(toBytes(swapSectors))}`)
	console.log(`  Device:        ${swapDev}`)
	console.log()
	console.log("--- Execution Steps ---")
	const steps = ["swapoff -a"]
	if (p.doBtrfsResize) {
		steps.push(`btrfs filesystem resize ${p.btrfsTargetBytes} ${p.mountPoint}`)
	}
	steps.push(
		`sgdisk: recreate partition ${p.partition} (start=${p.partStartSector}, end=${p.partNewEndSector})`,
		`sgdisk: create partition ${p.swapPartNumber} (start=${p.swapStartSector}, end=${p.swapEndSector}, type=swap)`,
		`partprobe ${p.disk}`,
		`mkswap ${swapDev}`,
	)
	steps.forEach((s, i) => console.log(`  ${i + 1}. ${s}`))
	console.log()
}

function executePlan(p: Plan, dryRun: boolean): void {
	const swapPStr = swapPartStr(p.partStr, p.swapPartNumber)
	const swapDev = partPath(p.disk, swapPStr)
	const partInfo = getPartInfo(p.disk, p.partition)

	console.log(dryRun ? "\n=== DRY RUN ===\n" : "\n=== EXECUTING ===\n")

	console.log("Step 1: Disable swap")
	stepSwapoff(dryRun)

	if (p.doBtrfsResize) {
		console.log("Step 2: Resize btrfs filesystem")
		stepBtrfsResize(p.btrfsTargetBytes, p.mountPoint, dryRun)
	} else {
		console.log("Step 2: (skipped — btrfs already resized)")
	}

	console.log("Step 3: Shrink partition")
	stepShrinkPartition(
		p.disk,
		p.partition,
		partInfo,
		p.partNewEndSector,
		dryRun,
	)

	console.log("Step 4: Create swap partition")
	stepCreateSwapPartition(
		p.disk,
		p.swapPartNumber,
		p.swapStartSector,
		p.swapEndSector,
		dryRun,
	)

	console.log("Step 5: Re-read partition table")
	stepPartprobe(p.disk, dryRun)

	console.log("Step 6: Format swap")
	stepMkswap(swapDev, dryRun)

	console.log()
	if (dryRun) {
		console.log("Dry run complete. Pass -x to execute for real.")
	} else {
		console.log("Done. Add to /etc/fstab:")
		console.log(`  UUID=<check blkid> none swap defaults 0 0`)
	}
	console.log()
}

function main(): void {
	const { values, positionals } = parseArgs({
		options: {
			shrink: { type: "string", short: "s" },
			target: { type: "string", short: "t" },
			execute: { type: "boolean", short: "x", default: false },
			help: { type: "boolean", short: "h", default: false },
		},
		allowPositionals: true,
	})

	if (values.help) {
		console.log(
			`Usage: btrfs-resize.ts <disk> <partition> [--shrink <size> | --target <size>] [-x]

Modes:
  (no flag)     Match partition to current btrfs size (btrfs already resized)
  --shrink N    Shrink btrfs by N amount (e.g., 64GiB, 128G)
  --target N    Resize btrfs to N (e.g., 400GiB)

Flags:
  -x, --execute   Execute changes (default: dry run)
  -h, --help      Show this help

Examples:
  btrfs-resize.ts /dev/sda 6                           # dry run, match partition
  btrfs-resize.ts /dev/sda 6 --shrink 64GiB            # dry run, shrink by 64GiB
  btrfs-resize.ts /dev/nvme0n1 p3 --target 400GiB -x   # execute, resize to 400GiB`,
		)
		process.exit(0)
	}

	const [disk, partStr] = positionals
	if (!disk || !partStr) {
		console.error("Error: <disk> and <partition> required (e.g., /dev/nvme0n1 p6)")
		process.exit(1)
	}

	const partition = partNumber(partStr)
	if (!Number.isInteger(partition) || partition < 1) {
		console.error("Error: partition string must end with a positive integer")
		process.exit(1)
	}

	if (values.shrink && values.target) {
		console.error("Error: --shrink and --target are mutually exclusive")
		process.exit(1)
	}

	let mode: "shrink" | "target" | "match"
	let sizeBytes: number | undefined

	if (values.shrink) {
		mode = "shrink"
		sizeBytes = parseSize(values.shrink)
	} else if (values.target) {
		mode = "target"
		sizeBytes = parseSize(values.target)
	} else {
		mode = "match"
	}

	const dryRun = !values.execute

	try {
		const plan = makePlan(disk, partStr, mode, sizeBytes)
		displayPlan(plan)
		executePlan(plan, dryRun)
	} catch (err) {
		console.error(`\nError: ${err instanceof Error ? err.message : err}\n`)
		process.exit(1)
	}
}

main()
