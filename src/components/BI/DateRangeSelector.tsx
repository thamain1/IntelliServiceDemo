import { Calendar } from 'lucide-react';
import { DateRangeType } from '../../hooks/useBIDateRange';

interface DateRangeSelectorProps {
  value: DateRangeType;
  onChange: (range: DateRangeType) => void;
}

export function DateRangeSelector({ value, onChange }: DateRangeSelectorProps) {
  const ranges: DateRangeType[] = ['week', 'month', 'quarter', 'year'];

  return (
    <div className="card p-6">
      <div className="flex items-center space-x-4">
        <Calendar className="w-5 h-5 text-gray-600 dark:text-gray-400" />
        <span className="text-sm text-gray-700 dark:text-gray-300">Date Range:</span>
        <div className="flex space-x-2">
          {ranges.map((range) => (
            <button
              key={range}
              onClick={() => onChange(range)}
              className={`btn ${
                value === range ? 'btn-primary' : 'btn-outline'
              } capitalize`}
            >
              {range}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
