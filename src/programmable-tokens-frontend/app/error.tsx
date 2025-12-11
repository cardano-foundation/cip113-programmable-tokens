/**
 * Global Error Boundary Page
 *
 * Next.js error boundary component that catches unhandled errors
 * in the application. Provides user-friendly error display with
 * recovery options.
 *
 * ## Features
 * - Logs errors to console (can be extended to error reporting service)
 * - Shows error details in development mode
 * - Provides "Try Again" button to reset error state
 * - Links to home page for navigation escape
 *
 * ## Usage
 * This file is automatically used by Next.js as the error boundary
 * for the application. It catches errors from:
 * - Server Components
 * - Client Components (during rendering)
 * - Route segment errors
 *
 * @module app/error
 */

'use client';

import { useEffect } from 'react';
import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { AlertTriangle, RefreshCw, Home } from 'lucide-react';
import Link from 'next/link';

/**
 * Error boundary page component.
 *
 * @param props - Error component props from Next.js
 * @param props.error - The error that was thrown
 * @param props.reset - Function to reset the error boundary
 * @returns React component
 */
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log the error to an error reporting service
    console.error('Application error:', error);
  }, [error]);

  return (
    <PageContainer>
      <div className="max-w-lg mx-auto mt-16">
        <Card>
          <CardHeader className="text-center">
            <div className="w-16 h-16 bg-red-500/20 rounded-full flex items-center justify-center mx-auto mb-4">
              <AlertTriangle className="h-8 w-8 text-red-500" />
            </div>
            <CardTitle className="text-2xl">Something went wrong</CardTitle>
            <CardDescription>
              An unexpected error occurred. Please try again or return to the home page.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {process.env.NODE_ENV === 'development' && error.message && (
              <div className="p-4 bg-dark-900 rounded-lg border border-dark-700">
                <p className="text-sm font-mono text-red-400 break-all">
                  {error.message}
                </p>
                {error.digest && (
                  <p className="text-xs text-dark-500 mt-2">
                    Error ID: {error.digest}
                  </p>
                )}
              </div>
            )}
            <div className="flex gap-4">
              <Button onClick={reset} variant="ghost" className="flex-1 gap-2">
                <RefreshCw className="h-4 w-4" />
                Try Again
              </Button>
              <Link href="/" className="flex-1">
                <Button className="w-full gap-2">
                  <Home className="h-4 w-4" />
                  Go Home
                </Button>
              </Link>
            </div>
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
