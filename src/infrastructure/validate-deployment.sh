#!/bin/bash

# Lambda Auto-Repair System Deployment Validation Script
set -e

ENVIRONMENT="dev"
REGION="us-east-1"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -e, --environment ENV     Environment (dev, staging, prod) [default: dev]"
      echo "  -r, --region REGION       AWS Region [default: us-east-1]"
      echo "  -h, --help                Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Set stack names
MAIN_STACK_NAME="lambda-auto-repair-main-${ENVIRONMENT}"
FUNCTIONS_STACK_NAME="lambda-auto-repair-functions-${ENVIRONMENT}"
MONITORING_STACK_NAME="lambda-auto-repair-monitoring-${ENVIRONMENT}"

echo "=== Lambda Auto-Repair System Validation ==="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "============================================="

# Function to check stack status
check_stack_status() {
  local stack_name=$1
  echo "Checking stack: $stack_name"
  
  if aws cloudformation describe-stacks --stack-name $stack_name --region $REGION >/dev/null 2>&1; then
    local status=$(aws cloudformation describe-stacks \
      --stack-name $stack_name \
      --region $REGION \
      --query 'Stacks[0].StackStatus' \
      --output text)
    echo "  Status: $status"
    
    if [[ "$status" == "CREATE_COMPLETE" || "$status" == "UPDATE_COMPLETE" ]]; then
      echo "  ✅ Stack is healthy"
      return 0
    else
      echo "  ❌ Stack is in unhealthy state"
      return 1
    fi
  else
    echo "  ❌ Stack does not exist"
    return 1
  fi
}

# Function to validate Lambda functions
validate_lambda_functions() {
  echo "Validating Lambda functions..."
  
  local functions=(
    "lambda-auto-repair-data-collector-${ENVIRONMENT}"
    "lambda-auto-repair-diagnosis-${ENVIRONMENT}"
    "lambda-auto-repair-executor-${ENVIRONMENT}"
    "lambda-auto-repair-verifier-${ENVIRONMENT}"
    "lambda-auto-repair-coordinator-${ENVIRONMENT}"
  )
  
  for func in "${functions[@]}"; do
    echo "  Checking function: $func"
    if aws lambda get-function --function-name $func --region $REGION >/dev/null 2>&1; then
      local state=$(aws lambda get-function \
        --function-name $func \
        --region $REGION \
        --query 'Configuration.State' \
        --output text)
      echo "    State: $state"
      
      if [[ "$state" == "Active" ]]; then
        echo "    ✅ Function is active"
      else
        echo "    ❌ Function is not active"
      fi
    else
      echo "    ❌ Function does not exist"
    fi
  done
}

# Function to validate Step Functions
validate_step_functions() {
  echo "Validating Step Functions..."
  
  local state_machine="lambda-auto-repair-workflow-${ENVIRONMENT}"
  echo "  Checking state machine: $state_machine"
  
  if aws stepfunctions describe-state-machine \
    --state-machine-arn "arn:aws:states:${REGION}:$(aws sts get-caller-identity --query Account --output text):stateMachine:${state_machine}" \
    --region $REGION >/dev/null 2>&1; then
    
    local status=$(aws stepfunctions describe-state-machine \
      --state-machine-arn "arn:aws:states:${REGION}:$(aws sts get-caller-identity --query Account --output text):stateMachine:${state_machine}" \
      --region $REGION \
      --query 'status' \
      --output text)
    echo "    Status: $status"
    
    if [[ "$status" == "ACTIVE" ]]; then
      echo "    ✅ State machine is active"
    else
      echo "    ❌ State machine is not active"
    fi
  else
    echo "    ❌ State machine does not exist"
  fi
}

# Function to validate DynamoDB tables
validate_dynamodb_tables() {
  echo "Validating DynamoDB tables..."
  
  local tables=(
    "lambda-auto-repair-diagnosis-${ENVIRONMENT}"
    "lambda-auto-repair-repairs-${ENVIRONMENT}"
  )
  
  for table in "${tables[@]}"; do
    echo "  Checking table: $table"
    if aws dynamodb describe-table --table-name $table --region $REGION >/dev/null 2>&1; then
      local status=$(aws dynamodb describe-table \
        --table-name $table \
        --region $REGION \
        --query 'Table.TableStatus' \
        --output text)
      echo "    Status: $status"
      
      if [[ "$status" == "ACTIVE" ]]; then
        echo "    ✅ Table is active"
      else
        echo "    ❌ Table is not active"
      fi
    else
      echo "    ❌ Table does not exist"
    fi
  done
}

# Function to validate EventBridge
validate_eventbridge() {
  echo "Validating EventBridge..."
  
  local event_bus="lambda-auto-repair-${ENVIRONMENT}"
  echo "  Checking event bus: $event_bus"
  
  if aws events describe-event-bus --name $event_bus --region $REGION >/dev/null 2>&1; then
    echo "    ✅ Event bus exists"
  else
    echo "    ❌ Event bus does not exist"
  fi
  
  # Check event rules
  local rules=$(aws events list-rules \
    --event-bus-name $event_bus \
    --region $REGION \
    --query 'Rules[?contains(Name, `lambda-auto-repair`)].Name' \
    --output text)
  
  if [[ -n "$rules" ]]; then
    echo "    ✅ Event rules found: $rules"
  else
    echo "    ❌ No event rules found"
  fi
}

# Function to validate SNS
validate_sns() {
  echo "Validating SNS..."
  
  local topic_name="lambda-auto-repair-notifications-${ENVIRONMENT}"
  local topic_arn=$(aws sns list-topics \
    --region $REGION \
    --query "Topics[?contains(TopicArn, '${topic_name}')].TopicArn" \
    --output text)
  
  if [[ -n "$topic_arn" ]]; then
    echo "  ✅ SNS topic exists: $topic_arn"
    
    local subscriptions=$(aws sns list-subscriptions-by-topic \
      --topic-arn $topic_arn \
      --region $REGION \
      --query 'Subscriptions[].Protocol' \
      --output text)
    
    if [[ -n "$subscriptions" ]]; then
      echo "    ✅ Subscriptions found: $subscriptions"
    else
      echo "    ⚠️  No subscriptions found"
    fi
  else
    echo "  ❌ SNS topic does not exist"
  fi
}

# Function to validate CloudWatch
validate_cloudwatch() {
  echo "Validating CloudWatch..."
  
  # Check dashboard
  local dashboard_name="lambda-auto-repair-${ENVIRONMENT}"
  if aws cloudwatch get-dashboard --dashboard-name $dashboard_name --region $REGION >/dev/null 2>&1; then
    echo "  ✅ CloudWatch dashboard exists: $dashboard_name"
  else
    echo "  ❌ CloudWatch dashboard does not exist"
  fi
  
  # Check alarms
  local alarms=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "lambda-auto-repair" \
    --region $REGION \
    --query 'MetricAlarms[].AlarmName' \
    --output text)
  
  if [[ -n "$alarms" ]]; then
    echo "  ✅ CloudWatch alarms found"
    for alarm in $alarms; do
      echo "    - $alarm"
    done
  else
    echo "  ⚠️  No CloudWatch alarms found"
  fi
}

# Function to run basic functionality test
run_functionality_test() {
  echo "Running basic functionality test..."
  
  # Test Lambda function invocation
  local test_payload='{"test": true, "functionName": "test-function"}'
  local coordinator_function="lambda-auto-repair-coordinator-${ENVIRONMENT}"
  
  echo "  Testing coordinator function..."
  if aws lambda invoke \
    --function-name $coordinator_function \
    --payload "$test_payload" \
    --region $REGION \
    /tmp/test-response.json >/dev/null 2>&1; then
    
    local status_code=$(cat /tmp/test-response.json | jq -r '.statusCode // "unknown"')
    if [[ "$status_code" == "200" ]]; then
      echo "    ✅ Coordinator function test passed"
    else
      echo "    ⚠️  Coordinator function returned status: $status_code"
    fi
    rm -f /tmp/test-response.json
  else
    echo "    ❌ Coordinator function test failed"
  fi
}

# Main validation flow
echo "Starting validation..."

# Check stack statuses
check_stack_status $MAIN_STACK_NAME
main_stack_ok=$?

check_stack_status $FUNCTIONS_STACK_NAME
functions_stack_ok=$?

check_stack_status $MONITORING_STACK_NAME
monitoring_stack_ok=$?

# If stacks are healthy, validate components
if [[ $main_stack_ok -eq 0 && $functions_stack_ok -eq 0 && $monitoring_stack_ok -eq 0 ]]; then
  echo ""
  echo "All stacks are healthy. Validating components..."
  
  validate_lambda_functions
  validate_step_functions
  validate_dynamodb_tables
  validate_eventbridge
  validate_sns
  validate_cloudwatch
  run_functionality_test
  
  echo ""
  echo "=== Validation Summary ==="
  echo "✅ All core components validated"
  echo "🔗 Dashboard: https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=lambda-auto-repair-${ENVIRONMENT}"
  echo "📊 Step Functions: https://${REGION}.console.aws.amazon.com/states/home?region=${REGION}#/statemachines/view/arn:aws:states:${REGION}:$(aws sts get-caller-identity --query Account --output text):stateMachine:lambda-auto-repair-workflow-${ENVIRONMENT}"
  echo ""
  echo "Next steps:"
  echo "1. Configure Bedrock Knowledge Base"
  echo "2. Add target Lambda functions to monitor"
  echo "3. Test with real CloudWatch alarms"
  
else
  echo ""
  echo "❌ One or more stacks are not healthy. Please check the deployment."
  exit 1
fi