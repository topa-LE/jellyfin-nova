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

    function initialize() {
        updateTags();

        const observer = new MutationObserver(updateTags);

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
