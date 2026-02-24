/**
 * Agent Type Definitions
 * LOCAL DEMO ONLY - DO NOT COMMIT
 */

export type AgentId = 'DISPATCH' | 'PARTS' | 'CUSTOMER' | 'TECH_COPILOT' | 'ORCHESTRATOR';

export type AgentModel = 'claude-sonnet' | 'claude-haiku' | 'gemini-flash' | 'gemini-pro';

export type MessageType = 'QUERY' | 'RESPONSE' | 'ACTION' | 'APPROVAL_REQUEST' | 'THINKING' | 'HANDOFF';

export type MessageStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'EXECUTED' | 'THINKING';

export interface AgentConfig {
  id: AgentId;
  name: string;
  model: AgentModel;
  description: string;
  color: string;
  icon: string;
  costPerInputToken: number;  // per 1M tokens
  costPerOutputToken: number; // per 1M tokens
}

export interface AgentMessage {
  id: string;
  timestamp: Date;
  fromAgent: AgentId;
  toAgent: AgentId | 'ARCHITECT' | 'ALL';
  type: MessageType;
  content: string;
  thinking?: string;
  data?: Record<string, unknown>;
  requiresApproval?: boolean;
  status: MessageStatus;
  tokensUsed?: {
    input: number;
    output: number;
  };
  latencyMs?: number;
  cost?: number;
}

export interface AgentAction {
  id: string;
  agentId: AgentId;
  actionType: 'ASSIGN_TECH' | 'CREATE_PO' | 'SEND_MESSAGE' | 'UPDATE_TICKET' | 'ALERT';
  description: string;
  preview: string;
  data: Record<string, unknown>;
  status: 'PENDING_APPROVAL' | 'APPROVED' | 'REJECTED' | 'EXECUTED';
  createdAt: Date;
  executedAt?: Date;
}

export interface SessionStats {
  totalMessages: number;
  totalTokensInput: number;
  totalTokensOutput: number;
  totalCost: number;
  agentBreakdown: {
    [key in AgentId]?: {
      messages: number;
      tokensInput: number;
      tokensOutput: number;
      cost: number;
      avgLatencyMs: number;
    };
  };
  startTime: Date;
  lastActivity: Date;
}

// Agent configurations
export const AGENT_CONFIGS: Record<AgentId, AgentConfig> = {
  DISPATCH: {
    id: 'DISPATCH',
    name: 'Dispatch Agent',
    model: 'claude-sonnet',
    description: 'Schedule optimization, conflict resolution, technician assignment',
    color: '#8B5CF6', // Purple
    icon: 'Calendar',
    costPerInputToken: 3.00,
    costPerOutputToken: 15.00,
  },
  PARTS: {
    id: 'PARTS',
    name: 'Parts Agent',
    model: 'gemini-flash',
    description: 'Inventory checks, reorder alerts, truck stock verification',
    color: '#10B981', // Green
    icon: 'Package',
    costPerInputToken: 0.075,
    costPerOutputToken: 0.30,
  },
  CUSTOMER: {
    id: 'CUSTOMER',
    name: 'Customer Agent',
    model: 'gemini-flash',
    description: 'ETA notifications, appointment confirmations, follow-ups',
    color: '#F59E0B', // Amber
    icon: 'MessageSquare',
    costPerInputToken: 0.075,
    costPerOutputToken: 0.30,
  },
  TECH_COPILOT: {
    id: 'TECH_COPILOT',
    name: 'Tech Co-Pilot',
    model: 'claude-haiku',
    description: 'Diagnostics, repair procedures, parts lookup, documentation',
    color: '#3B82F6', // Blue
    icon: 'Wrench',
    costPerInputToken: 0.80,
    costPerOutputToken: 4.00,
  },
  ORCHESTRATOR: {
    id: 'ORCHESTRATOR',
    name: 'Orchestrator',
    model: 'claude-sonnet',
    description: 'Agent coordination, routing, sequencing',
    color: '#EC4899', // Pink
    icon: 'Cpu',
    costPerInputToken: 3.00,
    costPerOutputToken: 15.00,
  },
};

// Calculate cost from tokens
export function calculateCost(agentId: AgentId, inputTokens: number, outputTokens: number): number {
  const config = AGENT_CONFIGS[agentId];
  const inputCost = (inputTokens / 1_000_000) * config.costPerInputToken;
  const outputCost = (outputTokens / 1_000_000) * config.costPerOutputToken;
  return inputCost + outputCost;
}

// Demo mode scenarios
export interface DemoScenario {
  id: string;
  name: string;
  description: string;
  steps: DemoStep[];
}

export interface DemoStep {
  agentId: AgentId;
  type: MessageType;
  content: string;
  thinking?: string;
  toAgent?: AgentId | 'ARCHITECT';
  delayMs: number;
  tokensInput: number;
  tokensOutput: number;
  action?: Omit<AgentAction, 'id' | 'createdAt' | 'status'>;
}
