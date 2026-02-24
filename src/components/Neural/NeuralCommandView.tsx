/**
 * Neural Command View - The War Room
 * LOCAL DEMO ONLY - DO NOT COMMIT
 *
 * Three-panel layout:
 * A: Swarm Feed - Inter-agent communication log
 * B: Intelligence Canvas - Visual simulation of dispatch operations
 * C: Approval Gate - Human approval panel
 */

import { useState, useEffect, useRef } from 'react';
import {
  Brain,
  Play,
  Square,
  RotateCcw,
  Zap,
  ToggleLeft,
  ToggleRight,
  Terminal,
  Cpu,
  Shield,
  Calendar,
  Package,
  MessageSquare,
  Wrench,
  CheckCircle,
  XCircle,
  Clock,
  DollarSign,
  BarChart3,
  User,
  Ticket,
  MapPin,
  Truck,
  ArrowRight,
  AlertTriangle,
  Mail,
} from 'lucide-react';
import { orchestrator, MORNING_DISPATCH_DEMO, LiveAnalysisResult } from '../../services/agents/AgentOrchestrator';
import { supabase } from '../../lib/supabase';
import { AgentMessage, AgentAction, SessionStats, AGENT_CONFIGS, AgentId } from '../../types/agents';
import { EquipmentIntelligence, CustomerSalesIntelligence, LatentSalesOpportunity } from '../../services/agents/LiveDataService';

// Agent icon mapping
const AgentIcon: Record<AgentId, React.ElementType> = {
  DISPATCH: Calendar,
  PARTS: Package,
  CUSTOMER: MessageSquare,
  TECH_COPILOT: Wrench,
  ORCHESTRATOR: Cpu,
};

// Agent color mapping - works in both light and dark mode
const AgentColor: Record<AgentId, string> = {
  DISPATCH: 'text-purple-600 dark:text-purple-400 bg-purple-100 dark:bg-purple-400/20',
  PARTS: 'text-green-600 dark:text-green-400 bg-green-100 dark:bg-green-400/20',
  CUSTOMER: 'text-amber-600 dark:text-amber-400 bg-amber-100 dark:bg-amber-400/20',
  TECH_COPILOT: 'text-blue-600 dark:text-blue-400 bg-blue-100 dark:bg-blue-400/20',
  ORCHESTRATOR: 'text-pink-600 dark:text-pink-400 bg-pink-100 dark:bg-pink-400/20',
};

// Agent text color for names
const AgentTextColor: Record<AgentId, string> = {
  DISPATCH: 'text-purple-600 dark:text-purple-400',
  PARTS: 'text-green-600 dark:text-green-400',
  CUSTOMER: 'text-amber-600 dark:text-amber-400',
  TECH_COPILOT: 'text-blue-600 dark:text-blue-400',
  ORCHESTRATOR: 'text-pink-600 dark:text-pink-400',
};

// Canvas state types
interface CanvasTicket {
  id: string;
  title: string;
  customer: string;
  location: string;
  status: 'unassigned' | 'pending' | 'assigned' | 'en-route';
  assignedTo: string | null;
  priority: 'emergency' | 'high' | 'normal';
}

interface CanvasTechnician {
  id: string;
  name: string;
  initials: string;
  status: 'available' | 'assigned' | 'en-route' | 'busy';
  hasPart: boolean;
  distance: string;
}

interface CustomerNotification {
  sent: boolean;
  message: string;
}

export default function NeuralCommandView() {
  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [pendingActions, setPendingActions] = useState<AgentAction[]>([]);
  const [stats, setStats] = useState<SessionStats>(orchestrator.getStats());
  const [isRunning, setIsRunning] = useState(false);
  const [isDemoMode, setIsDemoMode] = useState(true);
  const [isLiveMode, setIsLiveMode] = useState(false);
  const [liveAnalysis, setLiveAnalysis] = useState<LiveAnalysisResult | null>(null);
  const [activeTab, setActiveTab] = useState<'swarm' | 'insights'>('swarm');
  const feedRef = useRef<HTMLDivElement>(null);

  // Canvas simulation state
  const [ticket, setTicket] = useState<CanvasTicket>({
    id: '1247',
    title: 'Emergency HVAC Repair',
    customer: 'Johnson Residence',
    location: '123 Main St',
    status: 'unassigned',
    assignedTo: null,
    priority: 'emergency',
  });

  const [technicians, setTechnicians] = useState<CanvasTechnician[]>([
    { id: 'scott', name: 'Scott', initials: 'SA', status: 'available', hasPart: false, distance: '5 mi' },
    { id: 'mike', name: 'Mike', initials: 'MB', status: 'available', hasPart: true, distance: '8 mi' },
  ]);

  const [notification, setNotification] = useState<CustomerNotification>({
    sent: false,
    message: '',
  });

  const [canvasHighlight, setCanvasHighlight] = useState<string | null>(null);

  // Equipment intelligence state for Phase 2
  const [equipmentIntel, setEquipmentIntel] = useState<EquipmentIntelligence | null>(null);

  // Sales intelligence state for Phase 3
  const [salesIntel, setSalesIntel] = useState<CustomerSalesIntelligence | null>(null);

  // Latent opportunities state for Ticket Mining
  const [latentOpps, setLatentOpps] = useState<LatentSalesOpportunity[]>([]);

  useEffect(() => {
    // Subscribe to messages
    const unsubMessage = orchestrator.onMessage((msg) => {
      setMessages([...orchestrator.getMessages()]);
      setStats(orchestrator.getStats());

      // Update canvas based on message content
      if (msg.content.includes('[ANALYSIS]')) {
        setTicket(t => ({ ...t, status: 'pending' }));
        setCanvasHighlight('ticket');
        setTimeout(() => setCanvasHighlight(null), 2000);
      }
      if (msg.content.includes('[DIAGNOSTIC]')) {
        setCanvasHighlight('scott');
        setTimeout(() => {
          setCanvasHighlight('parts-alert');
          setTimeout(() => setCanvasHighlight(null), 2000);
        }, 1500);
      }
      if (msg.content.includes('[ALERT]')) {
        setTechnicians(techs => techs.map(t =>
          t.id === 'scott' ? { ...t, status: 'busy' } : t
        ));
        setCanvasHighlight('mike');
        setTimeout(() => setCanvasHighlight(null), 2000);
      }
      if (msg.content.includes('[REROUTE]')) {
        setCanvasHighlight('mike');
        setTimeout(() => setCanvasHighlight(null), 2000);
      }
      if (msg.content.includes('[DRAFT]')) {
        setNotification({ sent: false, message: 'Draft ready...' });
        setCanvasHighlight('notification');
        setTimeout(() => setCanvasHighlight(null), 2000);
      }
    });

    // Subscribe to actions
    const unsubAction = orchestrator.onAction(() => {
      setPendingActions([...orchestrator.getPendingActions()]);
    });

    return () => {
      unsubMessage();
      unsubAction();
    };
  }, []);

  // Auto-scroll feed
  useEffect(() => {
    if (feedRef.current) {
      feedRef.current.scrollTop = feedRef.current.scrollHeight;
    }
  }, [messages]);

  const handleStartDemo = async () => {
    // Reset canvas state
    setTicket({
      id: '1247',
      title: 'Emergency HVAC Repair',
      customer: 'Johnson Residence',
      location: '123 Main St',
      status: 'unassigned',
      assignedTo: null,
      priority: 'emergency',
    });
    setTechnicians([
      { id: 'scott', name: 'Scott', initials: 'SA', status: 'available', hasPart: false, distance: '5 mi' },
      { id: 'mike', name: 'Mike', initials: 'MB', status: 'available', hasPart: true, distance: '8 mi' },
    ]);
    setNotification({ sent: false, message: '' });
    setCanvasHighlight(null);
    setLiveAnalysis(null);

    setIsRunning(true);
    await orchestrator.runDemoScenario(MORNING_DISPATCH_DEMO);
    setIsRunning(false);
  };

  const handleStartLive = async () => {
    // Reset for live mode
    setTicket({
      id: 'LIVE',
      title: 'Scanning...',
      customer: 'Loading...',
      location: 'Querying database...',
      status: 'unassigned',
      assignedTo: null,
      priority: 'normal',
    });
    setTechnicians([]);
    setNotification({ sent: false, message: '' });
    setCanvasHighlight(null);
    setEquipmentIntel(null);
    setSalesIntel(null);
    setLatentOpps([]);

    setIsRunning(true);
    const result = await orchestrator.runLiveAnalysis();
    setIsRunning(false);

    if (result) {
      setLiveAnalysis(result);
      // Update canvas with live data
      if (result.selectedTicket) {
        setTicket({
          id: result.selectedTicket.ticketNumber,
          title: result.selectedTicket.title,
          customer: result.selectedTicket.customerName,
          location: `${result.selectedTicket.address || ''}, ${result.selectedTicket.city || ''}`,
          status: result.selectedTicket.assignedTo ? 'assigned' : 'unassigned',
          assignedTo: result.selectedTicket.assignedTo,
          priority: (result.selectedTicket.priority as 'emergency' | 'high' | 'normal') || 'normal',
        });
      } else {
        // No tickets - set to GLOBAL mode for revenue audit
        setTicket({
          id: 'GLOBAL',
          title: 'Global Revenue Audit',
          customer: 'All Customers',
          location: 'Business-wide scan',
          status: 'unassigned',
          assignedTo: null,
          priority: 'normal',
        });
      }
      // Update technicians with live data
      if (result.technicians.length > 0) {
        setTechnicians(result.technicians.slice(0, 4).map(t => ({
          id: t.id,
          name: t.name,
          initials: t.initials,
          status: t.id === result.recommendedTech ? 'available' : 'available',
          hasPart: t.hasPart,
          distance: `${t.inventory.length} parts`,
        })));
      }
      // Update equipment intelligence
      if (result.equipmentIntelligence) {
        setEquipmentIntel(result.equipmentIntelligence);
      }
      // Update sales intelligence
      if (result.salesIntelligence) {
        setSalesIntel(result.salesIntelligence);
      }
      // Update latent opportunities
      if (result.latentOpportunities) {
        setLatentOpps(result.latentOpportunities);
      }
    }
  };

  const handleStop = () => {
    orchestrator.stopDemo();
    setIsRunning(false);
  };

  const handleReset = () => {
    orchestrator.reset();
    setMessages([]);
    setPendingActions([]);
    setStats(orchestrator.getStats());
    // Reset canvas
    setTicket({
      id: '1247',
      title: 'Emergency HVAC Repair',
      customer: 'Johnson Residence',
      location: '123 Main St',
      status: 'unassigned',
      assignedTo: null,
      priority: 'emergency',
    });
    setTechnicians([
      { id: 'scott', name: 'Scott', initials: 'SA', status: 'available', hasPart: false, distance: '5 mi' },
      { id: 'mike', name: 'Mike', initials: 'MB', status: 'available', hasPart: true, distance: '8 mi' },
    ]);
    setNotification({ sent: false, message: '' });
    setCanvasHighlight(null);
    setEquipmentIntel(null);
    setSalesIntel(null);
    setLatentOpps([]);
    setLiveAnalysis(null);
  };

  const handleApprove = async (actionId: string) => {
    const action = pendingActions.find(a => a.id === actionId);

    if (action?.actionType === 'ASSIGN_TECH') {
      const ticketId = action.data.ticketId as string;
      const technicianId = action.data.technicianId as string;
      const technicianName = action.data.technicianName as string || 'Technician';

      // Write to Supabase
      const { error } = await supabase
        .from('tickets')
        .update({ assigned_to: technicianId })
        .eq('id', ticketId);

      if (error) {
        console.error('[Neural Command] Failed to assign ticket in DB:', error);
      } else {
        console.log(`[Neural Command] Ticket ${ticketId} assigned to ${technicianId} in database.`);
      }

      // Visual update on canvas
      setTicket(t => ({ ...t, status: 'assigned', assignedTo: technicianId }));
      setTechnicians(techs => techs.map(t =>
        t.id === technicianId ? { ...t, status: 'assigned' } : t
      ));
      setCanvasHighlight('assignment');
      setTimeout(() => {
        setTicket(t => ({ ...t, status: 'en-route' }));
        setTechnicians(techs => techs.map(t =>
          t.id === technicianId ? { ...t, status: 'en-route' } : t
        ));
        setCanvasHighlight(null);
      }, 1500);

      // Emit confirmation to swarm feed
      orchestrator.approveAction(actionId);
      setPendingActions([...orchestrator.getPendingActions()]);
      setMessages([...orchestrator.getMessages()]);
      return;
    }

    if (action?.actionType === 'SEND_MESSAGE') {
      setNotification({ sent: true, message: `SMS sent to ${action.data.customerName || 'customer'}` });
      setCanvasHighlight('notification-sent');
      setTimeout(() => setCanvasHighlight(null), 2000);
    }

    orchestrator.approveAction(actionId);
    setPendingActions([...orchestrator.getPendingActions()]);
    setMessages([...orchestrator.getMessages()]);
  };

  const handleReject = (actionId: string) => {
    const reason = prompt('Reason for rejection (optional):');
    orchestrator.rejectAction(actionId, reason || undefined);
    setPendingActions([...orchestrator.getPendingActions()]);
    setMessages([...orchestrator.getMessages()]);
  };

  const toggleDemoMode = () => {
    if (isDemoMode) {
      // Switch to live mode
      setIsDemoMode(false);
      setIsLiveMode(true);
      orchestrator.setLiveMode(true);
    } else {
      // Switch to demo mode
      setIsDemoMode(true);
      setIsLiveMode(false);
      orchestrator.setDemoMode(true);
    }
  };

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  };

  // Canvas Component
  const IntelligenceCanvas = () => (
    <div className="h-full flex flex-col">
      {/* Ticket Card / Global Mode Indicator */}
      <div className="mb-4">
        <h3 className="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">
          {ticket.id === 'GLOBAL' ? 'Operations Status' : 'Active Ticket'}
        </h3>
        {ticket.id === 'GLOBAL' ? (
          // Global Mode - No active tickets
          <div className="bg-gradient-to-br from-purple-50 to-blue-50 dark:from-purple-900/20 dark:to-blue-900/20 rounded-xl p-4 border-2 border-purple-300 dark:border-purple-500/50">
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                <Brain className="w-4 h-4 text-purple-500" />
                <span className="font-bold text-purple-700 dark:text-purple-400">GLOBAL MODE</span>
              </div>
              <span className="text-xs px-2 py-0.5 rounded-full font-semibold bg-purple-100 dark:bg-purple-900/30 text-purple-700 dark:text-purple-400">
                REVENUE AUDIT
              </span>
            </div>
            <p className="text-sm font-semibold text-gray-900 dark:text-white">No Active Service Tickets</p>
            <div className="flex items-center gap-1 mt-2 text-xs text-purple-600 dark:text-purple-400">
              <Zap className="w-3 h-3" />
              <span>Agents pivoting to revenue opportunities</span>
            </div>
            <div className="mt-3 pt-3 border-t border-purple-200 dark:border-purple-700">
              <div className="flex items-center gap-2">
                <DollarSign className="w-4 h-4 text-green-500" />
                <span className="text-sm font-semibold text-green-600 dark:text-green-400">
                  CRM Strike Active
                </span>
              </div>
            </div>
          </div>
        ) : (
          // Normal Ticket Mode
          <div className={`bg-white dark:bg-gray-700 rounded-xl p-4 border-2 transition-all duration-500 ${
            canvasHighlight === 'ticket' ? 'border-purple-500 shadow-lg shadow-purple-500/20' :
            canvasHighlight === 'assignment' ? 'border-green-500 shadow-lg shadow-green-500/20' :
            ticket.status === 'en-route' ? 'border-green-500' :
            ticket.status === 'assigned' ? 'border-blue-500' :
            'border-gray-200 dark:border-gray-600'
          }`}>
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                <Ticket className="w-4 h-4 text-red-500" />
                <span className="font-bold text-gray-900 dark:text-white">#{ticket.id}</span>
              </div>
              <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${
                ticket.status === 'en-route' ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400' :
                ticket.status === 'assigned' ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400' :
                ticket.status === 'pending' ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-400' :
                'bg-gray-100 dark:bg-gray-600 text-gray-700 dark:text-gray-300'
              }`}>
                {ticket.status.toUpperCase()}
              </span>
            </div>
            <p className="text-sm font-semibold text-gray-900 dark:text-white">{ticket.title}</p>
            <div className="flex items-center gap-1 mt-1 text-xs text-gray-500 dark:text-gray-400">
              <User className="w-3 h-3" />
              <span>{ticket.customer}</span>
            </div>
            <div className="flex items-center gap-1 mt-1 text-xs text-gray-500 dark:text-gray-400">
              <MapPin className="w-3 h-3" />
              <span>{ticket.location}</span>
            </div>
            {ticket.assignedTo && (
              <div className="flex items-center gap-2 mt-3 pt-3 border-t border-gray-200 dark:border-gray-600">
                <ArrowRight className="w-4 h-4 text-green-500" />
                <span className="text-sm font-semibold text-green-600 dark:text-green-400">
                  Assigned to {technicians.find(t => t.id === ticket.assignedTo)?.name}
                </span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Technicians */}
      <div className="mb-4">
        <h3 className="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">Technicians</h3>
        <div className="space-y-2">
          {technicians.map(tech => (
            <div key={tech.id} className={`bg-white dark:bg-gray-700 rounded-lg p-3 border-2 transition-all duration-500 ${
              canvasHighlight === tech.id ? 'border-blue-500 shadow-lg shadow-blue-500/20' :
              canvasHighlight === 'assignment' && tech.id === 'mike' ? 'border-green-500 shadow-lg shadow-green-500/20' :
              tech.status === 'en-route' ? 'border-green-500' :
              tech.status === 'assigned' ? 'border-blue-500' :
              tech.status === 'busy' ? 'border-red-300 dark:border-red-800' :
              'border-gray-200 dark:border-gray-600'
            }`}>
              <div className="flex items-center gap-3">
                <div className={`w-10 h-10 rounded-full flex items-center justify-center font-bold text-white ${
                  tech.status === 'en-route' ? 'bg-green-500' :
                  tech.status === 'assigned' ? 'bg-blue-500' :
                  tech.status === 'busy' ? 'bg-red-400' :
                  'bg-gray-400 dark:bg-gray-500'
                }`}>
                  {tech.initials}
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-gray-900 dark:text-white">{tech.name}</span>
                    <span className={`text-xs px-1.5 py-0.5 rounded ${
                      tech.status === 'en-route' ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400' :
                      tech.status === 'assigned' ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400' :
                      tech.status === 'busy' ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400' :
                      'bg-gray-100 dark:bg-gray-600 text-gray-600 dark:text-gray-300'
                    }`}>
                      {tech.status}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
                    <span className="flex items-center gap-1">
                      <Truck className="w-3 h-3" />
                      {tech.distance}
                    </span>
                    <span className={`flex items-center gap-1 ${tech.hasPart ? 'text-green-600 dark:text-green-400' : 'text-red-500'}`}>
                      <Package className="w-3 h-3" />
                      CK-4500: {tech.hasPart ? 'Yes' : 'No'}
                    </span>
                  </div>
                </div>
                {canvasHighlight === 'parts-alert' && tech.id === 'scott' && (
                  <AlertTriangle className="w-5 h-5 text-red-500 animate-pulse" />
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Equipment Intelligence - Phase 2 */}
      {equipmentIntel && (
        <div className="mb-4">
          <h3 className="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">Equipment Intelligence</h3>
          <div className={`bg-white dark:bg-gray-700 rounded-xl p-3 border-2 transition-all duration-500 ${
            equipmentIntel.isChronic
              ? 'border-red-500 shadow-lg shadow-red-500/20'
              : 'border-gray-200 dark:border-gray-600'
          }`}>
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                <Wrench className="w-4 h-4 text-blue-500" />
                <span className="font-semibold text-gray-900 dark:text-white text-sm">
                  {equipmentIntel.equipment.equipmentType}
                </span>
              </div>
              {equipmentIntel.isChronic && (
                <span className="text-xs px-2 py-0.5 rounded-full font-bold bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400 animate-pulse">
                  CHRONIC
                </span>
              )}
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400 space-y-1">
              <div className="flex justify-between">
                <span>Model:</span>
                <span className="text-gray-900 dark:text-white">{equipmentIntel.equipment.modelNumber || 'N/A'}</span>
              </div>
              <div className="flex justify-between">
                <span>Age:</span>
                <span className="text-gray-900 dark:text-white">{equipmentIntel.ageYears} years</span>
              </div>
              <div className="flex justify-between">
                <span>Service Calls (12mo):</span>
                <span className={equipmentIntel.serviceCallsLast12Months >= 3 ? 'text-red-600 dark:text-red-400 font-bold' : 'text-gray-900 dark:text-white'}>
                  {equipmentIntel.serviceCallsLast12Months}
                </span>
              </div>
              <div className="flex justify-between">
                <span>Warranty:</span>
                <span className={equipmentIntel.warrantyStatus === 'expired' ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400'}>
                  {equipmentIntel.warrantyStatus.toUpperCase()}
                </span>
              </div>
            </div>
            {equipmentIntel.isChronic && (
              <div className="mt-2 pt-2 border-t border-red-200 dark:border-red-800">
                <div className="flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 text-red-500" />
                  <span className="text-xs font-semibold text-red-600 dark:text-red-400">
                    Recommend: {equipmentIntel.recommendedAction.toUpperCase()} ({equipmentIntel.confidenceScore}%)
                  </span>
                </div>
                <p className="text-xs text-red-500 dark:text-red-400 mt-1">
                  {equipmentIntel.chronicReason}
                </p>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Sales Intelligence - Phase 3 */}
      {salesIntel && (
        <div className="mb-4">
          <h3 className="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">Sales Intelligence</h3>
          <div className={`bg-white dark:bg-gray-700 rounded-xl p-3 border-2 transition-all duration-500 ${
            salesIntel.hasUpsellOpportunity
              ? 'border-green-500 shadow-lg shadow-green-500/20'
              : 'border-gray-200 dark:border-gray-600'
          }`}>
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                <DollarSign className="w-4 h-4 text-green-500" />
                <span className="font-semibold text-gray-900 dark:text-white text-sm">
                  Pipeline Status
                </span>
              </div>
              {salesIntel.hasUpsellOpportunity && (
                <span className="text-xs px-2 py-0.5 rounded-full font-bold bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 animate-pulse">
                  OPPORTUNITY
                </span>
              )}
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400 space-y-1">
              <div className="flex justify-between">
                <span>Customer:</span>
                <span className="text-gray-900 dark:text-white">{salesIntel.customerName}</span>
              </div>
              <div className="flex justify-between">
                <span>Open Estimates:</span>
                <span className="text-gray-900 dark:text-white">{salesIntel.openEstimates.length}</span>
              </div>
              <div className="flex justify-between">
                <span>Pipeline Value:</span>
                <span className="text-green-600 dark:text-green-400 font-bold">
                  ${salesIntel.totalPipelineValue.toLocaleString()}
                </span>
              </div>
              {salesIntel.openEstimates.length > 0 && (
                <div className="flex justify-between">
                  <span>Highest Probability:</span>
                  <span className="text-gray-900 dark:text-white">{salesIntel.highestProbability}%</span>
                </div>
              )}
            </div>
            {salesIntel.hasUpsellOpportunity && salesIntel.openEstimates[0] && (
              <div className="mt-2 pt-2 border-t border-green-200 dark:border-green-800">
                <div className="flex items-center gap-2 mb-1">
                  <Zap className="w-4 h-4 text-green-500" />
                  <span className="text-xs font-semibold text-green-600 dark:text-green-400">
                    High-Value Consolidation
                  </span>
                </div>
                <div className="text-xs text-gray-600 dark:text-gray-300 space-y-1">
                  <p className="font-medium">Est #{salesIntel.openEstimates[0].estimateNumber}</p>
                  <p>{salesIntel.openEstimates[0].title}</p>
                  <p className="text-green-600 dark:text-green-400 font-bold">
                    ${salesIntel.openEstimates[0].totalAmount.toLocaleString()}
                  </p>
                </div>
                <p className="text-xs text-green-500 dark:text-green-400 mt-1 italic">
                  {salesIntel.upsellReason}
                </p>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Latent Opportunities - Ticket Mining */}
      {latentOpps.length > 0 && (
        <div className="mb-4">
          <h3 className="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">Pending Conversions</h3>
          <div className="bg-gradient-to-r from-amber-50 to-orange-50 dark:from-amber-900/20 dark:to-orange-900/20 rounded-xl p-3 border-2 border-amber-300 dark:border-amber-500/50">
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                <Ticket className="w-4 h-4 text-amber-600 dark:text-amber-400" />
                <span className="font-semibold text-gray-900 dark:text-white text-sm">
                  Ticket Mining
                </span>
              </div>
              <span className="text-xs px-2 py-0.5 rounded-full font-bold bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400">
                {latentOpps.length} FOUND
              </span>
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400 space-y-2">
              {latentOpps.slice(0, 3).map((opp, i) => (
                <div key={opp.ticketId} className="bg-white dark:bg-gray-700 rounded-lg p-2 border border-amber-200 dark:border-amber-700">
                  <div className="flex justify-between items-start mb-1">
                    <span className="font-medium text-gray-900 dark:text-white">#{opp.ticketNumber}</span>
                    <span className={`text-xs px-1.5 py-0.5 rounded ${
                      opp.conversionPriority === 'high'
                        ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400'
                        : opp.conversionPriority === 'medium'
                        ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-400'
                        : 'bg-gray-100 dark:bg-gray-600 text-gray-600 dark:text-gray-300'
                    }`}>
                      {opp.conversionPriority.toUpperCase()}
                    </span>
                  </div>
                  <p className="text-gray-700 dark:text-gray-300 truncate">{opp.customerName}</p>
                  <p className="text-gray-500 dark:text-gray-400 text-xs truncate">{opp.reason}</p>
                  <div className="flex justify-between mt-1">
                    <span className="text-amber-600 dark:text-amber-400 font-bold">${opp.estimatedValue.toLocaleString()}</span>
                    <span className="text-gray-400">{opp.daysSinceCompletion}d ago</span>
                  </div>
                </div>
              ))}
            </div>
            <div className="mt-2 pt-2 border-t border-amber-200 dark:border-amber-700 text-xs">
              <span className="text-amber-600 dark:text-amber-400 font-medium">
                Total Latent Value: ${latentOpps.reduce((sum, o) => sum + o.estimatedValue, 0).toLocaleString()}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Customer Notification */}
      <div>
        <h3 className="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">Customer Notification</h3>
        <div className={`bg-white dark:bg-gray-700 rounded-lg p-3 border-2 transition-all duration-500 ${
          canvasHighlight === 'notification' ? 'border-amber-500 shadow-lg shadow-amber-500/20' :
          canvasHighlight === 'notification-sent' ? 'border-green-500 shadow-lg shadow-green-500/20' :
          notification.sent ? 'border-green-500' :
          'border-gray-200 dark:border-gray-600'
        }`}>
          <div className="flex items-center gap-2">
            <Mail className={`w-5 h-5 ${notification.sent ? 'text-green-500' : 'text-gray-400'}`} />
            <span className={`text-sm ${notification.sent ? 'text-green-600 dark:text-green-400 font-semibold' : 'text-gray-500 dark:text-gray-400'}`}>
              {notification.sent ? notification.message : notification.message || 'No notification queued'}
            </span>
            {notification.sent && <CheckCircle className="w-4 h-4 text-green-500 ml-auto" />}
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <div className="font-sans">
      <div className="max-w-[1800px] mx-auto">
        {/* Header */}
        <header className="mb-6 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="bg-purple-600 p-3 rounded-xl">
              <Brain className="w-8 h-8 text-white" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Neural Command</h1>
              <p className="text-xs text-purple-600 dark:text-purple-400 uppercase tracking-widest">Multi-Agent Orchestration Hub</p>
            </div>
          </div>

          {/* Controls */}
          <div className="flex items-center gap-4">
            {/* Mode Toggle */}
            <button
              onClick={toggleDemoMode}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors border ${
                isDemoMode
                  ? 'bg-purple-100 dark:bg-purple-500/20 text-purple-700 dark:text-purple-400 border-purple-300 dark:border-purple-500/50'
                  : 'bg-green-100 dark:bg-green-500/20 text-green-700 dark:text-green-400 border-green-300 dark:border-green-500/50'
              }`}
            >
              {isDemoMode ? <ToggleLeft className="w-5 h-5" /> : <ToggleRight className="w-5 h-5" />}
              <span className="text-sm font-semibold">{isDemoMode ? 'DEMO' : 'LIVE'}</span>
              <Zap className={`w-4 h-4 ${isLiveMode ? 'text-green-500 animate-pulse' : 'text-gray-400'}`} />
            </button>

            {/* Action Buttons */}
            {!isRunning ? (
              <button
                onClick={isLiveMode ? handleStartLive : handleStartDemo}
                className={`flex items-center gap-2 px-5 py-2 text-white rounded-lg transition-colors font-semibold ${
                  isLiveMode
                    ? 'bg-green-600 hover:bg-green-700'
                    : 'bg-purple-600 hover:bg-purple-700'
                }`}
              >
                <Play className="w-4 h-4" />
                <span>{isLiveMode ? 'Run Live Analysis' : 'Run Demo'}</span>
              </button>
            ) : (
              <button
                onClick={handleStop}
                className="flex items-center gap-2 px-5 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors font-semibold"
              >
                <Square className="w-4 h-4" />
                <span>Stop</span>
              </button>
            )}

            <button
              onClick={handleReset}
              className="flex items-center gap-2 px-4 py-2 bg-gray-200 dark:bg-gray-700 hover:bg-gray-300 dark:hover:bg-gray-600 text-gray-700 dark:text-white rounded-lg transition-colors"
            >
              <RotateCcw className="w-4 h-4" />
              <span>Reset</span>
            </button>
          </div>
        </header>

        {/* Stats Bar */}
        <div className="mb-6 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-4 flex items-center gap-8">
          <div className="flex items-center gap-2">
            <Zap className="w-4 h-4 text-yellow-500 dark:text-yellow-400" />
            <span className="text-gray-500 dark:text-gray-400 text-sm">Messages:</span>
            <span className="text-gray-900 dark:text-white font-mono font-bold">{stats.totalMessages}</span>
          </div>
          <div className="flex items-center gap-2">
            <Terminal className="w-4 h-4 text-blue-500 dark:text-blue-400" />
            <span className="text-gray-500 dark:text-gray-400 text-sm">Tokens:</span>
            <span className="text-blue-600 dark:text-blue-400 font-mono">{stats.totalTokensInput.toLocaleString()} in</span>
            <span className="text-gray-400 dark:text-gray-600">/</span>
            <span className="text-green-600 dark:text-green-400 font-mono">{stats.totalTokensOutput.toLocaleString()} out</span>
          </div>
          <div className="flex items-center gap-2">
            <DollarSign className="w-4 h-4 text-amber-500 dark:text-amber-400" />
            <span className="text-gray-500 dark:text-gray-400 text-sm">Session Cost:</span>
            <span className="text-amber-600 dark:text-amber-400 font-mono font-bold">${stats.totalCost.toFixed(4)}</span>
          </div>
          <div className="flex items-center gap-2">
            <Clock className="w-4 h-4 text-gray-500 dark:text-gray-400" />
            <span className="text-gray-500 dark:text-gray-400 text-sm">Pending:</span>
            <span className={`font-mono font-bold ${pendingActions.length > 0 ? 'text-orange-600 dark:text-orange-400' : 'text-gray-400 dark:text-gray-500'}`}>
              {pendingActions.length} actions
            </span>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="mb-4 flex gap-2">
          <button
            onClick={() => setActiveTab('swarm')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${
              activeTab === 'swarm'
                ? 'bg-purple-600 text-white'
                : 'bg-gray-200 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
            }`}
          >
            Command Center
          </button>
          <button
            onClick={() => setActiveTab('insights')}
            className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${
              activeTab === 'insights'
                ? 'bg-purple-600 text-white'
                : 'bg-gray-200 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'
            }`}
          >
            <BarChart3 className="w-4 h-4 inline mr-2" />
            Neural Insights
          </button>
        </div>

        {activeTab === 'swarm' ? (
          <div className="grid grid-cols-12 gap-4" style={{ height: 'calc(100vh - 380px)' }}>
            {/* Module A: Swarm Feed */}
            <div className="col-span-5 bg-white dark:bg-gray-800 rounded-2xl border border-gray-200 dark:border-gray-700 flex flex-col overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between bg-gray-50 dark:bg-gray-800/50">
                <h2 className="text-xs font-bold text-purple-600 dark:text-purple-400 uppercase tracking-widest flex items-center gap-2">
                  <Terminal className="w-4 h-4" />
                  Swarm Feed
                </h2>
                <span className="text-xs text-gray-500 dark:text-gray-500">{messages.length} messages</span>
              </div>
              <div ref={feedRef} className="flex-1 p-3 space-y-2 overflow-auto bg-gray-50 dark:bg-gray-900">
                {messages.length === 0 ? (
                  <div className="flex flex-col items-center justify-center h-full text-gray-500 dark:text-gray-500">
                    <Brain className="w-12 h-12 mb-3 opacity-30" />
                    <p className="text-sm">Awaiting neural activity...</p>
                    <p className="text-xs mt-1">Click "Run Demo" to begin</p>
                  </div>
                ) : (
                  messages.map((msg) => {
                    const Icon = AgentIcon[msg.fromAgent];
                    const colorClass = AgentColor[msg.fromAgent];
                    const textColorClass = AgentTextColor[msg.fromAgent];
                    const config = AGENT_CONFIGS[msg.fromAgent];

                    return (
                      <div
                        key={msg.id}
                        className={`rounded-lg p-2 ${
                          msg.type === 'THINKING'
                            ? 'bg-gray-100 dark:bg-gray-700/50 border border-gray-300 dark:border-gray-600 border-dashed'
                            : 'bg-white dark:bg-gray-700/80 border border-gray-200 dark:border-gray-600'
                        }`}
                      >
                        <div className="flex items-start gap-2">
                          <div className={`p-1.5 rounded-lg ${colorClass}`}>
                            <Icon className="w-3 h-3" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-0.5">
                              <span className={`text-xs font-bold ${textColorClass}`}>
                                {config.name}
                              </span>
                              {msg.type === 'THINKING' && (
                                <span className="text-xs text-gray-500 dark:text-gray-500 italic">thinking...</span>
                              )}
                              <span className="text-xs text-gray-500 dark:text-gray-500 ml-auto">
                                {formatTime(new Date(msg.timestamp))}
                              </span>
                            </div>
                            <div className="text-xs text-gray-700 dark:text-gray-300 whitespace-pre-wrap leading-relaxed">
                              {msg.content}
                            </div>
                            {msg.tokensUsed && (
                              <div className="flex items-center gap-2 mt-1 text-xs text-gray-500 dark:text-gray-500">
                                <span>{msg.tokensUsed.input + msg.tokensUsed.output} tok</span>
                                <span>${msg.cost?.toFixed(4)}</span>
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </div>

            {/* Module B: Intelligence Canvas */}
            <div className="col-span-4 bg-white dark:bg-gray-800 rounded-2xl border border-gray-200 dark:border-gray-700 flex flex-col overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between bg-gray-50 dark:bg-gray-800/50">
                <h2 className="text-xs font-bold text-blue-600 dark:text-blue-400 uppercase tracking-widest flex items-center gap-2">
                  <Brain className="w-4 h-4" />
                  Intelligence Canvas
                </h2>
              </div>
              <div className="flex-1 p-4 overflow-auto bg-gray-50 dark:bg-gray-900">
                <IntelligenceCanvas />
              </div>
            </div>

            {/* Module C: Approval Gate */}
            <div className="col-span-3 bg-white dark:bg-gray-800 rounded-2xl border border-gray-200 dark:border-gray-700 flex flex-col overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between bg-gray-50 dark:bg-gray-800/50">
                <h2 className="text-xs font-bold text-red-600 dark:text-red-400 uppercase tracking-widest flex items-center gap-2">
                  <Shield className="w-4 h-4" />
                  Approval Gate
                </h2>
                {pendingActions.length > 0 && (
                  <span className="bg-orange-500 text-white text-xs px-2 py-0.5 rounded-full font-bold">
                    {pendingActions.length}
                  </span>
                )}
              </div>
              <div className="flex-1 p-3 overflow-auto bg-gray-50 dark:bg-gray-900">
                {pendingActions.length === 0 ? (
                  <div className="flex flex-col items-center justify-center h-full text-gray-500 dark:text-gray-500">
                    <Shield className="w-10 h-10 mb-2 opacity-30" />
                    <p className="text-sm">No pending actions</p>
                    <p className="text-xs mt-1">Agent actions appear here</p>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {pendingActions.map((action) => {
                      const Icon = AgentIcon[action.agentId];
                      const colorClass = AgentColor[action.agentId];

                      return (
                        <div key={action.id} className="bg-white dark:bg-gray-700 rounded-xl p-3 border border-orange-300 dark:border-orange-500/30">
                          <div className="flex items-center gap-2 mb-2">
                            <div className={`p-1 rounded ${colorClass}`}>
                              <Icon className="w-3 h-3" />
                            </div>
                            <span className="text-xs font-bold text-orange-600 dark:text-orange-400 uppercase">
                              Requires Approval
                            </span>
                          </div>
                          <p className="text-sm text-gray-900 dark:text-white font-semibold mb-2">{action.description}</p>
                          <div className="bg-gray-100 dark:bg-gray-800 rounded-lg p-2 mb-2 text-xs text-gray-600 dark:text-gray-400 whitespace-pre-wrap">
                            {action.preview}
                          </div>
                          <div className="flex gap-2">
                            <button
                              onClick={() => handleApprove(action.id)}
                              className="flex-1 flex items-center justify-center gap-1 px-2 py-1.5 bg-green-600 hover:bg-green-700 text-white rounded-lg text-xs font-semibold transition-colors"
                            >
                              <CheckCircle className="w-3 h-3" />
                              Approve
                            </button>
                            <button
                              onClick={() => handleReject(action.id)}
                              className="flex-1 flex items-center justify-center gap-1 px-2 py-1.5 bg-red-600 hover:bg-red-700 text-white rounded-lg text-xs font-semibold transition-colors"
                            >
                              <XCircle className="w-3 h-3" />
                              Reject
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>
          </div>
        ) : (
          /* Neural Insights Tab */
          <div className="bg-white dark:bg-gray-800 rounded-2xl border border-gray-200 dark:border-gray-700 p-6" style={{ height: 'calc(100vh - 380px)' }}>
            <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-6">Agent Performance Breakdown</h2>
            <div className="grid grid-cols-5 gap-4">
              {Object.entries(stats.agentBreakdown).map(([agentId, agentStats]) => {
                const config = AGENT_CONFIGS[agentId as AgentId];
                const Icon = AgentIcon[agentId as AgentId];
                const colorClass = AgentColor[agentId as AgentId];

                return (
                  <div key={agentId} className="bg-gray-50 dark:bg-gray-700 rounded-xl p-4 border border-gray-200 dark:border-gray-600">
                    <div className="flex items-center gap-3 mb-4">
                      <div className={`p-2 rounded-lg ${colorClass}`}>
                        <Icon className="w-5 h-5" />
                      </div>
                      <div>
                        <p className="text-sm font-bold text-gray-900 dark:text-white">{config.name}</p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">{config.model}</p>
                      </div>
                    </div>
                    <div className="space-y-2 text-sm">
                      <div className="flex justify-between">
                        <span className="text-gray-500 dark:text-gray-400">Messages</span>
                        <span className="text-gray-900 dark:text-white font-mono">{agentStats?.messages || 0}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-500 dark:text-gray-400">Tokens</span>
                        <span className="text-gray-900 dark:text-white font-mono">
                          {((agentStats?.tokensInput || 0) + (agentStats?.tokensOutput || 0)).toLocaleString()}
                        </span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-500 dark:text-gray-400">Cost</span>
                        <span className="text-amber-600 dark:text-amber-400 font-mono">${(agentStats?.cost || 0).toFixed(4)}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-500 dark:text-gray-400">Avg Latency</span>
                        <span className="text-gray-900 dark:text-white font-mono">{Math.round(agentStats?.avgLatencyMs || 0)}ms</span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
