#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import {
  analyzeMidiCapabilities,
  formatCapabilityReportMarkdown
} from "../src/midi/capability-analysis.js";

const HELP = `Usage:
  node scripts/analyze-midi-capabilities.mjs <inventory.json> [options]

Options:
  -o, --output <report.md>         Write the report instead of printing it
      --mirror-window-ms <number>  Exact-byte mirror matching window (default: 12)
      --mirror-threshold <0..1>    Required directional match rate (default: 0.95)
      --mirror-min-matches <count> Required matches for candidate status (default: 20)
      --mirror-min-signatures <n>  Required varied messages (default: 3)
  -h, --help                       Show this help
`;

async function main() {
  let command;
  try {
    command = parseArguments(process.argv.slice(2));
  } catch (error) {
    fail(error.message, true);
    return;
  }

  if (command.help) {
    process.stdout.write(HELP);
    return;
  }
  if (!command.inputPath) {
    fail("An inventory JSON path is required.", true);
    return;
  }
  if (command.outputPath && samePath(command.inputPath, command.outputPath)) {
    fail("The Markdown output must not overwrite the source inventory.");
    return;
  }

  let text;
  try {
    text = await readFile(command.inputPath, "utf8");
  } catch {
    fail(`Could not read inventory file "${basename(command.inputPath)}".`);
    return;
  }

  let inventory;
  try {
    inventory = JSON.parse(text);
  } catch (error) {
    fail(`Inventory "${basename(command.inputPath)}" is not valid JSON: ${error.message}`);
    return;
  }

  let report;
  try {
    const analysis = analyzeMidiCapabilities(inventory, command.analysisOptions);
    report = formatCapabilityReportMarkdown(analysis);
  } catch (error) {
    fail(`Could not analyze inventory: ${error.message}`);
    return;
  }

  if (!command.outputPath) {
    process.stdout.write(report);
    return;
  }

  try {
    await mkdir(dirname(resolve(command.outputPath)), { recursive: true });
    await writeFile(command.outputPath, report, "utf8");
    process.stdout.write(`Wrote MIDI capability report to "${basename(command.outputPath)}".\n`);
  } catch {
    fail(`Could not write report file "${basename(command.outputPath)}".`);
  }
}

function parseArguments(argumentsList) {
  const result = { inputPath: null, outputPath: null, analysisOptions: {}, help: false };
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === "-h" || argument === "--help") {
      result.help = true;
      continue;
    }
    if (argument === "-o" || argument === "--output") {
      result.outputPath = requireValue(argumentsList, ++index, argument);
      continue;
    }
    if (argument === "--mirror-window-ms") {
      result.analysisOptions.mirrorWindowMs = parseNumber(requireValue(argumentsList, ++index, argument), argument);
      continue;
    }
    if (argument === "--mirror-threshold") {
      result.analysisOptions.mirrorMatchThreshold = parseNumber(requireValue(argumentsList, ++index, argument), argument);
      continue;
    }
    if (argument === "--mirror-min-matches") {
      result.analysisOptions.mirrorMinimumMatches = parseNumber(requireValue(argumentsList, ++index, argument), argument);
      continue;
    }
    if (argument === "--mirror-min-signatures") {
      result.analysisOptions.mirrorMinimumSignatures = parseNumber(requireValue(argumentsList, ++index, argument), argument);
      continue;
    }
    if (argument.startsWith("-")) throw new Error(`Unknown option: ${argument}`);
    if (result.inputPath) throw new Error("Only one inventory JSON path may be supplied.");
    result.inputPath = argument;
  }
  return result;
}

function requireValue(argumentsList, index, option) {
  const value = argumentsList[index];
  if (!value || value.startsWith("-")) throw new Error(`${option} requires a value.`);
  return value;
}

function parseNumber(value, option) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`${option} requires a finite number.`);
  return parsed;
}

function samePath(left, right) {
  const leftPath = resolve(left);
  const rightPath = resolve(right);
  return process.platform === "win32"
    ? leftPath.toLowerCase() === rightPath.toLowerCase()
    : leftPath === rightPath;
}

function fail(message, showHelp = false) {
  process.stderr.write(`${message}\n`);
  if (showHelp) process.stderr.write(`\n${HELP}`);
  process.exitCode = 1;
}

await main();
