import { editDistance, similarity, longestCommonSubsequence } from '../utils/Levenshtein';
import { Sentence } from '../model/Sentence';

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

/**
 * 片假名 -> 平假名（U+30A1..U+30F6 偏移 -0x60）
 * ASR 输出常含片假名，而句子读音数据为平假名，归一化后才能在同一音位空间比较
 */
function katakanaToHiragana(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0x30A1 && code <= 0x30F6) {
      out += String.fromCharCode(code - 0x60);
    } else {
      out += text.charAt(i);
    }
  }
  return out;
}

export function normalize(text: string): string {
  return katakanaToHiragana(text.replace(PUNCT_REGEX, '')).toLowerCase();
}

/**
 * 从振假名分段构建整句读音（纯假名形式）。
 * 汉字段取 kana，其余取原文；无 segments 时回退到 japanese 原文。
 *
 * 用于跟读评分：ASR 对同一发音的输出可能是假名（このちかくにえき…），
 * 而 japanese 原文含汉字（この近くに駅…），直接比较会把"读对了"误判成低分。
 * 以读音为基准比较，评的是"发音对不对"而非"汉字写没写对"。
 */
export function getSentenceReading(sentence: Sentence): string {
  const segs = sentence.segments;
  if (!segs || segs.length === 0) {
    return sentence.japanese;
  }
  let reading = '';
  for (const seg of segs) {
    reading += (seg.kana && seg.kana.length > 0) ? seg.kana : seg.text;
  }
  return reading;
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

/**
 * 双基准匹配：同时与汉字原文、假名读音比较，取相似度更高的结果。
 * ASR 对同一发音可能输出汉字或假名，双基准取优避免"读对了却被汉字形式拉低分"。
 * 高亮数据取自更优的那次匹配（若读音更优，originalHighlighted 为假名序列）。
 */
export function matchWithReading(userText: string, originalText: string, readingText: string): MatchResult {
  const byOriginal = match(userText, originalText);
  const normReading = normalize(readingText);
  const normOriginal = normalize(originalText);
  if (normReading.length === 0 || normReading === normOriginal) {
    return byOriginal;
  }
  const byReading = match(userText, readingText);
  return byReading.similarity > byOriginal.similarity ? byReading : byOriginal;
}

