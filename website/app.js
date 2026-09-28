// Noodle website — v5
// Keeps the nav quiet at the top of the page: the logo and Download button
// fade in only after the hero's own buttons have scrolled out of view.
(() => {
  const nav = document.querySelector(".nav");
  const heroCtas = document.querySelector(".intro .ctas");
  if (!nav || !heroCtas) return;
  if (!("IntersectionObserver" in window)) { nav.classList.add("show-cta"); return; }
  new IntersectionObserver(([entry]) => {
    const scrolledPast = !entry.isIntersecting && entry.boundingClientRect.top < 0;
    nav.classList.toggle("show-cta", scrolledPast);
  }, { rootMargin: "-48px 0px 0px 0px", threshold: 0 }).observe(heroCtas);
})();

// Writes the wordmark on as the apps' first screens do (NoodleBrand's Wordmark): a swirl
// rises from behind the screenshot, or the bottom edge of the window when that is nearer,
// curls once and runs up into the n, then the pen
// writes the word in one ease-in-out stroke. The swirl's end follows the pen in, so only the
// word is left.
(() => {
  const svg = document.querySelector(".wordmark svg");
  if (!svg || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const box = svg.getBoundingClientRect();
  const ctm = svg.getScreenCTM();
  // Coming back to the page scrolled down, the word is already written.
  if (!ctm || box.top < 0 || box.bottom > innerHeight) return;

  const pen = 128, radius = pen * 4, pull = radius * 0.5523;
  const entry = { x: 64, y: 906 };
  const curl = { x: entry.x, y: entry.y + radius * 2.4 };
  const centre = { x: curl.x - radius, y: curl.y };
  const shot = document.querySelector(".hero-shot");
  const floor = Math.min(innerHeight, shot ? shot.getBoundingClientRect().top : innerHeight);
  const start = { x: (innerWidth / 2 - ctm.e) / ctm.a, y: (floor - ctm.f) / ctm.d + pen };
  const rise = start.y - curl.y;
  const at = (...points) => points.map(([x, y]) => `${x},${y}`).join(" ");
  const swirl = document.createElementNS("http://www.w3.org/2000/svg", "path");
  swirl.setAttribute("d", `M${at([start.x, start.y])}` +
    ` C${at([start.x + radius * 3, start.y - rise * 0.45], [curl.x, curl.y + rise * 0.4], [curl.x, curl.y])}` +
    ` C${at([curl.x, curl.y - pull], [centre.x + pull, centre.y - radius], [centre.x, centre.y - radius])}` +
    ` C${at([centre.x - pull, centre.y - radius], [centre.x - radius, centre.y - pull], [centre.x - radius, centre.y])}` +
    ` C${at([centre.x - radius, centre.y + pull], [centre.x - pull, centre.y + radius], [centre.x, centre.y + radius])}` +
    ` C${at([centre.x + pull, centre.y + radius], [curl.x, centre.y + pull], [curl.x, curl.y])}` +
    ` L${at([entry.x, entry.y])}`);
  svg.prepend(swirl);
  svg.classList.add("writing");

  // Each stroke's place along the one pen line, which the head and tail trim.
  let total = 0;
  const strokes = [...svg.querySelectorAll("path")].map(path => {
    const length = path.getTotalLength(), from = total;
    total += length;
    return { path, from, length };
  });
  const swirlEnd = strokes[0].length;
  // How much of the swirl shows at once; shorter than the word, so its end is in before the pen finishes.
  const body = Math.min(swirlEnd * 0.6, total - swirlEnd);
  // The swirl fades in over its first stretch rather than appearing at full strength.
  const fadeIn = swirlEnd * 0.35;

  const draw = head => {
    const shown = Math.min(head / fadeIn, 1);
    swirl.style.opacity = `${shown * shown * (3 - 2 * shown)}`;
    const tail = Math.min(Math.max(0, head - body), swirlEnd);
    for (const { path, from, length } of strokes) {
      const a = Math.max(tail - from, 0), b = Math.min(head - from, length);
      path.style.visibility = b > a ? "" : "hidden";
      path.style.strokeDasharray = `${Math.max(b - a, 0)} ${length * 2 + 1}`;
      path.style.strokeDashoffset = `${-a}`;
    }
  };

  // SwiftUI's easeInOut, cubic-bezier(.42, 0, .58, 1).
  const ease = t => {
    const curve = (u, p1, p2) => 3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u;
    let lo = 0, hi = 1, u = t;
    for (let i = 0; i < 24; i++) {
      u = (lo + hi) / 2;
      if (curve(u, .42, .58) < t) lo = u; else hi = u;
    }
    return curve(u, 0, 1);
  };

  // The swirl is drawn faster than the word, and the time it saves comes off the 3.4 s.
  const rush = 1.6, paced = swirlEnd / rush + total - swirlEnd;
  const reach = d => d < swirlEnd / rush ? d * rush : d - swirlEnd / rush + swirlEnd;
  const delay = 550, duration = 3400 * paced / total;
  let began;
  draw(0);
  const frame = now => {
    began ??= now;
    const t = Math.min(Math.max((now - began - delay) / duration, 0), 1);
    if (t < 1) { draw(reach(ease(t) * paced)); requestAnimationFrame(frame); return; }
    swirl.remove();
    svg.classList.remove("writing");
    for (const { path } of strokes) path.removeAttribute("style");
  };
  requestAnimationFrame(frame);
})();
