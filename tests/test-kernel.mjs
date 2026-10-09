import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {fileURLToPath, pathToFileURL} from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const modules = process.env.KERNEL_NODE_MODULES;
assert.ok(modules, 'Run bash tests/test-kernel.sh');
const {createNodeKernel, nodeTransport} = await import(pathToFileURL(path.join(modules, '@ai-ecoverse/slicc-kernel/dist/node.js')));
const source = 'https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/';
const scripts = new Map(await Promise.all(['install.sh', 'upskill', 'gh-upskill'].map(async name => [source + name, await readFile(path.join(root, name))])));
const transport = nodeTransport();
const send = transport.fetch.bind(transport);
transport.fetch = async request => {
  const script = scripts.get(request.url);
  if (!script) return send(request);
  return {
    status: 200,
    statusText: 'OK',
    headers: [['content-type', 'text/plain'], ['content-length', String(script.length)]],
    body: (async function* () { yield script; })(),
    cancel: async () => {},
  };
};
const kernel = await createNodeKernel({network: {transport}, env: {
  HOME: '/home',
  PNPM_HOME: '/home/.local/share/pnpm',
  PATH: '/usr/bin:/bin:/home/.local/share/pnpm/bin',
  ...(process.env.GITHUB_TOKEN ? {GITHUB_TOKEN: process.env.GITHUB_TOKEN} : {}),
  ...(process.env.GH_TOKEN ? {GH_TOKEN: process.env.GH_TOKEN} : {}),
}});
async function copy(directory, destination) {
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const src = path.join(directory, entry.name);
    const dest = `${destination}/${entry.name}`;
    if (entry.isDirectory()) await copy(src, dest);
    else if (entry.isFile()) await kernel.writeFile(dest, await readFile(src));
  }
}
try {
  await copy(path.join(modules, '@ai-ecoverse'), '/node_modules/@ai-ecoverse');
  const result = await kernel.run(['bash', '-e', '-o', 'pipefail', '-c', `
    uname -a
    echo "$PATH"
    for tool in git gh tar unzip python perl; do
      if command -v "$tool"; then exit 1; fi
    done
    curl -fsSL ${source}install.sh | bash
    test "$(command -v upskill)" = "$PNPM_HOME/bin/upskill"
    export SLICC_PAGE_LOOPBACK=1
    curl -fsSL ${source}install.sh | bash
    test "$(command -v upskill)" = "$PNPM_HOME/bin/upskill"
    unset SLICC_PAGE_LOOPBACK
    upskill adobe/helix-website --skill "Searching AEM Documentation"
    test -f "$HOME/.pi/agent/skills/docs-search/SKILL.md"
    upskill read docs-search > /home/read-back.md
    test -s "$HOME/.pi/agent/skills/docs-search/scripts/search.js"
    upskill adobe/helix-website --path .claude/skills/docs-search --skill "Searching AEM Documentation" --dest /home/explicit
    test -f /home/explicit/docs-search/SKILL.md
  `], {cwd: '/home'});
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  assert.equal(result.status, 0, 'SLICC kernel install and skill install must succeed');
  const manifest = await kernel.readFile('/home/.pi/agent/skills/docs-search/SKILL.md');
  assert.match(new TextDecoder().decode(manifest), /name: Searching AEM Documentation/);
  assert.deepEqual(await kernel.readFile('/home/read-back.md'), manifest);
  console.log('KERNEL TEST PASSED');
} finally {
  kernel.terminate();
}
