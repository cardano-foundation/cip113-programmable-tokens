"use client";

import { ReactNode } from "react";
import dynamic from "next/dynamic";

const AppProviders = dynamic(
  () => import("@/components/providers/app-providers").then((mod) => ({ default: mod.AppProviders })),
  { ssr: false }
);

interface ClientLayoutProps {
  children: ReactNode;
}

export function ClientLayout({ children }: ClientLayoutProps) {
  return <AppProviders>{children}</AppProviders>;
}
