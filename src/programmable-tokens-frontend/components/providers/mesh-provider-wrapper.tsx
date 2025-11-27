"use client";

import { ReactNode } from "react";
import { MeshProvider } from "@meshsdk/react";

interface MeshProviderWrapperProps {
  children: ReactNode;
}

export function MeshProviderWrapper({ children }: MeshProviderWrapperProps) {
  return <MeshProvider>{children}</MeshProvider>;
}
