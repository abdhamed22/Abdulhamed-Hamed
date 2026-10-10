(function () {
  "use strict";

  var root = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- Theme toggle ---------- */
  var themeBtn = document.getElementById("theme-toggle");
  var systemDark = window.matchMedia("(prefers-color-scheme: dark)");

  function currentTheme() {
    var t = root.getAttribute("data-theme");
    if (t === "light" || t === "dark") return t;
    return systemDark.matches ? "dark" : "light";
  }

  function syncThemeLabel() {
    var next = currentTheme() === "dark" ? "light" : "dark";
    themeBtn.setAttribute("aria-label", "Switch to " + next + " mode");
  }

  if (themeBtn) {
    syncThemeLabel();
    themeBtn.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("theme", next); } catch (e) {}
      syncThemeLabel();
    });
    systemDark.addEventListener("change", syncThemeLabel);
  }

  /* ---------- Mobile menu ---------- */
  var menuBtn = document.getElementById("menu-toggle");
  var nav = document.getElementById("site-nav");

  function setMenu(open) {
    nav.classList.toggle("is-open", open);
    menuBtn.setAttribute("aria-expanded", String(open));
    menuBtn.setAttribute("aria-label", open ? "Close menu" : "Open menu");
  }

  if (menuBtn && nav) {
    menuBtn.addEventListener("click", function () {
      setMenu(!nav.classList.contains("is-open"));
    });
    nav.addEventListener("click", function (e) {
      if (e.target.closest("a")) setMenu(false);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("is-open")) {
        setMenu(false);
        menuBtn.focus();
      }
    });
  }

  /* ---------- Active section in nav ---------- */
  var navLinks = nav ? Array.prototype.slice.call(nav.querySelectorAll('a[href^="#"]')) : [];
  if ("IntersectionObserver" in window && navLinks.length) {
    var byId = {};
    navLinks.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });
    var sectionObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        navLinks.forEach(function (a) { a.classList.remove("is-active"); });
        var link = byId[entry.target.id];
        if (link) link.classList.add("is-active");
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    Object.keys(byId).forEach(function (id) {
      var el = document.getElementById(id);
      if (el) sectionObserver.observe(el);
    });
  }

  /* ---------- Reveal on scroll ---------- */
  var revealEls = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealEls.forEach(function (el) { el.classList.add("is-visible"); });
  } else {
    var revealObserver = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          obs.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    revealEls.forEach(function (el) { revealObserver.observe(el); });
  }

  /* ---------- Terminal typing ---------- */
  var term = document.getElementById("terminal");
  if (term && !reduceMotion) {
    var lines = Array.prototype.slice.call(term.querySelectorAll(".t-line"));
    // Newlines between the spans are text nodes; hide them with their line.
    var gaps = Array.prototype.filter.call(term.childNodes, function (n) { return n.nodeType === 3; });
    gaps.forEach(function (n) { n.textContent = ""; });

    var steps = lines.map(function (line) {
      var cmd = line.querySelector(".t-cmd");
      var text = cmd ? cmd.textContent : "";
      if (cmd) cmd.textContent = "";
      line.classList.add("is-hidden");
      return { line: line, cmd: cmd, text: text };
    });

    var i = 0;
    function show(step) {
      step.line.classList.remove("is-hidden");
      if (i > 0) step.line.insertAdjacentText("beforebegin", "\n");
    }
    function next() {
      if (i >= steps.length) return;
      var step = steps[i];
      show(step);
      i++;
      if (step.cmd && step.text) {
        var c = 0;
        (function type() {
          step.cmd.textContent = step.text.slice(0, ++c);
          if (c < step.text.length) setTimeout(type, 55 + Math.random() * 45);
          else setTimeout(next, 380);
        })();
      } else {
        setTimeout(next, step.line.getAttribute("data-kind") === "out" ? 140 : 300);
      }
    }
    setTimeout(next, 450);
  }

  /* ---------- Footer year ---------- */
  var year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());
})();
