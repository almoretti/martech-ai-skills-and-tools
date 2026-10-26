#!/usr/bin/env node
// Regenerate BOTH Claude Code manifests from the skills present + the version in package.json:
//   .claude-plugin/plugin.json      — the bundled plugin (name, version, keywords, skills[])
//   .claude-plugin/marketplace.json — the single-plugin marketplace that ships it
// A skill = any directory containing a SKILL.md, under skills/ or CLI/*/skills/.
// Run after adding/removing/renaming a skill OR bumping the version in package.json:
//   node scripts/build-marketplace.mjs   (npm run build:marketplace)
// CI (.github/workflows/marketplace.yml) runs this and fails if either file is stale.

import { readdirSync, readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));

const MARKETPLACE_NAME = 'martech-ai';          // /plugin marketplace add almoretti/martech-ai-skills-and-tools
const PLUGIN_NAME = 'martech-ai-skills';         // /plugin install martech-ai-skills@martech-ai
const KEYWORDS = ['martech', 'marketing', 'competitive-intelligence', 'google-ads', 'microsoft-ads', 'google-merchant-center', 'adtech', 'skills'];

function findSkillDirs(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    if (['node_modules', 'dist', '.git', '.venv', 'venv', '__pycache__'].includes(e.name)) continue;
    const p = join(dir, e.name);
    if (existsSync(join(p, 'SKILL.md'))) out.push(p);
    findSkillDirs(p, out);
  }
  return out;
}

// Only skills under skills/ are shipped by the marketplace. CLI skills live with their CLI
// under CLI/<name>/skills/ and are installed alongside the CLI — they are NOT bundled here,
// because they need the CLI binary + credentials to do anything.
const SKILLS_DIR = join(ROOT, 'skills');
const skills = (existsSync(SKILLS_DIR) ? findSkillDirs(SKILLS_DIR) : [])
  .map((d) => './' + relative(ROOT, d).split('\\').join('/'))
  .sort((a, b) => a.localeCompare(b));

// .claude-plugin/plugin.json — the plugin itself; `version` drives update notifications for installed users
const pluginJson = {
  name: PLUGIN_NAME,
  version: pkg.version,
  description: pkg.description,
  author: { name: 'Alessandro Moretti', url: 'https://github.com/almoretti' },
  repository: pkg.repository.url,
  license: pkg.license,
  keywords: KEYWORDS,
  skills,
};

// .claude-plugin/marketplace.json — a single-plugin marketplace that ships the plugin above
const marketplaceJson = {
  name: MARKETPLACE_NAME,
  owner: { name: 'Alessandro Moretti', url: 'https://github.com/almoretti' },
  description: pkg.description,
  plugins: [
    {
      name: PLUGIN_NAME,
      source: './',
      description: pkg.description,
      category: 'marketing',
      keywords: KEYWORDS,
      skills,
    },
  ],
};

// Standalone plugins under plugins/<name>/ (each with its own .claude-plugin/plugin.json) are listed beside the
// bundle. A dependency on another marketplace's plugin (`name@marketplace`) needs that marketplace allowlisted.
const PLUGINS_DIR = join(ROOT, 'plugins');
const allow = new Set();
for (const name of existsSync(PLUGINS_DIR) ? readdirSync(PLUGINS_DIR).sort() : []) {
  const pj = join(PLUGINS_DIR, name, '.claude-plugin', 'plugin.json');
  if (!existsSync(pj)) continue;
  const p = JSON.parse(readFileSync(pj, 'utf8'));
  marketplaceJson.plugins.push({ name: p.name, source: `./plugins/${name}`, description: p.description });
  for (const dep of p.dependencies || []) {
    const m = typeof dep === 'string' ? dep.split('@')[1] : dep.marketplace;
    if (m && m !== MARKETPLACE_NAME) allow.add(m);
  }
}
if (allow.size) marketplaceJson.allowCrossMarketplaceDependenciesOn = [...allow].sort();

const dir = join(ROOT, '.claude-plugin');
if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, 'plugin.json'), JSON.stringify(pluginJson, null, 2) + '\n');
writeFileSync(join(dir, 'marketplace.json'), JSON.stringify(marketplaceJson, null, 2) + '\n');
console.log(`v${pkg.version} — wrote plugin.json + marketplace.json with ${skills.length} skill(s):`);
skills.forEach((s) => console.log('  ' + s));
