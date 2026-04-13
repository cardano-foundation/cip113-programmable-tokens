/**
 * CIP-67/CIP-68 asset name utilities.
 *
 * CIP-67 defines 4-byte label prefixes on asset names to indicate token purpose.
 * CIP-68 uses these labels to distinguish user tokens (333) from reference tokens (100).
 */

// CIP-67 label prefixes (4 bytes = 8 hex chars)
const CIP67_LABEL_333 = "0014df10"; // FT user token (holds value)
const CIP67_LABEL_100 = "000643b0"; // Reference token (holds metadata)
const CIP67_LABEL_222 = "000de140"; // NFT token
const CIP67_PREFIX_LENGTH = 8;

const LABEL_MAP: Record<string, { label: number; name: string }> = {
  [CIP67_LABEL_333]: { label: 333, name: "FT" },
  [CIP67_LABEL_100]: { label: 100, name: "Reference" },
  [CIP67_LABEL_222]: { label: 222, name: "NFT" },
};

export interface CIP68Info {
  /** Whether this asset name has a CIP-67 label prefix */
  isCIP68: boolean;
  /** Numeric label (333, 100, 222) or null */
  label: number | null;
  /** Human-readable label name ("FT", "Reference", "NFT") or null */
  labelName: string | null;
  /** Asset name hex WITHOUT the label prefix */
  rawAssetNameHex: string;
  /** Human-readable decoded name (prefix stripped, UTF-8 decoded) */
  displayName: string;
}

/** Decode hex to UTF-8 string, returning hex on failure */
function hexDecode(hex: string): string {
  if (!hex) return "";
  try {
    const bytes = new Uint8Array(
      hex.match(/.{1,2}/g)?.map((b) => parseInt(b, 16)) || []
    );
    const decoder = new TextDecoder("utf-8", { fatal: true });
    return decoder.decode(bytes);
  } catch {
    return hex;
  }
}

/** Parse an asset name hex string and detect CIP-67 labels. */
export function parseCIP68AssetName(assetNameHex: string): CIP68Info {
  if (!assetNameHex || assetNameHex.length <= CIP67_PREFIX_LENGTH) {
    return {
      isCIP68: false,
      label: null,
      labelName: null,
      rawAssetNameHex: assetNameHex || "",
      displayName: hexDecode(assetNameHex || ""),
    };
  }

  const prefix = assetNameHex.substring(0, CIP67_PREFIX_LENGTH).toLowerCase();
  const entry = LABEL_MAP[prefix];

  if (entry) {
    const raw = assetNameHex.substring(CIP67_PREFIX_LENGTH);
    return {
      isCIP68: true,
      label: entry.label,
      labelName: entry.name,
      rawAssetNameHex: raw,
      displayName: hexDecode(raw),
    };
  }

  return {
    isCIP68: false,
    label: null,
    labelName: null,
    rawAssetNameHex: assetNameHex,
    displayName: hexDecode(assetNameHex),
  };
}

/** Strip CIP-67 label prefix from hex asset name. Returns raw hex without prefix. */
export function stripCIP67Label(assetNameHex: string): string {
  if (!assetNameHex || assetNameHex.length <= CIP67_PREFIX_LENGTH) return assetNameHex || "";
  const prefix = assetNameHex.substring(0, CIP67_PREFIX_LENGTH).toLowerCase();
  return prefix in LABEL_MAP ? assetNameHex.substring(CIP67_PREFIX_LENGTH) : assetNameHex;
}

/** Decode asset name hex to display string, stripping CIP-67 prefix if present. */
export function decodeAssetNameDisplay(assetNameHex: string): string {
  return parseCIP68AssetName(assetNameHex).displayName;
}

/** Check if asset name hex has CIP-67 label 100 (reference token). */
export function isReferenceToken(assetNameHex: string): boolean {
  if (!assetNameHex || assetNameHex.length <= CIP67_PREFIX_LENGTH) return false;
  return assetNameHex.substring(0, CIP67_PREFIX_LENGTH).toLowerCase() === CIP67_LABEL_100;
}

/** Check if asset name hex has CIP-67 label 333 (FT user token). */
export function isCIP68FT(assetNameHex: string): boolean {
  if (!assetNameHex || assetNameHex.length <= CIP67_PREFIX_LENGTH) return false;
  return assetNameHex.substring(0, CIP67_PREFIX_LENGTH).toLowerCase() === CIP67_LABEL_333;
}
