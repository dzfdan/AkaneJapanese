/**
 * Levenshtein 编辑距离 + 相似度 + LCS 算法
 * 纯算法，无副作用，可独立测试
 */

export function editDistance(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  const dp: number[][] = [];
  for (let i = 0; i <= m; i++) {
    dp.push(new Array<number>(n + 1).fill(0));
  }
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (a.charAt(i - 1) === b.charAt(j - 1)) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] = 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
      }
    }
  }
  return dp[m][n];
}

export function similarity(a: string, b: string): number {
  if (a.length === 0 && b.length === 0) return 1;
  if (a.length === 0 || b.length === 0) return 0;
  return 1 - editDistance(a, b) / Math.max(a.length, b.length);
}

export function longestCommonSubsequence(a: string, b: string): string {
  const m = a.length;
  const n = b.length;
  const dp: string[][] = [];
  for (let i = 0; i <= m; i++) {
    dp.push(new Array<string>(n + 1).fill(''));
  }
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (a.charAt(i - 1) === b.charAt(j - 1)) {
        dp[i][j] = dp[i - 1][j - 1] + a.charAt(i - 1);
      } else {
        dp[i][j] = dp[i - 1][j].length >= dp[i][j - 1].length ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }
  return dp[m][n];
}

