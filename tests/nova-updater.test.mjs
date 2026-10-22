import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const source = fs.readFileSync(
    new URL('../scripts/installer/nova-updater.sh', import.meta.url),
    'utf8'
);

const start = source.indexOf(
    'echo "===== 8. UPDATE HOST INSTALLATION SCRIPTS ====="'
);
const end = source.indexOf(
    'echo "Jellyfin Nova update completed."',
    start
);

assert.ok(start >= 0 && end > start);

const block = source.slice(start, end);

function runUpdateTest(failSecond) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nova-test-'));

    try {
        const installed = path.join(root, 'installed');
        const current = path.join(root, 'current');
        const temporary = path.join(root, 'temporary');

        for (const dir of [installed, current, temporary]) {
            fs.mkdirSync(dir);
        }

        const oldInstaller = '#!/bin/bash\necho OLD_INSTALLER\n';
        const oldUpdater = '#!/bin/bash\necho OLD_UPDATER\n';
        const newInstaller = '#!/bin/bash\necho NEW_INSTALLER\n';
        const newUpdater = '#!/bin/bash\necho NEW_UPDATER\n';

        for (const [dir, name, data] of [
            [installed, 'nova-installer.sh', oldInstaller],
            [installed, 'nova-updater.sh', oldUpdater],
            [current, 'nova-installer.sh', newInstaller],
            [current, 'nova-updater.sh', newUpdater]
        ]) {
            fs.writeFileSync(path.join(dir, name), data);
        }

        const assignments = {
            SCRIPT_DIR: installed,
            INSTALLER: path.join(installed, 'nova-installer.sh'),
            CURRENT_INSTALLER: path.join(current, 'nova-installer.sh'),
            CURRENT_UPDATER: path.join(current, 'nova-updater.sh'),
            TEMP_DIR: temporary
        };

        const lines = ['set -euo pipefail'];

        for (const [name, value] of Object.entries(assignments)) {
            lines.push(name + '=' + JSON.stringify(value));
        }

        if (failSecond) {
            lines.push(
                'mv() {',
                '  if [[ "$*" == *"nova-updater.sh"* ]]; then return 1; fi',
                '  command mv "$@"',
                '}'
            );
        }

        lines.push(block);

        const result = spawnSync('bash', ['-c', lines.join('\n')], {
            encoding: 'utf8'
        });

        const actualInstaller = fs.readFileSync(
            path.join(installed, 'nova-installer.sh'), 'utf8'
        );
        const actualUpdater = fs.readFileSync(
            path.join(installed, 'nova-updater.sh'), 'utf8'
        );

        if (failSecond) {
            assert.notEqual(result.status, 0);
            assert.equal(actualInstaller, oldInstaller);
            assert.equal(actualUpdater, oldUpdater);
        } else {
            assert.equal(result.status, 0, result.stderr);
            assert.equal(actualInstaller, newInstaller);
            assert.equal(actualUpdater, newUpdater);
        }
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
}

test('Nova updater installs both scripts', () => {
    runUpdateTest(false);
});

test('Nova updater restores both scripts on failure', () => {
    runUpdateTest(true);
});
