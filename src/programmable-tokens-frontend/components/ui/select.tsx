import { SelectHTMLAttributes, forwardRef } from "react";
import { cn } from "@/lib/utils";

export interface SelectOption {
  value: string;
  label: string;
}

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  error?: string;
  helperText?: string;
  options: SelectOption[];
}

const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, label, error, helperText, options, ...props }, ref) => {
    return (
      <div className="w-full">
        {label && (
          <label className="block text-sm font-medium text-dark-200 mb-2">
            {label}
          </label>
        )}
        <select
          className={cn(
            "flex w-full rounded-lg border bg-dark-800 px-4 py-3 text-white",
            "transition-colors duration-200 cursor-pointer",
            "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-dark-900",
            "disabled:cursor-not-allowed disabled:opacity-50",
            error
              ? "border-red-500 focus:ring-red-500"
              : "border-dark-700 focus:border-primary-500 focus:ring-primary-500",
            className
          )}
          ref={ref}
          {...props}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value} className="bg-dark-800">
              {option.label}
            </option>
          ))}
        </select>
        {error && (
          <p className="mt-2 text-sm text-red-500">{error}</p>
        )}
        {helperText && !error && (
          <p className="mt-2 text-sm text-dark-400">{helperText}</p>
        )}
      </div>
    );
  }
);

Select.displayName = "Select";

export { Select };
