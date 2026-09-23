import { useState } from 'react';
import type { MediaItem } from '../api/types';

/** Photo/video gallery with thumbnails and a lightbox viewer. */
export default function ImageGallery({
  media,
  title,
}: {
  media: MediaItem[];
  title: string;
}) {
  const [active, setActive] = useState(0);
  const [lightbox, setLightbox] = useState(false);

  if (media.length === 0) {
    return (
      <div className="flex aspect-video items-center justify-center rounded-xl bg-stone-200 text-sm text-stone-500">
        No media uploaded
      </div>
    );
  }

  const current = media[Math.min(active, media.length - 1)];

  const viewer = (large: boolean) => (
    <div
      className={
        large
          ? 'flex max-h-[80vh] items-center justify-center'
          : 'aspect-video w-full cursor-zoom-in overflow-hidden rounded-xl bg-stone-900'
      }
      onClick={() => !large && setLightbox(true)}
    >
      {current.type === 'video' ? (
        <video
          src={current.url}
          controls
          onClick={(e) => e.stopPropagation()}
          className={large ? 'max-h-[80vh] w-auto' : 'h-full w-full object-contain'}
        />
      ) : (
        <img
          src={current.url}
          alt={title}
          className={large ? 'max-h-[80vh] w-auto object-contain' : 'h-full w-full object-contain'}
        />
      )}
    </div>
  );

  return (
    <div>
      {viewer(false)}

      {media.length > 1 && (
        <div className="mt-3 grid grid-cols-5 gap-2">
          {media.map((m, i) => (
            <button
              key={i}
              onClick={() => setActive(i)}
              className={`relative aspect-square overflow-hidden rounded-lg bg-stone-900 ring-2 ${
                i === active ? 'ring-gold-400' : 'ring-transparent'
              }`}
            >
              {m.type === 'video' ? (
                <span className="flex h-full w-full items-center justify-center text-xl text-white">
                  ▶
                </span>
              ) : (
                <img src={m.url} alt={`${title} ${i + 1}`} className="h-full w-full object-cover" />
              )}
            </button>
          ))}
        </div>
      )}

      {lightbox && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setLightbox(false)}
        >
          <button
            className="absolute right-4 top-4 rounded-full bg-white/10 px-3 py-2 text-lg text-white hover:bg-white/20"
            aria-label="Close"
          >
            ✕
          </button>
          {viewer(true)}
        </div>
      )}
    </div>
  );
}
