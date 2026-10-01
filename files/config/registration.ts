/** Coherent input-registration batches with one caller-owned assembly operation.
 * Rollback covers ordinary failures, not crash atomicity or concurrent writers. */
import { mkdtemp, rm } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize } from "node:path";
import { tmpdir } from "node:os";
import { captureFile } from "./capture.ts";
import { inspectDeliveryEntry, localLinkDeliveryExecutor, pathsSharePhysicalEntry, replaceWithCopy, replaceWithLink, type DeliveryEntry } from "../links/delivery.ts";

export type InputRegistration = { source: string; destination: string; strategy: "copy" | "link"; disabledSuffix?: string; initiallyDisabled?: boolean };
export type RegisteredInput = { path: string; disabled: boolean };

export async function withInputBatch<T>(records: readonly InputRegistration[], operation: (inputs: RegisteredInput[]) => Promise<T>, options: {
  success: (result: T) => boolean; workspaceRoot?: string;
}): Promise<T> {
  const selected: { record: InputRegistration; path: string; disabled: boolean; previous: DeliveryEntry; backup?: string }[] = [];
  for (const record of records) {
    if (!isAbsolute(record.source) || !isAbsolute(record.destination) || /[\0\r\n\t]/.test(record.source + record.destination)) throw new Error("registration paths must be absolute concrete paths");
    if (record.strategy !== "copy" && record.strategy !== "link") throw new Error("registration strategy must be copy or link");
    if (record.disabledSuffix !== undefined && !/^\.[A-Za-z0-9_.-]+$/.test(record.disabledSuffix)) throw new Error("invalid registration disabled suffix");
    if (!(await captureFile(record.source)).bytes) throw new Error(`registration source missing or dangling: ${record.source}`);
    const active = await inspectDeliveryEntry(record.destination);
    const disabledPath = record.disabledSuffix ? record.destination + record.disabledSuffix : undefined;
    const disabled = disabledPath ? await inspectDeliveryEntry(disabledPath) : { kind: "missing" as const };
    if (active.kind !== "missing" && disabled.kind !== "missing") throw new Error(`both enabled and disabled registration entries exist: ${record.destination}`);
    const useDisabled = disabled.kind !== "missing" || (active.kind === "missing" && (record.initiallyDisabled ?? false));
    if (useDisabled && !disabledPath) throw new Error("disabled registration requires a suffix");
    const path = normalize(useDisabled ? disabledPath! : record.destination);
    const previous = useDisabled ? disabled : active;
    if (previous.kind === "directory" || previous.kind === "special") throw new Error(`registration destination is not replaceable: ${path}`);
    if (await pathsSharePhysicalEntry(record.source, path)) throw new Error(`registration aliases donor: ${path}`);
    for (const other of selected) {
      // Compare BOTH active and disabled slots: one record may not choose the
      // other's dormant alternate and thereby create an enabled/disabled pair.
      for (const first of [record.destination, disabledPath].filter((value): value is string => !!value))
        for (const second of [other.record.destination, other.record.disabledSuffix ? other.record.destination + other.record.disabledSuffix : undefined].filter((value): value is string => !!value))
          if (await pathsSharePhysicalEntry(first, second)) throw new Error(`registration batch claims the same slot: ${path}`);
    }
    selected.push({ record, path, disabled: useDisabled, previous });
  }
  const workspace = await mkdtemp(join(options.workspaceRoot ?? tmpdir(), "config-input-batch-"));
  let mutated = 0;
  let accepted = false;
  const restore = async (): Promise<void> => {
    for (const entry of selected.slice(0, mutated).reverse()) {
      if (entry.previous.kind === "missing") await rm(entry.path, { force: true });
      else if (entry.previous.kind === "file") await replaceWithCopy(entry.backup!, entry.path);
      else if (entry.previous.kind === "symlink") {
        const temporary = join(dirname(entry.path), `.registration-restore-${process.pid}-${Math.random().toString(16).slice(2)}`);
        try { await localLinkDeliveryExecutor.symlink(entry.previous.target, temporary); await localLinkDeliveryExecutor.rename(temporary, entry.path); }
        finally { await localLinkDeliveryExecutor.rm(temporary); }
      }
    }
    mutated = 0;
  };
  try {
    for (const [index, entry] of selected.entries()) if (entry.previous.kind === "file") {
      entry.backup = join(workspace, `previous-${index}`);
      await replaceWithCopy(entry.path, entry.backup);
    }
    for (const entry of selected) {
      if (entry.record.strategy === "link") await replaceWithLink(entry.record.source, entry.path);
      else await replaceWithCopy(entry.record.source, entry.path);
      mutated++;
    }
    const result = await operation(selected.map(({ path, disabled }) => ({ path, disabled })));
    accepted = options.success(result);
    if (!accepted) await restore();
    return result;
  } catch (error) {
    if (!accepted) await restore();
    throw error;
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
}
