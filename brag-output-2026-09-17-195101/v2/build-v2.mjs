import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

// Voice-led kinetic type over 3D product planes. Everything sits on the 84 BPM bar grid of
// music/bolkit-lofi-84.wav (an original track rendered by music/make_music.py).
const BAR = (60 / 84) * 4;
const b = (n) => Number((n * BAR).toFixed(3));
const S1 = 0, S2 = b(1), S3 = b(3), S4 = b(5), BREAK = b(6), S5 = b(7), END = 25.0;
const XF = 0.5; // dissolve overlap between scenes
const VOICE = process.env.VOICE === "1";
const OUT = VOICE ? "composition-voice" : "composition";

const words = JSON.parse(readFileSync("words.json", "utf8"));
const VO_AT = [0.45, 3.25, 9.0, 14.7, 20.45];
const probe = (p) => Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p], { encoding: "utf8" }).trim());
const voLen = VO_AT.map((_, i) => probe(`composition/assets/vo/vo-${i + 1}.wav`));
const rms = JSON.parse(readFileSync("rms.json", "utf8")).rms;

const sfx = [
  { file: "interface/drop_002.ogg", at: 5.8, volume: 0.4 },
  { file: "interface/click_002.ogg", at: b(4), volume: 0.28 },
  { file: "interface/click_002.ogg", at: b(4) + BAR / 4, volume: 0.28 },
  { file: "impact/impactSoft_medium_001.ogg", at: S5, volume: 0.45 },
];

function musicPoints() {
  const base = VOICE ? 1 : 1;
  const duck = 0.3;
  const pts = [{ t: 0, v: 0 }, { t: 0.3, v: base }];
  if (VOICE) {
    VO_AT.forEach((at, i) => {
      const a = Math.max(0.35, at - 0.15), z = at + voLen[i] + 0.15;
      pts.push({ t: a, v: base }, { t: a + 0.15, v: duck }, { t: z, v: duck }, { t: z + 0.3, v: base });
    });
  }
  const fade = END - 1.2;
  const kept = pts.filter((p) => p.t < fade);
  kept.push({ t: fade, v: kept[kept.length - 1].v }, { t: END, v: 0 });
  return kept;
}

const MARK = "M180 520 C236 520 236 553 292 553 C342 553 342 343 392 343 C441 343 441 666 490 666 C547.5 666 547.5 469 605 469 C664.5 469 664.5 520 724 520 C757 520 757 520 790 520";

// one caption block per voice line; words become visible exactly when they are spoken
const caption = (i, cls) =>
  `<div class="cap ${cls}" id="cap-${i}">${words[i].words.map((w, j) => `<span class="w" id="w-${i}-${j}">${w.w}</span>`).join(" ")}</div>`;

const hudBars = Array.from({ length: 8 }, (_, i) => `<i id="hb-${i}"></i>`).join("");
const tBars = (p) => Array.from({ length: 5 }, (_, i) => `<i id="${p}-${i}"></i>`).join("");

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1920, height=1080" />
  <title>Bolkit, voice-led</title>
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,300..800&family=Hanken+Grotesk:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    :root { --bg:#000; --panel:#0b0b0d; --panel2:#131316; --line:#26262b; --ink:#f5f5f7; --ink2:#b6b6bd; --ink3:#8e8e96; --red:#ff453a; --green:#30d158; }
    * { margin:0; padding:0; box-sizing:border-box; }
    html, body { width:1920px; height:1080px; overflow:hidden; background:var(--bg); }
    body { font-family:"Hanken Grotesk", sans-serif; color:var(--ink); -webkit-font-smoothing:antialiased; }
    #root { position:relative; width:1920px; height:1080px; overflow:hidden; background:var(--bg); }

    #leak { position:absolute; left:-400px; top:-300px; width:2700px; height:1700px; background:linear-gradient(115deg, rgba(255,255,255,0) 30%, rgba(255,255,255,.07) 48%, rgba(255,255,255,0) 66%); }
    #motif { position:absolute; left:-240px; top:300px; width:2400px; height:1243px; opacity:.5; }
    #motif path { stroke:#2a2a30; }
    #vignette { position:absolute; inset:0; background:radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 45%, rgba(0,0,0,.75) 100%); }

    .scene { position:absolute; inset:0; }
    .stage { position:absolute; inset:0; perspective:1900px; perspective-origin:50% 38%; }
    .plane { position:absolute; transform-style:preserve-3d; }

    .cap { position:absolute; left:140px; right:140px; text-align:center; font-family:"Bricolage Grotesque", sans-serif; font-weight:700; letter-spacing:-.03em; line-height:1.05; color:var(--ink); }
    .cap .w { display:inline-block; opacity:0; }
    .cap.low { top:800px; font-size:86px; transform-origin:50% 50%; }
    .cap.mid { top:420px; font-size:150px; }

    /* s1 intro */
    #s1-kicker { position:absolute; left:0; right:0; top:330px; text-align:center; font-family:"JetBrains Mono", monospace; font-size:26px; letter-spacing:.3em; color:var(--ink3); opacity:0; }

    /* s2 dictation plane */
    #s2-plane { left:470px; top:120px; width:980px; height:560px; }
    #s2-win { position:absolute; inset:0; background:linear-gradient(180deg,#121215,#0a0a0c); border:2px solid var(--line); border-radius:28px; box-shadow:0 60px 120px rgba(0,0,0,.6); }
    #s2-to { position:absolute; left:48px; top:40px; font-family:"JetBrains Mono", monospace; font-size:24px; color:var(--ink3); }
    #s2-field { position:absolute; left:48px; right:48px; top:104px; height:250px; background:var(--panel2); border:2px solid var(--line); border-radius:18px; }
    #s2-ph { position:absolute; left:40px; top:38px; font-size:44px; color:#6e6e76; }
    #s2-text { position:absolute; left:40px; top:38px; right:40px; font-size:44px; font-weight:500; line-height:1.3; opacity:0; }
    #s2-hud { position:absolute; left:490px; top:420px; height:96px; padding:0 44px; transform:translate3d(-50%,0,120px); background:rgba(0,0,0,.9); border:3px solid rgba(255,255,255,.14); border-radius:48px; display:flex; align-items:center; gap:26px; white-space:nowrap; }
    #s2-bars { display:flex; align-items:center; gap:7px; height:58px; }
    #s2-bars i { display:block; width:7px; height:8px; border-radius:4px; background:#fff; }
    #s2-spin { width:30px; height:30px; border-radius:50%; border:4px solid rgba(255,255,255,.25); border-top-color:#fff; display:none; }
    #s2-check { width:34px; height:34px; border-radius:50%; background:var(--green); color:#000; font-size:22px; font-weight:800; display:none; align-items:center; justify-content:center; }
    #s2-label { font-size:32px; font-weight:500; color:#fff; }

    /* s3 meeting */
    #s3-notch { position:absolute; left:560px; top:0; width:800px; height:84px; background:#000; border:2px solid #1d1d21; border-top:0; border-radius:0 0 26px 26px; display:flex; align-items:center; justify-content:space-between; padding:0 46px; opacity:0; }
    #s3-rec { display:flex; align-items:center; gap:14px; }
    #s3-dot { width:18px; height:18px; border-radius:50%; background:var(--red); }
    #s3-timer { font-size:30px; font-weight:600; font-variant-numeric:tabular-nums; }
    .tw { display:flex; align-items:center; gap:14px; }
    .tw .bars { display:flex; align-items:center; gap:5px; height:40px; }
    .tw .bars i { display:block; width:6px; height:8px; border-radius:3px; background:#fff; }
    .tw .lab { font-family:"JetBrains Mono", monospace; font-size:20px; color:var(--ink3); }
    #s3-plane { left:385px; top:150px; width:1150px; height:640px; }
    #s3-crop { position:absolute; inset:0; border-radius:22px; border:2px solid var(--line); overflow:hidden; background:#000; box-shadow:0 60px 120px rgba(0,0,0,.6); }
    #s3-img { position:absolute; left:0; top:-393px; width:1150px; }
    .hl { position:absolute; left:40px; width:1070px; height:58px; border:3px solid var(--ink); border-radius:12px; opacity:0; }

    /* s4 models */
    #s4-noacc { position:absolute; left:0; right:0; top:390px; text-align:center; font-family:"Bricolage Grotesque", sans-serif; font-weight:800; font-size:220px; letter-spacing:-.045em; line-height:1; opacity:0; }
    #s4-plane { left:385px; top:130px; width:1150px; height:640px; }
    #s4-crop { position:absolute; inset:0; border-radius:22px; border:2px solid var(--line); overflow:hidden; background:#000; box-shadow:0 60px 120px rgba(0,0,0,.6); }
    #s4-img { position:absolute; left:0; top:0; width:1150px; }
    .chip { position:absolute; font-family:"JetBrains Mono", monospace; font-size:34px; padding:14px 26px; border:2px solid #3a3a40; border-radius:40px; background:rgba(12,12,14,.92); color:var(--ink); opacity:0; white-space:nowrap; }

    /* s5 outro */
    #s5-mark { position:absolute; left:660px; top:250px; width:600px; height:311px; overflow:visible; }
    #s5-word { position:absolute; left:0; right:0; top:560px; text-align:center; font-family:"Bricolage Grotesque", sans-serif; font-weight:800; font-size:190px; letter-spacing:-.04em; line-height:1; opacity:0; }
    #s5-cap { top:800px; font-size:70px; }
    #s5-meta { position:absolute; left:0; right:0; top:930px; text-align:center; font-family:"JetBrains Mono", monospace; font-size:30px; color:var(--ink2); opacity:0; }
    #s5-meta span { color:var(--ink3); }
  </style>
</head>
<body>
  <div id="root" data-composition-id="main" data-start="0" data-width="1920" data-height="1080" data-duration="${END}">
    <div id="leak"></div>
    <svg id="motif" viewBox="160 323 701 363" data-layout-allow-overflow><path id="motif-path" d="${MARK}" fill="none" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/></svg>
    <div id="vignette"></div>

    <section id="s1" class="scene clip" data-start="${S1}" data-duration="${S2 - S1 + XF}" data-track-index="1">
      <div id="s1-kicker">bolkit · for mac</div>
      ${caption(0, "mid")}
    </section>

    <section id="s2" class="scene clip" data-start="${S2}" data-duration="${S3 - S2 + XF}" data-track-index="2">
      <div class="stage"><div class="plane" id="s2-plane">
        <div id="s2-win">
          <div id="s2-to">to: team standup</div>
          <div id="s2-field"><div id="s2-ph" data-layout-allow-overlap>Message</div><div id="s2-text" data-layout-allow-overlap>kal ka standup 10 baje shift kar do, sab log free hain</div></div>
        </div>
        <div id="s2-hud" data-layout-allow-overlap><div id="s2-bars">${hudBars}</div><div id="s2-spin"></div><div id="s2-check">✓</div><div id="s2-label">Listening</div></div>
      </div></div>
      ${caption(1, "low")}
    </section>

    <section id="s3" class="scene clip" data-start="${S3}" data-duration="${S4 - S3 + XF}" data-track-index="3">
      <div id="s3-notch">
        <div id="s3-rec"><div id="s3-dot"></div><div id="s3-timer">14:00</div></div>
        <div class="tw"><span class="lab">you</span><div class="bars">${tBars("ty")}</div></div>
        <div class="tw"><span class="lab">others</span><div class="bars">${tBars("to")}</div></div>
      </div>
      <div class="stage"><div class="plane" id="s3-plane">
        <div id="s3-crop"><img id="s3-img" src="assets/ui/meeting-Transcript.png" alt="" data-layout-allow-overflow />
          <div class="hl" id="hl-1" style="top:122px"></div><div class="hl" id="hl-2" style="top:201px"></div>
        </div>
      </div></div>
      ${caption(2, "low")}
    </section>

    <section id="s4" class="scene clip" data-start="${S4}" data-duration="${S5 - S4 + XF}" data-track-index="4">
      <div class="stage"><div class="plane" id="s4-plane">
        <div id="s4-crop"><img id="s4-img" src="assets/ui/models.png" alt="" data-layout-allow-overflow /></div>
        <div class="chip" id="chip-0" style="left:-70px; top:120px;" data-layout-allow-overlap>apple speech</div>
        <div class="chip" id="chip-1" style="left:880px; top:260px;" data-layout-allow-overlap>parakeet</div>
        <div class="chip" id="chip-2" style="left:120px; top:470px;" data-layout-allow-overlap>gemma on mlx</div>
      </div></div>
      ${caption(3, "low")}
      <div id="s4-noacc">no account.</div>
    </section>

    <section id="s5" class="scene clip" data-start="${S5}" data-duration="${END - S5}" data-track-index="5">
      <svg id="s5-mark" viewBox="160 323 701 363"><path id="s5-wave" d="${MARK}" fill="none" stroke="#f5f5f7" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/><rect id="s5-bar" x="821" y="426" width="40" height="170" rx="20" fill="#f5f5f7"/></svg>
      <div id="s5-word">Bolkit</div>
      ${caption(4, "low").replace('class="cap low"', 'class="cap low" style="top:760px; font-size:70px;"')}
      <div id="s5-meta">mac app out now · github.com/kumard3/scribe <span>· iphone coming soon</span></div>
    </section>

    <audio id="music" src="assets/music/bolkit-lofi-84.wav" data-start="0" data-duration="${END}" data-track-index="10" data-volume="${VOICE ? 0.55 : 0.7}" data-automation='${JSON.stringify({ version: 1, lanes: [{ target: "volume", points: musicPoints() }] })}'></audio>
${VOICE ? VO_AT.map((at, i) => `    <audio id="vo-${i + 1}" src="assets/vo/vo-${i + 1}.wav" data-start="${at}" data-duration="${Math.floor(voLen[i] * 1000) / 1000}" data-track-index="${20 + i}" data-volume="1"></audio>`).join("\n") : ""}
${sfx.map((s, i) => `    <audio id="sfx-${i + 1}" src="assets/sfx/${s.file}" data-start="${s.at}" data-duration="${Math.floor(probe(`${OUT}/assets/sfx/${s.file}`) * 1000) / 1000}" data-track-index="${30 + i}" data-volume="${s.volume}"></audio>`).join("\n")}
  </div>

  <script>
    const WORDS = ${JSON.stringify(words.map((l) => l.words.map((w) => w.t0)))};
    const VO_AT = ${JSON.stringify(VO_AT)};
    const RMS = ${JSON.stringify(rms)};
    const S1 = ${S1}, S2 = ${S2}, S3 = ${S3}, S4 = ${S4}, BREAK = ${BREAK}, S5 = ${S5}, END = ${END}, XF = ${XF}, BAR = ${BAR};
    const tl = gsap.timeline({ paused: true });

    // background: drifting light leak, the brand wave as a giant slow line, subtle music-driven presence
    tl.fromTo("#leak", { x: -260 }, { x: 260, duration: END, ease: "sine.inOut" }, 0);
    const motif = document.getElementById("motif-path");
    const mLen = motif.getTotalLength();
    motif.setAttribute("stroke-dasharray", String(mLen));
    tl.fromTo("#motif-path", { attr: { "stroke-dashoffset": mLen } }, { attr: { "stroke-dashoffset": 0 }, duration: 2.6, ease: "power2.inOut" }, 0.1);
    tl.fromTo("#motif", { x: 0, y: 0 }, { x: -120, y: 20, duration: END, ease: "none" }, 0);
    for (let f = 0; f < RMS.length && f / 30 < END; f += 2) {
      tl.call(((v) => () => { document.getElementById("motif").style.opacity = String(0.35 + v * 0.4); })(RMS[f]), [], f / 30);
    }

    // words appear as they are spoken: blur to sharp, small rise
    WORDS.forEach((times, i) => {
      times.forEach((t0, j) => {
        tl.fromTo("#w-" + i + "-" + j, { opacity: 0, y: 26, filter: "blur(12px)" }, { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.28, ease: "power3.out" }, VO_AT[i] + t0);
      });
    });

    // scene dissolves on the bar lines
    function dissolveIn(sel, t) { tl.fromTo(sel, { opacity: 0, filter: "blur(18px)" }, { opacity: 1, filter: "blur(0px)", duration: XF, ease: "power2.out" }, t); }
    function dissolveOut(sel, t) { tl.to(sel, { opacity: 0, filter: "blur(18px)", duration: XF, ease: "power2.in" }, t); }
    dissolveOut("#s1", S2); dissolveIn("#s2", S2);
    dissolveOut("#s2", S3); dissolveIn("#s3", S3);
    dissolveOut("#s4", S5); dissolveIn("#s4", S4); dissolveOut("#s3", S4);
    dissolveIn("#s5", S5);

    // s1
    tl.fromTo("#s1-kicker", { opacity: 0, y: 12 }, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out" }, 0.2);

    // s2: plane settles in 3D, pill listens, Hinglish lands
    tl.fromTo("#s2-plane", { rotationX: 26, rotationY: -30, rotationZ: 4, z: -260 }, { rotationX: 14, rotationY: -14, rotationZ: 2, z: 0, duration: S3 - S2 + XF, ease: "power2.out" }, S2);
    const level = (t) => Math.max(0, Math.min(1, 0.25 + 0.45 * Math.abs(Math.sin(t * 7.1)) * (0.6 + 0.4 * Math.sin(t * 2.3 + 1)) + 0.2 * Math.abs(Math.sin(t * 13.7))));
    const hw = [0.35, 0.6, 0.85, 1.0, 0.7, 0.9, 0.55, 0.3];
    const st = { p: 0 };
    tl.fromTo(st, { p: 0 }, { p: 1, duration: 5.3 - S2, ease: "none", onUpdate: () => {
      const t = S2 + st.p * (5.3 - S2);
      hw.forEach((w, i) => { document.getElementById("hb-" + i).style.height = (8 + level(t) * 44 * w) + "px"; });
    } }, S2);
    tl.set("#s2-bars", { display: "flex" }, 0); tl.set("#s2-spin", { display: "none" }, 0); tl.set("#s2-check", { display: "none" }, 0); tl.set("#s2-label", { textContent: "Listening" }, 0);
    tl.set("#s2-bars", { display: "none" }, 5.3); tl.set("#s2-spin", { display: "block" }, 5.3); tl.set("#s2-label", { textContent: "Transcribing…" }, 5.3);
    tl.fromTo("#s2-spin", { rotation: 0 }, { rotation: 360, duration: 0.5, ease: "none" }, 5.3);
    tl.set("#s2-spin", { display: "none" }, 5.8); tl.set("#s2-check", { display: "flex" }, 5.8); tl.set("#s2-label", { textContent: "Inserted" }, 5.8);
    tl.to("#s2-ph", { opacity: 0, duration: 0.1 }, 5.8);
    tl.fromTo("#s2-text", { opacity: 0, y: 12 }, { opacity: 1, y: 0, duration: 0.35, ease: "power3.out" }, 5.8);

    // s3: notch recorder, then the real transcript swings in and names light up on the beat
    tl.fromTo("#s3-notch", { opacity: 0, y: -30 }, { opacity: 1, y: 0, duration: 0.45, ease: "power3.out" }, S3 + 0.1);
    const nt = { p: 0 };
    tl.fromTo(nt, { p: 0 }, { p: 1, duration: S4 - S3, ease: "none", onUpdate: () => {
      const t = S3 + nt.p * (S4 - S3);
      document.getElementById("s3-timer").textContent = "14:0" + Math.min(9, Math.floor(t - S3));
      const you = Math.max(0, level(t * 1.3) - 0.35) * 1.4, oth = level(t + 5);
      [0.45, 0.8, 1.0, 0.7, 0.4].forEach((k, i) => {
        document.getElementById("ty-" + i).style.height = (8 + you * 30 * k) + "px";
        document.getElementById("to-" + i).style.height = (8 + oth * 30 * k) + "px";
      });
    } }, S3);
    tl.fromTo("#s3-plane", { rotationX: 30, rotationY: 34, rotationZ: -3, z: -420, opacity: 0 }, { rotationX: 12, rotationY: 12, rotationZ: -1, z: 0, opacity: 1, duration: 1.4, ease: "power3.out" }, S3 + 0.4);
    tl.to("#s3-plane", { rotationY: 4, duration: S4 - S3 - 1.8, ease: "sine.inOut" }, S3 + 1.8);
    tl.fromTo("#hl-1", { opacity: 0 }, { opacity: 1, duration: 0.2 }, ${b(4)});
    tl.fromTo("#hl-2", { opacity: 0 }, { opacity: 1, duration: 0.2 }, ${b(4) + BAR / 4});

    // s4: models plane scrolls, chips pop on the beats, then the breakdown clears the stage
    tl.fromTo("#s4-plane", { rotationX: 22, rotationY: -26, z: -300 }, { rotationX: 10, rotationY: -8, z: 0, duration: BREAK - S4, ease: "power2.out" }, S4);
    tl.fromTo("#s4-img", { y: 0 }, { y: -230, duration: BREAK - S4, ease: "sine.inOut" }, S4);
    [0, 1, 2].forEach((i) => tl.fromTo("#chip-" + i, { opacity: 0, z: 160, scale: 0.8 }, { opacity: 1, z: 60, scale: 1, duration: 0.35, ease: "back.out(2)" }, S4 + (i + 1) * BAR / 4));
    tl.to("#s4 .stage", { opacity: 0, filter: "blur(16px)", scale: 0.94, duration: 0.6, ease: "power2.in" }, BREAK);
    tl.to("#cap-3", { opacity: 0, y: -40, filter: "blur(10px)", duration: 0.45, ease: "power2.in" }, BREAK);
    tl.fromTo("#s4-noacc", { opacity: 0, scale: 0.86, filter: "blur(14px)" }, { opacity: 1, scale: 1, filter: "blur(0px)", duration: 0.7, ease: "expo.out" }, BREAK + 0.25);
    tl.to("#s4-noacc", { scale: 1.06, duration: S5 - BREAK - 0.95, ease: "none" }, BREAK + 0.95);

    // s5: the mark draws, wordmark, last line, facts
    const wave = document.getElementById("s5-wave");
    const wLen = wave.getTotalLength();
    wave.setAttribute("stroke-dasharray", String(wLen));
    tl.fromTo("#s5-wave", { attr: { "stroke-dashoffset": wLen } }, { attr: { "stroke-dashoffset": 0 }, duration: 0.9, ease: "power2.inOut" }, S5 + 0.1);
    tl.fromTo("#s5-bar", { opacity: 0 }, { opacity: 1, duration: 0.2 }, S5 + 0.9);
    tl.fromTo("#s5-word", { opacity: 0, y: 30, filter: "blur(10px)" }, { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.6, ease: "power3.out" }, S5 + 0.5);
    tl.fromTo("#s5-meta", { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out" }, ${b(8)});

    window.__timelines["main"] = tl;
  </script>
</body>
</html>
`;

writeFileSync(`${OUT}/index.html`, html);
console.log(`wrote ${OUT}/index.html${VOICE ? " (voiced)" : ""}`);
