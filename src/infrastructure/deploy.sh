#!/bin/bash

# Lambda Auto-Repair System Deployment Script
set -e

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
NOTIFICATION_EMAIL=""
ENABLE_APPROVAL="false"
KNOWLEDGE_BASE_ID=""
DRY_RUN="false"

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
    --email)
      NOTIFICATION_EMAIL="$2"
      shift 2
      ;;
    --enable-approval)
      ENABLE_APPROVAL="true"
      shift
      ;;
    --knowledge-base-id)
      KNOWLEDGE_BASE_ID="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -e, --environment ENV     Environment (dev, staging, prod) [default: dev]"
      echo "  -r, --region REGION       AWS Region [default: us-east-1]"
      echo "  --email EMAIL             Notification email address"
      echo "  --enable-approval         Enable manual approval workflow"
      echo "  --knowledge-base-id ID    Bedrock Knowledge Base ID"
      echo "  --dry-run                 Validate templates without deploying"
      echo "  -h, --help                Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$NOTIFICATION_EMAIL" ]]; then
  echo "Error: Notification email is required. Use --email parameter."
  exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: Environment must be one of: dev, staging, prod"
  exit 1
fi

# Set stack names
MAIN_STACK_NAME="lambda-auto-repair-main-${ENVIRONMENT}"
FUNCTIONS_STACK_NAME="lambda-auto-repair-functions-${ENVIRONMENT}"
MONITORING_STACK_NAME="lambda-auto-repair-monitoring-${ENVIRONMENT}"

echo "=== Lambda Auto-Repair System Deployment ==="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Notification Email: $NOTIFICATION_EMAIL"
echo "Enable Approval: $ENABLE_APPROVAL"
echo "Knowledge Base ID: $KNOWLEDGE_BASE_ID"
echo "Dry Run: $DRY_RUN"
echo "============================================="

# Function to validate CloudFormation template
validate_template() {
  local template_file=$1
  echo "Validating template: $template_file"
  aws cloudformation validate-template \
    --template-body file://$template_file \
    --region $REGION
}

# Function to deploy CloudFormation stack
deploy_stack() {
  local stack_name=$1
  local template_file=$2
  local parameters=$3
  
  echo "Deploying stack: $stack_name"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN: Would deploy $stack_name with template $template_file"
    return 0
  fi
  
  # Check if stack exists
  if aws cloudformation describe-stacks --stack-name $stack_name --region $REGION >/dev/null 2>&1; then
    echo "Stack $stack_name exists, updating..."
    aws cloudformation update-stack \
      --stack-name $stack_name \
      --template-body file://$template_file \
      --parameters $parameters \
      --capabilities CAPABILITY_NAMED_IAM \
      --region $REGION
    
    echo "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
      --stack-name $stack_name \
      --region $REGION
  else
    echo "Stack $stack_name does not exist, creating..."
    aws cloudformation create-stack \
      --stack-name $stack_name \
      --template-body file://$template_file \
      --parameters $parameters \
      --capabilities CAPABILITY_NAMED_IAM \
      --region $REGION
    
    echo "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete \
      --stack-name $stack_name \
      --region $REGION
  fi
  
  echo "Stack $stack_name deployed successfully!"
}

# Validate all templates
echo "Validating CloudFormation templates..."
validate_template "lambda-auto-repair-main.yaml"
validate_template "lambda-auto-repair-functions.yaml"
validate_template "lambda-auto-repair-monitoring.yaml"

# Deploy main infrastructure stack
echo "Deploying main infrastructure stack..."
MAIN_PARAMETERS="ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=NotificationEmail,ParameterValue=$NOTIFICATION_EMAIL ParameterKey=EnableApprovalWorkflow,ParameterValue=$ENABLE_APPROVAL"
deploy_stack $MAIN_STACK_NAME "lambda-auto-repair-main.yaml" "$MAIN_PARAMETERS"

# Deploy functions stack
echo "Deploying functions stack..."
FUNCTIONS_PARAMETERS="ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=MainStackName,ParameterValue=$MAIN_STACK_NAME"
if [[ -n "$KNOWLEDGE_BASE_ID" ]]; then
  FUNCTIONS_PARAMETERS="$FUNCTIONS_PARAMETERS ParameterKey=KnowledgeBaseId,ParameterValue=$KNOWLEDGE_BASE_ID"
fi
deploy_stack $FUNCTIONS_STACK_NAME "lambda-auto-repair-functions.yaml" "$FUNCTIONS_PARAMETERS"

# Deploy monitoring stack
echo "Deploying monitoring stack..."
MONITORING_PARAMETERS="ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=MainStackName,ParameterValue=$MAIN_STACK_NAME"
deploy_stack $MONITORING_STACK_NAME "lambda-auto-repair-monitoring.yaml" "$MONITORING_PARAMETERS"

if [[ "$DRY_RUN" == "false" ]]; then
  echo "=== Deployment Complete ==="
  echo "Main Stack: $MAIN_STACK_NAME"
  echo "Functions Stack: $FUNCTIONS_STACK_NAME"
  echo "Monitoring Stack: $MONITORING_STACK_NAME"
  echo ""
  echo "Next steps:"
  echo "1. Configure Bedrock Knowledge Base if not already done"
  echo "2. Add Lambda functions to monitor using the monitoring template"
  echo "3. Test the system with a sample alarm"
  echo "4. Review CloudWatch Dashboard: https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=lambda-auto-repair-${ENVIRONMENT}"
else
  echo "=== Dry Run Complete ==="
  echo "All templates validated successfully!"
fi