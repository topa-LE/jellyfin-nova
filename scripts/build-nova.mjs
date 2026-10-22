/*
 * Jellyfin Nova – CSS Build
 *
 * Fuehrt die modularen Nova-CSS-Dateien zusammen.
 * Kopiert lokale Schriftdateien und optionale Zusatzmodule.
 *
 * Keine externen npm-Abhaengigkeiten.
 * Keine Veraenderungen an den Quelldateien.
 */

import { readFile, writeFile, mkdir, copyFile, rm, rename, lstat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, dirname, relative, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourceRoot = resolve(projectRoot, 'src');
const entryFile = resolve(sourceRoot, 'styles/nova.css');
const outputRoot = resolve(projectRoot, 'dist');
const stagingRoot = resolve(projectRoot, '.dist-nova-building');
const backupRoot = resolve(projectRoot, '.dist-nova-previous');

const spotlightFiles = [
    'spotlight-loader.js',
    'spotlight.html',
    'spotlight.css'
];

const assetFiles = [
    'jellyfin-logo.png'
];

const loginFiles = [
    'login-loader.js'
];

const optionalModules = [
    'nova-je.css',
    'nova-lite.css',
    'nova-mbe.css'
];

const importPattern = /@import\s+url\(\s*["']([^"']+)["']\s*\)\s*;/g;
const urlPattern = /url\(\s*["']?([^"')]+)["']?\s*\)/g;

const fontFiles = new Map();
const importedFiles = new Set();

function fail(message) {
    throw new Error(message);
}

function insideDirectory(path, directory) {
    return path === directory || path.startsWith(directory + sep);
}

async function buildCss(path) {
    const absolutePath = resolve(path);

    if (!insideDirectory(absolutePath, resolve(sourceRoot, 'styles'))) {
        fail(`CSS-Datei ausserhalb des Nova-Styles-Verzeichnisses: ${absolutePath}`);
    }

    if (!existsSync(absolutePath)) {
        fail(`CSS-Datei fehlt: ${absolutePath}`);
    }

    if (importedFiles.has(absolutePath)) {
        fail(`Doppelter oder zyklischer CSS-Import: ${absolutePath}`);
    }

    importedFiles.add(absolutePath);

    let css = await readFile(absolutePath, 'utf8');
    const importedModules = [];
    const imports = [...css.matchAll(importPattern)];

    for (const match of imports) {
        const reference = match[1];

        if (/^(?:https?:|\/\/|data:)/i.test(reference)) {
            fail(`Externer CSS-Import nicht erlaubt: ${reference}`);
        }

        const importedPath = resolve(dirname(absolutePath), reference);
        const importedCss = await buildCss(importedPath);

        css = css.replace(match[0], `/* NOVA MODULE: ${reference} */`);
        importedModules.push(importedCss);
    }

    if (/@import\b/i.test(css)) {
        fail(`Nicht aufgeloester CSS-Import: ${absolutePath}`);
    }

    const references = [...css.matchAll(urlPattern)];

    for (const match of references) {
        const reference = match[1].trim();

        if (/^(?:https?:|\/\/|data:)/i.test(reference)) {
            fail(`Externe oder eingebettete Ressource nicht erlaubt: ${reference}`);
        }

        if (reference.startsWith('#')) {
            continue;
        }

        const resource = resolve(dirname(absolutePath), reference);
        const fontRoot = resolve(sourceRoot, 'fonts');

        if (!insideDirectory(resource, fontRoot)) {
            fail(`Unerwarteter Ressourcenpfad: ${absolutePath}: ${reference}`);
        }

        if (!resource.endsWith('.woff2')) {
            fail(`Nicht unterstuetzte Ressource: ${resource}`);
        }

        if (!existsSync(resource)) {
            fail(`Schriftdatei fehlt: ${resource}`);
        }

        const destination = relative(fontRoot, resource).split(sep).join('/');
        const outputReference = `fonts/${destination}`;

        fontFiles.set(resource, outputReference);
        css = css.replace(match[0], `url("${outputReference}")`);
    }

    return [...importedModules, css].join('\n');
}

async function main() {
    for (const path of [stagingRoot, backupRoot]) {
        if (existsSync(path)) {
            fail(`Vorheriger Build-Zwischenstand vorhanden: ${path}`);
        }
    }

    if (existsSync(outputRoot)) {
        const info = await lstat(outputRoot);
        if (!info.isDirectory() || info.isSymbolicLink()) {
            fail('dist ist kein regulaeres Verzeichnis.');
        }
    }

    console.log('===== JELLYFIN NOVA – CSS BUILD =====');
    console.log();

    const css = await buildCss(entryFile);

    if (!css.includes('--nova-accent')) {
        fail('Nova-Akzentvariable fehlt im Build.');
    }

    if (!css.includes('@font-face')) {
        fail('Schriftdefinitionen fehlen im Build.');
    }

    const plugins = new Map();

    for (const name of optionalModules) {
        const path = resolve(sourceRoot, 'styles/plugins', name);

        if (!existsSync(path)) {
            fail(`Optionales CSS-Modul fehlt: ${name}`);
        }

        const text = await readFile(path, 'utf8');

        if (/@import\b/i.test(text)) {
            fail(`Unerwarteter Import im Zusatzmodul: ${name}`);
        }

        if (/url\s*\(/i.test(text)) {
            fail(`Ressourcenpfad im Zusatzmodul muss geprueft werden: ${name}`);
        }

        plugins.set(name, text);
    }

    for (const name of spotlightFiles) {
        const source = resolve(sourceRoot, 'spotlight', name);

        if (!existsSync(source)) {
            fail(`Spotlight-Datei fehlt: ${name}`);
        }
    }

    try {
        await mkdir(stagingRoot, { recursive: false });
        await writeFile(join(stagingRoot, 'nova.css'), css, 'utf8');

        for (const [source, destination] of fontFiles) {
            const target = resolve(stagingRoot, destination);

            await mkdir(dirname(target), { recursive: true });
            await copyFile(source, target);
        }

        const pluginRoot = join(stagingRoot, 'plugins');
        await mkdir(pluginRoot);

        for (const [name, content] of plugins) {
            await writeFile(join(pluginRoot, name), content, 'utf8');
        }

        const spotlightRoot = join(stagingRoot, 'spotlight');
        await mkdir(spotlightRoot);

        for (const name of spotlightFiles) {
            await copyFile(
                resolve(sourceRoot, 'spotlight', name),
                join(spotlightRoot, name)
            );
        }

        const assetsRoot = join(stagingRoot, 'assets');
        await mkdir(assetsRoot);

        for (const name of assetFiles) {
            await copyFile(
                resolve(sourceRoot, 'assets', name),
                join(assetsRoot, name)
            );
        }

        const loginRoot = join(stagingRoot, 'login');
        await mkdir(loginRoot);

        for (const name of loginFiles) {
            await copyFile(
                resolve(sourceRoot, 'login', name),
                join(loginRoot, name)
            );
        }
    } catch (error) {
        await rm(stagingRoot, { recursive: true, force: true });
        throw error;
    }

    let previousBuildMoved = false;

    try {
        if (existsSync(outputRoot)) {
            await rename(outputRoot, backupRoot);
            previousBuildMoved = true;
        }

        await rename(stagingRoot, outputRoot);
    } catch (error) {
        if (previousBuildMoved && !existsSync(outputRoot)) {
            await rename(backupRoot, outputRoot);
        }
        throw error;
    }

    if (previousBuildMoved) {
        await rm(backupRoot, { recursive: true, force: true });
    }

    console.log(`CSS-Module: ${importedFiles.size}`);
    console.log(`Schriftdateien: ${fontFiles.size}`);
    console.log(`Optionale Module: ${plugins.size}`);
    console.log(`Spotlight-Dateien: ${spotlightFiles.length}`);
    console.log();
    console.log('Erstellt: dist/nova.css');
    console.log('Erstellt: dist/fonts/');
    console.log('Erstellt: dist/plugins/');
    console.log('Erstellt: dist/spotlight/');
    console.log();
    console.log('Kein Deployment, kein Commit, kein Push.');
}

main().catch(error => {
    console.error(`BUILD-FEHLER: ${error.message}`);
    process.exitCode = 1;
});
