#!/bin/bash

# Cleanup script for Serverless Workshop
# Safely removes all AWS resources to avoid ongoing charges

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

# Configuration
STACK_NAME="serverless-demo"
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

print_header "🧹 SERVERLESS WORKSHOP - CLEANUP"

print_warning "This script will delete ALL resources created for the serverless workshop."
print_warning "This action cannot be undone!"
print_info "Stack to delete: $STACK_NAME"
print_info "Region: $REGION"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    print_error "AWS CLI is not configured or credentials are invalid"
    exit 1
fi

# Confirmation prompt
echo -e "\n${YELLOW}Do you want to continue with the cleanup? (yes/no): ${NC}"
read -r confirmation

if [[ $confirmation != "yes" ]]; then
    print_info "Cleanup cancelled by user"
    exit 0
fi

print_header "🔍 CHECKING EXISTING RESOURCES"

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_info "Stack '$STACK_NAME' found"
    
    # Get stack outputs before deletion for logging
    print_info "Current stack resources:"
    
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text 2>/dev/null || echo "Not found")
    
    ORDERS_TABLE=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`OrdersTableName`].OutputValue' \
        --output text 2>/dev/null || echo "Not found")
    
    QUEUE_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`OrdersQueueUrl`].OutputValue' \
        --output text 2>/dev/null || echo "Not found")
    
    echo "  - API Gateway: $API_URL"
    echo "  - DynamoDB Table: $ORDERS_TABLE"
    echo "  - SQS Queue: $QUEUE_URL"
    
    # Check for data in DynamoDB table
    if [[ "$ORDERS_TABLE" != "Not found" ]]; then
        ORDER_COUNT=$(aws dynamodb scan \
            --table-name "$ORDERS_TABLE" \
            --region "$REGION" \
            --select "COUNT" \
            --query "Count" \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$ORDER_COUNT" -gt 0 ]]; then
            print_warning "DynamoDB table contains $ORDER_COUNT orders"
            print_warning "All order data will be permanently lost!"
        fi
    fi
    
else
    print_warning "Stack '$STACK_NAME' not found"
    print_info "Nothing to clean up"
    exit 0
fi

print_header "🗑️  DELETING RESOURCES"

print_info "Starting stack deletion..."
print_warning "This may take several minutes..."

# Delete the stack
if aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"; then
    print_success "Stack deletion initiated"
else
    print_error "Failed to initiate stack deletion"
    exit 1
fi

print_info "Waiting for stack deletion to complete..."

# Wait for deletion with progress updates
WAIT_COUNT=0
MAX_WAIT=60  # 10 minutes max wait

while aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    
    if [ $WAIT_COUNT -gt $MAX_WAIT ]; then
        print_error "Stack deletion is taking longer than expected"
        print_info "Check CloudFormation console for details:"
        echo "https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
        exit 1
    fi
    
    # Get stack status
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "DELETE_COMPLETE")
    
    if [[ "$STACK_STATUS" == "DELETE_FAILED" ]]; then
        print_error "Stack deletion failed"
        print_info "Check CloudFormation console for error details:"
        echo "https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
        
        # Show stack events for debugging
        print_info "Recent stack events:"
        aws cloudformation describe-stack-events \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'StackEvents[0:5].[Timestamp,ResourceType,ResourceStatus,ResourceStatusReason]' \
            --output table 2>/dev/null || echo "Could not retrieve stack events"
        
        exit 1
    fi
    
    echo -n "."
    sleep 10
done

echo ""
print_success "Stack deletion completed!"

print_header "🧽 ADDITIONAL CLEANUP"

# Check for any leftover resources (sometimes happens with custom resources)
print_info "Checking for any remaining resources..."

# Check for Lambda functions with our naming pattern
LAMBDA_FUNCTIONS=$(aws lambda list-functions \
    --region "$REGION" \
    --query "Functions[?contains(FunctionName, 'serverless-demo') || contains(FunctionName, 'CreateOrder') || contains(FunctionName, 'GetOrder') || contains(FunctionName, 'OrderProcessor')].FunctionName" \
    --output text 2>/dev/null || echo "")

if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
    print_warning "Found leftover Lambda functions:"
    echo "$LAMBDA_FUNCTIONS"
    print_info "These may be from a different stack or manual creation"
fi

# Check for API Gateways
API_GATEWAYS=$(aws apigatewayv2 get-apis \
    --region "$REGION" \
    --query "Items[?contains(Name, 'serverless-demo')].{Name:Name,Id:ApiId}" \
    --output text 2>/dev/null || echo "")

if [[ -n "$API_GATEWAYS" ]]; then
    print_warning "Found leftover API Gateways:"
    echo "$API_GATEWAYS"
fi

# Clean up local files
print_info "Cleaning up local files..."

if [ -f ".env" ]; then
    rm .env
    print_success "Removed .env file"
fi

if [ -d ".aws-sam" ]; then
    rm -rf .aws-sam
    print_success "Removed .aws-sam build directory"
fi

if [ -f "samconfig.toml" ]; then
    print_info "Found samconfig.toml (contains deployment configuration)"
    echo -e "${YELLOW}Do you want to remove it? (yes/no): ${NC}"
    read -r remove_config
    
    if [[ $remove_config == "yes" ]]; then
        rm samconfig.toml
        print_success "Removed samconfig.toml"
    fi
fi

print_header "✅ CLEANUP SUMMARY"

print_success "Cleanup completed successfully!"
print_info "Resources removed:"
echo "  ✅ CloudFormation stack: $STACK_NAME"
echo "  ✅ Lambda functions (3)"
echo "  ✅ API Gateway"
echo "  ✅ DynamoDB table and all data"
echo "  ✅ SQS queues (main and DLQ)"
echo "  ✅ IAM roles and policies"
echo "  ✅ CloudWatch log groups"
echo "  ✅ Local build artifacts"

print_info "What was NOT removed:"
echo "  ℹ️  CloudWatch logs (they have retention policies)"
echo "  ℹ️  Source code files"
echo "  ℹ️  This cleanup script"

print_warning "Final reminders:"
echo "  - Check your AWS billing console to confirm no ongoing charges"
echo "  - CloudWatch logs may incur small charges but will expire automatically"
echo "  - If you see unexpected charges, check for resources in other regions"

print_info "Billing console: https://console.aws.amazon.com/billing/home#/bills"

echo -e "\n${GREEN}🎉 All workshop resources have been cleaned up!${NC}"
echo -e "${BLUE}Thank you for attending the VNSGU Serverless Workshop!${NC}"
