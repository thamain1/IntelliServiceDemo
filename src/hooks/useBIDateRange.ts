import { useState } from 'react';

export type DateRangeType = 'week' | 'month' | 'quarter' | 'year';

export function useBIDateRange(initialRange: DateRangeType = 'month') {
  const [dateRange, setDateRange] = useState<DateRangeType>(initialRange);

  const getDateRange = () => {
    const now = new Date();
    const ranges = {
      week: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000),
      month: new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000),
      quarter: new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000),
      year: new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000),
    };
    return {
      start: ranges[dateRange],
      end: now,
      type: dateRange,
    };
  };

  return {
    dateRange,
    setDateRange,
    ...getDateRange(),
  };
}
