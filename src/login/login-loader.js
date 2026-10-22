"use strict";

/*
 * Jellyfin Nova – Login Loader
 * Created by topa-LE
 *
 * Adds the locally bundled Jellyfin logo to the login page.
 * Supports Jellyfin's single-page navigation.
 */

(function () {
    var LOGO_ID = "nova-login-final-logo";
    var LOGIN_SELECTOR = "#loginPage";
    var FORM_SELECTOR = ".manualLoginForm";
    var LOGO_PATH = "assets/jellyfin-logo.png";

    var logoUrl = "nova/" + LOGO_PATH;

    try {
        var script = document.currentScript;

        if (script && script.src) {
            logoUrl = new URL("../" + LOGO_PATH, script.src).href;
        }
    } catch (error) {
        console.warn("[nova-login] Could not resolve logo URL.", error);
    }

    function installLoginLogo() {
        var page = document.querySelector(LOGIN_SELECTOR);

        if (!page) {
            return;
        }

        var form = page.querySelector(FORM_SELECTOR);

        if (!form || !form.parentNode) {
            return;
        }

        var existing = document.getElementById(LOGO_ID);

        if (existing) {
            if (existing.isConnected && existing.parentNode === form.parentNode) {
                return;
            }

            existing.remove();
        }

        var link = document.createElement("a");
        link.id = LOGO_ID;
        link.href = "#/";
        link.setAttribute("aria-label", "Jellyfin Startseite");

        var image = document.createElement("img");
        image.src = logoUrl;
        image.alt = "Jellyfin";

        link.appendChild(image);
        form.parentNode.insertBefore(link, form);
    }

    function boot() {
        installLoginLogo();

        if (typeof MutationObserver === "function") {
            var observer = new MutationObserver(function () {
                var page = document.querySelector(LOGIN_SELECTOR);

                if (!page || !page.querySelector(FORM_SELECTOR)) {
                    return;
                }

                var logo = document.getElementById(LOGO_ID);

                if (!logo || !logo.isConnected) {
                    installLoginLogo();
                }
            });

            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", boot, { once: true });
    } else {
        boot();
    }
})();
