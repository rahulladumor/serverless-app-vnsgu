import { v4 as uuid } from 'uuid';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';
import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';

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

const sqsClient = new SQSClient({
  maxAttempts: 3,
  retryMode: 'adaptive'
});

const TABLE_NAME = process.env.TABLE_NAME;
const QUEUE_URL = process.env.QUEUE_URL;

// Enhanced validation function
function validateOrderData(body) {
  const errors = [];
  
  if (!body) {
    errors.push('Request body is required');
    return { isValid: false, errors };
  }
  
  if (!body.customerName || typeof body.customerName !== 'string' || body.customerName.trim().length === 0) {
    errors.push('customerName is required and must be a non-empty string');
  }
  
  if (!Array.isArray(body.items) || body.items.length === 0) {
    errors.push('items must be a non-empty array');
  } else {
    body.items.forEach((item, index) => {
      if (!item.sku || typeof item.sku !== 'string') {
        errors.push(`Item ${index}: sku is required and must be a string`);
      }
      if (!item.qty || typeof item.qty !== 'number' || item.qty <= 0) {
        errors.push(`Item ${index}: qty is required and must be a positive number`);
      }
      if (item.price !== undefined && (typeof item.price !== 'number' || item.price < 0)) {
        errors.push(`Item ${index}: price must be a non-negative number`);
      }
    });
  }
  
  return {
    isValid: errors.length === 0,
    errors
  };
}

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

export const handler = async (event) => {
  const requestId = event.requestContext?.requestId || 'unknown';
  
  log('info', 'Processing create order request', {
    requestId,
    httpMethod: event.httpMethod,
    path: event.path
  });
  
  try {
    // Parse and validate request body
    let orderData;
    try {
      orderData = JSON.parse(event.body || '{}');
    } catch (parseError) {
      log('warn', 'Invalid JSON in request body', { requestId, error: parseError.message });
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Invalid JSON format',
          message: 'Request body must be valid JSON'
        })
      };
    }
    
    // Validate order data
    const validation = validateOrderData(orderData);
    if (!validation.isValid) {
      log('warn', 'Order validation failed', {
        requestId,
        errors: validation.errors,
        orderData: { ...orderData, items: orderData.items?.length || 0 }
      });
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Validation failed',
          message: validation.errors.join(', ')
        })
      };
    }
    
    // Generate order ID and create order object
    const orderId = uuid();
    const timestamp = new Date().toISOString();
    const order = {
      id: orderId,
      customerName: orderData.customerName.trim(),
      items: orderData.items.map(item => ({
        sku: item.sku,
        qty: item.qty,
        price: item.price || 0
      })),
      status: 'PENDING',
      createdAt: timestamp,
      updatedAt: timestamp
    };
    
    log('info', 'Creating order in database', {
      requestId,
      orderId,
      customerName: order.customerName,
      itemCount: order.items.length
    });
    
    // Store order in DynamoDB with conditional write
    await ddbDocClient.send(new PutCommand({
      TableName: TABLE_NAME,
      Item: order,
      ConditionExpression: 'attribute_not_exists(id)'
    }));
    
    log('info', 'Order created successfully in database', {
      requestId,
      orderId
    });
    
    // Send event to SQS for async processing
    const eventMessage = {
      type: 'OrderCreated',
      timestamp,
      detail: {
        id: orderId,
        customerName: order.customerName,
        items: order.items,
        createdAt: timestamp
      }
    };
    
    await sqsClient.send(new SendMessageCommand({
      QueueUrl: QUEUE_URL,
      MessageBody: JSON.stringify(eventMessage),
      MessageAttributes: {
        eventType: { DataType: 'String', StringValue: 'OrderCreated' },
        orderId: { DataType: 'String', StringValue: orderId },
        timestamp: { DataType: 'String', StringValue: timestamp }
      }
    }));
    
    log('info', 'Order event sent to queue successfully', {
      requestId,
      orderId,
      queueUrl: QUEUE_URL
    });
    
    // Return success response
    const response = {
      statusCode: 201,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: true,
        data: {
          id: orderId,
          status: 'PENDING',
          createdAt: timestamp
        },
        message: 'Order created successfully'
      })
    };
    
    log('info', 'Create order request completed successfully', {
      requestId,
      orderId,
      statusCode: response.statusCode
    });
    
    return response;
    
  } catch (error) {
    log('error', 'Unexpected error processing create order request', {
      requestId,
      error: error.message,
      stack: error.stack,
      errorCode: error.code
    });
    
    // Handle specific AWS errors
    if (error.code === 'ConditionalCheckFailedException') {
      return {
        statusCode: 409,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Conflict',
          message: 'Order with this ID already exists'
        })
      };
    }
    
    // Generic error response
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Internal Server Error',
        message: 'An unexpected error occurred while processing your request',
        requestId
      })
    };
  }
};
