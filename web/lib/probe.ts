// Throwaway file for testing the coverage gate on a real PR (#129). Never merged.
export function probe(n: number): number {
  if (n > 10) {
    return n * 2;
  }
  return n + 1;
}

export function probe2(n: number): number {
  return n - 1;
}
