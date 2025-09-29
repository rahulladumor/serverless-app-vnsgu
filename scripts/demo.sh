#!/bin/bash

# Demo script for Serverless Workshop - Order Management Service
# This script demonstrates all the key functionalities of our serverless application

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if API_URL is set
if [ -z "$API_URL" ]; then
    print_error "API_URL environment variable is not set!"
    echo "Please set it using: export API_URL=https://your-api-id.execute-api.region.amazonaws.com"
    exit 1
fi

print_header "🚀 SERVERLESS DEMO: ORDER MANAGEMENT SERVICE"
print_info "API Endpoint: $API_URL"

# Function to make HTTP requests and show response
make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    echo -e "\n${YELLOW}📡 $description${NC}"
    echo "Request: $method $API_URL$endpoint"
    
    if [ -n "$data" ]; then
        echo "Data: $data"
        response=$(curl -s -w "\n%{http_code}" -X $method "$API_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method "$API_URL$endpoint")
    fi
    
    # Extract response body and status code
    response_body=$(echo "$response" | head -n -1)
    status_code=$(echo "$response" | tail -n 1)
    
    echo "Status Code: $status_code"
    echo "Response:"
    echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    
    if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
        print_success "Request successful!"
    else
        print_error "Request failed with status code $status_code"
    fi
    
    echo -e "\n${BLUE}Press Enter to continue...${NC}"
    read
}

# Demo scenarios
print_header "📋 DEMO SCENARIO 1: CREATE ORDERS"

print_info "Creating a small order..."
make_request "POST" "/orders" '{
    "customerName": "Alice Johnson",
    "items": [
        {"sku": "laptop-dell-xps13", "qty": 1, "price": 1299.99},
        {"sku": "mouse-wireless", "qty": 1, "price": 29.99}
    ]
}' "Creating order for Alice Johnson"

# Store the order ID for later use
SMALL_ORDER_ID=$(echo "$response_body" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)

print_info "Creating a large order (will trigger review)..."
make_request "POST" "/orders" '{
    "customerName": "Bob Smith",
    "items": [
        {"sku": "server-rack", "qty": 5, "price": 2500.00},
        {"sku": "network-switch", "qty": 8, "price": 450.00},
        {"sku": "ethernet-cable", "qty": 50, "price": 15.99},
        {"sku": "power-cable", "qty": 25, "price": 8.99}
    ]
}' "Creating large order for Bob Smith (11+ items)"

LARGE_ORDER_ID=$(echo "$response_body" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)

print_info "Creating a high-value order (will trigger approval)..."
make_request "POST" "/orders" '{
    "customerName": "Carol Williams",
    "items": [
        {"sku": "enterprise-server", "qty": 2, "price": 8500.00},
        {"sku": "premium-support", "qty": 1, "price": 5000.00}
    ]
}' "Creating high-value order for Carol Williams ($22,000 total)"

HIGH_VALUE_ORDER_ID=$(echo "$response_body" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)

print_header "📋 DEMO SCENARIO 2: VALIDATION ERRORS"

print_info "Testing validation with invalid data..."
make_request "POST" "/orders" '{
    "customerName": "",
    "items": []
}' "Testing empty customer name and items"

make_request "POST" "/orders" '{
    "customerName": "Test User",
    "items": [
        {"sku": "", "qty": -1, "price": -50}
    ]
}' "Testing invalid item data"

make_request "POST" "/orders" '{"invalid": "json"}' "Testing invalid order structure"

print_header "📋 DEMO SCENARIO 3: RETRIEVE ORDERS"

if [ -n "$SMALL_ORDER_ID" ]; then
    print_info "Retrieving the small order by ID..."
    make_request "GET" "/orders/$SMALL_ORDER_ID" "" "Getting order details for Alice Johnson"
fi

print_info "Testing order not found..."
make_request "GET" "/orders/nonexistent-id" "" "Attempting to get non-existent order"

print_info "Testing invalid UUID format..."
make_request "GET" "/orders/invalid-uuid-format" "" "Testing invalid UUID format"

print_header "📋 DEMO SCENARIO 4: LIST ALL ORDERS"

print_info "Listing all orders..."
make_request "GET" "/orders" "" "Getting all orders (default pagination)"

print_info "Listing orders with filters and pagination..."
make_request "GET" "/orders?limit=2&sortOrder=desc" "" "Getting 2 most recent orders"

make_request "GET" "/orders?status=CONFIRMED" "" "Getting only confirmed orders"

make_request "GET" "/orders?status=PENDING_REVIEW" "" "Getting orders pending review"

print_header "📋 DEMO SCENARIO 5: WAIT FOR ASYNC PROCESSING"

print_info "The order processor Lambda function runs asynchronously via SQS."
print_info "Let's wait a moment and then check the order statuses..."

echo -e "${YELLOW}⏱️  Waiting 10 seconds for async processing...${NC}"
for i in {10..1}; do
    echo -n "$i... "
    sleep 1
done
echo -e "\n"

if [ -n "$SMALL_ORDER_ID" ]; then
    print_info "Checking small order status after processing..."
    make_request "GET" "/orders/$SMALL_ORDER_ID" "" "Checking if small order was confirmed"
fi

if [ -n "$LARGE_ORDER_ID" ]; then
    print_info "Checking large order status after processing..."
    make_request "GET" "/orders/$LARGE_ORDER_ID" "" "Checking if large order needs review"
fi

if [ -n "$HIGH_VALUE_ORDER_ID" ]; then
    print_info "Checking high-value order status after processing..."
    make_request "GET" "/orders/$HIGH_VALUE_ORDER_ID" "" "Checking if high-value order needs approval"
fi

print_header "📋 DEMO SCENARIO 6: MONITORING AND OBSERVABILITY"

print_info "To view CloudWatch logs in real-time, use these commands:"
echo -e "${BLUE}# Stream Create Order Function logs:${NC}"
echo "sam logs -n CreateOrderFunction --stack-name serverless-demo --tail"
echo ""
echo -e "${BLUE}# Stream Order Processor Function logs:${NC}"
echo "sam logs -n OrderProcessorFunction --stack-name serverless-demo --tail"
echo ""
echo -e "${BLUE}# View API Gateway access logs:${NC}"
echo "aws logs tail /aws/apigateway/welcome --follow"

print_header "🎉 DEMO COMPLETED!"

print_success "All demo scenarios completed successfully!"
print_info "Key Serverless Concepts Demonstrated:"
echo "✅ Event-driven architecture (HTTP → Lambda → DynamoDB → SQS → Lambda)"
echo "✅ Auto-scaling (Lambda functions scale automatically with load)"
echo "✅ Pay-per-use pricing (only pay when functions execute)"
echo "✅ Managed services (no server management required)"
echo "✅ Async processing (SQS decouples order creation from processing)"
echo "✅ Error handling and retries (built-in with SQS and DLQ)"
echo "✅ Structured logging for observability"
echo "✅ Input validation and business logic"

print_header "🧹 CLEANUP"
print_warning "Don't forget to clean up AWS resources to avoid charges:"
echo "sam delete"

echo -e "\n${GREEN}🎓 Thank you for attending the VNSGU Serverless Workshop!${NC}"
