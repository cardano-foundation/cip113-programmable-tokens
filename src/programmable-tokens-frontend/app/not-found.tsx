/**
 * 404 Not Found Page
 *
 * Custom 404 page displayed when a route is not found.
 * Provides helpful navigation back to the home page.
 *
 * ## Display
 * - Centered card with icon
 * - "Page Not Found" heading
 * - Descriptive message
 * - "Go Home" button for navigation
 *
 * @module app/not-found
 */

import Link from 'next/link';
import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { FileQuestion, Home, ArrowLeft } from 'lucide-react';

export default function NotFound() {
  return (
    <PageContainer>
      <div className="max-w-lg mx-auto mt-16">
        <Card>
          <CardHeader className="text-center">
            <div className="w-16 h-16 bg-primary-500/20 rounded-full flex items-center justify-center mx-auto mb-4">
              <FileQuestion className="h-8 w-8 text-primary-500" />
            </div>
            <CardTitle className="text-2xl">Page Not Found</CardTitle>
            <CardDescription>
              The page you&apos;re looking for doesn&apos;t exist or has been moved.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex gap-4">
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
