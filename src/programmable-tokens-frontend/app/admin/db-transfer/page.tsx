"use client";

import { useState } from "react";
import { PageContainer } from "@/components/layout";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Download, Upload, AlertCircle, CheckCircle, Database } from "lucide-react";

interface ExportData {
  blacklistInits: any[];
  tokenRegistrations: any[];
  exportedAt: number;
  counts: {
    blacklistInits: number;
    tokenRegistrations: number;
  };
}

interface ImportResult {
  success: boolean;
  blacklistInits?: {
    inserted: number;
    skipped: number;
  };
  tokenRegistrations?: {
    inserted: number;
    skipped: number;
  };
  error?: string;
}

export default function DbTransferPage() {
  const [exportData, setExportData] = useState<ExportData | null>(null);
  const [importJson, setImportJson] = useState("");
  const [importResult, setImportResult] = useState<ImportResult | null>(null);
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const apiBaseUrl = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8080";

  const handleExport = async () => {
    setIsExporting(true);
    setError(null);

    try {
      const response = await fetch(`${apiBaseUrl}/api/v1/admin/db-transfer/export`);

      if (!response.ok) {
        throw new Error(`Export failed: ${response.status} ${response.statusText}`);
      }

      const data: ExportData = await response.json();
      setExportData(data);

      // Automatically download as JSON file
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `freeze-and-seize-export-${new Date().toISOString()}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Export failed");
      console.error("Export error:", err);
    } finally {
      setIsExporting(false);
    }
  };

  const handleImport = async () => {
    setIsImporting(true);
    setError(null);
    setImportResult(null);

    try {
      const parsedData = JSON.parse(importJson);

      const response = await fetch(`${apiBaseUrl}/api/v1/admin/db-transfer/import`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(parsedData),
      });

      if (!response.ok) {
        throw new Error(`Import failed: ${response.status} ${response.statusText}`);
      }

      const result: ImportResult = await response.json();
      setImportResult(result);

      if (result.success) {
        setImportJson(""); // Clear input on success
      }
    } catch (err) {
      if (err instanceof SyntaxError) {
        setError("Invalid JSON format");
      } else {
        setError(err instanceof Error ? err.message : "Import failed");
      }
      console.error("Import error:", err);
    } finally {
      setIsImporting(false);
    }
  };

  const handleFileUpload = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (e) => {
      const content = e.target?.result as string;
      setImportJson(content);
    };
    reader.readAsText(file);
  };

  return (
    <PageContainer maxWidth="xl">
      <div className="space-y-8">
        {/* Header */}
        <div className="text-center space-y-2">
          <div className="flex items-center justify-center gap-3">
            <Database className="h-10 w-10 text-primary-400" />
            <h1 className="text-4xl font-bold text-white">Database Transfer Utility</h1>
          </div>
          <p className="text-dark-300">
            Export and import freeze-and-seize data between databases (dev/debug utility)
          </p>
        </div>

        {/* Warning Banner */}
        <div className="bg-yellow-900/20 border border-yellow-600/30 rounded-lg p-4 flex items-start gap-3">
          <AlertCircle className="h-5 w-5 text-yellow-500 flex-shrink-0 mt-0.5" />
          <div className="text-sm text-yellow-200">
            <p className="font-semibold mb-1">Warning: Utility Endpoint</p>
            <p>
              This is a hidden utility page for transferring data between development environments.
              Do not expose in production. No authentication is required.
            </p>
          </div>
        </div>

        <div className="grid md:grid-cols-2 gap-8">
          {/* Export Section */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Download className="h-5 w-5 text-primary-400" />
                Export Data
              </CardTitle>
              <CardDescription>
                Download all freeze-and-seize data from the current database
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <Button
                onClick={handleExport}
                isLoading={isExporting}
                variant="primary"
                className="w-full"
              >
                {isExporting ? "Exporting..." : "Export All Data"}
              </Button>

              {exportData && (
                <div className="mt-4 p-4 bg-dark-900 rounded-lg border border-dark-700">
                  <div className="flex items-center gap-2 mb-3">
                    <CheckCircle className="h-5 w-5 text-green-500" />
                    <h4 className="font-semibold text-white">Export Successful</h4>
                  </div>
                  <div className="space-y-2 text-sm text-dark-300">
                    <div className="flex justify-between">
                      <span>Blacklist Inits:</span>
                      <span className="font-mono text-white">{exportData.counts.blacklistInits}</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Token Registrations:</span>
                      <span className="font-mono text-white">{exportData.counts.tokenRegistrations}</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Exported At:</span>
                      <span className="font-mono text-white">
                        {new Date(exportData.exportedAt).toLocaleString()}
                      </span>
                    </div>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Import Section */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Upload className="h-5 w-5 text-accent-400" />
                Import Data
              </CardTitle>
              <CardDescription>
                Import freeze-and-seize data into the current database (skips duplicates)
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-dark-300 mb-2">
                  Upload JSON File
                </label>
                <input
                  type="file"
                  accept=".json"
                  onChange={handleFileUpload}
                  className="block w-full text-sm text-dark-300
                    file:mr-4 file:py-2 file:px-4
                    file:rounded file:border-0
                    file:text-sm file:font-semibold
                    file:bg-primary-600 file:text-white
                    hover:file:bg-primary-700
                    file:cursor-pointer cursor-pointer"
                />
              </div>

              <div className="relative">
                <label className="block text-sm font-medium text-dark-300 mb-2">
                  Or Paste JSON
                </label>
                <textarea
                  value={importJson}
                  onChange={(e) => setImportJson(e.target.value)}
                  placeholder='{"blacklistInits": [...], "tokenRegistrations": [...]}'
                  rows={8}
                  className="w-full px-3 py-2 bg-dark-900 border border-dark-700 rounded-lg
                    text-white text-sm font-mono
                    focus:outline-none focus:ring-2 focus:ring-primary-500
                    placeholder:text-dark-500"
                />
              </div>

              <Button
                onClick={handleImport}
                isLoading={isImporting}
                variant="secondary"
                className="w-full"
                disabled={!importJson.trim()}
              >
                {isImporting ? "Importing..." : "Import Data"}
              </Button>

              {importResult && importResult.success && (
                <div className="mt-4 p-4 bg-dark-900 rounded-lg border border-dark-700">
                  <div className="flex items-center gap-2 mb-3">
                    <CheckCircle className="h-5 w-5 text-green-500" />
                    <h4 className="font-semibold text-white">Import Successful</h4>
                  </div>
                  <div className="space-y-3 text-sm text-dark-300">
                    <div>
                      <p className="font-medium text-white mb-1">Blacklist Inits:</p>
                      <div className="ml-4 space-y-1">
                        <div className="flex justify-between">
                          <span>Inserted:</span>
                          <span className="font-mono text-green-400">
                            {importResult.blacklistInits?.inserted}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span>Skipped (duplicates):</span>
                          <span className="font-mono text-yellow-400">
                            {importResult.blacklistInits?.skipped}
                          </span>
                        </div>
                      </div>
                    </div>
                    <div>
                      <p className="font-medium text-white mb-1">Token Registrations:</p>
                      <div className="ml-4 space-y-1">
                        <div className="flex justify-between">
                          <span>Inserted:</span>
                          <span className="font-mono text-green-400">
                            {importResult.tokenRegistrations?.inserted}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span>Skipped (duplicates):</span>
                          <span className="font-mono text-yellow-400">
                            {importResult.tokenRegistrations?.skipped}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {importResult && !importResult.success && (
                <div className="mt-4 p-4 bg-red-900/20 border border-red-600/30 rounded-lg">
                  <div className="flex items-center gap-2">
                    <AlertCircle className="h-5 w-5 text-red-500" />
                    <h4 className="font-semibold text-red-200">Import Failed</h4>
                  </div>
                  <p className="mt-2 text-sm text-red-300">{importResult.error}</p>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Global Error Display */}
        {error && (
          <div className="p-4 bg-red-900/20 border border-red-600/30 rounded-lg flex items-start gap-3">
            <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-red-200">
              <p className="font-semibold mb-1">Error</p>
              <p>{error}</p>
            </div>
          </div>
        )}

        {/* Usage Instructions */}
        <Card>
          <CardHeader>
            <CardTitle>Usage Instructions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm text-dark-300">
            <div>
              <h4 className="font-semibold text-white mb-2">Export Workflow:</h4>
              <ol className="list-decimal ml-5 space-y-1">
                <li>Click &quot;Export All Data&quot; to download current database contents</li>
                <li>JSON file will be automatically downloaded</li>
                <li>Transfer the file to your target environment</li>
              </ol>
            </div>
            <div>
              <h4 className="font-semibold text-white mb-2">Import Workflow:</h4>
              <ol className="list-decimal ml-5 space-y-1">
                <li>Upload the exported JSON file or paste its contents</li>
                <li>Click &quot;Import Data&quot; to import into current database</li>
                <li>Duplicates will be automatically skipped based on primary keys</li>
                <li>Review the import summary to see what was inserted/skipped</li>
              </ol>
            </div>
            <div className="pt-4 border-t border-dark-700">
              <h4 className="font-semibold text-white mb-2">Duplicate Detection:</h4>
              <ul className="list-disc ml-5 space-y-1">
                <li>Blacklist Inits: Checked by <code className="text-primary-400">blacklistNodePolicyId</code></li>
                <li>Token Registrations: Checked by <code className="text-primary-400">programmableTokenPolicyId</code></li>
              </ul>
            </div>
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
