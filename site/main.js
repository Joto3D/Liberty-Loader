(function () {
  "use strict";

  var nodes = Array.prototype.slice.call(document.querySelectorAll("[data-i18n]"));
  var english = new Map(nodes.map(function (el) { return [el, el.textContent]; }));
  var titles = {
    en: document.title,
    de: "Liberty Loader – Helldivers 2 auf deinem Mac"
  };

  function storedLang() {
    try { return localStorage.getItem("lang"); } catch (e) { return null; }
  }

  function storeLang(lang) {
    try { localStorage.setItem("lang", lang); } catch (e) { /* private mode */ }
  }

  function apply(lang) {
    var de = window.I18N_DE || {};
    nodes.forEach(function (el) {
      var key = el.getAttribute("data-i18n");
      el.textContent = lang === "de" && de[key] ? de[key] : english.get(el);
    });
    document.documentElement.lang = lang;
    document.title = titles[lang];
    document.querySelectorAll(".lang button").forEach(function (btn) {
      btn.setAttribute("aria-pressed", String(btn.getAttribute("data-lang") === lang));
    });
  }

  var initial = storedLang() || ((navigator.language || "en").toLowerCase().indexOf("de") === 0 ? "de" : "en");
  apply(initial);

  document.querySelectorAll(".lang button").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var lang = btn.getAttribute("data-lang");
      storeLang(lang);
      apply(lang);
    });
  });

  // Show the newest released version next to the download button.
  fetch("https://api.github.com/repos/Joto3D/Liberty-Loader/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (release) {
      if (release && release.tag_name) {
        document.getElementById("version").textContent = release.tag_name;
      }
    })
    .catch(function () { /* keep the built-in version text */ });
})();
