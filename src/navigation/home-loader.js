/* ============================================================
 * Created with ♥ by topa-LE
 * ============================================================ */

/*
 * Jellyfin Nova – Home navigation label
 *
 * Replaces the visible server name in the Home navigation
 * with "Home". Does not modify Jellyfin server settings.
 */
(() => {
    "use strict";

    if (window.__novaHomeNavigationLoaded) {
        return;
    }

    window.__novaHomeNavigationLoaded = true;

    const homeSelector =
        'header.MuiAppBar-root a.MuiButton-root[href="#/"]';

    function updateHomeLabel() {
        const home = document.querySelector(homeSelector);

        if (!home) {
            return;
        }

        const walker = document.createTreeWalker(
            home,
            NodeFilter.SHOW_TEXT
        );

        let node;

        while ((node = walker.nextNode())) {
            const value = node.textContent.trim();

            if (!value || value === "Home") {
                continue;
            }

            node.textContent = node.textContent.replace(
                value,
                "Home"
            );

            break;
        }
    }

    function initialize() {
        updateHomeLabel();

        const observer = new MutationObserver(() => {
            updateHomeLabel();
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
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
