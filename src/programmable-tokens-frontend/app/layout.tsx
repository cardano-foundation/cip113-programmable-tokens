import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { ClientLayout } from "@/components/layout/client-layout";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "CIP-113 Programmable Tokens",
  description: "Mint and transfer programmable tokens on Cardano",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <ClientLayout>{children}</ClientLayout>
      </body>
    </html>
  );
}
