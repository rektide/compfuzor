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

test("adapter strips Git env pollution; deliberate env still routes", async (t) => {
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
  // Pollution in the parent process is stripped for every entry point.
  const stripped = await run(git(["config", "--get", "custody.probe"], { cwd: dir }));
  assert.equal(stripped.exitCode, 1);
  // Positive control that the variable still routes when passed deliberately.
  const deliberate = await run(
    git(["config", "--get", "custody.probe"], { cwd: dir, env: { GIT_CONFIG_GLOBAL: fakeGlobal } }),
  );
  assert.equal(deliberate.exitCode, 0);
  assert.equal(utf8Fatal(deliberate.stdout).trim(), "inherited");
  // gitRead ignores both the polluted parent and a caller trying to loosen it.
  const isolated = await run(gitRead(["config", "--get", "custody.probe"], { cwd: dir }));
  assert.equal(isolated.exitCode, 1);
  const loosened = await run(
    gitRead(["config", "--get", "custody.probe"], {
      cwd: dir,
      env: { GIT_CONFIG_GLOBAL: fakeGlobal },
    }),
  );
  assert.equal(loosened.exitCode, 1);
});

test("polluted GIT_CONFIG_COUNT injection is stripped from every entry point", async (t) => {
  const dir = await scratch(t, "envconfig");
  assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
  const saved = {
    count: process.env.GIT_CONFIG_COUNT,
    key: process.env.GIT_CONFIG_KEY_0,
    value: process.env.GIT_CONFIG_VALUE_0,
  };
  process.env.GIT_CONFIG_COUNT = "1";
  process.env.GIT_CONFIG_KEY_0 = "custody.injected";
  process.env.GIT_CONFIG_VALUE_0 = "polluted";
  t.after(() => {
    for (const [key, was] of Object.entries(saved)) {
      if (was === undefined) delete process.env[key];
      else process.env[key] = was;
    }
  });
  for (const adapter of [git, gitRead]) {
    const result = await run(adapter(["config", "--get", "custody.injected"], { cwd: dir }));
    assert.equal(
      result.exitCode,
      1,
      `${adapter === git ? "git" : "gitRead"} must strip inherited injection`,
    );
  }
  // Positive control: the same variables passed deliberately do configure git.
  const deliberate = await run(
    git(["config", "--get", "custody.injected"], {
      cwd: dir,
      env: {
        GIT_CONFIG_COUNT: "1",
        GIT_CONFIG_KEY_0: "custody.injected",
        GIT_CONFIG_VALUE_0: "polluted",
      },
    }),
  );
  assert.equal(deliberate.exitCode, 0);
  assert.equal(utf8Fatal(deliberate.stdout).trim(), "polluted");
});

test("update-ref and hash-object land in the declared cwd despite polluted GIT_DIR", async (t) => {
  const holder = await scratch(t, "writerouting");
  const target = path.join(holder, "target");
  const decoy = path.join(holder, "decoy");
  for (const dir of [target, decoy]) {
    await mkdir(dir);
    assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
  }
  const identity = [
    "-c",
    "user.name=probe",
    "-c",
    "user.email=probe@example.invalid",
    "-c",
    "commit.gpgsign=false",
  ];
  await run(
    git([...identity, "commit", "--allow-empty", "--quiet", "-m", "base"], { cwd: target }),
  );
  const oid = utf8Fatal((await run(git(["rev-parse", "HEAD"], { cwd: target }))).stdout).trim();
  const saved = process.env.GIT_DIR;
  process.env.GIT_DIR = path.join(decoy, ".git");
  t.after(() => {
    if (saved === undefined) delete process.env.GIT_DIR;
    else process.env.GIT_DIR = saved;
  });
  // Writes must land in `target` even though the parent points at `decoy`.
  await run(gitChecked(["update-ref", "refs/heads/probe", oid], { cwd: target }));
  const blob = Buffer.from("routed write\n");
  const hashed = await run(git(["hash-object", "-w", "--stdin"], { cwd: target, input: blob }));
  const blobOid = utf8Fatal(hashed.stdout).trim();
  // Prove the decoy is reachable only through deliberate env — and empty.
  const inTarget = await run(git(["rev-parse", "refs/heads/probe"], { cwd: target }));
  assert.equal(utf8Fatal(inTarget.stdout).trim(), oid);
  assert.equal((await run(git(["cat-file", "-e", blobOid], { cwd: target }))).exitCode, 0);
  const decoyEnv = { GIT_DIR: path.join(decoy, ".git") };
  assert.notEqual(
    (await run(git(["rev-parse", "--verify", "refs/heads/probe"], { env: decoyEnv }))).exitCode,
    0,
  );
  assert.notEqual((await run(git(["cat-file", "-e", blobOid], { env: decoyEnv }))).exitCode, 0);
});

test("gitRead resolves the declared cwd repository, not a polluted GIT_DIR", async (t) => {
  const holder = await scratch(t, "readrouting");
  const declared = path.join(holder, "declared");
  const other = path.join(holder, "other");
  const identity = [
    "-c",
    "user.name=probe",
    "-c",
    "user.email=probe@example.invalid",
    "-c",
    "commit.gpgsign=false",
  ];
  for (const [dir, subject] of [
    [declared, "declared"],
    [other, "other"],
  ] as const) {
    await mkdir(dir);
    assert.equal((await run(git(["init", "--quiet"], { cwd: dir }))).exitCode, 0);
    await run(
      git([...identity, "commit", "--allow-empty", "--quiet", "-m", subject], { cwd: dir }),
    );
  }
  const saved = process.env.GIT_DIR;
  process.env.GIT_DIR = path.join(other, ".git");
  t.after(() => {
    if (saved === undefined) delete process.env.GIT_DIR;
    else process.env.GIT_DIR = saved;
  });
  // Positive control: deliberate env routing is the one way to reach `other`.
  const deliberate = utf8Fatal(
    (
      await run(
        git(["log", "-1", "--format=%s"], {
          cwd: declared,
          env: { GIT_DIR: path.join(other, ".git") },
        }),
      )
    ).stdout,
  ).trim();
  assert.equal(deliberate, "other");
  const read = utf8Fatal(
    (await run(gitRead(["log", "-1", "--format=%s"], { cwd: declared }))).stdout,
  ).trim();
  assert.equal(read, "declared");
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
  assert.ok(!err.message.includes("0".repeat(40)));
  assert.ok(err.message.includes("cat-file"));
});

test("utf8Fatal decodes valid text and throws on invalid bytes", () => {
  assert.equal(utf8Fatal(Buffer.from("pl\u00f6n")), "pl\u00f6n");
  assert.equal(utf8Fatal(new Uint8Array(0)), "");
  assert.throws(() => utf8Fatal(Uint8Array.from([0x68, 0xc3, 0x28])), TypeError);
});
