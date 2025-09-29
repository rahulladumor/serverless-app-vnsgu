import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';

// Initialize AWS clients with latest v3 SDK
const dynamoClient = new DynamoDBClient({
  maxAttempts: 3,
  retryMode: 'adaptive'
});

const ddbDocClient = DynamoDBDocumentClient.from(dynamoClient, {
  marshallOptions: {
    removeUndefinedValues: true,
    convertClassInstanceToMap: true
  },
  unmarshallOptions: {
    wrapNumbers: false
  }
});

const TABLE_NAME = process.env.TABLE_NAME;

// Utility function for structured logging
function log(level, message, metadata = {}) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    level: level.toUpperCase(),
    message,
    ...metadata
  };
  console.log(JSON.stringify(logEntry));
}

// Order processing business logic
async function processOrderCreated(orderDetail) {
  const { id, customerName, items } = orderDetail;
  
  // Simulate order validation and processing logic
  log('info', 'Processing order created event', {
    orderId: id,
    customerName,
    itemCount: items?.length || 0
  });
  
  // Business rules for order confirmation
  let newStatus = 'CONFIRMED';
  let processingNotes = 'Order processed successfully';
  
  // Example: Check inventory (simulated)
  if (items && items.length > 10) {
    // Large orders need manual review
    newStatus = 'PENDING_REVIEW';
    processingNotes = 'Large order requires manual review';
    log('warn', 'Large order flagged for review', { orderId: id, itemCount: items.length });
  }
  
  // Example: Check customer credit (simulated)
  const totalValue = items?.reduce((sum, item) => sum + ((item.price || 0) * (item.qty || 0)), 0) || 0;
  if (totalValue > 10000) {
    newStatus = 'PENDING_APPROVAL';
    processingNotes = 'High-value order requires approval';
    log('warn', 'High-value order flagged for approval', { orderId: id, totalValue });
  }
  
  return { newStatus, processingNotes };
}

export const handler = async (event) => {
  const batchItemFailures = [];
  
  log('info', 'Starting order processor batch', {
    recordCount: event.Records?.length || 0,
    batchId: event.batchId || 'unknown'
  });
  
  for (const record of event.Records) {
    const messageId = record.messageId;
    let orderId = 'unknown';
    
    try {
      log('info', 'Processing SQS record', {
        messageId,
        receiptHandle: record.receiptHandle?.substring(0, 20) + '...'
      });
      
      // Parse message body
      let messageBody;
      try {
        messageBody = JSON.parse(record.body);
      } catch (parseError) {
        log('error', 'Failed to parse message body', {
          messageId,
          error: parseError.message,
          rawBody: record.body
        });
        // Don't retry parsing errors - send to DLQ
        batchItemFailures.push({ itemIdentifier: messageId });
        continue;
      }
      
      // Validate message structure
      if (!messageBody.type || !messageBody.detail) {
        log('error', 'Invalid message structure', {
          messageId,
          messageType: messageBody.type,
          hasDetail: !!messageBody.detail
        });
        // Don't retry structural errors - send to DLQ
        batchItemFailures.push({ itemIdentifier: messageId });
        continue;
      }
      
      // Process different message types
      if (messageBody.type === 'OrderCreated') {
        orderId = messageBody.detail?.id;
        
        if (!orderId) {
          log('error', 'Missing order ID in OrderCreated event', {
            messageId,
            detail: messageBody.detail
          });
          batchItemFailures.push({ itemIdentifier: messageId });
          continue;
        }
        
        log('info', 'Processing OrderCreated event', {
          messageId,
          orderId,
          customerName: messageBody.detail?.customerName
        });
        
        // Apply business logic for order processing
        const { newStatus, processingNotes } = await processOrderCreated(messageBody.detail);
        
        // Update order status in DynamoDB
        const updateParams = {
          TableName: TABLE_NAME,
          Key: { id: orderId },
          UpdateExpression: 'SET #status = :status, #updatedAt = :updatedAt, #processingNotes = :notes',
          ExpressionAttributeNames: {
            '#status': 'status',
            '#updatedAt': 'updatedAt',
            '#processingNotes': 'processingNotes'
          },
          ExpressionAttributeValues: {
            ':status': newStatus,
            ':updatedAt': new Date().toISOString(),
            ':notes': processingNotes
          },
          // Ensure order exists before updating
          ConditionExpression: 'attribute_exists(id)',
          ReturnValues: 'ALL_NEW'
        };
        
        const updateResult = await ddbDocClient.send(new UpdateCommand(updateParams));
        
        log('info', 'Order status updated successfully', {
          messageId,
          orderId,
          oldStatus: 'PENDING',
          newStatus,
          processingNotes,
          updatedAt: updateResult.Attributes?.updatedAt
        });
        
      } else {
        log('warn', 'Unknown message type received', {
          messageId,
          messageType: messageBody.type
        });
        // Unknown message types should not be retried
        batchItemFailures.push({ itemIdentifier: messageId });
      }
      
    } catch (error) {
      log('error', 'Failed to process SQS record', {
        messageId,
        orderId,
        error: error.message,
        errorCode: error.code,
        stack: error.stack
      });
      
      // Handle specific errors that shouldn't be retried
      if (error.code === 'ConditionalCheckFailedException') {
        log('warn', 'Order not found for update, message will be discarded', {
          messageId,
          orderId
        });
        // Don't retry if order doesn't exist
        batchItemFailures.push({ itemIdentifier: messageId });
      } else if (error.code === 'ValidationException') {
        log('warn', 'DynamoDB validation error, message will be discarded', {
          messageId,
          orderId,
          error: error.message
        });
        // Don't retry validation errors
        batchItemFailures.push({ itemIdentifier: messageId });
      } else {
        // Transient errors should be retried
        log('warn', 'Transient error, message will be retried', {
          messageId,
          orderId,
          error: error.message
        });
        batchItemFailures.push({ itemIdentifier: messageId });
      }
    }
  }
  
  const successCount = event.Records.length - batchItemFailures.length;
  const failureCount = batchItemFailures.length;
  
  log('info', 'Order processor batch completed', {
    totalRecords: event.Records.length,
    successCount,
    failureCount,
    batchItemFailures: batchItemFailures.map(f => f.itemIdentifier)
  });
  
  // Return partial batch failure information
  // SQS will only retry the failed messages
  return {
    batchItemFailures
  };
};
