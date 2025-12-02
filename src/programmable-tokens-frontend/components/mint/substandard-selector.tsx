/**
 * Substandard Selector Component
 *
 * A cascading dropdown component for selecting a CIP-0113 substandard
 * and its associated validator. The first dropdown selects the substandard
 * type, and the second dropdown (populated based on first selection)
 * selects the specific validator to use.
 *
 * ## Cascading Selection
 * 1. User selects substandard (e.g., "blacklist")
 * 2. Validator dropdown populates with validators from that substandard
 * 3. User selects validator (e.g., "example_transfer_logic.spend")
 * 4. Parent receives both selections via onSelect callback
 *
 * @module components/mint/substandard-selector
 */

"use client";

import { useState, useEffect, useMemo } from 'react';
import { Select, SelectOption } from '@/components/ui/select';
import { Substandard } from '@/types/api';

/**
 * Props for the SubstandardSelector component.
 */
interface SubstandardSelectorProps {
  /** Available substandard configurations from backend */
  substandards: Substandard[];
  /** Callback when both substandard and validator are selected */
  onSelect: (substandardId: string, validatorTitle: string) => void;
  /** Whether the selector should be disabled */
  disabled?: boolean;
}

/**
 * Cascading dropdown for substandard and validator selection.
 *
 * Provides a two-step selection process where the validator options
 * are dynamically populated based on the selected substandard.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <SubstandardSelector
 *   substandards={substandards}
 *   onSelect={(subId, validatorTitle) => {
 *     console.log(`Selected ${validatorTitle} from ${subId}`);
 *   }}
 * />
 * ```
 */
export function SubstandardSelector({
  substandards,
  onSelect,
  disabled = false,
}: SubstandardSelectorProps) {
  const [selectedSubstandard, setSelectedSubstandard] = useState<string>('');
  const [selectedValidator, setSelectedValidator] = useState<string>('');

  // Get validator options for selected substandard (memoized to prevent unnecessary recalculations)
  const validatorOptions: SelectOption[] = useMemo(() => {
    if (!selectedSubstandard) return [];

    const substandard = substandards.find(s => s.id === selectedSubstandard);
    return substandard?.validators.map(v => ({
      value: v.title,
      label: v.title,
    })) || [];
  }, [selectedSubstandard, substandards]);

  const handleSubstandardChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const substandardId = e.target.value;
    setSelectedSubstandard(substandardId);
    setSelectedValidator(''); // Reset validator selection when substandard changes
  };

  const handleValidatorChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const validatorTitle = e.target.value;
    setSelectedValidator(validatorTitle);
    // Only call onSelect when user has selected both substandard and validator
    if (selectedSubstandard && validatorTitle) {
      onSelect(selectedSubstandard, validatorTitle);
    }
  };

  const substandardOptions: SelectOption[] = [
    { value: '', label: '-- Select a substandard --' },
    ...substandards.map(s => ({
      value: s.id,
      label: s.id.charAt(0).toUpperCase() + s.id.slice(1),
    }))
  ];

  const validatorOptionsWithPlaceholder: SelectOption[] = [
    { value: '', label: '-- Select a validator --' },
    ...validatorOptions
  ];

  return (
    <div className="space-y-4">
      <Select
        label="Step 1: Validation Logic (Substandard)"
        options={substandardOptions}
        value={selectedSubstandard}
        onChange={handleSubstandardChange}
        disabled={disabled || substandards.length === 0}
        helperText="Choose the validation rules for your token (e.g., dummy, regulated, etc.)"
      />

      {selectedSubstandard && validatorOptions.length > 0 && (
        <Select
          label="Step 2: Validator Script"
          options={validatorOptionsWithPlaceholder}
          value={selectedValidator}
          onChange={handleValidatorChange}
          disabled={disabled}
          helperText="Select which validator contract to use for minting"
        />
      )}
    </div>
  );
}
