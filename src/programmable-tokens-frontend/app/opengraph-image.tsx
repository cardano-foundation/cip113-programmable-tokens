/**
 * OpenGraph Image Generator
 *
 * Dynamically generates the OpenGraph preview image for social sharing.
 * Uses Next.js ImageResponse for edge-rendered image generation.
 *
 * ## Specifications
 * - Size: 1200x630 pixels (OpenGraph standard)
 * - Format: PNG
 * - Runtime: Edge for fast generation
 *
 * ## Design
 * - Dark background (#0F172A)
 * - Green gradient logo
 * - "CIP-113 Programmable Tokens" title
 * - Tagline and Cardano branding
 *
 * @see https://nextjs.org/docs/app/api-reference/file-conventions/metadata/opengraph-image
 * @module app/opengraph-image
 */

import { ImageResponse } from 'next/og';

// Route segment config
export const runtime = 'edge';

// Image metadata
export const alt = 'CIP-113 Programmable Tokens';
export const size = {
  width: 1200,
  height: 630,
};

export const contentType = 'image/png';

// Image generation
export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          background: '#0F172A',
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexDirection: 'column',
          fontFamily: 'system-ui, sans-serif',
        }}
      >
        {/* Logo */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: 160,
            height: 160,
            borderRadius: 32,
            background: 'linear-gradient(135deg, #10B981 0%, #059669 100%)',
            marginBottom: 40,
          }}
        >
          <span
            style={{
              fontSize: 80,
              fontWeight: 'bold',
              color: 'white',
            }}
          >
            PT
          </span>
        </div>

        {/* Title */}
        <div
          style={{
            fontSize: 64,
            fontWeight: 'bold',
            background: 'linear-gradient(135deg, #10B981 0%, #059669 100%)',
            backgroundClip: 'text',
            WebkitBackgroundClip: 'text',
            color: 'transparent',
            marginBottom: 20,
          }}
        >
          CIP-113 Programmable Tokens
        </div>

        {/* Subtitle */}
        <div
          style={{
            fontSize: 32,
            color: '#94A3B8',
            textAlign: 'center',
            maxWidth: 900,
          }}
        >
          Create and manage regulated tokens on Cardano with embedded validation logic
        </div>

        {/* Footer */}
        <div
          style={{
            position: 'absolute',
            bottom: 40,
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            fontSize: 24,
            color: '#64748B',
          }}
        >
          <span>Cardano Foundation</span>
          <span style={{ color: '#10B981' }}>•</span>
          <span>Built with Next.js & Mesh SDK</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
