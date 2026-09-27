import { editDistance, similarity, longestCommonSubsequence } from '../utils/Levenshtein';

export const THRESHOLD: number = 0.85;

export interface HighlightSegment {
  text: string;
  isDiff: boolean;
}

export interface MatchResult {
  similarity: number;
  isCorrect: boolean;
  userHighlighted: HighlightSegment[];
  originalHighlighted: HighlightSegment[];
}

const PUNCT_REGEX = /[。！？、，．\s　]/g;

export function normalize(text: string): string {
  return text.replace(PUNCT_REGEX, '').toLowerCase();
}

export function match(userText: string, originalText: string): MatchResult {
  const u = normalize(userText);
  const o = normalize(originalText);
  const sim = similarity(u, o);
  const lcs = longestCommonSubsequence(u, o);

  const userHighlighted: HighlightSegment[] = [];
  let li = 0;
  for (let i = 0; i < u.length; i++) {
    if (li < lcs.length && u.charAt(i) === lcs.charAt(li)) {
      userHighlighted.push({ text: u.charAt(i), isDiff: false });
      li++;
    } else {
      userHighlighted.push({ text: u.charAt(i), isDiff: true });
    }
  }

  const originalHighlighted: HighlightSegment[] = [];
  li = 0;
  for (let i = 0; i < o.length; i++) {
    if (li < lcs.length && o.charAt(i) === lcs.charAt(li)) {
      originalHighlighted.push({ text: o.charAt(i), isDiff: false });
      li++;
    } else {
      originalHighlighted.push({ text: o.charAt(i), isDiff: true });
    }
  }

  return {
    similarity: sim,
    isCorrect: sim >= THRESHOLD,
    userHighlighted,
    originalHighlighted,
  };
}

