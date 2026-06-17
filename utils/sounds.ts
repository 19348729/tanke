// 基于 Web Audio API 的合成音效，无需任何外部音频资源
let ctx: AudioContext | null = null;
let muted = false;

export function setMuted(m: boolean) {
  muted = m;
}

function getCtx(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  if (!ctx) {
    const AC = window.AudioContext || (window as any).webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

// 单音（可滑音）
function tone(
  freq: number,
  startDelay: number,
  dur: number,
  type: OscillatorType,
  vol: number,
  slideTo?: number
) {
  const ac = getCtx();
  if (!ac || muted) return;
  const t = ac.currentTime + startDelay;
  const osc = ac.createOscillator();
  const g = ac.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t);
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(Math.max(slideTo, 1), t + dur);
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(vol, t + 0.012);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  osc.connect(g);
  g.connect(ac.destination);
  osc.start(t);
  osc.stop(t + dur + 0.05);
}

// 白噪声脉冲（经低通滤波），用于爆炸/落子质感
function noiseBurst(startDelay: number, dur: number, vol: number, filterFreq: number) {
  const ac = getCtx();
  if (!ac || muted) return;
  const t = ac.currentTime + startDelay;
  const len = Math.max(1, Math.floor(ac.sampleRate * dur));
  const buf = ac.createBuffer(1, len, ac.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) {
    data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2);
  }
  const src = ac.createBufferSource();
  src.buffer = buf;
  const filter = ac.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = filterFreq;
  const g = ac.createGain();
  g.gain.value = vol;
  src.connect(filter);
  filter.connect(g);
  g.connect(ac.destination);
  src.start(t);
}

/** 选中棋子：清脆短促 */
export function playSelect() {
  tone(660, 0, 0.08, 'triangle', 0.18, 920);
}

/** 棋子移动：低沉的滑动+落子声 */
export function playMove() {
  noiseBurst(0, 0.07, 0.1, 2400);
  tone(190, 0.02, 0.12, 'sine', 0.28, 95);
}

/** 夹击吃子：爆炸（吃越多越响） */
export function playCapture(count = 1) {
  const boost = Math.min(count, 3) * 0.12;
  noiseBurst(0, 0.08, 0.3 + boost, 3200); // 炸裂
  noiseBurst(0.02, 0.5, 0.35 + boost, 850); // 轰鸣
  tone(110, 0, 0.45, 'sine', 0.42 + boost, 38); // 低频冲击
  if (count > 1) {
    noiseBurst(0.12, 0.4, 0.25, 600); // 连环爆炸的余响
    tone(90, 0.12, 0.4, 'sine', 0.3, 32);
  }
}

/** 无效操作：低沉两声 */
export function playInvalid() {
  tone(150, 0, 0.09, 'square', 0.1);
  tone(120, 0.1, 0.11, 'square', 0.1);
}

/** 悔棋：下滑音 */
export function playUndo() {
  tone(540, 0, 0.16, 'sine', 0.18, 260);
}

/** 胜利：上行琶音号角 */
export function playWin() {
  const notes = [523.25, 659.25, 783.99, 1046.5];
  notes.forEach((f, i) => {
    tone(f, i * 0.13, 0.34, 'triangle', 0.22);
    tone(f / 2, i * 0.13, 0.34, 'sine', 0.12);
  });
  tone(1046.5, 0.56, 0.6, 'triangle', 0.2);
}
