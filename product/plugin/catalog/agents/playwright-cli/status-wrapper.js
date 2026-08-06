#!/usr/bin/env node
/*
 * AgentLinux boundary for @playwright/cli's action-status defect.
 *
 * The pinned upstream client prints a machine-identifiable `### Error` block
 * for daemon action failures but exits zero. JSON mode likewise returns
 * `{isError:true}` with status zero. Keep the package's output and command
 * surface unchanged; only those exact error forms change the process status.
 * Output is collected without a fixed size cap so large valid results remain
 * valid. Page text and ordinary CLI output cannot trigger either check.
 */

const path = require('path');
const childProcess = require('child_process');

const prefix = path.resolve(__dirname, '..');
const realCli = path.join(
  prefix,
  'lib',
  'node_modules',
  '@playwright',
  'cli',
  'playwright-cli.js',
);

const child = childProcess.spawn(process.execPath, [realCli, ...process.argv.slice(2)], {
  env: process.env,
});
const stdoutChunks = [];
const stderrChunks = [];
let spawnError = null;

child.stdout.on('data', (chunk) => stdoutChunks.push(chunk));
child.stderr.on('data', (chunk) => stderrChunks.push(chunk));
child.on('error', (error) => {
  spawnError = error;
});
child.on('close', (status) => {
  const stdout = Buffer.concat(stdoutChunks).toString('utf8');
  const stderr = Buffer.concat(stderrChunks).toString('utf8');
  if (stdout) process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);

  if (spawnError) {
    process.stderr.write(`${spawnError.message}\n`);
    process.exit(1);
  }

  const actionError = /^### Error\r?\nError:/.test(stdout);
  let jsonActionError = false;
  try {
    const parsed = JSON.parse(stdout.trim());
    jsonActionError = parsed?.isError === true;
  } catch {
    // Non-JSON output is the normal human-readable CLI mode.
  }
  if ((actionError || jsonActionError) && status === 0) process.exit(1);
  if (status !== null) process.exit(status);
  process.exit(1);
});
