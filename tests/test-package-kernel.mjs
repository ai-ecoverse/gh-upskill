import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {gunzipSync} from 'node:zlib';

const modules = process.env.KERNEL_NODE_MODULES;
const tarball = process.env.UPSKILL_TGZ;
assert.ok(modules && tarball, 'Run bash tests/test-package-kernel.sh');
const {createNodeKernel} = await import(pathToFileURL(path.join(modules, '@ai-ecoverse/slicc-kernel/dist/node.js')));
const TOOLS = '/opt/slicc/tools/node_modules';
const kernel = await createNodeKernel({commands: {append: [TOOLS]}});

async function copy(directory, destination) {
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const src = path.join(directory, entry.name);
    const dest = `${destination}/${entry.name}`;
    if (entry.isDirectory()) await copy(src, dest);
    else if (entry.isFile()) await kernel.writeFile(dest, await readFile(src));
  }
}

function untar(bytes) {
  const files = [];
  for (let at = 0; at + 512 <= bytes.length;) {
    const header = bytes.subarray(at, at + 512);
    const name = header.subarray(0, 100).toString().replace(/\0.*$/s, '');
    if (!name) break;
    const size = parseInt(header.subarray(124, 136).toString().replace(/\0.*$/s, '').trim() || '0', 8);
    const type = String.fromCharCode(header[156] || 48);
    if (type === '0') files.push({name, data: bytes.subarray(at + 512, at + 512 + size)});
    at += 512 + Math.ceil(size / 512) * 512;
  }
  return files;
}

async function sh(script) {
  const result = await kernel.run(['bash', '-e', '-o', 'pipefail', '-c', script], {cwd: '/tmp'});
  return {code: result.status, out: `${result.stdout ?? ''}`.trim(), err: `${result.stderr ?? ''}`.trim()};
}

try {
  await copy(path.join(modules, '@ai-ecoverse'), '/node_modules/@ai-ecoverse');
  const packed = await readFile(tarball);
  await kernel.writeFile('/tmp/gh-upskill.tgz', packed);

  const global = await sh(`
    pnpm add -g /tmp/gh-upskill.tgz >/tmp/pnpm.log 2>&1 || { cat /tmp/pnpm.log; exit 1; }
    printf 'pnpm-home=%s\\n' "$(command -v upskill)"
    upskill --version
    gh-upskill --version
    "$PNPM_HOME/bin/upskill" --version
    "$PNPM_HOME/bin/gh-upskill" --version
    /usr/bin/upskill --version
    /usr/bin/gh-upskill --version
    upskill --help | grep -c outdated
    printf '%s\\n' "$(upskill read 'no such skill' --dest '/tmp/a dir' 2>&1 >/dev/null; echo "status=$?")" | tail -1
  `);
  assert.equal(global.code, 0, `${global.out}\n${global.err}`);
  const lines = global.out.split('\n');
  assert.match(lines[0], /^pnpm-home=\/usr\/local\/share\/pnpm\/bin\/upskill$/, global.out);
  assert.deepEqual(lines.slice(1, 7), Array(6).fill('upskill 9.8.7'), global.out);
  assert.ok(Number(lines[7]) > 0, global.out);
  assert.match(lines[8], /^status=[1-9]/, global.out);
  const removed = await sh('pnpm remove -g @ai-ecoverse/gh-upskill >/dev/null 2>&1; command -v upskill || echo gone');
  assert.equal(removed.out, 'gone', removed.out);

  for (const {name, data} of untar(gunzipSync(packed))) {
    const file = `${TOOLS}/@ai-ecoverse/gh-upskill/${name.replace(/^package\//, '')}`;
    await kernel.writeFile(file, data);
  }
  await kernel.writeFile('/tmp/install.sh', await readFile(new URL('../install.sh', import.meta.url)));
  const tools = await sh(`
    chmod 0755 ${TOOLS}/@ai-ecoverse/gh-upskill/upskill ${TOOLS}/@ai-ecoverse/gh-upskill/gh-upskill
    command -v upskill
    stat -c '%U %a' /usr/bin/upskill /usr/bin/gh-upskill
    upskill --version
    gh-upskill --version
    bash /tmp/install.sh
    test ! -e "$PNPM_HOME/bin/upskill"
    command -v upskill
  `);
  assert.equal(tools.code, 0, `${tools.out}\n${tools.err}`);
  assert.deepEqual(tools.out.split('\n'), [
    '/usr/bin/upskill',
    'root 755',
    'root 755',
    'upskill 9.8.7',
    'upskill 9.8.7',
    'seven ships upskill in /usr/bin; nothing to install. Use --bin-dir to install a copy anyway.',
    '/usr/bin/upskill',
  ], tools.out);
  console.log('PACKAGE KERNEL TEST PASSED');
} finally {
  kernel.terminate();
}
