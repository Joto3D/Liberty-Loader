(function () {
  "use strict";
  var root = document.getElementById("releases");
  var de = function () { return document.documentElement.lang === "de"; };

  function escapeHTML(s) {
    return s.replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Tiny, safe Markdown subset: headings, bullet lists, bold, links. Input is escaped first.
  function inline(text) {
    return escapeHTML(text)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
      .replace(/(^|\s)(https?:\/\/[^\s<]+)/g, '$1<a href="$2" target="_blank" rel="noopener">$2</a>');
  }

  function markdown(md) {
    var out = [], inList = false;
    (md || "").split(/\r?\n/).forEach(function (line) {
      var item = line.match(/^\s*[-*]\s+(.*)$/);
      if (item) {
        if (!inList) { out.push("<ul>"); inList = true; }
        out.push("<li>" + inline(item[1]) + "</li>");
        return;
      }
      if (inList) { out.push("</ul>"); inList = false; }
      var heading = line.match(/^#{1,6}\s+(.*)$/);
      if (heading) out.push("<h3>" + inline(heading[1]) + "</h3>");
      else if (line.trim()) out.push("<p>" + inline(line) + "</p>");
    });
    if (inList) out.push("</ul>");
    return out.join("");
  }

  function render(releases) {
    if (!releases.length) {
      root.innerHTML = '<p class="muted">' + (de() ? "Noch keine Versionen veröffentlicht." : "No releases yet.") + "</p>";
      return;
    }
    root.innerHTML = releases.map(function (r, i) {
      var date = new Date(r.published_at || r.created_at);
      var when = date.toLocaleDateString(de() ? "de-DE" : "en-US", { year: "numeric", month: "long", day: "numeric" });
      return '<article class="release' + (i === 0 ? " latest" : "") + '">' +
        '<header><span class="tag">' + escapeHTML(r.tag_name || "") + "</span>" +
        (i === 0 ? '<span class="badge">' + (de() ? "Neueste" : "Latest") + "</span>" : "") +
        '<time datetime="' + date.toISOString() + '">' + when + "</time></header>" +
        "<h2>" + escapeHTML(r.name || r.tag_name || "") + "</h2>" +
        '<div class="notes">' + markdown(r.body) + "</div>" +
        '<a class="btn btn-ghost btn-sm" href="' + escapeHTML(r.html_url) + '" target="_blank" rel="noopener">' +
        (de() ? "Auf GitHub ansehen" : "View on GitHub") + "</a></article>";
    }).join("");
  }

  var cache = null;
  fetch("https://api.github.com/repos/Joto3D/Liberty-Loader/releases?per_page=20", { headers: { Accept: "application/vnd.github+json" } })
    .then(function (res) { if (!res.ok) throw new Error(res.status); return res.json(); })
    .then(function (list) {
      cache = list.filter(function (r) { return !r.draft; });
      render(cache);
    })
    .catch(function () {
      root.innerHTML = '<p class="muted">' + (de()
        ? 'Versionen konnten nicht geladen werden. <a href="https://github.com/Joto3D/Liberty-Loader/releases">Auf GitHub ansehen</a>.'
        : 'Couldn’t load releases. <a href="https://github.com/Joto3D/Liberty-Loader/releases">See them on GitHub</a>.') + "</p>";
    });

  // Re-render dates and labels when the language changes.
  document.addEventListener("langchange", function () { if (cache) render(cache); });
})();
