import React, { useState, useEffect, useRef } from 'react';
import { Board, ExplosionEffect, BOARD_OUTER_PX } from './components/Board';
import { GameState, Player, Piece, Position, BOARD_SIZE } from './types';
import { RotateCcw, Info, Trophy, Undo2, Volume2, VolumeX } from 'lucide-react';
import { setMuted, playSelect, playMove, playCapture, playInvalid, playUndo, playWin } from './utils/sounds';

// Initial Setup Helper
const createInitialState = (): GameState => {
  const pieces: Piece[] = [];
  let idCounter = 0;

  // Black Pieces (Top)
  // Row 0 (y=0): Main intersections 0, 2, 4, 6, 8
  [0, 2, 4, 6, 8].forEach(c => {
    pieces.push({ id: `b-${idCounter++}`, player: 'black', position: { col: c, row: 0 } });
  });
  // Row 1 (y=1): Diagonal intersections 1, 3, 5, 7
  [1, 3, 5, 7].forEach(c => {
    pieces.push({ id: `b-${idCounter++}`, player: 'black', position: { col: c, row: 1 } });
  });

  // Red Pieces (Bottom)
  // Row 8 (y=8): Main intersections 0, 2, 4, 6, 8
  [0, 2, 4, 6, 8].forEach(c => {
    pieces.push({ id: `r-${idCounter++}`, player: 'red', position: { col: c, row: 8 } });
  });
  // Row 7 (y=7): Diagonal intersections 1, 3, 5, 7
  [1, 3, 5, 7].forEach(c => {
    pieces.push({ id: `r-${idCounter++}`, player: 'red', position: { col: c, row: 7 } });
  });

  return {
    pieces,
    currentPlayer: 'red',
    selectedPieceId: null,
    winner: null,
    history: ['游戏开始。红方先行。'],
    lastMove: null,
  };
};

// 页面左右留白（p-4 ×2）
const PAGE_GUTTER_PX = 32;

// 按视口宽度计算棋盘缩放比例，小屏等比缩小，大屏保持原尺寸
const calcBoardScale = () =>
  Math.min(1, (window.innerWidth - PAGE_GUTTER_PX) / BOARD_OUTER_PX);

const CONFETTI_COLORS = ['#ef4444', '#f97316', '#fbbf24', '#22c55e', '#3b82f6', '#a855f7', '#ec4899'];

export default function App() {
  const [gameState, setGameState] = useState<GameState>(createInitialState());
  const [historyStack, setHistoryStack] = useState<GameState[]>([]); // Stack for Undo
  const [showRules, setShowRules] = useState(false);
  const [soundOn, setSoundOn] = useState(true);
  const [explosions, setExplosions] = useState<ExplosionEffect[]>([]);
  const [shaking, setShaking] = useState(false);
  const shakeTimer = useRef<number | null>(null);
  const [boardScale, setBoardScale] = useState(calcBoardScale);

  useEffect(() => {
    const onResize = () => setBoardScale(calcBoardScale());
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  // Check for win condition
  useEffect(() => {
    const redCount = gameState.pieces.filter(p => p.player === 'red' && !p.isDead).length;
    const blackCount = gameState.pieces.filter(p => p.player === 'black' && !p.isDead).length;

    if (redCount < 2 && gameState.winner === null) {
      setGameState(prev => ({ ...prev, winner: 'black', history: [...prev.history, '黑方胜！'] }));
    } else if (blackCount < 2 && gameState.winner === null) {
      setGameState(prev => ({ ...prev, winner: 'red', history: [...prev.history, '红方胜！'] }));
    }
  }, [gameState.pieces, gameState.winner]);

  // Win fanfare
  useEffect(() => {
    if (gameState.winner) {
      playWin();
    }
  }, [gameState.winner]);

  const toggleSound = () => {
    setSoundOn(prev => {
      setMuted(prev); // prev=true means we're turning sound OFF
      return !prev;
    });
  };

  const triggerShake = () => {
    playInvalid();
    setShaking(true);
    if (shakeTimer.current) window.clearTimeout(shakeTimer.current);
    shakeTimer.current = window.setTimeout(() => setShaking(false), 320);
  };

  const handleRestart = () => {
    playSelect();
    setGameState(createInitialState());
    setHistoryStack([]);
    setExplosions([]);
  };

  const handleUndo = () => {
    if (historyStack.length === 0) return;

    playUndo();
    const previousState = historyStack[historyStack.length - 1];
    const newStack = historyStack.slice(0, -1);

    setGameState(previousState);
    setHistoryStack(newStack);
    setExplosions([]);
  };

  const handlePieceSelect = (pieceId: string) => {
    if (gameState.winner) return;

    const piece = gameState.pieces.find(p => p.id === pieceId);
    if (!piece) return;
    if (piece.player !== gameState.currentPlayer) {
      // 点了对方棋子：给出无效反馈
      if (gameState.selectedPieceId) triggerShake();
      return;
    }

    playSelect();
    setGameState(prev => ({
      ...prev,
      selectedPieceId: pieceId,
    }));
  };

  const handleMove = (target: Position) => {
    if (gameState.winner || !gameState.selectedPieceId) return;

    const pieceIndex = gameState.pieces.findIndex(p => p.id === gameState.selectedPieceId);
    if (pieceIndex === -1) return;

    const piece = gameState.pieces[pieceIndex];

    // Check if move is valid
    if (!isValidMove(piece.position, target, gameState.pieces)) {
      // If clicked on another own piece, switch selection
      const targetPiece = gameState.pieces.find(p => p.position.col === target.col && p.position.row === target.row && !p.isDead);
      if (targetPiece && targetPiece.player === gameState.currentPlayer) {
        playSelect();
        setGameState(prev => ({ ...prev, selectedPieceId: targetPiece.id }));
      } else {
        triggerShake();
      }
      return;
    }

    // Save current state to history stack before modifying
    setHistoryStack(prev => [...prev, gameState]);

    // Execute Move
    const from = piece.position;
    const newPieces = [...gameState.pieces];
    newPieces[pieceIndex] = { ...piece, position: target };

    // Check Captures (The Pinch Logic)
    const capturedIds = checkCaptures(target, gameState.currentPlayer, newPieces);

    // 被吃掉的棋子标记 isDead（保留在数组中，便于统计阵亡数）
    const finalPieces = newPieces.map(p =>
      capturedIds.includes(p.id) ? { ...p, isDead: true } : p
    );

    // 音效 + 爆炸特效
    if (capturedIds.length > 0) {
      playCapture(capturedIds.length);
      const effects: ExplosionEffect[] = capturedIds.map((id, i) => {
        const dead = newPieces.find(p => p.id === id)!;
        return { key: Date.now() + i + Math.random(), position: dead.position, player: dead.player };
      });
      setExplosions(prev => [...prev, ...effects]);
      const keys = effects.map(e => e.key);
      window.setTimeout(() => {
        setExplosions(prev => prev.filter(e => !keys.includes(e.key)));
      }, 900);
    } else {
      playMove();
    }

    // Convert coords to readable grid (1-5) for log
    const logCol = Math.floor(target.col / 2) + 1;
    const logRow = Math.floor(target.row / 2) + 1;
    const isHalfStep = target.col % 2 !== 0;
    const coordStr = isHalfStep ? `(斜线中心)` : `(${logCol},${logRow})`;

    const playerName = gameState.currentPlayer === 'red' ? '红方' : '黑方';
    const moveLog = `${playerName} 移至 ${coordStr}`;
    const captureLog = capturedIds.length > 0 ? ` 💥 吃掉 ${capturedIds.length} 子！` : '。';

    setGameState({
      pieces: finalPieces,
      currentPlayer: gameState.currentPlayer === 'red' ? 'black' : 'red',
      selectedPieceId: null,
      winner: null,
      history: [...gameState.history, moveLog + captureLog].slice(-12),
      lastMove: { from, to: target },
    });
  };

  // Logic: Is Valid Move?
  const isValidMove = (start: Position, end: Position, pieces: Piece[]): boolean => {
    // 0. Check bounds and validity of the node (Must be on grid or center)
    // Valid nodes are where col%2 == row%2. (0,0) valid, (1,1) valid, (0,1) invalid.
    if (end.col % 2 !== end.row % 2) return false;

    // 1. Check if target is occupied
    if (pieces.some(p => p.position.col === end.col && p.position.row === end.row && !p.isDead)) return false;

    const dx = end.col - start.col;
    const dy = end.row - start.row;

    if (dx === 0 && dy === 0) return false;

    // 2. Determine direction and step size
    let step = 0;

    // Diagonal Move: dx == dy (in magnitude). Step size on grid is 1.
    // Diagonal moves are allowed from everywhere (Main or Center).
    if (Math.abs(dx) === Math.abs(dy)) {
      step = 1;
    }
    // Orthogonal Move: dx or dy is 0.
    else if (dx === 0 || dy === 0) {
      // Must be even distance for orthogonal
      if (Math.abs(dx) % 2 !== 0 || Math.abs(dy) % 2 !== 0) return false;

      // RULE: Orthogonal moves are only allowed along main grid lines (Even coordinates).
      // If start is a Center (odd coordinates), no orthogonal lines exist.
      if (start.col % 2 !== 0 || start.row % 2 !== 0) return false;

      step = 2;
    } else {
      return false; // Not a straight line
    }

    // 3. Check obstacles along the path
    const stepX = (dx === 0 ? 0 : dx / Math.abs(dx)) * step;
    const stepY = (dy === 0 ? 0 : dy / Math.abs(dy)) * step;

    // Iterate from start + step to end - step
    let currentX = start.col + stepX;
    let currentY = start.row + stepY;

    while (Math.abs(currentX - start.col) < Math.abs(dx) || Math.abs(currentY - start.row) < Math.abs(dy)) {
      if (pieces.some(p => p.position.col === currentX && p.position.row === currentY && !p.isDead)) {
        return false; // Blocked
      }
      currentX += stepX;
      currentY += stepY;
    }

    return true;
  };

  // Logic: Check Captures (Pinch/Sandwich)
  const checkCaptures = (pos: Position, player: Player, pieces: Piece[]): string[] => {
    const captured: string[] = [];

    // Directions defined as [dx, dy, stepSize]
    const directions = [
      // Orthogonal (Step 2)
      { x: 0, y: 1, step: 2 }, { x: 0, y: -1, step: 2 },
      { x: 1, y: 0, step: 2 }, { x: -1, y: 0, step: 2 },
      // Diagonal (Step 1)
      { x: 1, y: 1, step: 1 }, { x: -1, y: -1, step: 1 },
      { x: 1, y: -1, step: 1 }, { x: -1, y: 1, step: 1 }
    ];

    directions.forEach(dir => {
      // RULE: If we are at a Center (Odd coordinates), we cannot pinch orthogonally because no line exists.
      if ((pos.col % 2 !== 0) && dir.step === 2) return;

      let potentialCaptures: string[] = [];
      let foundPartner = false;

      // Look outward from the new position
      for (let i = 1; i < BOARD_SIZE; i++) {
        const checkCol = pos.col + (dir.x * i * dir.step);
        const checkRow = pos.row + (dir.y * i * dir.step);

        // Check bounds
        if (checkCol < 0 || checkCol >= BOARD_SIZE || checkRow < 0 || checkRow >= BOARD_SIZE) break;

        const p = pieces.find(p => p.position.col === checkCol && p.position.row === checkRow && !p.isDead);

        if (!p) break; // Empty space breaks the chain

        if (p.player !== player) {
          potentialCaptures.push(p.id);
        } else {
          // Found a friendly piece sandwiching the enemies
          if (potentialCaptures.length > 0) {
            foundPartner = true;
          }
          break; // Stop looking either way
        }
      }

      if (foundPartner) {
        captured.push(...potentialCaptures);
      }
    });

    return captured;
  };

  // 计分统计
  const redAlive = gameState.pieces.filter(p => p.player === 'red' && !p.isDead).length;
  const blackAlive = gameState.pieces.filter(p => p.player === 'black' && !p.isDead).length;
  const redDead = gameState.pieces.filter(p => p.player === 'red' && p.isDead).length;
  const blackDead = gameState.pieces.filter(p => p.player === 'black' && p.isDead).length;

  const PlayerBadge = ({ player }: { player: Player }) => {
    const isActive = gameState.currentPlayer === player && !gameState.winner;
    const isRed = player === 'red';
    const alive = isRed ? redAlive : blackAlive;
    return (
      <div
        key={`${player}-${isActive}`}
        className={`flex items-center gap-2 px-4 py-1.5 rounded-full transition-all duration-300 font-serif font-bold
          ${isActive
            ? `${isRed ? 'bg-red-600' : 'bg-stone-900'} text-white shadow-lg animate-turn-pop`
            : 'bg-white/70 text-stone-400'}
        `}
      >
        <div className={`w-2.5 h-2.5 rounded-full ${isActive ? 'bg-white animate-pulse' : isRed ? 'bg-red-300' : 'bg-stone-400'}`}></div>
        {isRed ? '红方' : '黑方'}
        <span className={`text-xs font-mono ${isActive ? 'text-white/80' : 'text-stone-400'}`}>×{alive}</span>
      </div>
    );
  };

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-4 bg-gradient-to-br from-stone-200 via-amber-50 to-stone-300 text-stone-800">

      <div className="w-full max-w-[1200px] flex flex-col lg:flex-row gap-8 items-center lg:items-start justify-center">

        {/* Game Board Section */}
        <div className="flex flex-col items-center gap-4 flex-shrink-0">
          {/* Header Info */}
          <div className="flex justify-between items-center" style={{ width: BOARD_OUTER_PX * boardScale }}>
            <PlayerBadge player="black" />
            <PlayerBadge player="red" />
          </div>

          {/* 占位容器按缩放后的尺寸排版，内层保持原始像素坐标整体缩放 */}
          <div style={{ width: BOARD_OUTER_PX * boardScale, height: BOARD_OUTER_PX * boardScale }}>
            <div
              className="relative"
              style={{
                width: BOARD_OUTER_PX,
                height: BOARD_OUTER_PX,
                transform: `scale(${boardScale})`,
                transformOrigin: 'top left',
              }}
            >

              <Board
                gameState={gameState}
                explosions={explosions}
                shaking={shaking}
                onPieceSelect={handlePieceSelect}
                onMove={handleMove}
                onInvalidClick={triggerShake}
                isValidMove={isValidMove}
              />

              {/* Winner Overlay */}
              {gameState.winner && (
                <div className="absolute inset-0 bg-black/30 backdrop-blur-[3px] flex items-center justify-center rounded-lg z-50 overflow-hidden">
                  {/* 彩带 */}
                  {Array.from({ length: 28 }).map((_, i) => (
                    <div
                      key={i}
                      className="confetti"
                      style={{
                        left: `${(i * 37) % 100}%`,
                        background: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
                        animationDuration: `${2.2 + (i % 5) * 0.45}s`,
                        animationDelay: `${(i % 7) * 0.25}s`,
                      }}
                    />
                  ))}
                  <div className="bg-white/95 p-8 rounded-2xl shadow-2xl flex flex-col items-center animate-pop-in">
                    <Trophy className={`w-14 h-14 mb-4 animate-trophy ${gameState.winner === 'red' ? 'text-red-500' : 'text-stone-800'}`} />
                    <h2 className={`text-3xl font-serif font-bold mb-1 tracking-widest ${gameState.winner === 'red' ? 'text-red-600' : 'text-stone-900'}`}>
                      {gameState.winner === 'red' ? '红方' : '黑方'} 胜利!
                    </h2>
                    <p className="text-sm text-stone-400 mb-4 font-mono">
                      红 {redAlive} : {blackAlive} 黑
                    </p>
                    <button
                      onClick={handleRestart}
                      className="mt-2 px-8 py-2.5 bg-stone-800 text-white rounded-full hover:bg-stone-700 hover:scale-105 active:scale-95 transition-all shadow-lg"
                    >
                      再来一局
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Sidebar Controls */}
        <div className="flex flex-col gap-5 bg-white/90 backdrop-blur p-6 rounded-2xl shadow-xl border border-stone-200 w-full lg:w-[320px] lg:mt-[52px]">

          <div className="space-y-1">
            <h1 className="text-3xl font-serif font-bold text-stone-800">坦克大战</h1>
            <h2 className="text-xs font-medium text-stone-500 uppercase tracking-widest">传统民间策略棋 · 夹击吃子</h2>
          </div>

          {/* 战况计分板 */}
          <div className="grid grid-cols-2 gap-2 text-sm">
            <div className={`rounded-xl p-3 border transition-all ${gameState.currentPlayer === 'red' && !gameState.winner ? 'border-red-300 bg-red-50 shadow-sm' : 'border-stone-100 bg-stone-50'}`}>
              <div className="flex items-center gap-1.5 font-bold text-red-600 mb-1">
                <span className="w-2.5 h-2.5 rounded-full bg-red-500 inline-block"></span> 红方
              </div>
              <div className="text-stone-500 text-xs">存活 <b className="text-stone-800 text-sm">{redAlive}</b> · 阵亡 <b className="text-stone-800 text-sm">{redDead}</b></div>
            </div>
            <div className={`rounded-xl p-3 border transition-all ${gameState.currentPlayer === 'black' && !gameState.winner ? 'border-stone-400 bg-stone-100 shadow-sm' : 'border-stone-100 bg-stone-50'}`}>
              <div className="flex items-center gap-1.5 font-bold text-stone-800 mb-1">
                <span className="w-2.5 h-2.5 rounded-full bg-stone-800 inline-block"></span> 黑方
              </div>
              <div className="text-stone-500 text-xs">存活 <b className="text-stone-800 text-sm">{blackAlive}</b> · 阵亡 <b className="text-stone-800 text-sm">{blackDead}</b></div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={handleRestart}
              className="flex items-center justify-center gap-2 px-3 py-3 bg-stone-800 text-stone-100 rounded-lg hover:bg-stone-700 transition-all active:scale-95 text-sm font-medium"
            >
              <RotateCcw size={16} /> 新游戏
            </button>
            <button
              onClick={handleUndo}
              disabled={historyStack.length === 0}
              className={`flex items-center justify-center gap-2 px-3 py-3 rounded-lg transition-all text-sm font-medium
                ${historyStack.length === 0
                  ? 'bg-stone-100 text-stone-300 cursor-not-allowed'
                  : 'bg-stone-200 text-stone-700 hover:bg-stone-300 active:scale-95'}
              `}
            >
              <Undo2 size={16} /> 悔棋
            </button>
            <button
              onClick={() => setShowRules(!showRules)}
              className="flex items-center justify-center gap-2 px-3 py-2 bg-stone-100 text-stone-600 rounded-lg hover:bg-stone-200 transition-all text-sm font-medium"
            >
              <Info size={16} /> {showRules ? '隐藏规则' : '规则'}
            </button>
            <button
              onClick={toggleSound}
              className={`flex items-center justify-center gap-2 px-3 py-2 rounded-lg transition-all text-sm font-medium
                ${soundOn ? 'bg-amber-100 text-amber-700 hover:bg-amber-200' : 'bg-stone-100 text-stone-400 hover:bg-stone-200'}
              `}
            >
              {soundOn ? <Volume2 size={16} /> : <VolumeX size={16} />}
              {soundOn ? '音效开' : '音效关'}
            </button>
          </div>

          {showRules && (
            <div className="text-sm text-stone-600 space-y-2 bg-amber-50 p-4 rounded-lg border border-amber-100 animate-slide-down">
              <p><strong className="text-amber-800">获胜条件：</strong> 吃掉对方棋子，直到对方剩余少于2个。</p>
              <p><strong className="text-amber-800">移动：</strong> 沿棋盘线移动，可停留在任意交叉点或方格中心。</p>
              <p><strong className="text-amber-800">夹击吃子：</strong> 当两枚己方棋子在一条直线上紧紧夹住对方一枚或多枚棋子时（如 红-黑-红），对方棋子即被消灭。</p>
            </div>
          )}

          <div className="flex-1 bg-stone-50 rounded-lg p-4 border border-stone-100 overflow-hidden flex flex-col min-h-[220px] shadow-inner">
            <h3 className="text-xs font-bold text-stone-400 uppercase tracking-wider mb-3">对战记录</h3>
            <div className="flex-1 overflow-y-auto space-y-2 font-mono text-xs text-stone-600 log-scroll">
              {[...gameState.history].reverse().map((log, i) => (
                <div
                  key={gameState.history.length - i}
                  className={`border-b border-stone-100 pb-1 last:border-0 ${i === 0 ? 'font-bold text-stone-800' : ''} ${log.includes('💥') ? 'text-orange-600' : ''}`}
                >
                  {log}
                </div>
              ))}
              {gameState.history.length === 0 && <span className="text-stone-300 italic">暂无走棋记录...</span>}
            </div>
          </div>

        </div>

      </div>
    </div>
  );
}
