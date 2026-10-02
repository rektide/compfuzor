/**
 * Shared mutable input-registration batch, separate from native material placement.
 * It reads sources/slots, backs up prior regular entries privately and uses existing
 * copy/link primitives to refresh explicitly declared source registrations. Exactly
 * one caller operation runs after the entire batch is available, so action/binding
 * resources do not trigger two half-graph rebuilds.
 * Normal failure restores prior chosen entries, including disabled state and literal
 * symlink targets. This is not the CONFIG artifact publisher, crash atomicity or
 * concurrent-reader/writer isolation; the callback owns its CONFIG commit outcome.
 * @see /doc/config/keybinding-producers.md
 */
import { mkdtemp, rm } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize } from "node:path";
import { tmpdir } from "node:os";
import { captureFile } from "./capture.ts";
import {
  inspectDeliveryEntry,
  localLinkDeliveryExecutor,
  pathsSharePhysicalEntry,
  replaceWithCopy,
  replaceWithLink,
  type DeliveryEntry,
} from "../links/delivery.ts";

/** One explicit managed source refresh; these copies are not editable native receiver copies. */
export type InputRegistration = {
  /** Concrete absolute usable donor path, provided by producer/batch declaration. */
  source: string;
  /** Concrete absolute ACTIVE slot; an existing disabled alternate remains selected. */
  destination: string;
  /** Source copy/link refresh policy; producer reinstall refreshes either deliberately. */
  strategy: "copy" | "link";
  /** Alternate slot suffix; both enabled and disabled slots present is a preflight error. */
  disabledSuffix?: string;
  /** Initial state only when no slot exists; never overrides an existing enabled/disabled state. */
  initiallyDisabled?: boolean;
};
/** Selected refreshed slot supplied to the single coherent callback. */
export type RegisteredInput = {
  /** Actual chosen entry, possibly the disabled alternate rather than active destination. */
  path: string;
  /** Retained/initial disabled state; caller source selection must not re-enable it implicitly. */
  disabled: boolean;
};

/**
 * Refresh a closed registration batch, invoke one operation and accept only its
 * explicit success result. Preflight checks both active/disabled slot claims and
 * each destination against EVERY donor's symlink chain/physical-parent aliases;
 * an earlier registration must not overwrite a later donor. Copying donor bytes
 * alone would not make requested link topology safe.
 *
 * Normal non-success or thrown operation errors restore old entries/new-slot
 * absence. No crash-atomicity or concurrent-writer isolation is supplied. The
 * callback must not treat a completed CONFIG commit as preparation; a thrown
 * post-commit failure cannot make the artifact mutation un-happen. Cleanup errors
 * may surface after accepted publication and must not be advertised as safe retry.
 * @param records Explicit absolute source/slot declarations; no filesystem scan adds records.
 * @param operation Runs once only after all registrations are present, with chosen slot states.
 * @param options Caller success predicate and private backup parent.
 * @returns The operation result after acceptance or ordinary restoration; non-success
 * remains a non-success result rather than silently becoming a successful install.
 * @throws On source/slot/alias preflight, delivery, callback, restoration or cleanup failure.
 */
export async function withInputBatch<T>(
  records: readonly InputRegistration[],
  operation: (inputs: RegisteredInput[]) => Promise<T>,
  options: {
    /** True accepts the callback outcome; e.g. consumer code === 0, not a premature metadata save. */
    success: (result: T) => boolean;
    /** Private backup directory parent; defaults to platform temp, never a live output tree. */
    workspaceRoot?: string;
  },
): Promise<T> {
  const selected: {
    record: InputRegistration;
    path: string;
    disabled: boolean;
    previous: DeliveryEntry;
    backup?: string;
  }[] = [];
  for (const record of records) {
    if (
      !isAbsolute(record.source) ||
      !isAbsolute(record.destination) ||
      /[\0\r\n\t]/.test(record.source + record.destination)
    )
      throw new Error("registration paths must be absolute concrete paths");
    if (record.strategy !== "copy" && record.strategy !== "link")
      throw new Error("registration strategy must be copy or link");
    if (record.disabledSuffix !== undefined && !/^\.[A-Za-z0-9_.-]+$/.test(record.disabledSuffix))
      throw new Error("invalid registration disabled suffix");
    if (!(await captureFile(record.source)).bytes)
      throw new Error(`registration source missing or dangling: ${record.source}`);
    const active = await inspectDeliveryEntry(record.destination);
    const disabledPath = record.disabledSuffix
      ? record.destination + record.disabledSuffix
      : undefined;
    const disabled = disabledPath
      ? await inspectDeliveryEntry(disabledPath)
      : { kind: "missing" as const };
    if (active.kind !== "missing" && disabled.kind !== "missing")
      throw new Error(
        `both enabled and disabled registration entries exist: ${record.destination}`,
      );
    const useDisabled =
      disabled.kind !== "missing" ||
      (active.kind === "missing" && (record.initiallyDisabled ?? false));
    if (useDisabled && !disabledPath) throw new Error("disabled registration requires a suffix");
    const path = normalize(useDisabled ? disabledPath! : record.destination);
    const previous = useDisabled ? disabled : active;
    if (previous.kind === "directory" || previous.kind === "special")
      throw new Error(`registration destination is not replaceable: ${path}`);
    if (await pathsSharePhysicalEntry(record.source, path))
      throw new Error(`registration aliases donor: ${path}`);
    for (const other of selected) {
      // Compare BOTH active and disabled slots: one record may not choose the
      // other's dormant alternate and thereby create an enabled/disabled pair.
      for (const first of [record.destination, disabledPath].filter(
        (value): value is string => !!value,
      ))
        for (const second of [
          other.record.destination,
          other.record.disabledSuffix
            ? other.record.destination + other.record.disabledSuffix
            : undefined,
        ].filter((value): value is string => !!value))
          if (await pathsSharePhysicalEntry(first, second))
            throw new Error(`registration batch claims the same slot: ${path}`);
    }
    selected.push({ record, path, disabled: useDisabled, previous });
  }
  // Reject a destination that can alter ANY donor, not just its own. Copying
  // donor bytes alone would not make staged symlink semantics safe here.
  for (const entry of selected) {
    const slots = [entry.record.destination, entry.record.disabledSuffix ? entry.record.destination + entry.record.disabledSuffix : undefined].filter((path): path is string => !!path);
    for (const slot of slots) for (const donor of records) {
      let source = donor.source;
      const seen = new Set<string>();
      while (!seen.has(source)) {
        seen.add(source);
        if (await pathsSharePhysicalEntry(slot, source)) throw new Error(`registration destination aliases a batch donor: ${slot}`);
        const state = await inspectDeliveryEntry(source);
        if (state.kind !== "symlink") break;
        source = state.targetPath;
      }
    }
  }
  const workspace = await mkdtemp(join(options.workspaceRoot ?? tmpdir(), "config-input-batch-"));
  let mutated = 0;
  let accepted = false;
  const restore = async (): Promise<void> => {
    for (const entry of selected.slice(0, mutated).reverse()) {
      if (entry.previous.kind === "missing") await rm(entry.path, { force: true });
      else if (entry.previous.kind === "file") await replaceWithCopy(entry.backup!, entry.path);
      else if (entry.previous.kind === "symlink") {
        const temporary = join(
          dirname(entry.path),
          `.registration-restore-${process.pid}-${Math.random().toString(16).slice(2)}`,
        );
        try {
          await localLinkDeliveryExecutor.symlink(entry.previous.target, temporary);
          await localLinkDeliveryExecutor.rename(temporary, entry.path);
        } finally {
          await localLinkDeliveryExecutor.rm(temporary);
        }
      }
    }
    mutated = 0;
  };
  try {
    for (const [index, entry] of selected.entries())
      if (entry.previous.kind === "file") {
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
