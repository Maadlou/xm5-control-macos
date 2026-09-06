import { useEffect, useRef, useState } from 'react'
import shotAmbient from '@/imports/Screenshot_2026-09-06_at_4.37.50_AM.png'
import headphonesAngle from '@/imports/01_f1c833504-removebg-preview.png'
import headphonesFront from '@/imports/image.png'
import popoverSettings from '@/imports/image-2.png'
import popoverDisconnected from '@/imports/image-1.png'

// ─── Constants ────────────────────────────────────────────────────────────────
const ACCENT = '#d4b896'
const ACCENT_DIM = 'rgba(212,184,150,'

// ─── Hooks ───────────────────────────────────────────────────────────────────
function useInView(threshold = 0.14) {
  const ref = useRef<HTMLDivElement>(null)
  const [inView, setInView] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const obs = new IntersectionObserver(
      ([e]) => { if (e.isIntersecting) setInView(true) },
      { threshold }
    )
    obs.observe(el)
    return () => obs.disconnect()
  }, [])
  return { ref, inView }
}

function fi(inView: boolean, delay = 0): React.CSSProperties {
  return {
    opacity: inView ? 1 : 0,
    transform: inView ? 'none' : 'translateY(22px)',
    transition: `opacity 0.8s ease ${delay}ms, transform 0.8s ease ${delay}ms`,
  }
}

// ─── Icons ────────────────────────────────────────────────────────────────────
function IconHeadphones({ size = 16, color = ACCENT }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <path d="M3.5 9C3.5 5.686 5.462 3 8 3s4.5 2.686 4.5 6" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
      <rect x="2" y="8.5" width="3" height="4.5" rx="1.5" fill={color} />
      <rect x="11" y="8.5" width="3" height="4.5" rx="1.5" fill={color} />
    </svg>
  )
}

function IconGitHub({ size = 16, color = 'currentColor' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill={color}>
      <path fillRule="evenodd" d="M8 .25a7.75 7.75 0 00-2.45 15.1c.39.07.53-.17.53-.37l-.01-1.31c-2.15.47-2.6-1.04-2.6-1.04-.35-.9-.86-1.14-.86-1.14-.7-.48.05-.47.05-.47.78.06 1.19.8 1.19.8.69 1.18 1.81.84 2.25.64.07-.5.27-.84.49-1.03-1.72-.2-3.53-.86-3.53-3.82 0-.84.3-1.53.79-2.07-.08-.2-.34-1 .08-2.07 0 0 .65-.21 2.12.79A7.38 7.38 0 018 4.04c.66 0 1.32.09 1.94.26 1.47-1 2.12-.79 2.12-.79.42 1.07.16 1.87.08 2.07.49.54.79 1.23.79 2.07 0 2.97-1.81 3.62-3.54 3.81.28.24.52.71.52 1.43l-.01 2.12c0 .21.14.45.54.37A7.75 7.75 0 008 .25z" />
    </svg>
  )
}

function IconApple({ size = 13, color = 'currentColor' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 17" fill={color}>
      <path d="M13.07 12.26c-.3.93-.7 1.75-1.22 2.47-.64.92-1.16 1.56-1.56 1.92-.62.57-1.29.87-2.02.88-.52 0-1.14-.15-1.87-.44-.74-.3-1.42-.44-2.03-.44-.64 0-1.34.15-2.1.44-.75.3-1.36.46-1.82.47-.7.03-1.4-.28-2.1-.92-.44-.39-.98-1.06-1.64-2.01C.25 13.5 0 12.44 0 11.3c0-1.17.26-2.17.77-3a4.51 4.51 0 011.63-1.64 4.39 4.39 0 012.2-.62c.6 0 1.3.17 2.06.5.76.34 1.25.5 1.48.5.16 0 .7-.2 1.63-.59.88-.37 1.62-.52 2.23-.47 1.65.13 2.89.78 3.7 1.95-1.47.9-2.19 2.13-2.17 3.71.01 1.24.46 2.27 1.35 3.1.4.38.84.67 1.34.88l-.05.04zM10.4.24c0 .97-.35 1.88-1.06 2.72-.85.99-1.87 1.56-2.98 1.47-.01-.12-.02-.23-.02-.36 0-.93.4-1.92 1.12-2.73C7.79.97 8.22.65 8.77.37 9.32.1 9.84-.03 10.36-.04c.01.1.02.19.02.28z" />
    </svg>
  )
}

// ─── Framed screenshot ──────────────────────────────────────────────────────
function Shot({ src, alt }: { src: string; alt: string }) {
  return (
    <div
      style={{
        borderRadius: 14,
        overflow: 'hidden',
        border: '1px solid rgba(255,255,255,0.08)',
        boxShadow: '0 40px 100px rgba(0,0,0,0.7), inset 0 1px 0 rgba(255,255,255,0.05)',
        background: '#0e0d0b',
        lineHeight: 0,
      }}
    >
      <img src={src} alt={alt} style={{ width: '100%', height: 'auto', display: 'block' }} />
    </div>
  )
}

// ─── Navbar ───────────────────────────────────────────────────────────────────
function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        zIndex: 100,
        height: 52,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 clamp(20px, 4vw, 48px)',
        background: scrolled ? 'rgba(12,11,9,0.88)' : 'transparent',
        backdropFilter: scrolled ? 'blur(18px) saturate(1.4)' : 'none',
        borderBottom: scrolled ? '1px solid rgba(255,255,255,0.06)' : '1px solid transparent',
        transition: 'background 0.35s ease, border-color 0.35s ease, backdrop-filter 0.35s ease',
      }}
    >
      <a href="#" style={{ display: 'flex', alignItems: 'center', gap: 8, textDecoration: 'none' }}>
        <IconHeadphones size={16} />
        <span style={{ fontSize: 14, fontWeight: 600, color: '#e2ddd6', letterSpacing: '-0.02em' }}>
          XM5 Control
        </span>
      </a>
      <div style={{ display: 'flex', alignItems: 'center', gap: 22 }}>
        <a
          href="https://github.com/Maadlou/xm5-control-macos"
          target="_blank"
          rel="noreferrer"
          style={{ fontSize: 13, color: '#7a7470', textDecoration: 'none', display: 'flex', alignItems: 'center', gap: 6, transition: 'color 0.2s' }}
          onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.color = '#e2ddd6')}
          onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.color = '#7a7470')}
        >
          <IconGitHub size={13} color="currentColor" />
          GitHub
        </a>
        <a
          href="https://github.com/Maadlou/xm5-control-macos/releases/download/v0.1.0/XM5-Control-0.1.0.dmg"
          style={{
            fontSize: 12.5,
            fontWeight: 600,
            color: '#0c0b09',
            background: ACCENT,
            padding: '5px 14px',
            borderRadius: 6,
            textDecoration: 'none',
            letterSpacing: '-0.01em',
            transition: 'opacity 0.2s',
          }}
          onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.opacity = '0.86')}
          onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.opacity = '1')}
        >
          Download
        </a>
      </div>
    </nav>
  )
}

// ─── Hero ───────────────────────────────────────────────────────────────────
function Hero() {
  const [mounted, setMounted] = useState(false)
  useEffect(() => {
    const t = setTimeout(() => setMounted(true), 80)
    return () => clearTimeout(t)
  }, [])

  return (
    <section
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        padding: 'clamp(120px, 15vw, 150px) clamp(20px, 4vw, 48px) clamp(40px, 6vw, 60px)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          top: '30%',
          right: '8%',
          width: 640,
          height: 520,
          background: `radial-gradient(ellipse at center, ${ACCENT_DIM}0.12) 0%, transparent 70%)`,
          pointerEvents: 'none',
        }}
      />

      {/* Two-column: copy + product */}
      <div
        className="feature-grid"
        style={{ maxWidth: 1040, width: '100%', position: 'relative', zIndex: 1, ...fi(mounted) }}
      >
        <div>
          <div
            style={{
              fontSize: 10.5,
              fontWeight: 600,
              letterSpacing: '0.15em',
              color: ACCENT,
              textTransform: 'uppercase',
              marginBottom: 22,
              opacity: 0.85,
            }}
          >
            XM5 Control · For macOS
          </div>
          <h1
            style={{
              fontSize: 'clamp(38px, 5.4vw, 58px)',
              fontWeight: 300,
              lineHeight: 1.08,
              letterSpacing: '-0.035em',
              color: '#ede8e0',
              margin: '0 0 22px',
            }}
          >
            Your XM5s.
            <br />
            Finally at home on Mac.
          </h1>
          <p style={{ fontSize: 16.5, lineHeight: 1.65, color: '#6a6460', margin: '0 0 36px', maxWidth: 400 }}>
            Noise cancellation, ambient sound and EQ — right from your menu bar. No phone required.
          </p>
          <div style={{ display: 'flex', gap: 11, flexWrap: 'wrap' }}>
          <a
            href="https://github.com/Maadlou/xm5-control-macos/releases/download/v0.1.0/XM5-Control-0.1.0.dmg"
            id="download"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 8,
              padding: '12px 22px',
              background: ACCENT,
              color: '#0c0b09',
              borderRadius: 7,
              fontSize: 14.5,
              fontWeight: 600,
              textDecoration: 'none',
              letterSpacing: '-0.01em',
              transition: 'opacity 0.2s',
            }}
            onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.opacity = '0.86')}
            onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.opacity = '1')}
          >
            <IconApple size={14} color="#0c0b09" />
            Download for macOS
          </a>
          <a
            href="https://github.com/Maadlou/xm5-control-macos"
            target="_blank"
            rel="noreferrer"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 7,
              padding: '12px 20px',
              color: '#8a8480',
              borderRadius: 7,
              fontSize: 14.5,
              fontWeight: 500,
              textDecoration: 'none',
              border: '1px solid rgba(255,255,255,0.09)',
              transition: 'border-color 0.2s, color 0.2s',
            }}
            onMouseEnter={(e) => {
              const el = e.currentTarget as HTMLElement
              el.style.borderColor = 'rgba(255,255,255,0.18)'
              el.style.color = '#e2ddd6'
            }}
            onMouseLeave={(e) => {
              const el = e.currentTarget as HTMLElement
              el.style.borderColor = 'rgba(255,255,255,0.09)'
              el.style.color = '#8a8480'
            }}
          >
            <IconGitHub size={15} color="currentColor" />
            View on GitHub
          </a>
        </div>
        </div>

        {/* Product */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <img
            src={headphonesAngle}
            alt="Sony WH-1000XM5 wireless headphones in black"
            style={{
              width: '100%',
              maxWidth: 460,
              height: 'auto',
              display: 'block',
              filter: 'drop-shadow(0 40px 70px rgba(0,0,0,0.6))',
            }}
          />
        </div>
      </div>

      {/* Real app screenshot */}
      <div
        style={{
          marginTop: 60,
          position: 'relative',
          zIndex: 1,
          width: '100%',
          maxWidth: 1040,
          opacity: mounted ? 1 : 0,
          transform: mounted ? 'translateY(0)' : 'translateY(28px)',
          transition: 'opacity 1s ease 0.25s, transform 1s ease 0.25s',
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: '30%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            width: 640,
            height: 340,
            background: `radial-gradient(ellipse at center, ${ACCENT_DIM}0.13) 0%, transparent 70%)`,
            pointerEvents: 'none',
            zIndex: 0,
          }}
        />
        <div style={{ position: 'relative', zIndex: 1 }}>
          <Shot src={shotAmbient} alt="XM5 Control menu bar popover showing listening modes, ambient sound and equalizer" />
        </div>
      </div>
    </section>
  )
}

// ─── States showcase ──────────────────────────────────────────────────────────
const STATES = [
  {
    src: popoverSettings,
    alt: 'XM5 Control settings panel with behavior toggles and Bluetooth diagnostics',
    kicker: 'Control room',
    title: 'The nerdy stuff, when you want it.',
    body: 'Auto reconnect, launch at login, a global shortcut, plus live Bluetooth diagnostics — protocol, firmware and last sync.',
  },
  {
    src: popoverDisconnected,
    alt: 'XM5 Control showing the headphones disconnected state with a Connect button',
    kicker: 'Effortless',
    title: 'Turn them on. That’s basically it.',
    body: 'When your headphones go quiet, one tap reconnects them. No manual pairing, no phone in hand.',
  },
]

// Floating popover — the real menu-bar panel on a soft glow
function Popover({ src, alt }: { src: string; alt: string }) {
  return (
    <div style={{ position: 'relative', display: 'flex', justifyContent: 'center' }}>
      <div
        style={{
          position: 'absolute',
          top: '48%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          width: 380,
          height: 380,
          background: `radial-gradient(circle at center, ${ACCENT_DIM}0.1) 0%, transparent 68%)`,
          pointerEvents: 'none',
        }}
      />
      <img
        src={src}
        alt={alt}
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 320,
          height: 'auto',
          display: 'block',
          borderRadius: 24,
          border: '1px solid rgba(255,255,255,0.07)',
          boxShadow: '0 40px 90px rgba(0,0,0,0.65)',
        }}
      />
    </div>
  )
}

function StatesSection() {
  const { ref, inView } = useInView()
  return (
    <section ref={ref} style={{ padding: 'clamp(60px, 8vw, 100px) clamp(20px, 4vw, 48px)' }}>
      <div style={{ maxWidth: 1040, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 'clamp(48px, 7vw, 96px)' }}>
        {STATES.map((s, i) => (
          <div
            key={s.title}
            className="feature-grid"
            style={{ alignItems: 'center', ...fi(inView, i * 120) }}
          >
            {i % 2 === 1 ? (
              <>
                <Popover src={s.src} alt={s.alt} />
                <StatesCopy {...s} />
              </>
            ) : (
              <>
                <StatesCopy {...s} />
                <Popover src={s.src} alt={s.alt} />
              </>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}

function StatesCopy({ kicker, title, body }: { kicker: string; title: string; body: string }) {
  return (
    <div>
      <div style={{ fontSize: 10.5, fontWeight: 600, letterSpacing: '0.12em', color: '#3a3733', textTransform: 'uppercase', marginBottom: 16 }}>
        {kicker}
      </div>
      <h2 style={{ fontSize: 'clamp(26px, 3.6vw, 40px)', fontWeight: 300, lineHeight: 1.15, letterSpacing: '-0.03em', color: '#ede8e0', marginBottom: 18 }}>
        {title}
      </h2>
      <p style={{ fontSize: 15.5, lineHeight: 1.7, color: '#5a5550', maxWidth: 380 }}>{body}</p>
    </div>
  )
}

// ─── Footer / Final CTA ───────────────────────────────────────────────────────
function Footer() {
  const { ref, inView } = useInView(0.1)
  return (
    <footer
      ref={ref}
      style={{
        borderTop: '1px solid rgba(255,255,255,0.05)',
        overflow: 'hidden',
        position: 'relative',
        textAlign: 'center',
      }}
    >
      {/* Product — behind the text and CTA */}
      <img
        src={headphonesFront}
        alt="Sony WH-1000XM5 headphones, front view"
        style={{
          position: 'absolute',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          width: 'min(500px, 90vw)',
          height: 'auto',
          opacity: 0.16,
          filter: 'drop-shadow(0 24px 48px rgba(0,0,0,0.6))',
          pointerEvents: 'none',
          zIndex: 0,
        }}
      />

      <div
        style={{
          position: 'relative',
          zIndex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          padding: 'clamp(96px, 13vw, 150px) clamp(20px, 4vw, 48px) clamp(56px, 8vw, 88px)',
          ...fi(inView),
        }}
      >
        <div
          style={{
            fontSize: 10.5,
            fontWeight: 600,
            letterSpacing: '0.15em',
            color: ACCENT,
            textTransform: 'uppercase',
            marginBottom: 'clamp(36px, 5vw, 52px)',
            opacity: 0.85,
          }}
        >
          Get XM5 Control
        </div>

        <h2 style={{ fontSize: 'clamp(32px, 5vw, 54px)', fontWeight: 300, lineHeight: 1.1, letterSpacing: '-0.035em', color: '#ede8e0', marginBottom: 14 }}>
          Your headphones
          <br />
          already know what to do.
        </h2>
        <p style={{ fontSize: 17.5, color: '#5a5550', letterSpacing: '-0.01em', marginBottom: 34, fontWeight: 300 }}>
          Now your Mac does too.
        </p>
        <a
          href="https://github.com/Maadlou/xm5-control-macos/releases/download/v0.1.0/XM5-Control-0.1.0.dmg"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 8,
            padding: '13px 26px',
            background: ACCENT,
            color: '#0c0b09',
            borderRadius: 8,
            fontSize: 15,
            fontWeight: 600,
            textDecoration: 'none',
            letterSpacing: '-0.01em',
            transition: 'opacity 0.2s',
          }}
          onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.opacity = '0.86')}
          onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.opacity = '1')}
        >
          <IconApple size={14} color="#0c0b09" />
          Download XM5 Control
        </a>
        <div style={{ marginTop: 18, fontSize: 11.5, color: '#3a3733', letterSpacing: '0.04em', textTransform: 'uppercase' }}>
          Free · Sony WH-1000XM5 · macOS 13+
        </div>
        <p style={{ margin: '12px 0 0', fontSize: 12, lineHeight: 1.5, color: '#8a8480' }}>
          Open source. Built because I needed it myself.
        </p>
      </div>

      {/* Meta row */}
      <div
        style={{
          position: 'relative',
          zIndex: 1,
          borderTop: '1px solid rgba(255,255,255,0.05)',
          padding: '22px clamp(20px, 4vw, 48px)',
          display: 'flex',
          flexWrap: 'wrap',
          gap: '12px 32px',
          alignItems: 'center',
          justifyContent: 'space-between',
          textAlign: 'left',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <IconHeadphones size={13} color="#3a3733" />
          <span style={{ fontSize: 12, color: '#3a3733', fontWeight: 500 }}>XM5 Control</span>
        </div>
        <p style={{ flex: 1, textAlign: 'center', fontSize: 11, color: '#2e2b28', minWidth: 240, lineHeight: 1.5, margin: 0 }}>
          XM5 Control is an independent project and is not affiliated with or endorsed by Sony.
        </p>
        <div style={{ display: 'flex', gap: 20 }}>
          <a href="https://github.com/Maadlou/xm5-control-macos" target="_blank" rel="noreferrer" style={{ fontSize: 12, color: '#3a3733', textDecoration: 'none' }}>GitHub</a>
          <a href="https://github.com/Maadlou/xm5-control-macos/releases/download/v0.1.0/XM5-Control-0.1.0.dmg" style={{ fontSize: 12, color: '#3a3733', textDecoration: 'none' }}>Download</a>
        </div>
      </div>
    </footer>
  )
}

// ─── App ─────────────────────────────────────────────────────────────────────
export default function App() {
  return (
    <div style={{ background: '#0a0a0a', color: '#e2ddd6', minHeight: '100%' }}>
      <Navbar />
      <Hero />
      <StatesSection />
      <Footer />
    </div>
  )
}
