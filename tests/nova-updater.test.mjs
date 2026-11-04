/* ============================================================
 * Created with ♥ by topa-LE
 * ============================================================ */

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

test('Nova updater activates branding through Jellyfin API', () => {
    const startMarker = 'echo "===== ACTIVATE NOVA BRANDING ====="';
    const endMarker = 'echo "===== 8. UPDATE HOST INSTALLATION SCRIPTS ====="';

    const start = source.indexOf(startMarker);
    const end = source.indexOf(endMarker, start);

    assert.ok(start >= 0, 'Branding activation must exist');
    assert.ok(end > start, 'Branding activation must precede script updates');

    const activation = source.slice(start, end);
    const branding = {
        CustomCss: "/* NOVA THEME START */\n@import url('/web/nova/nova.css');\n/* NOVA THEME END */",
        LoginDisclaimer: 'Korea Drama Jellyfin',
        SplashscreenEnabled: true
    };

    for (const shouldFail of [false, true]) {
        const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nova-branding-api-'));

        try {
            const payloadFile = path.join(root, 'payload.json');

            const script = [
                'set -euo pipefail',
                'nova_server_url="http://127.0.0.1:8096"',
                'nova_api_header="Nova test authorization"',
                'nova_updated_branding=' + JSON.stringify(JSON.stringify(branding)),
                'curl() {',
                '  local argument',
                '  local found_endpoint=0',
                '  local found_content_type=0',
                '  local found_stdin=0',
                '  for argument in "$@"; do',
                '    [[ "$argument" == "http://127.0.0.1:8096/System/Configuration/Branding" ]] && found_endpoint=1',
                '    [[ "$argument" == "Content-Type: application/json" ]] && found_content_type=1',
                '    [[ "$argument" == "@-" ]] && found_stdin=1',
                '  done',
                '  [[ "$found_endpoint" -eq 1 && "$found_content_type" -eq 1 && "$found_stdin" -eq 1 ]] || return 2',
                '  cat > ' + JSON.stringify(payloadFile),
                shouldFail ? '  return 22' : '  return 0',
                '}',
                activation
            ].join('\n');

            const result = spawnSync('bash', ['-c', script], {
                encoding: 'utf8'
            });

            assert.equal(
                result.status === 0,
                !shouldFail,
                `Unexpected updater result: ${result.stderr}`
            );

            assert.deepEqual(
                JSON.parse(fs.readFileSync(payloadFile, 'utf8')),
                branding
            );

            if (shouldFail) {
                assert.match(result.stderr, /Could not activate Nova CSS/);
                assert.doesNotMatch(result.stdout, /OK: Nova CSS activated/);
            } else {
                assert.match(result.stdout, /OK: Nova CSS activated/);
            }
        } finally {
            fs.rmSync(root, { recursive: true, force: true });
        }
    }
});

test('Nova updater prepares branding before changing files', () => {
    const positions = {
        validation: source.indexOf('validate_nova_package_before_docker "$ARCHIVE"'),
        authentication: source.indexOf('connect_jellyfin "$nova_server_url"'),
        preparation: source.indexOf(
            'prepare_nova_branding "$nova_server_url" "$nova_api_header"'
        ),
        hook: source.indexOf('install_nova_docker_init_hook "$CONTAINER"'),
        package: source.indexOf('install_nova_docker_package "$CONTAINER"'),
        index: source.indexOf('set_nova_docker_spotlight_index "$CONTAINER"'),
        hash: source.indexOf('if [[ "$persistent_hash" != "$active_hash" ]]'),
        activation: source.indexOf('===== ACTIVATE NOVA BRANDING ====='),
        scriptUpdate: source.indexOf('===== 8. UPDATE HOST INSTALLATION SCRIPTS =====')
    };

    for (const [name, position] of Object.entries(positions)) {
        assert.ok(position >= 0, `Missing updater stage: ${name}`);
    }

    const order = [
        'validation',
        'authentication',
        'preparation',
        'hook',
        'package',
        'index',
        'hash',
        'activation',
        'scriptUpdate'
    ];

    for (let i = 1; i < order.length; i++) {
        assert.ok(
            positions[order[i]] > positions[order[i - 1]],
            `${order[i]} must follow ${order[i - 1]}`
        );
    }
});
