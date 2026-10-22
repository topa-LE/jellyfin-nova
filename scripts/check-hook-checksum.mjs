import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const installerPath = resolve(
    projectRoot,
    'scripts/installer/nova-installer.sh'
);

const hookPath = resolve(
    projectRoot,
    'scripts/docker/nova-init.sh'
);

const installer = await readFile(installerPath, 'utf8');
const hook = await readFile(hookPath);

const matches = [
    ...installer.matchAll(
        /^\s*local expected_sha256="([0-9a-f]{64})"\s*$/gm
    )
];

if (matches.length !== 1) {
    throw new Error(
        `Erwartet genau eine Startup-Hook-Pruefsumme, gefunden: ${matches.length}`
    );
}

const expected = matches[0][1];

const actual = createHash('sha256')
    .update(hook)
    .digest('hex');

if (expected !== actual) {
    console.error('FEHLER: Nova Startup-Hook-Pruefsumme stimmt nicht.');
    console.error(`Installer: ${expected}`);
    console.error(`Hook:      ${actual}`);
    process.exitCode = 1;
} else {
    console.log('OK: Nova Startup-Hook-Pruefsumme stimmt.');
}
