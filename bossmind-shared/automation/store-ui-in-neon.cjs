const { Client } = require("pg");

(async () => {
  const client = new Client({
    connectionString: process.env.NEON_DATABASE_URL || process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });
  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_ui_memory (
      id SERIAL PRIMARY KEY,
      ui_key TEXT UNIQUE,
      ui_content TEXT,
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resumora  Premium Resume Services</title>
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body { font-family: system-ui, sans-serif; background:#07111f; color:white; }
        .container { max-width:1200px; margin:0 auto; padding:0 24px; }
        .flex { display:flex; justify-content:space-between; align-items:center; }
        .logo { font-size:1.8rem; font-weight:bold; color:#fbbf24; }
        .btn-lang { background:transparent; border:1px solid #fbbf24; color:#fbbf24; padding:8px 20px; border-radius:9999px; cursor:pointer; }
        .hero { text-align:center; padding:60px 0; }
        .hero h1 { font-size:3rem; color:#fbbf24; margin-bottom:16px; }
        .hero p { font-size:1.2rem; color:#9ca3af; max-width:600px; margin:0 auto; }
        .features { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:16px; margin:60px 0; }
        .feature-card { border:1px solid rgba(251,191,36,0.3); background:rgba(255,255,255,0.05); padding:20px; text-align:center; border-radius:16px; }
        .pricing { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:30px; margin:60px 0; }
        .plan { border:1px solid rgba(251,191,36,0.4); background:rgba(255,255,255,0.05); border-radius:24px; padding:32px; text-align:center; }
        .plan.popular { transform:scale(1.02); background:rgba(251,191,36,0.1); border-color:#fbbf24; }
        .price { font-size:3rem; font-weight:bold; color:#fbbf24; margin:16px 0; }
        .btn-plan { background:#fbbf24; color:#07111f; border:none; padding:12px 28px; border-radius:9999px; font-weight:bold; cursor:pointer; margin-top:20px; }
        footer { text-align:center; padding:32px 0; border-top:1px solid rgba(251,191,36,0.2); color:#6b7280; margin-top:40px; }
        @media (max-width:768px){ .hero h1 { font-size:2rem; } }
    </style>
</head>
<body>
<div class="container">
    <div class="flex" style="padding:24px 0; border-bottom:1px solid rgba(251,191,36,0.2);">
        <div class="logo">RESUMORA</div>
        <button class="btn-lang" id="toggleLang">FR</button>
    </div>
    <div id="hero" class="hero">
        <h1 id="heroTitle">Premium Resume & Career Services</h1>
        <p id="heroSub">Professional bilingual resume, cover letter, LinkedIn optimization, and interview preparation.</p>
    </div>
    <div id="features" class="features"></div>
    <div id="pricing" class="pricing"></div>
    <footer id="footer"> 2026 Resumora  All rights reserved</footer>
</div>
<script>
const content = {
  en: {
    heroTitle:"Premium Resume & Career Services",
    heroSub:"Professional bilingual resume, cover letter, LinkedIn optimization, and interview preparation.",
    features:["ATS Optimized Resume","Cover Letter","LinkedIn Optimization","Interview Preparation","EN/FR Translation"],
    plans:[{name:"Basic",price:"$19",popular:false},{name:"Professional",price:"$49",popular:true},{name:"Elite",price:"$99",popular:false}],
    button:"Choose Plan",
    footer:" 2026 Resumora  All rights reserved"
  },
  fr: {
    heroTitle:"Services Premium de CV et Carrière",
    heroSub:"CV bilingue, lettre de motivation, optimisation LinkedIn, et préparation aux entretiens.",
    features:["CV optimisé ATS","Lettre de motivation","Optimisation LinkedIn","Préparation entretien","Traduction EN/FR"],
    plans:[{name:"Basique",price:"19",popular:false},{name:"Professionnel",price:"49",popular:true},{name:"Élite",price:"99",popular:false}],
    button:"Choisir",
    footer:" 2026 Resumora  Tous droits réservés"
  }
};
let lang='en';
function render(){
  const d=content[lang];
  document.getElementById('heroTitle').innerText=d.heroTitle;
  document.getElementById('heroSub').innerText=d.heroSub;
  document.getElementById('footer').innerHTML=d.footer;
  document.getElementById('features').innerHTML=d.features.map(f=>'<div class="feature-card">'+f+'</div>').join('');
  document.getElementById('pricing').innerHTML=d.plans.map(p=>'<div class="plan'+(p.popular?' popular':'')+'"><h3>'+p.name+'</h3><div class="price">'+p.price+'</div><button class="btn-plan">'+d.button+'</button></div>').join('');
  document.getElementById('toggleLang').innerText=lang==='en'?'FR':'EN';
}
document.getElementById('toggleLang').addEventListener('click',()=>{lang=lang==='en'?'fr':'en';render();});
render();
</script>
</body>
</html>`;

  await client.query(`
    INSERT INTO bossmind_ui_memory (ui_key, ui_content)
    VALUES ('resumora_luxury_ui', $1)
    ON CONFLICT (ui_key) DO UPDATE SET ui_content = EXCLUDED.ui_content, updated_at = NOW()
  `, [html]);

  console.log("UI_STORED_IN_NEON");
  await client.end();
})();
