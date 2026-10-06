#!/usr/bin/env node
// Focused metadata/config tests; no network or host configuration writes.
//
// Ported from test_retrieve.py. Run directly with Node (no build step):
//
//     node files/linux-config-debplus/debian/test-retrieve.ts
//
// Uses the stdlib node:test runner so a deployed copy of the bundle needs no
// node_modules.

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import * as retrieve from "./retrieve.ts";

test("folded metadata", () => {
  const result = retrieve.records("Package: a\nDepends: b,\n c (= 1)\n\nPackage: d\nVersion: 2\n");
  assert.equal(result[0]["Depends"], "b,\nc (= 1)");
  assert.equal(result[1]["Package"], "d");
});

test("meta exact dependency beats later unreferenced headers", () => {
  const [selected, meta] = retrieve.selectPackage([
    { "Package": "linux-headers-amd64", "Version": "7.2.8-1",
      "Depends": "linux-base-amd64 (= 7.2.8-1), linux-headers-7.2.8+deb14-amd64 (= 7.2.8-1)" },
    { "Package": "linux-headers-7.2.8+deb14-amd64", "Version": "7.2.8-1" },
    { "Package": "linux-headers-7.3-amd64", "Version": "7.3-1" },
  ]);
  assert.equal(selected!["Version"], "7.2.8-1");
  assert.equal(meta!["Package"], "linux-headers-amd64");
});

test("fallback uses Debian not lexical versions and excludes flavours", () => {
  const [selected, meta] = retrieve.selectPackage([
    { "Package": "linux-headers-7.2.9-amd64", "Version": "7.2.9-1" },
    { "Package": "linux-headers-7.2.10-amd64", "Version": "7.2.10-1" },
    { "Package": "linux-headers-7.3-rt-amd64", "Version": "7.3-1" },
    { "Package": "linux-headers-7.3-cloud-amd64", "Version": "7.3-1" },
  ]);
  assert.equal(selected!["Version"], "7.2.10-1");
  assert.equal(meta, null);
});

test("experimental absence is not unstable fallback", () => {
  const [selected, meta] = retrieve.selectPackage([]);
  assert.deepEqual([selected, meta], [null, null]);
});

test("incomplete meta fails", () => {
  assert.throws(() => retrieve.selectPackage([
    { "Package": "linux-headers-amd64", "Version": "1", "Depends": "missing" },
  ]));
});

test("checksum failure", () => {
  assert.throws(
    () => retrieve.checked(Buffer.from("corrupt"), retrieve.sha(Buffer.from("expected"))),
    /SHA-256 mismatch/);
});

test("index release checksum", () => {
  const digest = "a".repeat(64);
  const release = `SHA256:\n ${digest} 42 main/binary-amd64/Packages.xz\nDate: now\n`;
  assert.deepEqual(retrieve.releaseIndex(Buffer.from(release)), [digest, 42]);
});

test("absence is not disabled and metadata is not policy", () => {
  const before = retrieve.parseConfig("CONFIG_GCC_VERSION=160000\n# CONFIG_RUST is not set\n");
  const after = retrieve.parseConfig("CONFIG_GCC_VERSION=0\nCONFIG_RUST=y\nCONFIG_NEW=y\n");
  assert.equal(
    retrieve.delta(before, after, null, true),
    "NEW: <absent> -> y\nRUST: n -> y\n");
});

test("required intent distinguishes inherited match and missing value", () => {
  const result = retrieve.requiredAudit({ "RUST": "y", "DEBUG_INFO_BTF": "y" }, { "RUST": "y" }, {});
  assert.equal((result["RUST"] as Record<string, unknown>)["fulfilled"], true);
  assert.equal((result["RUST"] as Record<string, unknown>)["declaration"], "inherited/not explicitly declared");
  assert.equal((result["DEBUG_INFO_BTF"] as Record<string, unknown>)["fulfilled"], false);
});

test("merge replaces prior assignments without duplicate symbols", () => {
  const text = retrieve.mergedConfig("CONFIG_X=y\nCONFIG_Y=m\n", "# CONFIG_X is not set\nCONFIG_Z=y\n");
  assert.deepEqual({ ...retrieve.parseConfig(text) }, { "X": "n", "Y": "m", "Z": "y" });
  assert.equal(text.split("\n").filter((line) => line !== "").length, 3);
});

test("debug info is derived from declared selectable choice", () => {
  const result = retrieve.requiredAudit(
    { "DEBUG_INFO": "y" }, { "DEBUG_INFO": "y" },
    { "DEBUG_KERNEL": "y", "DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT": "y" });
  assert.equal((result["DEBUG_INFO"] as Record<string, unknown>)["fulfilled"], true);
  assert.equal(
    (result["DEBUG_INFO"] as Record<string, unknown>)["declaration"],
    "derived from explicitly declared debug-information choice");
});

test("kernel export does not inherit parent repository head", () => {
  const scratch = join(process.cwd(), ".test-agent", "linux-debian-retrieval", "git-provenance-tests");
  mkdirSync(scratch, { recursive: true });
  const directory = mkdtempSync(join(scratch, "git-provenance-"));
  try {
    const repository = join(directory, "parent-repository");
    mkdirSync(repository);
    spawnSync("git", ["init", "-q", repository], { encoding: "utf8" });
    spawnSync(
      "git",
      ["-C", repository, "-c", "user.name=Config audit test",
        "-c", "user.email=config-audit@example.invalid", "commit", "-q", "--allow-empty",
        "-m", "Fixture parent HEAD"],
      { encoding: "utf8" });
    const expected = spawnSync("git", ["-C", repository, "rev-parse", "HEAD"], { encoding: "utf8" })
      .stdout.trim();
    const exportTree = join(repository, "plain-kernel-export");
    mkdirSync(exportTree);
    assert.equal(retrieve.kernelGitHead(repository), expected);
    assert.equal(retrieve.kernelGitHead(exportTree), null);
    const alias = join(directory, "repository-alias");
    symlinkSync(repository, alias);
    assert.equal(retrieve.kernelGitHead(alias), expected);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
