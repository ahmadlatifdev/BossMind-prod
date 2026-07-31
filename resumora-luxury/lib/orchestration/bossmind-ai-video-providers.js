/**
 * External AI/media providers for BossMind AI Video (env-driven; never hardcode keys).
 */
const DEFAULT_DEEPSEEK_BASE = "https://api.deepseek.com";

async function deepseekScenarioFromScript({ scriptText, language = "en", channelName: channelLabel }) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) {
    throw new Error("DEEPSEEK_API_KEY is required for scenario generation");
  }
  const base = (process.env.DEEPSEEK_API_BASE || DEFAULT_DEEPSEEK_BASE).replace(/\/$/, "");
  const model = process.env.DEEPSEEK_MODEL || "deepseek-chat";
  const url = base.includes("/v1") ? `${base}/chat/completions` : `${base}/chat/completions`;

  const brand = (channelLabel || require("./bossmind-ai-video-store.js").channelName()).trim();
  const vvb = require("./vibevoyage-brand.js");
  const brandContext = vvb.getScenarioBrandContext(brand);

  const sys = `You are lead director for the "${brand}" channel (${vvb.tagline()}).
${brandContext}
Output ONE JSON object only, no markdown, with keys:
title (string), scenes (array of { index, prompt, durationSec, visualStyle }).
Language context for VO/captions: ${language}.
Script / idea:
${scriptText.slice(0, 120_000)}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: "Return only valid JSON." },
        { role: "user", content: sys },
      ],
      temperature: 0.35,
    }),
  });

  const raw = await res.text();
  if (!res.ok) {
    throw new Error(`DeepSeek HTTP ${res.status}: ${raw.slice(0, 500)}`);
  }
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error(`DeepSeek invalid JSON: ${raw.slice(0, 200)}`);
  }
  const content = data.choices?.[0]?.message?.content || "";
  const cleaned = String(content).replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  let structured;
  try {
    structured = JSON.parse(cleaned);
  } catch {
    const m = cleaned.match(/\{[\s\S]*\}/);
    if (!m) throw new Error(`DeepSeek returned non-JSON: ${cleaned.slice(0, 400)}`);
    structured = JSON.parse(m[0]);
  }
  if (!structured.scenes || !Array.isArray(structured.scenes)) {
    structured.scenes = structured.sceneList || structured.scenes || [];
  }
  if (structured.scenes.length === 0) {
    throw new Error("DeepSeek JSON missing scenes array");
  }
  return { model, structured, rawUsage: data.usage || null };
}

/**
 * Non-OpenAI TTS: ElevenLabs when configured; otherwise fail (no ChatGPT fallback).
 */
async function speechTts({ text, outPath }) {
  const elevenKey = String(process.env.ELEVENLABS_API_KEY || "").trim();
  const voiceId = process.env.ELEVENLABS_VOICE_ID || "21m00Tcm4TlvDq8ikWAM";
  if (!elevenKey) {
    throw new Error(
      "openai_removed: OpenAI TTS disabled. Set ELEVENLABS_API_KEY (or wire a speech webhook). Text AI is Kimi K3 / DeepSeek only.",
    );
  }
  const fs = require("fs");
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: {
      "xi-api-key": elevenKey,
      "Content-Type": "application/json",
      Accept: "audio/mpeg",
    },
    body: JSON.stringify({
      text: String(text || "").slice(0, 5000),
      model_id: process.env.ELEVENLABS_MODEL || "eleven_multilingual_v2",
    }),
  });
  if (!res.ok) {
    throw new Error(`ElevenLabs TTS ${res.status}: ${(await res.text()).slice(0, 300)}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(outPath, buf);
  return { bytes: buf.length, path: outPath, provider: "elevenlabs" };
}

/** @deprecated name kept for callers — routes to non-OpenAI speechTts */
async function openAiSpeechTts(opts) {
  return speechTts(opts);
}

/**
 * Non-OpenAI transcription: AssemblyAI when configured; otherwise fail (no Whisper/OpenAI).
 */
async function transcribeAudio({ audioPath }) {
  const key = String(process.env.ASSEMBLYAI_API_KEY || "").trim();
  if (!key) {
    throw new Error(
      "openai_removed: OpenAI Whisper disabled. Set ASSEMBLYAI_API_KEY for captions. Text AI is Kimi K3 / DeepSeek only.",
    );
  }
  const fs = require("fs");
  const upload = await fetch("https://api.assemblyai.com/v2/upload", {
    method: "POST",
    headers: { authorization: key, "content-type": "application/octet-stream" },
    body: fs.readFileSync(audioPath),
  });
  if (!upload.ok) {
    throw new Error(`AssemblyAI upload ${upload.status}: ${(await upload.text()).slice(0, 300)}`);
  }
  const { upload_url: uploadUrl } = await upload.json();
  const create = await fetch("https://api.assemblyai.com/v2/transcript", {
    method: "POST",
    headers: { authorization: key, "content-type": "application/json" },
    body: JSON.stringify({ audio_url: uploadUrl }),
  });
  if (!create.ok) {
    throw new Error(`AssemblyAI create ${create.status}: ${(await create.text()).slice(0, 300)}`);
  }
  const { id } = await create.json();
  for (let i = 0; i < 60; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    const poll = await fetch(`https://api.assemblyai.com/v2/transcript/${id}`, {
      headers: { authorization: key },
    });
    const j = await poll.json();
    if (j.status === "completed") return { text: j.text || "", provider: "assemblyai" };
    if (j.status === "error") throw new Error(`AssemblyAI error: ${j.error || "failed"}`);
  }
  throw new Error("AssemblyAI transcription timed out");
}

/** @deprecated name kept for callers — routes to non-OpenAI transcribeAudio */
async function openAiWhisperTranscribe(opts) {
  return transcribeAudio(opts);
}

/**
 * Delegate scene media to n8n or custom worker — POST JSON, expect { assetUrl, mime? }.
 */
async function requestSceneMediaFromWebhook({ scene, prompt, providerHint }) {
  const url = process.env.BOSSMIND_AI_VIDEO_SCENE_WEBHOOK_URL;
  const secret = process.env.BOSSMIND_AI_VIDEO_SCENE_WEBHOOK_SECRET;
  if (!url || !secret) {
    throw new Error("BOSSMIND_AI_VIDEO_SCENE_WEBHOOK_URL and BOSSMIND_AI_VIDEO_SCENE_WEBHOOK_SECRET are required for scene media");
  }
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${secret}`,
    },
    body: JSON.stringify({
      sceneId: scene.id,
      sceneIndex: scene.scene_index,
      prompt,
      providerHint: providerHint || scene.provider || null,
    }),
  });
  const body = await res.text();
  if (!res.ok) throw new Error(`Scene webhook ${res.status}: ${body.slice(0, 400)}`);
  const j = JSON.parse(body);
  if (!j.assetUrl) throw new Error("Scene webhook must return JSON { assetUrl }");
  return { assetUrl: j.assetUrl, mime: j.mime || "video/mp4", meta: j.meta || {} };
}

async function requestPublishFromWebhook({ platform, renderId, manifest }) {
  const url = process.env.BOSSMIND_AI_VIDEO_PUBLISH_WEBHOOK_URL;
  const secret = process.env.BOSSMIND_AI_VIDEO_PUBLISH_WEBHOOK_SECRET;
  if (!url || !secret) {
    throw new Error("BOSSMIND_AI_VIDEO_PUBLISH_WEBHOOK_URL and BOSSMIND_AI_VIDEO_PUBLISH_WEBHOOK_SECRET required to publish");
  }
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${secret}`,
    },
    body: JSON.stringify({ platform, renderId, manifest }),
  });
  const body = await res.text();
  if (!res.ok) throw new Error(`Publish webhook ${res.status}: ${body.slice(0, 400)}`);
  const j = JSON.parse(body);
  return { publishedUrl: j.publishedUrl || j.url || null, meta: j.meta || {} };
}

module.exports = {
  deepseekScenarioFromScript,
  speechTts,
  transcribeAudio,
  openAiSpeechTts,
  openAiWhisperTranscribe,
  requestSceneMediaFromWebhook,
  requestPublishFromWebhook,
};
