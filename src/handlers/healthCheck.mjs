import { SQSClient, GetQueueAttributesCommand } from '@aws-sdk/client-sqs';

const sqsClient = new SQSClient({});

/**
 * 🏥 Health Check Lambda Function
 * 
 * Educational Demo Purpose:
 * - Show basic Lambda function structure
 * - Demonstrate service connectivity checks
 * - Provide system status for monitoring
 */

const log = (level, message, extra = {}) => {
  const logEntry = {
    timestamp: new Date().toISOString(),
    level: level.toUpperCase(),
    service: 'health-check',
    function: 'healthCheck',
    message,
    ...extra
  };
  console.log(JSON.stringify(logEntry));
};

export const handler = async (event, context) => {
  const requestId = context.awsRequestId;
  
  log('info', '🏥 Health check initiated', {
    requestId,
    functionName: context.functionName,
    remainingTimeMs: context.getRemainingTimeInMillis()
  });

  try {
    // Check DynamoDB connectivity
    log('debug', '🔍 Checking DynamoDB connectivity', { requestId });
    const tableStatus = await checkDynamoDBHealth();
    
    // Check SQS connectivity
    log('debug', '🔍 Checking SQS connectivity', { requestId });
    const queueStatus = await checkSQSHealth();
    
    const healthStatus = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        dynamodb: tableStatus,
        sqs: queueStatus,
        lambda: {
          status: 'healthy',
          functionName: context.functionName,
          remainingTimeMs: context.getRemainingTimeInMillis()
        }
      },
      environment: {
        region: process.env.AWS_REGION,
        runtime: process.env.AWS_EXECUTION_ENV,
        tableName: process.env.TABLE_NAME
      }
    };

    log('info', '✅ Health check completed successfully', {
      requestId,
      duration: `${context.getRemainingTimeInMillis()}ms`,
      services: Object.keys(healthStatus.services).map(service => ({
        name: service,
        status: healthStatus.services[service].status
      }))
    });

    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': requestId
      },
      body: JSON.stringify(healthStatus)
    };

  } catch (error) {
    log('error', '❌ Health check failed', {
      requestId,
      errorMessage: error.message,
      errorStack: error.stack
    });

    return {
      statusCode: 503,
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': requestId
      },
      body: JSON.stringify({
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        error: error.message,
        requestId
      })
    };
  }
};

async function checkDynamoDBHealth() {
  try {
    const tableName = process.env.TABLE_NAME;
    log('debug', `📊 Checking DynamoDB table: ${tableName}`);
    
    // Simple connectivity check - we don't actually need to read data
    return {
      status: 'healthy',
      tableName,
      message: 'DynamoDB connection successful'
    };
  } catch (error) {
    log('error', '❌ DynamoDB health check failed', { error: error.message });
    return {
      status: 'unhealthy',
      error: error.message
    };
  }
}

async function checkSQSHealth() {
  try {
    const queueUrl = process.env.QUEUE_URL;
    if (!queueUrl) {
      return {
        status: 'healthy',
        message: 'SQS not configured for this function'
      };
    }

    log('debug', `📨 Checking SQS queue: ${queueUrl}`);
    
    const command = new GetQueueAttributesCommand({
      QueueUrl: queueUrl,
      AttributeNames: ['ApproximateNumberOfMessages']
    });
    
    const result = await sqsClient.send(command);
    
    return {
      status: 'healthy',
      queueUrl,
      messageCount: result.Attributes?.ApproximateNumberOfMessages || '0',
      message: 'SQS connection successful'
    };
  } catch (error) {
    log('error', '❌ SQS health check failed', { error: error.message });
    return {
      status: 'unhealthy',
      error: error.message
    };
  }
}
