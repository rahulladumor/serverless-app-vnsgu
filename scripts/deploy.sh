#!/bin/bash

# Deployment script for Serverless Workshop
# Automates the deployment process with proper error handling and validation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS CLI is not configured or credentials are invalid"
        print_info "Please run: aws configure"
        print_info "You'll need:"
        echo "  - AWS Access Key ID"
        echo "  - AWS Secret Access Key" 
        echo "  - Default region (e.g., us-east-1)"
        echo "  - Default output format (json recommended)"
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null | cut -d'/' -f2)
    
    print_success "AWS CLI configured"
    print_info "Account: $AWS_ACCOUNT"
    print_info "Region: $AWS_REGION"
    print_info "User/Role: $AWS_USER"
}

print_header "🚀 SERVERLESS WORKSHOP - AUTOMATED DEPLOYMENT"

# Check prerequisites
print_info "Checking prerequisites..."

# Check required tools
if ! command_exists aws; then
    print_error "AWS CLI is not installed"
    print_info "Install from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! command_exists sam; then
    print_error "AWS SAM CLI is not installed"
    print_info "Install from: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi

if ! command_exists node; then
    print_error "Node.js is not installed"
    print_info "Install from: https://nodejs.org/"
    exit 1
fi

print_success "All required tools are installed"

# Check AWS configuration
check_aws_config

# Check Node.js version
NODE_VERSION=$(node --version | cut -d'v' -f2)
NODE_MAJOR=$(echo $NODE_VERSION | cut -d'.' -f1)
if [ "$NODE_MAJOR" -lt 22 ]; then
    print_warning "Node.js version $NODE_VERSION detected. Recommended version is 22 or higher for optimal performance."
    if [ "$NODE_MAJOR" -lt 18 ]; then
        print_error "Node.js 18+ is required for this application."
        exit 1
    fi
fi

print_header "📦 PREPARING APPLICATION"

# Install dependencies
if [ -f "package.json" ]; then
    print_info "Installing Node.js dependencies..."
    npm install
    print_success "Dependencies installed"
else
    print_error "package.json not found. Are you in the correct directory?"
    exit 1
fi

# Validate SAM template
print_info "Validating SAM template..."
if sam validate; then
    print_success "SAM template is valid"
else
    print_error "SAM template validation failed"
    exit 1
fi

print_header "🔨 BUILDING APPLICATION"

# Build the application
print_info "Building SAM application..."
if sam build; then
    print_success "Application built successfully"
else
    print_error "Build failed"
    exit 1
fi

print_header "🚀 DEPLOYING TO AWS"

# Deployment configuration
STACK_NAME="serverless-demo"
REGION="$AWS_REGION"

# Check if this is first deployment
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_info "Stack '$STACK_NAME' already exists. Updating..."
    DEPLOY_COMMAND="sam deploy --stack-name $STACK_NAME --region $REGION --capabilities CAPABILITY_IAM --no-confirm-changeset"
else
    print_info "First deployment. Using guided deployment..."
    print_warning "You will be prompted for deployment parameters."
    DEPLOY_COMMAND="sam deploy --guided --stack-name $STACK_NAME --region $REGION"
fi

print_info "Executing deployment..."
if eval $DEPLOY_COMMAND; then
    print_success "Deployment completed successfully!"
else
    print_error "Deployment failed"
    print_info "Check the CloudFormation console for error details:"
    echo "https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
    exit 1
fi

print_header "📋 DEPLOYMENT INFORMATION"

# Get stack outputs
print_info "Retrieving deployment outputs..."
API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text 2>/dev/null)

ORDERS_TABLE=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrdersTableName`].OutputValue' \
    --output text 2>/dev/null)

QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrdersQueueUrl`].OutputValue' \
    --output text 2>/dev/null)

if [ -n "$API_URL" ]; then
    print_success "API URL: $API_URL"
    
    # Create environment file for easy testing
    echo "export API_URL=\"$API_URL\"" > .env
    print_info "Environment file created: .env"
    print_info "Source it with: source .env"
    
else
    print_warning "Could not retrieve API URL from stack outputs"
fi

if [ -n "$ORDERS_TABLE" ]; then
    print_info "DynamoDB Table: $ORDERS_TABLE"
fi

if [ -n "$QUEUE_URL" ]; then
    print_info "SQS Queue: $QUEUE_URL"
fi

print_header "🧪 TESTING DEPLOYMENT"

if [ -n "$API_URL" ]; then
    print_info "Testing API endpoint..."
    
    # Test health by creating a simple order
    TEST_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/orders" \
        -H "Content-Type: application/json" \
        -d '{
            "customerName": "Deployment Test",
            "items": [{"sku": "test-item", "qty": 1, "price": 1.00}]
        }')
    
    HTTP_STATUS=$(echo "$TEST_RESPONSE" | tail -c 4)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        print_success "API is responding correctly!"
        
        # Extract order ID for cleanup
        ORDER_ID=$(echo "$TEST_RESPONSE" | head -n -1 | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)
        if [ -n "$ORDER_ID" ]; then
            print_info "Test order created with ID: $ORDER_ID"
        fi
    else
        print_warning "API test returned status: $HTTP_STATUS"
        print_info "This might be normal for a cold start. Try again in a few seconds."
    fi
else
    print_warning "Skipping API test - no API URL available"
fi

print_header "🎯 NEXT STEPS"

print_success "Deployment completed successfully!"
print_info "You can now:"

if [ -n "$API_URL" ]; then
    echo "✅ Test the API using the demo script:"
    echo "   export API_URL=\"$API_URL\""
    echo "   ./scripts/demo.sh"
    echo ""
    echo "✅ Run load tests to see auto-scaling:"
    echo "   ./scripts/load-test.sh"
    echo ""
fi

echo "✅ Monitor the application:"
echo "   - CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups"
echo "   - Lambda Functions: https://console.aws.amazon.com/lambda/home?region=$REGION#/functions"
echo "   - API Gateway: https://console.aws.amazon.com/apigateway/home?region=$REGION#/apis"
echo "   - DynamoDB: https://console.aws.amazon.com/dynamodbv2/home?region=$REGION#tables"

echo ""
echo "✅ View real-time logs:"
echo "   sam logs -n CreateOrderFunction --stack-name $STACK_NAME --tail"

print_warning "Don't forget to clean up resources when done:"
echo "   sam delete --stack-name $STACK_NAME --region $REGION"

print_header "🎉 HAPPY SERVERLESS COMPUTING!"

echo -e "${GREEN}Your serverless Order Management Service is now live!${NC}"
echo -e "${BLUE}Built with ❤️  for VNSGU Serverless Workshop${NC}"
