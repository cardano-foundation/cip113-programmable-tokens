"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { PageContainer } from "@/components/layout/page-container";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ArrowRight, Info } from "lucide-react";
import Link from "next/link";

export default function MintPage() {
  const router = useRouter();

  // Auto-redirect after 5 seconds
  useEffect(() => {
    const timer = setTimeout(() => {
      router.push("/admin");
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
                  Token minting has moved to the Admin Panel. You will be
                  redirected automatically.
                </p>
              </div>

              <div className="space-y-3">
                <p className="text-sm text-dark-500">
                  For initial token creation, use the{" "}
                  <Link href="/register" className="text-primary-400 hover:underline">
                    Register Token
                  </Link>{" "}
                  page.
                </p>
                <p className="text-sm text-dark-500">
                  For additional minting to existing tokens, use the Admin Panel.
                </p>
              </div>

              <div className="flex gap-3 justify-center pt-4">
                <Link href="/register">
                  <Button variant="ghost">Register Token</Button>
                </Link>
                <Link href="/admin">
                  <Button variant="primary">
                    Go to Admin Panel
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
