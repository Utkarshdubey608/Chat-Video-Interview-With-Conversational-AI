/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // ── Fortune 500 TalbotIQ palette ──────────────────────────────
        primary:   { DEFAULT: '#0d5c3a', 50: '#f0faf5', 100: '#dcf5e8', 200: '#b3e9cd', 300: '#7dd3a8', 400: '#4bb87f', 500: '#2a9e65', 600: '#1a8050', 700: '#0d5c3a', 800: '#0a4a2e', 900: '#073522' },
        accent:    { DEFAULT: '#d97706', light: '#fef3c7', pale: '#fffbeb' },
        neutral:   { 50: '#f8fafc', 100: '#f1f5f9', 200: '#e2e8f0', 300: '#cbd5e1', 400: '#94a3b8', 500: '#64748b', 600: '#475569', 700: '#334155', 800: '#1e293b', 900: '#0f172a' },
        surface:   '#ffffff',
        background:'#eff5f0',   /* green-tinted — matches screenshot */
        border:    '#dde8e0',
        success:   { DEFAULT: '#16a34a', bg: '#f0fdf4', border: '#bbf7d0' },
        warning:   { DEFAULT: '#d97706', bg: '#fffbeb', border: '#fde68a' },
        danger:    { DEFAULT: '#dc2626', bg: '#fef2f2', border: '#fecaca' },
      },
      fontFamily: {
        sans:    ['Inter', 'system-ui', 'sans-serif'],
        display: ['Inter', 'system-ui', 'sans-serif'],
        mono:    ['JetBrains Mono', 'Fira Code', 'monospace'],
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
        xs:    '0 1px 2px 0 rgb(0 0 0 / 0.05)',
        sm:    '0 1px 3px 0 rgb(0 0 0 / 0.08), 0 1px 2px -1px rgb(0 0 0 / 0.05)',
        DEFAULT:'0 2px 8px -1px rgb(0 0 0 / 0.08), 0 2px 4px -2px rgb(0 0 0 / 0.05)',
        md:    '0 4px 12px -2px rgb(0 0 0 / 0.08), 0 2px 6px -2px rgb(0 0 0 / 0.05)',
        lg:    '0 8px 24px -4px rgb(0 0 0 / 0.10), 0 4px 10px -4px rgb(0 0 0 / 0.06)',
        xl:    '0 16px 40px -8px rgb(0 0 0 / 0.12), 0 8px 16px -8px rgb(0 0 0 / 0.08)',
        inner: 'inset 0 2px 4px 0 rgb(0 0 0 / 0.06)',
        'primary-sm': '0 2px 8px -2px rgb(13 92 58 / 0.3)',
        'primary-md': '0 4px 16px -4px rgb(13 92 58 / 0.35)',
      },
      ringColor: { primary: '#0d5c3a' },
      animation: {
        'fade-in':    'fadeIn 0.25s ease',
        'slide-up':   'slideUp 0.3s ease',
        'pulse-soft': 'pulse 3s ease-in-out infinite',
        'spin-slow':  'spin 2s linear infinite',
      },
      keyframes: {
        fadeIn:  { from: { opacity: '0' }, to: { opacity: '1' } },
        slideUp: { from: { opacity: '0', transform: 'translateY(12px)' }, to: { opacity: '1', transform: 'translateY(0)' } },
      },
    },
  },
  plugins: [],
}
