import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const installer = readFileSync(
  'scripts/installer/nova-installer.sh',
  'utf8'
);

const start = installer.indexOf('transform_branding_json() {');
const end = installer.indexOf('set_spotlight_index() {', start);

assert.ok(start >= 0, 'Branding function must exist');
assert.ok(end > start, 'Branding function must have a valid boundary');

const brandingFunction = installer.slice(start, end);

function transform(mode, data) {
  const result = spawnSync(
    'bash',
    ['-c', brandingFunction + '\ntransform_branding_json "$1"\n', 'nova-test', mode],
    {
      input: JSON.stringify(data),
      encoding: 'utf8'
    }
  );

  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

const novaCss = [
  '/* NOVA THEME START */',
  "@import url('/web/nova/nova.css');",
  '/* NOVA THEME END */'
].join('\n');

const legacyCss = [
  '@import url("https://theme-park.dev/css/base/jellyfin/space-gray.css");',
  'html {',
  '    font-family: "Saira Condensed";',
  '    font-size: 107%;',
  '}'
].join('\n');

const original = {
  CustomCss: legacyCss,
  LoginDisclaimer: 'Korea Drama Jellyfin',
  SplashscreenEnabled: true
};

test('installation replaces legacy CSS and preserves branding', () => {
  const result = transform('install', original);

  assert.equal(result.CustomCss, novaCss);
  assert.equal(result.LoginDisclaimer, original.LoginDisclaimer);
  assert.equal(result.SplashscreenEnabled, true);
  assert.equal(original.CustomCss, legacyCss);
});

test('repeated installation does not duplicate Nova CSS', () => {
  const first = transform('install', original);
  const second = transform('install', first);

  assert.deepEqual(second, first);
});

test('uninstall removes the Nova block', () => {
  const installed = transform('install', original);
  const removed = transform('uninstall', installed);

  assert.equal(removed.CustomCss, '');
  assert.equal(removed.LoginDisclaimer, original.LoginDisclaimer);
});

test('uninstall preserves unrelated custom CSS', () => {
  assert.deepEqual(transform('uninstall', original), original);
});

test('branding confirmation precedes package installation', () => {
  const prepareStart = installer.indexOf('prepare_nova_branding() {');
  const installStart = installer.indexOf('install_nova() {');
  const uninstallStart = installer.indexOf('uninstall_nova() {', installStart);

  assert.ok(prepareStart >= 0, 'Shared branding function must exist');
  assert.ok(installStart > prepareStart, 'Installer must follow branding function');
  assert.ok(uninstallStart > installStart);

  const preparation = installer.slice(prepareStart, installStart);
  const installation = installer.slice(installStart, uninstallStart);

  const backup = preparation.indexOf('Backing up existing Jellyfin branding');
  const confirmation = preparation.indexOf('Replace existing custom CSS?');

  assert.ok(backup >= 0, 'Branding backup must exist');
  assert.ok(confirmation > backup, 'Confirmation must follow backup');

  const prepareCall = installation.indexOf(
    'prepare_nova_branding "$server_url" "$api_header"'
  );
  const packageInstall = installation.indexOf(
    'step "Installing Nova package..."'
  );

  assert.ok(prepareCall >= 0, 'Installer must call branding preparation');
  assert.ok(packageInstall > prepareCall, 'Branding must precede package installation');
});

test('branding backup uses a JSON-compatible newline', () => {
  const expected = "printf '%s" + String.fromCharCode(92) + "n'";

  assert.ok(
    installer.includes(expected + ' "$branding" > "$branding_backup_file"'),
    'Branding backup must use a valid printf newline'
  );
});

test('CSS comparison preserves trailing newlines', () => {
  const startMarker = "    if ! css_comparison=$(python3 -c '";
  const endMarker = "' \"$branding\" \"$updated_branding\"); then";

  const start = installer.indexOf(startMarker);
  assert.ok(start >= 0, 'CSS comparison must exist');

  const end = installer.indexOf(endMarker, start + startMarker.length);
  assert.ok(end > start, 'CSS comparison must have a valid boundary');

  const comparison = installer.slice(start + startMarker.length, end);

  const cases = [
    ['Empty CSS', '', 'NOVA', 'keep'],
    ['Legacy CSS', 'body { color: red; }', 'NOVA', 'replace'],
    ['Identical CSS', 'NOVA', 'NOVA', 'keep'],
    ['Trailing newline', 'NOVA\n', 'NOVA', 'replace'],
    ['Multiple trailing newlines', 'NOVA\n\n', 'NOVA', 'replace'],
    ['Whitespace-only CSS', '   \n', 'NOVA', 'replace'],
    ['Unicode CSS', '/* Grüße */', 'NOVA', 'replace']
  ];

  for (const [name, originalCss, replacementCss, expected] of cases) {
    const result = spawnSync(
      'python3',
      [
        '-c',
        comparison,
        JSON.stringify({ CustomCss: originalCss }),
        JSON.stringify({ CustomCss: replacementCss })
      ],
      { encoding: 'utf8' }
    );

    assert.equal(result.status, 0, `${name}: ${result.stderr}`);
    assert.equal(result.stdout.trim(), expected, name);
  }
});
