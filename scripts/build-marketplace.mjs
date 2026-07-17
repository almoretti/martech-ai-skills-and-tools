#!/usr/bin/env node
// Regenerate BOTH Claude Code manifests from the skills present + the version in package.json:
//   .claude-plugin/plugin.json      — the bundled plugin (name, version, keywords, skills[])
//   .claude-plugin/marketplace.json — the single-plugin marketplace that ships it
// A skill = any directory containing a SKILL.md, under Skills/ or CLI/*/skills/.
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

const skills = findSkillDirs(ROOT)
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

const dir = join(ROOT, '.claude-plugin');
if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, 'plugin.json'), JSON.stringify(pluginJson, null, 2) + '\n');
writeFileSync(join(dir, 'marketplace.json'), JSON.stringify(marketplaceJson, null, 2) + '\n');
console.log(`v${pkg.version} — wrote plugin.json + marketplace.json with ${skills.length} skill(s):`);
skills.forEach((s) => console.log('  ' + s));
