import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';

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

// UUID validation function
function isValidUUID(uuid) {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

export const handler = async (event) => {
  const requestId = event.requestContext?.requestId || 'unknown';
  
  log('info', 'Processing get order request', {
    requestId,
    httpMethod: event.httpMethod,
    path: event.path
  });
  
  try {
    // Extract and validate order ID from path parameters
    const orderId = event.pathParameters?.id;
    
    if (!orderId) {
      log('warn', 'Missing order ID in path parameters', { requestId });
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Bad Request',
          message: 'Order ID is required in the URL path'
        })
      };
    }
    
    // Validate UUID format
    if (!isValidUUID(orderId)) {
      log('warn', 'Invalid UUID format for order ID', { requestId, orderId });
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Bad Request',
          message: 'Invalid order ID format. Must be a valid UUID.'
        })
      };
    }
    
    log('info', 'Retrieving order from database', {
      requestId,
      orderId
    });
    
    // Retrieve order from DynamoDB
    const result = await ddbDocClient.send(new GetCommand({
      TableName: TABLE_NAME,
      Key: { id: orderId },
      // Use consistent reads for the most up-to-date data
      ConsistentRead: true
    }));
    
    // Check if order exists
    if (!result.Item) {
      log('info', 'Order not found', { requestId, orderId });
      return {
        statusCode: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Not Found',
          message: `Order with ID ${orderId} was not found`
        })
      };
    }
    
    const order = result.Item;
    
    log('info', 'Order retrieved successfully', {
      requestId,
      orderId,
      orderStatus: order.status,
      customerName: order.customerName
    });
    
    // Calculate order total if prices are available
    let orderTotal = 0;
    if (order.items && Array.isArray(order.items)) {
      orderTotal = order.items.reduce((total, item) => {
        return total + ((item.price || 0) * (item.qty || 0));
      }, 0);
    }
    
    // Prepare response with additional computed fields
    const response = {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache' // Prevent caching of dynamic data
      },
      body: JSON.stringify({
        success: true,
        data: {
          ...order,
          itemCount: order.items?.length || 0,
          orderTotal: parseFloat(orderTotal.toFixed(2))
        }
      })
    };
    
    log('info', 'Get order request completed successfully', {
      requestId,
      orderId,
      statusCode: response.statusCode
    });
    
    return response;
    
  } catch (error) {
    log('error', 'Unexpected error processing get order request', {
      requestId,
      orderId: event.pathParameters?.id,
      error: error.message,
      stack: error.stack,
      errorCode: error.code
    });
    
    // Handle specific AWS errors
    if (error.code === 'ResourceNotFoundException') {
      return {
        statusCode: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Not Found',
          message: 'The requested resource was not found'
        })
      };
    }
    
    if (error.code === 'ProvisionedThroughputExceededException') {
      return {
        statusCode: 429,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Retry-After': '1'
        },
        body: JSON.stringify({
          error: 'Too Many Requests',
          message: 'Database is currently busy. Please try again in a moment.'
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
        message: 'An unexpected error occurred while retrieving the order',
        requestId
      })
    };
  }
};
