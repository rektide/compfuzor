#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** General jj toolkit, with a JSON-only refresh mode for Ansible. */
import { realpath } from "node:fs/promises";
import { cli, define } from "gunshi";
import completion from "@gunshi/plugin-completion";
import { harvest, recoveryCovered } from "./harvest.ts";
import { heal } from "./heal.ts";
import { preflight } from "./health.ts";
import { jj, refs, revision } from "./jj.ts";
import { refreshArchive } from "./refresh.ts";
import { declaredRemotes, mismatchError, reconcile, remoteDiff } from "./remotes.ts";
import { locateCompfuzor } from "./self.ts";

const destArg = {
  type: "string",
  required: true,
  description: "Path to jj-colocated archive checkout",
} as const;
const repoArg = { type: "string", required: true, description: "Declared origin URL" } as const;
const remotesArg = {
  type: "string",
  default: "{}",
  description: "JSON object of additional remote names and URLs",
} as const;

const refresh = define({
  name: "refresh",
  description:
    "Snapshot, preserve recovery tips, fetch, and reconcile the selected base and worktree.",
  args: {
    dest: destArg,
    repo: repoArg,
    remotes: remotesArg,
    label: {
      type: "string",
      required: true,
      description: "Deployment label for recovery bookmarks",
    },
    remote: { type: "string", default: "origin", description: "Selected declared remote" },
    branch: {
      type: "string",
      default: "HEAD",
      description: "Branch or branch@remote; HEAD chooses main then master",
    },
    update: { type: "string", default: "true", description: "Fetch/reconcile: true or false" },
    depth: { type: "string", description: "Clone depth (only for new archives)" },
    submodules: { type: "boolean", description: "Unsupported: fail rather than silently recurse" },
    json: { type: "boolean", description: "Exactly one JSON line on stdout for Ansible" },
    "reconcile-remotes": {
      type: "boolean",
      description: "Explicitly add/rewrite declared remotes before refresh",
    },
  },
  run: async (ctx) => {
    const { dest, repo, remotes, label, remote, branch, update, depth, submodules, json } =
      ctx.values;
    const result = await refreshArchive({
      dest,
      repo,
      remotes,
      label,
      remote,
      version: branch,
      update,
      depth,
      submodules,
      reconcileRemotes: ctx.values["reconcile-remotes"],
    });
    if (json) console.log(JSON.stringify(result));
    else {
      console.log(result.changed ? "Archive changed" : "Archive unchanged");
      for (const notice of result.notices)
        console.log(
          notice.kind === "bookmark-created"
            ? `BOOKMARK CREATED  ${notice.name} -> ${notice.target}`
            : `REPO NOTICE ${notice.message}`,
        );
    }
  },
});

const health = define({
  name: "health",
  description: "Materialize visible_heads() and list conflicted bookmarks; no mutations.",
  args: { dest: destArg },
  run: async (ctx) => {
    const conflicts = await preflight(ctx.values.dest);
    console.log(
      conflicts.length
        ? `Visible heads OK; conflicted bookmarks: ${conflicts.join(", ")}`
        : "Visible heads OK; no conflicted bookmarks",
    );
  },
});

const snapshot = define({
  name: "snapshot",
  description: "Snapshot current tracked/untracked work and import colocated Git refs.",
  args: { dest: destArg },
  run: async (ctx) => {
    await preflight(ctx.values.dest);
    await jj(["status"], ctx.values.dest);
    console.log(`Snapshotted ${ctx.values.dest}`);
  },
});

const save = define({
  name: "harvest",
  description: "Pin a revision under a unique harvest/<label>/ bookmark.",
  args: {
    dest: destArg,
    label: { type: "string", required: true, description: "Recovery bookmark namespace" },
    kind: { type: "string", default: "manual", description: "Recovery bookmark category" },
    target: { type: "string", default: "@", description: "Revision to pin" },
    copy: {
      type: "boolean",
      description: "Duplicate mutable @ to a fixed change ID before pinning",
    },
  },
  run: async (ctx) => {
    const { dest, label, kind, target, copy } = ctx.values;
    await preflight(dest);
    await jj(["status"], dest);
    const notice = await harvest(dest, label, kind, target, copy);
    console.log(`BOOKMARK CREATED  ${notice.name} -> ${notice.target}`);
  },
});

const remotes = define({
  name: "remotes",
  description: "Compare declared remote URLs; --reconcile deliberately applies differences.",
  args: {
    dest: destArg,
    repo: repoArg,
    remotes: remotesArg,
    reconcile: { type: "boolean", description: "Apply missing or mismatched remote URLs" },
  },
  run: async (ctx) => {
    const { dest, repo, remotes: additional, reconcile: apply } = ctx.values;
    const diff = await remoteDiff(dest, declaredRemotes(repo, additional));
    if (apply) {
      await reconcile(dest, diff);
      console.log(
        diff.length ? `Reconciled ${diff.map(({ name }) => name).join(", ")}` : "Remotes match",
      );
    } else if (diff.length) throw mismatchError(dest, diff, repo, additional);
    else console.log("Remotes match");
  },
});

const fetch = define({
  name: "fetch",
  description: "Snapshot, harvest dirty @, freeze tracked refs, then fetch one remote.",
  args: {
    dest: destArg,
    remote: { type: "string", default: "origin", description: "Existing remote to fetch" },
    label: { type: "string", required: true, description: "Recovery bookmark namespace" },
  },
  run: async (ctx) => {
    const { dest, remote, label } = ctx.values;
    await preflight(dest);
    await jj(["status"], dest);
    const before = await refs(dest);
    const working = await revision(dest, "@");
    if (!working.empty && !(await recoveryCovered(dest, label, before, working.parents)))
      await harvest(dest, label, "working-copy", working.commit, true);
    for (const ref of before.values()) {
      if (ref.remote !== "-" && ref.remote !== "git" && ref.tracked)
        await jj(["bookmark", "untrack", ref.name, "--remote", ref.remote], dest);
    }
    await jj(
      ["--config", "git.abandon-unreachable-commits=false", "git", "fetch", "--remote", remote],
      dest,
    );
    console.log(`Fetched ${remote}; local bookmarks remain frozen until refresh`);
  },
});

const healCommand = define({
  name: "heal",
  description: "Back up .jj and re-adopt from Git refs; loses jj-only operation history.",
  args: {
    dest: destArg,
    yes: {
      type: "boolean",
      description: "Required explicit permission to back up and replace .jj",
    },
  },
  run: async (ctx) =>
    console.log(
      `Re-adopted ${ctx.values.dest}; old jj state preserved at ${await heal(ctx.values.dest, ctx.values.yes ?? false)}`,
    ),
});

const self = define({
  name: "self",
  description: "Detect ~/archive/rektide/compfuzor; optionally fetch its origin.",
  args: {
    "archive-dir": {
      type: "string",
      description: "Override ~/archive for detection (useful for fixtures)",
    },
    freshen: { type: "boolean", description: "Opt in to fetching origin of detected checkout" },
  },
  run: async (ctx) => {
    const location = await locateCompfuzor(ctx.values.freshen ?? false, ctx.values["archive-dir"]);
    console.log(
      location === null
        ? "No compfuzor archive checkout detected"
        : `${location}${ctx.values.freshen ? " (origin fetched)" : ""}`,
    );
  },
});

export async function main(): Promise<void> {
  const args = process.argv.slice(2);
  // Legacy flag-only Ansible argv is the same refresh command with JSON output.
  // The explicit subcommand is preferred; only --help stays at root level.
  const legacy = args[0]?.startsWith("--") && args[0] !== "--help";
  const argv = legacy ? ["refresh", ...args, "--json"] : [...args];
  // Gunshi reserves --version globally. The legacy refresh surface used that
  // spelling for a branch; translate it before Gunshi parses either surface.
  if (argv[0] === "refresh")
    for (let i = 1; i < argv.length; i++) {
      if (argv[i] === "--version") argv[i] = "--branch";
    }
  await cli(
    argv,
    define({
      name: "archive",
      description: "Composable jj archive operations; use COMMAND --help for flags.",
      run: () => console.log("Run repo-jj-archive --help for commands."),
    }),
    {
      name: "repo-jj-archive",
      version: "0.1.0",
      // Gunshi prints the header even when a command succeeds; JSON mode
      // promises *one* stdout line and the header would break Ansible.
      renderHeader: null,
      subCommands: {
        refresh,
        health,
        snapshot,
        harvest: save,
        remotes,
        fetch,
        heal: healCommand,
        self,
      },
      plugins: [completion()],
    },
  );
}

const argvPath = process.argv[1];
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return;
      return main().catch((error: unknown) => {
        console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
      });
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
      process.exitCode = 1;
    },
  );
}
