
class BessieLanding {
  CH = ' .:!;1S$&8@0'.split('');
  BAY = [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];
  // The twelve sine terms, verbatim from the live Cowprint field.
  T = [[1,0,.58,0.4,.11],[0,1,.52,1.9,-.09],[1,1,.44,3.1,.14],[2,1,.34,0.7,-.12],
       [1,2,.30,4.4,.10],[2,2,.24,2.2,-.16],[3,1,.19,5.0,.13],[1,3,.17,1.1,-.11],
       [3,2,.13,3.6,.18],[2,3,.12,0.2,-.15],[3,3,.09,4.9,.20],[4,1,.08,2.7,-.19]];
  // Period fixed in PIXELS, not columns — otherwise the field smears at window width.
  PER = 820; CYC = 2.1;
  DUR = 4700;

  cvRef = { current: document.getElementById('cowprint') };
  rootRef = { current: document.getElementById('site-root') };
  probeRef = { current: document.getElementById('cow-probe') };
  navRef = { current: document.getElementById('site-nav') };

  constructor(props){ this.props=props; }
  onCopy(e){
        const row = e.currentTarget;
        const src = row.querySelector('[data-copy]');
        if (!src) return;
        const text = src.dataset.copy || src.textContent || '';
        const label = row.querySelector('[data-copylabel]');
        const ico = row.querySelector('[data-copybtn] i');
        const say = (msg, glyph) => {
          if (label) label.textContent = msg;
          if (ico) ico.className = 'ph-thin ph-' + glyph;
          clearTimeout(row._copyT);
          row._copyT = setTimeout(() => {
            if (label) label.textContent = 'Copy';
            if (ico) ico.className = 'ph-thin ph-copy';
          }, 1800);
        };
        // writeText rejects on an unfocused document even in a secure context, so
        // every failure path lands here rather than in an unreachable else branch.
        const viaSelection = () => {
          const t = document.createElement('textarea');
          t.value = text;
          t.setAttribute('readonly', '');
          t.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;';
          document.body.appendChild(t);
          let done = false;
          try {
            t.focus(); t.select(); t.setSelectionRange(0, text.length);
            done = document.execCommand('copy');
          } catch(err){ done = false; }
          document.body.removeChild(t);
          if (done){ say('Copied', 'check'); return; }
          // Last resort: leave the command genuinely selected so ⌘C works, and
          // say so instead of reporting a copy that did not happen.
          try {
            const rng = document.createRange();
            rng.selectNodeContents(src);
            const sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(rng);
          } catch(err){}
          say('Press ⌘C', 'keyboard');
        };
        let p = null;
        if (navigator.clipboard && navigator.clipboard.writeText){
          try { p = navigator.clipboard.writeText(text); } catch(err){ p = null; }
        }
        if (p && p.then) p.then(() => say('Copied', 'check'), viaSelection);
        else viaSelection();
      
  }

  ambient(){ const v = +(this.props.heroInk ?? 0.13); return v >= 0 ? v : 0.13; }
  cowPx(){ const v = +(this.props.cowPx ?? 320); return v > 40 ? v : 320; }
  moves(){ return this.props.parallax !== false && !this.reduce && !this.loopDead; }


  // Labelled links must not lie: with no repoUrl set they fall back to the install
  // section and say why, rather than looking wired while scrolling somewhere else.
  applyLinks(){
    const r = this.rootRef.current;
    if (!r) return;
    const repo = (this.props.repoUrl || '').trim();
    for (const el of r.querySelectorAll('[data-link="repo"]')){
      if (repo){
        el.setAttribute('href', repo);
        el.setAttribute('target', '_blank');
        el.setAttribute('rel', 'noopener');
        el.removeAttribute('title');
      } else {
        el.setAttribute('href', '#get');
        el.setAttribute('title', 'Repo URL not set — set repoUrl in Tweaks');
      }
    }
    const download = (this.props.downloadUrl || '').trim();
    for (const el of r.querySelectorAll('[data-link="download"]')) { el.href = download || '#get'; if(download){el.target='_blank';el.rel='noopener'}else{el.removeAttribute('target');el.removeAttribute('rel')} }
    const cmd = (this.props.installCmd || '').trim();
    if (cmd){
      for (const el of r.querySelectorAll('[data-install]')){
        el.textContent = cmd;
        el.dataset.copy = cmd;
      }
    }
  }

  mkGeom(cv){
    const ctx = cv.getContext('2d');
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(1, window.innerWidth), h = Math.max(1, window.innerHeight);
    cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const font = '11px ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
    ctx.font = font; ctx.textBaseline = 'top';
    const cw = ctx.measureText('M').width || 6.6;
    const chh = Math.max(2, Math.round(cw * 1.34));
    const n = this.T.length;
    const cols = Math.ceil(w / cw) + 1, rows = Math.ceil(h / chh) + 1;
    return { ctx, font, w, h, cw, chh, cols, rows,
      norm: this.T.reduce((s, q) => s + q[2], 0),
      sA: new Float32Array(n * cols), cA: new Float32Array(n * cols),
      sB: new Float32Array(n), cB: new Float32Array(n) };
  }

  async loadGlyph(){
    const p = this.probeRef.current;
    if (!p) return;
    let ch = '';
    try { ch = (getComputedStyle(p, '::before').content || '').replace(/["']/g, ''); } catch(e){}
    if (!ch || ch === 'none' || ch === 'normal') return;
    const fam = getComputedStyle(p).fontFamily || '"Phosphor-Fill"';
    try { if (document.fonts){ await document.fonts.load('112px ' + fam, ch); await document.fonts.ready; } } catch(e){}
    if (this.dead) return;
    const N = 128, F = 112;
    const c = document.createElement('canvas'); c.width = N; c.height = N;
    const x = c.getContext('2d');
    x.font = F + 'px ' + fam; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillStyle = '#fff';
    x.fillText(ch, N / 2, N / 2);
    let im;
    try { im = x.getImageData(0, 0, N, N).data; } catch(e){ return; }
    const a = new Float32Array(N * N);
    let mx = 0, x0 = N, x1 = -1, y0 = N, y1 = -1;
    for (let i = 0; i < N * N; i++){
      const v = im[i * 4 + 3] / 255;
      a[i] = v;
      if (v > mx) mx = v;
      if (v > 0.5){
        const px = i % N, py = (i / N) | 0;
        if (px < x0) x0 = px; if (px > x1) x1 = px;
        if (py < y0) y0 = py; if (py > y1) y1 = py;
      }
    }
    if (mx < 0.05 || x1 < x0) return;
    this.glyph = { n: N, f: F, a, gcx: (x0 + x1 + 1) / 2, gcy: (y0 + y1 + 1) / 2 };
  }

  // The cold open, once, over the hero. After it lands the same field carries the
  // whole page as ambient print — the sequence does not end, it settles.
  env(t, W, H, ctr){
    const cl = (v, a, b) => v < a ? a : v > b ? b : v;
    const nr = (a, b) => cl((t - a) / (b - a), 0, 1);
    const ei = v => v * v * v;
    const eo4 = v => 1 - Math.pow(1 - v, 4);
    const eio = v => v < .5 ? 4 * v * v * v : 1 - Math.pow(-2 * v + 2, 3) / 2;
    const has = !!this.glyph;
    const cx = ctr.x, cy = ctr.y;
    const big = this.cowPx();
    const markPx = big - (big - 82) * ei(nr(1000, 1440));
    const half = markPx * 0.60;
    const blast = eo4(nr(1560, 2150));
    const maxR = Math.hypot(Math.max(cx, W - cx), Math.max(cy, H - cy)) * 1.08;
    const amb = this.ambient();
    return {
      cx, cy,
      S: this.CYC / this.PER,
      k: 0.30 + 0.70 * eo4(nr(1560, 2500)) + 0.85 * eio(nr(2900, 3340)) - 0.85 * eio(nr(3600, 4500)),
      alpha: cl(0.86 * nr(40, 200) - 0.36 * eio(nr(2150, 2900)) - 0.44 * eio(nr(2900, 3340)) + (amb + 0.02) * eio(nr(3600, 4500)), 0, 1),
      steep: 4.4 + 1.3 * Math.sin(Math.PI * nr(1560, 2400)),
      cow: has ? 1 - eio(nr(1560, 1960)) : 0,
      markPx, half,
      scanY: has && t < 580 ? cy - half + nr(100, 560) * (2 * half + 3) : 1e9,
      flash: 0.42 * Math.sin(Math.PI * nr(1400, 1600)),
      front: has && t >= 1560 ? Math.max(half * 1.04, blast * maxR) : 1e9,
      soft: 14 + 46 * (1 - blast),
      ringW: 30 + 66 * (1 - blast),
      ringAmp: 0.60 * Math.pow(1 - blast, 0.7),
      glyphOp: nr(3400, 3720),
      letter: i => nr(3560 + i * 44, 3780 + i * 44),
      tag: nr(3860, 4260),
      cta: nr(4060, 4480),
      ver: nr(4260, 4640),
      cue: nr(4460, 4900),
      plate: 4 + Math.round(9 * nr(1560, 2400))
    };
  }

  // Ambient state once the cold open has landed: no carve, no blast, ink and
  // vertical origin driven by the scroll position instead of a clock.
  ambientEnv(W, H){
    return {
      cx: W / 2, cy: H / 2, S: this.CYC / this.PER, k: 1,
      alpha: this.ink, steep: 4.4, cow: 0, markPx: 82, half: 49,
      scanY: 1e9, flash: 0, front: 1e9, soft: 60, ringW: 96, ringAmp: 0,
      plate: 5
    };
  }

  paint(g, e, ph, yOff){
    const { ctx, cols, rows, cw, chh, sA, cA, sB, cB, norm } = g;
    const T = this.T, n = T.length, CH = this.CH, BAY = this.BAY, top = CH.length - 1;
    const S = e.S, k = e.k, cx = e.cx, cy = e.cy, TAU = 2 * Math.PI;
    for (let j = 0; j < n; j++){
      const q = T[j], ax = TAU * q[0] * S * k, bx = TAU * q[0] * S * cx * (1 - k);
      for (let x = 0; x < cols; x++){
        const A = ax * (x * cw + cw * 0.5) + bx;
        sA[j * cols + x] = q[2] * Math.sin(A);
        cA[j * cols + x] = q[2] * Math.cos(A);
      }
    }
    ctx.fillStyle = 'rgb(' + e.plate + ',' + e.plate + ',' + e.plate + ')';
    ctx.fillRect(0, 0, g.w, g.h);
    if (e.alpha < 0.004) return;
    ctx.font = g.font; ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(255,255,255,' + e.alpha.toFixed(3) + ')';
    const gl = this.glyph;
    const useCow = gl && e.cow > 0.004;
    const gs = gl ? gl.f / Math.max(1, e.markPx) : 0;
    const gh = gl ? e.markPx * gl.n / (2 * gl.f) : 0;
    for (let y = 0; y < rows; y++){
      const py = y * chh + chh * 0.5;
      if (py > e.scanY) break;
      for (let j = 0; j < n; j++){
        const q = T[j], B = TAU * q[1] * S * (cy * (1 - k) + (py + yOff) * k) + q[3] + ph * q[4];
        sB[j] = Math.sin(B); cB[j] = Math.cos(B);
      }
      const dy = py - cy, dy2 = dy * dy;
      const band = e.scanY < 1e8 ? Math.max(0, 1 - Math.abs(py - e.scanY) / (chh * 2.5)) * 0.5 : 0;
      const inRow = useCow && py > cy - gh && py < cy + gh;
      let grow = -1;
      if (inRow){ const r = ((py - cy) * gs + gl.gcy) | 0; if (r >= 0 && r < gl.n) grow = r * gl.n; }
      let line = '';
      for (let x = 0; x < cols; x++){
        let f = 0;
        for (let j = 0; j < n; j++){ const i = j * cols + x; f += sA[i] * cB[j] + cA[i] * sB[j]; }
        let d = ((f / norm + 1) / 2 - 0.60) * e.steep + 0.5;
        const px = x * cw + cw * 0.5;
        if (useCow){
          let m = 0;
          if (grow >= 0){
            const gx = ((px - cx) * gs + gl.gcx) | 0;
            if (gx >= 0 && gx < gl.n) m = gl.a[grow + gx];
          }
          const cd = m * 1.30 - 0.32 + (d - 0.5) * 0.42 * m + (e.flash + band) * m;
          d = d * (1 - e.cow) + cd * e.cow;
        }
        if (e.front < 1e8){
          const dx = px - cx, dist = Math.sqrt(dx * dx + dy2);
          const vis = (e.front - dist) / e.soft;
          if (vis <= 0){ line += ' '; continue; }
          if (vis < 1) d = d * vis - (1 - vis) * 0.12;
          const rg = 1 - Math.abs(dist - e.front) / e.ringW;
          if (rg > 0) d += rg * e.ringAmp;
        }
        d += (BAY[((y & 3) << 2) | (x & 3)] / 16 - 0.5) * 0.13;
        line += CH[d < 0 ? 0 : d > 1 ? top : Math.round(d * top)];
      }
      ctx.fillText(line, 0, y * chh);
    }
  }

  grab(){
    const r = this.rootRef.current;
    const q = s => r.querySelector(s);
    this.ov = {
      mark: q('[data-o="mark"]'), tag: q('[data-o="tag"]'), cta: q('[data-o="cta"]'),
      ver: q('[data-o="ver"]'), cue: q('[data-o="scrollcue"]'),
      letters: Array.from(r.querySelectorAll('[data-l]'))
    };
    this.rises = Array.from(r.querySelectorAll('[data-rise]'));
    this.pars = Array.from(r.querySelectorAll('[data-par]'));
    this.floats = Array.from(r.querySelectorAll('[data-float]'));
    this.ladders = Array.from(r.querySelectorAll('[data-ladder]'));
    this.inks = Array.from(r.querySelectorAll('[data-ink]'));
    this.reveals = Array.from(r.querySelectorAll('[data-reveal]'));
    this.fits = Array.from(r.querySelectorAll('[data-fit]'));

    // Ages are parsed out of the markup and then tick for real, so the shots are
    // never frozen at 38s while you read the page.
    this.ages = Array.from(r.querySelectorAll('.rr-age')).map(el => {
      const m = /^(\d+)\s*([smh])$/.exec((el.textContent || '').trim());
      if (!m) return null;
      const mul = m[2] === 'h' ? 3600 : m[2] === 'm' ? 60 : 1;
      return { el, s: +m[1] * mul };
    }).filter(Boolean);

    // One-shot timelines, started when their element reaches the trigger line.
    this.anims = [];
    if (this.moves()){
      for (const el of this.rises){ el.style.opacity = '0'; el.style.willChange = 'opacity, transform'; }
      for (const el of this.ladders) el.style.opacity = '0.28';
      for (const el of this.reveals){ el.style.opacity = '0'; el.style.willChange = 'opacity, transform'; }

      for (const el of r.querySelectorAll('[data-term]')){
        const lines = Array.from(el.children);
        for (const l of lines) l.style.opacity = '0';
        this.anims.push({ el, t0: null, step: t => {
          for (let i = 0; i < lines.length; i++){
            const p = Math.max(0, Math.min(1, (t - i * 78) / 150));
            lines[i].style.opacity = p.toFixed(3);
          }
        }});
      }
      for (const el of r.querySelectorAll('[data-stagger]')){
        const kids = Array.from(el.querySelectorAll('.rail-row, .rail-item, .cmdk-row'));
        const gap = +el.dataset.stagger || 40;
        const lead = el.classList.contains('cmdk-list') ? 300 : 0;
        for (const k of kids){ k.style.opacity = '0'; }
        this.anims.push({ el, t0: null, step: t => {
          for (let i = 0; i < kids.length; i++){
            const p = Math.max(0, Math.min(1, (t - lead - i * gap) / 220));
            kids[i].style.opacity = p.toFixed(3);
            kids[i].style.transform = 'translate3d(' + ((1 - p) * -7).toFixed(2) + 'px,0,0)';
          }
        }});
      }
      for (const el of r.querySelectorAll('[data-typed]')){
        const full = el.dataset.typed || '';
        this.anims.push({ el, t0: null, step: t => {
          const n = Math.max(0, Math.min(full.length, Math.round((t - 120) / 105)));
          if (el._n !== n){ el.value = full.slice(0, n); el._n = n; }
        }});
      }
      for (const el of r.querySelectorAll('[data-arrive]')){
        const count = r.querySelector('[data-needs-count]');
        this.anims.push({ el, t0: null, step: t => {
          const p = Math.max(0, Math.min(1, (t - 1150) / 380));
          const e = 1 - Math.pow(1 - p, 3);
          el.style.opacity = e.toFixed(3);
          el.style.transform = 'translate3d(0,' + ((1 - e) * -10).toFixed(2) + 'px,0)';
          if (count && p > 0.35 && count.textContent !== 'Needs you · 3') count.textContent = 'Needs you · 3';
        }});
      }
    }
  }

  // The blast has to leave the mark, so read where the mark actually sits
  // rather than trusting an offset the hero layout can change under us.
  markCenter(g){
    const m = this.ov && this.ov.mark;
    if (m){
      const r = m.getBoundingClientRect();
      if (r.width) return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    }
    return { x: g.w / 2, y: g.h / 2 - 96 };
  }

  // A scaled mockup does not shrink with its wrapper on its own, so the scale is
  // computed from the space actually available and the wrapper reserves the height.
  fit(){
    for (const el of this.fits || []){
      const d = (el.dataset.fit || '').split('x');
      const w = +d[0], h = +d[1];
      const host = el.parentElement;
      if (!w || !h || !host) continue;
      const sc = Math.min(1, (host.clientWidth || w) / w);
      el.style.transform = 'scale(' + sc.toFixed(4) + ')';
      host.style.height = Math.round(h * sc) + 'px';
    }
  }

  // Timelines are advanced from wall clock, and driven from BOTH the scroll event
  // and the paint loop. Either one alone is enough, so a stall in one cannot leave
  // content stuck at the opacity:0 that grab() set.
  stepAll(){
    const now = performance.now();
    for (const a of this.anims || []){
      if (a.t0 == null) continue;
      try { a.step(now - a.t0); } catch(e){}
    }
  }

  // Fail open: if anything in the motion pipeline dies, the page must still read.
  openAll(){
    for (const el of this.rises || []){ el.style.opacity = '1'; el.style.transform = 'none'; }
    for (const el of this.reveals || []) el.style.opacity = '1';
    for (const el of this.ladders || []) el.style.opacity = '1';
    for (const a of this.anims || []){ try { a.step(1e6); } catch(e){} }
    const root = this.rootRef.current;
    if (!root) return;
    for (const el of root.querySelectorAll('[data-arrive], [data-term] > *, [data-stagger] > *')){
      el.style.opacity = '1';
      el.style.transform = 'none';
    }
    for (const el of root.querySelectorAll('[data-typed]')) el.value = el.dataset.typed || '';
    const count = root.querySelector('[data-needs-count]');
    if (count) count.textContent = 'Needs you · 3';
  }

  heroOverlay(t, e){
    const o = this.ov;
    if (!o) return;
    o.mark.style.opacity = e.glyphOp.toFixed(3);
    o.tag.style.opacity = e.tag.toFixed(3);
    o.cta.style.opacity = e.cta.toFixed(3);
    o.ver.style.opacity = e.ver.toFixed(3);
    o.cue.style.opacity = e.cue.toFixed(3);
    for (let i = 0; i < o.letters.length; i++) o.letters[i].style.opacity = e.letter(i).toFixed(3);
  }

  heroLanded(){
    const o = this.ov;
    if (!o) return;
    o.mark.style.opacity = '1'; o.tag.style.opacity = '1';
    o.cta.style.opacity = '1'; o.ver.style.opacity = '1';
    for (const l of o.letters) l.style.opacity = '1';
  }

  scroll(){
    try { this.scrollInner(); this.scrolled = true; }
    catch(err){ this.broken = true; this.openAll(); }
  }

  scrollInner(){
    const cl = (v, a, b) => v < a ? a : v > b ? b : v;
    const eo = v => 1 - Math.pow(1 - v, 3);
    const vh = window.innerHeight, sy = window.scrollY || window.pageYOffset || 0;
    this.sy = sy;

    const nav = this.navRef.current;
    if (nav){
      const on = sy > 40;
      nav.style.background = on ? 'rgba(5,5,5,.82)' : 'rgba(5,5,5,0)';
      nav.style.borderBottomColor = on ? 'var(--border)' : 'transparent';
      nav.style.backdropFilter = on ? 'saturate(140%)' : 'none';
    }
    if (this.ov && this.ov.cue) this.ov.cue.style.opacity = this.done ? (1 - cl(sy / 260, 0, 1)).toFixed(3) : this.ov.cue.style.opacity;

    if (!this.moves()){
      for (const el of this.rises){ el.style.opacity = '1'; el.style.transform = 'none'; }
      for (const el of this.ladders) el.style.opacity = '1';
      this.inkTarget = this.ambient();
      return;
    }

    for (const el of this.rises){
      const r = el.getBoundingClientRect();
      const p = eo(cl((vh * 0.94 - r.top) / (vh * 0.42), 0, 1));
      el.style.opacity = p.toFixed(3);
      el.style.transform = 'translate3d(0,' + ((1 - p) * 34).toFixed(2) + 'px,0)';
    }
    for (const el of this.reveals){
      const r = el.getBoundingClientRect();
      const p = eo(cl((vh * 0.98 - r.top) / (vh * 0.5), 0, 1));
      el.style.opacity = p.toFixed(3);
      el.dataset.revealP = p.toFixed(4);
    }
    // Anything with a one-shot timeline starts when it crosses 88% of the fold.
    for (const a of this.anims){
      if (a.t0 != null) continue;
      const r = a.el.getBoundingClientRect();
      if (r.top < vh * 0.88 && r.bottom > 0) a.t0 = performance.now();
    }
    this.stepAll();
    for (const el of this.pars){
      const r = el.getBoundingClientRect();
      const f = +el.dataset.par || 0;
      const p = cl((vh - r.top) / (vh + r.height), 0, 1);
      const y = (0.5 - p) * f;
      // A reveal element also scales up as it lands — value and size, no bounce.
      if (el.dataset.revealP != null){
        const sc = 0.972 + 0.028 * +el.dataset.revealP;
        el.style.transform = 'translate3d(0,' + y.toFixed(2) + 'px,0) scale(' + sc.toFixed(4) + ')';
      } else {
        el.style.transform = 'translate3d(0,' + y.toFixed(2) + 'px,0)';
      }
    }
    for (const el of this.floats){
      const r = el.getBoundingClientRect();
      const p = eo(cl((vh * 0.9 - r.top) / (vh * 0.5), 0, 1));
      if (el.dataset.float === 'lift'){
        el.style.transform = 'translate3d(0,' + (-p * 22).toFixed(2) + 'px,0)';
        el.style.opacity = '1';
      } else {
        el.style.opacity = (1 - p * 0.56).toFixed(3);
        el.style.transform = 'translate3d(0,' + (p * 6).toFixed(2) + 'px,0)';
      }
    }
    for (const el of this.ladders){
      const r = el.getBoundingClientRect();
      const i = +el.dataset.ladder || 0;
      const p = cl((vh * 0.82 - r.top) / (vh * 0.2) - i * 0.34, 0, 1);
      el.style.opacity = (0.28 + 0.72 * p).toFixed(3);
    }

    // Sections bid for the ink level; the nearest one to the viewport centre wins.
    let target = this.ambient(), best = 1e9;
    for (const el of this.inks){
      const r = el.getBoundingClientRect();
      const d = Math.abs((r.top + r.height / 2) - vh / 2);
      if (d < best && r.top < vh && r.bottom > 0){ best = d; target = +el.dataset.ink; }
    }
    this.inkTarget = target;
  }

  // An interval, not requestAnimationFrame: preview surfaces throttle rAF when
  // they are not focused, and a frozen field is worse than a coarse one.
  frame = () => {
    if (this.dead) return;
    const g = this.g;
    if (!g) return;
    const now = performance.now();
    if (this.t0 == null){ this.t0 = now; this.prev = now; this.ph = 0; }
    const dt = Math.min(0.1, (now - this.prev) / 1000); this.prev = now;

    if (!this.done){
      const t = now - this.t0;
      if (t >= this.DUR){ this.done = true; this.heroLanded(); this.ink = this.ambient(); }
      else {
        const warp = 1 + 6 * Math.max(0, 1 - Math.max(0, t - 1560) / 900);
        this.ph += dt * (t < 1560 ? 0.55 : warp);
        const e = this.env(t, g.w, g.h, this.markCenter(g));
        this.heroOverlay(t, e);
        this.paint(g, e, this.ph, 0);
        return;
      }
    }

    // scroll() is driven from this loop, not requestAnimationFrame — the same
    // reason the paint is. An rAF callback that never fired used to latch the
    // scroll pipeline off for good and blank everything below the hero.
    if (!this.broken && (this.sy !== (window.scrollY || 0) || (this.ticks2 = (this.ticks2 || 0) + 1) % 8 === 0)) this.scroll();

    this.frameTicks = (this.frameTicks || 0) + 1;
    this.stepAll();
    if (now - (this.tick1s || 0) > 1000){
      this.tick1s = now;
      for (const a of this.ages){
        a.s += 1;
        const v = a.s < 60 ? a.s + 's' : a.s < 3600 ? Math.floor(a.s / 60) + 'm' : Math.floor(a.s / 3600) + 'h';
        if (a.el.textContent !== v) a.el.textContent = v;
      }
    }

    this.ph += dt * 0.42;
    this.ink += ((this.inkTarget != null ? this.inkTarget : this.ambient()) - this.ink) * Math.min(1, dt * 3.4);
    const yOff = this.moves() ? (this.sy || 0) * 0.22 : 0;
    if (this.cost > 17 && (this.ticks = (this.ticks || 0) + 1) % 2) return;
    const p0 = performance.now();
    this.paint(g, this.ambientEnv(g.w, g.h), this.ph, yOff);
    this.cost = (this.cost || 0) * 0.82 + (performance.now() - p0) * 0.18;
  };

  async boot(){
    const cv = this.cvRef.current, root = this.rootRef.current;
    if (!cv || !root) return;
    this.dead = false;
    if (this.timer) clearInterval(this.timer);
    this.reduce = document.documentElement.getAttribute('data-reduce-motion') === '1' ||
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
    this.ink = 0.05;
    this.grab();
    this.g = this.mkGeom(cv);

    this.onRz = () => { this.g = this.mkGeom(cv); this.fit(); this.scroll(); };
    window.addEventListener('resize', this.onRz);
    this.onSc = () => {
      // The cold open is never a reason to wait: scrolling lands it immediately.
      if (!this.done && (window.scrollY || 0) > 30){ this.done = true; this.heroLanded(); this.ink = this.ambient(); }
      this.scroll();
    };
    window.addEventListener('scroll', this.onSc, { passive: true });
    this.fit();
    this.applyLinks();
    this.scroll();
    // Watchdog: if the paint loop is not advancing, the timelines can never finish
    // on their own, so complete everything and stop hiding things behind motion.
    const watch = (n) => setTimeout(() => {
      if (this.dead) return;
      const before = this.frameTicks || 0;
      setTimeout(() => {
        if (this.dead) return;
        if ((this.frameTicks || 0) === before){ this.loopDead = true; this.openAll(); }
        else if (n < 3) watch(n + 1);
      }, 800);
    }, n === 0 ? 1500 : 2600);
    watch(0);

    if (this.props.coldOpen === false || this.reduce){
      this.done = true; this.heroLanded(); this.ink = this.ambient();
    }
    if (!this.moves()) this.openAll();
    this.t0 = null;
    this.frame();
    this.timer = setInterval(this.frame, 26);
    await this.loadGlyph();
    if (this.dead) return;
    this.frame();
  }
}

window.addEventListener('DOMContentLoaded',()=>{const app=new BessieLanding(window.__BESSIE_SITE__||{});document.querySelectorAll('[data-copy-row]').forEach(row=>row.addEventListener('click',e=>app.onCopy(e)));app.boot().catch(()=>app.openAll());window.__BESSIE_LANDING__=app});
