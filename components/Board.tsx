import React from 'react';
import { GameState, Position, Piece as PieceType, Player, BOARD_SIZE } from '../types';
import { Piece } from './Piece';

export interface ExplosionEffect {
  key: number;
  position: Position;
  player: Player;
}

interface BoardProps {
  gameState: GameState;
  explosions: ExplosionEffect[];
  shaking: boolean;
  onPieceSelect: (id: string) => void;
  onMove: (pos: Position) => void;
  onInvalidClick: () => void;
  isValidMove: (start: Position, end: Position, pieces: PieceType[]) => boolean;
}

// 爆炸特效：闪光 + 冲击波 + 飞溅粒子 + 烟雾
const Explosion: React.FC<{ x: number; y: number }> = ({ x, y }) => {
  const particleColors = ['#fbbf24', '#f97316', '#ef4444', '#fde68a', '#78716c'];
  return (
    <div
      className="absolute pointer-events-none"
      style={{ left: x, top: y, zIndex: 60 }}
    >
      <div className="boom-smoke" />
      <div className="boom-flash" />
      <div className="boom-ring" />
      {Array.from({ length: 10 }).map((_, i) => {
        const angle = (i / 10) * Math.PI * 2 + (i % 2) * 0.3;
        const dist = 30 + (i % 3) * 12;
        return (
          <div
            key={i}
            className="boom-particle"
            style={{
              background: particleColors[i % particleColors.length],
              '--dx': `${Math.cos(angle) * dist}px`,
              '--dy': `${Math.sin(angle) * dist}px`,
            } as React.CSSProperties}
          />
        );
      })}
    </div>
  );
};

const stepSize = 60;
const padding = 60;
const boardSizePx = stepSize * (BOARD_SIZE - 1);
const totalSize = boardSizePx + padding * 2;
const BORDER_PX = 10;

// 棋盘外框总尺寸（含边框），供外层按屏幕宽度等比缩放
export const BOARD_OUTER_PX = totalSize + BORDER_PX * 2;

export const Board: React.FC<BoardProps> = ({
  gameState, explosions, shaking, onPieceSelect, onMove, onInvalidClick, isValidMove,
}) => {

  const toPx = (pos: Position) => ({
    x: padding + pos.col * stepSize,
    y: padding + pos.row * stepSize,
  });

  // Generate Grid Paths
  const renderGrid = () => {
    let dPaths = '';
    let mainPaths = '';

    // 1. Diagonals (Background Layer)
    for (let r = 0; r < BOARD_SIZE - 1; r += 2) {
      for (let c = 0; c < BOARD_SIZE - 1; c += 2) {
        const x = padding + c * stepSize;
        const y = padding + r * stepSize;
        const size = stepSize * 2;
        dPaths += `M${x},${y} L${x + size},${y + size} `;
        dPaths += `M${x + size},${y} L${x},${y + size} `;
      }
    }

    // 2. Main Grid Lines (Foreground Layer)
    for (let i = 0; i < BOARD_SIZE; i += 2) {
      const pos = padding + i * stepSize;
      const start = padding;
      const end = padding + boardSizePx;
      mainPaths += `M${start},${pos} L${end},${pos} `;
      mainPaths += `M${pos},${start} L${pos},${end} `;
    }

    return (
      <>
        {/* 刻线效果：先画一层错位的浅色高光，再画深色线条 */}
        <g transform="translate(0.8 1)" opacity="0.55">
          <path d={dPaths} stroke="#fff6e0" strokeWidth="1.5" strokeLinecap="square" />
          <path d={mainPaths} stroke="#fff6e0" strokeWidth="2.5" strokeLinecap="square" />
        </g>
        {/* 斜线 */}
        <path d={dPaths} stroke="#a9834f" strokeWidth="1.5" strokeLinecap="square" />
        {/* 主网格 */}
        <path d={mainPaths} stroke="#5e4322" strokeWidth="2.5" strokeLinecap="square" />
        {/* 外边框（粗细双线，更像传统棋盘） */}
        <rect x={padding} y={padding} width={boardSizePx} height={boardSizePx} fill="none" stroke="#4a3219" strokeWidth="4" />
        <rect x={padding - 14} y={padding - 14} width={boardSizePx + 28} height={boardSizePx + 28} fill="none" stroke="#4a3219" strokeWidth="1.5" opacity="0.75" />
      </>
    );
  };

  // 上一步走子标记：起点空心圈 + 终点光环
  const renderLastMove = () => {
    if (!gameState.lastMove) return null;
    const from = toPx(gameState.lastMove.from);
    const to = toPx(gameState.lastMove.to);
    return (
      <g className="pointer-events-none">
        <circle cx={from.x} cy={from.y} r={8} fill="none" stroke="#d97706" strokeWidth="2.5" opacity="0.7" />
        <line
          x1={from.x} y1={from.y} x2={to.x} y2={to.y}
          stroke="#d97706" strokeWidth="2" strokeDasharray="4,6" opacity="0.35"
        />
        <circle cx={to.x} cy={to.y} r={31} fill="rgba(217, 119, 6, 0.14)" stroke="#d97706" strokeWidth="2" opacity="0.85" />
      </g>
    );
  };

  // Generate Clickable Intersection Points
  const renderIntersections = () => {
    const points = [];
    const selectedPiece = gameState.pieces.find(p => p.id === gameState.selectedPieceId);

    for (let row = 0; row < BOARD_SIZE; row++) {
      for (let col = 0; col < BOARD_SIZE; col++) {
        // Only render valid nodes (Union Jack topology)
        if (col % 2 !== row % 2) continue;

        const x = padding + col * stepSize;
        const y = padding + row * stepSize;

        const isOccupied = gameState.pieces.some(p => p.position.col === col && p.position.row === row && !p.isDead);

        let isPotentialMove = false;
        if (selectedPiece && !isOccupied) {
          isPotentialMove = isValidMove(selectedPiece.position, { col, row }, gameState.pieces);
        }

        const isMainIntersection = col % 2 === 0;

        points.push(
          <g
            key={`point-${col}-${row}`}
            className={isPotentialMove ? 'move-target' : undefined}
            onClick={() => {
              if (isPotentialMove) {
                onMove({ col, row });
              } else if (selectedPiece && !isOccupied) {
                onInvalidClick();
              }
            }}
          >
            {/* Invisible Hit Area */}
            <circle
              cx={x}
              cy={y}
              r={25}
              fill="transparent"
              className={isPotentialMove ? 'cursor-pointer' : 'cursor-default'}
            />

            {/* 星位 / 普通交叉点 */}
            {!isOccupied && !isPotentialMove && (
              <circle
                cx={x}
                cy={y}
                r={isMainIntersection ? 4 : 2.5}
                fill={isMainIntersection ? '#5e4322' : '#a9834f'}
              />
            )}

            {/* 可落点提示：呼吸圆点 + 悬停展开外圈 */}
            {isPotentialMove && (
              <>
                <circle
                  cx={x}
                  cy={y}
                  r={24}
                  fill="rgba(34, 197, 94, 0.08)"
                  stroke="#16a34a"
                  strokeWidth="2"
                  strokeDasharray="5,4"
                  className="move-hover-ring pointer-events-none"
                />
                <circle
                  cx={x}
                  cy={y}
                  r={11}
                  fill="rgba(34, 197, 94, 0.28)"
                  className="move-pulse pointer-events-none"
                />
                <circle
                  cx={x}
                  cy={y}
                  r={5.5}
                  fill="#16a34a"
                  className="move-dot pointer-events-none"
                  style={{ transition: 'transform 0.18s ease-out' }}
                />
              </>
            )}
          </g>
        );
      }
    }
    return points;
  };

  return (
    <div
      className={`board-frame relative select-none rounded-xl ${shaking ? 'animate-shake' : ''}`}
      style={{ padding: BORDER_PX }}
    >
      <div className="relative rounded-[4px] overflow-hidden board-inset">
        <svg width={totalSize} height={totalSize} className="block">
          <defs>
            {/* 木纹底色 */}
            <linearGradient id="wood-bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#f4ddb0" />
              <stop offset="45%" stopColor="#ebc88d" />
              <stop offset="100%" stopColor="#dcac6b" />
            </linearGradient>
            {/* 木纹：横向拉长的湍流噪声模拟年轮纹理 */}
            <filter id="wood-grain" x="0" y="0" width="100%" height="100%">
              <feTurbulence type="fractalNoise" baseFrequency="0.006 0.09" numOctaves="4" seed="11" />
              <feColorMatrix
                type="matrix"
                values="0 0 0 0 0.45  0 0 0 0 0.29  0 0 0 0 0.12  0 0 0 0.22 -0.02"
              />
            </filter>
            {/* 细密木纤维 */}
            <filter id="wood-fiber" x="0" y="0" width="100%" height="100%">
              <feTurbulence type="fractalNoise" baseFrequency="0.9 0.02" numOctaves="2" seed="3" />
              <feColorMatrix
                type="matrix"
                values="0 0 0 0 0.40  0 0 0 0 0.26  0 0 0 0 0.12  0 0 0 0.08 0"
              />
            </filter>
            {/* 边缘暗角 */}
            <radialGradient id="wood-vignette" cx="0.5" cy="0.5" r="0.72">
              <stop offset="60%" stopColor="#5b3a17" stopOpacity="0" />
              <stop offset="100%" stopColor="#5b3a17" stopOpacity="0.22" />
            </radialGradient>
          </defs>

          {/* 棋盘背景 */}
          <rect width="100%" height="100%" fill="url(#wood-bg)" />
          <rect width="100%" height="100%" filter="url(#wood-grain)" />
          <rect width="100%" height="100%" filter="url(#wood-fiber)" />
          <rect width="100%" height="100%" fill="url(#wood-vignette)" />

          {/* Grid Layer */}
          {renderGrid()}

          {/* 上一步标记（位于棋子下方） */}
          {renderLastMove()}

          {/* Interaction Layer (Nodes) */}
          {renderIntersections()}
        </svg>

        {/* Pieces Layer */}
        <div className="absolute inset-0 pointer-events-none">
          {gameState.pieces.map(piece => !piece.isDead && (
            <Piece
              key={piece.id}
              piece={piece}
              padding={padding}
              stepSize={stepSize}
              isSelected={gameState.selectedPieceId === piece.id}
              isActiveSide={piece.player === gameState.currentPlayer && !gameState.winner}
              onSelect={() => onPieceSelect(piece.id)}
            />
          ))}
        </div>

        {/* 爆炸特效层 */}
        <div className="absolute inset-0 pointer-events-none">
          {explosions.map(exp => {
            const { x, y } = toPx(exp.position);
            return <Explosion key={exp.key} x={x} y={y} />;
          })}
        </div>
      </div>
    </div>
  );
};
