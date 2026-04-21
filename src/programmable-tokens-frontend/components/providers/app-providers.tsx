"use client";

import { ReactNode } from "react";
import { WalletProvider } from "@/contexts/wallet-context";
import { Header } from "@/components/layout/header";
import { Footer } from "@/components/layout/footer";
import { Toaster } from "@/components/ui/toast";
import { ProtocolVersionProvider } from "@/contexts/protocol-version-context";
import { CIP113Provider } from "@/contexts/cip113-context";

interface AppProvidersProps {
  children: ReactNode;
}

export function AppProviders({ children }: AppProvidersProps) {
  return (
    <WalletProvider>
      <ProtocolVersionProvider>
        <CIP113Provider>
          <div className="flex flex-col min-h-screen bg-dark-900">
            <Header />
            <main className="flex-1">{children}</main>
            <Footer />
            <Toaster />
          </div>
        </CIP113Provider>
      </ProtocolVersionProvider>
    </WalletProvider>
  );
}
