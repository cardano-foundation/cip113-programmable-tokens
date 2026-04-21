import { parseCIP68AssetName, decodeAssetNameDisplay } from "@/lib/utils/cip68";
import { CIP68Badge } from "./cip68-badge";

interface TokenNameProps {
  /** Hex-encoded asset name (may include CIP-67 prefix) */
  assetNameHex: string;
  /** Pre-decoded name (fallback when not CIP-68) */
  assetName?: string;
  /** Whether to show CIP-68 badge (default: true) */
  showBadge?: boolean;
  /** Additional classes for the name text */
  className?: string;
}

export function TokenName({
  assetNameHex,
  assetName,
  showBadge = true,
  className,
}: TokenNameProps) {
  const info = parseCIP68AssetName(assetNameHex);
  const displayName = info.isCIP68
    ? info.displayName
    : assetName || decodeAssetNameDisplay(assetNameHex);

  return (
    <span className="inline-flex items-center gap-1.5">
      <span className={className}>{displayName}</span>
      {showBadge && info.isCIP68 && <CIP68Badge assetNameHex={assetNameHex} />}
    </span>
  );
}
