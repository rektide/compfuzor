import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import { git } from "../../src/repository/git.ts";
import { ancestor, jj, JjError, lines, refKey, refs, revision } from "../../src/repository/jj.ts";

// Every fixture is a disposable directory under .test-agent; production
// repositories are never touched. All tests exercise the real installed jj
// (0.45.1 at the time of writing) through the adapter under test, with the
// git adapter only arranging git-side fixture state.
const scratchRoot = resolve(import.meta.dirname, "../../..", ".test-agent", "jj-adapter");

const run = <A, E>(effect: Effect.Effect<A, E>): Promise<A> => Effect.runPromise(effect);

async function scratch(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
): Promise<string> {
  await mkdir(scratchRoot, { recursive: true });
  const dir = await mkdtemp(join(scratchRoot, `${name}-`));
  t.after(async () => {
    await rm(dir, { recursive: true, force: true });
  });
  return dir;
}

/** Hermetic colocated fixture: repo-level identity so commits never depend on operator config. */
async function colocated(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
): Promise<string> {
  const holder = await scratch(t, name);
  const repo = join(holder, "repo");
  await jj(["git", "init", "--colocate", repo], holder);
  await writeFile(
    join(repo, ".jj", "repo", "config.toml"),
    '[user]\n\tname = "probe"\n\temail = "probe@jj.invalid"\n',
  );
  return repo;
}

// Observers for "the operation log and store were untouched": both go
// through the adapter's own query mode, whose flags are what keep the
// measurement from snapshotting, importing, or reconciling by itself.
const opHead = (repo: string): Promise<string> =>
  jj(["op", "log", "--limit", "1", "--no-graph", "-T", "id.short()"], repo, {
    readOnly: true,
  });
const opCount = (repo: string): Promise<number> =>
  jj(["op", "log", "--no-graph", "-T", 'id ++ "\\n"'], repo, { readOnly: true }).then(
    (out) => lines(out).length,
  );

test("jj returns trimmed template text and JjError reports logical args", async (t) => {
  const repo = await colocated(t, "text");
  await jj(["describe", "-m", "trim probe"], repo);
  // The template emits a trailing newline; the adapter hands back trimmed text.
  assert.equal(
    await jj(["log", "-r", "@", "-T", 'description ++ "\\n"', "--no-graph"], repo, {
      readOnly: true,
    }),
    "trim probe",
  );
  const err = await jj(["log", "-r", "nosuchrevision!!"], repo).then(
    () => assert.fail("expected jj to fail"),
    (e: unknown) => e,
  );
  assert.ok(err instanceof JjError);
  assert.deepEqual(err.args, ["log", "-r", "nosuchrevision!!"]);
  assert.ok(err.message.startsWith("jj log -r nosuchrevision!!: "));
  // Transport flags stay out of the diagnostics; the detail is jj's stderr.
  assert.ok(!err.message.includes("--no-pager"));
  assert.ok(!err.message.includes("--at-op"));
  assert.ok(!err.message.includes("--ignore-working-copy"));
  assert.ok(err.detail.length > 0);
});

test("query mode never snapshots a dirty working copy", async (t) => {
  const repo = await colocated(t, "no-snapshot");
  await jj(["describe", "-m", "no snapshot probe"], repo);
  await writeFile(join(repo, "dirty.txt"), "dirty\n");
  const head = await opHead(repo);
  const count = await opCount(repo);
  // Two query shapes, both flags accepted (readOnly and its pinned alias).
  const files = lines(await jj(["file", "list", "-r", "@"], repo, { readOnly: true }));
  assert.ok(!files.includes("dirty.txt"), `dirty.txt must stay unsnapshotted, got ${files}`);
  await refs(repo, { pinned: true });
  assert.equal(await opHead(repo), head);
  assert.equal(await opCount(repo), count);
});

test("query mode never imports external git refs; plain queries still do", async (t) => {
  const repo = await colocated(t, "git-import");
  const identity = ["-c", "user.name=probe", "-c", "user.email=probe@jj.invalid"];
  assert.equal(
    (
      await run(
        git([...identity, "commit", "--allow-empty", "--quiet", "-m", "external base"], {
          cwd: repo,
        }),
      )
    ).exitCode,
    0,
  );
  await run(git(["update-ref", "refs/heads/external", "HEAD"], { cwd: repo }));
  const head = await opHead(repo);
  const count = await opCount(repo);
  const before = await refs(repo, { readOnly: true });
  assert.ok(
    ![...before.keys()].some((key) => key.startsWith("external\t")),
    "external git ref must stay unimported in query mode",
  );
  assert.equal(await opHead(repo), head);
  assert.equal(await opCount(repo), count);
  // Positive control: a plain (non-query) invocation imports git refs, so
  // routine refresh still observes the git side; only the query flags hold back.
  await refs(repo);
  const after = await refs(repo, { readOnly: true });
  assert.ok(
    [...after.keys()].some((key) => key.startsWith("external\t")),
    "plain bookmark list must import the external git ref",
  );
  assert.notEqual(await opHead(repo), head);
});

test("plain invocations still snapshot the working copy", async (t) => {
  const repo = await colocated(t, "snapshot");
  await jj(["describe", "-m", "snapshot probe"], repo);
  await writeFile(join(repo, "dirty.txt"), "dirty\n");
  const head = await opHead(repo);
  await jj(["status"], repo);
  assert.notEqual(await opHead(repo), head);
  const files = lines(await jj(["file", "list", "-r", "@"], repo, { readOnly: true }));
  assert.ok(files.includes("dirty.txt"), `snapshot must record dirty.txt, got ${files}`);
});

test("operator jj config is inherited, not sanitized", async (t) => {
  const repo = await colocated(t, "env-inherit");
  await jj(["describe", "-m", "env inherited"], repo);
  const config = join(repo, "..", "probe-config.toml");
  await writeFile(config, '[template-aliases]\njj_adapter_env_probe = "description"\n');
  const saved = process.env.JJ_CONFIG;
  process.env.JJ_CONFIG = config;
  t.after(() => {
    if (saved === undefined) delete process.env.JJ_CONFIG;
    else process.env.JJ_CONFIG = saved;
  });
  // The alias only exists through the inherited environment: if the adapter
  // stripped or replaced the child env, the template would fail to parse.
  assert.equal(
    await jj(["log", "-r", "@", "-T", "jj_adapter_env_probe", "--no-graph"], repo, {
      readOnly: true,
    }),
    "env inherited",
  );
});

test("polluted GIT_DIR cannot reroute jj; routing is the explicit cwd", async (t) => {
  const holder = await scratch(t, "gitdir");
  const repo = join(holder, "repo");
  await jj(["git", "init", "--colocate", repo], holder);
  await writeFile(
    join(repo, ".jj", "repo", "config.toml"),
    '[user]\n\tname = "probe"\n\temail = "probe@jj.invalid"\n',
  );
  await jj(["describe", "-m", "routed by cwd not GIT_DIR"], repo);
  const decoy = join(holder, "decoy.git");
  await run(git(["init", "--quiet", "--bare", decoy], { cwd: holder }));
  const saved = process.env.GIT_DIR;
  process.env.GIT_DIR = decoy;
  t.after(() => {
    if (saved === undefined) delete process.env.GIT_DIR;
    else process.env.GIT_DIR = saved;
  });
  assert.equal(
    await jj(["log", "-r", "@", "-T", "description", "--no-graph"], repo, { readOnly: true }),
    "routed by cwd not GIT_DIR",
  );
});

test("refs, revision, and ancestor parse through the migrated boundary", async (t) => {
  const repo = await colocated(t, "shapes");
  await jj(["describe", "-m", "shape probe"], repo);
  await jj(["bookmark", "create", "shapebase", "-r", "@"], repo);
  const marks = await refs(repo, { readOnly: true });
  const shape = marks.get(refKey("shapebase", "-"));
  assert.ok(shape, "local bookmark listed with remote '-'");
  assert.equal(shape.tracked, false);
  assert.match(shape.target, /^[0-9a-f]{40}$/);
  const rev = await revision(repo, "@");
  assert.match(rev.commit, /^[0-9a-f]{40}$/);
  assert.equal(rev.commit, shape.target);
  assert.equal(rev.empty, true);
  assert.equal(rev.parents.length, 1);
  assert.equal(rev.conflict, false);
  assert.equal(await ancestor(repo, "@", "@"), true);
  assert.equal(await ancestor(repo, "@", "@-"), false);
});
