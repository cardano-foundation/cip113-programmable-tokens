import Link from "next/link";
import { Github, FileText, BookOpen } from "lucide-react";

const AIKEN_ICON_BASE64 =
  "data:image/png;base64,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";

function AikenLogo({ className }: { className?: string }) {
  return <img src={AIKEN_ICON_BASE64} alt="Aiken" className={className} />;
}

function MeshLogo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 300 200" xmlns="http://www.w3.org/2000/svg" fill="white" className={className}>
      <path d="m289 127-45-60-45-60c-.9-1.3-2.4-2-4-2s-3.1.7-4 2l-37 49.3c-2 2.7-6 2.7-8 0l-37-49.3c-.9-1.3-2.4-2-4-2s-3.1.7-4 2l-45 60-45 60c-1.3 1.8-1.3 4.2 0 6l45 60c.9 1.3 2.4 2 4 2s3.1-.7 4-2l37-49.3c2-2.7 6-2.7 8 0l37 49.3c.9 1.3 2.4 2 4 2s3.1-.7 4-2l37-49.3c2-2.7 6-2.7 8 0l37 49.3c.9 1.3 2.4 2 4 2s3.1-.7 4-2l45-60c1.3-1.8 1.3-4.2 0-6zm-90-103.3 32.5 43.3c1.3 1.8 1.3 4.2 0 6l-32.5 43.3c-2 2.7-6 2.7-8 0l-32.5-43.3c-1.3-1.8-1.3-4.2 0-6l32.5-43.3c2-2.7 6-2.7 8 0zm-90 0 32.5 43.3c1.3 1.8 1.3 4.2 0 6l-32.5 43.3c-2 2.7-6 2.7-8 0l-32.5-43.3c-1.3-1.8-1.3-4.2 0-6l32.5-43.3c2-2.7 6-2.7 8 0zm-53 152.6-32.5-43.3c-1.3-1.8-1.3-4.2 0-6l32.5-43.3c2-2.7 6-2.7 8 0l32.5 43.3c1.3 1.8 1.3 4.2 0 6l-32.5 43.3c-2 2.7-6 2.7-8 0zm90 0-32.5-43.3c-1.3-1.8-1.3-4.2 0-6l32.5-43.3c2-2.7 6-2.7 8 0l32.5 43.3c1.3 1.8 1.3 4.2 0 6l-32.5 43.3c-2 2.7-6 2.7-8 0zm90 0-32.5-43.3c-1.3-1.8-1.3-4.2 0-6l32.5-43.3c2-2.7 6-2.7 8 0l32.5 43.3c1.3 1.8 1.3 4.2 0 6l-32.5 43.3c-2 2.7-6 2.7-8 0z" />
    </svg>
  );
}

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
                  href="https://cips.cardano.org/cps/CPS-0003"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-dark-300 hover:text-primary-400 transition-colors flex items-center gap-2"
                >
                  <FileText className="h-4 w-4" />
                  CPS-0003 Problem Statement
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/cardano-foundation/CIPs/blob/559aefe688593e77721d9e6e891e1d827eaecb02/CIP-0113/README.md"
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
                  href="https://cips.cardano.org/cip/CIP-0143"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-dark-300 hover:text-primary-400 transition-colors flex items-center gap-2"
                >
                  <FileText className="h-4 w-4" />
                  CIP-143 Specification
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
                  href="https://github.com/input-output-hk/wsc-poc"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-dark-300 hover:text-primary-400 transition-colors flex items-center gap-2"
                >
                  <Github className="h-4 w-4" />
                  CIP-143 WSC PoC
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

        <div className="mt-8 pt-8 border-t border-dark-800 flex flex-col items-center gap-4">
          <div className="flex items-center gap-3 text-sm text-dark-400">
            <span>Powered by</span>
            <a
              href="https://aiken-lang.org"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 hover:opacity-80 transition-opacity"
            >
              <AikenLogo className="h-5 w-5" />
              <span className="text-white font-medium">Aiken</span>
            </a>
            <span>&</span>
            <a
              href="https://meshjs.dev"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 hover:opacity-80 transition-opacity"
            >
              <MeshLogo className="h-5 w-7" />
              <span className="text-white font-medium">MeshJS</span>
            </a>
          </div>
          <p className="text-center text-sm text-dark-400">
            Licensed under Apache License 2.0
          </p>
        </div>
      </div>
    </footer>
  );
}
