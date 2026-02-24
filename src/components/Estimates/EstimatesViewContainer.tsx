import { useState } from 'react';
import { EstimatesView } from './EstimatesView';
import { NewEstimateModal } from './NewEstimateModal';
import { EstimateDetailModal } from './EstimateDetailModal';
import { SendEstimateModal } from './SendEstimateModal';

export function EstimatesViewContainer() {
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showSendModal, setShowSendModal] = useState(false);
  const [selectedEstimateId, setSelectedEstimateId] = useState<string | null>(null);
  const [sendEstimateData, setSendEstimateData] = useState<{
    estimateId: string;
    estimateNumber: string;
    customerId: string;
    customerEmail: string | null;
    customerPhone: string | null;
  } | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const handleCreateEstimate = () => {
    setShowCreateModal(true);
  };

  const handleViewEstimate = (estimateId: string) => {
    setSelectedEstimateId(estimateId);
    setShowDetailModal(true);
  };

  const handleEstimateCreated = (estimateData: {
    estimateId: string;
    estimateNumber: string;
    customerId: string;
    customerEmail: string | null;
    customerPhone: string | null;
  }) => {
    setSendEstimateData(estimateData);
    setShowSendModal(true);
    setRefreshKey(prev => prev + 1);
  };

  const handleSuccess = () => {
    setRefreshKey(prev => prev + 1);
  };

  return (
    <>
      <EstimatesView
        key={refreshKey}
        onViewEstimate={handleViewEstimate}
        onCreateEstimate={handleCreateEstimate}
      />
      <NewEstimateModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSuccess={handleEstimateCreated}
      />
      <EstimateDetailModal
        estimateId={selectedEstimateId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedEstimateId(null);
        }}
        onSuccess={handleSuccess}
      />
      {sendEstimateData && (
        <SendEstimateModal
          isOpen={showSendModal}
          onClose={() => {
            setShowSendModal(false);
            setSendEstimateData(null);
          }}
          onSuccess={handleSuccess}
          estimateId={sendEstimateData.estimateId}
          estimateNumber={sendEstimateData.estimateNumber}
          customerId={sendEstimateData.customerId}
          customerEmail={sendEstimateData.customerEmail}
          customerPhone={sendEstimateData.customerPhone}
        />
      )}
    </>
  );
}
