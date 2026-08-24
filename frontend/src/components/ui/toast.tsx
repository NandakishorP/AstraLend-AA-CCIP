"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { cx, Spinner } from "./primitives";

export type ToastTone = "info" | "success" | "error" | "pending";

export interface Toast {
  id: number;
  tone: ToastTone;
  title: string;
  body?: string;
  /** Rendered under the body — used for explorer links on transaction toasts. */
  link?: { href: string; label: string };
}

interface ToastApi {
  push: (toast: Omit<Toast, "id">) => number;
  update: (id: number, toast: Partial<Omit<Toast, "id">>) => void;
  dismiss: (id: number) => void;
}

const ToastContext = createContext<ToastApi>({
  push: () => 0,
  update: () => {},
  dismiss: () => {},
});

export function useToast(): ToastApi {
  return useContext(ToastContext);
}

/** Errors and pending states stay until dismissed or replaced; the rest expire. */
const AUTO_DISMISS_MS: Record<ToastTone, number | null> = {
  info: 5_000,
  success: 8_000,
  error: null,
  pending: null,
};

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((toast) => toast.id !== id));
  }, []);

  const scheduleDismiss = useCallback(
    (id: number, tone: ToastTone) => {
      const delay = AUTO_DISMISS_MS[tone];
      if (delay === null) return;
      window.setTimeout(() => dismiss(id), delay);
    },
    [dismiss]
  );

  const push = useCallback(
    (toast: Omit<Toast, "id">) => {
      const id = Date.now() + Math.random();
      setToasts((current) => [...current, { ...toast, id }]);
      scheduleDismiss(id, toast.tone);
      return id;
    },
    [scheduleDismiss]
  );

  const update = useCallback(
    (id: number, patch: Partial<Omit<Toast, "id">>) => {
      setToasts((current) =>
        current.map((toast) => (toast.id === id ? { ...toast, ...patch } : toast))
      );
      // A toast that transitions out of `pending` needs a fresh expiry clock.
      if (patch.tone) scheduleDismiss(id, patch.tone);
    },
    [scheduleDismiss]
  );

  const api = useMemo(() => ({ push, update, dismiss }), [push, update, dismiss]);

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className="pointer-events-none fixed bottom-4 right-4 z-100 flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-2">
        {toasts.map((toast) => (
          <ToastCard key={toast.id} toast={toast} onDismiss={() => dismiss(toast.id)} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastCard({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  const accent: Record<ToastTone, string> = {
    info: "border-l-glow",
    success: "border-l-mint",
    error: "border-l-rose",
    pending: "border-l-astra-400",
  };

  return (
    <div
      role="status"
      className={cx(
        "pointer-events-auto animate-rise rounded-xl border border-hairline border-l-2 bg-surface/95 p-3.5 shadow-2xl backdrop-blur-xl",
        accent[toast.tone]
      )}
    >
      <div className="flex items-start gap-3">
        {toast.tone === "pending" ? <Spinner className="mt-0.5 text-astra-400" /> : null}
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-ink">{toast.title}</p>
          {toast.body ? (
            <p className="mt-1 break-words text-xs leading-relaxed text-ink-muted">{toast.body}</p>
          ) : null}
          {toast.link ? (
            <a
              href={toast.link.href}
              target="_blank"
              rel="noreferrer"
              className="mt-2 inline-flex text-xs font-medium text-astra-200 underline-offset-4 hover:underline"
            >
              {toast.link.label} ↗
            </a>
          ) : null}
        </div>
        <button
          onClick={onDismiss}
          className="-m-1 rounded-lg p-1 text-ink-faint transition hover:bg-surface-2 hover:text-ink"
          aria-label="Dismiss notification"
        >
          <svg viewBox="0 0 16 16" className="size-3.5" fill="none" stroke="currentColor" strokeWidth="1.8">
            <path d="M3 3l10 10M13 3L3 13" strokeLinecap="round" />
          </svg>
        </button>
      </div>
    </div>
  );
}
