"use client";

import dynamic from 'next/dynamic';
import { PageContainer } from '@/components/layout/page-container';

// Dynamically import the wizard to prevent SSR issues with wallet
const RegistrationWizard = dynamic(
  () => import('@/components/register/wizard').then(mod => ({ default: mod.RegistrationWizard })),
  {
    ssr: false,
    loading: () => (
      <div className="flex justify-center py-12">
        <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
      </div>
    ),
  }
);

export default function RegisterPage() {
  return (
    <PageContainer>
      <div className="max-w-4xl mx-auto">
        {/* Page Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-white mb-2">
            Register Programmable Token
          </h1>
          <p className="text-dark-300">
            Create a new CIP-113 token with programmable validation logic
          </p>
        </div>

        {/* Registration Wizard */}
        <RegistrationWizard />
      </div>
    </PageContainer>
  );
}
