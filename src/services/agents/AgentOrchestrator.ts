/**
 * Agent Orchestrator Service
 * LOCAL DEMO ONLY - DO NOT COMMIT
 *
 * Coordinates multi-agent communication, handles demo mode,
 * live data integration, and tracks session statistics.
 */

import {
  AgentId,
  AgentMessage,
  AgentAction,
  SessionStats,
  DemoScenario,
  DemoStep,
  AGENT_CONFIGS,
  calculateCost,
  MessageStatus,
} from '../../types/agents';
import { LiveDataService, LiveTicket, TechInventoryItem, EquipmentIntelligence, CustomerSalesIntelligence, SalesPipelineItem, LatentSalesOpportunity } from './LiveDataService';

type MessageCallback = (message: AgentMessage) => void;
type ActionCallback = (action: AgentAction) => void;

// Live analysis result for canvas updates
export interface LiveAnalysisResult {
  tickets: LiveTicket[];
  technicians: Array<{
    id: string;
    name: string;
    initials: string;
    hasPart: boolean;
    inventory: TechInventoryItem[];
  }>;
  selectedTicket: LiveTicket | null;
  recommendedTech: string | null;
  equipmentIntelligence: EquipmentIntelligence | null;
  salesIntelligence: CustomerSalesIntelligence | null;
  latentOpportunities: LatentSalesOpportunity[];
}

class AgentOrchestrator {
  private messages: AgentMessage[] = [];
  private actions: AgentAction[] = [];
  private messageListeners: MessageCallback[] = [];
  private actionListeners: ActionCallback[] = [];
  private sessionStats: SessionStats;
  private isDemoMode: boolean = true;
  private isLiveMode: boolean = false;
  private isRunning: boolean = false;
  private currentDemoStep: number = 0;
  private lastLiveAnalysis: LiveAnalysisResult | null = null;

  constructor() {
    this.sessionStats = this.initializeStats();
  }

  private initializeStats(): SessionStats {
    return {
      totalMessages: 0,
      totalTokensInput: 0,
      totalTokensOutput: 0,
      totalCost: 0,
      agentBreakdown: {},
      startTime: new Date(),
      lastActivity: new Date(),
    };
  }

  // Subscribe to message updates
  onMessage(callback: MessageCallback): () => void {
    this.messageListeners.push(callback);
    return () => {
      this.messageListeners = this.messageListeners.filter(cb => cb !== callback);
    };
  }

  // Subscribe to action updates
  onAction(callback: ActionCallback): () => void {
    this.actionListeners.push(callback);
    return () => {
      this.actionListeners = this.actionListeners.filter(cb => cb !== callback);
    };
  }

  // Emit message to all listeners
  private emitMessage(message: AgentMessage): void {
    this.messages.push(message);
    this.updateStats(message);
    this.messageListeners.forEach(cb => cb(message));
  }

  // Emit action to all listeners
  private emitAction(action: AgentAction): void {
    this.actions.push(action);
    this.actionListeners.forEach(cb => cb(action));
  }

  // Update session statistics
  private updateStats(message: AgentMessage): void {
    this.sessionStats.totalMessages++;
    this.sessionStats.lastActivity = new Date();

    if (message.tokensUsed) {
      this.sessionStats.totalTokensInput += message.tokensUsed.input;
      this.sessionStats.totalTokensOutput += message.tokensUsed.output;
    }

    if (message.cost) {
      this.sessionStats.totalCost += message.cost;
    }

    // Update agent breakdown
    const agentStats = this.sessionStats.agentBreakdown[message.fromAgent] || {
      messages: 0,
      tokensInput: 0,
      tokensOutput: 0,
      cost: 0,
      avgLatencyMs: 0,
    };

    agentStats.messages++;
    if (message.tokensUsed) {
      agentStats.tokensInput += message.tokensUsed.input;
      agentStats.tokensOutput += message.tokensUsed.output;
    }
    if (message.cost) {
      agentStats.cost += message.cost;
    }
    if (message.latencyMs) {
      agentStats.avgLatencyMs =
        (agentStats.avgLatencyMs * (agentStats.messages - 1) + message.latencyMs) / agentStats.messages;
    }

    this.sessionStats.agentBreakdown[message.fromAgent] = agentStats;
  }

  // Get all messages
  getMessages(): AgentMessage[] {
    return [...this.messages];
  }

  // Get all pending actions
  getPendingActions(): AgentAction[] {
    return this.actions.filter(a => a.status === 'PENDING_APPROVAL');
  }

  // Get session stats
  getStats(): SessionStats {
    return { ...this.sessionStats };
  }

  // Toggle demo mode
  setDemoMode(enabled: boolean): void {
    this.isDemoMode = enabled;
    if (enabled) this.isLiveMode = false;
  }

  isDemoModeEnabled(): boolean {
    return this.isDemoMode;
  }

  // Toggle live mode
  setLiveMode(enabled: boolean): void {
    this.isLiveMode = enabled;
    if (enabled) this.isDemoMode = false;
  }

  isLiveModeEnabled(): boolean {
    return this.isLiveMode;
  }

  // Get last live analysis result
  getLastLiveAnalysis(): LiveAnalysisResult | null {
    return this.lastLiveAnalysis;
  }

  // Run live data analysis
  async runLiveAnalysis(): Promise<LiveAnalysisResult | null> {
    if (this.isRunning) return null;

    this.isRunning = true;
    this.messages = [];
    this.actions = [];
    this.sessionStats = this.initializeStats();

    try {
      // Emit start message
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'ORCHESTRATOR',
        toAgent: 'ALL',
        type: 'RESPONSE',
        content: '[LIVE] Initiating live dispatch analysis. Querying Supabase...',
        status: 'EXECUTED',
      });

      await this.delay(500);

      // Step 1: Dispatch Agent fetches open tickets
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'DISPATCH',
        toAgent: 'ALL',
        type: 'THINKING',
        content: 'Querying open tickets from database...',
        status: 'THINKING',
      });

      const tickets = await LiveDataService.getOpenTickets(10);
      const urgentTickets = tickets.filter(t => t.priority === 'urgent' || t.priority === 'high');

      // Emit dispatch analysis
      const dispatchContent = urgentTickets.length > 0
        ? `[ANALYSIS] **Live Dispatch Analysis**\n\nFound ${tickets.length} open tickets\n- Urgent: ${urgentTickets.length} (emergency/high priority)\n- Unassigned: ${tickets.filter(t => !t.assignedTo).length}\n\n**Priority Ticket:**\n- #${urgentTickets[0]?.ticketNumber || 'N/A'}: ${urgentTickets[0]?.title || 'N/A'}\n- Customer: ${urgentTickets[0]?.customerName || 'Unknown'}\n- Location: ${urgentTickets[0]?.address || 'No address'}, ${urgentTickets[0]?.city || ''}\n- Priority: ${urgentTickets[0]?.priority || 'normal'}\n\n**Routing to Tech Co-Pilot for analysis.**`
        : `[ANALYSIS] **Live Dispatch Analysis**\n\nFound ${tickets.length} open tickets\n- No urgent tickets at this time\n- Unassigned: ${tickets.filter(t => !t.assignedTo).length}\n\n**System nominal.**`;

      await this.delay(800);
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'DISPATCH',
        toAgent: 'TECH_COPILOT',
        type: 'RESPONSE',
        content: dispatchContent,
        status: 'EXECUTED',
        tokensUsed: { input: 1200, output: 200 },
        cost: calculateCost('DISPATCH', 1200, 200),
      });

      // Step 2: Tech Co-Pilot equipment intelligence analysis
      let equipmentIntelligence: EquipmentIntelligence | null = null;
      const selectedTicket = urgentTickets[0] || tickets[0];

      if (selectedTicket?.customerId) {
        await this.delay(600);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'TECH_COPILOT',
          toAgent: 'ALL',
          type: 'THINKING',
          content: `Analyzing equipment history for ${selectedTicket.customerName}...`,
          status: 'THINKING',
        });

        // Get equipment intelligence for the customer
        const equipmentList = await LiveDataService.getCustomerEquipmentIntelligence(selectedTicket.customerId);
        equipmentIntelligence = equipmentList[0] || null;

        await this.delay(800);

        if (equipmentIntelligence) {
          const chronicWarning = equipmentIntelligence.isChronic
            ? `\n\n**[CHRONIC UNIT DETECTED]**\n- ${equipmentIntelligence.chronicReason}\n- Recommendation: ${equipmentIntelligence.recommendedAction.toUpperCase()}\n- Confidence: ${equipmentIntelligence.confidenceScore}%`
            : '';

          const warrantyNote = equipmentIntelligence.warrantyStatus === 'expired'
            ? '\n- Warranty: EXPIRED'
            : equipmentIntelligence.warrantyStatus === 'active'
            ? '\n- Warranty: Active'
            : '';

          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'TECH_COPILOT',
            toAgent: 'PARTS',
            type: 'RESPONSE',
            content: `[DIAGNOSTIC] **Equipment Intelligence Report**\n\nUnit: ${equipmentIntelligence.equipment.equipmentType}\n- Model: ${equipmentIntelligence.equipment.modelNumber || 'N/A'}\n- Serial: ${equipmentIntelligence.equipment.serialNumber || 'N/A'}\n- Age: ${equipmentIntelligence.ageYears} years${warrantyNote}\n\n**Service History:**\n- Total Calls: ${equipmentIntelligence.totalServiceCalls}\n- Last 12 Months: ${equipmentIntelligence.serviceCallsLast12Months}${chronicWarning}\n\n**Routing to Parts Agent for inventory verification.**`,
            status: 'EXECUTED',
            tokensUsed: { input: 1200, output: 250 },
            cost: calculateCost('TECH_COPILOT', 1200, 250),
          });
        } else {
          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'TECH_COPILOT',
            toAgent: 'PARTS',
            type: 'RESPONSE',
            content: `[DIAGNOSTIC] **Equipment Intelligence Report**\n\nNo equipment records found for ${selectedTicket.customerName}.\n\n**Routing to Parts Agent for inventory verification.**`,
            status: 'EXECUTED',
            tokensUsed: { input: 400, output: 80 },
            cost: calculateCost('TECH_COPILOT', 400, 80),
          });
        }
      }

      // Step 3: Get available technicians
      await this.delay(600);
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'TECH_COPILOT',
        toAgent: 'ALL',
        type: 'THINKING',
        content: 'Analyzing technician availability and inventory...',
        status: 'THINKING',
      });

      const technicians = await LiveDataService.getAvailableTechnicians();

      // Get inventory for each technician
      const techsWithInventory = await Promise.all(
        technicians.slice(0, 5).map(async (tech) => {
          const inventory = await LiveDataService.getTechnicianInventory(tech.id);
          return {
            id: tech.id,
            name: tech.name,
            initials: tech.initials,
            hasPart: inventory.length > 0,
            inventory,
          };
        })
      );

      // Emit tech analysis
      const techContent = techsWithInventory.length > 0
        ? `[STATUS] **Technician Availability**\n\n${techsWithInventory.map(t =>
            `- ${t.name}: ${t.inventory.length} parts on truck`
          ).join('\n')}\n\n**Routing to Parts Agent for inventory verification.**`
        : `[ALERT] **Technician Availability**\n\nNo active technicians found in system.\n\n**Alert: Staffing issue detected.**`;

      await this.delay(700);
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'TECH_COPILOT',
        toAgent: 'PARTS',
        type: 'RESPONSE',
        content: techContent,
        status: 'EXECUTED',
        tokensUsed: { input: 800, output: 150 },
        cost: calculateCost('TECH_COPILOT', 800, 150),
      });

      // Step 4: Parts Agent checks inventory
      await this.delay(500);
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'PARTS',
        toAgent: 'ALL',
        type: 'QUERY',
        content: '[QUERY] Checking reorder alerts and inventory status...',
        status: 'EXECUTED',
      });

      const reorderAlerts = await LiveDataService.getReorderAlerts(5);

      // Adjust Parts recommendation based on chronic unit status
      let partsRecommendation = '';
      if (equipmentIntelligence?.isChronic && equipmentIntelligence.recommendedAction === 'replace') {
        partsRecommendation = `\n\n**[CHRONIC UNIT OVERRIDE]**\nTech Co-Pilot flagged this unit as chronic (${equipmentIntelligence.chronicReason}).\n**Recommendation:** Skip repair parts. Generate replacement estimate instead.`;
      }

      const partsContent = reorderAlerts.length > 0
        ? `[ALERT] **Inventory Status**\n\n${reorderAlerts.length} reorder alerts active:\n${reorderAlerts.slice(0, 3).map(a =>
            `- ${a.partName} (${a.partNumber}): ${a.qtyOnHand} on hand, reorder at ${a.reorderPoint}`
          ).join('\n')}\n\n**Recommend: Generate POs for critical items.**${partsRecommendation}`
        : `[STATUS] **Inventory Status**\n\nAll inventory levels nominal. No reorder alerts.${partsRecommendation}\n\n**System healthy.**`;

      await this.delay(600);
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'PARTS',
        toAgent: 'DISPATCH',
        type: 'RESPONSE',
        content: partsContent,
        status: 'EXECUTED',
        tokensUsed: { input: 600, output: 120 },
        cost: calculateCost('PARTS', 600, 120),
      });

      // Step 4: Generate action if there's an urgent unassigned ticket
      const unassignedUrgent = urgentTickets.find(t => !t.assignedTo);
      const recommendedTech = techsWithInventory[0];

      if (unassignedUrgent && recommendedTech) {
        await this.delay(800);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'DISPATCH',
          toAgent: 'ARCHITECT',
          type: 'RESPONSE',
          content: `[REROUTE] **Assignment Recommendation**\n\nTicket #${unassignedUrgent.ticketNumber}\n- ${unassignedUrgent.title}\n- Customer: ${unassignedUrgent.customerName}\n- Priority: ${unassignedUrgent.priority}\n\n**Recommended:** Assign to ${recommendedTech.name}\n- Has ${recommendedTech.inventory.length} parts on truck\n\n**Awaiting Architect approval.**`,
          status: 'PENDING',
          requiresApproval: true,
          tokensUsed: { input: 1800, output: 150 },
          cost: calculateCost('DISPATCH', 1800, 150),
        });

        // Emit action for approval
        this.emitAction({
          id: crypto.randomUUID(),
          agentId: 'DISPATCH',
          actionType: 'ASSIGN_TECH',
          description: `Assign ${recommendedTech.name} to Ticket #${unassignedUrgent.ticketNumber}`,
          preview: `This will:\n• Assign ${recommendedTech.name} to ${unassignedUrgent.title}\n• Customer: ${unassignedUrgent.customerName}\n• Location: ${unassignedUrgent.address || 'No address'}`,
          data: {
            ticketId: unassignedUrgent.id,
            technicianId: recommendedTech.id,
            ticketNumber: unassignedUrgent.ticketNumber,
          },
          status: 'PENDING_APPROVAL',
          createdAt: new Date(),
        });
      }

      // Step 5: CRM Opportunity Strike - Check for upsell opportunities
      let salesIntelligence: CustomerSalesIntelligence | null = null;
      let globalPipelineItems: SalesPipelineItem[] = [];
      let latentOpportunities: LatentSalesOpportunity[] = [];

      if (selectedTicket?.customerId) {
        // Customer-specific CRM strike
        await this.delay(500);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'CUSTOMER',
          toAgent: 'ALL',
          type: 'THINKING',
          content: `Scanning sales pipeline for ${selectedTicket.customerName}...`,
          status: 'THINKING',
        });

        salesIntelligence = await LiveDataService.getCustomerSalesIntelligence(
          selectedTicket.customerId,
          selectedTicket.customerName
        );

        await this.delay(600);

        if (salesIntelligence && salesIntelligence.hasUpsellOpportunity) {
          // High-value consolidation opportunity detected
          const topEstimate = salesIntelligence.openEstimates[0];

          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ARCHITECT',
            type: 'RESPONSE',
            content: `[CRM STRIKE] **High-Value Consolidation Opportunity**\n\n**Customer:** ${salesIntelligence.customerName}\n**Open Estimate:** #${topEstimate.estimateNumber}\n- ${topEstimate.title}\n- Value: $${topEstimate.totalAmount.toLocaleString()}\n- Stage: ${topEstimate.stageName} (${topEstimate.probability}% probability)\n- Days in Stage: ${topEstimate.daysInStage}\n\n**${salesIntelligence.upsellReason}**\n\n**Pipeline Summary:**\n- Open Estimates: ${salesIntelligence.openEstimates.length}\n- Total Pipeline Value: $${salesIntelligence.totalPipelineValue.toLocaleString()}\n\n**Recommended:** Present estimate to customer while tech is on-site.`,
            status: 'PENDING',
            requiresApproval: true,
            tokensUsed: { input: 1500, output: 200 },
            cost: calculateCost('CUSTOMER', 1500, 200),
          });

          // Emit Follow-up action for Approval Gate
          this.emitAction({
            id: crypto.randomUUID(),
            agentId: 'CUSTOMER',
            actionType: 'FOLLOW_UP',
            description: `Present Estimate #${topEstimate.estimateNumber} to ${salesIntelligence.customerName}`,
            preview: `This will:\n• Flag tech to discuss estimate during service visit\n• Estimate: ${topEstimate.title}\n• Value: $${topEstimate.totalAmount.toLocaleString()}\n• Customer: ${salesIntelligence.customerName}`,
            data: {
              customerId: selectedTicket.customerId,
              customerName: salesIntelligence.customerName,
              estimateId: topEstimate.estimateId,
              estimateNumber: topEstimate.estimateNumber,
              estimateValue: topEstimate.totalAmount,
              ticketId: selectedTicket.id,
              ticketNumber: selectedTicket.ticketNumber,
            },
            status: 'PENDING_APPROVAL',
            createdAt: new Date(),
          });
        } else if (salesIntelligence && salesIntelligence.openEstimates.length > 0) {
          // Has open estimates but below high-value threshold
          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ALL',
            type: 'RESPONSE',
            content: `[CRM INTEL] **Sales Pipeline Status**\n\nCustomer: ${salesIntelligence.customerName}\n- Open Estimates: ${salesIntelligence.openEstimates.length}\n- Total Pipeline: $${salesIntelligence.totalPipelineValue.toLocaleString()}\n- Highest Probability: ${salesIntelligence.highestProbability}%\n\n**No high-priority upsell signal.** Monitor for future opportunity.`,
            status: 'EXECUTED',
            tokensUsed: { input: 800, output: 100 },
            cost: calculateCost('CUSTOMER', 800, 100),
          });
        } else {
          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ALL',
            type: 'RESPONSE',
            content: `[CRM INTEL] **Sales Pipeline Status**\n\nCustomer: ${salesIntelligence?.customerName || selectedTicket.customerName}\n- No open estimates in pipeline.\n\n**Opportunity:** Consider generating estimate if equipment replacement discussed on-site.`,
            status: 'EXECUTED',
            tokensUsed: { input: 400, output: 60 },
            cost: calculateCost('CUSTOMER', 400, 60),
          });
        }
      } else {
        // GLOBAL PIVOT: No ticket context - execute Global Sales Audit
        await this.delay(500);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'ORCHESTRATOR',
          toAgent: 'ALL',
          type: 'RESPONSE',
          content: '[PIVOT] **No active tickets detected.** Initiating Global Revenue Audit...',
          status: 'EXECUTED',
          tokensUsed: { input: 200, output: 40 },
          cost: calculateCost('ORCHESTRATOR', 200, 40),
        });

        // Tech Co-Pilot: Global Fleet Health Signal
        await this.delay(600);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'TECH_COPILOT',
          toAgent: 'ALL',
          type: 'THINKING',
          content: 'Analyzing global fleet health and technician readiness...',
          status: 'THINKING',
        });

        await this.delay(800);
        const fleetHealthNote = techsWithInventory.length > 0
          ? `**Fleet Status:**\n${techsWithInventory.map(t => `- ${t.name}: ${t.inventory.length} parts ready`).join('\n')}`
          : '**Fleet Status:** No technicians currently active.';

        const alertNote = reorderAlerts.length > 0
          ? `\n\n**Inventory Alerts:** ${reorderAlerts.length} items below reorder threshold.`
          : '\n\n**Inventory Status:** All stock levels nominal.';

        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'TECH_COPILOT',
          toAgent: 'CUSTOMER',
          type: 'RESPONSE',
          content: `[GLOBAL FLEET HEALTH] **System Status Report**\n\n${fleetHealthNote}${alertNote}\n\n**All technicians standing by.** Routing to CRM for revenue opportunities.`,
          status: 'EXECUTED',
          tokensUsed: { input: 600, output: 120 },
          cost: calculateCost('TECH_COPILOT', 600, 120),
        });

        // Customer Agent: Global Sales Pipeline Scan
        await this.delay(500);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'CUSTOMER',
          toAgent: 'ALL',
          type: 'THINKING',
          content: 'Executing Global Sales Pipeline scan...',
          status: 'THINKING',
        });

        // Get top opportunities from the entire pipeline
        globalPipelineItems = await LiveDataService.getHighValueOpportunities(500, 50);

        await this.delay(700);

        if (globalPipelineItems.length > 0) {
          const totalPipelineValue = globalPipelineItems.reduce((sum, item) => sum + item.totalAmount, 0);
          const top3 = globalPipelineItems.slice(0, 3);

          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ARCHITECT',
            type: 'RESPONSE',
            content: `[GLOBAL CRM STRIKE] **Revenue Opportunity Report**\n\n**Pipeline Summary:**\n- High-Value Estimates: ${globalPipelineItems.length}\n- Total Pipeline Value: $${totalPipelineValue.toLocaleString()}\n\n**Top 3 Opportunities:**\n${top3.map((item, i) =>
              `${i + 1}. **#${item.estimateNumber}** - ${item.customerName}\n   - ${item.title}\n   - Value: $${item.totalAmount.toLocaleString()} (${item.probability}% probability)\n   - Days in Stage: ${item.daysInStage}`
            ).join('\n\n')}\n\n**Recommend:** Schedule follow-up calls for these high-value prospects.`,
            status: 'PENDING',
            requiresApproval: true,
            tokensUsed: { input: 1800, output: 300 },
            cost: calculateCost('CUSTOMER', 1800, 300),
          });

          // Create Follow-up actions for top 3 estimates
          for (const item of top3) {
            this.emitAction({
              id: crypto.randomUUID(),
              agentId: 'CUSTOMER',
              actionType: 'FOLLOW_UP',
              description: `Follow up on Estimate #${item.estimateNumber} - ${item.customerName}`,
              preview: `This will:\n• Schedule follow-up call with ${item.customerName}\n• Estimate: ${item.title}\n• Value: $${item.totalAmount.toLocaleString()}\n• Probability: ${item.probability}%`,
              data: {
                customerId: item.customerId,
                customerName: item.customerName,
                estimateId: item.estimateId,
                estimateNumber: item.estimateNumber,
                estimateValue: item.totalAmount,
                ticketId: null,
                ticketNumber: null,
              },
              status: 'PENDING_APPROVAL',
              createdAt: new Date(),
            });
          }

          // Build synthetic sales intelligence for canvas
          salesIntelligence = {
            customerId: 'GLOBAL',
            customerName: 'Global Pipeline',
            openEstimates: globalPipelineItems,
            totalPipelineValue,
            highestProbability: Math.max(...globalPipelineItems.map(i => i.probability)),
            hasUpsellOpportunity: true,
            upsellReason: `${globalPipelineItems.length} high-value opportunities identified across business`,
          };
        } else {
          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ALL',
            type: 'RESPONSE',
            content: `[GLOBAL CRM INTEL] **Sales Pipeline Status**\n\nNo high-value estimates currently in pipeline.\n\n**Pivoting to Ticket Mining...**`,
            status: 'EXECUTED',
            tokensUsed: { input: 400, output: 60 },
            cost: calculateCost('CUSTOMER', 400, 60),
          });
        }

        // Step 6: Ticket Mining - Extract latent opportunities from completed tickets
        await this.delay(500);
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: 'CUSTOMER',
          toAgent: 'ALL',
          type: 'THINKING',
          content: 'Mining completed tickets for unconverted revenue opportunities...',
          status: 'THINKING',
        });

        latentOpportunities = await LiveDataService.getLatentSalesOpportunities(5);

        await this.delay(600);

        if (latentOpportunities.length > 0) {
          const totalEstimatedValue = latentOpportunities.reduce((sum, opp) => sum + opp.estimatedValue, 0);

          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ARCHITECT',
            type: 'RESPONSE',
            content: `[TICKET MINING] **Latent Revenue Discovered**\n\n**Completed Tickets with Replacement Indicators:**\n${latentOpportunities.map((opp, i) =>
              `${i + 1}. **#${opp.ticketNumber}** - ${opp.customerName}\n   - ${opp.ticketTitle}\n   - Reason: ${opp.reason}\n   - Est. Value: $${opp.estimatedValue.toLocaleString()}\n   - Days Since: ${opp.daysSinceCompletion} (${opp.conversionPriority.toUpperCase()} priority)`
            ).join('\n\n')}\n\n**Total Latent Value:** $${totalEstimatedValue.toLocaleString()}\n**Recommend:** Create estimates for these unconverted opportunities.`,
            status: 'PENDING',
            requiresApproval: true,
            tokensUsed: { input: 2000, output: 350 },
            cost: calculateCost('CUSTOMER', 2000, 350),
          });

          // Create CREATE_ESTIMATE actions for each latent opportunity
          for (const opp of latentOpportunities) {
            this.emitAction({
              id: crypto.randomUUID(),
              agentId: 'CUSTOMER',
              actionType: 'CREATE_ESTIMATE',
              description: `Create estimate for ${opp.customerName} - ${opp.equipmentType || 'Equipment'} ${opp.opportunityType}`,
              preview: `This will:\n• Generate new estimate for ${opp.customerName}\n• Based on: Ticket #${opp.ticketNumber}\n• Reason: ${opp.reason}\n• Equipment: ${opp.equipmentType || 'N/A'} ${opp.equipmentModel || ''}\n• Est. Value: $${opp.estimatedValue.toLocaleString()}`,
              data: {
                customerId: opp.customerId,
                customerName: opp.customerName,
                sourceTicketId: opp.ticketId,
                sourceTicketNumber: opp.ticketNumber,
                equipmentId: opp.equipmentId,
                equipmentType: opp.equipmentType,
                opportunityType: opp.opportunityType,
                estimatedValue: opp.estimatedValue,
                reason: opp.reason,
              },
              status: 'PENDING_APPROVAL',
              createdAt: new Date(),
            });
          }

          // Update sales intelligence with latent opportunities
          if (!salesIntelligence) {
            salesIntelligence = {
              customerId: 'LATENT',
              customerName: 'Ticket Mining',
              openEstimates: [],
              totalPipelineValue: totalEstimatedValue,
              highestProbability: 80, // High probability since these are based on tech recommendations
              hasUpsellOpportunity: true,
              upsellReason: `${latentOpportunities.length} unconverted opportunities mined from completed tickets`,
            };
          }
        } else {
          this.emitMessage({
            id: crypto.randomUUID(),
            timestamp: new Date(),
            fromAgent: 'CUSTOMER',
            toAgent: 'ALL',
            type: 'RESPONSE',
            content: `[TICKET MINING] **No Latent Opportunities Found**\n\nNo completed tickets with replacement indicators detected.\n\n**System Status:** Revenue pipeline is current.`,
            status: 'EXECUTED',
            tokensUsed: { input: 300, output: 50 },
            cost: calculateCost('CUSTOMER', 300, 50),
          });
        }
      }

      // Final summary
      await this.delay(500);
      const pendingCount = this.getPendingActions().length;
      const upsellNote = salesIntelligence?.hasUpsellOpportunity
        ? `\n- CRM Strike: ACTIVE (${salesIntelligence.openEstimates.length || 0} pipeline)`
        : '';
      const miningNote = latentOpportunities.length > 0
        ? `\n- Ticket Mining: ${latentOpportunities.length} unconverted`
        : '';

      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'ORCHESTRATOR',
        toAgent: 'ALL',
        type: 'RESPONSE',
        content: `[COMPLETE] **Live Analysis Summary**\n\n- Open Tickets: ${tickets.length}\n- Urgent: ${urgentTickets.length}\n- Active Technicians: ${techsWithInventory.length}\n- Reorder Alerts: ${reorderAlerts.length}${upsellNote}${miningNote}\n- Pending Actions: ${pendingCount}\n\n**Live data sync complete.**`,
        status: 'EXECUTED',
        tokensUsed: { input: 300, output: 80 },
        cost: calculateCost('ORCHESTRATOR', 300, 80),
      });

      // Store result for canvas
      this.lastLiveAnalysis = {
        tickets,
        technicians: techsWithInventory,
        selectedTicket: unassignedUrgent || urgentTickets[0] || tickets[0] || null,
        recommendedTech: recommendedTech?.id || null,
        equipmentIntelligence,
        salesIntelligence,
        latentOpportunities,
      };

      return this.lastLiveAnalysis;

    } catch (error) {
      console.error('[AgentOrchestrator] Live analysis error:', error);
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'ORCHESTRATOR',
        toAgent: 'ALL',
        type: 'RESPONSE',
        content: `[ERROR] Live analysis failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        status: 'EXECUTED',
      });
      return null;
    } finally {
      this.isRunning = false;
    }
  }

  // Approve an action
  approveAction(actionId: string): void {
    const action = this.actions.find(a => a.id === actionId);
    if (action) {
      action.status = 'APPROVED';
      action.executedAt = new Date();
      this.emitAction(action);

      // Emit confirmation message
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: action.agentId,
        toAgent: 'ARCHITECT',
        type: 'RESPONSE',
        content: `[APPROVED] Action executed: ${action.description}`,
        status: 'EXECUTED',
      });
    }
  }

  // Reject an action
  rejectAction(actionId: string, reason?: string): void {
    const action = this.actions.find(a => a.id === actionId);
    if (action) {
      action.status = 'REJECTED';
      this.emitAction(action);

      // Emit rejection message
      this.emitMessage({
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: 'ORCHESTRATOR',
        toAgent: action.agentId,
        type: 'RESPONSE',
        content: `[REJECTED] Action denied: ${action.description}${reason ? ` - Reason: ${reason}` : ''}`,
        status: 'EXECUTED',
      });
    }
  }

  // Run a demo scenario
  async runDemoScenario(scenario: DemoScenario): Promise<void> {
    if (this.isRunning) return;

    this.isRunning = true;
    this.currentDemoStep = 0;
    this.messages = [];
    this.actions = [];
    this.sessionStats = this.initializeStats();

    // Emit start message
    this.emitMessage({
      id: crypto.randomUUID(),
      timestamp: new Date(),
      fromAgent: 'ORCHESTRATOR',
      toAgent: 'ALL',
      type: 'RESPONSE',
      content: `[STARTING] Demo scenario: "${scenario.name}"`,
      status: 'EXECUTED',
    });

    for (const step of scenario.steps) {
      if (!this.isRunning) break;

      // Simulate thinking delay
      await this.delay(step.delayMs);

      // If step has thinking, emit thinking message first
      if (step.thinking) {
        this.emitMessage({
          id: crypto.randomUUID(),
          timestamp: new Date(),
          fromAgent: step.agentId,
          toAgent: step.toAgent || 'ALL',
          type: 'THINKING',
          content: step.thinking,
          status: 'THINKING',
        });

        await this.delay(800); // Brief pause after thinking
      }

      // Calculate cost
      const cost = calculateCost(step.agentId, step.tokensInput, step.tokensOutput);

      // Emit the main message
      const message: AgentMessage = {
        id: crypto.randomUUID(),
        timestamp: new Date(),
        fromAgent: step.agentId,
        toAgent: step.toAgent || 'ALL',
        type: step.type,
        content: step.content,
        status: step.action ? 'PENDING' : 'EXECUTED',
        tokensUsed: {
          input: step.tokensInput,
          output: step.tokensOutput,
        },
        latencyMs: step.delayMs,
        cost,
        requiresApproval: !!step.action,
      };

      this.emitMessage(message);

      // If step has action, emit it
      if (step.action) {
        const action: AgentAction = {
          id: crypto.randomUUID(),
          agentId: step.agentId,
          actionType: step.action.actionType,
          description: step.action.description,
          preview: step.action.preview,
          data: step.action.data,
          status: 'PENDING_APPROVAL',
          createdAt: new Date(),
        };

        this.emitAction(action);
      }

      this.currentDemoStep++;
    }

    this.isRunning = false;
  }

  // Stop running demo
  stopDemo(): void {
    this.isRunning = false;
  }

  // Reset orchestrator
  reset(): void {
    this.stopDemo();
    this.messages = [];
    this.actions = [];
    this.sessionStats = this.initializeStats();
    this.currentDemoStep = 0;
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Singleton instance
export const orchestrator = new AgentOrchestrator();

// Pre-built demo scenario: Intelligent Morning Dispatch
export const MORNING_DISPATCH_DEMO: DemoScenario = {
  id: 'morning-dispatch',
  name: 'The Intelligent Morning Dispatch',
  description: 'Multi-agent collaboration to resolve a scheduling conflict with parts verification',
  steps: [
    {
      agentId: 'ORCHESTRATOR',
      type: 'RESPONSE',
      content: '[INIT] Morning dispatch analysis initiated. Scanning open tickets and technician availability...',
      delayMs: 1000,
      tokensInput: 500,
      tokensOutput: 50,
    },
    {
      agentId: 'DISPATCH',
      type: 'THINKING',
      thinking: 'Analyzing 12 open tickets for today... Checking technician schedules... Found potential assignment for Ticket #1247 (HVAC repair at 123 Main St)',
      content: '[ANALYSIS] **Dispatch Analysis Complete**\n\nTicket #1247: Emergency HVAC Repair\n- Customer: Johnson Residence\n- Location: 123 Main St\n- Required Skills: HVAC Certified\n- Estimated Duration: 2 hours\n\n**Recommended:** Assign to Tech A (Scott) - closest proximity, certified, available 9am-11am slot.',
      toAgent: 'TECH_COPILOT',
      delayMs: 2000,
      tokensInput: 2500,
      tokensOutput: 180,
    },
    {
      agentId: 'TECH_COPILOT',
      type: 'THINKING',
      thinking: 'Receiving dispatch recommendation... Analyzing equipment history for Johnson Residence... Cross-referencing with common HVAC failure patterns...',
      content: '[DIAGNOSTIC] **Tech Co-Pilot Pre-Analysis**\n\nEquipment Profile: Carrier 24ACC636A003\n- Age: 8 years\n- Last Service: 2025-09-14\n- Common Failure: Compressor degradation\n\n**Pre-Diagnostic Signal:**\n- High probability (87%) compressor replacement needed\n- Required Part: Compressor Kit (CK-4500)\n- Recommend: Verify technician has CK-4500 on truck\n\n**Routing to Parts Agent for inventory verification.**',
      toAgent: 'PARTS',
      delayMs: 1500,
      tokensInput: 800,
      tokensOutput: 150,
    },
    {
      agentId: 'PARTS',
      type: 'QUERY',
      content: '[QUERY] Tech Co-Pilot flagged CK-4500 as likely required. Checking Tech A (Scott)\'s truck inventory...',
      delayMs: 800,
      tokensInput: 400,
      tokensOutput: 30,
    },
    {
      agentId: 'PARTS',
      type: 'THINKING',
      thinking: 'Querying vw_technician_truck_inventory for Scott... Required: Compressor Kit (P/N: CK-4500)... Checking stock levels...',
      content: '[ALERT] **Inventory Alert**\n\nTech A (Scott) is **MISSING** required part:\n- Part: Compressor Kit (CK-4500)\n- Required: 1\n- On Truck: 0\n- Nearest Stock: Main Warehouse (15 min detour)\n\n**Recommendation:** Check alternative technicians or route for pickup.',
      toAgent: 'DISPATCH',
      delayMs: 1500,
      tokensInput: 600,
      tokensOutput: 120,
    },
    {
      agentId: 'DISPATCH',
      type: 'THINKING',
      thinking: 'Parts conflict detected. Re-evaluating technician pool... Tech B (Mike) - checking certification and inventory...',
      content: '[REROUTE] **Re-routing Analysis**\n\nAlternative Found: Tech B (Mike)\n- Distance: 8 miles (vs Scott\'s 5 miles)\n- Has Compressor Kit: Yes (2 in stock)\n- HVAC Certified: Yes\n- Available: 9:30am-11:30am\n\n**Net Impact:** +15 min travel time, but eliminates warehouse detour (saves 30 min total)',
      toAgent: 'ARCHITECT',
      delayMs: 2000,
      tokensInput: 1800,
      tokensOutput: 150,
      action: {
        actionType: 'ASSIGN_TECH',
        description: 'Assign Tech B (Mike) to Ticket #1247',
        preview: 'This will:\n• Assign Mike to HVAC Repair at 123 Main St\n• Schedule for 9:30am - 11:30am\n• Reserve 1x Compressor Kit from Mike\'s truck',
        data: {
          ticketId: '1247',
          technicianId: 'tech-b-mike',
          scheduledStart: '2026-02-14T09:30:00',
          scheduledEnd: '2026-02-14T11:30:00',
          partsReserved: ['CK-4500'],
        },
      },
    },
    {
      agentId: 'CUSTOMER',
      type: 'RESPONSE',
      content: '[DRAFT] **Customer Notification**\n\nTo: Johnson Residence\nSubject: Technician En Route - HVAC Service\n\n"Good morning! Your HVAC technician Mike will arrive between 9:30-10:00 AM today. He\'s fully equipped to complete your repair. Reply STOP to cancel notifications."\n\n**Awaiting dispatch approval to send.**',
      toAgent: 'ARCHITECT',
      delayMs: 1200,
      tokensInput: 400,
      tokensOutput: 100,
      action: {
        actionType: 'SEND_MESSAGE',
        description: 'Send ETA notification to customer',
        preview: 'This will send an SMS to Johnson Residence with technician ETA',
        data: {
          customerId: 'johnson-residence',
          messageType: 'ETA_NOTIFICATION',
          channel: 'SMS',
        },
      },
    },
    {
      agentId: 'ORCHESTRATOR',
      type: 'RESPONSE',
      content: '[COMPLETE] **Morning Dispatch Summary**\n\n- Analyzed: 12 tickets\n- Conflicts Resolved: 1 (parts availability)\n- Optimizations: Saved 30 min by re-routing\n- Pending Approvals: 2 actions\n\n**Awaiting Architect approval to execute.**',
      delayMs: 1000,
      tokensInput: 300,
      tokensOutput: 80,
    },
  ],
};

export default orchestrator;
