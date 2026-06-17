export type Player = 'red' | 'black';

export interface Position {
  col: number; // x axis
  row: number; // y axis
}

export interface Piece {
  id: string;
  player: Player;
  position: Position;
  isDead?: boolean;
}

export interface GameState {
  pieces: Piece[];
  currentPlayer: Player;
  selectedPieceId: string | null;
  winner: Player | null;
  history: string[]; // Simple log for debug/display
  lastMove: { from: Position; to: Position } | null;
}

// 0..8 coordinate space (9x9)
// Even indices (0, 2, 4...) are main grid lines.
// Odd indices (1, 3, 5...) are centers of squares.
export const BOARD_SIZE = 9; 
