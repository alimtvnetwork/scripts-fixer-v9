#!/usr/bin/env node
// Auto-regenerate spec/script-registry-summary.md from
//   - scripts/registry.json     (id -> folder mapping)
//   - scripts/<folder>/config.json (per-script metadata: name, desc, modes)
//   - scripts/shared/install-keywords.json (keyword -> [ids], modes -> per-script default)
//
// Output: spec/script-registry-summary.md (overwrites in place)

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SCRIPTS_DIR = path.join(ROOT, 'scripts');
const REGISTRY_PATH = path.join(SCRIPTS_DIR, 'registry.json');
const KEYWORDS_PATH = path.join(SCRIPTS_DIR, 'shared', 'install-keywords.json');
const OUT_PATH = path.join(ROOT, 'spec', 'script-registry-summary.md');

function readJson(p) {
  const raw = fs.readFileSync(p, 'utf8');
  return JSON.parse(raw);
}

const registry = readJson(REGISTRY_PATH).scripts; // { "01": "01-install-vscode", ... }
const kwData = readJson(KEYWORDS_PATH);
const keywords = kwData.keywords || {};
const modes = kwData.modes || {};

// -- Per-script keyword + mode aggregation -------------------------------
//    Walk the keyword map once. For each numeric ID a keyword resolves to,
//    attach the keyword to that script's keyword list. Subcommand-style
//    targets like "os:clean" or "profile:base" are skipped (they're not
//    script IDs in the registry).
const idToKeywords = {};       // { "07": ["git", "git-lfs", ...] }
const idToModeMap = {};        // { "33": { "notepad++": "install+settings", ... } }
const subcommandKeywords = {}; // { "os:clean": ["os-clean", "osclean"], ... }

for (const [kw, targets] of Object.entries(keywords)) {
  for (const t of targets) {
    if (typeof t === 'number') {
      const id = String(t).padStart(2, '0');
      if (!idToKeywords[id]) idToKeywords[id] = [];
      idToKeywords[id].push(kw);
    } else if (typeof t === 'string') {
      // subcommand target (e.g. "os:clean")
      if (!subcommandKeywords[t]) subcommandKeywords[t] = [];
      subcommandKeywords[t].push(kw);
    }
  }
}

for (const [kw, mapping] of Object.entries(modes)) {
  for (const [scriptIdRaw, modeValue] of Object.entries(mapping)) {
    const id = String(scriptIdRaw).padStart(2, '0');
    if (!idToModeMap[id]) idToModeMap[id] = {};
    idToModeMap[id][kw] = modeValue;
  }
}

// -- Per-script config.json scrape (name + desc + valid modes) -----------
function scrapeScriptMeta(folder) {
  const cfgPath = path.join(SCRIPTS_DIR, folder, 'config.json');
  if (!fs.existsSync(cfgPath)) {
    return { name: null, desc: null, validModes: null, chocoPackage: null };
  }
  let cfg;
  try { cfg = readJson(cfgPath); } catch { return { name: null, desc: null, validModes: null, chocoPackage: null }; }

  // The "name" / "desc" / "validModes" / "defaultMode" fields can live at
  // the top level OR nested under a single descriptive sub-key (e.g. cfg.notepadpp.name).
  // Walk one level deep, take the first non-meta object that has any of those.
  const candidates = [cfg];
  for (const [k, v] of Object.entries(cfg)) {
    if (k.startsWith('_')) continue;
    if (v && typeof v === 'object' && !Array.isArray(v)) candidates.push(v);
  }

  let name = null, desc = null, validModes = null, chocoPackage = null, defaultMode = null;
  for (const c of candidates) {
    if (!name && typeof c.name === 'string') name = c.name;
    if (!desc && typeof c.desc === 'string') desc = c.desc;
    if (!desc && typeof c.description === 'string') desc = c.description;
    if (!validModes && Array.isArray(c.validModes)) validModes = c.validModes;
    if (!chocoPackage && typeof c.chocoPackage === 'string') chocoPackage = c.chocoPackage;
    if (!chocoPackage && typeof c.chocoPackageName === 'string') chocoPackage = c.chocoPackageName;
    if (!defaultMode && typeof c.defaultMode === 'string') defaultMode = c.defaultMode;
  }

  return { name, desc, validModes, chocoPackage, defaultMode };
}

// -- Combo keyword detection (>1 numeric ID) ------------------------------
const comboKeywords = {}; // { kw: [ids...] }
for (const [kw, targets] of Object.entries(keywords)) {
  const numericIds = targets.filter(t => typeof t === 'number');
  if (numericIds.length > 1) comboKeywords[kw] = numericIds;
}

// -- Build the markdown ---------------------------------------------------
const ids = Object.keys(registry).sort();
const totalScripts = ids.length;

let totalKeywords = 0;
for (const id of ids) totalKeywords += (idToKeywords[id] || []).length;

let totalModeEntries = 0;
let scriptsWithModes = 0;
for (const id of ids) {
  const m = idToModeMap[id];
  if (m && Object.keys(m).length > 0) {
    scriptsWithModes++;
    totalModeEntries += Object.keys(m).length;
  }
}

const lines = [];
lines.push('# Script Registry Summary');
lines.push('');
lines.push(`> Auto-generated report of all ${totalScripts} registered scripts, ${totalKeywords} keywords, and ${totalModeEntries} mode entries.`);
lines.push('> Regenerate with: `node scripts/_internal/generate-registry-summary.cjs`');
lines.push('');
lines.push('## Overview');
lines.push('');
lines.push('| ID | Folder | Keywords | Modes |');
lines.push('|----|--------|----------|-------|');
for (const id of ids) {
  const folder = registry[id];
  const kwCount = (idToKeywords[id] || []).length;
  const modeCount = idToModeMap[id] ? Object.keys(idToModeMap[id]).length : 0;
  const modeCell = modeCount > 0 ? String(modeCount) : '--';
  lines.push(`| ${id} | ${folder} | ${kwCount} | ${modeCell} |`);
}
lines.push('');
lines.push('## Detailed Script Reference');
lines.push('');

for (const id of ids) {
  const folder = registry[id];
  const meta = scrapeScriptMeta(folder);
  const heading = meta.name ? meta.name : folder;
  lines.push(`### Script ${id}: ${heading}`);
  lines.push('');
  lines.push(`- **Folder**: \`${folder}\``);
  if (meta.desc) lines.push(`- **Description**: ${meta.desc}`);
  if (meta.chocoPackage) lines.push(`- **Choco package**: \`${meta.chocoPackage}\``);
  lines.push('');

  const kws = idToKeywords[id] || [];
  lines.push(`**Keywords** (${kws.length}):`);
  if (kws.length === 0) {
    lines.push('```');
    lines.push('(none)');
    lines.push('```');
  } else {
    lines.push('```');
    lines.push(kws.join(', '));
    lines.push('```');
  }
  lines.push('');

  const mm = idToModeMap[id];
  if (mm && Object.keys(mm).length > 0) {
    lines.push('**Mode Mappings**:');
    lines.push('');
    lines.push('| Keyword | Mode |');
    lines.push('|---------|------|');
    for (const [kw, mode] of Object.entries(mm)) {
      lines.push(`| \`${kw}\` | \`${mode}\` |`);
    }
    lines.push('');
    if (meta.validModes) {
      lines.push(`**Valid Modes**: ${meta.validModes.map(m => `\`${m}\``).join(', ')}`);
      lines.push('');
    }
    if (meta.defaultMode) {
      lines.push(`**Default Mode**: \`${meta.defaultMode}\``);
      lines.push('');
    }
  }

  lines.push('---');
  lines.push('');
}

// -- Combo keywords table -------------------------------------------------
lines.push('## Combo Keywords');
lines.push('');
lines.push('Keywords that trigger multiple scripts in sequence.');
lines.push('');
lines.push('| Keyword | Scripts | IDs |');
lines.push('|---------|---------|-----|');

// Sort: most scripts first, then alphabetic
const comboEntries = Object.entries(comboKeywords).sort((a, b) => {
  const sizeDiff = b[1].length - a[1].length;
  if (sizeDiff !== 0) return sizeDiff;
  return a[0].localeCompare(b[0]);
});
for (const [kw, idList] of comboEntries) {
  const folders = idList
    .map(n => String(n).padStart(2, '0'))
    .map(id => registry[id] || `(missing-${id})`);
  const idsStr = idList.join(', ');
  lines.push(`| \`${kw}\` | ${folders.join(', ')} | ${idsStr} |`);
}
lines.push('');
lines.push(`**Total combo keywords**: ${comboEntries.length}`);
lines.push('');

// -- Subcommand keywords (os:* / profile:*) -------------------------------
const subcommandEntries = Object.entries(subcommandKeywords).sort((a, b) => a[0].localeCompare(b[0]));
if (subcommandEntries.length > 0) {
  lines.push('## Subcommand Keywords');
  lines.push('');
  lines.push('Keywords routed to top-level dispatchers (not script IDs).');
  lines.push('');
  lines.push('| Target | Keywords |');
  lines.push('|--------|----------|');
  for (const [target, kws] of subcommandEntries) {
    lines.push(`| \`${target}\` | ${kws.map(k => `\`${k}\``).join(', ')} |`);
  }
  lines.push('');
  lines.push(`**Total subcommand keyword groups**: ${subcommandEntries.length}`);
  lines.push('');
}

// -- Statistics -----------------------------------------------------------
lines.push('## Statistics');
lines.push('');
lines.push('| Metric | Count |');
lines.push('|--------|-------|');
lines.push(`| Registered scripts | ${totalScripts} |`);
lines.push(`| Total keywords (numeric-target) | ${totalKeywords} |`);
let subKwCount = 0;
for (const list of Object.values(subcommandKeywords)) subKwCount += list.length;
lines.push(`| Subcommand keywords | ${subKwCount} |`);
lines.push(`| Mode entries | ${totalModeEntries} |`);
lines.push(`| Scripts with modes | ${scriptsWithModes} |`);
lines.push(`| Combo keywords | ${comboEntries.length} |`);
lines.push('');

fs.writeFileSync(OUT_PATH, lines.join('\n'));
console.log(`Wrote ${OUT_PATH}`);
console.log(`  ${totalScripts} scripts, ${totalKeywords} keywords, ${totalModeEntries} mode entries, ${comboEntries.length} combos, ${subKwCount} subcommand keywords`);
