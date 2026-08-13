/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // ── Mimic violet brand — inherited from the parent (Eightfold AI):
        //    violet→magenta spectrum, mint action accent, lavender neutrals.
        //    One system across marketing, workspace, and candidate surfaces.
        primary:   { DEFAULT: '#6B2BE0', 50: '#F8F5FE', 100: '#F0E9FD', 200: '#E0D4FB', 300: '#C9B3F7', 400: '#A985F2', 500: '#8B5CF0', 600: '#7A45EA', 700: '#6B2BE0', 800: '#4A1BA8', 900: '#2A1259' },
        magenta:   { DEFAULT: '#C42C93', light: '#D93BA8', bg: '#FCEBF6', border: '#F5CBE7' },
        mint:      { DEFAULT: '#8FE3D0', hover: '#79D9C3', ink: '#0F7A66', bg: '#E9FAF5', border: '#BFF0E3' },
        accent:    { DEFAULT: '#d97706', light: '#fef3c7', pale: '#fffbeb' },
        // Violet-toned neutral ramp — replaces the old slate grays so even
        // "gray" text carries the brand undertone.
        // 400/500 are darkened from the first draft so hint, placeholder and
        // secondary text clear WCAG AA (4.5:1) on white AND on the tinted app
        // ground. 300 and below stay decorative (borders, tracks) only.
        neutral:   { 50: '#FAF9FD', 100: '#F3F1F9', 200: '#E7E2F2', 300: '#D2CBE4', 400: '#746C8B', 500: '#645C7B', 600: '#524A69', 700: '#4A4460', 800: '#2E2749', 900: '#1B0B3B' },
        surface:   '#ffffff',
        background:'#F7F5FB',   /* lavender-neutral app ground */
        border:    '#E7E2F2',
        success:   { DEFAULT: '#0F7A5F', bg: '#E4F6F0', border: '#B8E8D8' },
        warning:   { DEFAULT: '#B45309', bg: '#FDF3E2', border: '#F5D9A8' },
        danger:    { DEFAULT: '#dc2626', bg: '#fef2f2', border: '#fecaca' },
        // ── Dark interview UI tokens (AI Avatar Screening) ─────────────
        // Same key names as the old gold-on-black theme, so every consumer
        // re-skins to the violet-dark world without touching a component.
        brand: {
          black:        '#0E0620',
          gold:         '#B98CFF',
          'gold-light': '#E4D8FB',
          green:        '#2FBF9F',
          'green-light':'#8FE3D0',
          border:       '#332154',
          card:         '#1D1038',
          gray:         '#9D93B8',
        },
        // ── Hume AI emotion dashboard tokens (light theme) ────────────
        hume: {
          base:    '#F7F5FB',
          surface: '#ffffff',
          card:    '#FAF9FD',
          border:  '#E7E2F2',
          gold:    '#b45309',
          teal:    '#0d9488',
          coral:   '#dc2626',
          indigo:  '#4f46e5',
          amber:   '#d97706',
          muted:   '#645C7B',   /* matches neutral-500 — clears AA as text */
          text:    '#1B0B3B',
          live:    '#0F7A5F',
        },
      },
      fontFamily: {
        sans:    ['Figtree', 'Roboto', 'system-ui', 'sans-serif'],
        display: ['Figtree', 'system-ui', 'sans-serif'],
        mono:    ['Roboto Mono', 'monospace'],
        head:    ['Figtree', 'system-ui', 'sans-serif'],
      },
      fontSize: {
        '2xs': ['0.625rem', { lineHeight: '1rem' }],
        xs:    ['0.75rem',  { lineHeight: '1.125rem' }],
        sm:    ['0.875rem', { lineHeight: '1.375rem' }],
        base:  ['1rem',     { lineHeight: '1.625rem' }],
        lg:    ['1.125rem', { lineHeight: '1.75rem' }],
        xl:    ['1.25rem',  { lineHeight: '1.875rem' }],
        '2xl': ['1.5rem',   { lineHeight: '2rem' }],
        '3xl': ['1.875rem', { lineHeight: '2.375rem' }],
        '4xl': ['2.25rem',  { lineHeight: '2.75rem', letterSpacing: '-0.02em' }],
        '5xl': ['3rem',     { lineHeight: '1.2', letterSpacing: '-0.03em' }],
      },
      spacing: {
        '4.5': '1.125rem',
        '13': '3.25rem',
        '15': '3.75rem',
        '18': '4.5rem',
      },
      borderRadius: {
        sm:   '4px',
        DEFAULT: '6px',
        md:   '8px',
        lg:   '10px',
        xl:   '12px',
        '2xl':'16px',
        '3xl':'20px',
      },
      boxShadow: {
        // Ink-toned (violet-black) shadows — offset + soft blur, never a halo.
        xs:    '0 1px 2px 0 rgb(27 11 59 / 0.05)',
        sm:    '0 1px 3px 0 rgb(27 11 59 / 0.07), 0 1px 2px -1px rgb(27 11 59 / 0.05)',
        DEFAULT:'0 2px 8px -1px rgb(27 11 59 / 0.07), 0 2px 4px -2px rgb(27 11 59 / 0.05)',
        md:    '0 4px 12px -2px rgb(27 11 59 / 0.08), 0 2px 6px -2px rgb(27 11 59 / 0.05)',
        lg:    '0 8px 24px -4px rgb(27 11 59 / 0.10), 0 4px 10px -4px rgb(27 11 59 / 0.06)',
        xl:    '0 16px 40px -8px rgb(27 11 59 / 0.14), 0 8px 16px -8px rgb(27 11 59 / 0.08)',
        inner: 'inset 0 2px 4px 0 rgb(27 11 59 / 0.06)',
        'primary-sm': '0 2px 8px -2px rgb(107 43 224 / 0.3)',
        'primary-md': '0 4px 16px -4px rgb(107 43 224 / 0.35)',
        'mint-sm':    '0 2px 10px -2px rgb(15 122 102 / 0.35)',
      },
      backgroundImage: {
        // The parent brand's signature gradient — full-bleed fields + accents.
        'brand-field': 'linear-gradient(132deg,#6D3BE8 0%,#8B34D6 44%,#C42C93 100%)',
        'brand-band':  'linear-gradient(90deg,#5B6FE8 0%,#8B3FD9 50%,#D93BA8 100%)',
      },
      ringColor: { primary: '#6B2BE0' },
      zIndex: { '5': '5' },
      animation: {
        'fade-in':       'fadeIn 0.25s ease',
        'slide-up':      'slideUp 0.3s ease',
        'pulse-soft':    'pulse 3s ease-in-out infinite',
        'spin-slow':     'spin 2s linear infinite',
        'pulse-live':    'pulseLive 1.5s ease-in-out infinite',
        'radar-expand':  'radarExpand 0.6s ease-out forwards',
        'count-up':      'countUp 0.4s ease-out forwards',
        'slide-in-right':'slideInRight 0.35s ease-out forwards',
        'typing-dot':   'typingDot 1.4s ease-in-out infinite',
      },
      keyframes: {
        fadeIn:        { from: { opacity: '0' }, to: { opacity: '1' } },
        slideUp:       { from: { opacity: '0', transform: 'translateY(12px)' }, to: { opacity: '1', transform: 'translateY(0)' } },
        pulseLive:     { '0%, 100%': { opacity: '1', transform: 'scale(1)' }, '50%': { opacity: '0.6', transform: 'scale(1.15)' } },
        radarExpand:   { from: { transform: 'scale(0.6)', opacity: '0' }, to: { transform: 'scale(1)', opacity: '1' } },
        countUp:       { from: { opacity: '0', transform: 'translateY(8px)' }, to: { opacity: '1', transform: 'translateY(0)' } },
        slideInRight:  { from: { opacity: '0', transform: 'translateX(20px)' }, to: { opacity: '1', transform: 'translateX(0)' } },
        // Typing indicator — opacity only. Bounce/elastic easing reads dated.
        typingDot:     { '0%, 60%, 100%': { opacity: '0.3' }, '30%': { opacity: '1' } },
      },
    },
  },
  plugins: [],
}
