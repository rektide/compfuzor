import assert from "node:assert/strict";
import { execFile as callbackExecFile } from "node:child_process";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";
import { oid, pinRef, receiptRef } from "../../src/custody/codec.ts";
import type { PinIntent, RefName } from "../../src/custody/model.ts";
import {
  decideInstallation,
  GitRefStore,
  installImmutableRefs,
  prefixConflict,
} from "../../src/recovery/transaction.ts";

const exec = promisify(callbackExecFile);
async function git(dest: string, ...args: string[]): Promise<string> {
  const { stdout } = await exec("git", ["-C", dest, ...args]);
  return stdout.trim();
}
async function fixture(t: {
  after: (cleanup: () => Promise<void>) => void;
}): Promise<{ dest: string; first: ReturnType<typeof oid>; second: ReturnType<typeof oid> }> {
  const scratch = join(process.cwd(), ".test-agent", "recovery");
  await mkdir(scratch, { recursive: true });
  const dest = await mkdtemp(join(scratch, "fixture-"));
  t.after(() => rm(dest, { recursive: true, force: true }));
  await git(dest, "init", "-q");
  await git(dest, "config", "user.name", "Fixture");
  await git(dest, "config", "user.email", "fixture@example.invalid");
  await writeFile(join(dest, "file"), "first");
  await git(dest, "add", "file");
  await git(dest, "commit", "-qm", "first");
  const first = oid(await git(dest, "rev-parse", "HEAD"), "sha1");
  await writeFile(join(dest, "file"), "second");
  await git(dest, "commit", "-qam", "second");
  const second = oid(await git(dest, "rev-parse", "HEAD"), "sha1");
  return { dest, first, second };
}
function pin(target: ReturnType<typeof oid>): PinIntent {
  const input = {
    sourceKind: "branch",
    sourceName: "refs/heads/head",
    sourceOid: target,
    destinationOid: target,
  } as const;
  return { ...input, objectType: "commit", destinationRef: pinRef(input, "legacy", "g0") };
}

test("atomic install: identical retry no-op, partial matching receipt resumes only missing pin", async (t) => {
  const { dest, first, second } = await fixture(t);
  const store = new GitRefStore(dest, "sha1");
  const receipt = receiptRef("legacy", "g0");
  const branch = pin(first);
  const other: PinIntent = {
    ...pin(second),
    sourceKind: "head",
    sourceName: "HEAD",
    destinationRef: pinRef(
      { sourceKind: "head", sourceName: "HEAD", sourceOid: second, destinationOid: second },
      "legacy",
      "g0",
    ),
  };
  const input = {
    receiptRef: receipt,
    receiptCommitOid: first,
    pins: [branch, other],
    matchingReceiptApproved: false,
  };
  const installed = await installImmutableRefs(store, input);
  assert.equal(installed.created.length, 3);
  assert.equal(await git(dest, "rev-parse", receipt), first);
  assert.equal(await git(dest, "rev-parse", branch.destinationRef), first);
  assert.equal(await git(dest, "rev-parse", other.destinationRef), second);
  await assert.rejects(installImmutableRefs(store, input), /receipt has not passed same-input/);
  const retry = await installImmutableRefs(store, { ...input, matchingReceiptApproved: true });
  assert.equal(retry.changed, false);
  // Simulate an interrupted/external receipt-first state, not a normal expected outcome.
  await git(dest, "update-ref", "-d", other.destinationRef);
  const resumed = await installImmutableRefs(store, { ...input, matchingReceiptApproved: true });
  assert.deepEqual(resumed.created, [other.destinationRef]);
  assert.equal(await git(dest, "rev-parse", receipt), first);
  assert.equal(await git(dest, "rev-parse", other.destinationRef), second);
});

test("occupied old harvest prefixes and different receipt block without changing existing refs", async (t) => {
  const { dest, first, second } = await fixture(t);
  const store = new GitRefStore(dest, "sha1");
  await git(dest, "update-ref", "refs/heads/harvest/legacy/head", first);
  const receipt = receiptRef("legacy", "g0");
  await assert.rejects(
    installImmutableRefs(store, {
      receiptRef: receipt,
      receiptCommitOid: first,
      pins: [pin(first)],
      matchingReceiptApproved: false,
    }),
    /legacy harvest namespace/,
  );
  assert.equal((await store.list()).has(receipt), false);
  assert.equal(await git(dest, "rev-parse", "refs/heads/harvest/legacy/head"), first);
  await git(dest, "update-ref", receipt, second);
  await assert.rejects(
    installImmutableRefs(store, {
      receiptRef: receipt,
      receiptCommitOid: first,
      pins: [],
      matchingReceiptApproved: true,
    }),
    /another OID/,
  );
  assert.equal(await git(dest, "rev-parse", receipt), second);
});

test("concurrent creation after observation fails whole transaction, never replaces either ref", async (t) => {
  const { dest, first, second } = await fixture(t);
  const store = new GitRefStore(dest, "sha1");
  const receipt = receiptRef("legacy", "g0");
  const branch = pin(first);
  const racingStore = {
    list: () => store.list(),
    createAtomically: async (refs: readonly { ref: RefName; oid: ReturnType<typeof oid> }[]) => {
      await git(dest, "update-ref", branch.destinationRef, second);
      await store.createAtomically(refs);
    },
  };
  await assert.rejects(
    installImmutableRefs(racingStore, {
      receiptRef: receipt,
      receiptCommitOid: first,
      pins: [branch],
      matchingReceiptApproved: false,
    }),
    /atomic compare-and-create failed/,
  );
  assert.equal((await store.list()).has(receipt), false);
  assert.equal(await git(dest, "rev-parse", branch.destinationRef), second);
});

test("pure decision rejects pins installed without receipt and prefix-colliding planned pins", () => {
  const expected = receiptRef("legacy", "g0");
  const branch = pin(oid("1".repeat(40), "sha1"));
  assert.equal(prefixConflict("refs/heads/harvest/legacy/head", branch.destinationRef), false);
  assert.equal(prefixConflict("refs/heads/harvest/legacy", branch.destinationRef), true);
  assert.throws(
    () =>
      decideInstallation(new Map([[branch.destinationRef, branch.destinationOid]]), {
        receiptRef: expected,
        receiptCommitOid: branch.sourceOid,
        pins: [branch],
        matchingReceiptApproved: false,
      }),
    /without an approved matching receipt/,
  );
});
