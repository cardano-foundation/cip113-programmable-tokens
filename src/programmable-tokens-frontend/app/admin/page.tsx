"use client";

import dynamicImport from "next/dynamic";
import { PageContainer } from "@/components/layout";
import { Card, CardContent } from "@/components/ui/card";

// Dynamically import the entire admin page content to avoid WASM issues during SSG
const AdminPageContent = dynamicImport(
  () => import("@/components/admin/admin-page-content"),
  {
    ssr: false,
    loading: () => (
      <PageContainer maxWidth="lg">
        <div className="space-y-8">
          <div className="text-center space-y-2">
            <h1 className="text-4xl font-bold text-white">Admin Panel</h1>
            <p className="text-dark-300">
              Manage your programmable token administration tasks
            </p>
          </div>
          <Card>
            <CardContent className="flex items-center justify-center py-16">
              <div className="h-8 w-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
            </CardContent>
          </Card>
        </div>
      </PageContainer>
    ),
  }
);

export default function AdminPage() {
  return <AdminPageContent />;
}
