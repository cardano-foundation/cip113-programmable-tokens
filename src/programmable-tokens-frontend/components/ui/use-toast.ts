/**
 * Toast State Management Hook
 *
 * A lightweight toast notification system using React state and
 * external memory store for cross-component access.
 *
 * ## Architecture
 * - Uses memory-based state to allow toasts from non-React contexts
 * - Listener pattern for reactive updates across components
 * - Auto-dismissal with configurable duration
 *
 * ## Toast Properties
 * - **id**: Auto-generated unique identifier
 * - **title**: Main toast heading (optional)
 * - **description**: Toast body text (optional)
 * - **variant**: Visual style (success, error, warning, info)
 * - **duration**: Auto-dismiss time in ms (default 5000, Infinity to persist)
 *
 * @module components/ui/use-toast
 *
 * @example
 * ```tsx
 * const { toast, dismiss } = useToast();
 *
 * // Show success toast
 * toast({
 *   variant: 'success',
 *   title: 'Minted!',
 *   description: 'Token minted successfully',
 * });
 *
 * // Show persistent error
 * toast({
 *   variant: 'error',
 *   title: 'Failed',
 *   duration: Infinity,
 * });
 * ```
 */

"use client";

import { useState, useCallback } from "react";

export type ToastVariant = "default" | "success" | "error" | "warning" | "info" | "destructive";

export interface Toast {
  id: string;
  title?: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
}

interface ToastState {
  toasts: Toast[];
}

let toastCounter = 0;
const listeners = new Set<(state: ToastState) => void>();
let memoryState: ToastState = { toasts: [] };

function dispatch(action: { type: string; toast?: Toast; toastId?: string }) {
  if (action.type === "ADD_TOAST") {
    const id = (++toastCounter).toString();
    const toast = {
      ...action.toast!,
      id,
      duration: action.toast!.duration ?? 5000,
    };

    memoryState.toasts = [...memoryState.toasts, toast];

    if (toast.duration !== Infinity) {
      setTimeout(() => {
        dispatch({ type: "DISMISS_TOAST", toastId: id });
      }, toast.duration);
    }
  } else if (action.type === "DISMISS_TOAST") {
    memoryState.toasts = memoryState.toasts.filter((t) => t.id !== action.toastId);
  } else if (action.type === "REMOVE_TOAST") {
    memoryState.toasts = memoryState.toasts.filter((t) => t.id !== action.toastId);
  }

  listeners.forEach((listener) => listener(memoryState));
}

export function useToast() {
  const [state, setState] = useState<ToastState>(memoryState);

  useState(() => {
    listeners.add(setState);
    return () => {
      listeners.delete(setState);
    };
  });

  const toast = useCallback(
    (props: Omit<Toast, "id">) => {
      dispatch({ type: "ADD_TOAST", toast: props as Toast });
    },
    []
  );

  const dismiss = useCallback((toastId: string) => {
    dispatch({ type: "DISMISS_TOAST", toastId });
  }, []);

  return {
    toasts: state.toasts,
    toast,
    dismiss,
  };
}
