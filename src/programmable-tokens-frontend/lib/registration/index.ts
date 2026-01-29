/**
 * Registration Module
 * Exports flow registry and initializes flows
 */

// Export registry functions
export {
  registerFlow,
  getFlow,
  getAllFlows,
  getFlowIds,
  hasFlow,
  clearFlows,
  isFlowEnabled,
} from './flow-registry';

// Import and register flows
// These imports trigger the flow registration via side effects
import './flows/dummy-flow.tsx';
import './flows/freeze-and-seize-flow.tsx';
