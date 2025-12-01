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
