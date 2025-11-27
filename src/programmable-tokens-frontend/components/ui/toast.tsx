"use client";

import { useToast, type Toast as ToastType } from "./use-toast";
import { cn } from "@/lib/utils";
import { X, CheckCircle2, XCircle, AlertCircle, Info } from "lucide-react";

export function Toaster() {
  const { toasts, dismiss } = useToast();

  return (
    <div className="fixed top-0 right-0 z-50 w-full md:max-w-md p-4 md:p-6 pointer-events-none">
      <div className="flex flex-col gap-2">
        {toasts.map((toast) => (
          <Toast key={toast.id} toast={toast} onDismiss={() => dismiss(toast.id)} />
        ))}
      </div>
    </div>
  );
}

interface ToastProps {
  toast: ToastType;
  onDismiss: () => void;
}

function Toast({ toast, onDismiss }: ToastProps) {
  const variants = {
    default: {
      container: "bg-dark-800 border-dark-700",
      icon: null,
    },
    success: {
      container: "bg-dark-800 border-primary-500/50",
      icon: <CheckCircle2 className="h-5 w-5 text-primary-500" />,
    },
    error: {
      container: "bg-dark-800 border-red-500/50",
      icon: <XCircle className="h-5 w-5 text-red-500" />,
    },
    warning: {
      container: "bg-dark-800 border-accent-500/50",
      icon: <AlertCircle className="h-5 w-5 text-accent-500" />,
    },
    info: {
      container: "bg-dark-800 border-blue-500/50",
      icon: <Info className="h-5 w-5 text-blue-500" />,
    },
  };

  const variant = variants[toast.variant || "default"];

  return (
    <div
      className={cn(
        "pointer-events-auto flex items-start gap-3 rounded-lg border p-4 shadow-lg",
        "animate-in slide-in-from-top-5 fade-in",
        variant.container
      )}
    >
      {variant.icon && <div className="mt-0.5">{variant.icon}</div>}
      <div className="flex-1 space-y-1">
        {toast.title && (
          <p className="text-sm font-semibold text-white">{toast.title}</p>
        )}
        {toast.description && (
          <p className="text-sm text-dark-300">{toast.description}</p>
        )}
      </div>
      <button
        onClick={onDismiss}
        className="text-dark-400 hover:text-white transition-colors"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}

export { Toast, useToast };
