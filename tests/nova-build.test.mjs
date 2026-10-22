/* ============================================================
 * Created with ♥ by topa-LE
 * ============================================================ */

/*
 * Jellyfin Nova – Build-Tests
 *
 * Checks the locally generated distribution.
 * Does not run a build or modify source files.
 */

import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const cssUrl = new URL('dist/nova.css', root);
const css = await readFile(cssUrl, 'utf8');

test('Nova distribution contains the complete CSS', () => {
    assert.match(css, /--nova-accent:\s*#dc9b66/);
    assert.match(css, /--nova-font-family:/);
    assert.match(css, /@font-face/);
    assert.doesNotMatch(css, /@import\b/i);
});

test('Nova distribution contains all three themes', () => {
    // Dark is the default; Gray and Blue require explicit selection.
    assert.match(
        css,
        /:root:not\(\[data-nova-theme="gray"\]\):not\(\[data-nova-theme="blue"\]\)\s*\{/
    );

    for (const theme of ['gray', 'blue']) {
        assert.match(
            css,
            new RegExp(`data-nova-theme=["']${theme}["']`)
        );
    }

    assert.doesNotMatch(
        css,
        /:root\[data-nova-theme=["']dark["']\]/
    );
});

test('Nova distribution uses local font resources', async () => {
    const references = [
        ...css.matchAll(/url\(\s*["']?(fonts\/[^"')\s]+)["']?\s*\)/g)
    ].map(match => match[1]);

    assert.ok(references.length > 0, 'No local fonts referenced');

    const unique = [...new Set(references)];

    for (const reference of unique) {
        assert.match(reference, /\.woff2$/);
        const file = new URL(`dist/${reference}`, root);
        const info = await stat(file);
        assert.ok(info.size > 0, `Empty font: ${reference}`);
    }

    assert.equal(unique.length, 23);
});

test('Nova distribution includes optional plugin styles', async () => {
    for (const name of ['nova-je.css', 'nova-lite.css', 'nova-mbe.css']) {
        const file = new URL(`dist/plugins/${name}`, root);
        const content = await readFile(file, 'utf8');

        assert.ok(content.length > 0, `Empty plugin: ${name}`);
        assert.doesNotMatch(content, /@import\b/i);
    }
});

test('Nova distribution contains no external CSS resources', () => {
    assert.doesNotMatch(
        css,
        /url\(\s*["']?(?:https?:|\/\/|data:)/i
    );
});


test('Nova Login resources match their sources', async () => {
    for (const [sourcePath, outputPath] of [
        ['src/assets/jellyfin-logo.png', 'dist/assets/jellyfin-logo.png'],
        ['src/login/login-loader.js', 'dist/login/login-loader.js']
    ]) {
        const original = await readFile(new URL(sourcePath, root));
        const built = await readFile(new URL(outputPath, root));

        assert.ok(original.length > 0, `Empty source: ${sourcePath}`);
        assert.deepEqual(built, original, outputPath);
    }
});

test('Nova Login loader uses the bundled logo and correct login selectors', async () => {
    const loader = await readFile(
        new URL('dist/login/login-loader.js', root),
        'utf8'
    );

    assert.match(loader, /nova-login-final-logo/);
    assert.match(loader, /#loginPage/);
    assert.match(loader, /\.manualLoginForm/);
    assert.match(loader, /assets\/jellyfin-logo\.png/);
    assert.match(loader, /MutationObserver/);
    assert.match(loader, /document\.currentScript/);
    assert.doesNotMatch(loader, /banner-light\.[a-f0-9]+\.png/i);
});

test('Nova Spotlight distribution files match their sources', async () => {
    const { readFile } = await import('node:fs/promises');
    const { resolve } = await import('node:path');
    const { strict: assert } = await import('node:assert');

    for (const name of ['spotlight-loader.js', 'spotlight.html', 'spotlight.css']) {
        const source = await readFile(resolve('src/spotlight', name));
        const built = await readFile(resolve('dist/spotlight', name));
        assert.deepEqual(built, source, name);
    }
});

test('Nova Spotlight loader and HTML use matching communication identifiers', async () => {
    const { readFile } = await import('node:fs/promises');
    const { strict: assert } = await import('node:assert');

    const loader = await readFile('dist/spotlight/spotlight-loader.js', 'utf8');
    const html = await readFile('dist/spotlight/spotlight.html', 'utf8');

    assert.match(loader, /nova-spotlight/);
    assert.match(html, /nova-spotlight/);
    assert.match(loader, /nova-spotlight-visible/);
    assert.match(loader, /nova-spotlight-active/);
});

test('Nova Spotlight state classes match the main Nova stylesheet', async () => {
    const { readFile } = await import('node:fs/promises');
    const { strict: assert } = await import('node:assert');

    const css = await readFile('dist/nova.css', 'utf8');

    assert.match(css, /nova-spotlight-visible/);
    assert.match(css, /nova-spotlight-active/);
    assert.doesNotMatch(css, /abyss-spotlight/);
});

test('Nova Spotlight uses its locally bundled Inter font', async () => {
    const { readFile, stat } = await import('node:fs/promises');
    const { resolve, dirname } = await import('node:path');
    const { strict: assert } = await import('node:assert');

    const cssFile = resolve('dist/spotlight/spotlight.css');
    const css = await readFile(cssFile, 'utf8');
    const html = await readFile('dist/spotlight/spotlight.html', 'utf8');

    const fontPath = '../fonts/inter/InterVariable.woff2';

    assert.ok(css.includes(fontPath));
    assert.ok((await stat(resolve(dirname(cssFile), fontPath))).size > 0);
    assert.ok(html.includes('href="spotlight.css"'));
    assert.doesNotMatch(html + css, /fonts\.googleapis|fonts\.gstatic|Google Sans/i);
});

test('Nova Spotlight has no legacy Abyss references and checks Nova releases', async () => {
    const { readFile } = await import('node:fs/promises');
    const { strict: assert } = await import('node:assert');

    const files = await Promise.all(
        ['spotlight-loader.js', 'spotlight.html', 'spotlight.css']
            .map(name => readFile('dist/spotlight/' + name, 'utf8'))
    );

    const combined = files.join('\n');
    const html = files[1];

    assert.doesNotMatch(combined, /abyss|AumGupta/i);
    assert.match(html, /NOVA_SPOTLIGHT_VERSION/);
    assert.ok(html.includes('https://api.github.com/repos/topa-LE/jellyfin-nova/releases/latest'));
    assert.ok(html.includes('https://github.com/topa-LE/jellyfin-nova/releases/tag/'));
});
