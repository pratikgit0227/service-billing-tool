/* Runs first (before paint): apply saved theme, and refuse to run inside someone else's frame (clickjacking). */
(function () {
  try { var t = localStorage.getItem('theme'); if (t) document.documentElement.dataset.theme = t; } catch (e) {}
  if (window.top !== window.self) {
    document.documentElement.style.display = 'none';
    try { window.top.location = window.self.location; } catch (e) {}
  }
})();
