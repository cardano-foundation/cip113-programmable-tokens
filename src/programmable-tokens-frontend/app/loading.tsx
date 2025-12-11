/**
 * Global Loading State
 *
 * Displays a loading spinner during page transitions and
 * route segment loading. Used by Next.js Suspense boundaries.
 *
 * ## Display
 * - Centered spinner animation
 * - "Loading..." text below spinner
 * - Uses PageContainer for consistent layout
 *
 * @module app/loading
 */

import { PageContainer } from '@/components/layout/page-container';

export default function Loading() {
  return (
    <PageContainer>
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          <p className="text-dark-400">Loading...</p>
        </div>
      </div>
    </PageContainer>
  );
}
