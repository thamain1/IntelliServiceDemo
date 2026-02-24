/**
 * Live Data Service for Neural Command
 * LOCAL DEMO ONLY - DO NOT COMMIT
 *
 * Provides real-time data queries from Supabase for the
 * AI agent system to process live operational data.
 */

import { supabase } from '../../lib/supabase';

// Live data types for agent consumption
export interface LiveTicket {
  id: string;
  ticketNumber: string;
  title: string;
  description: string | null;
  priority: 'emergency' | 'high' | 'medium' | 'low' | null;
  status: string;
  scheduledDate: string | null;
  estimatedMinutes: number | null;
  customerName: string;
  customerId: string;
  address: string | null;
  city: string | null;
  state: string | null;
  latitude: number | null;
  longitude: number | null;
  assignedTo: string | null;
  technicianName: string | null;
  equipmentType: string | null;
  equipmentModel: string | null;
  createdAt: string;
}

export interface TechInventoryItem {
  technicianId: string;
  technicianName: string;
  partId: string;
  partNumber: string;
  partName: string;
  qtyOnHand: number;
  unitPrice: number | null;
  vehicleName: string | null;
}

export interface TechnicianAvailability {
  id: string;
  name: string;
  initials: string;
  role: string;
  isActive: boolean;
  defaultVehicleId: string | null;
}

export interface ReorderAlert {
  partId: string;
  partNumber: string;
  partName: string;
  locationName: string;
  locationType: string;
  qtyOnHand: number;
  reorderPoint: number;
  reorderQty: number;
  preferredVendor: string | null;
}

export interface EquipmentRecord {
  id: string;
  equipmentType: string;
  manufacturer: string | null;
  modelNumber: string | null;
  serialNumber: string | null;
  installedAt: string | null;
  warrantyExpiresAt: string | null;
  lastServiceDate: string | null;
}

export interface ServiceHistoryEntry {
  ticketId: string;
  ticketNumber: string;
  ticketTitle: string;
  serviceDate: string;
  technicianName: string | null;
  status: string;
}

export interface EquipmentIntelligence {
  equipment: EquipmentRecord;
  serviceHistory: ServiceHistoryEntry[];
  totalServiceCalls: number;
  serviceCallsLast12Months: number;
  isChronic: boolean;
  chronicReason: string | null;
  ageYears: number;
  warrantyStatus: 'active' | 'expired' | 'unknown';
  recommendedAction: 'repair' | 'replace' | 'monitor';
  confidenceScore: number;
}

// CRM/Sales Pipeline types for Phase 3
export interface SalesPipelineItem {
  estimateId: string;
  estimateNumber: string;
  customerId: string;
  customerName: string;
  customerPhone: string | null;
  title: string;
  totalAmount: number;
  status: string;
  stageName: string;
  probability: number;
  daysInStage: number;
  expectedCloseDate: string | null;
}

export interface CustomerSalesIntelligence {
  customerId: string;
  customerName: string;
  openEstimates: SalesPipelineItem[];
  totalPipelineValue: number;
  highestProbability: number;
  hasUpsellOpportunity: boolean;
  upsellReason: string | null;
}

export class LiveDataService {
  /**
   * Get open tickets for dispatch analysis
   */
  static async getOpenTickets(limit = 20): Promise<LiveTicket[]> {
    const { data, error } = await supabase
      .from('tickets')
      .select(`
        id,
        ticket_number,
        title,
        description,
        priority,
        status,
        scheduled_date,
        estimated_minutes,
        latitude,
        longitude,
        assigned_to,
        created_at,
        customers (
          id,
          name,
          address,
          city,
          state
        ),
        profiles:assigned_to (
          full_name
        ),
        equipment:equipment_id (
          equipment_type,
          model_number
        )
      `)
      .in('status', ['new', 'open', 'assigned', 'in_progress', 'on_hold'])
      .order('priority', { ascending: true })
      .order('scheduled_date', { ascending: true, nullsFirst: false })
      .limit(limit);

    if (error) {
      console.error('[LiveDataService] Error fetching tickets:', error);
      return [];
    }

    return (data || []).map((ticket: any) => ({
      id: ticket.id,
      ticketNumber: ticket.ticket_number || 'N/A',
      title: ticket.title || 'Untitled',
      description: ticket.description,
      priority: ticket.priority,
      status: ticket.status,
      scheduledDate: ticket.scheduled_date,
      estimatedMinutes: ticket.estimated_minutes,
      customerName: ticket.customers?.name || 'Unknown Customer',
      customerId: ticket.customers?.id || '',
      address: ticket.customers?.address,
      city: ticket.customers?.city,
      state: ticket.customers?.state,
      latitude: ticket.latitude,
      longitude: ticket.longitude,
      assignedTo: ticket.assigned_to,
      technicianName: ticket.profiles?.full_name || null,
      equipmentType: ticket.equipment?.equipment_type || null,
      equipmentModel: ticket.equipment?.model_number || null,
      createdAt: ticket.created_at,
    }));
  }

  /**
   * Get a specific ticket by ID
   */
  static async getTicketById(ticketId: string): Promise<LiveTicket | null> {
    const { data, error } = await supabase
      .from('tickets')
      .select(`
        id,
        ticket_number,
        title,
        description,
        priority,
        status,
        scheduled_date,
        estimated_minutes,
        latitude,
        longitude,
        assigned_to,
        created_at,
        customers (
          id,
          name,
          address,
          city,
          state
        ),
        profiles:assigned_to (
          full_name
        ),
        equipment:equipment_id (
          equipment_type,
          model_number
        )
      `)
      .eq('id', ticketId)
      .single();

    if (error || !data) {
      console.error('[LiveDataService] Error fetching ticket:', error);
      return null;
    }

    const ticket: any = data;
    return {
      id: ticket.id,
      ticketNumber: ticket.ticket_number || 'N/A',
      title: ticket.title || 'Untitled',
      description: ticket.description,
      priority: ticket.priority,
      status: ticket.status,
      scheduledDate: ticket.scheduled_date,
      estimatedMinutes: ticket.estimated_minutes,
      customerName: ticket.customers?.name || 'Unknown Customer',
      customerId: ticket.customers?.id || '',
      address: ticket.customers?.address,
      city: ticket.customers?.city,
      state: ticket.customers?.state,
      latitude: ticket.latitude,
      longitude: ticket.longitude,
      assignedTo: ticket.assigned_to,
      technicianName: ticket.profiles?.full_name || null,
      equipmentType: ticket.equipment?.equipment_type || null,
      equipmentModel: ticket.equipment?.model_number || null,
      createdAt: ticket.created_at,
    };
  }

  /**
   * Get technician's truck inventory
   */
  static async getTechnicianInventory(techId: string): Promise<TechInventoryItem[]> {
    const { data, error } = await supabase
      .from('vw_technician_truck_inventory')
      .select('*')
      .eq('technician_id', techId);

    if (error) {
      console.error('[LiveDataService] Error fetching tech inventory:', error);
      return [];
    }

    return (data || []).map((item: any) => ({
      technicianId: item.technician_id,
      technicianName: item.technician_name || 'Unknown',
      partId: item.part_id,
      partNumber: item.part_number || '',
      partName: item.part_name || 'Unknown Part',
      qtyOnHand: item.qty_on_hand || 0,
      unitPrice: item.unit_price,
      vehicleName: item.vehicle_name,
    }));
  }

  /**
   * Check if a technician has a specific part
   */
  static async checkPartAvailability(techId: string, partNumber: string): Promise<number> {
    const { data, error } = await supabase
      .from('vw_technician_truck_inventory')
      .select('qty_on_hand')
      .eq('technician_id', techId)
      .eq('part_number', partNumber)
      .single();

    if (error || !data) {
      return 0;
    }

    return data.qty_on_hand || 0;
  }

  /**
   * Get available technicians (active with technician role)
   */
  static async getAvailableTechnicians(): Promise<TechnicianAvailability[]> {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, full_name, role, is_active, default_vehicle_id')
      .eq('role', 'technician')
      .eq('is_active', true);

    if (error) {
      console.error('[LiveDataService] Error fetching technicians:', error);
      return [];
    }

    return (data || []).map((tech: any) => {
      const nameParts = (tech.full_name || 'Unknown').split(' ');
      const initials = nameParts.length >= 2
        ? `${nameParts[0][0]}${nameParts[nameParts.length - 1][0]}`.toUpperCase()
        : nameParts[0].substring(0, 2).toUpperCase();

      return {
        id: tech.id,
        name: tech.full_name || 'Unknown',
        initials,
        role: tech.role,
        isActive: tech.is_active,
        defaultVehicleId: tech.default_vehicle_id,
      };
    });
  }

  /**
   * Get reorder alerts from the view
   */
  static async getReorderAlerts(limit = 20): Promise<ReorderAlert[]> {
    const { data, error } = await supabase
      .from('vw_reorder_alerts')
      .select('*')
      .limit(limit);

    if (error) {
      console.error('[LiveDataService] Error fetching reorder alerts:', error);
      return [];
    }

    return (data || []).map((alert: any) => ({
      partId: alert.part_id,
      partNumber: alert.part_number || '',
      partName: alert.part_name || 'Unknown Part',
      locationName: alert.location_name || 'Unknown Location',
      locationType: alert.location_type || 'unknown',
      qtyOnHand: alert.qty_on_hand || 0,
      reorderPoint: alert.reorder_point || 0,
      reorderQty: alert.reorder_qty || 0,
      preferredVendor: alert.preferred_vendor_name,
    }));
  }

  /**
   * Get equipment history for a customer
   */
  static async getEquipmentHistory(customerId: string): Promise<EquipmentRecord[]> {
    const { data, error } = await supabase
      .from('equipment')
      .select(`
        id,
        equipment_type,
        manufacturer,
        model_number,
        serial_number,
        installation_date,
        warranty_expiration
      `)
      .eq('customer_id', customerId);

    if (error) {
      console.error('[LiveDataService] Error fetching equipment:', error);
      return [];
    }

    return (data || []).map((eq: any) => ({
      id: eq.id,
      equipmentType: eq.equipment_type || 'Unknown',
      manufacturer: eq.manufacturer,
      modelNumber: eq.model_number,
      serialNumber: eq.serial_number,
      installedAt: eq.installation_date,
      warrantyExpiresAt: eq.warranty_expiration,
      lastServiceDate: null, // Not available on equipment table - derived from service history
    }));
  }

  /**
   * Get service history for a specific equipment unit
   */
  static async getEquipmentServiceHistory(equipmentId: string): Promise<ServiceHistoryEntry[]> {
    const { data, error } = await supabase
      .from('customer_service_history')
      .select('*')
      .eq('equipment_id', equipmentId)
      .order('service_date', { ascending: false });

    if (error) {
      console.error('[LiveDataService] Error fetching service history:', error);
      return [];
    }

    return (data || []).map((entry: any) => ({
      ticketId: entry.ticket_id || '',
      ticketNumber: entry.ticket_number || 'N/A',
      ticketTitle: entry.ticket_title || 'Unknown',
      serviceDate: entry.service_date,
      technicianName: entry.technician_name,
      status: entry.ticket_status || 'unknown',
    }));
  }

  /**
   * Get full equipment intelligence with pattern recognition
   * This is the core Tech Co-Pilot analysis method
   */
  static async getEquipmentIntelligence(equipmentId: string): Promise<EquipmentIntelligence | null> {
    // Get equipment details - Corrected column names
    const { data: eqData, error: eqError } = await supabase
      .from('equipment')
      .select(`
        id,
        equipment_type,
        manufacturer,
        model_number,
        serial_number,
        installation_date,
        warranty_expiration
      `)
      .eq('id', equipmentId)
      .single();

    if (eqError || !eqData) {
      console.error('[LiveDataService] Error fetching equipment:', eqError);
      return null;
    }

    // Get service history
    const serviceHistory = await this.getEquipmentServiceHistory(equipmentId);

    // Calculate metrics
    const now = new Date();
    const oneYearAgo = new Date(now.getFullYear() - 1, now.getMonth(), now.getDate());

    const serviceCallsLast12Months = serviceHistory.filter(entry => {
      const serviceDate = new Date(entry.serviceDate);
      return serviceDate >= oneYearAgo;
    }).length;

    // Calculate age - Corrected column name
    const installedAt = eqData.installation_date ? new Date(eqData.installation_date) : null;
    const ageYears = installedAt
      ? Math.floor((now.getTime() - installedAt.getTime()) / (365.25 * 24 * 60 * 60 * 1000))
      : 0;

    // Warranty status - Corrected column name
    const warrantyExpires = eqData.warranty_expiration ? new Date(eqData.warranty_expiration) : null;
    const warrantyStatus: 'active' | 'expired' | 'unknown' = warrantyExpires
      ? (warrantyExpires > now ? 'active' : 'expired')
      : 'unknown';

    // Pattern recognition: Chronic unit detection
    // A unit is chronic if: 3+ service calls in 12 months OR 5+ total calls
    const isChronic = serviceCallsLast12Months >= 3 || serviceHistory.length >= 5;

    let chronicReason: string | null = null;
    if (isChronic) {
      if (serviceCallsLast12Months >= 3) {
        chronicReason = `${serviceCallsLast12Months} service calls in last 12 months`;
      } else if (serviceHistory.length >= 5) {
        chronicReason = `${serviceHistory.length} total service calls on record`;
      }
    }

    // Recommendation logic
    let recommendedAction: 'repair' | 'replace' | 'monitor' = 'repair';
    let confidenceScore = 70;

    if (isChronic && ageYears >= 10) {
      recommendedAction = 'replace';
      confidenceScore = 92;
    } else if (isChronic && ageYears >= 7) {
      recommendedAction = 'replace';
      confidenceScore = 85;
    } else if (isChronic) {
      recommendedAction = 'repair';
      confidenceScore = 75;
    } else if (ageYears >= 15) {
      recommendedAction = 'replace';
      confidenceScore = 80;
    } else if (serviceHistory.length === 0) {
      recommendedAction = 'monitor';
      confidenceScore = 60;
    }

    // Derive last service date from service history
    const lastServiceDate = serviceHistory.length > 0 ? serviceHistory[0].serviceDate : null;

    const equipment: EquipmentRecord = {
      id: eqData.id,
      equipmentType: eqData.equipment_type || 'Unknown',
      manufacturer: eqData.manufacturer,
      modelNumber: eqData.model_number,
      serialNumber: eqData.serial_number,
      installedAt: eqData.installation_date,
      warrantyExpiresAt: eqData.warranty_expiration,
      lastServiceDate,
    };

    return {
      equipment,
      serviceHistory,
      totalServiceCalls: serviceHistory.length,
      serviceCallsLast12Months,
      isChronic,
      chronicReason,
      ageYears,
      warrantyStatus,
      recommendedAction,
      confidenceScore,
    };
  }

  /**
   * Get equipment intelligence by customer (analyzes all equipment)
   */
  static async getCustomerEquipmentIntelligence(customerId: string): Promise<EquipmentIntelligence[]> {
    console.log('[LiveDataService] getCustomerEquipmentIntelligence called for:', customerId);
    const equipment = await this.getEquipmentHistory(customerId);
    console.log('[LiveDataService] Equipment found:', equipment.length, 'items');

    const results: EquipmentIntelligence[] = [];

    for (const eq of equipment) {
      console.log('[LiveDataService] Getting intelligence for equipment:', eq.id);
      const intelligence = await this.getEquipmentIntelligence(eq.id);
      if (intelligence) {
        results.push(intelligence);
      }
    }

    console.log('[LiveDataService] Final results:', results.length, 'items');
    // Sort by chronic status and service calls
    return results.sort((a, b) => {
      if (a.isChronic && !b.isChronic) return -1;
      if (!a.isChronic && b.isChronic) return 1;
      return b.serviceCallsLast12Months - a.serviceCallsLast12Months;
    });
  }

  /**
   * Get emergency/high priority tickets for immediate dispatch
   */
  static async getUrgentTickets(): Promise<LiveTicket[]> {
    const { data, error } = await supabase
      .from('tickets')
      .select(`
        id,
        ticket_number,
        title,
        description,
        priority,
        status,
        scheduled_date,
        estimated_minutes,
        latitude,
        longitude,
        assigned_to,
        created_at,
        customers (
          id,
          name,
          address,
          city,
          state
        ),
        profiles:assigned_to (
          full_name
        ),
        equipment:equipment_id (
          equipment_type,
          model_number
        )
      `)
      .in('status', ['new', 'open'])
      .in('priority', ['emergency', 'high'])
      .is('assigned_to', null)
      .order('priority', { ascending: true })
      .order('created_at', { ascending: true })
      .limit(10);

    if (error) {
      console.error('[LiveDataService] Error fetching urgent tickets:', error);
      return [];
    }

    return (data || []).map((ticket: any) => ({
      id: ticket.id,
      ticketNumber: ticket.ticket_number || 'N/A',
      title: ticket.title || 'Untitled',
      description: ticket.description,
      priority: ticket.priority,
      status: ticket.status,
      scheduledDate: ticket.scheduled_date,
      estimatedMinutes: ticket.estimated_minutes,
      customerName: ticket.customers?.name || 'Unknown Customer',
      customerId: ticket.customers?.id || '',
      address: ticket.customers?.address,
      city: ticket.customers?.city,
      state: ticket.customers?.state,
      latitude: ticket.latitude,
      longitude: ticket.longitude,
      assignedTo: ticket.assigned_to,
      technicianName: ticket.profiles?.full_name || null,
      equipmentType: ticket.equipment?.equipment_type || null,
      equipmentModel: ticket.equipment?.model_number || null,
      createdAt: ticket.created_at,
    }));
  }

  // ============================================
  // PHASE 3: CRM STRIKE - Sales Pipeline Methods
  // ============================================

  /**
   * Get sales pipeline items (open estimates)
   */
  static async getSalesPipeline(minProbability = 50, limit = 20): Promise<SalesPipelineItem[]> {
    const { data, error } = await supabase
      .from('vw_sales_pipeline')
      .select('*')
      .in('status', ['draft', 'sent'])
      .gte('probability', minProbability)
      .order('total_amount', { ascending: false })
      .order('probability', { ascending: false })
      .limit(limit);

    if (error) {
      console.error('[LiveDataService] Error fetching sales pipeline:', error);
      return [];
    }

    return (data || []).map((item: any) => ({
      estimateId: item.estimate_id,
      estimateNumber: item.estimate_number || 'N/A',
      customerId: item.customer_id || '',
      customerName: item.customer_name || 'Unknown',
      customerPhone: item.customer_phone,
      title: item.title || 'Untitled Estimate',
      totalAmount: item.total_amount || 0,
      status: item.status || 'draft',
      stageName: item.stage_name || 'Unknown Stage',
      probability: item.probability || 0,
      daysInStage: item.days_in_stage || 0,
      expectedCloseDate: item.expected_close_date,
    }));
  }

  /**
   * Get open estimates for a specific customer
   */
  static async getCustomerOpenEstimates(customerId: string): Promise<SalesPipelineItem[]> {
    const { data, error } = await supabase
      .from('vw_sales_pipeline')
      .select('*')
      .eq('customer_id', customerId)
      .in('status', ['draft', 'sent'])
      .order('total_amount', { ascending: false });

    if (error) {
      console.error('[LiveDataService] Error fetching customer estimates:', error);
      return [];
    }

    return (data || []).map((item: any) => ({
      estimateId: item.estimate_id,
      estimateNumber: item.estimate_number || 'N/A',
      customerId: item.customer_id || '',
      customerName: item.customer_name || 'Unknown',
      customerPhone: item.customer_phone,
      title: item.title || 'Untitled Estimate',
      totalAmount: item.total_amount || 0,
      status: item.status || 'draft',
      stageName: item.stage_name || 'Unknown Stage',
      probability: item.probability || 0,
      daysInStage: item.days_in_stage || 0,
      expectedCloseDate: item.expected_close_date,
    }));
  }

  /**
   * Get full sales intelligence for a customer
   * Identifies upsell opportunities when tech is on-site
   */
  static async getCustomerSalesIntelligence(customerId: string, customerName: string): Promise<CustomerSalesIntelligence> {
    const openEstimates = await this.getCustomerOpenEstimates(customerId);

    const totalPipelineValue = openEstimates.reduce((sum, est) => sum + est.totalAmount, 0);
    const highestProbability = openEstimates.length > 0
      ? Math.max(...openEstimates.map(e => e.probability))
      : 0;

    // Determine upsell opportunity
    // High-value consolidation: tech on-site + open estimate > $500 with probability >= 50%
    const highValueEstimates = openEstimates.filter(e => e.totalAmount >= 500 && e.probability >= 50);
    const hasUpsellOpportunity = highValueEstimates.length > 0;

    let upsellReason: string | null = null;
    if (hasUpsellOpportunity) {
      const topEstimate = highValueEstimates[0];
      upsellReason = `Open estimate #${topEstimate.estimateNumber} for $${topEstimate.totalAmount.toLocaleString()} (${topEstimate.probability}% probability) - "${topEstimate.title}"`;
    }

    return {
      customerId,
      customerName,
      openEstimates,
      totalPipelineValue,
      highestProbability,
      hasUpsellOpportunity,
      upsellReason,
    };
  }

  /**
   * Get high-value pipeline opportunities across all customers
   */
  static async getHighValueOpportunities(minAmount = 1000, minProbability = 60): Promise<SalesPipelineItem[]> {
    const { data, error } = await supabase
      .from('vw_sales_pipeline')
      .select('*')
      .in('status', ['draft', 'sent'])
      .gte('total_amount', minAmount)
      .gte('probability', minProbability)
      .order('total_amount', { ascending: false })
      .limit(10);

    if (error) {
      console.error('[LiveDataService] Error fetching high-value opportunities:', error);
      return [];
    }

    return (data || []).map((item: any) => ({
      estimateId: item.estimate_id,
      estimateNumber: item.estimate_number || 'N/A',
      customerId: item.customer_id || '',
      customerName: item.customer_name || 'Unknown',
      customerPhone: item.customer_phone,
      title: item.title || 'Untitled Estimate',
      totalAmount: item.total_amount || 0,
      status: item.status || 'draft',
      stageName: item.stage_name || 'Unknown Stage',
      probability: item.probability || 0,
      daysInStage: item.days_in_stage || 0,
      expectedCloseDate: item.expected_close_date,
    }));
  }

  /**
   * Get latent sales opportunities from completed tickets
   * Mines completed tickets for replacement/upgrade indicators that haven't been converted to estimates
   */
  static async getLatentSalesOpportunities(limit = 10): Promise<LatentSalesOpportunity[]> {
    // Keywords indicating replacement or major upgrade needed
    const replacementKeywords = [
      'recommend replacement',
      'end of life',
      'eol',
      'replace unit',
      'needs replacement',
      'gas leak',
      'compressor failed',
      'major failure',
      'condemned',
      'not repairable',
      'beyond repair',
      'obsolete',
      'no longer serviceable',
      'recommend new',
      'upgrade recommended',
    ];

    // Build OR filter for text search
    const keywordFilter = replacementKeywords.map(k => `resolution.ilike.%${k}%`).join(',');

    const { data, error } = await supabase
      .from('tickets')
      .select(`
        id,
        ticket_number,
        title,
        resolution,
        completed_date,
        customer_id,
        customers (
          id,
          name,
          phone,
          address
        ),
        equipment:equipment_id (
          id,
          equipment_type,
          model_number,
          manufacturer
        ),
        problem_code:problem_code (
          code,
          triggers_sales_lead
        ),
        resolution_code:resolution_code (
          code,
          triggers_sales_lead
        )
      `)
      .in('status', ['completed', 'closed_billed'])
      .not('resolution', 'is', null)
      .or(keywordFilter)
      .order('completed_date', { ascending: false })
      .limit(limit * 2); // Fetch more to filter locally

    if (error) {
      console.error('[LiveDataService] Error fetching latent opportunities:', error);
      return [];
    }

    // Filter results to ensure we match keywords OR sales flags
    const opportunities = (data || [])
      .filter((ticket: any) => {
        const resolution = (ticket.resolution || '').toLowerCase();
        const hasKeyword = replacementKeywords.some(keyword => resolution.includes(keyword.toLowerCase()));
        const hasProblemFlag = ticket.problem_code?.triggers_sales_lead;
        const hasResolutionFlag = ticket.resolution_code?.triggers_sales_lead;
        
        // Include if ANY condition matches
        return hasKeyword || hasProblemFlag || hasResolutionFlag;
      })
      .slice(0, limit)
      .map((ticket: any) => {
        const resolution = (ticket.resolution || '').toLowerCase();
        const hasProblemFlag = ticket.problem_code?.triggers_sales_lead;
        const hasResolutionFlag = ticket.resolution_code?.triggers_sales_lead;

        // Determine opportunity type
        let opportunityType: 'replacement' | 'upgrade' | 'repair' = 'replacement';
        let reason = 'Replacement recommended in service notes';

        if (hasProblemFlag || hasResolutionFlag) {
           reason = 'Flagged by Standard Code as Sales Lead';
           opportunityType = 'replacement';
        } else if (resolution.includes('gas leak') || resolution.includes('compressor failed')) {
          opportunityType = 'replacement';
          reason = 'Critical failure - immediate replacement opportunity';
        } else if (resolution.includes('end of life') || resolution.includes('eol')) {
          opportunityType = 'replacement';
          reason = 'Equipment at end of life - replacement due';
        } else if (resolution.includes('upgrade')) {
          opportunityType = 'upgrade';
          reason = 'Upgrade recommended by technician';
        }

        // Calculate days since completion
        const completedDate = ticket.completed_date ? new Date(ticket.completed_date) : new Date();
        const daysSinceCompletion = Math.floor((Date.now() - completedDate.getTime()) / (1000 * 60 * 60 * 24));

        return {
          ticketId: ticket.id,
          ticketNumber: ticket.ticket_number || 'N/A',
          ticketTitle: ticket.title || 'Untitled',
          resolution: ticket.resolution,
          completedDate: ticket.completed_date,
          daysSinceCompletion,
          customerId: ticket.customers?.id || ticket.customer_id || '',
          customerName: ticket.customers?.name || 'Unknown Customer',
          customerPhone: ticket.customers?.phone || null,
          customerAddress: ticket.customers?.address || null,
          equipmentId: ticket.equipment?.id || null,
          equipmentType: ticket.equipment?.equipment_type || null,
          equipmentModel: ticket.equipment?.model_number || null,
          manufacturer: ticket.equipment?.manufacturer || null,
          opportunityType,
          reason,
          estimatedValue: opportunityType === 'replacement' ? 5000 : 2000,
          conversionPriority: daysSinceCompletion <= 30 ? 'high' : daysSinceCompletion <= 90 ? 'medium' : 'low',
        };
      });

    return opportunities;
  }
}

// Latent sales opportunity type for ticket mining
export interface LatentSalesOpportunity {
  ticketId: string;
  ticketNumber: string;
  ticketTitle: string;
  resolution: string;
  completedDate: string | null;
  daysSinceCompletion: number;
  customerId: string;
  customerName: string;
  customerPhone: string | null;
  customerAddress: string | null;
  equipmentId: string | null;
  equipmentType: string | null;
  equipmentModel: string | null;
  manufacturer: string | null;
  opportunityType: 'replacement' | 'upgrade' | 'repair';
  reason: string;
  estimatedValue: number;
  conversionPriority: 'high' | 'medium' | 'low';
}

export default LiveDataService;