"use strict";

/*
 * Jellyfin Nova – Login Loader
 * Created by topa-LE
 *
 * Adds the locally bundled Jellyfin logo to the login page.
 * Places password recovery inside the visual login card, outside the form.
 * Supports Jellyfin's single-page navigation.
 */

(function () {
    var LOGO_ID = "nova-login-final-logo";
    var LOGIN_SELECTOR = "#loginPage";
    var FORM_SELECTOR = ".manualLoginForm";
    var RESET_SELECTOR = "#forgotPasswordPage";
    var RESET_FORM_SELECTOR = ".forgotPasswordForm";
    var RESET_LOGO_ID = "nova-reset-logo";
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

    function installLoginLogo(page, form) {
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

    function installForgotButton(page, form) {
        var forgot = page.querySelector("button.btnForgotPassword");
        var login = form.querySelector("button.button-submit");

        if (!forgot || !login) {
            return;
        }

        if (
            form.parentElement.id === "nova-login-card" &&
            forgot.parentElement === form.parentElement &&
            forgot.classList.contains("nova-forgot-inside-login")
        ) {
            return;
        }

        forgot.className = login.className;
        forgot.classList.add("btnForgotPassword");
        forgot.classList.add("nova-forgot-inside-login");
        forgot.classList.remove("button-submit");

        forgot.removeAttribute("style");
        forgot.type = "button";

        var card = form.parentElement;

        if (card.id !== "nova-login-card") {
            card = document.createElement("div");
            card.id = "nova-login-card";
            form.parentNode.insertBefore(card, form);
            card.appendChild(form);
        }

        card.appendChild(forgot);
    }

    function installResetPage() {
        var page = document.querySelector(RESET_SELECTOR);

        if (!page) {
            return;
        }

        var form = page.querySelector(RESET_FORM_SELECTOR);

        if (!form || !form.parentNode) {
            return;
        }

        var logo = document.getElementById(RESET_LOGO_ID);

        if (!logo) {
            logo = document.createElement("a");
            logo.id = RESET_LOGO_ID;
            logo.href = "#/";
            logo.setAttribute("aria-label", "Jellyfin Startseite");

            var image = document.createElement("img");
            image.src = logoUrl;
            image.alt = "Jellyfin";

            logo.appendChild(image);
        }

        if (logo.parentNode !== form.parentNode ||
            logo.nextElementSibling !== form) {
            form.parentNode.insertBefore(logo, form);
        }

        var submit = page.querySelector("#btnSubmit");
        var cancel = page.querySelector("#btnCancel");

        if (submit && cancel &&
            submit.nextElementSibling !== cancel) {
            submit.insertAdjacentElement("afterend", cancel);
        }
    }

    function installLogin() {
        var page = document.querySelector(LOGIN_SELECTOR);

        if (!page) {
            return;
        }

        var form = page.querySelector(FORM_SELECTOR);

        if (!form || !form.parentNode) {
            return;
        }

        installLoginLogo(page, form);
        installForgotButton(page, form);
    }

    function boot() {
        installLogin();
        installResetPage();

        if (typeof MutationObserver === "function") {
            var observer = new MutationObserver(function () {
                installLogin();
                installResetPage();
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
