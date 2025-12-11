/**
 * Footer Component
 *
 * Site-wide footer with links to resources and documentation.
 * Displays:
 * - Project description
 * - Links to CIP-113 specification and GitHub
 * - Documentation links
 * - Copyright information
 *
 * @module components/layout/footer
 */

import Link from "next/link";
import { Github, FileText, BookOpen } from "lucide-react";

/**
 * Application footer with resource links and branding.
 *
 * @returns React component
 */
export function Footer() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="border-t border-dark-700 bg-dark-900 mt-auto">
      <div className="container mx-auto px-4 py-8">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div>
            <h3 className="font-bold text-white mb-3">CIP-113 Programmable Tokens</h3>
            <p className="text-sm text-dark-300">
              A reference implementation for creating and managing programmable tokens on Cardano.
            </p>
          </div>

          <div>
            <h4 className="font-semibold text-white mb-3">Resources</h4>
            <ul className="space-y-2">
              <li>
                <a
                  href="https://github.com/cardano-foundation/CIPs/tree/master/CIP-0113"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-dark-300 hover:text-primary-400 transition-colors flex items-center gap-2"
                >
                  <FileText className="h-4 w-4" />
                  CIP-113 Specification
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/cardano-foundation/cip113-programmable-tokens"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-dark-300 hover:text-primary-400 transition-colors flex items-center gap-2"
                >
                  <Github className="h-4 w-4" />
                  GitHub Repository
                </a>
              </li>
              <li>
                <a
                  href="https://docs.cardano.org"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-dark-300 hover:text-primary-400 transition-colors flex items-center gap-2"
                >
                  <BookOpen className="h-4 w-4" />
                  Cardano Documentation
                </a>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="font-semibold text-white mb-3">About</h4>
            <p className="text-sm text-dark-300 mb-2">
              Built on top of the CIP-113 standard and the original CIP-143 implementation.
            </p>
            <p className="text-sm text-dark-400">
              © {currentYear} Cardano Foundation
            </p>
          </div>
        </div>

        <div className="mt-8 pt-8 border-t border-dark-800">
          <p className="text-center text-sm text-dark-400">
            Licensed under Apache License 2.0
          </p>
        </div>
      </div>
    </footer>
  );
}
