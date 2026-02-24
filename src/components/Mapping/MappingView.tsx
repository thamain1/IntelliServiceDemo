import { useEffect, useState } from 'react';
import { MapPin, Filter } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { CallMapGoogle } from './CallMapGoogle';
import type { Database } from '../../lib/database.types';

type Ticket = Database['public']['Tables']['tickets']['Row'] & {
  customers?: {
    name: string;
    address: string;
    city: string;
    state: string;
    latitude: number | null;
    longitude: number | null;
    place_id: string | null;
  };
  profiles?: { full_name: string };
};

export function MappingView() {
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('all');

  useEffect(() => {
    loadTickets();
  }, []);

  const loadTickets = async () => {
    try {
      console.log('[MappingView] Loading tickets for map...');

      const { data, error } = await supabase
        .from('tickets')
        .select('*, customers!tickets_customer_id_fkey(name, address, city, state, latitude, longitude, place_id), profiles!tickets_assigned_to_fkey(full_name)')
        .not('status', 'in', '(cancelled,closed_billed,completed)')
        .order('priority', { ascending: false });

      if (error) {
        console.error('[MappingView] Error loading tickets:', error);
        throw error;
      }

      console.log('[MappingView] Loaded tickets:', data?.length || 0);

      // Diagnostic logging
      const ticketsWithCoords = data?.filter(t => {
        const hasTicketCoords = t.latitude != null && t.longitude != null;
        const hasCustomerCoords = t.customers &&
          t.customers.latitude != null &&
          t.customers.longitude != null;
        return hasTicketCoords || hasCustomerCoords;
      }) || [];

      const ticketsMissingCoords = data?.filter(t => {
        const hasTicketCoords = t.latitude != null && t.longitude != null;
        const hasCustomerCoords = t.customers &&
          t.customers.latitude != null &&
          t.customers.longitude != null;
        return !hasTicketCoords && !hasCustomerCoords;
      }) || [];

      console.log('[MappingView] Tickets WITH coordinates:', ticketsWithCoords.length);
      console.log('[MappingView] Tickets MISSING coordinates:', ticketsMissingCoords.length);

      if (ticketsWithCoords.length > 0) {
        console.log('[MappingView] Sample ticket with coords:', {
          ticket_number: ticketsWithCoords[0].ticket_number,
          status: ticketsWithCoords[0].status,
          priority: ticketsWithCoords[0].priority,
          ticket_lat: ticketsWithCoords[0].latitude,
          ticket_lng: ticketsWithCoords[0].longitude,
          customer_lat: ticketsWithCoords[0].customers?.latitude,
          customer_lng: ticketsWithCoords[0].customers?.longitude,
          customer_name: ticketsWithCoords[0].customers?.name
        });
      }

      if (ticketsMissingCoords.length > 0) {
        console.log('[MappingView] Sample ticket missing coords:', {
          ticket_number: ticketsMissingCoords[0].ticket_number,
          customer_name: ticketsMissingCoords[0].customers?.name,
          customer_address: ticketsMissingCoords[0].customers?.address
        });
      }

      setTickets((data as Ticket[]) || []);
    } catch (error) {
      console.error('[MappingView] Error loading tickets:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredTickets = tickets.filter((ticket) => {
    return statusFilter === 'all' || ticket.status === statusFilter;
  });

  const statusCounts = {
    open: tickets.filter((t) => t.status === 'open').length,
    scheduled: tickets.filter((t) => t.status === 'scheduled').length,
    in_progress: tickets.filter((t) => t.status === 'in_progress').length,
    completed: tickets.filter((t) => t.status === 'completed').length,
  };

  const getStatusColor = (status: string | null) => {
    const colors: Record<string, string> = {
      open: 'bg-red-500',
      scheduled: 'bg-blue-500',
      in_progress: 'bg-yellow-500',
      completed: 'bg-green-500',
    };
    return colors[status || ''] || 'bg-gray-500';
  };

  const getPriorityIcon = (priority: string | null) => {
    const sizes: Record<string, string> = {
      urgent: 'w-6 h-6',
      high: 'w-5 h-5',
      normal: 'w-4 h-4',
      low: 'w-3 h-3',
    };
    return sizes[priority || ''] || 'w-4 h-4';
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">
          Interactive Call Map
        </h1>
        <p className="text-gray-600 dark:text-gray-400 mt-1">
          Visual overview of all service calls by location
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div className="card p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400">Open Calls</p>
              <p className="text-3xl font-bold text-red-600 mt-2">{statusCounts.open}</p>
            </div>
            <div className="w-3 h-3 rounded-full bg-red-500"></div>
          </div>
        </div>

        <div className="card p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400">Scheduled</p>
              <p className="text-3xl font-bold text-blue-600 mt-2">{statusCounts.scheduled}</p>
            </div>
            <div className="w-3 h-3 rounded-full bg-blue-500"></div>
          </div>
        </div>

        <div className="card p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400">In Progress</p>
              <p className="text-3xl font-bold text-yellow-600 mt-2">
                {statusCounts.in_progress}
              </p>
            </div>
            <div className="w-3 h-3 rounded-full bg-yellow-500"></div>
          </div>
        </div>

        <div className="card p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400">Completed</p>
              <p className="text-3xl font-bold text-green-600 mt-2">{statusCounts.completed}</p>
            </div>
            <div className="w-3 h-3 rounded-full bg-green-500"></div>
          </div>
        </div>
      </div>

      <div className="card p-6">
        <div className="flex items-center space-x-4 mb-4">
          <Filter className="w-5 h-5 text-gray-600 dark:text-gray-400" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="input md:w-64"
          >
            <option value="all">All Statuses</option>
            <option value="open">Open</option>
            <option value="scheduled">Scheduled</option>
            <option value="in_progress">In Progress</option>
            <option value="completed">Completed</option>
          </select>
        </div>

        <CallMapGoogle statusFilter={statusFilter} tickets={tickets} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card p-6">
          <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-4">
            Active Service Calls
          </h2>
          <div className="space-y-3 max-h-96 overflow-y-auto">
            {filteredTickets.length === 0 ? (
              <p className="text-center text-gray-600 dark:text-gray-400 py-8">
                No calls found
              </p>
            ) : (
              filteredTickets.map((ticket) => (
                <div
                  key={ticket.id}
                  className="flex items-start space-x-3 p-3 bg-gray-50 dark:bg-gray-700/50 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                >
                  <div className="flex-shrink-0 mt-1">
                    <div className={`${getStatusColor(ticket.status)} rounded-full p-2`}>
                      <MapPin className={`text-white ${getPriorityIcon(ticket.priority)}`} />
                    </div>
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center space-x-2">
                      <span className="font-medium text-gray-900 dark:text-white">
                        {ticket.ticket_number}
                      </span>
                      <span className="badge badge-gray capitalize">{(ticket.status ?? 'unknown').replace('_', ' ')}</span>
                    </div>
                    <p className="text-sm text-gray-700 dark:text-gray-300 mt-1">
                      {ticket.title}
                    </p>
                    <div className="mt-2 space-y-1">
                      <p className="text-xs text-gray-600 dark:text-gray-400">
                        <span className="font-medium">Customer:</span> {ticket.customers?.name || 'N/A'}
                      </p>
                      {ticket.customers?.address && (
                        <p className="text-xs text-gray-600 dark:text-gray-400">
                          <span className="font-medium">Address:</span> {ticket.customers.address},{' '}
                          {ticket.customers.city}, {ticket.customers.state}
                        </p>
                      )}
                      {ticket.profiles && (
                        <p className="text-xs text-gray-600 dark:text-gray-400">
                          <span className="font-medium">Tech:</span> {ticket.profiles.full_name}
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="card p-6">
          <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-4">
            Map Legend
          </h2>
          <div className="space-y-4">
            <div>
              <h3 className="font-medium text-gray-900 dark:text-white mb-2">Status Colors</h3>
              <div className="space-y-2">
                <div className="flex items-center space-x-2">
                  <div className="w-4 h-4 rounded-full bg-red-500"></div>
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    Open - Requires immediate attention
                  </span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="w-4 h-4 rounded-full bg-blue-500"></div>
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    Scheduled - Appointment set
                  </span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="w-4 h-4 rounded-full bg-yellow-500"></div>
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    In Progress - Tech on site
                  </span>
                </div>
              </div>
            </div>

            <div>
              <h3 className="font-medium text-gray-900 dark:text-white mb-2">Pin Sizes</h3>
              <div className="space-y-2">
                <div className="flex items-center space-x-2">
                  <MapPin className="w-6 h-6 text-gray-600" />
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    Urgent Priority
                  </span>
                </div>
                <div className="flex items-center space-x-2">
                  <MapPin className="w-5 h-5 text-gray-600" />
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    High Priority
                  </span>
                </div>
                <div className="flex items-center space-x-2">
                  <MapPin className="w-4 h-4 text-gray-600" />
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    Normal Priority
                  </span>
                </div>
                <div className="flex items-center space-x-2">
                  <MapPin className="w-3 h-3 text-gray-600" />
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    Low Priority
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div className="mt-6 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
            <p className="text-sm text-blue-700 dark:text-blue-300">
              Click on any pin on the map to view detailed information about the service call
              and get directions.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
