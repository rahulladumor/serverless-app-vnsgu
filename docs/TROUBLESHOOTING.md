# 🔧 Troubleshooting Guide

This guide helps you resolve common issues that may occur during the serverless workshop.

---

## 🚨 Quick Fixes

### "Command not found" Errors

**Issue**: `sam: command not found` or `aws: command not found`

**Solution**:
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Install SAM CLI  
brew install aws-sam-cli
# OR
pip install aws-sam-cli
```

### AWS Credentials Issues

**Issue**: `Unable to locate credentials` or `Access Denied`

**Solution**:
```bash
# Configure AWS CLI
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)

# Verify configuration
aws sts get-caller-identity
```

**Alternative**: Use AWS CloudShell (browser-based terminal) if local setup fails.

---

## 🔍 Deployment Issues

### SAM Build Failures

**Issue**: `BUILD FAILED` during `sam build`

**Common Causes & Solutions**:

1. **Node.js Version Mismatch**
   ```bash
   # Check version
   node --version
   # Should be 18.x or higher
   
   # Update if needed
   nvm install 18
   nvm use 18
   ```

2. **Missing Dependencies**
   ```bash
   # Install dependencies
   npm install
   
   # Clear cache if needed
   npm cache clean --force
   rm -rf node_modules package-lock.json
   npm install
   ```

3. **Template Validation Errors**
   ```bash
   # Validate template
   sam validate
   
   # Common fix: Check YAML indentation
   # Use spaces, not tabs
   ```

### Deployment Permission Errors

**Issue**: `User is not authorized to perform: cloudformation:CreateStack`

**Solution**:
```bash
# Check current permissions
aws iam get-user

# Required permissions:
# - CloudFormation (full access)
# - Lambda (full access)  
# - API Gateway (full access)
# - DynamoDB (full access)
# - SQS (full access)
# - IAM (pass role)
```

**Quick Fix**: Use PowerUser or Administrator policy for workshop (not for production).

### Stack Already Exists

**Issue**: `Stack already exists`

**Solutions**:
```bash
# Option 1: Update existing stack
sam deploy --stack-name serverless-demo

# Option 2: Delete and recreate
sam delete --stack-name serverless-demo
sam deploy --guided

# Option 3: Use different stack name
sam deploy --guided --stack-name serverless-demo-2
```

---

## 🌐 API Issues

### API Returns 502/503 Errors

**Issue**: `{"message": "Internal server error"}`

**Debugging Steps**:

1. **Check Lambda Logs**
   ```bash
   sam logs -n CreateOrderFunction --tail
   # Look for error messages
   ```

2. **Common Causes**:
   - Function timeout (increase in template.yaml)
   - Memory limit exceeded (increase MemorySize)
   - Import/require errors in code
   - AWS service permission issues

3. **Test Function Locally**
   ```bash
   sam local invoke CreateOrderFunction --event events/create-order-event.json
   ```

### API Returns 404 Errors

**Issue**: `{"message": "Not Found"}`

**Solution**:
```bash
# Check API Gateway URL
aws cloudformation describe-stacks \
  --stack-name serverless-demo \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text

# Verify endpoint exists
curl $API_URL/orders -v
```

### CORS Errors in Browser

**Issue**: `Access-Control-Allow-Origin` errors

**Solution**: Check template.yaml CORS configuration:
```yaml
CorsConfiguration:
  AllowOrigins: ['*']
  AllowHeaders: ['*'] 
  AllowMethods: [GET, POST, PUT, DELETE, OPTIONS]
```

---

## 💾 Database Issues

### DynamoDB Access Denied

**Issue**: `User is not authorized to perform: dynamodb:PutItem`

**Solution**: Check Lambda execution role has DynamoDB permissions:
```yaml
Policies:
  - DynamoDBCrudPolicy:
      TableName: !Ref OrdersTable
```

### Table Not Found

**Issue**: `Requested resource not found`

**Debugging**:
```bash
# Check if table exists
aws dynamodb list-tables

# Check table name in environment variables
aws lambda get-function-configuration \
  --function-name CreateOrderFunction \
  --query 'Environment.Variables'
```

---

## 📨 SQS Issues

### Messages Not Processing

**Issue**: Orders stuck in PENDING status

**Debugging Steps**:

1. **Check Queue Depth**
   ```bash
   aws sqs get-queue-attributes \
     --queue-url $QUEUE_URL \
     --attribute-names ApproximateNumberOfMessages
   ```

2. **Check Order Processor Logs**
   ```bash
   sam logs -n OrderProcessorFunction --tail
   ```

3. **Manual Message Send Test**
   ```bash
   aws sqs send-message \
     --queue-url $QUEUE_URL \
     --message-body '{"type":"OrderCreated","detail":{"id":"test-id"}}'
   ```

### Dead Letter Queue Issues

**Issue**: Messages going to DLQ repeatedly

**Solution**: Check processor function for:
- Parsing errors
- DynamoDB connection issues  
- Timeout problems
- Memory limits

---

## 🚀 Performance Issues

### High Latency/Cold Starts

**Issue**: First requests take 2-5 seconds

**Solutions**:
1. **Provisioned Concurrency** (costs extra)
2. **Increase Memory** (faster CPU allocation)
3. **Connection Pooling** (reuse DB connections)

**Temporary Workaround**:
```bash
# Keep functions warm with scheduled pings
aws events put-rule --name warm-lambda --schedule-expression "rate(5 minutes)"
```

### Lambda Timeouts

**Issue**: Functions timing out after 10 seconds

**Solution**: Increase timeout in template.yaml:
```yaml
Globals:
  Function:
    Timeout: 30  # Increased from 10
```

---

## 🧪 Testing Issues

### Demo Script Fails

**Issue**: `./scripts/demo.sh` returns errors

**Common Fixes**:

1. **Set API_URL Environment Variable**
   ```bash
   export API_URL="https://your-api-gateway-url"
   ```

2. **Check Script Permissions**
   ```bash
   chmod +x scripts/demo.sh
   ```

3. **Python JSON Tool Missing**
   ```bash
   # Install Python 3 if missing
   brew install python3
   # OR use jq instead
   brew install jq
   ```

### Load Test Script Issues

**Issue**: Load test fails with connection errors

**Solutions**:
1. **Reduce Concurrency**
   ```bash
   ./scripts/load-test.sh 5 25  # Lower numbers
   ```

2. **Check API Gateway Throttling**
   ```bash
   aws apigatewayv2 get-stage --api-id $API_ID --stage-name $STAGE_NAME
   ```

---

## 🔧 Local Development Issues

### SAM Local API Fails

**Issue**: `sam local start-api` doesn't work

**Solutions**:

1. **Docker Issues**
   ```bash
   # Make sure Docker is running
   docker --version
   
   # Pull required images
   sam build
   ```

2. **Port Conflicts**
   ```bash
   # Use different port
   sam local start-api --port 3001
   ```

3. **Environment Variables**
   ```bash
   # Create local env file
   echo "TABLE_NAME=Orders" > env.json
   sam local start-api --env-vars env.json
   ```

---

## 🧹 Cleanup Issues

### Stack Deletion Fails

**Issue**: `DELETE_FAILED` status in CloudFormation

**Common Causes & Solutions**:

1. **S3 Buckets Not Empty**
   ```bash
   # Empty S3 buckets manually
   aws s3 rm s3://bucket-name --recursive
   ```

2. **Lambda Functions Still Processing**
   ```bash
   # Wait for functions to finish
   # Then retry deletion
   ```

3. **Manual Resource Creation**
   ```bash
   # Delete manually created resources first
   # Then delete stack
   ```

**Force Deletion** (last resort):
```bash
aws cloudformation delete-stack --stack-name serverless-demo
# Manually delete remaining resources if needed
```

---

## 📊 Monitoring & Logging

### Missing CloudWatch Logs

**Issue**: No logs appearing in CloudWatch

**Solutions**:

1. **Check Log Group Names**
   ```bash
   aws logs describe-log-groups | grep serverless-demo
   ```

2. **Verify Function Execution**
   ```bash
   # Check Lambda metrics
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Lambda \
     --metric-name Invocations \
     --dimensions Name=FunctionName,Value=CreateOrderFunction \
     --start-time 2025-01-01T00:00:00Z \
     --end-time 2025-01-02T00:00:00Z \
     --period 3600 \
     --statistics Sum
   ```

### Log Viewing Issues

**Issue**: `sam logs` command fails

**Alternative Solutions**:
```bash
# Use AWS CLI directly
aws logs tail /aws/lambda/CreateOrderFunction --follow

# Use AWS Console
# Navigate to CloudWatch > Log Groups > /aws/lambda/FunctionName
```

---

## 🆘 Emergency Procedures

### Complete Workshop Reset

If everything fails, use this nuclear option:

```bash
# 1. Delete everything
./scripts/cleanup.sh
rm -rf .aws-sam
rm .env samconfig.toml

# 2. Start fresh
sam build
sam deploy --guided

# 3. Test basic functionality
export API_URL="new-api-url"
curl -X POST "$API_URL/orders" -d '{"customerName":"test","items":[{"sku":"test","qty":1}]}'
```

### Workshop Without AWS Account

If AWS setup fails completely:

1. **Use AWS CloudShell** (browser-based terminal)
2. **Use Local SAM** (limited functionality):
   ```bash
   sam local start-api
   # Test on http://localhost:3000
   ```
3. **Show Pre-recorded Demo** (have backup ready)

---

## 🤝 Getting Help

### During Workshop
1. **Raise hand** for immediate assistance
2. **Check with neighbors** - peer programming encouraged
3. **Use workshop Slack/chat** for questions

### After Workshop
1. **GitHub Issues**: Create issues in the workshop repository
2. **AWS Documentation**: Comprehensive troubleshooting guides
3. **Community Forums**: Stack Overflow, Reddit r/aws
4. **AWS Support**: For account/billing issues

### Useful Resources
- **AWS SAM Troubleshooting**: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/troubleshooting.html
- **AWS Lambda Troubleshooting**: https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html
- **AWS CLI Troubleshooting**: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-troubleshooting.html

---

## 📋 Pre-Workshop Checklist

To avoid issues during the workshop:

### Required Software
- [ ] AWS CLI installed and configured
- [ ] SAM CLI installed (version 1.70.0+)
- [ ] Node.js 18+ installed
- [ ] Docker installed (for local testing)
- [ ] Python 3 installed (for demo scripts)

### AWS Account Setup
- [ ] Active AWS account with valid payment method
- [ ] IAM user with appropriate permissions
- [ ] AWS credentials configured locally
- [ ] Test deployment in a throwaway region

### Network & Environment
- [ ] Stable internet connection
- [ ] Corporate firewall allows AWS API calls
- [ ] No VPN conflicts with AWS endpoints
- [ ] Terminal/shell with proper permissions

---

**Remember**: The goal is learning, not perfection. If you encounter issues during the workshop, don't stress - troubleshooting is part of the serverless journey!
