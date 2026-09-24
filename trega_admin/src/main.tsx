import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { configError } from './lib/firebase'
import App from './App.tsx'

const rootEl = document.getElementById('root')!

if (configError) {
  // Missing .env (npm run setup never ran) — say so instead of a blank page.
  rootEl.innerHTML =
    '<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#1c1917;padding:16px;font-family:system-ui,sans-serif">' +
    '<div style="max-width:24rem;background:#fff;border-radius:16px;padding:32px;box-shadow:0 25px 50px -12px rgba(0,0,0,.5)">' +
    '<h1 style="font-size:18px;font-weight:700;color:#1c1917;margin:0 0 8px">Trega Admin — setup needed</h1>' +
    '<p style="font-size:14px;color:#57534e;margin:0 0 12px">' +
    configError +
    '</p>' +
    '<code style="display:block;font-size:12px;background:#f5f5f4;border-radius:8px;padding:8px 12px;color:#44403c">cd trega_admin<br>npm run setup<br>npm run dev</code>' +
    '</div></div>'
} else {
  createRoot(rootEl).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
}
