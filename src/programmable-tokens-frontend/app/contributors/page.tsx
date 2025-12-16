"use client";

import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Github, ExternalLink, User } from 'lucide-react';
import { PageContainer } from '@/components/layout/page-container';

interface Contributor {
  name: string;
  role: string;
  description: string;
  githubProfile?: string;
  repositories: {
    name: string;
    url: string;
    description: string;
  }[];
}

const contributors: Contributor[] = [
  {
    name: "Phil Di Sarro",
    role: "Anastasia Labs CEO",
    description: "Author of CIP-143, which provided the foundational registry code that CIP-113 builds upon. Creator of the WSC Proof of Concept implementation.",
    githubProfile: "https://github.com/colll78",
    repositories: [
      {
        name: "wsc-poc",
        url: "https://github.com/input-output-hk/wsc-poc",
        description: "CIP-143 Web-Socket Contracts Proof of Concept"
      }
    ]
  },
  {
    name: "Michele Nuzzi",
    role: "Harmonic Labs",
    description: "Core contributor to the CIP-113 standard and the plu-ts library ecosystem. Developer at Harmonic Labs working on advanced Cardano smart contract tooling.",
    githubProfile: "https://github.com/michele-nuzzi",
    repositories: [
      {
        name: "harmoniclabs",
        url: "https://github.com/harmoniclabs",
        description: "Harmonic Labs organization"
      },
      {
        name: "plu-ts",
        url: "https://github.com/HarmonicLabs/plu-ts",
        description: "TypeScript library for Cardano smart contracts"
      }
    ]
  },
  {
    name: "Matteo Coppola",
    role: "FluidTokens",
    description: "Core contributor to the CIP-113 standard. Implemented the BaFin (German Federal Financial Supervisory Authority) compliance standard for tokenization in the FluidTokens repository.",
    githubProfile: "https://github.com/matteocoppola",
    repositories: [
      {
        name: "fluidtokens",
        url: "https://github.com/fluidtokens",
        description: "FluidTokens organization"
      },
      {
        name: "fluidtokens-bafin",
        url: "https://github.com/fluidtokens/fluidtokens-bafin",
        description: "BaFin compliance implementation for programmable tokens"
      }
    ]
  },
  {
    name: "Giovanni Gargiulo",
    role: "Cardano Foundation",
    description: "CIP-113 contributor. Provided extensive documentation, api indexer, and build the full-stack application demonstrating programmable token registration, minting, transfers, and burning on Cardano.",
    githubProfile: "https://github.com/nemo83",
    repositories: [
      {
        name: "cip113-programmable-tokens",
        url: "https://github.com/cardano-foundation/cip113-programmable-tokens",
        description: "CIP-113 Reference Implementation"
      }
    ]
  }
];

export default function ContributorsPage() {
  return (
    <PageContainer>
      <div className="space-y-6">
        {/* Page Header */}
        <div>
          <h1 className="text-3xl font-bold text-white mb-2">Contributors</h1>
          <p className="text-dark-300">
            Core contributors to the CIP-113 Programmable Tokens standard and implementation
          </p>
        </div>

        {/* Contributors Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {contributors.map((contributor) => (
          <Card key={contributor.name} className="flex flex-col">
            <CardHeader>
              <div className="flex items-start gap-4">
                {/* Avatar placeholder */}
                <div className="w-16 h-16 rounded-full bg-dark-700 flex items-center justify-center flex-shrink-0">
                  <User className="h-8 w-8 text-dark-400" />
                </div>

                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <CardTitle className="text-xl">{contributor.name}</CardTitle>
                    {contributor.githubProfile && (
                      <a
                        href={contributor.githubProfile}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-dark-400 hover:text-primary-400 transition-colors"
                        title="GitHub Profile"
                      >
                        <Github className="h-5 w-5" />
                      </a>
                    )}
                  </div>
                  <CardDescription className="text-primary-400 font-medium">
                    {contributor.role}
                  </CardDescription>
                </div>
              </div>
            </CardHeader>

            <CardContent className="flex-1 flex flex-col">
              {/* Description */}
              <p className="text-sm text-dark-300 mb-4">
                {contributor.description}
              </p>

              {/* Repositories */}
              <div className="mt-auto">
                <h4 className="text-xs font-semibold text-dark-400 uppercase tracking-wider mb-2">
                  Repositories
                </h4>
                <div className="space-y-2">
                  {contributor.repositories.map((repo) => (
                    <a
                      key={repo.url}
                      href={repo.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="block p-3 bg-dark-800 hover:bg-dark-700 rounded-lg transition-colors group"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <Github className="h-4 w-4 text-dark-400 flex-shrink-0" />
                            <span className="text-sm font-medium text-white truncate">
                              {repo.name}
                            </span>
                          </div>
                          <p className="text-xs text-dark-400">
                            {repo.description}
                          </p>
                        </div>
                        <ExternalLink className="h-4 w-4 text-dark-500 group-hover:text-primary-400 transition-colors flex-shrink-0" />
                      </div>
                    </a>
                  ))}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
        </div>

        {/* Additional Info */}
        <Card>
          <CardContent className="py-6">
            <div className="text-center space-y-2">
              <h3 className="text-lg font-semibold text-white">About CIP-113</h3>
              <p className="text-sm text-dark-300 max-w-3xl mx-auto">
                CIP-113 defines a standard for programmable tokens on Cardano, enabling complex
                validation logic for token operations including minting, burning, and transfers.
                This work builds upon CIP-143 and incorporates contributions from multiple teams
                across the Cardano ecosystem to create an interoperable standard for smart tokens.
              </p>
              <div className="flex justify-center gap-4 pt-4">
                <a
                  href="https://cips.cardano.org/cps/CPS-0003"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-primary-400 hover:text-primary-300 transition-colors inline-flex items-center gap-1"
                >
                  Read CPS-0003 Problem Statement
                  <ExternalLink className="h-3 w-3" />
                </a>
                <a
                  href="https://github.com/cardano-foundation/CIPs/tree/master/CIP-0113"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-primary-400 hover:text-primary-300 transition-colors inline-flex items-center gap-1"
                >
                  Read CIP-113 Specification
                  <ExternalLink className="h-3 w-3" />
                </a>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
