const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport:{width:800,height:800}, deviceScaleFactor:2 });
  const svg = `<svg id="h" xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 16 16" width="720" height="720" shape-rendering="crispEdges">
    <rect x="9" y="0" width="2" height="3" fill="#6e6e6e"/>
    <rect x="6" y="2" width="2" height="1" fill="#8f8f8f"/><rect x="5" y="3" width="4" height="1" fill="#8f8f8f"/>
    <rect x="4" y="4" width="6" height="1" fill="#8f8f8f"/><rect x="3" y="5" width="8" height="1" fill="#8f8f8f"/>
    <rect x="2" y="6" width="10" height="1" fill="#8f8f8f"/><rect x="1" y="7" width="12" height="1" fill="#8f8f8f"/>
    <rect x="0" y="8" width="14" height="1" fill="#6e6e6e"/>
    <rect x="1" y="9" width="12" height="5" fill="#2e2e2e"/><rect x="1" y="9" width="1" height="5" fill="#6e6e6e"/>
    <rect x="12" y="9" width="1" height="5" fill="#6e6e6e"/><rect x="1" y="9" width="12" height="1" fill="#6e6e6e"/>
    <rect x="2" y="10" width="2" height="2" fill="#ffffff"/><rect x="10" y="10" width="2" height="2" fill="#ffffff"/>
    <rect x="6" y="12" width="2" height="2" fill="#0a0a0a"/><rect x="7" y="13" width="1" height="1" fill="#6e6e6e"/>
  </svg>`;
  await p.setContent(`<body style="margin:0;background:transparent">${svg}</body>`);
  const el = await p.$('#h');
  await el.screenshot({ path:'./deck-house.png', omitBackground:true });
  // also a version with door same as bg removed -> make door transparent by using bg; fine
  await b.close(); console.log('house.png written');
})().catch(e=>{console.error(e);process.exit(1)});
