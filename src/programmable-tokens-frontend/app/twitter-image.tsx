/**
 * Twitter Card Image Generator
 *
 * Dynamically generates the Twitter card preview image for social sharing.
 * Uses Next.js ImageResponse for edge-rendered image generation.
 *
 * ## Specifications
 * - Size: 1200x600 pixels (Twitter 2:1 ratio)
 * - Format: PNG
 * - Runtime: Edge for fast generation
 *
 * ## Design
 * - Dark background (#0F172A)
 * - Split layout with text and logo
 * - "CIP-113 Programmable Tokens" title
 * - Description and Cardano branding
 *
 * @see https://nextjs.org/docs/app/api-reference/file-conventions/metadata/opengraph-image
 * @module app/twitter-image
 */

import { ImageResponse } from 'next/og';

// Route segment config
export const runtime = 'edge';

// Image metadata (Twitter uses 2:1 ratio)
export const alt = 'CIP-113 Programmable Tokens';
export const size = {
  width: 1200,
  height: 600,
};

export const contentType = 'image/png';

// Image generation (Twitter card)
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
          justifyContent: 'space-between',
          padding: '60px 80px',
          fontFamily: 'system-ui, sans-serif',
        }}
      >
        {/* Left side - Content */}
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            maxWidth: 700,
          }}
        >
          <div
            style={{
              fontSize: 56,
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

          <div
            style={{
              fontSize: 28,
              color: '#94A3B8',
              lineHeight: 1.4,
            }}
          >
            Create and manage regulated tokens on Cardano with embedded validation logic
          </div>

          <div
            style={{
              display: 'flex',
              gap: 16,
              marginTop: 32,
              fontSize: 20,
              color: '#64748B',
            }}
          >
            <span style={{ color: '#10B981' }}>✓</span>
            <span>Deploy Protocol</span>
            <span style={{ color: '#10B981' }}>✓</span>
            <span>Mint Tokens</span>
            <span style={{ color: '#10B981' }}>✓</span>
            <span>Transfer</span>
          </div>
        </div>

        {/* Right side - Logo */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: 200,
            height: 200,
            borderRadius: 40,
            background: 'linear-gradient(135deg, #10B981 0%, #059669 100%)',
            boxShadow: '0 25px 50px -12px rgba(16, 185, 129, 0.25)',
          }}
        >
          <span
            style={{
              fontSize: 96,
              fontWeight: 'bold',
              color: 'white',
            }}
          >
            PT
          </span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
