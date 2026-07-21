// AgentLinux pitch deck — native editable .pptx (pptxgenjs)
// Positioning: AgentLinux takes the setup & integration burden off the HUMAN —
// install any agent or framework in one command (like installing Python), and its
// maintainers keep the curated combos working. "Linux, for agents."
// Design: strict monochrome terminal, monospace (Consolas), pixel-art house motif,
// presenter-mode sparseness. No accent stripes/underlines (per pptx skill).
// Tight 6-slide cut (Problem + Turn dropped to fit the timed pitch).
// No speaker notes — the presenter writes their own.
const pptxgen = require('pptxgenjs');
const p = new pptxgen();
p.layout = 'LAYOUT_WIDE';                 // 13.333in x 7.5in (16:9)
p.author = 'AgentLinux';
p.title = 'AgentLinux — pitch deck';

const C = { bg:'0A0A0A', panel:'121212', panel2:'161616', border:'2A2A2A',
            border2:'383838', faint:'555555', muted:'7D7D7D', t2:'A8A8A8',
            t1:'E0E0E0', white:'FFFFFF' };
const F = 'Consolas';
const HOUSE = './deck-house.png';
const MX = 0.9;                            // left/right content margin
const SW = 13.333, SH = 7.5;
const CW = SW - 2*MX;                      // content width

const T = (o={}) => Object.assign({ fontFace:F, align:'left', valign:'top', margin:0 }, o);

let SLIDE_NO = 0;           // auto-incremented per footer() call
const TOTAL = 11;

function footer(s){
  SLIDE_NO++;
  s.addImage({ path:HOUSE, x:MX, y:6.94, w:0.26, h:0.26 });
  s.addText('agentlinux', T({ x:MX+0.36, y:6.9, w:3, h:0.34, fontSize:13, color:C.t2, bold:true, valign:'middle' }));
  s.addText([{ text:String(SLIDE_NO).padStart(2,'0'), options:{ color:C.t2, bold:true } },
             { text:'  /  ' + String(TOTAL).padStart(2,'0'), options:{ color:C.faint } }],
            T({ x:SW-MX-2.4, y:6.9, w:2.4, h:0.34, fontSize:13, align:'right', valign:'middle', charSpacing:1 }));
}
function kicker(s, label, x, y, comment=true){
  const runs = comment
    ? [{ text:'// ', options:{ color:C.faint } }, { text:label, options:{ color:C.muted } }]
    : [{ text:label, options:{ color:C.muted } }];
  s.addText(runs, T({ x, y, w:11, h:0.34, fontSize:13, bold:true, charSpacing:2 }));
}
const bg = () => ({ color:C.bg });

/* ============================ 01 — COVER ============================ */
let s = p.addSlide(); s.background = bg();
kicker(s, 'AGENT INFRASTRUCTURE', MX, 2.35);
s.addText('AgentLinux', T({ x:MX, y:2.68, w:7.6, h:1.05, fontSize:54, bold:true, color:C.white }));
s.addText([{ text:'Linux, for agents.', options:{ color:C.t1, bold:true } },
           { text:' █', options:{ color:C.white } }],
          T({ x:MX, y:3.85, w:7.8, h:0.8, fontSize:40, bold:true }));
s.addText([{ text:'Agent-ready Ubuntu, one command   ·   ', options:{ color:C.muted } },
           { text:'agentlinux.org', options:{ color:C.t2 } }],
          T({ x:MX, y:5.05, w:8, h:0.4, fontSize:16 }));
s.addImage({ path:HOUSE, x:8.55, y:2.15, w:3.55, h:3.55 });
footer(s);

/* ============================ 02 — SOLUTION ======================== */
s = p.addSlide(); s.background = bg();
kicker(s, 'THE SOLUTION', MX, 1.95);
s.addText('The setup,\nalready done.', T({ x:MX, y:2.3, w:7.2, h:1.5, fontSize:40, bold:true, color:C.t1, lineSpacingMultiple:1.05 }));
s.addText([{ text:'An Ubuntu layer where every agent and framework is a first-class package — ', options:{ color:C.t2 } },
           { text:'one command', options:{ color:C.white, bold:true } },
           { text:", and it's wired for you.", options:{ color:C.t2 } }],
          T({ x:MX, y:3.95, w:7.3, h:1.0, fontSize:18, lineSpacingMultiple:1.3 }));
// example agents/frameworks that "just install" — a clearly separated, labelled group
s.addText('ONE COMMAND EACH', T({ x:MX, y:5.34, w:6, h:0.3, fontSize:12, bold:true, color:C.muted, charSpacing:3 }));
const chips = [ {t:'claude-code', w:2.5}, {t:'codex', w:1.5}, {t:'gsd', w:1.2} ];
let cx = MX; const chipY = 5.74, cgap = 0.32;
chips.forEach((ch) => {
  s.addShape(p.ShapeType.roundRect, { x:cx, y:chipY, w:ch.w, h:0.56, fill:{ color:C.panel }, line:{ color:C.border, width:1 }, rectRadius:0.06 });
  s.addText(ch.t, T({ x:cx, y:chipY, w:ch.w, h:0.56, fontSize:16, bold:true, color:C.t1, align:'center', valign:'middle' }));
  cx += ch.w + cgap;
});
s.addImage({ path:HOUSE, x:8.95, y:2.4, w:3.1, h:3.1 });
footer(s);

/* ======== 03 — TWO COMMANDS (get AgentLinux on your Ubuntu, then an agent) == */
s = p.addSlide(); s.background = bg();
kicker(s, 'TIME-TO-PRODUCTIVE', MX, 1.7);
s.addText('Two commands to a working agent.', T({ x:MX, y:2.04, w:11.5, h:0.8, fontSize:32, bold:true, color:C.t1 }));
s.addShape(p.ShapeType.roundRect, { x:MX, y:3.05, w:CW, h:2.72, fill:{ color:C.panel }, line:{ color:C.border, width:1 }, rectRadius:0.1 });
[0,1,2].forEach(i => s.addShape(p.ShapeType.ellipse, { x:1.28+i*0.24, y:3.32, w:0.12, h:0.12, fill:{ color:C.border2 }, line:{ type:'none' } }));
s.addText('UBUNTU · AGENT SHELL', T({ x:8.4, y:3.26, w:3.6, h:0.3, fontSize:12, color:C.faint, align:'right', valign:'middle', charSpacing:2 }));
// step 1 — get AgentLinux, one time, on the Ubuntu you already run
s.addText('# one-time setup, on the Ubuntu you already have:', T({ x:1.28, y:3.72, w:11, h:0.3, fontSize:14, color:C.faint }));
s.addText([{ text:'$ ', options:{ color:C.muted } },
           { text:'curl -fsSL https://agentlinux.org/install.sh | sudo bash', options:{ color:C.t1, bold:true } }],
          T({ x:1.28, y:4.04, w:11.4, h:0.45, fontSize:18 }));
// step 2 — install an agent, one command
s.addText([{ text:'$ ', options:{ color:C.muted } },
           { text:'agentlinux install claude-code', options:{ color:C.white, bold:true } }],
          T({ x:1.28, y:4.74, w:11.4, h:0.5, fontSize:21 }));
s.addText([{ text:'# runtime · PATH · version handled — claude ready', options:{ color:C.faint } },
           { text:' █', options:{ color:C.white } }],
          T({ x:1.28, y:5.3, w:11.4, h:0.4, fontSize:14 }));
footer(s);

/* ============================ 04 — DIY MINEFIELD ================== */
s = p.addSlide(); s.background = bg();
kicker(s, 'INSTALLING IT YOURSELF', MX, 1.12);
s.addText('Three ways it bites.', T({ x:MX, y:1.46, w:11.5, h:0.9, fontSize:32, bold:true, color:C.t1 }));
const gap = 0.5, colW = (CW - 2*gap) / 3;
const probs = [
  { x: MX,               meta:'NODE.JS',    role:'PATH is on you',    v:"Node's global scripts must sit where your framework looks — or nothing launches." },
  { x: MX+colW+gap,      meta:'CODEX',      role:'The install drifts', v:'npm worked yesterday; the new feature is native-only today. Noticing and migrating is on you.' },
  { x: MX+2*(colW+gap),  meta:'PLAYWRIGHT', role:'Which Python?',      v:"System Python, or UV's latest? A best-practice call you — or your agent — can get wrong." },
];
probs.forEach(c => {
  s.addShape(p.ShapeType.roundRect, { x:c.x, y:2.9, w:colW, h:3.15, fill:{ color:C.panel }, line:{ type:'none' }, rectRadius:0.09 });
  s.addText(c.meta, T({ x:c.x+0.32, y:3.16, w:colW-0.64, h:0.3, fontSize:13, bold:true, color:C.muted, charSpacing:2 }));
  s.addText(c.role, T({ x:c.x+0.32, y:3.5, w:colW-0.64, h:0.82, fontSize:19, bold:true, color:C.t1, lineSpacingMultiple:1.05 }));
  s.addText(c.v,    T({ x:c.x+0.32, y:4.46, w:colW-0.64, h:1.45, fontSize:15, color:C.t2, lineSpacingMultiple:1.22 }));
});
footer(s);

/* ============================ 05 — BRIDGE ========================== */
s = p.addSlide(); s.background = bg();
kicker(s, 'PART II · THE HACKATHON BUILD', MX, 2.5, false);
s.addText([{ text:'Keeping it stable:', options:{ color:C.t1, breakLine:true } },
           { text:'an ', options:{ color:C.t1 } },
           { text:'autonomous QA loop.', options:{ color:C.white } }],
          T({ x:MX, y:2.85, w:12.0, h:1.5, fontSize:40, bold:true, lineSpacingMultiple:1.08 }));
s.addText('How we keep the curated combos working as the tools beneath them keep moving.',
          T({ x:MX, y:4.8, w:10.6, h:0.8, fontSize:18, color:C.t2, lineSpacingMultiple:1.3 }));
footer(s);

/* ==================== PART II — the hackathon build ==================== */

/* ---- 07 — THE CHALLENGE (complexity graph) ---- */
s = p.addSlide(); s.background = bg();
kicker(s, 'THE CHALLENGE', MX, 1.5);
s.addText("It's not the tools — it's the combinations.", T({ x:MX, y:1.85, w:12, h:0.7, fontSize:32, bold:true, color:C.t1 }));
s.addImage({ path:'./viz-A.png', x:1.15, y:2.62, w:11.04, h:4.05 });
footer(s);

/* ---- 07 — THE INSIGHT · when does the agent stop? (decay curve) ---- */
s = p.addSlide(); s.background = bg();
kicker(s, 'WHEN DOES THE AGENT STOP?', MX, 1.4);
s.addText('Bug discovery decays.', T({ x:MX, y:1.75, w:12, h:0.7, fontSize:32, bold:true, color:C.t1 }));
s.addText("The bugs are emergent — you can't script the tests. So we let the data answer:",
          T({ x:MX, y:2.5, w:12, h:0.4, fontSize:17, color:C.t2 }));
s.addImage({ path:'./viz-B.png', x:2.17, y:3.02, w:9.0, h:3.6 });
footer(s);

/* ---- 10 — THE STOPPING RULE (dual threshold) ---- */
s = p.addSlide(); s.background = bg();
kicker(s, 'THE STOPPING RULE', MX, 1.5);
s.addText('Stop on a dual threshold.', T({ x:MX, y:1.85, w:12, h:0.7, fontSize:32, bold:true, color:C.t1 }));
s.addImage({ path:'./viz-C.png', x:1.33, y:2.62, w:10.67, h:4.0 });
footer(s);

/* ---- 11 — RESULTS · by the numbers ---- */
s = p.addSlide(); s.background = bg();
kicker(s, 'RESULTS', MX, 1.5);
s.addText('By the numbers.', T({ x:MX, y:1.85, w:12, h:0.7, fontSize:32, bold:true, color:C.t1 }));
s.addText('Codex ran the QA skill autonomously over the v0.3.5 release candidate — in disposable Docker sandboxes.',
          T({ x:MX, y:2.6, w:11.5, h:0.5, fontSize:17, color:C.t2, lineSpacingMultiple:1.3 }));
const stats = [
  { n:'10',    l:'issues surfaced', sub:'5 confirmed new bugs' },
  { n:'129',   l:'QA test ideas',   sub:'3 campaigns · 2 install orders' },
  { n:'~11 h', l:'autonomous QA',   sub:'~19.5 h including fixes' },
];
const stW = 3.54, stGap = 0.45; let sx = MX;
stats.forEach(st => {
  s.addShape(p.ShapeType.roundRect, { x:sx, y:3.35, w:stW, h:2.15, fill:{ color:C.panel }, line:{ color:C.border, width:1 }, rectRadius:0.1 });
  s.addText(st.n, T({ x:sx, y:3.6, w:stW, h:0.9, fontSize:54, bold:true, color:C.white, align:'center', valign:'middle' }));
  s.addText(st.l, T({ x:sx, y:4.64, w:stW, h:0.35, fontSize:17, color:C.t2, align:'center', valign:'middle' }));
  s.addText(st.sub, T({ x:sx, y:5.04, w:stW, h:0.3, fontSize:13, color:C.muted, align:'center', valign:'middle' }));
  sx += stW + stGap;
});
s.addText('23 of 26 catalog packages exercised   ·   Ubuntu 22.04 / 24.04 / 26.04   ·   every Phase-50 finding fixed → 349/349 green',
          T({ x:MX, y:5.95, w:12, h:0.4, fontSize:13, color:C.faint }));
footer(s);

/* ---- 12 — SHOWCASE · two prominent findings ---- */
s = p.addSlide(); s.background = bg();
kicker(s, 'WHAT IT CAUGHT', MX, 1.5);
s.addText('Two worth showing.', T({ x:MX, y:1.85, w:12, h:0.7, fontSize:32, bold:true, color:C.t1 }));
const cW = 5.5;
const cards = [
  { x:MX, meta:'GSD × CODEX', h:'Agents breaking agents',
    b:"GSD's Codex fan-out writes [[hooks]]; Codex wants a HooksToml table — codex exec won't load.",
    code:'invalid type: sequence, expected struct HooksToml',
    tag:'the cross-tool break AgentLinux exists to catch' },
  { x:MX+cW+0.53, meta:'GEMINI CLI → ANTIGRAVITY', h:'A silent migration',
    b:"A test flagged GSD dropped Gemini CLI support — it's retiring into Antigravity CLI.",
    code:null,
    tag:'QA caught an ecosystem shift — we updated the catalog' },
];
cards.forEach(c => {
  s.addShape(p.ShapeType.roundRect, { x:c.x, y:2.85, w:cW, h:3.6, fill:{ color:C.panel }, line:{ type:'none' }, rectRadius:0.1 });
  s.addText(c.meta, T({ x:c.x+0.4, y:3.12, w:cW-0.8, h:0.3, fontSize:13, bold:true, color:C.muted, charSpacing:2 }));
  s.addText(c.h, T({ x:c.x+0.4, y:3.5, w:cW-0.8, h:0.5, fontSize:23, bold:true, color:C.t1 }));
  s.addText(c.b, T({ x:c.x+0.4, y:4.12, w:cW-0.8, h:1.0, fontSize:16, color:C.t2, lineSpacingMultiple:1.3 }));
  if (c.code) {
    s.addShape(p.ShapeType.roundRect, { x:c.x+0.4, y:5.15, w:cW-0.8, h:0.56, fill:{ color:C.bg }, line:{ color:C.border, width:1 }, rectRadius:0.05 });
    s.addText([{ text:'! ', options:{ color:C.muted } }, { text:c.code, options:{ color:C.t2 } }],
              T({ x:c.x+0.58, y:5.15, w:cW-1.1, h:0.56, fontSize:11.5, valign:'middle' }));
  }
  s.addText([{ text:'→  ', options:{ color:C.muted } }, { text:c.tag, options:{ color:C.t1 } }],
            T({ x:c.x+0.4, y:5.95, w:cW-0.8, h:0.4, fontSize:14, bold:true, valign:'middle' }));
});
footer(s);

/* ---- 13 — GOODBYE ---- */
s = p.addSlide(); s.background = bg();
kicker(s, 'FIN', MX, 2.5);
s.addText([{ text:'Thanks.', options:{ color:C.white, bold:true } }, { text:'█', options:{ color:C.white } }],
          T({ x:MX, y:2.85, w:7.6, h:1.0, fontSize:54, bold:true }));
s.addText('AgentLinux — Linux, for agents.', T({ x:MX, y:4.0, w:8, h:0.5, fontSize:24, bold:true, color:C.t1 }));
s.addText([{ text:'agentlinux.org', options:{ color:C.t2 } },
           { text:'    ·    github.com/Roo4L/Agent-Linux', options:{ color:C.muted } }],
          T({ x:MX, y:4.78, w:9.5, h:0.4, fontSize:16 }));
s.addImage({ path:HOUSE, x:8.55, y:2.35, w:3.45, h:3.45 });
footer(s);

p.writeFile({ fileName: './AgentLinux-deck.pptx' }).then(fn => console.log('WROTE', fn));
