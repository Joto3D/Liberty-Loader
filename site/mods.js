(function () {
  "use strict";
  var grid = document.getElementById("mods");
  var empty = document.getElementById("mods-empty");
  var updated = document.getElementById("mods-updated");
  var data = null;
  var tab = "trending";

  function escapeHTML(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function de() { return document.documentElement.lang === "de"; }

  function render() {
    var list = (data && data[tab]) || [];
    empty.hidden = list.length > 0;
    grid.innerHTML = list.map(function (m) {
      var id = Number(m.mod_id);
      var page = "https://www.nexusmods.com/helldivers2/mods/" + id;
      var picture = /^https:\/\//.test(m.picture_url || "") ? m.picture_url : "";
      return '<article class="mod-card">' +
        '<a class="thumb" href="' + page + '" target="_blank" rel="noopener">' +
        (picture ? '<img loading="lazy" alt="" src="' + escapeHTML(picture) + '">' : '<span class="ph">▣</span>') + "</a>" +
        '<div class="mod-body"><h3>' + escapeHTML(m.name) + "</h3>" +
        '<p class="mod-meta">' + escapeHTML(m.author || "") + (m.endorsement_count != null ? " · 👍 " + Number(m.endorsement_count) : "") + "</p>" +
        "<p>" + escapeHTML(m.summary || "") + "</p>" +
        '<a class="btn btn-ghost btn-sm" href="' + page + '?tab=files" target="_blank" rel="noopener">' +
        (de() ? "Herunterladen" : "Download") + "</a></div></article>";
    }).join("");
    if (data && data.updated) {
      updated.textContent = new Date(data.updated).toLocaleDateString(de() ? "de-DE" : "en-US", { year: "numeric", month: "short", day: "numeric" });
    }
  }

  document.querySelectorAll(".tabs button").forEach(function (btn) {
    btn.addEventListener("click", function () {
      tab = btn.getAttribute("data-tab");
      document.querySelectorAll(".tabs button").forEach(function (b) { b.setAttribute("aria-selected", String(b === btn)); });
      render();
    });
  });

  fetch("data/mods.json", { cache: "no-cache" })
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (json) { data = json; render(); })
    .catch(function () { render(); });

  document.addEventListener("langchange", render);
})();
