import { useEffect, useRef, useState, type ReactNode } from 'react';

export const ROW_CHUNK_SIZE = 32;
/** Keep variable-height titles and slot buttons intact; mount only nearby chunks.
 * Placeholder heights are measured before unmount, so scrolling back is stable.
 * Focused chunks stay mounted and keyboard traversal preloads adjacent chunks.
 */
export function WindowedRows<T>({ items, renderRow, estimatedHeight = 72, pinnedIndex = -1 }: { pinnedIndex?: number; items: T[]; renderRow: (item: T) => ReactNode; estimatedHeight?: number }) {
  const host = useRef<HTMLDivElement>(null);
  const heights = useRef(new Map<number, number>());
  const [focused, setFocused] = useState<number | null>(null);
  const [visible, setVisible] = useState(() => new Set([0]));
  const count = Math.ceil(items.length / ROW_CHUNK_SIZE);
  useEffect(() => {
    const element = host.current;
    if (!element || items.length <= 150) return;
    let root: HTMLElement | null = element.parentElement;
    while (root && !/(auto|scroll)/.test(getComputedStyle(root).overflowY)) root = root.parentElement;
    const observer = new IntersectionObserver(entries => {
      setVisible(previous => {
        const next = new Set(previous);
        for (const entry of entries) {
          const index = Number((entry.target as HTMLElement).dataset.chunk);
          if (entry.isIntersecting) next.add(index);
          else {
            heights.current.set(index, entry.target.getBoundingClientRect().height);
            next.delete(index);
          }
        }
        return next.size === previous.size && [...next].every(index => previous.has(index)) ? previous : next;
      });
    }, { root, rootMargin: '500px 0px' });
    element.querySelectorAll('[data-chunk]').forEach(chunk => observer.observe(chunk));
    return () => observer.disconnect();
  }, [items.length]);
  if (items.length <= 150) return <>{items.map(renderRow)}</>;
  return <div ref={host} className="windowed-rows" data-total-rows={items.length} onFocusCapture={event => {
    const chunk = (event.target as HTMLElement).closest<HTMLElement>('[data-chunk]');
    if (!chunk) return;
    const index = Number(chunk.dataset.chunk);
    setFocused(index);
  }} onBlurCapture={event => { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setFocused(null); }}>
    {Array.from({ length: count }, (_, index) => {
      const from = index * ROW_CHUNK_SIZE;
      const height = heights.current.get(index) ?? Math.min(ROW_CHUNK_SIZE, items.length - from) * estimatedHeight;
      const mounted = visible.has(index) || Math.floor(pinnedIndex / ROW_CHUNK_SIZE) === index || (focused !== null && Math.abs(focused - index) <= 1);
      return <div key={index} data-chunk={index} style={mounted ? undefined : { height }} aria-hidden={mounted ? undefined : true}>
        {mounted ? items.slice(from, from + ROW_CHUNK_SIZE).map(renderRow) : null}
      </div>;
    })}
  </div>;
}
