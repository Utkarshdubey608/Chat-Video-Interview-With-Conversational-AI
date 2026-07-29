/**
 * Thin wrapper over the browser Web Speech API (zero cost, no key). Pure
 * utility: no React imports. The Web Speech types are not in the standard DOM
 * lib, so the minimal shape we use is declared here (strict, no `any`). Used by
 * Mimic Guide for voice input (speech-to-text).
 */

export type SpeechResult = { transcript: string; lang: string; isFinal: boolean };

interface RecognitionAlternative {
  readonly transcript: string;
}
interface RecognitionResult {
  readonly 0: RecognitionAlternative;
  readonly length: number;
  readonly isFinal: boolean;
}
interface RecognitionResultList {
  readonly length: number;
  readonly [index: number]: RecognitionResult;
}
interface RecognitionEvent {
  readonly resultIndex: number;
  readonly results: RecognitionResultList;
}
interface RecognitionErrorEvent {
  readonly error: string;
}
interface SpeechRecognitionInstance {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult: ((event: RecognitionEvent) => void) | null;
  onerror: ((event: RecognitionErrorEvent) => void) | null;
  onend: (() => void) | null;
  start: () => void;
  stop: () => void;
}
type SpeechRecognitionCtor = new () => SpeechRecognitionInstance;

declare global {
  interface Window {
    SpeechRecognition?: SpeechRecognitionCtor;
    webkitSpeechRecognition?: SpeechRecognitionCtor;
  }
}

/** True when the current browser exposes the Web Speech API. */
export function isSpeechRecognitionSupported(): boolean {
  return Boolean(window.SpeechRecognition ?? window.webkitSpeechRecognition);
}

/**
 * Start a CONTINUOUS recognition in `lang` — it keeps listening across pauses
 * until the returned stop() is called (so a brief silence no longer ends it with
 * a "no-speech" error). Emits interim results live (`isFinal:false`) and each
 * finalized chunk (`isFinal:true`) so the caller can stream text into the box.
 */
export function startSpeechRecognition(
  lang: string,
  onResult: (result: SpeechResult) => void,
  onError: (error: string) => void,
  onEnd?: () => void,
): () => void {
  const Ctor = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!Ctor) {
    onError("Speech recognition not supported in this browser.");
    return () => {};
  }

  const recognition = new Ctor();
  recognition.lang = lang;
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.onresult = (event) => {
    let finalText = "";
    let interimText = "";
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const res = event.results[i];
      if (res.isFinal) finalText += res[0].transcript;
      else interimText += res[0].transcript;
    }
    if (finalText) onResult({ transcript: finalText, isFinal: true, lang });
    if (interimText) onResult({ transcript: interimText, isFinal: false, lang });
  };
  recognition.onerror = (event) => onError(event.error);
  if (onEnd) recognition.onend = onEnd;
  recognition.start();

  return () => recognition.stop();
}
