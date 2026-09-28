import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import { git, gitChecked, GitError, gitRead, utf8Fatal } from "../../src/repository/git.ts";

// Every fixture is a disposable directory under .test-agent; production
// repositories are never touched. All tests exercise the real installed git.
const scratchRoot = path.resolve(import.meta.dirname, "../../..", ".test-agent", "git-adapter");

const run = <A, E>(effect: Effect.Effect<A, E>): Promise<A> => Effect.runPromise(effect);

async function scratch(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
): Promise<string> {
  await mkdir(scratchRoot, { recursive: true });
  const dir = await mkdtemp(path.join(scratchRoot, `${name}-`));
  t.after(async () => {
    await rm(dir, { recursive: true, force: true });
  });
  return dir;
}

test("git collects raw stdout bytes and a zero exit code", async () => {
  const result = await run(git(["version"]));
  assert.equal(result.exitCode, 0);
  assert.match(utf8Fatal(result.stdout), /^git version \d/);
  assert.equal(result.stderr.byteLength, 0);
});

test("stdin bytes round-trip through hash-object and cat-file unchanged", async (t) => {
  const dir = await scratch(t, "roundtrip");
  assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
  // NUL bytes and invalid-UTF-8 sequences: output must stay bytes, not text.
  const blob = Uint8Array.from([0x00, 0xff, 0x00, 0x62, 0x00, 0x80, 0x00]);
  const hashed = await run(git(["hash-object", "-w", "--stdin"], { cwd: dir, input: blob }));
  assert.equal(hashed.exitCode, 0);
  const oid = utf8Fatal(hashed.stdout).trim();
  assert.match(oid, /^[0-9a-f]{40}$/);
  const back = await run(git(["cat-file", "blob", oid], { cwd: dir }));
  assert.deepEqual(back.stdout, blob);
});

test("explicit GIT_DIR addresses a private object store outside any repo", async (t) => {
  const holder = await scratch(t, "private");
  const gitDir = path.join(holder, "objects.git");
  const outside = path.join(holder, "outside");
  await mkdir(outside);
  await run(git(["init", "--quiet", "--bare", gitDir]));
  const payload = Buffer.from("private scratch\n");
  const hashed = await run(
    git(["hash-object", "-w", "--stdin"], {
      cwd: outside,
      env: { GIT_DIR: gitDir },
      input: payload,
    }),
  );
  const oid = utf8Fatal(hashed.stdout).trim();
  // Success proves the explicit GIT_DIR was honored: `outside` is no repo of
  // its own and no ancestor holds this object.
  const back = await run(
    git(["cat-file", "blob", oid], { cwd: outside, env: { GIT_DIR: gitDir } }),
  );
  // The adapter returns plain Uint8Array; compare byte contents, not prototypes.
  assert.deepEqual(back.stdout, Uint8Array.from(payload));
});

test("gitRead does not inherit global config that the base adapter passes through", async (t) => {
  const dir = await scratch(t, "isolation");
  assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
  const fakeGlobal = path.join(dir, "fake-global-config");
  await writeFile(fakeGlobal, "[custody]\n\tprobe = inherited\n");
  const saved = process.env.GIT_CONFIG_GLOBAL;
  process.env.GIT_CONFIG_GLOBAL = fakeGlobal;
  t.after(() => {
    if (saved === undefined) delete process.env.GIT_CONFIG_GLOBAL;
    else process.env.GIT_CONFIG_GLOBAL = saved;
  });
  // Positive control: the base adapter inherits the process environment.
  const inherited = await run(git(["config", "--get", "custody.probe"], { cwd: dir }));
  assert.equal(inherited.exitCode, 0);
  assert.equal(utf8Fatal(inherited.stdout).trim(), "inherited");
  // The read helper forces GIT_CONFIG_GLOBAL to /dev/null: value invisible.
  const isolated = await run(gitRead(["config", "--get", "custody.probe"], { cwd: dir }));
  assert.equal(isolated.exitCode, 1);
});

test("gitRead sees real history where the base adapter follows refs/replace", async (t) => {
  const dir = await scratch(t, "replace");
  assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
  const identity = [
    "-c",
    "user.name=probe",
    "-c",
    "user.email=probe@example.invalid",
    "-c",
    "commit.gpgsign=false",
  ];
  await run(git([...identity, "commit", "--allow-empty", "--quiet", "-m", "one"], { cwd: dir }));
  await run(git([...identity, "commit", "--allow-empty", "--quiet", "-m", "two"], { cwd: dir }));
  const head = utf8Fatal((await run(git(["rev-parse", "HEAD"], { cwd: dir }))).stdout).trim();
  const parent = utf8Fatal((await run(git(["rev-parse", "HEAD~"], { cwd: dir }))).stdout).trim();
  await run(gitChecked(["replace", parent, head], { cwd: dir }));
  const replaced = utf8Fatal(
    (await run(git(["log", "-1", "--format=%s", "HEAD~"], { cwd: dir }))).stdout,
  ).trim();
  const real = utf8Fatal(
    (await run(gitRead(["log", "-1", "--format=%s", "HEAD~"], { cwd: dir }))).stdout,
  ).trim();
  assert.equal(replaced, "two");
  assert.equal(real, "one");
});

test("gitChecked returns stdout on success and retains stderr on GitError", async (t) => {
  assert.match(utf8Fatal(await run(gitChecked(["version"]))), /^git version \d/);
  const dir = await scratch(t, "checked");
  assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
  const err = await run(gitChecked(["cat-file", "blob", "0".repeat(40)], { cwd: dir })).then(
    () => assert.fail("expected gitChecked to fail"),
    (e: unknown) => e,
  );
  assert.ok(err instanceof GitError);
  assert.notEqual(err.exitCode, 0);
  assert.ok(err.stderr.byteLength > 0);
  assert.match(utf8Fatal(err.stderr), /fatal:/);
  // The diagnostic stays a separate field: nothing of it lands in the message.
  assert.ok(!err.message.includes("fatal:"));
  assert.ok(err.message.includes("cat-file"));
});

test("utf8Fatal decodes valid text and throws on invalid bytes", () => {
  assert.equal(utf8Fatal(Buffer.from("pl\u00f6n")), "pl\u00f6n");
  assert.equal(utf8Fatal(new Uint8Array(0)), "");
  assert.throws(() => utf8Fatal(Uint8Array.from([0x68, 0xc3, 0x28])), TypeError);
});
