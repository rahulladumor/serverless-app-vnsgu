# 📊 CloudWatch Monitoring Guide for Serverless Demo

This guide shows you exactly what to watch in CloudWatch to demonstrate the complete serverless flow to students.

## 🎯 **Complete Flow Demonstration**

### **📋 Step-by-Step Flow to Show Students:**

1. **Create Order** (POST `/orders`) → 
2. **SQS Message** → 
3. **Order Processor** → 
4. **Status Update** → 
5. **Get Order** (GET `/orders/{id}`) → 
6. **View Updated Status**

---

## 🔍 **CloudWatch Log Groups to Monitor**

### **1. 📝 Create Order Function**
**Log Group**: `/aws/lambda/serverless-demo-CreateOrderFunction-*`

**🎓 What to show students:**
```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "service": "order-service",
  "function": "createOrder",
  "message": "Processing create order request",
  "requestId": "abc123",
  "httpMethod": "POST",
  "path": "/orders"
}
```

**🔍 Key Log Messages to Point Out:**
- `Processing create order request` - Lambda function started
- `Creating order in database` - DynamoDB write operation
- `📨 Preparing to send SQS message` - About to trigger async processing
- `✅ Order event sent to queue successfully` - SQS message sent with MessageId

### **2. 📨 SQS Message Processing**
**Log Group**: `/aws/lambda/serverless-demo-OrderProcessorFunction-*`

**🎓 What to show students:**
```json
{
  "timestamp": "2024-01-15T10:30:01.456Z",
  "level": "INFO",
  "service": "order-processor",
  "function": "orderProcessor",
  "message": "Processing SQS record",
  "messageId": "xyz789",
  "receiptHandle": "AQEB......"
}
```

**🔍 Key Log Messages to Point Out:**
- `Starting order processor batch` - SQS triggered the function
- `Processing SQS record` - Individual message processing
- `🔄 Applying business logic to order` - Business rules execution
- `💾 Updating order status in DynamoDB` - Status change
- `✅ Order status updated successfully` - Process completed
- `🎯 SQS message processed completely` - End-to-end timing

### **3. 🔍 Get Order Function**  
**Log Group**: `/aws/lambda/serverless-demo-GetOrderFunction-*`

**🎓 What to show students:**
```json
{
  "timestamp": "2024-01-15T10:30:02.789Z",
  "level": "INFO",
  "service": "order-service",
  "function": "getOrder",
  "message": "📊 Retrieving order from database",
  "requestId": "def456",
  "orderId": "12345678-1234-1234-1234-123456789012",
  "tableName": "Orders-dev"
}
```

**🔍 Key Log Messages to Point Out:**
- `Processing get order request` - HTTP GET received
- `📊 Retrieving order from database` - DynamoDB query starting
- `🔍 Executing DynamoDB GetItem operation` - Actual database call
- `Order retrieved successfully` - Shows updated status (CONFIRMED vs PENDING)

### **4. 🏥 Health Check Function**
**Log Group**: `/aws/lambda/serverless-demo-HealthCheckFunction-*`

**🎓 What to show students:**
```json
{
  "timestamp": "2024-01-15T10:30:03.012Z",
  "level": "INFO",
  "service": "health-check",
  "function": "healthCheck",
  "message": "✅ Health check completed successfully",
  "services": [
    {"name": "dynamodb", "status": "healthy"},
    {"name": "sqs", "status": "healthy"},
    {"name": "lambda", "status": "healthy"}
  ]
}
```

---

## 📊 **CloudWatch Metrics to Demonstrate**

### **Lambda Metrics Dashboard**
Navigate to: **CloudWatch → Dashboards → Lambda**

#### **🎯 Key Metrics to Show:**

1. **Invocations** 
   - Shows each API call triggering Lambda
   - Demonstrate scaling from 0 to multiple concurrent executions

2. **Duration**
   - Point out cold start vs warm start differences
   - First request: ~2-3 seconds (cold start)
   - Subsequent requests: ~100-500ms (warm start)

3. **Concurrent Executions**
   - Show auto-scaling in real-time
   - Create multiple orders rapidly to see scaling

4. **Error Rate**
   - Should be 0% for successful demo
   - Use validation errors to show error handling

### **API Gateway Metrics**
Navigate to: **API Gateway → APIs → serverless-demo-HttpApi → Monitoring**

#### **🎯 Key Metrics to Show:**
- **Request Count** - Total API calls
- **Latency** - End-to-end response time
- **4XX/5XX Errors** - Error rates

### **DynamoDB Metrics**
Navigate to: **DynamoDB → Tables → Orders-dev → Monitoring**

#### **🎯 Key Metrics to Show:**
- **Consumed Read/Write Units** - Pay-per-request pricing in action
- **Item Count** - Growing as orders are created
- **Throttled Requests** - Should be 0 (show scaling)

### **SQS Metrics**
Navigate to: **SQS → Queues → order-events-dev → Monitoring**

#### **🎯 Key Metrics to Show:**
- **Messages Sent** - Orders triggering async processing
- **Messages Received** - Order processor consuming messages
- **Queue Depth** - Should be 0 (messages processed quickly)
- **Dead Letter Queue** - For error handling demo

---

## 🎬 **Live Demo Script for Students**

### **Phase 1: Show the Architecture (5 minutes)**
1. Open **CloudWatch Logs** in multiple tabs:
   - CreateOrder function logs
   - OrderProcessor function logs
   - GetOrder function logs

2. Open **CloudWatch Metrics** dashboards:
   - Lambda metrics
   - DynamoDB metrics
   - SQS metrics

### **Phase 2: Execute the Flow (15 minutes)**

#### **Step 1: Create Order**
```bash
# In Postman: Run "Create Simple Order"
POST https://fli5nt4dt7.execute-api.us-east-1.amazonaws.com/orders
```

**🎓 Show students:**
- CreateOrder logs appearing immediately
- DynamoDB write operation logged
- SQS message ID in logs
- Order ID generated and stored

#### **Step 2: Watch SQS Processing**
**Wait 1-2 seconds, then refresh OrderProcessor logs**

**🎓 Show students:**
- SQS message received
- Business logic applied
- DynamoDB status update (PENDING → CONFIRMED)
- Processing timing logs

#### **Step 3: Verify Status Change**
```bash
# In Postman: Run "Get Order by ID" 
GET https://fli5nt4dt7.execute-api.us-east-1.amazonaws.com/orders/{id}
```

**🎓 Show students:**
- GetOrder logs showing retrieval
- Order status now shows "CONFIRMED"
- End-to-end processing completed

### **Phase 3: Health Check Demo (5 minutes)**
```bash
# In Postman: Run "Health Check Endpoint"
GET https://fli5nt4dt7.execute-api.us-east-1.amazonaws.com/health
```

**🎓 Show students:**
- System health verification
- Service connectivity checks
- Monitoring and observability patterns

### **Phase 4: Error Handling Demo (10 minutes)**

#### **Show Validation Errors:**
```bash
# In Postman: Run "Create Order - Validation Error"
POST /orders with invalid data
```

#### **Show 404 Handling:**
```bash
# In Postman: Run "Get Non-existent Order"
GET /orders/00000000-0000-0000-0000-000000000000
```

### **Phase 5: Load Testing (10 minutes)**
```bash
# In Postman: Run "Rapid Order Creation" multiple times quickly
```

**🎓 Show students:**
- Lambda concurrent executions scaling
- Multiple log streams appearing
- Auto-scaling metrics in real-time
- Cost implications of scaling

---

## 🎯 **Key Teaching Points**

### **💡 Cold Start vs Warm Start**
- **First request**: Show ~2-3 second duration (cold start logs)
- **Subsequent requests**: Show ~100-500ms duration (warm starts)
- **Explain**: Lambda containers reused for efficiency

### **💰 Cost Model Demonstration**
Calculate live costs during demo:
```
Lambda: $0.0000166667 per GB-second + $0.20 per 1M requests
DynamoDB: $0.25 per 1M read/write requests  
API Gateway: $3.50 per 1M requests
SQS: $0.40 per 1M requests

Demo cost: ~$0.001 for complete flow
```

### **🔄 Event-Driven Architecture**
- **Synchronous**: API Gateway → Lambda → Response
- **Asynchronous**: Lambda → SQS → Lambda → DynamoDB
- **Loose Coupling**: Services don't know about each other

### **📊 Observability Built-in**
- **Every request logged** automatically
- **Metrics available** without setup
- **Structured logging** for easy filtering
- **Distributed tracing** ready with X-Ray

---

## 🛠️ **CloudWatch Queries for Deep Analysis**

### **Find All Order Processing Flows**
```sql
fields @timestamp, @message
| filter @message like /orderId/
| sort @timestamp desc
| limit 20
```

### **Monitor Response Times**
```sql
fields @timestamp, @duration
| filter @message like /Order retrieved successfully/
| stats avg(@duration), max(@duration), min(@duration)
```

### **Track SQS Processing**
```sql
fields @timestamp, @message
| filter @message like /SQS message processed completely/
| sort @timestamp desc
```

### **Error Analysis**
```sql
fields @timestamp, @message, @requestId
| filter @level = "ERROR"
| sort @timestamp desc
```

---

## 🎉 **Success Indicators for Demo**

### **✅ Complete Flow Working:**
1. Order creation logs appear
2. SQS message processing logs appear
3. Order status changes from PENDING to CONFIRMED
4. Get order shows updated status
5. All metrics show successful operations

### **✅ Error Handling Working:**
1. Validation errors return 400 status
2. Missing orders return 404 status
3. Proper error messages in logs
4. No exceptions or crashes

### **✅ Performance Demonstrable:**
1. Cold starts visible (~2-3 seconds)
2. Warm starts visible (~100-500ms)
3. Auto-scaling visible in concurrent executions
4. Low cost per request demonstrable

---

**🎯 This comprehensive monitoring setup gives you everything needed to showcase the power, scalability, and cost-effectiveness of serverless architecture to your students!**
