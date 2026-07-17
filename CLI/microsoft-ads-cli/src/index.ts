#!/usr/bin/env node
import { createRequire } from "node:module";
import { Command } from "commander";

const require = createRequire(import.meta.url);
const { version } = require("../package.json") as { version: string };
import { registerAuthCommands } from "./commands/auth.js";
import { registerAccountCommands } from "./commands/accounts.js";
import { registerCampaignCommands } from "./commands/campaigns.js";
import { registerAdGroupCommands } from "./commands/adgroups.js";
import { registerStatsCommands } from "./commands/stats.js";
import { registerTargetingCommands } from "./commands/targeting.js";
import { registerAssetCommands } from "./commands/assets.js";
import { registerQueryCommands } from "./commands/query.js";

const program = new Command();

program
  .name("microsoft-ads-cli")
  .description("Microsoft Advertising (Bing Ads) CLI & Skills for AI agents")
  .version(version)
  .option("--format <format>", "Output format", "json")
  .option("--credentials <path>", "Path to credentials JSON file")
  .addHelpText(
    "after",
    "\nDocs: https://github.com/almoretti/martech-ai-skills-and-tools/tree/main/CLI/microsoft-ads-cli"
  );

program.configureOutput({
  writeErr: (str: string) => {
    const msg = str.replace(/^error: /i, "").trim();
    if (msg) process.stderr.write(JSON.stringify({ error: msg }) + "\n");
  },
  writeOut: (str: string) => {
    process.stdout.write(str);
  },
});

program.showHelpAfterError(false);

program.hook("preAction", () => {
  const format = program.opts().format;
  if (format !== "json" && format !== "compact") {
    process.stderr.write(
      JSON.stringify({ error: "Format must be 'json' or 'compact'." }) + "\n"
    );
    process.exit(1);
  }
});

registerAuthCommands(program);
registerAccountCommands(program);
registerCampaignCommands(program);
registerAdGroupCommands(program);
registerStatsCommands(program);
registerTargetingCommands(program);
registerAssetCommands(program);
registerQueryCommands(program);

program.on("command:*", (operands) => {
  process.stderr.write(
    JSON.stringify({ error: `Unknown command: ${operands[0]}. Run --help for available commands.` }) + "\n"
  );
  process.exit(1);
});

if (process.argv.length <= 2) {
  program.outputHelp();
  process.exit(0);
}

program.parse();
