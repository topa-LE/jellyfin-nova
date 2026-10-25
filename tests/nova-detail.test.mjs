/* ============================================================
 * Created with ♥ by topa-LE
 * ============================================================ */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sourcePath = 'src/detail/detail-loader.js';
const distributionPath = 'dist/detail/detail-loader.js';

test('Nova external database buttons use bundled artwork', async () => {
    const loader = await readFile('src/detail/detail-loader.js', 'utf8');
    const css = await readFile('dist/nova.css', 'utf8');

    assert.match(loader, /function updateExternalLinks\(\)/);
    assert.match(loader, /nova-external-button/);
    assert.ok(loader.includes("imdb.com"));
    assert.ok(loader.includes("themoviedb.org"));
    assert.match(loader, /new MutationObserver/);

    assert.match(css, /NOVA MOVIE EXTERNAL DATABASE BUTTONS/);
    assert.ok(css.includes('assets/icons/imdb-nova.webp'));
    assert.ok(css.includes('assets/icons/tmdb-nova.webp'));

    for (const name of ['imdb-nova.webp', 'tmdb-nova.webp']) {
        const original = await readFile(`src/assets/icons/${name}`);
        const distribution = await readFile(`dist/assets/icons/${name}`);

        assert.deepEqual(distribution, original);
    }
});

test('Nova Detail loader distribution matches its source', async () => {
    const source = await readFile(sourcePath);
    const distribution = await readFile(distributionPath);

    assert.deepEqual(distribution, source);
});

test('Nova Detail loader handles individually clickable tags', async () => {
    const source = await readFile(sourcePath, 'utf8');

    assert.match(source, /MutationObserver/);
    assert.match(source, /#itemDetailPage/);
    assert.match(source, /\.itemTags/);
    assert.match(source, /nova-tags-label/);
    assert.match(source, /Markierungen\|Tags/);
    assert.match(source, /node\.remove\(\)/);
    assert.match(source, /window\.__novaDetailLoaderLoaded/);
});

test('Nova Detail tags glass styling is included in CSS', async () => {
    const css = await readFile('dist/nova.css', 'utf8');

    assert.match(css, /NOVA MOVIE TAGS GLASS/);
    assert.match(css, /#itemDetailPage \.itemTags > a\.button-link/);
    assert.match(css, /#itemDetailPage \.itemTags > \.nova-tags-label/);
});
