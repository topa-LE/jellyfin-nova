/* ============================================================
 * Created with ♥ by topa-LE
 * ============================================================ */

/*
 * Jellyfin Nova – Theme and font switchers
 *
 * Adds two controls to the right-hand Jellyfin header.
 * Preferences are stored locally in the browser.
 */
(() => {
    "use strict";

    if (window.__novaSwitcherLoaded) {
        return;
    }

    window.__novaSwitcherLoaded = true;

    const themes = [
        ["dark", "Nova Dark"],
        ["gray", "Nova Gray"],
        ["blue", "Nova Blue"]
    ];

    const fonts = [
        "Clear Sans",
        "Cuprum",
        "Dosis",
        "Inter",
        "Maven Pro",
        "Play",
        "Roboto Condensed",
        "Saira Condensed",
        "Titillium Web",
        "Ubuntu Condensed"
    ];

    const keys = {
        theme: "jellyfin-nova-theme",
        font: "jellyfin-nova-font"
    };

    const root = document.documentElement;
    const defaultFont = "Titillium Web";

    function readPreference(key) {
        try {
            return localStorage.getItem(key);
        } catch {
            return null;
        }
    }

    function savePreference(key, value) {
        try {
            localStorage.setItem(key, value);
        } catch {
            // The switcher remains usable without local storage.
        }
    }

    function applyTheme(value) {
        if (!themes.some(([name]) => name === value)) {
            return;
        }

        root.setAttribute("data-nova-theme", value);
        savePreference(keys.theme, value);
    }

    function applyFont(value) {
        if (!fonts.includes(value)) {
            return;
        }

        root.style.setProperty(
            "--nova-font-family",
            `"${value}", system-ui, sans-serif`
        );

        savePreference(keys.font, value);
    }

    const storedTheme = readPreference(keys.theme);
    const storedFont = readPreference(keys.font);

    if (themes.some(([name]) => name === storedTheme)) {
        applyTheme(storedTheme);
    }

    if (fonts.includes(storedFont)) {
        applyFont(storedFont);
    }

    function createButton(type, label) {
        const button = document.createElement("button");

        button.type = "button";
        button.className = `nova-switcher nova-${type}-switcher`;
        button.setAttribute("aria-label", label);
        button.setAttribute("aria-haspopup", "menu");
        button.setAttribute("aria-expanded", "false");

        if (type === "theme") {
            button.innerHTML = `
                <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M12 3a9 9 0 1 0 0 18h1.5a2 2 0 0 0 1.5-3.3 1.8 1.8 0 0 1 1.3-3h1.2A3.5 3.5 0 0 0 21 11.2 9 9 0 0 0 12 3Z"/>
                    <circle cx="7.5" cy="11" r="1" fill="currentColor" stroke="none"/>
                    <circle cx="10" cy="7.5" r="1" fill="currentColor" stroke="none"/>
                    <circle cx="15" cy="7.5" r="1" fill="currentColor" stroke="none"/>
                    <circle cx="17" cy="11" r="1" fill="currentColor" stroke="none"/>
                </svg>
            `;
        } else {
            const text = document.createElement("span");
            text.textContent = "Aa";
            button.append(text);
        }

        return button;
    }

    function createMenu(type, entries, getCurrent, apply) {
        const menu = document.createElement("div");

        menu.id = `nova-${type}-menu`;
        menu.className = "nova-switcher-menu";
        menu.setAttribute("role", "menu");
        menu.hidden = true;

        for (const [value, label] of entries) {
            const option = document.createElement("button");

            option.type = "button";
            option.textContent = label;
            option.dataset.value = value;
            option.setAttribute("role", "menuitemradio");

            option.addEventListener("click", () => {
                apply(value);
                closeMenus();
            });

            menu.append(option);
        }

        document.body.append(menu);

        function updateSelection() {
            const current = getCurrent();

            for (const option of menu.querySelectorAll("button")) {
                option.setAttribute(
                    "aria-checked",
                    String(option.dataset.value === current)
                );
            }
        }

        return { menu, updateSelection };
    }

    let themeButton;
    let fontButton;
    let themeMenu;
    let fontMenu;

    function closeMenus() {
        for (const menu of [themeMenu, fontMenu]) {
            if (menu) {
                menu.menu.hidden = true;
            }
        }

        for (const button of [themeButton, fontButton]) {
            if (button) {
                button.setAttribute("aria-expanded", "false");
            }
        }
    }

    function toggleMenu(button, entry) {
        const opening = entry.menu.hidden;

        closeMenus();

        if (!opening) {
            return;
        }

        entry.updateSelection();

        const rect = button.getBoundingClientRect();
        const menuWidth = entry.menu.id === "nova-font-menu" ? 165 : 120;

        entry.menu.style.top = `${rect.bottom + 8}px`;
        entry.menu.style.left =
            `${Math.max(8, Math.min(rect.left, window.innerWidth - menuWidth - 8))}px`;

        entry.menu.hidden = false;
        button.setAttribute("aria-expanded", "true");
    }

    function ensureButtons() {
        const syncButton = document.querySelector(
            'header.MuiAppBar-root button[aria-controls="app-sync-play-menu"]'
        );

        if (!syncButton || !syncButton.parentElement) {
            return;
        }

        const container = syncButton.parentElement;

        if (themeButton.parentElement !== container ||
            fontButton.parentElement !== container ||
            themeButton.nextElementSibling !== fontButton ||
            fontButton.nextElementSibling !== syncButton) {
            container.insertBefore(themeButton, syncButton);
            container.insertBefore(fontButton, syncButton);
        }
    }

    function initialize() {
        themeButton = createButton("theme", "Nova Theme auswählen");
        fontButton = createButton("font", "Nova Schriftart auswählen");

        themeMenu = createMenu(
            "theme",
            themes,
            () => root.getAttribute("data-nova-theme") || "dark",
            applyTheme
        );

        fontMenu = createMenu(
            "font",
            fonts.map(name => [name, name]),
            () => readPreference(keys.font) || defaultFont,
            applyFont
        );

        themeButton.setAttribute("aria-controls", themeMenu.menu.id);
        fontButton.setAttribute("aria-controls", fontMenu.menu.id);

        themeButton.addEventListener("click", event => {
            event.stopPropagation();
            toggleMenu(themeButton, themeMenu);
        });

        fontButton.addEventListener("click", event => {
            event.stopPropagation();
            toggleMenu(fontButton, fontMenu);
        });

        document.addEventListener("click", event => {
            if (
                !themeMenu.menu.contains(event.target) &&
                !fontMenu.menu.contains(event.target)
            ) {
                closeMenus();
            }
        });

        document.addEventListener("keydown", event => {
            if (event.key === "Escape") {
                closeMenus();
            }
        });

        window.addEventListener("resize", closeMenus);
        window.addEventListener("scroll", closeMenus, true);

        ensureButtons();

        const observer = new MutationObserver(ensureButtons);

        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            { once: true }
        );
    } else {
        initialize();
    }
})();
