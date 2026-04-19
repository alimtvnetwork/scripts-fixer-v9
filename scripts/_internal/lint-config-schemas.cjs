#!/usr/bin/env node
/**
 * Lints every scripts/<folder>/config.json against the project schema.
 *
 * Two schemas:
 *   - "installer" (numbered scripts in registry.json that LOOK like installers --
 *      they have validModes / defaultMode / chocoPackage etc. or are SUPPOSED to)
 *   - "dispatcher" (audit/databases/models/profile/os/12-install-all-dev-tools/etc.)
 *      Schema is per-folder; we check structural sanity only.
 *
 * Rules (per the v0.40.5 sign-off):
 *   R1 (FAIL) Required: name + (desc | description) + validModes + defaultMode
 *             on installer scripts. defaultMode MUST appear in validModes.
 *   R2 (FAIL) Conditional: if validModes contains "choco", chocoPackage
 *             (or chocoPackageName) must be set on the script.
 *   R3 (WARN) Quality: name >= 3 chars, no placeholder values
 *             ("", "TODO", "...", "FIXME", "tbd") in name/desc.
 *   R4 (WARN) Strict: WARN on unknown TOP-LEVEL keys (anything not in the
 *             allowed schema for the script's category).
 *
 * Exit codes:
 *   0  -- no FAIL rows (WARN allowed)
 *   1  -- one or more FAIL rows (CI release workflow blocks here)
 *   2  -- linter itself crashed (bad JSON, missing files, etc.)
 *
 * Run: node scripts/_internal/lint-config-schemas.cjs
 */
"use strict";

const fs   = require("fs");
const path = require("path");

const REPO_ROOT     = path.resolve(__dirname, "..", "..");
const SCRIPTS_DIR   = path.join(REPO_ROOT, "scripts");
const REGISTRY_PATH = path.join(SCRIPTS_DIR, "registry.json");

// ANSI colors (CI strips, terminal renders)
const C = {
  reset:   "\x1b[0m",
  bold:    "\x1b[1m",
  dim:     "\x1b[2m",
  red:     "\x1b[31m",
  green:   "\x1b[32m",
  yellow:  "\x1b[33m",
  cyan:    "\x1b[36m",
  gray:    "\x1b[90m",
};

function color(s, c) { return process.env.NO_COLOR ? s : `${c}${s}${C.reset}`; }
function tagOK()   { return color("[  OK  ]", C.green); }
function tagWARN() { return color("[ WARN ]", C.yellow); }
function tagFAIL() { return color("[ FAIL ]", C.red); }

// GitHub Actions annotations (only emitted when running under GHA)
const isGitHubActions = !!process.env.GITHUB_ACTIONS;
function ghaWarn(file, msg) {
  if (isGitHubActions) console.log(`::warning file=${file}::${msg}`);
}
function ghaError(file, msg) {
  if (isGitHubActions) console.log(`::error file=${file}::${msg}`);
}

// ----------------------------- Schema definitions -----------------------------

// Folders that are dispatchers / orchestrators -- they don't need the full
// installer schema (no validModes, no chocoPackage, no defaultMode).
// Each lists the keys we EXPECT at top level; anything else triggers WARN R4.
const DISPATCHER_SCHEMAS = {
  "12-install-all-dev-tools": {
    label: "All-dev-tools dispatcher",
    allowedKeys: ["_comment", "devDir", "groups", "promptOnEmpty", "questionnaire", "scripts", "sequence"],
  },
  "audit": {
    label: "Audit dispatcher",
    allowedKeys: ["_comment", "enabled", "checks", "exportCapableScripts"],
  },
  "databases": {
    label: "Databases dispatcher",
    allowedKeys: ["_comment", "devDir", "installMode", "databases", "groups", "sequence"],
  },
  "models": {
    label: "Models dispatcher",
    allowedKeys: ["_comment", "enabled", "backends", "defaultBackend"],
  },
  "os": {
    label: "OS dispatcher",
    allowedKeys: ["_comment", "clean", "tempClean", "choco", "hibernate", "longPath", "addUser"],
  },
  "profile": {
    label: "Profile dispatcher",
    allowedKeys: ["_comment", "profiles", "defaultProfile", "modeEnvVars", "execution"],
  },
};

// Installer-script allowed top-level keys (everything else -> WARN R4).
// Per-script extras (e.g. "editions" for vscode, "phpmyadmin" for php,
// "tweaks" for windows-tweaks) are tolerated as 1-deep groupings.
const INSTALLER_ALLOWED_KEYS = new Set([
  "_comment", "enabled",
  "name", "desc", "description", "label",
  "chocoPackage", "chocoPackageName", "verifyCommand", "versionFlag",
  "validModes", "defaultMode",
  "promptEdition", "editions",
  "devDir",
]);

const PLACEHOLDER_VALUES = new Set(["", "todo", "fixme", "tbd", "...", "n/a", "na"]);

// ----------------------------- Helpers ---------------------------------------

function readJson(p) {
  const raw = fs.readFileSync(p, "utf8");
  try { return JSON.parse(raw); }
  catch (e) { throw new Error(`Invalid JSON in ${p}: ${e.message}`); }
}

/**
 * An installer config sometimes nests name/desc/chocoPackage one level deep
 * inside a feature group (e.g. scripts/16-install-php/config.json's "phpmyadmin"
 * block). We collect any chocoPackage/name/desc found at depth 0 OR 1.
 */
function collectInstallerFields(cfg) {
  const out = {
    name:         cfg.name || cfg.label || "",
    desc:         cfg.desc || cfg.description || "",
    chocoPackage: cfg.chocoPackage || cfg.chocoPackageName || "",
    validModes:   Array.isArray(cfg.validModes) ? cfg.validModes : null,
    defaultMode:  cfg.defaultMode || "",
  };

  // 1-deep scan: feature blocks that hold their own name/desc/chocoPackage
  for (const [k, v] of Object.entries(cfg)) {
    if (k.startsWith("_")) continue;
    if (typeof v !== "object" || v === null || Array.isArray(v)) continue;

    if (!out.name && typeof v.name === "string") out.name = v.name;
    if (!out.name && typeof v.label === "string") out.name = v.label;
    if (!out.desc && typeof v.desc === "string") out.desc = v.desc;
    if (!out.desc && typeof v.description === "string") out.desc = v.description;
    if (!out.chocoPackage) {
      if (typeof v.chocoPackage === "string") out.chocoPackage = v.chocoPackage;
      else if (typeof v.chocoPackageName === "string") out.chocoPackage = v.chocoPackageName;
    }
  }
  return out;
}

function isPlaceholder(s) {
  if (typeof s !== "string") return true;
  return PLACEHOLDER_VALUES.has(s.trim().toLowerCase());
}

// ----------------------------- Linter core -----------------------------------

const findings = []; // { folder, file, severity: "OK"|"WARN"|"FAIL", code, msg }

function emit(folder, file, severity, code, msg) {
  findings.push({ folder, file, severity, code, msg });
}

function lintInstaller(folder, file, cfg) {
  const f = collectInstallerFields(cfg);
  let hasFail = false;
  let hasWarn = false;

  // R1a (FAIL) -- defaultMode-in-validModes consistency (real bug if violated)
  if (f.validModes && f.defaultMode && !f.validModes.includes(f.defaultMode)) {
    emit(folder, file, "FAIL", "R1a",
      `defaultMode "${f.defaultMode}" is not in validModes [${f.validModes.join(", ")}]`);
    hasFail = true;
  }

  // R1b (FAIL) -- validModes shape sanity
  if (cfg.validModes !== undefined) {
    const isArray = Array.isArray(cfg.validModes);
    if (!isArray) {
      emit(folder, file, "FAIL", "R1b", `validModes must be an array, got ${typeof cfg.validModes}`);
      hasFail = true;
    } else if (cfg.validModes.length === 0) {
      emit(folder, file, "FAIL", "R1b", `validModes is an empty array`);
      hasFail = true;
    } else if (!cfg.validModes.every((m) => typeof m === "string" && m.trim().length > 0)) {
      emit(folder, file, "FAIL", "R1b", `validModes contains non-string or empty entries`);
      hasFail = true;
    }
  }

  // R1c (WARN) -- name + desc are RECOMMENDED but not required (advisory)
  if (!f.name) {
    emit(folder, file, "WARN", "R1c", "no name / label found at top-level or in any 1-deep feature block");
    hasWarn = true;
  }
  if (!f.desc) {
    emit(folder, file, "WARN", "R1c", "no desc / description found at top-level or in any 1-deep feature block");
    hasWarn = true;
  }

  // R2 (FAIL) -- chocoPackage required when validModes contains "choco"
  if (f.validModes && f.validModes.includes("choco") && !f.chocoPackage) {
    emit(folder, file, "FAIL", "R2",
      `validModes contains "choco" but no chocoPackage / chocoPackageName found at top-level or 1-deep`);
    hasFail = true;
  }

  // R3 (WARN) -- quality
  if (f.name && f.name.trim().length > 0 && f.name.trim().length < 3) {
    emit(folder, file, "WARN", "R3", `name "${f.name}" is shorter than 3 characters`);
    hasWarn = true;
  }
  if (f.name && isPlaceholder(f.name)) {
    emit(folder, file, "WARN", "R3", `name is a placeholder value: "${f.name}"`);
    hasWarn = true;
  }
  if (f.desc && isPlaceholder(f.desc)) {
    emit(folder, file, "WARN", "R3", `desc is a placeholder value: "${f.desc}"`);
    hasWarn = true;
  }

  // R4 (WARN) -- unknown TOP-LEVEL SCALAR keys only.
  // Object groups are tolerated (project convention -- e.g. "phpmyadmin",
  // "tweaks", "editions"). Scalar keys like "alwaysUpgradeToLatest" or
  // "installMethod" are flagged because they often indicate dead config.
  for (const key of Object.keys(cfg)) {
    if (key.startsWith("_")) continue;
    if (INSTALLER_ALLOWED_KEYS.has(key)) continue;

    const v = cfg[key];
    const isObjectGroup = typeof v === "object" && v !== null && !Array.isArray(v);
    if (isObjectGroup) continue; // feature blocks are fine

    emit(folder, file, "WARN", "R4", `unknown top-level scalar key: "${key}"`);
    hasWarn = true;
  }

  if (!hasFail && !hasWarn) emit(folder, file, "OK", "-", "all checks passed");
  return hasFail ? "FAIL" : (hasWarn ? "WARN" : "OK");
}

function lintDispatcher(folder, file, cfg, schema) {
  let hasWarn = false;
  let hasFail = false;
  const allowed = new Set(schema.allowedKeys);

  for (const key of Object.keys(cfg)) {
    if (allowed.has(key)) continue;
    emit(folder, file, "WARN", "R4",
      `${schema.label}: unknown top-level key "${key}" (allowed: ${schema.allowedKeys.join(", ")})`);
    hasWarn = true;
  }

  // Dispatchers don't have a name/desc requirement, but if they DO have one,
  // make sure it isn't a placeholder.
  if (typeof cfg.name === "string" && isPlaceholder(cfg.name)) {
    emit(folder, file, "WARN", "R3", `name is a placeholder value: "${cfg.name}"`);
    hasWarn = true;
  }

  if (!hasFail && !hasWarn) emit(folder, file, "OK", "-", `${schema.label} -- structurally clean`);
  return hasFail ? "FAIL" : (hasWarn ? "WARN" : "OK");
}

// ----------------------------- Main -----------------------------------------

function main() {
  // Discover every scripts/<folder>/config.json
  const folderEntries = fs.readdirSync(SCRIPTS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith("_") && d.name !== "shared");

  const registry = readJson(REGISTRY_PATH);
  const numberedFolders = new Set(Object.values(registry.scripts));

  const summary = { total: 0, ok: 0, warn: 0, fail: 0, missing: 0 };
  const folderResults = []; // { folder, status, hasConfig }

  for (const entry of folderEntries) {
    const folder    = entry.name;
    const cfgPath   = path.join(SCRIPTS_DIR, folder, "config.json");
    const relCfg    = path.relative(REPO_ROOT, cfgPath).replace(/\\/g, "/");
    const hasConfig = fs.existsSync(cfgPath);

    summary.total++;

    if (!hasConfig) {
      // Some folders legitimately have no config.json (e.g. git-tools).
      // We INFO-log them but don't count as failure.
      folderResults.push({ folder, status: "NONE", hasConfig: false });
      continue;
    }

    let cfg;
    try { cfg = readJson(cfgPath); }
    catch (e) {
      emit(folder, relCfg, "FAIL", "JSON", e.message);
      ghaError(relCfg, e.message);
      folderResults.push({ folder, status: "FAIL", hasConfig: true });
      summary.fail++;
      continue;
    }

    let status;
    if (DISPATCHER_SCHEMAS[folder]) {
      status = lintDispatcher(folder, relCfg, cfg, DISPATCHER_SCHEMAS[folder]);
    } else if (numberedFolders.has(folder)) {
      // Numbered installer-style script (or folders aliased to numeric IDs
      // like "audit" -> id 13, but those have a dispatcher schema above).
      status = lintInstaller(folder, relCfg, cfg);
    } else {
      // Unknown / orphan folder -- not in registry, not a dispatcher.
      // Treat as installer with R4 leniency since we don't know its shape.
      status = lintInstaller(folder, relCfg, cfg);
    }

    folderResults.push({ folder, status, hasConfig: true });
    if (status === "FAIL") summary.fail++;
    else if (status === "WARN") summary.warn++;
    else summary.ok++;
  }

  // ------------ Print report ------------
  console.log("");
  console.log(color("  config.json schema lint", C.cyan + C.bold));
  console.log(color("  =======================", C.gray));
  console.log("");

  // Group findings by folder so each script gets a contiguous block.
  const byFolder = new Map();
  for (const f of findings) {
    if (!byFolder.has(f.folder)) byFolder.set(f.folder, []);
    byFolder.get(f.folder).push(f);
  }

  const folders = [...byFolder.keys()].sort();
  for (const folder of folders) {
    const rows = byFolder.get(folder);
    // Folder heading -- color by worst severity in the block
    const worst = rows.reduce((acc, r) =>
      r.severity === "FAIL" ? "FAIL" :
      (acc === "FAIL" ? acc : (r.severity === "WARN" ? "WARN" : acc)), "OK");
    const folderTag =
      worst === "FAIL" ? tagFAIL() :
      worst === "WARN" ? tagWARN() : tagOK();
    console.log(`  ${folderTag} ${color(folder, C.bold)}`);
    for (const r of rows) {
      const tag =
        r.severity === "FAIL" ? color("FAIL", C.red) :
        r.severity === "WARN" ? color("WARN", C.yellow) :
        color("OK  ", C.green);
      console.log(`         ${color("[" + tag + "]", C.dim)} ${color("[" + r.code + "]", C.dim)} ${r.msg}`);

      // GitHub Actions annotations
      if (r.severity === "FAIL") ghaError(r.file, `[${r.code}] ${r.msg}`);
      else if (r.severity === "WARN") ghaWarn(r.file, `[${r.code}] ${r.msg}`);
    }
  }

  // Folders with no config.json
  const noCfg = folderResults.filter((r) => !r.hasConfig);
  if (noCfg.length > 0) {
    console.log("");
    console.log(color("  Folders WITHOUT config.json (informational, not a failure):", C.gray));
    for (const r of noCfg) {
      console.log(`    ${color("[ -- ]", C.gray)} ${r.folder}`);
    }
  }

  // Summary
  console.log("");
  console.log(color("  Summary", C.cyan + C.bold));
  console.log(color("  -------", C.gray));
  console.log(`    Folders scanned    : ${summary.total}`);
  console.log(`    With config.json   : ${summary.total - noCfg.length}`);
  console.log(`    ${color("OK", C.green)}                 : ${summary.ok}`);
  console.log(`    ${color("WARN", C.yellow)}               : ${summary.warn}`);
  console.log(`    ${color("FAIL", C.red)}               : ${summary.fail}`);
  console.log("");

  if (summary.fail > 0) {
    console.log(color(`  Result: ${summary.fail} folder(s) FAIL -- exiting 1 (CI will block release).`, C.red + C.bold));
    console.log("");
    process.exit(1);
  }

  if (summary.warn > 0) {
    console.log(color(`  Result: ${summary.warn} folder(s) have WARN -- exiting 0 (release proceeds, fix at leisure).`, C.yellow));
  } else {
    console.log(color(`  Result: all clean -- exiting 0.`, C.green + C.bold));
  }
  console.log("");
  process.exit(0);
}

try { main(); }
catch (e) {
  console.error(color(`\n  [ FAIL ] linter crashed: ${e.message}\n`, C.red));
  console.error(e.stack);
  process.exit(2);
}
