import { useEffect, useState } from "react";
import { Input } from "@/components/ui/input";
import { formatDuration } from "@/utils/time";

type Value = { quantity: number; hourly: boolean } | null;

const QuantityInput = ({
  value,
  onChange,
  ...props
}: {
  value: Value;
  onChange: (value: Value) => void;
} & Omit<React.ComponentProps<"input">, "value" | "onChange">) => {
  const [rawValue, setRawValue] = useState("");
  const [focused, setFocused] = useState(false);

  useEffect(() => {
    if (focused) return;
    setRawValue(value ? (value.hourly ? formatDuration(value.quantity) : value.quantity.toString()) : "");
  }, [value]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const input = e.target.value;
    setRawValue(input);

    if (!input.length) return onChange(null);

    const valueSplit = input.split(":");
    if (valueSplit.length === 1) return onChange({ quantity: parseFloat(valueSplit[0] ?? "0"), hourly: false });

    const hours = parseFloat(valueSplit[0] ?? "0");
    const minutes = parseFloat(valueSplit[1] ?? "0");
    onChange({
      quantity: Math.floor(isNaN(hours) ? 0 : hours * 60) + (isNaN(minutes) ? 0 : minutes),
      hourly: true,
    });
  };

  const handleFocus = () => setFocused(true);
  const handleBlur = () => setFocused(false);

  return <Input {...props} value={rawValue} onChange={handleChange} onFocus={handleFocus} onBlur={handleBlur} />;
};

export default QuantityInput;
