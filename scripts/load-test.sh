#!/bin/bash

# Load testing script for Serverless Workshop
# Demonstrates auto-scaling capabilities of Lambda functions

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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if API_URL is set
if [ -z "$API_URL" ]; then
    echo -e "${RED}❌ API_URL environment variable is not set!${NC}"
    echo "Please set it using: export API_URL=https://your-api-id.execute-api.region.amazonaws.com"
    exit 1
fi

# Check if required tools are installed
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl is required but not installed${NC}"
    exit 1
fi

print_header "🚀 SERVERLESS LOAD TEST - DEMONSTRATING AUTO-SCALING"
print_info "API Endpoint: $API_URL"
print_info "This test will send multiple concurrent requests to demonstrate Lambda auto-scaling"

# Configuration
CONCURRENT_REQUESTS=${1:-10}
TOTAL_REQUESTS=${2:-50}
REQUEST_DELAY=${3:-0.1}

print_info "Configuration:"
echo "  - Concurrent requests: $CONCURRENT_REQUESTS"
echo "  - Total requests: $TOTAL_REQUESTS"
echo "  - Delay between requests: ${REQUEST_DELAY}s"

# Sample order data for testing
ORDER_TEMPLATES=(
    '{"customerName": "Load Test User 1", "items": [{"sku": "test-item-1", "qty": 1, "price": 10.00}]}'
    '{"customerName": "Load Test User 2", "items": [{"sku": "test-item-2", "qty": 2, "price": 15.50}]}'
    '{"customerName": "Load Test User 3", "items": [{"sku": "test-item-3", "qty": 3, "price": 25.99}]}'
    '{"customerName": "Load Test User 4", "items": [{"sku": "test-item-4", "qty": 1, "price": 99.99}]}'
    '{"customerName": "Load Test User 5", "items": [{"sku": "test-item-5", "qty": 5, "price": 5.00}]}'
)

# Function to send a single request
send_request() {
    local request_id=$1
    local order_data=${ORDER_TEMPLATES[$((request_id % ${#ORDER_TEMPLATES[@]}))]}
    
    start_time=$(date +%s.%N)
    response=$(curl -s -w "%{http_code}:%{time_total}" -X POST "$API_URL/orders" \
        -H "Content-Type: application/json" \
        -d "$order_data")
    end_time=$(date +%s.%N)
    
    # Extract status code and response time
    status_code=$(echo "$response" | tail -c 10 | cut -d':' -f1)
    response_time=$(echo "$response" | tail -c 10 | cut -d':' -f2)
    
    echo "Request $request_id: Status $status_code, Time ${response_time}s"
    
    # Return success/failure for statistics
    if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
        echo "SUCCESS:$response_time" >> /tmp/load_test_results.txt
    else
        echo "FAILURE:$response_time" >> /tmp/load_test_results.txt
    fi
}

# Clear previous results
rm -f /tmp/load_test_results.txt

print_warning "Starting load test in 3 seconds..."
sleep 3

print_header "📊 EXECUTING LOAD TEST"

# Record start time
test_start=$(date +%s.%N)

# Send requests with controlled concurrency
for ((i=1; i<=TOTAL_REQUESTS; i++)); do
    # Control concurrency by limiting background processes
    while [ $(jobs -r | wc -l) -ge $CONCURRENT_REQUESTS ]; do
        sleep 0.01
    done
    
    # Send request in background
    send_request $i &
    
    # Small delay between requests to avoid overwhelming
    sleep $REQUEST_DELAY
done

# Wait for all background jobs to complete
wait

test_end=$(date +%s.%N)
total_test_time=$(echo "$test_end - $test_start" | bc)

print_header "📈 LOAD TEST RESULTS"

# Analyze results
if [ -f /tmp/load_test_results.txt ]; then
    total_requests=$(wc -l < /tmp/load_test_results.txt)
    successful_requests=$(grep -c "SUCCESS" /tmp/load_test_results.txt)
    failed_requests=$(grep -c "FAILURE" /tmp/load_test_results.txt)
    
    success_rate=$(echo "scale=2; $successful_requests * 100 / $total_requests" | bc)
    
    # Calculate average response time
    avg_response_time=$(grep "SUCCESS" /tmp/load_test_results.txt | cut -d':' -f2 | \
        awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 0}')
    
    # Calculate requests per second
    rps=$(echo "scale=2; $total_requests / $total_test_time" | bc)
    
    print_success "Load test completed!"
    echo ""
    echo "📊 Summary Statistics:"
    echo "  Total requests sent: $total_requests"
    echo "  Successful requests: $successful_requests"
    echo "  Failed requests: $failed_requests"
    echo "  Success rate: ${success_rate}%"
    echo "  Average response time: ${avg_response_time}s"
    echo "  Total test time: ${total_test_time}s"
    echo "  Requests per second: $rps"
    
    print_info "Key Observations for Serverless Auto-Scaling:"
    echo "✅ Lambda functions automatically scale to handle concurrent requests"
    echo "✅ No need to provision or manage servers"
    echo "✅ Pay only for actual compute time used"
    echo "✅ Built-in fault tolerance and error handling"
    
    if (( $(echo "$success_rate > 95" | bc -l) )); then
        print_success "Excellent success rate! Serverless architecture handled the load well."
    elif (( $(echo "$success_rate > 90" | bc -l) )); then
        print_warning "Good success rate. Some requests may have experienced cold starts."
    else
        print_warning "Lower success rate. Consider investigating errors or scaling limits."
    fi
    
    # Clean up
    rm -f /tmp/load_test_results.txt
    
else
    echo -e "${RED}❌ No results file found. Load test may have failed.${NC}"
    exit 1
fi

print_header "🔍 MONITORING RECOMMENDATIONS"
print_info "During and after the load test, check these metrics in AWS CloudWatch:"
echo "  - Lambda Invocations: See how functions scaled"
echo "  - Lambda Duration: Monitor performance under load"
echo "  - Lambda Errors: Check for any failures"
echo "  - Lambda Throttles: Monitor if concurrent execution limits were hit"
echo "  - API Gateway 4XXError/5XXError: Check API-level errors"
echo "  - DynamoDB ConsumedReadCapacityUnits/ConsumedWriteCapacityUnits"

print_info "CloudWatch Dashboard URLs:"
echo "  - Lambda: https://console.aws.amazon.com/lambda/home#/functions"
echo "  - API Gateway: https://console.aws.amazon.com/apigateway/home#/apis"
echo "  - DynamoDB: https://console.aws.amazon.com/dynamodb/home#tables"

echo -e "\n${GREEN}🎯 Load test completed! Check AWS CloudWatch for detailed metrics.${NC}"
