#!/usr/bin/env node
// Regenerate .claude-plugin/marketplace.json from the skills present in the repo.
// A skill = any directory containing a SKILL.md, under Skills/ or CLI/*/skills/.
// Run after adding/removing/renaming a skill:  node scripts/build-marketplace.mjs
// CI (.github/workflows/marketplace.yml) runs this and fails if the committed file is stale.

import { readdirSync, readFileSync, writeFileSync, existsSync, statSync, mkdirSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// find every dir with a SKILL.md (skip deps)
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

// pull name + description out of SKILL.md YAML frontmatter (handles folded >- blocks)
function parseFrontmatter(md) {
  const m = md.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return {};
  const fm = m[1].split('\n');
  const out = {};
  for (let i = 0; i < fm.length; i++) {
    const line = fm[i];
    const kv = line.match(/^([A-Za-z_-]+):\s*(.*)$/);
    if (!kv) continue;
    const key = kv[1];
    let val = kv[2].trim();
    if (val === '>-' || val === '>' || val === '|' || val === '|-' || val === '') {
      // collect subsequent more-indented lines
      const buf = [];
      while (i + 1 < fm.length && /^\s+\S/.test(fm[i + 1])) { buf.push(fm[++i].trim()); }
      val = buf.join(' ').trim();
    }
    if (key === 'name' || key === 'description') out[key] = val.replace(/\s+/g, ' ');
  }
  return out;
}

const plugins = findSkillDirs(ROOT)
  .map((d) => {
    const fm = parseFrontmatter(readFileSync(join(d, 'SKILL.md'), 'utf8'));
    const rel = './' + relative(ROOT, d).split('\\').join('/');
    return { name: fm.name || d.split('/').pop(), source: './', skills: [rel], description: fm.description || '' };
  })
  .sort((a, b) => a.name.localeCompare(b.name));

const marketplace = {
  name: 'martech-ai-skills-and-tools',
  owner: { name: 'Alessandro Moretti', url: 'https://github.com/almoretti' },
  metadata: {
    description: 'Martech AI skills & read-only CLIs for AI agents — martech teardown, Google Ads, Microsoft Ads, Google Merchant Center.',
    version: '0.1.0',
  },
  plugins,
};

const dir = join(ROOT, '.claude-plugin');
if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, 'marketplace.json'), JSON.stringify(marketplace, null, 2) + '\n');
console.log(`marketplace.json written with ${plugins.length} plugin(s): ${plugins.map((p) => p.name).join(', ')}`);
