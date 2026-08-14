/**
 * Adds all numbers given and returns the total.
 *
 * @param nums - The values to sum; at least one is expected.
 * @returns The sum of `nums`.
 */
export function sum(...nums: number[]): number {
  return nums.reduce((a, b) => a + b, 0);
}

/**
 * Renders a number as a fixed-length string.
 *
 * @param value - The value to format.
 * @param precision - Decimal places to keep; defaults to `2`.
 * @returns The formatted string.
 */
export function format(value: number, precision = 2): string {
  return value.toFixed(precision);
}

/**
 * Maps a list through a transform while skipping `null`/`undefined` entries.
 *
 * @param items - The input list.
 * @param fn - Transform applied to each non-null item.
 * @returns The transformed list with nulls removed.
 */
export function compactMap<T, U>(
  items: readonly T[],
  fn: (item: T, index: number) => U | null | undefined
): U[] {
  const result: U[] = [];
  items.forEach((item, index) => {
    const mapped = fn(item, index);
    if (mapped != null) result.push(mapped);
  });
  return result;
}
