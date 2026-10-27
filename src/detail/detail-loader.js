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

    function updateSimilarHeading() {
        const headings = document.querySelectorAll(
            "#itemDetailPage #similarCollapsible > h2.sectionTitle"
        );

        for (const heading of headings) {
            if (heading.textContent.trim() === "Ähnliches") {
                heading.textContent = "Ähnliche Movies";
            }
        }
    }

    const originalInfoPositions = new WeakMap();

    function updateLogoAlignment() {
        const desktop = window.innerWidth >= 1100;

        for (const page of document.querySelectorAll("#itemDetailPage")) {
            const logo = page.querySelector(".detailLogo");

            if (!logo) {
                continue;
            }

            if (!desktop) {
                logo.style.removeProperty("margin-left");
                logo.style.removeProperty("transform");
                continue;
            }

            const title = page.querySelector(".detailRibbon .itemName");

            if (!title) {
                continue;
            }

            // Existing horizontal layout stays unchanged.
            // Only the visible logo position is corrected.
            const logoX = logo.getBoundingClientRect().left;
            const titleX = title.getBoundingClientRect().left;

            const currentTransform = logo.style.getPropertyValue("transform");
            const match = currentTransform.match(
                /^translateX\\((-?[\\d.]+)px\\)$/
            );
            const previousOffset = match ? Number(match[1]) : 0;

            const correction = titleX - logoX;
            const nextOffset = previousOffset + correction;

            if (Math.abs(correction) > 0.5) {
                logo.style.setProperty(
                    "transform",
                    `translateX(${nextOffset}px)`,
                    "important"
                );
            }
        }
    }

    function updateFilmDataWidth() {
        for (const page of document.querySelectorAll("#itemDetailPage")) {
            const wrapper = page.querySelector(".nova-detail-info");
            const film = wrapper?.querySelector(".itemDetailsGroup");
            const media = wrapper?.querySelector("form.trackSelections");

            if (!film || !media) {
                continue;
            }

            if (window.innerWidth < 1100) {
                film.style.removeProperty("max-width");
                continue;
            }

            const mediaWidth = media.getBoundingClientRect().width;
            const gap = parseFloat(getComputedStyle(wrapper).columnGap) || 50;
            const right = parseFloat(getComputedStyle(wrapper).right) || 0;

            const available = Math.max(
                0,
                window.innerWidth - right - mediaWidth - gap - 40
            );

            const width = Math.min(480, available);
            const value = `${width}px`;

            if (film.style.getPropertyValue("max-width") !== value) {
                film.style.setProperty("max-width", value, "important");
            }
        }
    }

    function updateInfoBoxes() {
        const desktop = window.innerWidth >= 1100;

        for (const page of document.querySelectorAll("#itemDetailPage")) {
            const filmData = page.querySelector(".itemDetailsGroup");
            const mediaData = page.querySelector("form.trackSelections");

            if (!filmData || !mediaData) {
                continue;
            }

            let container = page.querySelector(".nova-detail-info");

            if (!desktop) {
                for (const element of [filmData, mediaData]) {
                    const original = originalInfoPositions.get(element);

                    if (original?.parent?.isConnected &&
                        element.parentElement !== original.parent) {
                        original.parent.insertBefore(
                            element,
                            original.next?.parentElement === original.parent
                                ? original.next
                                : null
                        );
                    }
                }

                if (container && !container.children.length) {
                    container.remove();
                }

                continue;
            }

            if (!container) {
                container = document.createElement("div");
                container.className = "nova-detail-info";
                page.appendChild(container);
            }

            for (const element of [filmData, mediaData]) {
                if (!originalInfoPositions.has(element)) {
                    originalInfoPositions.set(element, {
                        parent: element.parentElement,
                        next: element.nextSibling
                    });
                }

                if (element.parentElement !== container) {
                    container.appendChild(element);
                }
            }
        }
    }

    function initialize() {
        updateTags();
        updateExternalLinks();
        updateSimilarHeading();
        updateInfoBoxes();
        updateFilmDataWidth();
        updateLogoAlignment();

        const observer = new MutationObserver(() => {
            updateTags();
            updateExternalLinks();
            updateSimilarHeading();
            updateInfoBoxes();
            updateFilmDataWidth();
            updateLogoAlignment();
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true
        });

        window.addEventListener("resize", () => {
            updateInfoBoxes();
            updateFilmDataWidth();
            updateLogoAlignment();
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
