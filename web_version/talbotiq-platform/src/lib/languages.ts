/**
 * Single source of truth for the 55 languages offered by the Mimic Guide
 * voice-input / voice-output selector. Mirrors the Xeno Guide language list so
 * TTS and STT cover the same set. `code` is a Google Translate / BCP-47 base code.
 */

export type Language = {
  /** Google Translate / BCP-47 code. */
  code: string;
  /** Flag emoji (representative, not strictly 1:1 with the language). */
  flag: string;
  /** English name. */
  name: string;
  /** Endonym (native name). */
  native: string;
};

export const LANGUAGES: Language[] = [
  { code: "en", flag: "🇬🇧", name: "English", native: "English" },
  { code: "hi", flag: "🇮🇳", name: "Hindi", native: "हिन्दी" },
  { code: "mr", flag: "🇮🇳", name: "Marathi", native: "मराठी" },
  { code: "ta", flag: "🇮🇳", name: "Tamil", native: "தமிழ்" },
  { code: "te", flag: "🇮🇳", name: "Telugu", native: "తెలుగు" },
  { code: "kn", flag: "🇮🇳", name: "Kannada", native: "ಕನ್ನಡ" },
  { code: "ml", flag: "🇮🇳", name: "Malayalam", native: "മലയാളം" },
  { code: "gu", flag: "🇮🇳", name: "Gujarati", native: "ગુજરાતી" },
  { code: "pa", flag: "🇮🇳", name: "Punjabi", native: "ਪੰਜਾਬੀ" },
  { code: "bn", flag: "🇮🇳", name: "Bengali", native: "বাংলা" },
  { code: "ur", flag: "🇵🇰", name: "Urdu", native: "اردو" },
  { code: "zh", flag: "🇨🇳", name: "Chinese (Simplified)", native: "中文" },
  { code: "zh-TW", flag: "🇹🇼", name: "Chinese (Traditional)", native: "繁體中文" },
  { code: "ja", flag: "🇯🇵", name: "Japanese", native: "日本語" },
  { code: "ko", flag: "🇰🇷", name: "Korean", native: "한국어" },
  { code: "ar", flag: "🇸🇦", name: "Arabic", native: "العربية" },
  { code: "fa", flag: "🇮🇷", name: "Persian", native: "فارسی" },
  { code: "tr", flag: "🇹🇷", name: "Turkish", native: "Türkçe" },
  { code: "ru", flag: "🇷🇺", name: "Russian", native: "Русский" },
  { code: "uk", flag: "🇺🇦", name: "Ukrainian", native: "Українська" },
  { code: "pl", flag: "🇵🇱", name: "Polish", native: "Polski" },
  { code: "cs", flag: "🇨🇿", name: "Czech", native: "Čeština" },
  { code: "sk", flag: "🇸🇰", name: "Slovak", native: "Slovenčina" },
  { code: "ro", flag: "🇷🇴", name: "Romanian", native: "Română" },
  { code: "hu", flag: "🇭🇺", name: "Hungarian", native: "Magyar" },
  { code: "de", flag: "🇩🇪", name: "German", native: "Deutsch" },
  { code: "fr", flag: "🇫🇷", name: "French", native: "Français" },
  { code: "es", flag: "🇪🇸", name: "Spanish", native: "Español" },
  { code: "pt", flag: "🇧🇷", name: "Portuguese", native: "Português" },
  { code: "it", flag: "🇮🇹", name: "Italian", native: "Italiano" },
  { code: "nl", flag: "🇳🇱", name: "Dutch", native: "Nederlands" },
  { code: "sv", flag: "🇸🇪", name: "Swedish", native: "Svenska" },
  { code: "no", flag: "🇳🇴", name: "Norwegian", native: "Norsk" },
  { code: "da", flag: "🇩🇰", name: "Danish", native: "Dansk" },
  { code: "fi", flag: "🇫🇮", name: "Finnish", native: "Suomi" },
  { code: "el", flag: "🇬🇷", name: "Greek", native: "Ελληνικά" },
  { code: "he", flag: "🇮🇱", name: "Hebrew", native: "עברית" },
  { code: "id", flag: "🇮🇩", name: "Indonesian", native: "Bahasa Indonesia" },
  { code: "ms", flag: "🇲🇾", name: "Malay", native: "Bahasa Melayu" },
  { code: "th", flag: "🇹🇭", name: "Thai", native: "ภาษาไทย" },
  { code: "vi", flag: "🇻🇳", name: "Vietnamese", native: "Tiếng Việt" },
  { code: "fil", flag: "🇵🇭", name: "Filipino", native: "Filipino" },
  { code: "sw", flag: "🇰🇪", name: "Swahili", native: "Kiswahili" },
  { code: "af", flag: "🇿🇦", name: "Afrikaans", native: "Afrikaans" },
  { code: "am", flag: "🇪🇹", name: "Amharic", native: "አማርኛ" },
  { code: "az", flag: "🇦🇿", name: "Azerbaijani", native: "Azərbaycan" },
  { code: "be", flag: "🇧🇾", name: "Belarusian", native: "Беларуская" },
  { code: "bg", flag: "🇧🇬", name: "Bulgarian", native: "Български" },
  { code: "bs", flag: "🇧🇦", name: "Bosnian", native: "Bosanski" },
  { code: "ca", flag: "🇪🇸", name: "Catalan", native: "Català" },
  { code: "hr", flag: "🇭🇷", name: "Croatian", native: "Hrvatski" },
  { code: "lt", flag: "🇱🇹", name: "Lithuanian", native: "Lietuvių" },
  { code: "lv", flag: "🇱🇻", name: "Latvian", native: "Latviešu" },
  { code: "sr", flag: "🇷🇸", name: "Serbian", native: "Српски" },
  { code: "sl", flag: "🇸🇮", name: "Slovenian", native: "Slovenščina" },
];

/** Quick lookup of a language by code. */
export function findLanguage(code: string): Language | undefined {
  return LANGUAGES.find((language) => language.code === code);
}
