import { useCallback, useEffect, useRef, useState } from 'react'
import type { InputEvent } from '../types'
import { useI18n } from '../i18n'

const isLocalMac = /Mac|iPhone|iPod|iPad/.test(navigator.platform)
const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent)

interface Props {
  videoStream: MediaStream | null
  onInput: (e: InputEvent) => void
  onDisconnect: () => void
  deviceName: string
  remotePlatform: string
}

export default function RemoteScreen({ videoStream, onInput, onDisconnect, deviceName, remotePlatform }: Props) {
  const { t } = useI18n()
  const videoRef    = useRef<HTMLVideoElement>(null)
  const cursorRef   = useRef<HTMLDivElement>(null)
  const kbInputRef  = useRef<HTMLInputElement>(null)
  const [showKb, setShowKb] = useState(false)

  const defaultSwap = !isLocalMac && (remotePlatform === 'darwin' || remotePlatform === '')
  const [swapCtrlCmd, setSwapCtrlCmd] = useState(defaultSwap)

  // Sticky modifier keys (mobile)
  const [activeMods, setActiveMods] = useState<Set<string>>(new Set())

  // Toolbar auto-hide (desktop only; mobile toolbar is always small)
  const hideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [toolbarVisible, setToolbarVisible] = useState(true)

  const resetHideTimer = useCallback(() => {
    if (!isMobile) {
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current)
      setToolbarVisible(true)
      hideTimerRef.current = setTimeout(() => setToolbarVisible(false), 3000)
    }
  }, [])

  useEffect(() => {
    if (!isMobile) resetHideTimer()
    return () => { if (hideTimerRef.current) clearTimeout(hideTimerRef.current) }
  }, [resetHideTimer])

  useEffect(() => {
    const v = videoRef.current
    if (!v) return
    v.srcObject = videoStream
    if (videoStream) v.play().catch(() => {})
  }, [videoStream])

  // ── coordinate mapping ────────────────────────────────────────────────────
  const toRemote = useCallback((clientX: number, clientY: number): [number, number] => {
    const v = videoRef.current
    if (!v || !v.videoWidth || !v.videoHeight) return [0, 0]
    const rect = v.getBoundingClientRect()
    const vAspect = v.videoWidth / v.videoHeight
    const cAspect = rect.width / rect.height
    let rW: number, rH: number, oX: number, oY: number
    if (vAspect > cAspect) {
      rW = rect.width; rH = rect.width / vAspect
      oX = 0;         oY = (rect.height - rH) / 2
    } else {
      rW = rect.height * vAspect; rH = rect.height
      oX = (rect.width - rW) / 2; oY = 0
    }
    const x = ((clientX - rect.left - oX) / rW) * v.videoWidth
    const y = ((clientY - rect.top  - oY) / rH) * v.videoHeight
    return [Math.round(x), Math.round(y)]
  }, [])

  const moveCursor = useCallback((clientX: number, clientY: number, show: boolean) => {
    const c = cursorRef.current
    const v = videoRef.current
    if (!c || !v) return
    const rect = v.getBoundingClientRect()
    c.style.left    = `${clientX - rect.left}px`
    c.style.top     = `${clientY - rect.top}px`
    c.style.display = show ? 'block' : 'none'
  }, [])

  // ── keyboard helpers ──────────────────────────────────────────────────────
  const getMods = useCallback((e: MouseEvent | KeyboardEvent): string[] => {
    const m: string[] = []
    if (e.ctrlKey)  m.push('ctrl')
    if (e.shiftKey) m.push('shift')
    if (e.altKey)   m.push('alt')
    if (e.metaKey)  m.push('meta')
    if (!swapCtrlCmd) return m
    return m.map(k => k === 'ctrl' ? 'meta' : k === 'meta' ? 'ctrl' : k)
  }, [swapCtrlCmd])

  // Resolve active sticky mods (with Ctrl⇄Cmd swap applied)
  const getActiveMods = useCallback((): string[] => {
    const mods = [...activeMods]
    if (!swapCtrlCmd) return mods
    return mods.map(k => k === 'ctrl' ? 'meta' : k === 'meta' ? 'ctrl' : k)
  }, [activeMods, swapCtrlCmd])

  const clearMods = useCallback(() => setActiveMods(new Set()), [])

  // ── desktop mouse ─────────────────────────────────────────────────────────
  const lastSendTime = useRef(0)

  const onMouseMove = useCallback((e: React.MouseEvent) => {
    resetHideTimer()
    moveCursor(e.clientX, e.clientY, true)
    const now = performance.now()
    if (now - lastSendTime.current < 8) return
    lastSendTime.current = now
    const [x, y] = toRemote(e.clientX, e.clientY)
    onInput({ event: 'mousemove', x, y })
  }, [toRemote, onInput, moveCursor, resetHideTimer])

  const onMouseDown  = useCallback((e: React.MouseEvent) => {
    const [x, y] = toRemote(e.clientX, e.clientY)
    onInput({ event: 'mousedown', x, y, button: e.button, mods: getMods(e.nativeEvent) })
  }, [toRemote, onInput, getMods])

  const onMouseUp    = useCallback((e: React.MouseEvent) => {
    const [x, y] = toRemote(e.clientX, e.clientY)
    onInput({ event: 'mouseup', x, y, button: e.button })
  }, [toRemote, onInput])

  const onDoubleClick = useCallback((e: React.MouseEvent) => {
    const [x, y] = toRemote(e.clientX, e.clientY)
    onInput({ event: 'dblclick', x, y, button: e.button })
  }, [toRemote, onInput])

  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    onInput({ event: 'scroll', dx: Math.round(e.deltaX), dy: Math.round(e.deltaY) })
  }, [onInput])

  const onContextMenu = useCallback((e: React.MouseEvent) => { e.preventDefault() }, [])

  // ── touch ─────────────────────────────────────────────────────────────────
  const touchStart      = useRef<{ x: number; y: number; t: number } | null>(null)
  const longPressTimer  = useRef<ReturnType<typeof setTimeout> | null>(null)
  const prevCentroid    = useRef<{ x: number; y: number } | null>(null)
  const prevPinchDist   = useRef<number | null>(null)
  const touchDragging   = useRef(false)
  const twoFingerUsed   = useRef(false) // true if 2+ fingers were active in this gesture

  const clearLongPress = () => {
    if (longPressTimer.current) { clearTimeout(longPressTimer.current); longPressTimer.current = null }
  }

  const onTouchStart = useCallback((e: React.TouchEvent) => {
    e.preventDefault()
    if (e.touches.length === 1) {
      const t = e.touches[0]
      touchStart.current = { x: t.clientX, y: t.clientY, t: Date.now() }
      touchDragging.current = false
      moveCursor(t.clientX, t.clientY, true)
      longPressTimer.current = setTimeout(() => {
        clearLongPress()
        const [rx2, ry2] = toRemote(t.clientX, t.clientY)
        onInput({ event: 'mousedown', x: rx2, y: ry2, button: 2 })
        onInput({ event: 'mouseup',   x: rx2, y: ry2, button: 2 })
        touchStart.current = null
        if (navigator.vibrate) navigator.vibrate(40)
      }, 600)
    } else {
      clearLongPress()
      twoFingerUsed.current = true
      // Hide keyboard and toolbar on two-finger scroll
      if (showKb) {
        setShowKb(false)
        setActiveMods(new Set())
        kbInputRef.current?.blur()
      }
      setToolbarVisible(false)
      const t0 = e.touches[0], t1 = e.touches[1]
      const dx = t0.clientX - t1.clientX, dy = t0.clientY - t1.clientY
      prevPinchDist.current = Math.hypot(dx, dy)
      prevCentroid.current = {
        x: (t0.clientX + t1.clientX) / 2,
        y: (t0.clientY + t1.clientY) / 2,
      }
    }
  }, [toRemote, onInput, moveCursor, showKb])

  const onTouchMove = useCallback((e: React.TouchEvent) => {
    e.preventDefault()
    if (e.touches.length === 1) {
      const t = e.touches[0]
      const start = touchStart.current
      if (start) {
        const dist = Math.hypot(t.clientX - start.x, t.clientY - start.y)
        if (dist > 8) {
          clearLongPress()
          touchDragging.current = true
        }
      }
      // Single-finger drag → scroll
      if (touchDragging.current) {
        const prev = prevCentroid.current
        prevCentroid.current = { x: t.clientX, y: t.clientY }
        if (prev) {
          const dx = (prev.x - t.clientX) * 2
          const dy = (prev.y - t.clientY) * 2
          onInput({ event: 'scroll', dx: Math.round(dx), dy: Math.round(dy) })
        }
      } else {
        prevCentroid.current = { x: t.clientX, y: t.clientY }
      }
    } else if (e.touches.length === 2) {
      const t0 = e.touches[0], t1 = e.touches[1]
      const cx = (t0.clientX + t1.clientX) / 2
      const cy = (t0.clientY + t1.clientY) / 2
      const dx = t0.clientX - t1.clientX, dy = t0.clientY - t1.clientY
      const dist = Math.hypot(dx, dy)

      // Two-finger scroll (centroid movement)
      if (prevCentroid.current) {
        const sdx = (prevCentroid.current.x - cx) * 2
        const sdy = (prevCentroid.current.y - cy) * 2
        if (Math.abs(sdx) > 0.5 || Math.abs(sdy) > 0.5) {
          onInput({ event: 'scroll', dx: Math.round(sdx), dy: Math.round(sdy) })
        }
      }
      prevCentroid.current = { x: cx, y: cy }
      prevPinchDist.current = dist
    }
  }, [toRemote, onInput, moveCursor])

  const onTouchEnd = useCallback((e: React.TouchEvent) => {
    e.preventDefault()
    clearLongPress()

    if (!twoFingerUsed.current && touchStart.current && e.changedTouches.length >= 1) {
      const t = e.changedTouches[0]
      const dist = Math.hypot(t.clientX - touchStart.current.x, t.clientY - touchStart.current.y)
      if (dist < 10) {
        // Tap → click
        const [rx, ry] = toRemote(t.clientX, t.clientY)
        onInput({ event: 'mousemove', x: rx, y: ry })
        onInput({ event: 'mousedown', x: rx, y: ry, button: 0 })
        onInput({ event: 'mouseup',   x: rx, y: ry, button: 0 })
        if (isMobile) setToolbarVisible(true)
      }
    }

    if (e.touches.length === 0) {
      touchStart.current = null
      prevCentroid.current = null
      prevPinchDist.current = null
      touchDragging.current = false
      twoFingerUsed.current = false
      moveCursor(0, 0, false)
    } else if (e.touches.length === 1) {
      // Dropped from 2 fingers to 1 — clear two-finger state so the
      // remaining finger's first move doesn't produce a huge jump.
      prevCentroid.current = null
      prevPinchDist.current = null
    }
  }, [toRemote, onInput, moveCursor, setToolbarVisible])

  // ── keyboard ──────────────────────────────────────────────────────────────
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    e.preventDefault()
    onInput({ event: 'keydown', key: e.key, code: e.code, mods: getMods(e.nativeEvent) })
  }, [onInput, getMods])

  const handleKeyUp = useCallback((e: React.KeyboardEvent) => {
    e.preventDefault()
    onInput({ event: 'keyup', key: e.key, code: e.code, mods: getMods(e.nativeEvent) })
  }, [onInput, getMods])

  // Mobile virtual keyboard: physical keys (non-IME)
  const handleKbKeyDown = useCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Unidentified') return // IME composing, wait for input event
    e.preventDefault()
    const mods = getActiveMods()
    onInput({ event: 'keydown', key: e.key, code: e.code, mods })
    onInput({ event: 'keyup',   key: e.key, code: e.code, mods })
    if (activeMods.size > 0) clearMods()
  }, [onInput, getActiveMods, activeMods, clearMods])

  // IME / soft keyboard text input → paste_text, with \n → Enter
  const handleKbInput = useCallback((e: React.FormEvent<HTMLInputElement>) => {
    const input = e.currentTarget
    const text = input.value
    if (!text) return
    input.value = ''
    const mods = getActiveMods()
    if (activeMods.size > 0) clearMods()

    const parts = text.split('\n')
    for (let i = 0; i < parts.length; i++) {
      if (parts[i]) {
        if (mods.length > 0) {
          // Modifiers armed: send each char individually
          for (const ch of parts[i]) {
            const upper = ch.toUpperCase()
            const code = /^[a-zA-Z]$/.test(ch) ? `Key${upper}` : /^[0-9]$/.test(ch) ? `Digit${ch}` : ch === ' ' ? 'Space' : ch
            onInput({ event: 'keydown', key: ch, code, mods } as any)
            onInput({ event: 'keyup',   key: ch, code, mods } as any)
          }
        } else {
          onInput({ event: 'paste_text', text: parts[i] } as any)
        }
      }
      if (i < parts.length - 1) {
        onInput({ event: 'keydown', key: 'Enter', code: 'Enter', mods } as any)
        onInput({ event: 'keyup',   key: 'Enter', code: 'Enter', mods } as any)
      }
    }
  }, [onInput, getActiveMods, activeMods, clearMods])

  // Mobile: send a special key, then re-focus the hidden input
  const sendSpecialKey = useCallback((key: string, code: string) => {
    const mods = getActiveMods()
    onInput({ event: 'keydown', key, code, mods } as any)
    onInput({ event: 'keyup',   key, code, mods } as any)
    if (activeMods.size > 0) clearMods()
    kbInputRef.current?.focus()
  }, [onInput, getActiveMods, activeMods, clearMods])

  const toggleModifier = useCallback((mod: string) => {
    setActiveMods(prev => {
      const next = new Set(prev)
      if (next.has(mod)) next.delete(mod); else next.add(mod)
      return next
    })
    kbInputRef.current?.focus()
  }, [])

  const toggleKeyboard = useCallback(() => {
    const input = kbInputRef.current
    setShowKb(v => {
      const next = !v
      if (!next) { input?.blur(); setActiveMods(new Set()) }
      return next
    })
    if (input) input.focus()
  }, [])

  // ── paste ─────────────────────────────────────────────────────────────────
  const onPaste = useCallback((e: React.ClipboardEvent) => {
    e.preventDefault()
    const text = e.clipboardData.getData('text/plain')
    if (text) onInput({ event: 'paste_text', text } as any)
  }, [onInput])

  const sendClipboard = useCallback(async () => {
    try {
      const text = await navigator.clipboard.readText()
      if (text) onInput({ event: 'paste_text', text } as any)
    } catch {
      const text = window.prompt(t('paste_prompt'))
      if (text) onInput({ event: 'paste_text', text } as any)
    }
  }, [onInput])

  return (
    <div style={styles.wrapper}>
      {/* ── toolbar ── */}
      <div style={{
        ...styles.toolbar,
        transform: !toolbarVisible ? 'translateY(-100%)' : 'none',
        transition: 'transform 0.2s ease',
      }}>
        <span style={styles.toolbarLabel}>🖥 {deviceName}</span>
        <div style={styles.toolbarRight}>
          {!isMobile && (
            <label style={styles.swapLabel} title={t('ctrl_swap_title')}>
              <input type="checkbox" checked={swapCtrlCmd}
                onChange={e => setSwapCtrlCmd(e.target.checked)} style={{ marginRight: 4 }} />
              <span style={{ fontSize: 12, color: swapCtrlCmd ? '#86efac' : '#94a3b8' }}>Ctrl ⇄ ⌘</span>
            </label>
          )}
          <button style={styles.toolBtn} onClick={sendClipboard}
            title={t('paste_title')}>{t('paste')}</button>
          {isMobile && (
            <button
              style={{ ...styles.toolBtn, color: showKb ? '#86efac' : '#e2e8f0' }}
              onClick={toggleKeyboard}>{t('keyboard')}</button>
          )}
          <button style={styles.disconnectBtn} onClick={onDisconnect}>{t('disconnect')}</button>
        </div>
      </div>

      {/* ── mobile modifier key row ── */}
      {isMobile && showKb && (
        <div style={styles.modRow}>
          <div style={styles.modRowInner}>
            {/* Sticky modifiers */}
            {(['ctrl','shift','alt','meta'] as const).map(mod => (
              <ModKey key={mod}
                label={mod === 'meta' ? 'Cmd' : mod === 'ctrl' ? 'Ctrl' : mod === 'shift' ? 'Shift' : 'Alt'}
                active={activeMods.has(mod)}
                onTap={() => toggleModifier(mod)} />
            ))}
            <div style={styles.modSep} />
            <ModKey label="Tab"   onTap={() => sendSpecialKey('Tab',       'Tab')} />
            <ModKey label="Esc"   onTap={() => sendSpecialKey('Escape',    'Escape')} />
            <ModKey label="Del"   onTap={() => sendSpecialKey('Delete',    'Delete')} />
            <ModKey label="`"     onTap={() => sendSpecialKey('`',         'Backquote')} />
            <ModKey label="Space" onTap={() => sendSpecialKey(' ',         'Space')} />
            <div style={styles.modSep} />
            <ModKey label="←"   onTap={() => sendSpecialKey('ArrowLeft',  'ArrowLeft')} />
            <ModKey label="↑"   onTap={() => sendSpecialKey('ArrowUp',    'ArrowUp')} />
            <ModKey label="↓"   onTap={() => sendSpecialKey('ArrowDown',  'ArrowDown')} />
            <ModKey label="→"   onTap={() => sendSpecialKey('ArrowRight', 'ArrowRight')} />
            <div style={styles.modSep} />
            <ModKey label="Home" onTap={() => sendSpecialKey('Home',      'Home')} />
            <ModKey label="End"  onTap={() => sendSpecialKey('End',       'End')} />
            <ModKey label="PgUp" onTap={() => sendSpecialKey('PageUp',    'PageUp')} />
            <ModKey label="PgDn" onTap={() => sendSpecialKey('PageDown',  'PageDown')} />
            <div style={styles.modSep} />
            {Array.from({ length: 12 }, (_, i) => (
              <ModKey key={`f${i+1}`} label={`F${i+1}`}
                onTap={() => sendSpecialKey(`F${i+1}`, `F${i+1}`)} />
            ))}
          </div>
        </div>
      )}

      {/* ── video area ── */}
      <div style={styles.videoWrapper} onMouseMove={resetHideTimer}>
        <video
          ref={videoRef}
          style={styles.video}
          autoPlay playsInline muted
          onMouseMove={onMouseMove}
          onMouseDown={onMouseDown}
          onMouseUp={onMouseUp}
          onDoubleClick={onDoubleClick}
          onWheel={onWheel}
          onContextMenu={onContextMenu}
          onKeyDown={handleKeyDown}
          onKeyUp={handleKeyUp}
          onPaste={onPaste}
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={onTouchEnd}
          onMouseEnter={() => { videoRef.current?.focus() }}
          onMouseLeave={() => { videoRef.current?.blur(); moveCursor(0, 0, false) }}
          tabIndex={0}
        />
        <div ref={cursorRef} style={styles.cursor} />
        {!videoStream && (
          <div style={styles.waiting}><span>{t('connecting_webrtc')}</span></div>
        )}
      </div>

      {/* ── mobile virtual keyboard input (off-screen) ── */}
      {isMobile && (
        <input
          ref={kbInputRef}
          style={styles.hiddenInput}
          type="text"
          inputMode="text"
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="off"
          spellCheck={false}
          onKeyDown={handleKbKeyDown}
          onInput={handleKbInput}
          onBlur={() => { setShowKb(false); setActiveMods(new Set()) }}
        />
      )}

      {/* ── mobile gesture hint ── */}
      {isMobile && videoStream && <MobileHint />}
    </div>
  )
}

// ── Modifier key chip ─────────────────────────────────────────────────────────

function ModKey({ label, active = false, onTap }: { label: string; active?: boolean; onTap: () => void }) {
  return (
    <button
      onMouseDown={e => e.preventDefault()} // prevent focus loss on desktop
      onClick={onTap}
      style={{
        padding: '5px 10px',
        margin: '0 2px',
        borderRadius: 5,
        border: `1px solid ${active ? '#3b82f6' : 'rgba(255,255,255,0.2)'}`,
        background: active ? 'rgba(59,130,246,0.75)' : 'rgba(255,255,255,0.1)',
        color: active ? '#fff' : 'rgba(255,255,255,0.8)',
        fontSize: 12,
        fontWeight: active ? 700 : 400,
        cursor: 'pointer',
        whiteSpace: 'nowrap' as const,
        flexShrink: 0,
        transition: 'background 0.15s, border-color 0.15s',
      }}
    >{label}</button>
  )
}

// ── One-time gesture hint ─────────────────────────────────────────────────────

function MobileHint() {
  const { t } = useI18n()
  const [visible, setVisible] = useState(() => !sessionStorage.getItem('rc_hint_seen'))
  useEffect(() => {
    if (!visible) return
    const t = setTimeout(() => { sessionStorage.setItem('rc_hint_seen', '1'); setVisible(false) }, 4000)
    return () => clearTimeout(t)
  }, [visible])
  if (!visible) return null
  return (
    <div style={styles.hint} onClick={() => setVisible(false)}>
      <div style={styles.hintBox}>
        <div>{t('hint_click')} &nbsp;|&nbsp; {t('hint_longpress')}</div>
        <div>{t('hint_scroll')} &nbsp;|&nbsp; {t('hint_keyboard')}</div>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  wrapper: {
    display: 'flex', flexDirection: 'column', height: '100%', background: '#000',
  },
  toolbar: {
    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    padding: '6px 12px', background: '#1e293b', borderBottom: '1px solid #334155',
    flexShrink: 0, overflowX: 'auto', gap: 8,
  },
  toolbarLabel: { fontSize: 13, fontWeight: 600, color: '#e2e8f0', whiteSpace: 'nowrap' },
  toolbarRight: { display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 },
  swapLabel: { display: 'flex', alignItems: 'center', cursor: 'pointer', userSelect: 'none' as const },
  toolBtn: {
    background: '#334155', color: '#e2e8f0', border: 'none', borderRadius: 4,
    padding: '4px 10px', fontSize: 12, cursor: 'pointer',
  },
  disconnectBtn: {
    background: '#dc2626', color: '#fff', border: 'none', borderRadius: 4,
    padding: '4px 12px', fontSize: 12, cursor: 'pointer',
  },
  modRow: {
    background: '#0f172a', borderBottom: '1px solid #1e293b',
    flexShrink: 0, overflowX: 'auto',
  },
  modRowInner: {
    display: 'flex', alignItems: 'center', padding: '5px 8px',
    width: 'max-content',
  },
  modSep: {
    width: 1, height: 20, background: 'rgba(255,255,255,0.15)',
    margin: '0 6px', flexShrink: 0,
  },
  videoWrapper: {
    flex: 1, overflow: 'hidden', display: 'flex', alignItems: 'center',
    justifyContent: 'center', position: 'relative', background: '#000',
  },
  video: {
    width: '100%', height: '100%', objectFit: 'contain',
    cursor: 'none', outline: 'none', touchAction: 'none',
  },
  cursor: {
    display: 'none', position: 'absolute', width: 14, height: 14,
    marginLeft: -7, marginTop: -7, borderRadius: '50%',
    border: '2px solid #fff', boxShadow: '0 0 0 1px #000, inset 0 0 0 1px #000',
    pointerEvents: 'none', zIndex: 10,
  },
  waiting: {
    position: 'absolute', inset: 0, display: 'flex', alignItems: 'center',
    justifyContent: 'center', color: '#475569', fontSize: 15,
  },
  hiddenInput: {
    position: 'fixed', left: '-9999px', top: 0,
    width: 1, height: 1, opacity: 0,
  },
  hint: {
    position: 'absolute', inset: 0, display: 'flex', alignItems: 'flex-end',
    justifyContent: 'center', paddingBottom: 40, pointerEvents: 'none', zIndex: 20,
  },
  hintBox: {
    background: 'rgba(0,0,0,0.7)', color: '#e2e8f0', borderRadius: 10,
    padding: '10px 18px', fontSize: 13, lineHeight: 1.8, textAlign: 'center',
    backdropFilter: 'blur(4px)',
  },
}
