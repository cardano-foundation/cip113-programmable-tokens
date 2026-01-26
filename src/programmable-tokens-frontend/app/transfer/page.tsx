"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { PageContainer } from "@/components/layout/page-container";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ArrowRight, Info, Send } from "lucide-react";
import Link from "next/link";

export default function TransferPage() {
  const router = useRouter();

  // Auto-redirect after 5 seconds
  useEffect(() => {
    const timer = setTimeout(() => {
      router.push("/");
    }, 5000);
    return () => clearTimeout(timer);
  }, [router]);

  return (
    <PageContainer>
      <div className="max-w-lg mx-auto">
        <Card>
          <CardContent className="py-12">
            <div className="text-center space-y-6">
              <div className="w-16 h-16 rounded-full bg-blue-500/10 flex items-center justify-center mx-auto">
                <Info className="h-8 w-8 text-blue-500" />
              </div>

              <div className="space-y-2">
                <h1 className="text-2xl font-bold text-white">Page Moved</h1>
                <p className="text-dark-400">
                  Token transfers are now done directly from the home page.
                  You will be redirected automatically.
                </p>
              </div>

              <div className="px-4 py-3 bg-dark-800 rounded-lg text-left">
                <p className="text-sm text-white font-medium mb-2">
                  How to transfer tokens:
                </p>
                <ol className="text-sm text-dark-400 space-y-1 list-decimal list-inside">
                  <li>Go to the home page</li>
                  <li>Connect your wallet</li>
                  <li>
                    Click the <Send className="h-3 w-3 inline mx-1" /> button
                    next to any token
                  </li>
                </ol>
              </div>

              <div className="flex justify-center pt-4">
                <Link href="/">
                  <Button variant="primary">
                    Go to Home
                    <ArrowRight className="h-4 w-4 ml-2" />
                  </Button>
                </Link>
              </div>

              <p className="text-xs text-dark-600">
                Redirecting in 5 seconds...
              </p>
            </div>
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
