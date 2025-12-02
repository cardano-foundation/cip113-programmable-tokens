/**
 * Root Layout
 *
 * The root layout component that wraps all pages in the application.
 * Sets up fonts, metadata, and the client-side layout wrapper.
 *
 * ## Metadata
 * - Title and description for SEO
 * - OpenGraph and Twitter cards for social sharing
 * - Proper meta tags for search engines
 *
 * ## Structure
 * - Inter font from Google Fonts
 * - ClientLayout wraps children for Mesh SDK compatibility
 * - Global CSS imports
 *
 * @module app/layout
 */

import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { ClientLayout } from "@/components/layout/client-layout";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "CIP-113 Programmable Tokens",
  description: "Create and manage regulated tokens on Cardano with embedded validation logic",
  keywords: ["Cardano", "CIP-113", "Programmable Tokens", "Smart Contracts", "DeFi", "Blockchain"],
  authors: [{ name: "Cardano Foundation" }],
  creator: "Cardano Foundation",
  publisher: "Cardano Foundation",
  metadataBase: new URL(process.env.NEXT_PUBLIC_BASE_URL || 'http://localhost:3000'),
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "./",
    title: "CIP-113 Programmable Tokens",
    description: "Create and manage regulated tokens on Cardano with embedded validation logic",
    siteName: "CIP-113 Programmable Tokens",
    images: [
      {
        url: "/opengraph-image",
        width: 1200,
        height: 630,
        alt: "CIP-113 Programmable Tokens",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "CIP-113 Programmable Tokens",
    description: "Create and manage regulated tokens on Cardano with embedded validation logic",
    images: ["/twitter-image"],
    creator: "@Cardano_CF",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  icons: {
    icon: "/icon.svg",
    apple: "/icon.svg",
  },
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
