/* ============================================================
 * Created with ♥ by topa-LE
 * ============================================================ */

/*
 * Jellyfin Nova – Detail page enhancements
 *
 * Handles dynamic detail-page elements after Jellyfin navigation.
 * Initial feature: clean, individually clickable movie tags.
 */

(() => {
    "use strict";

    if (window.__novaDetailLoaderLoaded) {
        return;
    }

    window.__novaDetailLoaderLoaded = true;

    function updateTags() {
        const pages = document.querySelectorAll("#itemDetailPage");

        for (const page of pages) {
            const tags = page.querySelector(".itemTags");

            if (!tags || !tags.querySelector("a.button-link")) {
                continue;
            }

            for (const node of [...tags.childNodes]) {
                if (node.nodeType !== Node.TEXT_NODE) {
                    continue;
                }

                const value = node.textContent;

                if (/^\s*(Markierungen|Tags):\s*$/i.test(value)) {
                    const label = document.createElement("span");
                    label.className = "nova-tags-label";
                    label.textContent = "Tags:";
                    node.replaceWith(label);
                } else if (/^\s*,\s*$/.test(value)) {
                    node.remove();
                }
            }
        }
    }

    function updateExternalLinks() {
        const pages = document.querySelectorAll("#itemDetailPage");

        for (const page of pages) {
            const links = page.querySelector(".itemExternalLinks");

            if (!links) {
                continue;
            }

            for (const link of links.querySelectorAll("a.button-link")) {
                let provider = "";

                try {
                    const hostname = new URL(link.href).hostname.toLowerCase();

                    if (hostname === "imdb.com" || hostname.endsWith(".imdb.com")) {
                        provider = "imdb";
                    } else if (
                        hostname === "themoviedb.org" ||
                        hostname.endsWith(".themoviedb.org")
                    ) {
                        provider = "tmdb";
                    }
                } catch {
                    continue;
                }

                if (!provider) {
                    continue;
                }

                link.classList.add("nova-external-button");
                link.classList.add(`nova-external-${provider}`);

                if (!link.querySelector(".nova-external-button-label")) {
                    const label = document.createElement("span");
                    label.className = "nova-external-button-label";
                    label.textContent = provider === "imdb" ? "IMDb" : "TMDB";
                    link.replaceChildren(label);
                }
            }

            for (const node of [...links.childNodes]) {
                if (
                    node.nodeType === Node.TEXT_NODE &&
                    node.textContent.trim() === ","
                ) {
                    node.remove();
                }
            }
        }
    }

    function initialize() {
        updateTags();
        updateExternalLinks();

        const observer = new MutationObserver(() => {
            updateTags();
            updateExternalLinks();
        });

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
