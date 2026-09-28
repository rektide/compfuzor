/** Explicit local Git custody: read-only plan unless --apply is supplied. */
import { Console, Effect, Option } from "effect";
import { Command, Flag } from "effect/cli";
import { applyAdoption } from "../../custody/apply.ts";
import { canonicalJson, sha256 } from "../../custody/codec.ts";
import { planAdoption } from "../../custody/inventory.ts";
import type { AdoptInput, Issue, PlanV1 } from "../../custody/model.ts";
import { destFlag, labelFlag, repoFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";

const optionalPath = (name: string, description: string) =>
  Flag.optional(Flag.String(name).pipe(Flag.withDescription(description)));

const issueLines = (title: string, issues: readonly Issue[]): string[] =>
  issues.map(
    ({ code, subject, reason }) =>
      `${title} ${code}${subject === null ? "" : ` (${subject})`}: ${reason}`,
  );

const renderPlan = (plan: PlanV1): string => {
  const snapshotDigest =
    plan.state === "blocked"
      ? (plan.proposedSnapshot?.manifestSha256 ?? "not available")
      : plan.proposedSnapshot === null
        ? "none (clean HEAD)"
        : sha256(new TextEncoder().encode(`${canonicalJson(plan.proposedSnapshot.paths)}\n`));
  const lines = [
    `Adoption plan: ${plan.state} (no destination changes)`,
    `HEAD manifest SHA-256: ${plan.headManifestSha256 ?? "not observed"}`,
    `Snapshot manifest SHA-256: ${snapshotDigest}`,
    `Selected local remote baseline: ${plan.baselines?.sourceRemoteTracking.length ?? "not observed"} locally recorded tip(s); freshness is not proven`,
    `Selected tips not in destination: ${plan.baselines?.selectedTipsNotInDestination ?? "unknown"}`,
    ...issueLines("BLOCKER", plan.blockers),
    ...issueLines("WARNING", plan.warnings),
    ...issueLines("RETIREMENT UNRESOLVED", plan.retirementUnresolved),
  ];
  if (plan.blockers.some(({ code }) => code === "destination-missing"))
    lines.push(
      "Initialize the destination separately with refresh; adopt never clones or initializes it.",
    );
  if (plan.state === "blocked" && plan.proposedSnapshot !== null)
    lines.push(
      `Snapshot review requirements: ${plan.proposedSnapshot.reviewRequirements.sensitivePaths.length} sensitive path(s); staged/unstaged approval ${plan.proposedSnapshot.reviewRequirements.stagedVsUnstagedApprovalRequired ? "required" : "not required"}. Use --json for the complete manifest and exact path/mode/blob identities.`,
    );
  if (plan.state === "ready")
    lines.push(
      `Exact local path review: ${plan.proposedSnapshot?.pathReview == null && plan.cleanHeadPathReview === null ? "not required" : "recorded"}. Use --json for complete manifest and review evidence.`,
    );
  lines.push(
    "Git custody does not establish publication safety, off-host backup, or retirement readiness.",
  );
  return lines.join("\n");
};

export const adoptCommand: AnyCommand = Command.make(
  "adopt",
  {
    legacy: Flag.String("legacy").pipe(Flag.withDescription("Standalone legacy Git checkout")),
    dest: destFlag,
    repo: repoFlag,
    label: labelFlag,
    branch: Flag.String("branch").pipe(Flag.withDefault("main")),
    generation: Flag.String("generation").pipe(Flag.withDefault("g0")),
    "exclude-from": optionalPath("exclude-from", "Exact untracked-path exclusions file"),
    dispositions: optionalPath("dispositions", "Kind-and-OID candidate decisions JSON"),
    "path-review": optionalPath("path-review", "Exact manifest-bound local custody review JSON"),
    apply: Flag.Boolean("apply").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Explicitly transfer and verify custody"),
    ),
    json: Flag.Boolean("json").pipe(
      Flag.withDefault(false),
      Flag.withDescription("One complete JSON result line"),
    ),
  },
  (flags) => {
    const input: AdoptInput = {
      legacy: flags.legacy,
      dest: flags.dest,
      repo: flags.repo,
      label: flags.label,
      branch: flags.branch,
      generation: flags.generation,
      excludeFrom: Option.getOrNull(flags["exclude-from"]),
      dispositions: Option.getOrNull(flags.dispositions),
      pathReview: Option.getOrNull(flags["path-review"]),
    };
    return Effect.gen(function* () {
      if (!flags.apply) {
        const plan = yield* planAdoption(input);
        yield* Console.log(flags.json ? JSON.stringify(plan) : renderPlan(plan));
        return;
      }
      const result = yield* applyAdoption(input);
      yield* Console.log(
        flags.json
          ? JSON.stringify(result)
          : [
              `Adoption ${result.changed ? "installed" : "unchanged"}: ${result.receiptRef}`,
              `Receipt commit: ${result.receiptCommitOid}`,
              `Custody verified: ${result.verification.custodyVerified}`,
              `Retirement unresolved: ${result.verification.retirementUnresolved.length} item(s); review with --json or verify-adoption.`,
              "No publication or retirement permission is implied.",
            ].join("\n"),
      );
    });
  },
).pipe(
  Command.withDescription(
    "Plan Git custody read-only; --apply explicitly installs immutable pins and verifies.",
  ),
);
