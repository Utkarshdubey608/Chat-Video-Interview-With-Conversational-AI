import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import MimicIntro from './features/intro/MimicIntro'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
    {/* Additive, play-once cinematic splash mounted above the app. Non-blocking:
        the app boots and is interactive underneath; the overlay fades out and
        unmounts when the film ends, is skipped, or (fallback) after a hold. */}
    <MimicIntro />
  </React.StrictMode>,
)
