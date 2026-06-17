import React from 'react';
import { Piece as PieceType } from '../types';

interface PieceProps {
  piece: PieceType;
  padding: number;
  stepSize: number;
  isSelected: boolean;
  onSelect: () => void;
}

export const Piece: React.FC<PieceProps> = ({ piece, padding, stepSize, isSelected, onSelect }) => {
  const x = padding + piece.position.col * stepSize;
  const y = padding + piece.position.row * stepSize;

  const visualSize = 48;

  // Orientation: Red (bottom) faces Up, Black (top) faces Down
  const rotation = piece.player === 'red' ? 180 : 0;
  const isRed = piece.player === 'red';

  // 渐变 id 需带上棋子 id，避免多个内联 SVG 之间相互覆盖
  const gid = piece.id;

  const bodyLight = isRed ? '#f87171' : '#71717a';
  const bodyDark = isRed ? '#991b1b' : '#18181b';
  const trackColor = isRed ? '#7f1d1d' : '#1c1917';
  const turretLight = isRed ? '#ef4444' : '#52525b';
  const turretDark = isRed ? '#7f1d1d' : '#09090b';
  const accent = isRed ? '#fecaca' : '#d6d3d1';

  return (
    // 外层只负责定位与移动动画（内联 transform 会覆盖 Tailwind 的 scale 类，
    // 所以缩放等视觉效果放在内层）
    <div
      style={{
        transform: `translate(${x}px, ${y}px) translate(-50%, -50%)`,
        width: visualSize,
        height: visualSize,
        zIndex: isSelected ? 50 : 10,
        transition: 'transform 0.4s cubic-bezier(0.25, 0.9, 0.35, 1.15)',
      }}
      className="absolute pointer-events-auto"
    >
      <div
        onClick={(e) => {
          e.stopPropagation();
          onSelect();
        }}
        className={`w-full h-full cursor-pointer transition-all duration-200
          ${isSelected ? 'scale-125 drop-shadow-2xl' : 'hover:scale-110 drop-shadow-md'}
        `}
      >
        <svg
          viewBox="0 0 100 100"
          className="w-full h-full overflow-visible"
          style={{
            transform: `rotate(${rotation}deg)`,
            transition: 'transform 0.5s ease-out',
          }}
        >
          <defs>
            <linearGradient id={`body-${gid}`} x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor={bodyLight} />
              <stop offset="100%" stopColor={bodyDark} />
            </linearGradient>
            <radialGradient id={`turret-${gid}`} cx="0.35" cy="0.35" r="0.9">
              <stop offset="0%" stopColor={turretLight} />
              <stop offset="100%" stopColor={turretDark} />
            </radialGradient>
          </defs>

          {/* 选中状态：光晕 + 旋转虚线圈 */}
          {isSelected && (
            <>
              <circle cx="50" cy="50" r="58" fill="rgba(234, 179, 8, 0.15)" />
              <circle
                cx="50" cy="50" r="60"
                fill="none" stroke="#eab308" strokeWidth="4"
                strokeDasharray="10,6"
                className="animate-spin-slow"
              />
            </>
          )}

          {/* 接地阴影 */}
          <ellipse cx="50" cy="92" rx="36" ry="7" fill="rgba(0,0,0,0.18)" />

          {/* 履带 */}
          <rect x="12" y="10" width="17" height="80" rx="8" fill={trackColor} stroke="#1c1917" strokeWidth="2" />
          <rect x="71" y="10" width="17" height="80" rx="8" fill={trackColor} stroke="#1c1917" strokeWidth="2" />
          {/* 负重轮 */}
          {[20, 36, 52, 68, 81].map((cy) => (
            <g key={cy}>
              <circle cx="20.5" cy={cy} r="4.5" fill="#0c0a09" opacity="0.55" />
              <circle cx="79.5" cy={cy} r="4.5" fill="#0c0a09" opacity="0.55" />
            </g>
          ))}

          {/* 车体 */}
          <rect x="24" y="18" width="52" height="64" rx="9" fill={`url(#body-${gid})`} stroke="#1c1917" strokeWidth="2.5" />
          {/* 车体高光 */}
          <rect x="28" y="22" width="44" height="10" rx="5" fill="#ffffff" opacity="0.18" />

          {/* 炮管（含炮口制退器） */}
          <rect x="45.5" y="52" width="9" height="46" rx="3" fill={turretDark} stroke="#1c1917" strokeWidth="2" />
          <rect x="43" y="92" width="14" height="8" rx="2.5" fill={turretDark} stroke="#1c1917" strokeWidth="2" />

          {/* 炮塔 */}
          <circle cx="50" cy="44" r="19" fill={`url(#turret-${gid})`} stroke="#1c1917" strokeWidth="2.5" />
          {/* 舱盖 */}
          <circle cx="50" cy="44" r="9" fill={accent} opacity="0.9" />
          <circle cx="50" cy="44" r="9" fill="none" stroke="#1c1917" strokeWidth="1.5" opacity="0.6" />

          {/* 五角星徽记 */}
          <path
            d="M50 38.6 L51.7 42.3 L55.7 42.7 L52.7 45.4 L53.6 49.3 L50 47.2 L46.4 49.3 L47.3 45.4 L44.3 42.7 L48.3 42.3 Z"
            fill={isRed ? '#7f1d1d' : '#fafaf9'}
            opacity="0.85"
          />
        </svg>
      </div>
    </div>
  );
};
