import { Badge } from "./badge";
import { parseCIP68AssetName } from "@/lib/utils/cip68";

interface CIP68BadgeProps {
  assetNameHex: string;
}

export function CIP68Badge({ assetNameHex }: CIP68BadgeProps) {
  const info = parseCIP68AssetName(assetNameHex);
  if (!info.isCIP68) return null;

  if (info.label === 100) {
    return <Badge variant="warning" size="sm">CIP-68 Ref</Badge>;
  }

  return <Badge variant="info" size="sm">CIP-68</Badge>;
}
