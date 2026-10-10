// Light/dark toggle. The saved choice is applied in <head> before paint;
// without a saved choice the page follows the system setting.
(function () {
  "use strict";

  var root = document.documentElement;
  var button = document.getElementById("theme");
  if (!button) return;

  var systemDark = window.matchMedia("(prefers-color-scheme: dark)");

  function current() {
    var t = root.getAttribute("data-theme");
    if (t === "light" || t === "dark") return t;
    return systemDark.matches ? "dark" : "light";
  }

  function refreshLabel() {
    var next = current() === "dark" ? "light" : "dark";
    button.textContent = next + " mode";
    button.setAttribute("aria-label", "Switch to " + next + " mode");
  }

  button.addEventListener("click", function () {
    var next = current() === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("theme", next); } catch (e) {}
    refreshLabel();
  });

  systemDark.addEventListener("change", refreshLabel);
  refreshLabel();
})();
