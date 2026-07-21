// Renders 3 monochrome concept visuals (transparent PNG) for AgentLinux Part II.
// A: package-interaction complexity graph   B: bug-discovery decay curve   C: dual-threshold stop rule
const { chromium } = require('playwright');

const COL = { t1:'#e0e0e0', t2:'#a8a8a8', muted:'#7d7d7d', faint:'#555555',
              border:'#2a2a2a', border2:'#3a3a3a', panel:'#17171b', panel2:'#1e1e22',
              edge:'#3a3a3a', edgeHi:'#707070', white:'#ffffff', accentDim:'#8a8a8a' };
const FF = "'JetBrains Mono','Fira Code',monospace";

/* ---------- helpers ---------- */
const charW = fs => fs * 0.6;
function node(cx, cy, label, o = {}) {
  const fs = o.fs || 30, pad = o.pad || 26, h = o.h || 64;
  const w = Math.round(label.length * charW(fs) + pad * 2);
  const x = cx - w / 2, y = cy - h / 2;
  const stroke = o.stroke || COL.border2, sw = o.sw || 1.5, fill = o.fill || COL.panel;
  const tf = o.textFill || COL.t1, fw = o.fw || 600;
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="9" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>
    <text x="${cx}" y="${cy}" font-family="${FF}" font-size="${fs}" font-weight="${fw}" fill="${tf}" text-anchor="middle" dominant-baseline="central">${label}</text>`;
}
const txt = (x, y, s, o = {}) =>
  `<text x="${x}" y="${y}" font-family="${FF}" font-size="${o.fs||22}" font-weight="${o.fw||500}" fill="${o.fill||COL.muted}" text-anchor="${o.anchor||'start'}" dominant-baseline="${o.baseline||'alphabetic'}" letter-spacing="${o.ls||0}">${s}</text>`;

/* ================= VISUAL A — complexity graph ================= */
function vizA() {
  const W = 1800, H = 660;
  const fw = [ {l:'gsd',cx:470}, {l:'rtk',cx:900}, {l:'playwright',cx:1330} ];
  const ag = [ {l:'claude-code',cx:235}, {l:'codex',cx:590}, {l:'opencode',cx:900,collide:true}, {l:'antigravity',cx:1210}, {l:'qwen-code',cx:1560} ];
  const fy = 150, ay = 500, nh = 64;
  const cxOf = (arr,l)=>arr.find(n=>n.l===l).cx;
  let edges = '';
  const link = (fcx, acx, hi) =>
    `<line x1="${fcx}" y1="${fy+nh/2}" x2="${acx}" y2="${ay-nh/2}" stroke="${hi?COL.edgeHi:COL.edge}" stroke-width="${hi?2.4:1.4}" ${hi?'':'stroke-opacity="0.9"'}/>`;
  // gsd → all 5 agents (the "installed on five agents" story) — highlighted
  ag.forEach(a => edges += link(cxOf(fw,'gsd'), a.cx, true));
  // rtk → 3 agents
  ['codex','opencode','qwen-code'].forEach(l => edges += link(cxOf(fw,'rtk'), cxOf(ag,l), false));
  // playwright → 3 agents
  ['claude-code','opencode','antigravity'].forEach(l => edges += link(cxOf(fw,'playwright'), cxOf(ag,l), false));

  let nodes = '';
  fw.forEach(n => nodes += node(n.cx, fy, n.l, { fill:COL.panel2, stroke:COL.border2, textFill:COL.t1 }));
  ag.forEach(n => nodes += node(n.cx, ay, n.l, n.collide
      ? { fill:COL.panel2, stroke:COL.white, sw:2.5, textFill:COL.white }
      : { fill:COL.panel, stroke:COL.border2, textFill:COL.t2 }));

  // collision callout on aider
  const acx = ag.find(n=>n.collide).cx;
  const callout = `${txt(acx, ay+nh/2+40, '3 frameworks, one host', {fs:20, fill:COL.white, anchor:'middle'})}`;

  const labels =
    txt(120, 78, 'FRAMEWORKS · TOOLING', {fs:21, fill:COL.muted, ls:3}) +
    txt(120, 440, 'AGENTS', {fs:21, fill:COL.muted, ls:3});
  const caption = txt(W/2, H-26, 'each install · each removal · each combination — a test that must pass', {fs:23, fill:COL.t2, anchor:'middle'});

  return { id:'A', W, H, svg:`<svg id="vizA" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
    ${edges}${nodes}${callout}${labels}${caption}</svg>` };
}

/* ================= VISUAL B — bug-discovery decay ================= */
function vizB() {
  const W = 1600, H = 640;
  const xL = 210, xR = 1500, yBase = 470, yTop = 95, maxB = 6;
  const unit = (yBase - yTop) / maxB;
  const bugs = [5,4,2,1,1,0,0];
  const n = bugs.length, slot = (xR - xL) / n, bw = 96;
  let bars = '', ivl = '';
  const centers = [];
  bugs.forEach((b,i) => {
    const cx = xL + slot*(i+0.5); centers.push(cx);
    const top = yBase - b*unit;
    if (b>0) bars += `<rect x="${cx-bw/2}" y="${top}" width="${bw}" height="${yBase-top}" rx="4" fill="${COL.panel2}" stroke="${COL.border2}" stroke-width="1"/>`;
    if (i < 5) ivl += txt(cx, yBase+34, `${(i+1)*30}m`, {fs:18, fill:COL.faint, anchor:'middle'});
  });
  // decay (regression) curve overlay — exponential through first bar top, asymptotic
  const y0 = yBase - bugs[0]*unit, x0 = centers[0], x1 = centers[n-1];
  let path = '';
  for (let k=0;k<=60;k++){ const t=k/60; const x=x0+(x1-x0)*t; const y=yBase-(yBase-y0)*Math.exp(-3.2*t); path += (k?'L':'M')+x.toFixed(1)+' '+y.toFixed(1)+' '; }
  const curve = `<path d="${path}" fill="none" stroke="${COL.white}" stroke-width="3" stroke-dasharray="9 7" stroke-opacity="0.9"/>`;
  // converged tail shade + bracket
  const tailX = xL + slot*5;
  const tail = `<rect x="${tailX}" y="${yTop}" width="${xR-tailX}" height="${yBase-yTop}" fill="${COL.white}" fill-opacity="0.05"/>
    <line x1="${tailX}" y1="${yTop}" x2="${tailX}" y2="${yBase}" stroke="${COL.border2}" stroke-width="1" stroke-dasharray="4 5"/>
    ${txt((tailX+xR)/2, yTop+38, 'no new bugs', {fs:22, fill:COL.white, anchor:'middle'})}
    ${txt((tailX+xR)/2, yTop+68, '→ converged', {fs:20, fill:COL.t2, anchor:'middle'})}`;
  // axes
  const axes = `<line x1="${xL-30}" y1="${yBase}" x2="${xR}" y2="${yBase}" stroke="${COL.border}" stroke-width="1.5"/>
    <line x1="${xL-30}" y1="${yTop-10}" x2="${xL-30}" y2="${yBase}" stroke="${COL.border}" stroke-width="1.5"/>`;
  // value label on first bar + axis titles
  const ann = txt(centers[0], y0-22, '5 bugs', {fs:22, fill:COL.white, anchor:'middle'}) +
    `<text x="70" y="${(yTop+yBase)/2}" font-family="${FF}" font-size="20" fill="${COL.muted}" text-anchor="middle" transform="rotate(-90 70 ${(yTop+yBase)/2})">new bugs found / interval</text>` +
    txt(xR, yBase+34, 'testing time →', {fs:20, fill:COL.muted, anchor:'end'});

  return { id:'B', W, H, svg:`<svg id="vizB" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
    ${tail}${axes}${bars}${curve}${ivl}${ann}</svg>` };
}

/* ================= VISUAL C — dual-threshold stop ================= */
function vizC() {
  const W = 1600, H = 600;
  const rowX = 130, rowR = 1000;
  // Row A — 30-minute time window
  const ayc = 205;
  let rowA = txt(rowX, ayc-70, 'TIME  ·  LAST 30 MINUTES', {fs:22, fill:COL.t2, ls:2});
  const markN = 9, mSlot = (rowR-rowX)/(markN-1);
  // bug markers (filled white) at a few early positions; hollow later
  const bugAt = new Set([1,3,4]);
  for (let i=0;i<markN;i++){ const x=rowX+mSlot*i;
    rowA += bugAt.has(i)
      ? `<circle cx="${x}" cy="${ayc}" r="11" fill="${COL.white}"/>`
      : `<circle cx="${x}" cy="${ayc}" r="9" fill="none" stroke="${COL.border2}" stroke-width="2"/>`; }
  rowA += `<line x1="${rowX-15}" y1="${ayc+40}" x2="${rowR+15}" y2="${ayc+40}" stroke="${COL.border}" stroke-width="1"/>`;
  // quiet window shade over the tail
  const qA = rowX + mSlot*5;
  rowA += `<rect x="${qA-18}" y="${ayc-38}" width="${rowR-qA+40}" height="76" rx="8" fill="${COL.white}" fill-opacity="0.05" stroke="${COL.border2}" stroke-dasharray="4 5"/>
    ${txt((qA+rowR)/2+10, ayc+58, '0 new bugs', {fs:19, fill:COL.white, anchor:'middle'})}`;

  // Row B — last 10 test ideas
  const byc = 415;
  let rowB = txt(rowX, byc-70, 'TESTS  ·  LAST 10 IDEAS', {fs:22, fill:COL.t2, ls:2});
  const sq = 34, gap = (rowR-rowX-sq)/(10-1);
  for (let i=0;i<10;i++){ const x=rowX+gap*i;
    rowB += `<rect x="${x}" y="${byc-sq/2}" width="${sq}" height="${sq}" rx="5" fill="none" stroke="${COL.border2}" stroke-width="2"/>
      <path d="M ${x+9} ${byc} l 6 7 l 11 -14" fill="none" stroke="${COL.accentDim}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`; }
  rowB += `<rect x="${rowX-18}" y="${byc-38}" width="${rowR-rowX+56}" height="76" rx="8" fill="${COL.white}" fill-opacity="0.04" stroke="${COL.border2}" stroke-dasharray="4 5"/>
    ${txt(rowR+20, byc+58, '0 new bugs', {fs:19, fill:COL.white, anchor:'end'})}`;

  // AND brace + STOP badge
  const andX = 1075;
  const brace = `<path d="M ${andX} 150 q 22 0 22 22 v 108 q 0 22 22 22 q -22 0 -22 22 v 108 q 0 22 -22 22" fill="none" stroke="${COL.border2}" stroke-width="2"/>
    ${txt(andX+70, 300, 'AND', {fs:26, fill:COL.t1, fw:700, anchor:'middle', baseline:'central'})}`;
  const bx=1230, bw=310, byv=232, bh=136;
  const badge = `<rect x="${bx}" y="${byv}" width="${bw}" height="${bh}" rx="12" fill="${COL.panel2}" stroke="${COL.white}" stroke-width="2.5"/>
    ${txt(bx+bw/2, byv+54, 'STOP', {fs:44, fill:COL.white, fw:800, anchor:'middle', baseline:'central'})}
    ${txt(bx+bw/2, byv+100, 'converged', {fs:22, fill:COL.t2, anchor:'middle', baseline:'central'})}`;

  const caption = txt(W/2, H-24, 'both windows must go quiet — the test window guards against one long test faking a quiet clock', {fs:21, fill:COL.muted, anchor:'middle'});

  return { id:'C', W, H, svg:`<svg id="vizC" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
    ${rowA}${rowB}${brace}${badge}${caption}</svg>` };
}

/* ---------- render ---------- */
(async () => {
  const vs = [vizA(), vizB(), vizC()];
  const html = `<!doctype html><html><head><meta charset="utf8">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>body{margin:0;background:transparent}div{margin:0;padding:0}</style></head>
    <body>${vs.map(v=>`<div>${v.svg}</div>`).join('')}</body></html>`;
  require('fs').writeFileSync('/tmp/viz.html', html);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport:{width:1900,height:2200}, deviceScaleFactor:2.5 });
  await p.goto('file:///tmp/viz.html', { waitUntil:'networkidle' });
  await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(600);
  for (const v of vs) {
    const el = await p.$('#viz'+v.id);
    await el.screenshot({ path:`./viz-${v.id}.png`, omitBackground:true });
  }
  await b.close();
  console.log('wrote viz-A.png viz-B.png viz-C.png');
})().catch(e => { console.error(e); process.exit(1); });
