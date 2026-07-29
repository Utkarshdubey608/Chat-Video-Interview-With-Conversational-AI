/**
 * Thin wrapper over the browser Web Speech *synthesis* API (text-to-speech) —
 * zero cost, no key, no dependency. Pure utility: no React imports. Used by
 * Mimic Guide to read answers aloud in the user's language.
 *
 * SpeechSynthesisUtterance / SpeechSynthesisVoice are part of the standard DOM
 * lib, so no custom types are needed here.
 */

export function isSpeechSynthesisSupported(): boolean {
  return typeof window !== "undefined" && "speechSynthesis" in window;
}

/** Best matching installed voice for a BCP-47 locale. Prefers exact-locale
 *  matches, and within a tier prefers neural/online voices (Google voices on
 *  Chrome, "Natural"/"Online" voices on Edge) over the robotic local defaults. */
function pickVoice(lang: string): SpeechSynthesisVoice | undefined {
  const voices = window.speechSynthesis.getVoices();
  const target = lang.toLowerCase();
  const base = target.split("-")[0];
  const candidates = voices.filter((v) => {
    const l = v.lang.toLowerCase().replace("_", "-");
    return l === target || l.split("-")[0] === base;
  });
  const score = (v: SpeechSynthesisVoice) =>
    (v.lang.toLowerCase().replace("_", "-") === target ? 2 : 0) +
    (/natural|neural|online|google/i.test(v.name) ? 1 : 0);
  return candidates.sort((a, b) => score(b) - score(a))[0];
}

/**
 * Speak `text` in `lang`. Cancels any in-progress speech first. Returns a stop
 * function. `onEnd` fires when speech finishes, errors, or is stopped.
 */
export function speak(text: string, lang: string, onEnd?: () => void): () => void {
  if (!isSpeechSynthesisSupported() || text.trim().length === 0) {
    onEnd?.();
    return () => {};
  }

  const synth = window.speechSynthesis;
  synth.cancel(); // never stack utterances

  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = lang;
  const voice = pickVoice(lang);
  if (voice) utterance.voice = voice;

  // Chrome bug: network voices stop after ~15s of continuous speech and never
  // fire onend. The standard workaround is a periodic pause()+resume() nudge
  // while speech is in progress (harmless no-op on other engines/browsers).
  const keepAlive = window.setInterval(() => {
    if (!synth.speaking) {
      window.clearInterval(keepAlive);
      return;
    }
    synth.pause();
    synth.resume();
  }, 12000);

  const done = () => {
    window.clearInterval(keepAlive);
    onEnd?.();
  };
  utterance.onend = done;
  utterance.onerror = done;

  // Voice list can load lazily; speaking still works (engine uses lang default),
  // and a late-arriving exact voice is applied on the next call.
  synth.speak(utterance);

  return () => {
    utterance.onend = null;
    utterance.onerror = null;
    window.clearInterval(keepAlive);
    synth.cancel();
  };
}

/** Stop any in-progress speech. */
export function cancelSpeech(): void {
  if (isSpeechSynthesisSupported()) window.speechSynthesis.cancel();
}
