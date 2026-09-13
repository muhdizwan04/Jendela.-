import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

/// Runs the API, the site and the dashboard together, each labelled, so one
/// terminal shows everything and one Ctrl-C stops it all.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const parts = [
  { name: "api  ", dir: "server", command: "./run.sh", colour: "\x1b[36m" },
  { name: "web  ", dir: "web", command: "npm", args: ["run", "dev", "--silent"], colour: "\x1b[35m" },
  { name: "admin", dir: "admin", command: "npm", args: ["run", "dev", "--silent"], colour: "\x1b[33m" },
];

const children = parts.map(({ name, dir, command, args = [], colour }) => {
  const child = spawn(command, args, { cwd: path.join(root, dir), env: process.env });
  const write = (stream) => (data) =>
    String(data).split("\n").filter(Boolean)
      .forEach((line) => stream.write(`${colour}${name}\x1b[0m │ ${line}\n`));
  child.stdout.on("data", write(process.stdout));
  child.stderr.on("data", write(process.stderr));
  return child;
});

const stop = () => { children.forEach((c) => c.kill("SIGTERM")); process.exit(0); };
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
