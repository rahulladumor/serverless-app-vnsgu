import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';

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

// Parse query parameters for filtering and pagination
function parseQueryParameters(queryStringParameters) {
  const params = {
    limit: 10, // Default limit
    status: null,
    sortOrder: 'desc', // Default to newest first
    lastEvaluatedKey: null
  };

  if (queryStringParameters) {
    // Parse limit
    if (queryStringParameters.limit) {
      const limit = parseInt(queryStringParameters.limit, 10);
      if (limit > 0 && limit <= 100) {
        params.limit = limit;
      }
    }

    // Parse status filter
    if (queryStringParameters.status && 
        ['PENDING', 'CONFIRMED', 'PENDING_REVIEW', 'PENDING_APPROVAL', 'CANCELLED'].includes(queryStringParameters.status)) {
      params.status = queryStringParameters.status;
    }

    // Parse sort order
    if (queryStringParameters.sortOrder && 
        ['asc', 'desc'].includes(queryStringParameters.sortOrder.toLowerCase())) {
      params.sortOrder = queryStringParameters.sortOrder.toLowerCase();
    }

    // Parse pagination token
    if (queryStringParameters.nextToken) {
      try {
        params.lastEvaluatedKey = JSON.parse(Buffer.from(queryStringParameters.nextToken, 'base64').toString());
      } catch (error) {
        log('warn', 'Invalid pagination token provided', { token: queryStringParameters.nextToken });
      }
    }
  }

  return params;
}

export const handler = async (event) => {
  const requestId = event.requestContext?.requestId || 'unknown';
  
  log('info', 'Processing list orders request', {
    requestId,
    httpMethod: event.httpMethod,
    path: event.path,
    queryParams: event.queryStringParameters
  });
  
  try {
    // Parse query parameters
    const queryParams = parseQueryParameters(event.queryStringParameters);
    log('info', 'Listing orders with parameters', {
      requestId,
      ...queryParams
    });
    
    let result;
    
    // Use GSI for status-based queries, otherwise scan all
    if (queryParams.status) {
      // Use the StatusIndex GSI for efficient status-based queries
      const queryParams_db = {
        TableName: TABLE_NAME,
        IndexName: 'StatusIndex',
        KeyConditionExpression: '#status = :status',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':status': queryParams.status
        },
        Limit: queryParams.limit,
        ScanIndexForward: queryParams.sortOrder === 'asc'
      };

      // Add pagination for GSI query
      if (queryParams.lastEvaluatedKey) {
        queryParams_db.ExclusiveStartKey = queryParams.lastEvaluatedKey;
      }

      result = await ddbDocClient.send(new QueryCommand(queryParams_db));
    } else {
      // Fallback to scan for all orders
      const scanParams = {
        TableName: TABLE_NAME,
        Limit: queryParams.limit
      };

      // Add pagination
      if (queryParams.lastEvaluatedKey) {
        scanParams.ExclusiveStartKey = queryParams.lastEvaluatedKey;
      }

      result = await ddbDocClient.send(new ScanCommand(scanParams));
    }

    // Process results
    const orders = result.Items || [];
    
    // Sort by createdAt if no GSI is used (when scanning all orders)
    if (!queryParams.status) {
      orders.sort((a, b) => {
        const dateA = new Date(a.createdAt || 0);
        const dateB = new Date(b.createdAt || 0);
        return queryParams.sortOrder === 'asc' ? dateA - dateB : dateB - dateA;
      });
    }

    // Calculate totals for each order
    const enrichedOrders = orders.map(order => {
      let orderTotal = 0;
      if (order.items && Array.isArray(order.items)) {
        orderTotal = order.items.reduce((total, item) => {
          return total + ((item.price || 0) * (item.qty || 0));
        }, 0);
      }
      
      return {
        ...order,
        itemCount: order.items?.length || 0,
        orderTotal: parseFloat(orderTotal.toFixed(2))
      };
    });

    // Prepare pagination token
    let nextToken = null;
    if (result.LastEvaluatedKey) {
      nextToken = Buffer.from(JSON.stringify(result.LastEvaluatedKey)).toString('base64');
    }

    log('info', 'Orders listed successfully', {
      requestId,
      orderCount: enrichedOrders.length,
      hasMoreResults: !!nextToken,
      appliedFilters: {
        status: queryParams.status,
        limit: queryParams.limit,
        sortOrder: queryParams.sortOrder
      }
    });

    // Prepare response
    const response = {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache'
      },
      body: JSON.stringify({
        success: true,
        data: {
          orders: enrichedOrders,
          pagination: {
            limit: queryParams.limit,
            count: enrichedOrders.length,
            hasMore: !!nextToken,
            nextToken: nextToken
          },
          filters: {
            status: queryParams.status,
            sortOrder: queryParams.sortOrder
          }
        }
      })
    };

    log('info', 'List orders request completed successfully', {
      requestId,
      statusCode: response.statusCode,
      orderCount: enrichedOrders.length
    });

    return response;

  } catch (error) {
    log('error', 'Unexpected error processing list orders request', {
      requestId,
      error: error.message,
      stack: error.stack,
      errorCode: error.code
    });

    // Handle specific AWS errors
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

    if (error.code === 'ResourceNotFoundException') {
      return {
        statusCode: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Not Found',
          message: 'Orders table not found'
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
        message: 'An unexpected error occurred while retrieving orders',
        requestId
      })
    };
  }
};
